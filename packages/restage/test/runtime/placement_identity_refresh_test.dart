import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/delivery/surface_artifact_store.dart';
import 'package:restage/src/refresh/surface_refresh_registry.dart';
import 'package:restage/src/resolver/surface_delivery_observations.dart';
import 'package:restage/src/resolver/surface_metering_key_provider.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage/src/surface_screen/restage_surface_screen.dart'
    show debugLiveScreenStages;
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    show DeliveryPolicyScopeV1;
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart' hide WidgetLibrary;
import 'package:rfw/rfw.dart' show RemoteWidget, Runtime;
import 'package:shared_preferences/shared_preferences.dart';

import '../support/debug_print_capture.dart';
import '../support/placement_delivery_fixture.dart';
import '../support/sent_placement_request.dart';
import '../surface_screen/surface_screen_test_support.dart';

const _close = SurfaceEvent<void>('close');

BlobSurfacePayload _payload(String text, {bool broken = false}) =>
    BlobSurfacePayload(
      minClient: 1,
      blob: Uint8List.fromList(
        encodeLibraryBlob(
          parseLibraryFile('''
      import restage.core;
      import app.islands;
      widget OnboardingScreen = Column(children: [
        Text(text: "$text"),
        ${broken ? 'Broken()' : 'Keep()'},
      ]);
    '''),
        ),
      ),
    );

Widget _keep(BuildContext context, DataSource source) =>
    RestageIslandScope.build('Keep', 'missing', context, source);

Widget _broken(BuildContext context, DataSource source) => const _Throwing();

final class _Throwing extends StatelessWidget {
  const _Throwing();

  @override
  Widget build(BuildContext context) => throw StateError('render failed');
}

const _islands = RestageWidgetLibraryRegistration.constant(
  library: WidgetLibrary.custom('app.islands'),
  widgets: [
    RestageWidgetFactory(name: 'Keep', builder: _keep),
    RestageWidgetFactory(name: 'Broken', builder: _broken),
  ],
  islands: true,
);

const _watchToken =
    'v2.i5p7lxR3.1767229200.NDI6b25ib2FyZGluZzp3ZWxjb21lLWZsb3c.'
    'kV0gFtXCrtsWdYcIFXaVNEQDQFjXwvrEn4t_WY_KX44';

final class _Channel implements DeliveryUpdateChannel {
  final watched = <CanonicalDigest>[];

  @override
  Stream<SurfaceUpdate> watch(SurfaceRef surface) => const Stream.empty();

  @override
  Stream<DeliveryPolicyScopeV1> watchDelivery(
    DeliveryPolicyScopeV1 scope, {
    PlacementDeliveryWatchV1? watch,
    Future<PlacementRefreshProbeV1> Function()? reconnectProbe,
  }) {
    if (watch != null) watched.add(watch.decisionIdentityDigest);
    return StreamController<DeliveryPolicyScopeV1>().stream;
  }
}

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

// One hosted placement screen whose next answer the test sets.
final class _Harness {
  _Harness(this.tester);

  final WidgetTester tester;
  final channel = _Channel();
  final events = <String>[];
  var text = 'delivered';
  var digest = CanonicalDigest('a' * 64);
  var now = DateTime.utc(2026, 10, 4, 12);
  int? contentExpiresAtMicros;
  // The next answer's content throws while building.
  var broken = false;
  // Every answer carries a receipt of its own, as a signing service's do.
  final receipts = <String>[];
  final resolutions = <SurfaceResolutionReport>[];
  var requests = 0;

  // Holds an answer until it completes; the answer is built after it.
  Future<void> Function(PlacementBatchRequestV1 request)? hold;

