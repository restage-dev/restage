import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show StringCodec;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/delivery/surface_artifact_store.dart';
import 'package:restage/src/resolver/surface_delivery_observations.dart';
import 'package:restage/src/resolver/surface_metering_key_provider.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/placement_delivery_fixture.dart';
import '../surface_screen/surface_screen_test_support.dart';

void main() {
  for (final late in [false, true]) {
    testWidgets(
        late
            ? 'a fallback arriving after the original paint watches its placement'
            : 'an unhosted default watches its placement and adopts a push',
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
          slug: 'original_notice',
          schema: SurfaceScreenEventSchema(events: []));
      final bundleBytes = original.bundleBytes();
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMessageHandler('flutter/assets', (message) async {
        if (const StringCodec().decodeMessage(message) !=
            original.locator.assetKey) {
          return null;
        }
        return ByteData.sublistView(bundleBytes);
      });
      addTearDown(
          () => messenger.setMockMessageHandler('flutter/assets', null));
      final channel = _PushChannel();
      Restage.configure(
          apiKey: 'rs_pk_test',
          baseUrl: 'https://example.com',
          analyticsEnabled: false,
          measurementEnabled: false,
          deliveryReceiptsEnabled: false,
          liveRefresh: {SurfaceRefreshTrigger.updateChannel},
          updateChannel: channel);
      debugResetInstallObservations();
      debugSetOsVersion(19);
      SurfaceMeteringKeyProvider.clear();
      Restage.debugPlacementNow = () => DateTime.utc(2026, 10, 4, 12);
      final fixture = readPlacementDeliveryFixture();
      var hosted = false;
      final requests = <PlacementBatchRequestV1>[];
      final answer = Completer<void>();
      if (!late) answer.complete();
      final client = RestageRpcClient(
          baseUrl: 'https://example.com',
          apiKey: 'rs_pk_test',
          httpClient: MockClient((outgoing) async {
            final request =
                PlacementBatchRequestV1.fromCanonicalBytes(outgoing.bodyBytes);
            requests.add(request);
            await answer.future;
            if (hosted) {
              return http.Response.bytes(
                  placementFixtureResponse(request,
                          family: DeliveryFamilySelectorV1.screenContract(
                              contractVersion: 7))
                      .canonicalBytes,
                  200);
            }
            final mount = request.mounts.single;
            final descriptor = PlacementMountDescriptorV1(
                placement:
                    PlacementIdentityV1(target: fixture.target, key: mount.key),
                hostContractHash: mount.hostContractHash);
            final scope = DeliveryPolicyScopeV1(
                root: DeliveryRootIdentityV1.placement(descriptor.placement),
                family: const DeliveryFamilySelectorV1.none());
            return http.Response.bytes(
                PlacementBatchResolvedV1(
                    request: request,
                    expectedTarget: fixture.target,
                    decisions: [
                      PlacementBatchEntryV1.useFallback(descriptor,
                          PlacementBatchRefusalReasonV1.unavailable, const [],
                          watch: PlacementDeliveryWatchV1(
                              decisionIdentityDigest: CanonicalDigest('f' * 64),
                              channels: [
                                PlacementDeliveryWatchChannelV1(
                                    scope: scope, token: _watchToken)
                              ]))
                    ],
                    artifacts: const []).canonicalBytes,
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
          hostContract:
              fixture.request.buildContract.contractsByHash.values.first,
          vocabulary: SurfaceVocabulary.none);
      try {
        await tester.pumpWidget(MaterialApp(
            home: RestageScreen(
                screen: original.ref,
                placementBinding:
                    PlacementMountBinding(definition: () => definition),
                unavailable: const SurfaceScreenUnavailablePolicy.hide())));
        await _finishScreenFrames(tester);
        if (late) {
          await tester.pump(const Duration(milliseconds: 400));
          expect(find.text('Bundled screen'), findsOneWidget);
          answer.complete();
          await _finishScreenFrames(tester);
        }
        expect(find.text('Bundled screen'), findsOneWidget);
        expect(requests, hasLength(1));
        final scope = channel.controllers.keys.single;
        expect(scope.root.placement!.key, definition.key);

        hosted = true;
        channel.controllers[scope]!.add(scope);
        await _finishScreenFrames(tester);
        expect(requests, hasLength(2));
        expect(find.text('Welcome'), findsOneWidget);
        expect(find.text('Bundled screen'), findsNothing);
      } finally {
        await tester.pumpWidget(const SizedBox());
      }
    });
  }
}

Future<void> _finishScreenFrames(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

const _watchToken =
    'v2.i5p7lxR3.1767229200.NDI6b25ib2FyZGluZzp3ZWxjb21lLWZsb3c.'
    'kV0gFtXCrtsWdYcIFXaVNEQDQFjXwvrEn4t_WY_KX44';

final class _PushChannel implements DeliveryUpdateChannel {
  final controllers =
      <DeliveryPolicyScopeV1, StreamController<DeliveryPolicyScopeV1>>{};
  @override
  Stream<SurfaceUpdate> watch(SurfaceRef surface) => const Stream.empty();
  @override
  Stream<DeliveryPolicyScopeV1> watchDelivery(DeliveryPolicyScopeV1 scope,
          {PlacementDeliveryWatchV1? watch,
          Future<PlacementRefreshProbeV1> Function()? reconnectProbe}) =>
      (controllers[scope] ??= StreamController.broadcast()).stream;
}
