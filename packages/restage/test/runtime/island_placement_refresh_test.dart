import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show StringCodec;
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
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    show DeliveryPolicyScopeV1, DeliveryRootIdentityV1, PlacementIdentityV1;
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart' hide WidgetLibrary;
import 'package:shared_preferences/shared_preferences.dart';

import '../support/placement_delivery_fixture.dart';
import '../support/sent_placement_request.dart';
import '../surface_screen/surface_screen_test_support.dart';

BlobSurfacePayload _payload(String text) => BlobSurfacePayload(
    minClient: 1,
    blob: Uint8List.fromList(encodeLibraryBlob(parseLibraryFile('''
      import restage.core;
      import app.islands;
      widget OnboardingScreen = Column(children: [
        Text(text: "$text"),
        Keep(),
      ]);
    '''))));

Widget _keep(BuildContext context, DataSource source) =>
    RestageIslandScope.build('Keep', 'missing', context, source);

const _islands = RestageWidgetLibraryRegistration.constant(
  library: WidgetLibrary.custom('app.islands'),
  widgets: [RestageWidgetFactory(name: 'Keep', builder: _keep)],
  islands: true,
);

var _starts = 0;

class _Counter extends StatefulWidget {
  const _Counter();
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int count = 0;
  @override
  void initState() {
    super.initState();
    _starts++;
  }

  @override
  Widget build(BuildContext context) => Text('count $count');
}

// A design that places the app widget `Tally` by name, as a split widget's
// definition does.
BlobSurfacePayload _splitPayload(String text) => BlobSurfacePayload(
    minClient: 1,
    blob: Uint8List.fromList(encodeLibraryBlob(parseLibraryFile('''
      import restage.core;
      import app.splits;
      widget OnboardingScreen = Column(children: [
        Text(text: "$text"),
        Tally(restageIsland: "tally_0"),
      ]);
    '''))));

const _splits = RestageWidgetLibraryRegistration.constant(
  library: WidgetLibrary.custom('app.splits'),
  widgets: [RestageWidgetFactory(name: 'Tally', builder: _tally)],
);

Widget _tally(BuildContext context, DataSource source) =>
    RestageIslandScope.split(context, source, () => const _Counter());

const _watchToken =
    'v2.i5p7lxR3.1767229200.NDI6b25ib2FyZGluZzp3ZWxjb21lLWZsb3c.'
    'kV0gFtXCrtsWdYcIFXaVNEQDQFjXwvrEn4t_WY_KX44';

// The answer that leaves a mount on its fallback.
PlacementBatchResolvedV1 _fallback(PlacementBatchRequestV1 request) {
  final target = readPlacementDeliveryFixture().target;
  final mount = request.mounts.single;
  final descriptor = PlacementMountDescriptorV1(
      placement: PlacementIdentityV1(target: target, key: mount.key),
      hostContractHash: mount.hostContractHash);
  return PlacementBatchResolvedV1(
    request: request,
    expectedTarget: target,
    decisions: [
      PlacementBatchEntryV1.useFallback(
          descriptor, PlacementBatchRefusalReasonV1.unavailable, const [],
          watch: PlacementDeliveryWatchV1(
              decisionIdentityDigest: CanonicalDigest('f' * 64),
              channels: [
                PlacementDeliveryWatchChannelV1(
                    scope: DeliveryPolicyScopeV1(
                        root: DeliveryRootIdentityV1.placement(
                            descriptor.placement),
                        family: const DeliveryFamilySelectorV1.none()),
                    token: _watchToken)
              ])),
    ],
  );
}

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

