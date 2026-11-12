import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:restage/restage.dart';
import 'package:restage/src/resolver/resolved_paywall_payload.dart';
import 'package:restage/src/runtime/builtin_catalog_capabilities.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart' hide WidgetLibrary;
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/compiled_surfaces/native_flow.dart';
import '../flow/flow_test_support.dart'
    show registerThrowingWidget, throwingResolvedFlow, throwingScreenBlob;
import '../support/hosted_artifact_delivery.dart';

/// A delivered baseline paywall is at or below the installed built-in catalog
/// version; using it keeps these fixtures renderable on this build (the
/// resolvers reject anything above the installed ceiling).
const int _renderableMinClient =
    RestageBuiltInCatalogCapabilities.currentVersion;

// ---------------------------------------------------------------------------
// Flow-hosting integration tests for RestagePaywall.
//
// A paywall whose handler called Navigator.push is lowered (at build time) to a
// 2-screen flow: an entry paywall screen that pushes a "plans" paywall screen,
// plus a skip -> end terminator. These tests drive and verify the runtime half:
// navigation follows the graph, custom events remain paywall-keyed, and
// reserved commerce events are inert.
// ---------------------------------------------------------------------------

/// A flow screen blob whose root is `OnboardingScreen` (what the flow view
/// renders), with one tappable label per (label -> event).
Uint8List _screenBlob(Map<String, String> labelToEvent) {
  // Each label is a tall, full-width, centered tap target, with the content
  // pushed below the flow chrome (a pushed flow screen shows a top-start back
  // chevron), so the labels are reliably hit-testable in the widget test.
  final buttons = labelToEvent.entries
      .map(
        (e) => 'SizedBox(height: 100.0, child: GestureDetector('
            "onTap: event '${e.value}' { slot: \"primary\" }, "
            'child: Center(child: Text(text: "${e.key}"))))',
      )
      .join(',\n');
  final source = '''
    import restage.core;
    widget OnboardingScreen = Column(children: [
      SizedBox(height: 96.0),
      $buttons
    ]);
  ''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

Uint8List _contextScreenBlob({String marker = ''}) {
  final source = '''
    import restage.core;
    widget OnboardingScreen = Column(children: [
      Text(text: data.context.label),
      Text(text: "$marker")
    ]);
  ''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

/// Builds the lowered 2-screen flow document: entry (pushes "plans" via
/// restageNav0, dismisses via skip) -> plans (a pushed paywall, on:{}).
FlowDocument _navFlowDocument({
  required Uint8List entryBytes,
  required Uint8List plansBytes,
}) {
  return FlowDocument(
    flow: 'pro_upgrade',
    version: 1,
    schemaVersion: 1,
    minClient: _renderableMinClient,
    initial: 'entry',
    actions: const {},
    screenArtifacts: {
      'entry': ScreenArtifact(
        path: 'paywall_pro_upgrade.rfw',
        version: 1,
        schemaVersion: 1,
        minClient: _renderableMinClient,
        contentHash: FlowContentHash.compute(entryBytes),
      ),
      'plans': ScreenArtifact(
        path: 'paywall_pro_upgrade_plans.rfw',
        version: 1,
        schemaVersion: 1,
        minClient: _renderableMinClient,
        contentHash: FlowContentHash.compute(plansBytes),
      ),
    },
    states: {
      'entry': const ScreenFlowState(
        screen: 'entry',
        on: {
          'restageNav0': FlowTransition.goto('plans'),
          'skip': FlowTransition.goto('done'),
        },
      ),
      'plans': const ScreenFlowState(screen: 'plans', on: {}),
      'done': const EndFlowState(result: {}),
    },
  );
}

/// An in-memory bundle serving the flow JSON + its screen blobs.
final class _FlowAssetBundle extends CachingAssetBundle {
  final Map<String, Uint8List> _assets = {};

  void writeFlow(String id, FlowDocument document) {
    _assets['assets/paywalls/$id.flow.json'] = Uint8List.fromList(
      utf8.encode(FlowDocumentCodec.encodePrettyJson(document)),
    );
  }

  void writeScreen(String path, Uint8List bytes) {
    _assets['assets/paywalls/screens/$path'] = Uint8List.fromList(bytes);
  }

  void writeLegacyScreen(String path, Uint8List bytes) {
    _assets['assets/onboarding/screens/$path'] = Uint8List.fromList(bytes);
  }

  @override
  Future<ByteData> load(String key) async {
    final bytes = _assets[key];
    if (bytes == null) throw FlutterError('Unable to load asset: $key');
    return ByteData.view(Uint8List.fromList(bytes).buffer);
  }
}

/// Assembles the resolver for the lowered nav paywall.
VariantResolver _navPaywallResolver() {
  final entry = _screenBlob({'See plans': 'restageNav0', 'No thanks': 'skip'});
  final plans = _screenBlob({'Buy': 'restage.purchase'});
  final bundle = _FlowAssetBundle()
    ..writeFlow(
        'pro_upgrade', _navFlowDocument(entryBytes: entry, plansBytes: plans))
    ..writeScreen('paywall_pro_upgrade.rfw', entry)
    ..writeScreen('paywall_pro_upgrade_plans.rfw', plans);
  return AssetVariantResolver(bundle: bundle);
}

VariantResolver _legacyNavPaywallResolver() {
  final entry = _screenBlob({'See plans': 'restageNav0', 'No thanks': 'skip'});
  final plans = _screenBlob({'Buy': 'restage.purchase'});
  final bundle = _FlowAssetBundle()
    ..writeFlow(
        'pro_upgrade', _navFlowDocument(entryBytes: entry, plansBytes: plans))
    ..writeLegacyScreen('paywall_pro_upgrade.rfw', entry)
    ..writeLegacyScreen('paywall_pro_upgrade_plans.rfw', plans);
  return AssetVariantResolver(bundle: bundle);
}

/// A flow-capable resolver that resolves a flow payload once, then fails — to
/// drive the cache-fallback re-host path on a remount.
class _SeqFlowResolver implements VariantResolver, FlowCapableVariantResolver {
  _SeqFlowResolver(this._flow, {this.resolvedFromActiveArm = false});
  final ResolvedFlow _flow;
  final bool resolvedFromActiveArm;
  int _calls = 0;

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async =>
      throw UnimplementedError();

  @override
  Future<ResolvedPaywallPayload> resolvePayload(
    String id, {
    String? placementId,
    Locale? locale,
  }) async {
    if (_calls++ == 0) {
      return FlowPaywallPayload(
        flow: _flow,
        paywallId: id,
        resolvedFromActiveArm: resolvedFromActiveArm,
      );
    }
    throw const RestagePaywallError(
      code: RestageErrorCodes.deliveryUnavailable,
      message: 'fresh resolve failed',
    );
  }
}

/// A flow-capable resolver returning a pre-resolved hosted flow payload with a
/// served version.
class _PublishedFlowResolver
    implements VariantResolver, FlowCapableVariantResolver {
  _PublishedFlowResolver({this.publishedVersion});
  final int? publishedVersion;

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async =>
      throw UnimplementedError();

  @override
  Future<ResolvedPaywallPayload> resolvePayload(
    String id, {
    String? placementId,
    Locale? locale,
  }) async =>
      FlowPaywallPayload(
        flow: _navResolvedFlow(),
        paywallId: id,
        paywallPublishedVersion: publishedVersion,
      );
}

/// A flow-capable resolver whose every payload response stays under explicit
/// test control.
/// Reloads surfaces and answers any refetch with a candidate design.
Future<void> _refreshWithCandidate(
    WidgetTester tester, _ControlledFlowPayloadResolver resolver) async {
  final refresh = Restage.reloadSurfaces();
  await tester.pump();
  for (final response in resolver.responses.skip(1)) {
    response.complete(FlowPaywallPayload(
      flow: _navResolvedFlowOf(_armedEntryBlob(const {}, label: 'Candidate'),
          _screenBlob({'Back': 'back'})),
      paywallId: 'pro_upgrade',
    ));
  }
  await refresh;
  await tester.pumpAndSettle();
}

final class _ControlledFlowPayloadResolver
    implements VariantResolver, FlowCapableVariantResolver {
  final List<Completer<ResolvedPaywallPayload>> responses = [];

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async =>
      throw UnimplementedError();

  @override
  Future<ResolvedPaywallPayload> resolvePayload(
    String id, {
    String? placementId,
    Locale? locale,
  }) {
    final response = Completer<ResolvedPaywallPayload>();
    responses.add(response);
    return response.future;
  }
}

/// A flow-capable resolver that answers each fetch through [answer].
final class _AnswerResolver
    implements VariantResolver, FlowCapableVariantResolver {
  _AnswerResolver(this.answer);

  final Future<ResolvedPaywallPayload> Function(String id) answer;

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async =>
      throw UnimplementedError();

  @override
  Future<ResolvedPaywallPayload> resolvePayload(
    String id, {
    String? placementId,
    Locale? locale,
  }) =>
      answer(id);
}

/// A root flow whose initial state enters a child before any screen exists.
///
/// Paywall payloads are re-hosted through the already-resolved root artifact,
/// so the child lookup deterministically fails its flow-id contract. This
/// exercises the early root [FlowStarted] emitted before child resolution has
/// installed renderable content.
ResolvedFlow _initialSubFlowThatFailsBeforeScreen() {
  final childHash = FlowContentHash.compute(Uint8List.fromList(const [1]));
  final document = FlowDocument(
    flow: 'pro_upgrade',
    version: 1,
    schemaVersion: 1,
    minClient: _renderableMinClient,
    initial: 'child',
    actions: const {},
    screenArtifacts: const {},
    states: {
      'child': SubFlowState(
        flow: 'child_flow',
        version: 1,
        schemaVersion: 1,
        minClient: _renderableMinClient,
        contentHash: childHash,
        input: const {},
        onComplete: const [],
        defaultBranch: const FlowBranchTarget(target: 'done'),
      ),
      'done': const EndFlowState(result: {}),
    },
  );
  return ResolvedFlow(
    document: document,
    screenBlobs: const {},
    contentHash: FlowContentHash.compute(
      Uint8List.fromList(FlowDocumentCodec.encodeCanonicalJson(document)),
    ),
    cacheHit: false,
  );
}

ResolvedFlow _singleScreenResolvedFlow(String text) {
  return _singleScreenResolvedFlowFromBlob(_screenBlob({text: 'noop'}));
}

ResolvedFlow _contextSingleScreenResolvedFlow({String marker = ''}) {
  return _singleScreenResolvedFlowFromBlob(_contextScreenBlob(marker: marker));
}

ResolvedFlow _singleScreenResolvedFlowFromBlob(Uint8List screen) {
  return ResolvedFlow(
    document: FlowDocument(
      flow: 'pro_upgrade',
      version: 1,
      schemaVersion: 1,
      minClient: _renderableMinClient,
      initial: 'entry',
      actions: const {},
      screenArtifacts: {
        'entry': ScreenArtifact(
          path: 'entry.rfw',
          version: 1,
          schemaVersion: 1,
          minClient: _renderableMinClient,
          contentHash: FlowContentHash.compute(screen),
        ),
      },
      states: const {
        'entry': ScreenFlowState(screen: 'entry', on: {}),
      },
    ),
    screenBlobs: {'entry': screen},
    cacheHit: false,
  );
}

ResolvedFlow _navResolvedFlow() {
  final entry = _screenBlob({'See plans': 'restageNav0', 'No thanks': 'skip'});
  final plans = _screenBlob({'Buy': 'restage.purchase'});
  return ResolvedFlow(
    document: _navFlowDocument(entryBytes: entry, plansBytes: plans),
    screenBlobs: {'entry': entry, 'plans': plans},
    cacheHit: false,
  );
}

Future<void> _pumpFlowPaywall(
  WidgetTester tester, {
  String paywallId = 'pro_upgrade',
  void Function(RestageEvent)? onEvent,
  VariantResolver? resolver,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: RestagePaywall(
        id: paywallId,
        resolver: resolver ?? _navPaywallResolver(),
        onEvent: onEvent,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

const _armedLibrary = WidgetLibrary.custom('acme.armed');

/// Builds an empty box, or throws once [armed]; it reads the view size, so a
/// resize rebuilds it.
final class _ArmedThrow extends StatelessWidget {
  const _ArmedThrow();

  static bool armed = false;

  @override
  Widget build(BuildContext context) {
    MediaQuery.sizeOf(context);
    if (armed) throw StateError('armed');
    return const SizedBox.shrink();
  }
}

/// View-pairing lifecycle labels.
List<String> _views(List<RestageEvent> events) => [
      for (final event in events)
        if (event is PaywallViewed)
          'viewed'
        else if (event is PaywallDismissed)
          'dismissed ${event.reason.name}'
        else if (event is PaywallLoadCompleted)
          'loadCompleted'
        else if (event is PaywallLoadFailed)
          'loadFailed',
    ];

/// An entry screen labelled [label], with one tap target per entry of
/// [labelToEvent], that holds an [_ArmedThrow].
Uint8List _armedEntryBlob(Map<String, String> labelToEvent,
    {String label = 'Entry'}) {
  final buttons = [
    for (final entry in labelToEvent.entries)
      'SizedBox(height: 100.0, child: GestureDetector('
          "onTap: event '${entry.value}' { }, "
          'child: Center(child: Text(text: "${entry.key}")))),',
  ].join('\n');
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile('''
    import restage.core;
    import acme.armed;
    widget OnboardingScreen = Column(children: [
      SizedBox(height: 96.0),
      Text(text: "$label"),
      $buttons
      ArmedThrow(),
    ]);
  ''')));
}

/// Makes the shown [_ArmedThrow] throw on a rebuild driven by a resize.
Future<void> _throwOnRebuild(WidgetTester tester) async {
  _ArmedThrow.armed = true;
  tester.view.physicalSize = const Size(1000, 700);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpAndSettle();
}

_FlowAssetBundle _navBundle(Uint8List entry, Uint8List plans) =>
    _FlowAssetBundle()
      ..writeFlow(
        'native_offer',
        _navFlowDocument(entryBytes: entry, plansBytes: plans)
            .copyWith(flow: 'native_offer'),
      )
      ..writeScreen('paywall_pro_upgrade.rfw', entry)
      ..writeScreen('paywall_pro_upgrade_plans.rfw', plans);

ResolvedFlow _navResolvedFlowOf(Uint8List entry, Uint8List plans) =>
    ResolvedFlow(
      document: _navFlowDocument(entryBytes: entry, plansBytes: plans),
      screenBlobs: {'entry': entry, 'plans': plans},
      cacheHit: false,
    );

/// A blob paywall labelled [text] whose tap fires a custom event.
ResolvedPaywallPayload _tappableBlob(String text) =>
    BlobPaywallPayload(ResolvedVariant(
      bytes: Uint8List.fromList(encodeLibraryBlob(parseLibraryFile('''
        import restage.core;
        widget Paywall = GestureDetector(
          onTap: event "promo" { },
          child: Text(text: "$text"),
        );
      '''))),
      surfaceVersion: text,
      paywallId: 'pro_upgrade',
    ));

/// The stub delivery for this file: it describes surfaces AND answers for
/// their content, so no test here can stub half a wire.
final HostedArtifactFixture _delivery = HostedArtifactFixture();

void main() {
  setUp(() {
    Restage.debugReset();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  for (final firstScreenFails in [true, false]) {
    testWidgets(
        'generated paywall uses its original only before the flow leaves its '
        'first screen: '
        'first screen fails = $firstScreenFails', (tester) async {
      registerThrowingWidget();
      final entry = firstScreenFails
          ? throwingScreenBlob()
          : _screenBlob({'See plans': 'restageNav0'});
      final plans = throwingScreenBlob();
      final bundle = _FlowAssetBundle()
        ..writeFlow(
          'native_offer',
          _navFlowDocument(entryBytes: entry, plansBytes: plans)
              .copyWith(flow: 'native_offer'),
        )
        ..writeScreen('paywall_pro_upgrade.rfw', entry)
        ..writeScreen('paywall_pro_upgrade_plans.rfw', plans);
      final events = <RestageEvent>[];
      await tester.pumpWidget(MaterialApp(
        home: NativeOfferSurface(
          resolver: AssetVariantResolver(bundle: bundle),
          onEvent: events.add,
          errorBuilder: (_, __) => const Text('Navigation unavailable'),
        ),
      ));
      await tester.pumpAndSettle();
      if (!firstScreenFails) {
        expect(events.whereType<PaywallViewed>(), hasLength(1));
        await tester.tap(find.text('See plans'));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNotNull);
      expect(
        find.text('Offer original'),
        firstScreenFails ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('Navigation unavailable'),
        firstScreenFails ? findsNothing : findsOneWidget,
      );
      expect(events.whereType<PaywallViewed>(), hasLength(1));
      expect(
        events.whereType<PaywallLoadFailed>().map((event) => event.errorCode),
        contains('render_error'),
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  }

  group('a navigation paywall', () {
    setUp(() {
      _ArmedThrow.armed = false;
      Restage.registerWidgetLibrary(_armedLibrary, widgets: [
        RestageWidgetFactory(
            name: 'ArmedThrow', builder: (_, __) => const _ArmedThrow()),
      ]);
    });

    Future<List<RestageEvent>> mount(
      WidgetTester tester, {
      required Uint8List entry,
      required Uint8List plans,
      bool withErrorBuilder = true,
    }) async {
      final events = <RestageEvent>[];
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      });
      await tester.pumpWidget(MaterialApp(
        home: NativeOfferSurface(
          resolver: AssetVariantResolver(bundle: _navBundle(entry, plans)),
          onEvent: events.add,
          errorBuilder: withErrorBuilder
              ? (_, __) => const Text('Navigation unavailable')
              : null,
        ),
      ));
      await tester.pumpAndSettle();
      return events;
    }

    testWidgets(
        'that fails on its first screen with no user state shows its original '
        'and ends the delivered view first', (tester) async {
      final events = await mount(tester,
          entry: _armedEntryBlob(const {}),
          plans: _screenBlob({'Buy': 'restage.purchase'}));
      expect(find.text('Entry'), findsOneWidget);
      await _throwOnRebuild(tester);
      expect(tester.takeException(), isNotNull);
      expect(find.text('Offer original'), findsOneWidget);
      expect(find.text('Navigation unavailable'), findsNothing);
      expect(_views(events), [
        'loadCompleted',
        'viewed',
        'dismissed programmatic',
        'loadFailed',
        'viewed',
      ]);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(_views(events).skip(5), ['dismissed programmatic']);
    });

    testWidgets(
        'that fails on its first screen after the user tapped it keeps its '
        'error builder', (tester) async {
      await mount(tester,
          entry: _armedEntryBlob({'Buy': 'buy_tapped'}),
          plans: _screenBlob({'Back': 'back'}));
      await tester.tap(find.text('Buy'));
      await tester.pump();
      await _throwOnRebuild(tester);
      expect(tester.takeException(), isNotNull);
      expect(find.text('Navigation unavailable'), findsOneWidget);
      expect(find.text('Offer original'), findsNothing);
    });

    testWidgets(
        'that fails after leaving its first screen without an error builder '
        'shows its original rather than nothing', (tester) async {
      registerThrowingWidget();
      final events = await mount(tester,
          entry: _screenBlob({'See plans': 'restageNav0'}),
          plans: throwingScreenBlob(),
          withErrorBuilder: false);
      await tester.tap(find.text('See plans'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNotNull);
      expect(find.text('Offer original'), findsOneWidget);
      expect(_views(events), [
        'loadCompleted',
        'viewed',
        'dismissed programmatic',
        'loadFailed',
        'viewed',
      ]);
    });

    testWidgets(
        'that went back to its first screen keeps its error builder on '
        'failure', (tester) async {
      await mount(tester,
          entry: _armedEntryBlob({'See plans': 'restageNav0'}),
          plans: _screenBlob({'Back': 'back'}));
      await tester.tap(find.text('See plans'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Entry'), findsOneWidget);
      await _throwOnRebuild(tester);
      expect(tester.takeException(), isNotNull);
      expect(find.text('Navigation unavailable'), findsOneWidget);
      expect(find.text('Offer original'), findsNothing);
    });

    testWidgets(
        'rebound to another placement drops the old flow and starts a new '
        'view', (tester) async {
      final bundle = _navBundle(_screenBlob({'See plans': 'restageNav0'}),
          _screenBlob({'Buy': 'restage.purchase'}));
      final events = <RestageEvent>[];
      Widget paywall({bool rebound = false}) => MaterialApp(
            home: NativeOfferSurface(
              resolver: AssetVariantResolver(bundle: bundle),
              placement: rebound ? 'checkout' : null,
              onEvent: events.add,
              errorBuilder: (_, __) => const Text('Navigation unavailable'),
            ),
          );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      });
      await tester.pumpWidget(paywall());
      await tester.pumpAndSettle();
      await tester.tap(find.text('See plans'));
      await tester.pumpAndSettle();
      expect(find.text('Buy'), findsOneWidget);
      await tester.pumpWidget(paywall(rebound: true));
      expect(find.text('Buy'), findsNothing);
      expect(find.text('See plans'), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('See plans'), findsOneWidget);
      expect(_views(events), [
        'loadCompleted',
        'viewed',
        'dismissed programmatic',
        'loadCompleted',
        'viewed',
      ]);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(_views(events).skip(5), ['dismissed programmatic']);
    });

    testWidgets(
        'promoted by a refresh in the frame after first paint still views once',
        (tester) async {
      final first = Completer<ResolvedPaywallPayload>();
      var calls = 0;
      final resolver = _AnswerResolver((_) {
        calls++;
        if (calls == 1) return first.future;
        return Future.value(FlowPaywallPayload(
          flow: _singleScreenResolvedFlow('Second'),
          paywallId: 'pro_upgrade',
        ));
      });
      final events = <RestageEvent>[];
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      });
      await tester.pumpWidget(MaterialApp(
        home: RestagePaywall(
          id: 'pro_upgrade',
          resolver: resolver,
          onEvent: events.add,
          fallbackBuilder: (_) => const Text('Original'),
        ),
      ));
      await tester.pump();
      unawaited(Restage.reloadSurfaces());
      await tester.pump(Duration.zero);
      first.complete(FlowPaywallPayload(
        flow: _singleScreenResolvedFlow('First'),
        paywallId: 'pro_upgrade',
      ));
      for (var i = 0; i < 40; i++) {
        await tester.pump(Duration.zero);
      }
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('Second'), findsOneWidget);
      expect(_views(events), ['loadCompleted', 'viewed']);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(_views(events).skip(2), ['dismissed programmatic']);
    });

    testWidgets(
        'is never replaced by a refresh once its load advanced into its error '
        'state', (tester) async {
      registerThrowingWidget();
      final resolver = _ControlledFlowPayloadResolver();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      });
      await tester.pumpWidget(MaterialApp(
        home: RestagePaywall(
          id: 'pro_upgrade',
          resolver: resolver,
          fallbackBuilder: (_) => const Text('Original'),
          errorBuilder: (_, __) => const Text('Unavailable'),
        ),
      ));
      await tester.pump();
      resolver.responses.single.complete(FlowPaywallPayload(
        flow: _navResolvedFlowOf(
            _screenBlob({'See plans': 'restageNav0'}), throwingScreenBlob()),
        paywallId: 'pro_upgrade',
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('See plans'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNotNull);
      expect(find.text('Unavailable'), findsOneWidget);
      await _refreshWithCandidate(tester, resolver);
      expect(find.text('Candidate'), findsNothing);
      expect(find.text('Unavailable'), findsOneWidget);
    });

    testWidgets(
        'rebound after an advanced failure lets the new load show its '
        'original', (tester) async {
      registerThrowingWidget();
      final bundle = _navBundle(
          _armedEntryBlob({'See plans': 'restageNav0'}), throwingScreenBlob());
      Widget paywall({bool rebound = false}) => MaterialApp(
            home: NativeOfferSurface(
              resolver: AssetVariantResolver(bundle: bundle),
              placement: rebound ? 'checkout' : null,
              errorBuilder: (_, __) => const Text('Navigation unavailable'),
            ),
          );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      });
      await tester.pumpWidget(paywall());
      await tester.pumpAndSettle();
      await tester.tap(find.text('See plans'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNotNull);
      expect(find.text('Navigation unavailable'), findsOneWidget);
      await tester.pumpWidget(paywall(rebound: true));
      await tester.pumpAndSettle();
      expect(find.text('Entry'), findsOneWidget);
      await _throwOnRebuild(tester);
      expect(tester.takeException(), isNotNull);
      expect(find.text('Offer original'), findsOneWidget);
      expect(find.text('Navigation unavailable'), findsNothing);
    });

    testWidgets(
        'is never replaced by a refresh after the user went forward and back',
        (tester) async {
      final resolver = _ControlledFlowPayloadResolver();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      });
      await tester.pumpWidget(MaterialApp(
        home: RestagePaywall(
          id: 'pro_upgrade',
          resolver: resolver,
          fallbackBuilder: (_) => const Text('Original'),
          errorBuilder: (_, __) => const Text('Unavailable'),
        ),
      ));
      await tester.pump();
      resolver.responses.single.complete(FlowPaywallPayload(
        flow: _navResolvedFlowOf(_screenBlob({'See plans': 'restageNav0'}),
            _screenBlob({'Back': 'back'})),
        paywallId: 'pro_upgrade',
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('See plans'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      await _refreshWithCandidate(tester, resolver);
      expect(find.text('Candidate'), findsNothing);
      expect(find.text('See plans'), findsOneWidget);
    });
  });

  testWidgets(
      'a rebind sends the old view its dismiss after the build, under its '
      'own id and callback', (tester) async {
    final resolver = _ControlledFlowPayloadResolver();
    final oldEvents = <RestageEvent>[];
    final newEvents = <RestageEvent>[];
    var rebound = false;
    var hostBuilds = 0;
    late StateSetter updateHost;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(builder: (context, setState) {
        updateHost = setState;
        hostBuilds++;
        final sink = rebound ? newEvents : oldEvents;
        return Scaffold(
          body: Builder(
            builder: (_) => RestagePaywall(
              id: rebound ? 'pro_upgrade_annual' : 'pro_upgrade',
              placementBinding: RestagePaywall.generatedPlacementBinding(
                definition: nativeOfferPlacementDefinition,
                name: rebound ? 'checkout' : null,
              ),
              resolver: resolver,
              onEvent: (event) {
                sink.add(event);
                if (event is PaywallDismissed) updateHost(() {});
              },
            ),
          ),
        );
      }),
    ));
    await tester.pump();
    resolver.responses.single.complete(FlowPaywallPayload(
      flow: _singleScreenResolvedFlow('First'),
      paywallId: 'pro_upgrade',
    ));
    await tester.pumpAndSettle();
    expect(oldEvents.whereType<PaywallViewed>(), hasLength(1));
    final buildsBefore = hostBuilds;
    updateHost(() => rebound = true);
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    final dismissed = oldEvents.whereType<PaywallDismissed>().single;
    expect(dismissed.paywallId, 'pro_upgrade');
    expect(dismissed.reason, DismissReason.programmatic);
    expect(newEvents.whereType<PaywallDismissed>(), isEmpty);
    expect(hostBuilds, greaterThan(buildsBefore + 1));
  });

  testWidgets(
      "a dialog a hosted flow's mount opens fires on the paywall, not outside",
      (tester) async {
    final outer = <String>[];
    final events = <String>[];
    late BuildContext mount;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestageEventDispatcher(
          onEvent: (name, _) => outer.add(name),
          child: Builder(builder: (context) {
            mount = context;
            return RestagePaywall(
              id: 'pro_upgrade',
              placementBinding: RestagePaywall.generatedPlacementBinding(
                definition: nativeOfferPlacementDefinition,
                eventOwner: context,
              ),
              resolver: _navPaywallResolver(),
              onEvent: (event) {
                if (event is PaywallCustomEvent) events.add(event.eventName);
              },
            );
          }),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('See plans'), findsOneWidget);
    showDialog<void>(
      context: mount,
      builder: (_) => TextButton(
        onPressed: mount.surfaceEvent(const SurfaceEvent<void>('terms')),
        child: const Text('terms'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('terms'));

    expect(events, ['terms']);
    expect(outer, isEmpty);
  });

  testWidgets("app code moves a hosted flow as the flow's screens do",
      (tester) async {
    late BuildContext mount;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) {
          mount = context;
          return RestagePaywall(
            id: 'pro_upgrade',
            placementBinding: RestagePaywall.generatedPlacementBinding(
              definition: nativeOfferPlacementDefinition,
              eventOwner: context,
            ),
            resolver: _navPaywallResolver(),
          );
        }),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Buy'), findsNothing);

    // A recorded callback firing the flow's own navigation event.
    mount.surfaceEvent(const SurfaceEvent<void>('restageNav0'))();
    await tester.pumpAndSettle();
    expect(find.text('Buy'), findsOneWidget);
  });

  for (final explicitEvents in [true, false]) {
    testWidgets(
        "a staged flow refresh leaves the mount's events on the paywall, "
        'explicitEvents=$explicitEvents', (tester) async {
      final resolver = _ControlledFlowPayloadResolver();
      final events = <String>[];
      late BuildContext mount;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      });
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          mount = context;
          // A generated mount with islands routes its events by the mount.
          return RestageIslandScope(
            owner: context,
            explicitEvents: explicitEvents,
            builders: const {},
            child: RestagePaywall(
              id: 'pro_upgrade',
              placementBinding: RestagePaywall.generatedPlacementBinding(
                definition: nativeOfferPlacementDefinition,
                eventOwner: context,
              ),
              resolver: resolver,
              onEvent: (event) {
                if (event is PaywallCustomEvent) events.add(event.eventName);
              },
            ),
          );
        }),
      ));
      await tester.pump();
      resolver.responses.single.complete(FlowPaywallPayload(
        flow: _navResolvedFlowOf(_screenBlob({'See plans': 'restageNav0'}),
            _screenBlob({'Back': 'back'})),
        paywallId: 'pro_upgrade',
      ));
      await tester.pumpAndSettle();
      final refresh = Restage.reloadSurfaces();
      await tester.pump();
      expect(resolver.responses, hasLength(greaterThan(1)));
      for (final response in resolver.responses.skip(1)) {
        response.complete(FlowPaywallPayload(
          flow: _navResolvedFlowOf(_screenBlob({'Candidate': 'noop'}),
              _screenBlob({'Back': 'back'})),
          paywallId: 'pro_upgrade',
        ));
      }
      // Pump until the candidate is built beside the shown layer.
      for (var frame = 0;
          frame < 20 &&
              find.text('Candidate', skipOffstage: false).evaluate().isEmpty;
          frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.text('Candidate', skipOffstage: false), findsOneWidget);
      expect(find.text('See plans'), findsOneWidget);

      // The copied build's recorded event, while the candidate is staged.
      RestageRecording(owner: mount).surfaceEvent(
        const SurfaceEvent<void>('terms'),
      )();
      expect(events, ['terms']);
      await refresh;
      await tester.pumpAndSettle();
    });
  }

  testWidgets('a rebound paywall can refresh content the user has not touched',
      (tester) async {
    final resolver = _ControlledFlowPayloadResolver();
    Widget paywall({bool rebound = false}) => MaterialApp(
          home: RestagePaywall(
            id: 'pro_upgrade',
            placementBinding: RestagePaywall.generatedPlacementBinding(
              definition: nativeOfferPlacementDefinition,
              name: rebound ? 'checkout' : null,
            ),
            resolver: resolver,
          ),
        );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
    await tester.pumpWidget(paywall());
    await tester.pump();
    resolver.responses.single.complete(_tappableBlob('First'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('First'));
    await tester.pumpWidget(paywall(rebound: true));
    await tester.pump();
    resolver.responses.last.complete(_tappableBlob('Checkout'));
    await tester.pumpAndSettle();
    expect(find.text('Checkout'), findsOneWidget);
    final refresh = Restage.reloadSurfaces();
    await tester.pump();
    expect(resolver.responses, hasLength(3));
    resolver.responses.last.complete(_tappableBlob('Refreshed'));
    await refresh;
    await tester.pumpAndSettle();
    expect(find.text('Refreshed'), findsOneWidget);
  });

  testWidgets('a hosted flow that paints nothing fails with its own reason',
      (tester) async {
    registerThrowingWidget();
    final entry = throwingScreenBlob();
    final bundle = _FlowAssetBundle()
      ..writeFlow(
        'native_offer',
        _navFlowDocument(entryBytes: entry, plansBytes: entry)
            .copyWith(flow: 'native_offer'),
      )
      ..writeScreen('paywall_pro_upgrade.rfw', entry)
      ..writeScreen('paywall_pro_upgrade_plans.rfw', entry);
    final events = <RestageEvent>[];
    final subscription = Restage.events.listen(events.add);
    addTearDown(subscription.cancel);
    await tester.pumpWidget(MaterialApp(
      home: RestagePaywall(
        id: 'native_offer',
        resolver: AssetVariantResolver(bundle: bundle),
        errorBuilder: (_, __) => const Text('Navigation unavailable'),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNotNull);
    expect(find.text('Navigation unavailable'), findsOneWidget);
    final failed = events.whereType<SurfaceLoadFailed>().single;
    expect(failed.reason, SurfaceLoadFailureReason.renderError);
    expect(failed.detail, 'render_failed');
    expect(events.whereType<SurfaceLoadCompleted>(), isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('a flow-shaped paywall forwards context after controlled load',
      (tester) async {
    final resolver = _ControlledFlowPayloadResolver();
    var hostContext = <String, Object?>{'label': 'first'};
    late StateSetter updateHost;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            updateHost = setState;
            return Scaffold(
              body: RestagePaywall(
                id: 'pro_upgrade',
                resolver: resolver,
                context: hostContext,
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();
    expect(resolver.responses, hasLength(1));

    hostContext['label'] = 'later';
    resolver.responses.single.complete(
      FlowPaywallPayload(
        flow: _contextSingleScreenResolvedFlow(),
        paywallId: 'pro_upgrade',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('first'), findsOneWidget);
    expect(find.text('later'), findsNothing);

    updateHost(() => hostContext = <String, Object?>{'label': 'second'});
    await tester.pump();
    expect(find.text('second'), findsOneWidget);
  });

  testWidgets('a pending flow-shaped paywall retains its accepted context',
      (tester) async {
    final resolver = _ControlledFlowPayloadResolver();
    final hostContext = <String, Object?>{'label': 'accepted'};
    await tester.pumpWidget(
      MaterialApp(
        home: RestagePaywall(
          id: 'pro_upgrade',
          resolver: resolver,
          context: hostContext,
        ),
      ),
    );
    await tester.pump();
    resolver.responses.single.complete(
      FlowPaywallPayload(
        flow: _contextSingleScreenResolvedFlow(marker: 'Current content'),
        paywallId: 'pro_upgrade',
      ),
    );
    await tester.pumpAndSettle();

    final refresh = Restage.reloadSurfaces();
    await tester.pump();
    expect(resolver.responses, hasLength(2));
    hostContext['label'] = 'later';
    resolver.responses[1].complete(
      FlowPaywallPayload(
        flow: _contextSingleScreenResolvedFlow(marker: 'Candidate content'),
        paywallId: 'pro_upgrade',
      ),
    );
    await refresh;
    await tester.pumpAndSettle();

    expect(find.text('Candidate content'), findsOneWidget);
    expect(find.text('accepted'), findsOneWidget);
    expect(find.text('later'), findsNothing);
  });

  testWidgets(
      'an initial root SubFlow does not commit paywall lifecycle before a '
      'child installs the first screen', (tester) async {
    Restage.configure(apiKey: 'pk_test');
    final resolver = _ControlledFlowPayloadResolver();
    final events = <RestageEvent>[];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'pro_upgrade',
          resolver: resolver,
          onEvent: events.add,
          loadingBuilder: (_) => const Text('Loading child'),
          errorBuilder: (_, __) => const Text('Child unavailable'),
        ),
      ),
    ));
    await tester.pump();

    expect(resolver.responses, hasLength(1));
    expect(events.whereType<PaywallLoadCompleted>(), isEmpty);
    expect(events.whereType<PaywallViewed>(), isEmpty);

    resolver.responses.single.complete(FlowPaywallPayload(
      flow: _initialSubFlowThatFailsBeforeScreen(),
      paywallId: 'pro_upgrade',
      paywallPublishedVersion: 2,
    ));
    await tester.pumpAndSettle();

    final observed = (
      completed: events.whereType<PaywallLoadCompleted>().length,
      viewed: events.whereType<PaywallViewed>().length,
      failed: events.whereType<PaywallLoadFailed>().length,
      unavailable: find.text('Child unavailable').evaluate().length,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(
      observed,
      (completed: 0, viewed: 0, failed: 1, unavailable: 1),
    );
  });

  testWidgets(
      'a refresh root SubFlow that fails before its child screen preserves the '
      'old rendered controller and published identity', (tester) async {
    Restage.configure(apiKey: 'pk_test');
    final resolver = _ControlledFlowPayloadResolver();
    final events = <RestageEvent>[];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'pro_upgrade',
          resolver: resolver,
          onEvent: events.add,
          errorBuilder: (_, __) => const Text('Refresh failed visibly'),
        ),
      ),
    ));
    await tester.pump();
    expect(resolver.responses, hasLength(1));
    resolver.responses[0].complete(FlowPaywallPayload(
      flow: _singleScreenResolvedFlow('Old rendered paywall'),
      paywallId: 'pro_upgrade',
      paywallPublishedVersion: 1,
    ));
    await tester.pumpAndSettle();
    expect(find.text('Old rendered paywall'), findsOneWidget);
    events.clear();

    final failedRefresh = Restage.reloadSurfaces();
    await tester.pump();
    expect(resolver.responses, hasLength(2));
    resolver.responses[1].complete(FlowPaywallPayload(
      flow: _initialSubFlowThatFailsBeforeScreen(),
      paywallId: 'pro_upgrade',
      paywallPublishedVersion: 2,
    ));
    await failedRefresh;
    await tester.pumpAndSettle();

    final currentOld = find.text('Old rendered paywall').evaluate().length;
    final currentError = find.text('Refresh failed visibly').evaluate().length;

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(
      (currentOld: currentOld, currentError: currentError),
      (currentOld: 1, currentError: 0),
    );
  });

  testWidgets(
      'an initial flow screen that throws on first build stamps no identity, '
      'cache, or paywall lifecycle', (tester) async {
    Restage.configure(apiKey: 'pk_test');
    registerThrowingWidget();
    final resolver = _ControlledFlowPayloadResolver();
    final events = <RestageEvent>[];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'pro_upgrade',
          resolver: resolver,
          onEvent: events.add,
          errorBuilder: (_, __) => const Text('Initial render unavailable'),
        ),
      ),
    ));
    await tester.pump();
    resolver.responses.single.complete(FlowPaywallPayload(
      flow: throwingResolvedFlow(),
      paywallId: 'pro_upgrade',
      paywallPublishedVersion: 2,
    ));
    await tester.pumpAndSettle();

    final firstObserved = (
      error: find.text('Initial render unavailable').evaluate().length,
      completed: events.whereType<PaywallLoadCompleted>().length,
      viewed: events.whereType<PaywallViewed>().length,
      failed: events.whereType<PaywallLoadFailed>().length,
      dismissed: events.whereType<PaywallDismissed>().length,
      reported: tester.takeException() != null,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    final dismissedAfterUnmount = events.whereType<PaywallDismissed>().length;

    // A resolver failure on remount must surface its own delivery error. If the
    // throwing first render had been cached, the fallback would re-host it and
    // surface render_error instead.
    events.clear();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'pro_upgrade',
          resolver: resolver,
          onEvent: events.add,
          errorBuilder: (_, __) => const Text('Fresh delivery unavailable'),
        ),
      ),
    ));
    await tester.pump();
    resolver.responses[1].completeError(const RestagePaywallError(
      code: RestageErrorCodes.deliveryUnavailable,
      message: 'fresh remount failed',
    ));
    await tester.pumpAndSettle();
    final remountFailure = events.whereType<PaywallLoadFailed>().single;
    final remountObserved = (
      error: find.text('Fresh delivery unavailable').evaluate().length,
      code: remountFailure.errorCode,
      completed: events.whereType<PaywallLoadCompleted>().length,
      viewed: events.whereType<PaywallViewed>().length,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(
      firstObserved,
      (
        error: 1,
        completed: 0,
        viewed: 0,
        failed: 1,
        dismissed: 0,
        reported: true,
      ),
    );
    expect(dismissedAfterUnmount, 0);
    expect(
      remountObserved,
      (
        error: 1,
        code: RestageErrorCodes.deliveryUnavailable,
        completed: 0,
        viewed: 0,
      ),
    );
  });

  testWidgets(
      'a refresh flow screen that throws on first build preserves last-good '
      'render, identity, cache, and lifecycle', (tester) async {
    Restage.configure(apiKey: 'pk_test');
    registerThrowingWidget();
    final resolver = _ControlledFlowPayloadResolver();
    final events = <RestageEvent>[];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'pro_upgrade',
          resolver: resolver,
          onEvent: events.add,
          errorBuilder: (_, __) => const Text('Refresh failed visibly'),
        ),
      ),
    ));
    await tester.pump();
    resolver.responses.single.complete(FlowPaywallPayload(
      flow: _singleScreenResolvedFlow('Old rendered paywall'),
      paywallId: 'pro_upgrade',
      paywallPublishedVersion: 1,
    ));
    await tester.pumpAndSettle();
    events.clear();

    final refresh = Restage.reloadSurfaces();
    await tester.pump();
    resolver.responses[1].complete(FlowPaywallPayload(
      flow: throwingResolvedFlow(),
      paywallId: 'pro_upgrade',
      paywallPublishedVersion: 2,
    ));
    await refresh;
    await tester.pumpAndSettle();

    final currentObserved = (
      old: find.text('Old rendered paywall').evaluate().length,
      error: find.text('Refresh failed visibly').evaluate().length,
      completed: events.whereType<PaywallLoadCompleted>().length,
      viewed: events.whereType<PaywallViewed>().length,
      failed: events.whereType<PaywallLoadFailed>().length,
      dismissed: events.whereType<PaywallDismissed>().length,
      reported: tester.takeException() != null,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(
      currentObserved,
      (
        old: 1,
        error: 0,
        completed: 0,
        viewed: 0,
        failed: 0,
        dismissed: 0,
        reported: true,
      ),
    );
  });

  testWidgets(
      'a legacy flow-hosted paywall renders from the compatibility bundle path',
      (tester) async {
    Restage.configure(apiKey: 'pk_test');

    await _pumpFlowPaywall(tester, resolver: _legacyNavPaywallResolver());

    expect(find.text('See plans'), findsOneWidget);
    await tester.tap(find.text('See plans'));
    await tester.pumpAndSettle();
    expect(find.text('Buy'), findsOneWidget);
  });

  testWidgets(
    'a canonical flow-hosted paywall renders its entry screen, navigates to '
    'the pushed screen, and ignores a reserved commerce event there',
    (tester) async {
      Restage.configure(apiKey: 'pk_test');

      final received = <RestageEvent>[];
      await _pumpFlowPaywall(tester, onEvent: received.add);

      expect(find.text('See plans'), findsOneWidget);
      expect(find.text('Buy'), findsNothing);

      await tester.tap(find.text('See plans'));
      await tester.pumpAndSettle();
      expect(find.text('Buy'), findsOneWidget);

      final beforeTap = received.length;
      await tester.tap(find.text('Buy'));
      await tester.pumpAndSettle();

      expect(received, hasLength(beforeTap));
      expect(find.text('Buy'), findsOneWidget);
    },
  );

  testWidgets('a flow-hosted paywall reports its published version',
      (tester) async {
    Restage.configure(apiKey: 'pk_test');

    final received = <RestageEvent>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'pro_upgrade',
          resolver: _PublishedFlowResolver(publishedVersion: 7),
          onEvent: received.add,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final viewed = received.whereType<PaywallViewed>().toList();
    expect(viewed, isNotEmpty,
        reason: 'a flow paywall must fire PaywallViewed');
    expect(viewed.first.publishedVersion, 7);
  });

  testWidgets(
      'tapping skip on the entry screen completes the flow as a paywall '
      'dismiss keyed on paywallId (not an onboarding completion)',
      (tester) async {
    Restage.configure(apiKey: 'pk_test');
    final received = <RestageEvent>[];
    await _pumpFlowPaywall(tester, onEvent: received.add);

    await tester.tap(find.text('No thanks')); // the skip affordance
    await tester.pumpAndSettle();

    final dismissed = received.whereType<PaywallDismissed>().toList();
    expect(dismissed, hasLength(1));
    expect(dismissed.single.paywallId, 'pro_upgrade');
    expect(dismissed.single.reason, DismissReason.userClose);
  });

  testWidgets(
      'a flow-hosted paywall surfaces PAYWALL lifecycle (not onboarding) — no '
      'flowId-bearing event leaks to analytics', (tester) async {
    Restage.configure(apiKey: 'pk_test');
    final received = <RestageEvent>[];
    final sub = Restage.events.listen(received.add);
    addTearDown(sub.cancel);

    await _pumpFlowPaywall(tester);
    await tester.pumpAndSettle();

    final names = received.map((e) => e.name).toSet();
    // Paywall-shaped lifecycle fires, keyed on paywallId.
    expect(names, contains('paywall_load_started'));
    expect(names, contains('paywall_load_completed'));
    expect(names, contains('paywall_viewed'));
    for (final e in received) {
      expect(e.paywallId, anyOf(isNull, 'pro_upgrade'));
    }
    // The vanilla onboarding flow lifecycle is suppressed — none of these leak.
    expect(names, isNot(contains('onboarding_started')));
    expect(names, isNot(contains('flow_started')));
    expect(names, isNot(contains('onboarding_step_viewed')));
  });

  testWidgets(
      'FAIL-CLOSED: a hosted flow payload under a paywall surface is rejected '
      'by the hosted resolver and does NOT render — it falls through to the '
      'bundled/error path', (tester) async {
    Restage.configure(apiKey: 'pk_test');
    // The hosted fetch returns a FLOW payload under a paywall surface. The
    // hosted resolver rejects a non-blob hosted payload, and with no bundled
    // asset there is nothing to fall back to -> the paywall fails closed to its
    // error builder. The hosted flow's screens are NEVER hosted/rendered.
    final entry =
        _screenBlob({'See plans': 'restageNav0', 'No thanks': 'skip'});
    final plans = _screenBlob({'Buy': 'restage.purchase'});
    final hostedFlowEnvelope = SurfaceDocumentCodec.encode(SurfaceDocument(
      surfaceType: Surface.paywall,
      surfaceSlug: 'pro_upgrade',
      version: 9,
      minClient: _renderableMinClient,
      payload: FlowSurfacePayload(
        flowDocument: _navFlowDocument(entryBytes: entry, plansBytes: plans),
        // screenBlobs are keyed by screen id (matching the document artifacts).
        screenBlobs: {'entry': entry, 'plans': plans},
      ),
      publishedAt: DateTime.utc(2026),
    ));
    final resolver = RestageVariantResolver(
      apiKey: 'rs_pk_test_x',
      baseUrl: 'https://surfaces.example.com',
      httpClient: _delivery.client(
        (_) async => http.Response(
          jsonEncode({..._delivery.describeEnvelope(hostedFlowEnvelope)}),
          200,
        ),
      ),
      // An empty bundle: no bundled fallback for this id.
      assetFallback: AssetVariantResolver(bundle: _FlowAssetBundle()),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'pro_upgrade',
          resolver: resolver,
          errorBuilder: (_, __) => const Text('FAILED_CLOSED'),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // The error builder rendered; the hosted flow's screens did NOT.
    expect(find.text('FAILED_CLOSED'), findsOneWidget);
    expect(find.text('See plans'), findsNothing);
    expect(find.text('Buy'), findsNothing);
  });

  testWidgets(
      'a restageNav look-alike custom event (restageNavFoo) surfaces as a PaywallCustomEvent',
      (tester) async {
    Restage.configure(apiKey: 'pk_test');
    final received = <RestageEvent>[];

    // The entry screen also exposes a look-alike "restageNavFoo" event.
    final entry = _screenBlob({
      'See plans': 'restageNav0',
      'Help': 'restageNavFoo',
      'No thanks': 'skip',
    });
    final plans = _screenBlob({'Buy': 'restage.purchase'});
    final bundle = _FlowAssetBundle()
      ..writeFlow(
          'pro_upgrade', _navFlowDocument(entryBytes: entry, plansBytes: plans))
      ..writeScreen('paywall_pro_upgrade.rfw', entry)
      ..writeScreen('paywall_pro_upgrade_plans.rfw', plans);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'pro_upgrade',
          resolver: AssetVariantResolver(bundle: bundle),
          onEvent: received.add,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Help'));
    await tester.pumpAndSettle();

    // It did NOT navigate (still on the entry screen) and surfaced as a custom
    // event, not a swallowed/forwarded navigation.
    expect(find.text('See plans'), findsOneWidget);
    final custom = received.whereType<PaywallCustomEvent>().toList();
    expect(custom.map((e) => e.eventName), contains('restageNavFoo'));
  });

  testWidgets('an active-resolved flow is not re-hosted when a remount fails',
      (tester) async {
    Restage.configure(apiKey: 'pk_test');
    // The active-resolved flow renders once, then the resolver fails.
    final resolver =
        _SeqFlowResolver(_navResolvedFlow(), resolvedFromActiveArm: true);

    Widget paywall(List<RestageEvent> received) => MaterialApp(
          home: Scaffold(
            body: RestagePaywall(
              id: 'pro_upgrade',
              resolver: resolver,
              onEvent: received.add,
            ),
          ),
        );

    // Mount 1: the fresh active flow resolves + renders + caches.
    final first = <RestageEvent>[];
    await tester.pumpWidget(paywall(first));
    await tester.pumpAndSettle();
    expect(find.text('See plans'), findsOneWidget);

    // Remount: the fresh resolve fails. Unlike a bundled flow, an ACTIVE-resolved
    // flow must NOT be re-hosted from the runtime cache un-re-gated — the
    // resolver's own re-gated hold-last-good owns re-serving it. Here (a
    // stub resolver that just fails) it falls closed to the error path.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    final second = <RestageEvent>[];
    await tester.pumpWidget(paywall(second));
    await tester.pumpAndSettle();
    expect(find.text('See plans'), findsNothing);
    expect(second.whereType<PaywallLoadCompleted>(), isEmpty);
    expect(second.whereType<PaywallLoadFailed>(), isNotEmpty);
  });
}