  Future<void> mount(
      {bool brokenOriginal = false, bool original = true}) async {
    Restage.debugReset();
    addTearDown(Restage.debugReset);
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'test',
      packageName: 'test',
      version: '1',
      buildNumber: '42',
      buildSignature: '',
    );
    debugResetAppBuildOrdinal();
    sharedSurfaceArtifactStore = MemorySurfaceArtifactStore();
    addTearDown(() => sharedSurfaceArtifactStore = null);
    final fixture = stringScreenFixture(
      slug: 'inner',
      schema: SurfaceScreenEventSchema(
        events: [
          SurfaceScreenEvent(
            id: 'close',
            arguments: const SurfaceScreenEventNoArguments(),
          ),
        ],
      ),
      vocabulary: const SurfaceVocabulary(libraries: [_islands]),
      blob: brokenOriginal ? rfwSourceBlob('''
import app.islands;
widget OnboardingScreen = Broken();
''') : null,
    );
    Restage.configure(
      apiKey: 'rs_pk_test',
      baseUrl: 'https://example.com',
      analyticsEnabled: false,
      measurementEnabled: false,
      deliveryReceiptsEnabled: false,
      updateChannel: channel,
      liveRefresh: const {SurfaceRefreshTrigger.updateChannel},
      onSurfaceResolution: resolutions.add,
    );
    const SurfaceVocabulary(libraries: [_islands]).addToInstalled();
    debugResetInstallObservations();
    debugSetOsVersion(19);
    SurfaceMeteringKeyProvider.clear();
    Restage.debugPlacementNow = () => now;
    // The screen's bundled original, which a local lapse stages.
    final bundle = fixture.bundleBytes();
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMessageHandler('flutter/assets', (message) async {
      if (!original ||
          const StringCodec().decodeMessage(message) !=
              fixture.locator.assetKey) {
        return null;
      }
      return ByteData.sublistView(bundle);
    });
    addTearDown(() => messenger.setMockMessageHandler('flutter/assets', null));
    final client = RestageRpcClient(
      baseUrl: 'https://example.com',
      apiKey: 'rs_pk_test',
      httpClient: MockClient((outgoing) async {
        final artifact = placementFixtureArtifact(outgoing);
        if (artifact != null) return artifact;
        if (!outgoing.url.path.endsWith('/placements/resolve')) {
          return http.Response('{}', 200);
        }
        requests++;
        final request = sentPlacementRequest(outgoing.bodyBytes);
        await hold?.call(request);
        final watched = digest;
        final receipt = 'routing-receipt-$requests';
        receipts.add(receipt);
        return http.Response.bytes(
          placementFixtureResponse(
            request,
            payload: _payload(text, broken: broken),
            cacheValidityOverrides: {
              if (contentExpiresAtMicros != null)
                'contentExpiresAtMicros': contentExpiresAtMicros,
            },
            family: DeliveryFamilySelectorV1.screenContract(contractVersion: 7),
            routingSelectionReceipt: receipt,
            watch: (delivery) => PlacementDeliveryWatchV1(
              decisionIdentityDigest: watched,
              channels: [
                for (final scope in delivery.dependencyClosure)
                  PlacementDeliveryWatchChannelV1(
                    scope: scope,
                    token: _watchToken,
                  ),
              ],
            ),
          ).canonicalBytes,
          200,
        );
      }),
    );
    addTearDown(client.close);
    Restage.debugRestageRpcClient = client;
    final definition = GeneratedPlacementDefinition(
      defaultSurface: fixture.ref,
      defaultSurfaceLocator: DeliverySurfaceLocatorV1(
        surfaceType: DeliverySurfaceTypeId('general'),
        slug: fixture.ref.slug,
        family: DeliveryFamilySelectorV1.screenContract(
          contractVersion: fixture.ref.contractVersion,
        ),
      ),
      key: PlacementKeyV1.generatedDefault(
        surfaceType: DeliverySurfaceTypeId('general'),
        slug: fixture.ref.slug,
      ),
      hostContract: readPlacementDeliveryFixture()
          .request
          .buildContract
          .contractsByHash
          .values
          .first,
      vocabulary: SurfaceVocabulary.none,
    );
    _app = () => MaterialApp(
          home: Builder(
            builder: (mount) {
              final recording = RestageRecording(owner: mount);
              final island = recording.island(
                'Keep',
                TextButton(
                  onPressed: recording.surfaceEvent(_close),
                  child: const Text('island close'),
                ),
              );
              final screen = RestageScreen<String>(
                screen: fixture.ref,
                placementBinding: RestageScreen.generatedPlacementBinding(
                  definition: () => definition,
                  eventOwner: mount,
                ),
                onEvent: events.add,
                fallbackBuilder: (_) => island,
              );
              return RestageIslandScope(
                owner: mount,
                builders: {
                  'Keep': (context, source) =>
                      recording.islandAt('Keep', const [], context, source),
                },
                // A transition that changes type remounts the screen, as one
                // that follows Reduce Motion does.
                child: fade
                    ? FadeTransition(
                        opacity: kAlwaysCompleteAnimation, child: screen)
                    : SlideTransition(
                        position: const AlwaysStoppedAnimation(Offset.zero),
                        child: screen),
              );
            },
          ),
        );
    await tester.pumpWidget(_app());
    await _frames(tester);
    expect(tester.takeException(), isNull);
    expect(find.text(text), findsOneWidget);
  }

  late Widget Function() _app;
  var fade = false;

  /// Remounts the screen by changing the transition around it.
  Future<void> remount() {
    fade = !fade;
    return tester.pumpWidget(_app());
  }

  Runtime get runtime =>
      tester.widget<RemoteWidget>(find.byType(RemoteWidget)).runtime;

  Future<void> refresh() async {
    final before = requests;
    await SurfaceRefreshRegistry.instance.reload();
    expect(requests, greaterThan(before));
  }

  Future<void> settle() async {
    await _frames(tester);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }
}