void main() {
  testWidgets(
      'a split widget keeps its State from the fallback to the design and '
      'across a new version', (tester) async {
    Restage.debugReset();
    addTearDown(Restage.debugReset);
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
        appName: 'test',
        packageName: 'test',
        version: '1',
        buildNumber: '42',
        buildSignature: '');
    debugResetAppBuildOrdinal();
    sharedSurfaceArtifactStore = MemorySurfaceArtifactStore();
    addTearDown(() => sharedSurfaceArtifactStore = null);
    final original = stringScreenFixture(
        slug: 'original_notice', schema: SurfaceScreenEventSchema(events: []));
    Restage.configure(
        apiKey: 'rs_pk_test',
        baseUrl: 'https://example.com',
        analyticsEnabled: false,
        measurementEnabled: false,
        deliveryReceiptsEnabled: false);
    const SurfaceVocabulary(libraries: [_splits]).addToInstalled();
    debugResetInstallObservations();
    debugSetOsVersion(19);
    SurfaceMeteringKeyProvider.clear();
    Restage.debugPlacementNow = () => DateTime.utc(2026, 10, 4, 12);
    String? text;
    final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: MockClient((outgoing) async {
          final artifact = placementFixtureArtifact(outgoing);
          if (artifact != null) return artifact;
          final request = sentPlacementRequest(outgoing.bodyBytes);
          final design = text;
          return http.Response.bytes(
              (design == null
                      ? _fallback(request)
                      : placementFixtureResponse(request,
                          payload: _splitPayload(design),
                          family: DeliveryFamilySelectorV1.screenContract(
                              contractVersion: 7)))
                  .canonicalBytes,
              200);
        }));
    addTearDown(client.close);
    Restage.debugRestageRpcClient = client;
    final definition = GeneratedPlacementDefinition(
        defaultSurface: original.ref,
        defaultSurfaceLocator: DeliverySurfaceLocatorV1(
            surfaceType: DeliverySurfaceTypeId('general'),
            slug: original.ref.slug,
            family: DeliveryFamilySelectorV1.screenContract(
                contractVersion: original.ref.contractVersion)),
        key: PlacementKeyV1.generatedDefault(
            surfaceType: DeliverySurfaceTypeId('general'),
            slug: original.ref.slug),
        hostContract: readPlacementDeliveryFixture()
            .request
            .buildContract
            .contractsByHash
            .values
            .first,
        vocabulary: SurfaceVocabulary.none);
    late final RestageScreen<String> host;
    // The fallback places the app's widget as the build's copy does.
    host = RestageScreen(
        screen: original.ref,
        placementBinding: PlacementMountBinding(definition: () => definition),
        fallbackBuilder: (_) => Column(children: [
              const Text('fallback'),
              RestageIslandScope.keyed(host, 'tally_0', const _Counter()),
            ]));
    _starts = 0;
    try {
      await tester.pumpWidget(MaterialApp(
          home: RestageIslandScope(owner: host, builders: {}, child: host)));
      await _frames(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('fallback'), findsOneWidget);
      tester.state<_CounterState>(find.byType(_Counter)).count = 7;

      for (final version in ['A', 'B']) {
        text = version;
        await SurfaceRefreshRegistry.instance.reload();
        await _frames(tester);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text(version), findsOneWidget);
        expect(tester.state<_CounterState>(find.byType(_Counter)).count, 7);
        expect(_starts, 1);
      }
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets(
      'a placement refresh swaps a screen in place and keeps its island State',
      (tester) async {
    Restage.debugReset();
    addTearDown(Restage.debugReset);
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
        appName: 'test',
        packageName: 'test',
        version: '1',
        buildNumber: '42',
        buildSignature: '');
    debugResetAppBuildOrdinal();
    sharedSurfaceArtifactStore = MemorySurfaceArtifactStore();
    addTearDown(() => sharedSurfaceArtifactStore = null);
    final original = stringScreenFixture(
        slug: 'original_notice', schema: SurfaceScreenEventSchema(events: []));
    final bundleBytes = original.bundleBytes();
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMessageHandler('flutter/assets', (message) async {
      if (const StringCodec().decodeMessage(message) !=
          original.locator.assetKey) {
        return null;
      }
      return ByteData.sublistView(bundleBytes);
    });
    addTearDown(() => messenger.setMockMessageHandler('flutter/assets', null));
    Restage.configure(
        apiKey: 'rs_pk_test',
        baseUrl: 'https://example.com',
        analyticsEnabled: false,
        measurementEnabled: false,
        deliveryReceiptsEnabled: false);
    const SurfaceVocabulary(libraries: [_islands]).addToInstalled();
    debugResetInstallObservations();
    debugSetOsVersion(19);
    SurfaceMeteringKeyProvider.clear();
    Restage.debugPlacementNow = () => DateTime.utc(2026, 10, 4, 12);
    var text = 'A';
    var requests = 0;
    final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: MockClient((outgoing) async {
          final artifact = placementFixtureArtifact(outgoing);
          if (artifact != null) return artifact;
          requests++;
          return http.Response.bytes(
              placementFixtureResponse(sentPlacementRequest(outgoing.bodyBytes),
                      payload: _payload(text),
                      family: DeliveryFamilySelectorV1.screenContract(
                          contractVersion: 7))
                  .canonicalBytes,
              200);
        }));
    addTearDown(client.close);
    Restage.debugRestageRpcClient = client;
    final definition = GeneratedPlacementDefinition(
        defaultSurface: original.ref,
        defaultSurfaceLocator: DeliverySurfaceLocatorV1(
            surfaceType: DeliverySurfaceTypeId('general'),
            slug: original.ref.slug,
            family: DeliveryFamilySelectorV1.screenContract(
                contractVersion: original.ref.contractVersion)),
        key: PlacementKeyV1.generatedDefault(
            surfaceType: DeliverySurfaceTypeId('general'),
            slug: original.ref.slug),
        hostContract: readPlacementDeliveryFixture()
            .request
            .buildContract
            .contractsByHash
            .values
            .first,
        vocabulary: SurfaceVocabulary.none);
    final host = RestageScreen(
      screen: original.ref,
      placementBinding: PlacementMountBinding(definition: () => definition),
    );
    _starts = 0;
    try {
      await tester.pumpWidget(MaterialApp(
          home: RestageIslandScope(
              owner: host,
              builders: {'Keep': (context, source) => const _Counter()},
              child: host)));
      await _frames(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('A'), findsOneWidget);
      final screen = tester.state(find.byWidget(host));
      tester.state<_CounterState>(find.byType(_Counter)).count = 7;

      text = 'B';
      await SurfaceRefreshRegistry.instance.reload();
      await _frames(tester);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(requests, 2);
      expect(find.text('B'), findsOneWidget);
      expect(find.text('A', skipOffstage: false), findsNothing);
      expect(tester.state(find.byWidget(host)), same(screen));
      expect(tester.state<_CounterState>(find.byType(_Counter)).count, 7);
      expect(_starts, 1);
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
  });
}
