import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:restage/src/measurement/measurement_resolved_publication_provenance.dart';

import 'package:restage/src/resolver/restage_variant_resolver.dart';
import 'package:restage/src/resolver/surface_resolution_report.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage/src/surface_screen/restage_surface_screen_resolver.dart';
import 'package:restage/src/surface_screen/surface_screen_types.dart';

import '../support/hosted_artifact_delivery.dart';
import '../surface_screen/surface_screen_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(resetSurfaceScreenTestState);
  tearDown(resetSurfaceScreenTestState);

  const receipt = '  opaque.receipt+/= 雪  ';
  final cases = <String, Object?>{
    'an exact receipt': receipt,
    'no receipt member': null,
    'a non-string receipt': 42,
    'an oversized receipt': 'x' * 4097,
  };

  for (final entry in cases.entries) {
    test('variant delivery succeeds with ${entry.key}', () async {
      final delivery = HostedArtifactFixture();
      final blob = rfwScreenBlob(text: 'Hosted paywall', event: 'tap');
      final body = delivery.deliveryBody(
        testBlobDocument(blob, version: 7),
        extra: {
          if (entry.value != null) 'routingSelectionReceipt': entry.value,
        },
      );
      final resolver = RestageVariantResolver(
        apiKey: 'rs_pk_test',
        environment: RestageEnvironment.sandbox,
        baseUrl: 'https://example.com',
        httpClient: delivery.client((request) async {
          expect(request.url.path, '/sdk/v1/surface');
          return http.Response.bytes(
            utf8.encode(jsonEncode(body)),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final resolved = await resolver.resolve('pro_upgrade');

      expect(resolved.bytes, orderedEquals(blob));
      expect(resolved.paywallPublishedVersion, 7);
      expect(resolved.cacheHit, isFalse);
      expect(
        routingSelectionReceiptFor(resolved),
        entry.value == receipt ? receipt : isNull,
      );
      expect(delivery.artifactRequests, hasLength(1));
    });

    test('typed screen delivery succeeds with ${entry.key}', () async {
      final fixture = stringScreenFixture();
      final body = <String, Object?>{
        ...fixture.delivery().toJson(),
        if (entry.value != null) 'routingSelectionReceipt': entry.value,
      };
      final fallback = AbsentBundledScreenResolver();
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: fixture.hostedDelivery.client((request) async {
          expect(request.url.path, '/sdk/v1/surface');
          return http.Response.bytes(
            utf8.encode(jsonEncode(body)),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final resolver = RestageScreenResolver(
        apiKey: 'rs_pk_test',
        environment: RestageEnvironment.sandbox,
        assetFallback: fallback,
        rpcClientProvider: () => client,
      );

      final resolved = await resolver.resolve(fixture.ref);

      expect(resolved.origin, SurfaceScreenOrigin.hosted);
      expect(resolved.blob, orderedEquals(fixture.blob));
      expect(resolved.publishedRevision, 7);
      expect(resolved.cacheHit, isFalse);
      expect(
        routingSelectionReceiptFor(resolved),
        entry.value == receipt ? receipt : isNull,
      );
      expect(fallback.calls, 0);
      expect(fixture.hostedDelivery.artifactRequests, hasLength(1));
    });
  }

  test('variant cache hit keeps the exact receipt', () async {
    final delivery = HostedArtifactFixture();
    final blob = rfwScreenBlob(text: 'Hosted paywall', event: 'tap');
    final body = delivery.deliveryBody(
      testBlobDocument(blob, version: 7),
      extra: {'routingSelectionReceipt': receipt},
    );
    var deliveryCalls = 0;
    final resolver = RestageVariantResolver(
      apiKey: 'rs_pk_test',
      environment: RestageEnvironment.sandbox,
      baseUrl: 'https://example.com',
      httpClient: delivery.client((request) async {
        expect(request.url.path, '/sdk/v1/surface');
        deliveryCalls++;
        return deliveryCalls == 1
            ? http.Response.bytes(
                utf8.encode(jsonEncode(body)),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              )
            : http.Response('', 503);
      }),
    );

    final first = await resolver.resolve('pro_upgrade');
    final second = await resolver.resolve('pro_upgrade');

    expect(deliveryCalls, 2);
    expect(first.cacheHit, isFalse);
    expect(second.cacheHit, isTrue);
    expect(second.bytes, orderedEquals(blob));
    expect(second.paywallPublishedVersion, 7);
    expect(routingSelectionReceiptFor(first), receipt);
    expect(
        routingSelectionReceiptFor(second), routingSelectionReceiptFor(first));
    expect(delivery.artifactRequests, hasLength(1));
  });

  for (final failSecond in [false, true]) {
    test(
        'typed screen decides again and preserves the selected receipt on failure=$failSecond',
        () async {
      final fixture = stringScreenFixture();
      final body = <String, Object?>{
        ...fixture.delivery().toJson(),
        'routingSelectionReceipt': receipt,
      };
      var deliveryCalls = 0;
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: fixture.hostedDelivery.client((request) async {
          expect(request.url.path, '/sdk/v1/surface');
          deliveryCalls++;
          if (deliveryCalls == 2 && failSecond) return http.Response('', 503);
          body['routingSelectionReceipt'] =
              deliveryCalls == 1 ? receipt : 'second';
          return http.Response.bytes(
            utf8.encode(jsonEncode(body)),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final resolver = RestageScreenResolver(
        apiKey: 'rs_pk_test',
        environment: RestageEnvironment.sandbox,
        assetFallback: AbsentBundledScreenResolver(),
        rpcClientProvider: () => client,
      );

      final first = await resolver.resolve(fixture.ref);
      final second = await resolver.resolve(fixture.ref);

      expect(deliveryCalls, 2);
      expect(first.origin, SurfaceScreenOrigin.hosted);
      expect(second.origin, SurfaceScreenOrigin.hosted);
      expect(first.cacheHit, isFalse);
      expect(second.cacheHit, failSecond);
      expect(second.blob, orderedEquals(fixture.blob));
      expect(second.publishedRevision, 7);
      expect(routingSelectionReceiptFor(first), receipt);
      expect(
          routingSelectionReceiptFor(second), failSecond ? receipt : 'second');
      expect(
          surfaceResolutionSourceFor(second),
          failSecond
              ? SurfaceResolutionSource.holdLastGood
              : SurfaceResolutionSource.fresh);
      expect(fixture.hostedDelivery.artifactRequests, hasLength(1));
    });
  }

  test('the same receipt can be attached twice but a rebind throws', () {
    final resolved = Object();
    const receipt = 'opaque receipt';
    attachMeasurementPublicationBindingReference(
      resolved,
      null,
      routingSelectionReceipt: receipt,
    );
    expect(
      () => attachMeasurementPublicationBindingReference(
        resolved,
        null,
        routingSelectionReceipt: receipt,
      ),
      returnsNormally,
    );
    expect(
      () => attachMeasurementPublicationBindingReference(
        resolved,
        null,
        routingSelectionReceipt: 'different opaque receipt',
      ),
      throwsStateError,
    );
    expect(routingSelectionReceiptFor(resolved), receipt);
  });
}
