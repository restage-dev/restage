import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/delivery/surface_artifact_store.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage/src/resolver/surface_delivery_observations.dart';
import 'package:restage/src/resolver/surface_metering_key_provider.dart';
import 'package:restage/src/runtime/placement_discovery.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/placement_delivery_fixture.dart';
import '../support/sent_placement_request.dart';

final class _GatedStore
    implements SurfaceArtifactStore, SurfaceArtifactScopeReader {
  final _memory = MemorySurfaceArtifactStore();
  final gate = Completer<void>();

  @override
  bool get readsOffIsolate => true;

  @override
  Future<R> readScope<R>(String scope, Set<String> surfaceTypes,
      R Function(StoredScopeRows rows) process) async {
    await gate.future;
    return readStoreScope(_memory, scope, surfaceTypes, process);
  }

  @override
  Future<StoredSurface?> read(SurfaceStoreKey key) => _memory.read(key);
  @override
  Future<void> write(SurfaceStoreKey key, StoredSurface value) =>
      _memory.write(key, value);
  @override
  Future<void> remove(SurfaceStoreKey key) => _memory.remove(key);
  @override
  Future<List<SurfaceStoreKey>> keys() => _memory.keys();
  @override
  Future<void> clear() => _memory.clear();
}

void main() {
  for (final mountFirst in [false, true]) {
    testWidgets(
        'reports, with the build ordinal, when the first mount '
        '${mountFirst ? 'precedes' : 'follows'} the read ahead',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      PackageInfo.setMockInitialValues(
          appName: 'capture',
          packageName: 'example.capture',
          version: '1',
          buildNumber: '42',
          buildSignature: '');
      Restage.debugReset();
      debugResetAppBuildOrdinal();
      debugResetOsVersion();
      final store = _GatedStore();
      sharedSurfaceArtifactStore = store;
      final definition = _generatedOffer();
      Restage.declareSurfaces([definition]);
      Restage.configure(
          apiKey: 'rs_pk_capture',
          baseUrl: 'https://example.com',
          analyticsEnabled: false,
          measurementEnabled: false,
          deliveryReceiptsEnabled: true);
      Restage.debugPlacementNow = () => DateTime.utc(2026, 10, 4, 12);
      debugResetInstallObservations();
      debugSetOsVersion(19);
      SurfaceMeteringKeyProvider.clear();
      final reportBodies = <List<int>>[];
      final client = RestageRpcClient(
          baseUrl: 'https://example.com',
          apiKey: 'rs_pk_capture',
          httpClient: MockClient((request) async {
            final fixtureArtifact = placementFixtureArtifact(request);
            if (fixtureArtifact != null) return fixtureArtifact;
            if (request.url.path == '/sdk/v1/placements/resolve') {
              return http.Response.bytes(
                  placementFixtureResponse(
                          sentPlacementRequest(request.bodyBytes))
                      .canonicalBytes,
                  200);
            }
            if (request.url.path == '/sdk/v1/placements/report') {
              reportBodies.add(request.bodyBytes);
              return http.Response('{}', 200);
            }
            return http.Response('', 204);
          }));
      Restage.debugRestageRpcClient = client;
      try {
        if (!mountFirst) {
          store.gate.complete();
          await tester.pump();
        }
        await tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: RestagePaywall(
            id: 'original_offer',
            placementBinding: PlacementMountBinding(
                definition: () => definition, name: 'offer_card'),
            fallbackBuilder: (_) => const SizedBox(width: 80, height: 25),
          ),
        ));
        if (mountFirst) {
          store.gate.complete();
        }
        for (var step = 0; step < 50; step++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(reportBodies, isNotEmpty);
        expect(
            PlacementDiscoveryReportV1.fromCanonicalBytes(reportBodies.first)
                .buildContract
                .buildOrdinal,
            42);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        client.close();
        PlacementDiscovery.instance.reset();
        Restage.debugReset();
        sharedSurfaceArtifactStore = null;
      }
    });
  }

  test('the placement registry takes the configured environment', () {
    SharedPreferences.setMockInitialValues({});
    Restage.debugReset();
    sharedSurfaceArtifactStore = MemorySurfaceArtifactStore();
    addTearDown(() {
      Restage.debugReset();
      sharedSurfaceArtifactStore = null;
    });
    Restage.configure(
        apiKey: 'rs_pk_test',
        baseUrl: 'https://example.com',
        environment: RestageEnvironment.sandbox,
        analyticsEnabled: false,
        measurementEnabled: false,
        deliveryReceiptsEnabled: false);
    expect(
        Restage.placementRegistry!.scope,
        SurfaceStoreKey.scopeFor(
            apiKey: 'rs_pk_test',
            environment: 'sandbox',
            baseUrl: 'https://example.com'));
  });
}

GeneratedPlacementDefinition _generatedOffer() =>
    RestagePaywall.generatedPlacementDefinition(
      id: 'original_offer',
      defaultSurfaceLocatorJson: DeliverySurfaceLocatorV1(
              surfaceType: DeliverySurfaceTypeId('paywall'),
              slug: 'original_offer',
              family: const DeliveryFamilySelectorV1.general())
          .toJson(),
      hostContractJson: SurfaceHostContractV1(
          hosting: const SurfaceHostingV1(
              contentKind: SurfaceContentKindV1.single,
              presentation: SurfacePresentationV1.inline),
          providedContext: const SurfaceScreenHostDataSchema.empty(),
          handledEvents: SurfaceScreenEventSchema(events: const [])).toJson(),
    );