void main() {
  testWidgets(
    'a refresh that returns the same content under a new decision keeps the '
    'stage and its events, and watches the new decision',
    (tester) async {
      final harness = _Harness(tester);
      try {
        await harness.mount();
        final runtime = harness.runtime;
        expect(harness.channel.watched, contains(CanonicalDigest('a' * 64)));

        harness.digest = CanonicalDigest('b' * 64);
        await harness.refresh();
        await harness.settle();
        expect(
          harness.runtime,
          same(runtime),
          reason: 'the same content is not staged again',
        );
        expect(harness.channel.watched.last, CanonicalDigest('b' * 64));

        await tester.tap(find.text('island close'));
        await tester.pump();
        expect(harness.events, ['close']);
      } finally {
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  testWidgets(
    'a routing receipt minted for every answer does not stage the same '
    'content again',
    (tester) async {
      final harness = _Harness(tester);
      try {
        await harness.mount();
        final runtime = harness.runtime;
        final before = harness.receipts.length;

        harness.digest = CanonicalDigest('b' * 64);
        await harness.refresh();
        await harness.settle();
        expect(harness.receipts.length, greaterThan(before));
        expect(harness.receipts.toSet(), hasLength(harness.receipts.length));
        expect(harness.runtime, same(runtime));
        expect(harness.channel.watched.last, CanonicalDigest('b' * 64));
      } finally {
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  testWidgets(
      'a refresh that swaps a screen logs and reports it; the same content '
      'does neither', (tester) async {
    final harness = _Harness(tester);
    try {
      await harness.mount();
      final logs = await captureRestageLogs(() async {
        harness.digest = CanonicalDigest('b' * 64);
        await harness.refresh();
        await harness.settle();
        harness
          ..text = 'newer'
          ..digest = CanonicalDigest('c' * 64);
        await harness.refresh();
        await harness.settle();
      });

      expect(find.text('newer'), findsOneWidget);
      expect([
        for (final report in harness.resolutions) report.source
      ], [
        SurfaceResolutionSource.fresh,
        SurfaceResolutionSource.fresh,
      ]);
      expect(logs, hasLength(1));
      expect(logs.single,
          '[restage] live refresh: general "welcome" now shows r9.');
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets(
      'a remount shows the content its predecessor showed from its first '
      'frame, and fresh answers under the usual rules', (tester) async {
    final harness = _Harness(tester);
    try {
      await harness.mount();
      // An app that lists its surfaces reads its saved decisions at configure.
      Restage.placementRegistry!.warmSaved();
      await harness.settle();
      final before = harness.requests;
      harness.text = 'newer';
      harness.digest = CanonicalDigest('b' * 64);

      await harness.remount();
      expect(find.text('delivered'), findsOneWidget, reason: 'first frame');
      for (var frame = 0; frame < 5; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.text('delivered'), findsOneWidget, reason: 'frame $frame');
      }
      await harness.settle();
      expect(harness.requests, greaterThan(before));
      // A late answer is kept for the next mount, as after any held decision.
      expect(find.text('delivered'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets(
      'a refresh while newer content waits for its first paint stages the '
      'latest answer, and the screen stays consistent', (tester) async {
    final harness = _Harness(tester);
    try {
      await harness.mount();
      final first = harness.runtime;

      // New content is staged and has not painted yet.
      harness
        ..text = 'newer'
        ..digest = CanonicalDigest('b' * 64);
      await harness.refresh();
      // The first content comes back under another decision meanwhile.
      harness
        ..text = 'delivered'
        ..digest = CanonicalDigest('c' * 64);
      await harness.refresh();
      await harness.settle();
      // The latest answer replaced the pending stage rather than keeping one.
      expect(harness.runtime, isNot(same(first)));
      expect(find.text('delivered'), findsOneWidget);
      expect(harness.channel.watched.last, CanonicalDigest('c' * 64));

      // What shows is what is accepted: the same content keeps its stage.
      final runtime = harness.runtime;
      harness.digest = CanonicalDigest('d' * 64);
      await harness.refresh();
      await harness.settle();
      expect(harness.runtime, same(runtime));
      expect(harness.channel.watched.last, CanonicalDigest('d' * 64));
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
    // The stage the second answer displaced was disposed with the others.
    await _frames(tester);
    expect(debugLiveScreenStages, 0);
  });

  testWidgets(
      'keep under a new decision, then a replacement: the watch follows the '
      "replacement's decision", (tester) async {
    final harness = _Harness(tester);
    try {
      await harness.mount();
      final runtime = harness.runtime;
      harness.digest = CanonicalDigest('b' * 64);
      await harness.refresh();
      await harness.settle();
      expect(harness.runtime, same(runtime));
      expect(harness.channel.watched.last, CanonicalDigest('b' * 64));

      harness
        ..text = 'newer'
        ..digest = CanonicalDigest('c' * 64);
      await harness.refresh();
      await harness.settle();
      expect(find.text('newer'), findsOneWidget);
      expect(harness.runtime, isNot(same(runtime)));
      expect(harness.channel.watched.last, CanonicalDigest('c' * 64));
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets(
      'a refresh that finds nothing new while newer content waits for its '
      'first paint keeps the shown content on screen', (tester) async {
    final harness = _Harness(tester);
    final live = debugLiveScreenStages;
    try {
      await harness.mount();

      // New content is staged and has not painted yet.
      harness
        ..text = 'newer'
        ..digest = CanonicalDigest('b' * 64);
      await harness.refresh();

      // The next refresh's answer is held while frames run, then returns
      // what is already accepted.
      final gate = Completer<void>();
      harness.hold = (request) async {
        if (request.mode != PlacementBatchModeV1.refresh) await gate.future;
      };
      final refreshing = SurfaceRefreshRegistry.instance.reload();
      await _frames(tester);
      harness
        ..text = 'delivered'
        ..digest = CanonicalDigest('a' * 64);
      gate.complete();
      await refreshing;
      await harness.settle();
      expect(find.text('delivered').hitTestable(), findsOneWidget);
      // The restored stage is alive, and the refused one is gone.
      expect(debugLiveScreenStages, live + 1);
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets(
      'the original staged by a local lapse, then a same-content refresh under '
      'a new decision before it paints, shows the content', (tester) async {
    final harness = _Harness(tester);
    try {
      await harness.mount();
      harness
        ..now = DateTime.utc(2026, 10, 4, 11)
        ..digest = CanonicalDigest('b' * 64);
      await SurfaceRefreshRegistry.instance.checkLocalValidity();
      // No frame runs: the original is staged but has not painted.
      await harness.refresh();
      await harness.settle();
      expect(find.text('delivered').hitTestable(), findsOneWidget);
      expect(find.text('Bundled screen'), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets(
      'a refresh that finds nothing new while the original from a local lapse '
      'waits for its first paint keeps the shown content on screen',
      (tester) async {
    final harness = _Harness(tester);
    try {
      await harness.mount();
      harness
        ..now = DateTime.utc(2026, 10, 4, 11)
        ..digest = CanonicalDigest('b' * 64);
      await SurfaceRefreshRegistry.instance.checkLocalValidity();

      // The refresh's answer is held while frames run, then returns what is
      // already accepted.
      final gate = Completer<void>();
      harness.hold = (request) async {
        if (request.mode != PlacementBatchModeV1.refresh) await gate.future;
      };
      final refreshing = SurfaceRefreshRegistry.instance.reload();
      await _frames(tester);
      harness.digest = CanonicalDigest('a' * 64);
      gate.complete();
      await refreshing;
      await harness.settle();
      // The accepted decision lapsed, so the original shows, not it.
      expect(find.text('Bundled screen').hitTestable(), findsOneWidget);
      expect(find.text('delivered'), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets(
      'a refresh under a new decision after the shown decision lapsed stages '
      'the content again', (tester) async {
    final harness = _Harness(tester);
    try {
      await harness.mount();
      final runtime = harness.runtime;
      // The clock moved back, so the shown decision no longer holds.
      harness
        ..now = DateTime.utc(2026, 10, 4, 11)
        ..digest = CanonicalDigest('b' * 64);
      await harness.refresh();
      await harness.settle();
      expect(find.text('delivered').hitTestable(), findsOneWidget);
      expect(harness.runtime, isNot(same(runtime)));
      expect(harness.channel.watched.last, CanonicalDigest('b' * 64));
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets(
      'expired content whose original is refused at paint gives way to the '
      'original, and stays replaced', (tester) async {
    final harness = _Harness(tester)
      ..contentExpiresAtMicros =
          DateTime.utc(2026, 10, 4, 12, 30).microsecondsSinceEpoch;
    try {
      await harness.mount();
      // The content's validity ends; the local check stages the original.
      harness.now = DateTime.utc(2026, 10, 4, 13);
      await SurfaceRefreshRegistry.instance.checkLocalValidity();
      // A refresh starts before that paint and finds nothing it can show.
      final gate = Completer<void>();
      harness
        ..digest = CanonicalDigest('b' * 64)
        ..hold = (request) async {
          if (request.mode != PlacementBatchModeV1.refresh) await gate.future;
        };
      final refreshing = SurfaceRefreshRegistry.instance.reload();
      await _frames(tester);
      gate.complete();
      await refreshing;
      await harness.settle();
      expect(find.text('Bundled screen').hitTestable(), findsOneWidget);
      expect(find.text('delivered'), findsNothing);

      harness.hold = null;
      await SurfaceRefreshRegistry.instance.checkLocalValidity();
      await harness.settle();
      expect(find.text('Bundled screen').hitTestable(), findsOneWidget);
      expect(find.text('delivered'), findsNothing);

      // The mount still refreshes.
      await harness.refresh();
      await harness.settle();
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('the stage a committed replacement displaced is disposed',
      (tester) async {
    final harness = _Harness(tester)
      ..contentExpiresAtMicros =
          DateTime.utc(2026, 10, 4, 12, 30).microsecondsSinceEpoch;
    final live = debugLiveScreenStages;
    try {
      await harness.mount();
      harness.now = DateTime.utc(2026, 10, 4, 13);
      await SurfaceRefreshRegistry.instance.checkLocalValidity();
      await harness.settle();
      expect(find.text('Bundled screen'), findsOneWidget);
      expect(debugLiveScreenStages, live + 1);
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets(
      'content that fails while building restores the accepted stage while '
      'its decision holds', (tester) async {
    final harness = _Harness(tester);
    try {
      await harness.mount();
      final runtime = harness.runtime;
      harness
        ..text = 'newer'
        ..digest = CanonicalDigest('b' * 64)
        ..broken = true;
      await harness.refresh();
      await _frames(tester);
      expect(tester.takeException(), isNotNull);
      await harness.settle();
      expect(find.text('delivered').hitTestable(), findsOneWidget);
      expect(harness.runtime, same(runtime));
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets(
      'an original that fails while building after a lapse shows the '
      'fallback, and keeps the stored copy', (tester) async {
    final harness = _Harness(tester);
    try {
      await harness.mount(brokenOriginal: true);
      Future<int> stored() async => (await sharedSurfaceArtifactStore.keys())
          .where((key) => key.surfaceType == 'placementDecision')
          .length;
      final before = await tester.runAsync(stored) ?? 0;
      expect(before, greaterThan(0));
      // The clock moved back, so the shown decision no longer holds.
      harness.now = DateTime.utc(2026, 10, 4, 11);
      await SurfaceRefreshRegistry.instance.checkLocalValidity();
      await _frames(tester);
      expect(tester.takeException(), isNotNull);
      await harness.settle();
      expect(find.text('delivered'), findsNothing);
      expect(find.text('island close').hitTestable(), findsOneWidget);
      await _frames(tester);
      expect(await tester.runAsync(stored), before);

      // The mount still refreshes, also when reloaded by its own id.
      final requests = harness.requests;
      await Restage.reloadSurfaces(surfaceId: 'inner');
      expect(harness.requests, greaterThan(requests));
      await harness.settle();
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets(
      'a refresh staged while the original from a lapse waits, then refused '
      'after the decision holds again, restores the live accepted stage',
      (tester) async {
    final harness = _Harness(tester);
    try {
      await harness.mount();
      final runtime = harness.runtime;
      // A lapse stages the original; the decision then holds again.
      harness.now = DateTime.utc(2026, 10, 4, 11);
      await SurfaceRefreshRegistry.instance.checkLocalValidity();
      harness.now = DateTime.utc(2026, 10, 4, 12);
      // New content is staged before the original paints.
      harness
        ..text = 'newer'
        ..digest = CanonicalDigest('b' * 64);
      await harness.refresh();
      // A further refresh refuses it, then finds nothing new.
      final gate = Completer<void>();
      harness.hold = (request) async {
        if (request.mode != PlacementBatchModeV1.refresh) await gate.future;
      };
      final refreshing = SurfaceRefreshRegistry.instance.reload();
      await _frames(tester);
      harness
        ..text = 'delivered'
        ..digest = CanonicalDigest('a' * 64);
      gate.complete();
      await refreshing;
      await harness.settle();
      expect(find.text('delivered').hitTestable(), findsOneWidget);
      expect(harness.runtime, same(runtime));
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets(
      'a lapse on a mount with no bundled original shows the fallback, and '
      'the mount still refreshes', (tester) async {
    final harness = _Harness(tester);
    try {
      await harness.mount(original: false);
      harness.now = DateTime.utc(2026, 10, 4, 11);
      await SurfaceRefreshRegistry.instance.checkLocalValidity();
      await harness.settle();
      expect(find.text('island close').hitTestable(), findsOneWidget);
      harness.now = DateTime.utc(2026, 10, 4, 12);
      await harness.refresh();
      await harness.settle();
      expect(find.text('delivered').hitTestable(), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
  });
}
