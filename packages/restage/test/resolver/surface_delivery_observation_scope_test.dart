import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/src/resolver/restage_variant_resolver.dart';
import 'package:restage/src/resolver/surface_canonical_carrier_provider.dart';
import 'package:restage/src/resolver/surface_assignment_key_provider.dart';
import 'package:restage/src/resolver/surface_delivery_observations.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage/src/surface_screen/restage_surface_screen_resolver.dart';
import 'package:restage_shared/restage_shared.dart';

import '../support/hosted_artifact_delivery.dart';
import '../surface_screen/surface_screen_test_support.dart';
import 'package:restage/restage.dart' show SurfaceScreenOrigin;

SurfaceDeliveryObservations _snapshot({
  String? platform = 'ios',
  int build = 42,
  String country = 'SE',
}) =>
    SurfaceDeliveryObservations(
      presentationCountry: country,
      platform: platform,
      appBuildOrdinal: build,
      deviceClass: 'phone',
      sdkApiLevel: 3,
    );

Object? _document(Object? carrier) => jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(carrier as String))),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final delivery = HostedArtifactFixture();
  final ambient = base64UrlEncode(utf8.encode(
    '{"appBuildOrdinal":7,"country":"se","deviceClass":"phone","platform":"android","sdkApiLevel":3}',
  )).replaceAll('=', '');

  Map<String, Object?> body() => delivery.describeRaw(
        surfaceType: Surface.paywall,
        surfaceSlug: 'pro_upgrade',
        version: 1,
        publishedAt: DateTime.utc(2026),
        content: const [1, 2, 3],
      );

  RestageRpcClient clientFor(MockClient mock) => RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: mock,
      );

  tearDown(SurfaceCanonicalCarrierProvider.clear);
  tearDown(SurfaceAssignmentKeyProvider.clear);

  test('the presentation scope overrides the ambient observations', () async {
    SurfaceCanonicalCarrierProvider.installBuiltIns(() => ambient);
    late Map<String, dynamic> sent;
    final client = clientFor(delivery.client((request) async {
      sent = (jsonDecode(request.body) as Map).cast();
      return http.Response(jsonEncode(body()), 200);
    }));

    await withSurfaceDeliveryObservations(
      cell: SurfaceDeliveryObservationCell(() async => _snapshot()),
      resolve: () => client.fetchSurface(
        surfaceType: 'paywall',
        surfaceSlug: 'pro_upgrade',
      ),
    );

    expect(_document(sent['sdkBuiltInsCanonicalBase64']), {
      'appBuildOrdinal': 42,
      'country': 'se',
      'deviceClass': 'phone',
      'platform': 'ios',
      'sdkApiLevel': 3,
    });
  });

  test('requests outside a scope use the ambient provider', () async {
    SurfaceCanonicalCarrierProvider.installBuiltIns(() => ambient);
    late Map<String, dynamic> sent;
    final client = clientFor(delivery.client((request) async {
      sent = (jsonDecode(request.body) as Map).cast();
      return http.Response(jsonEncode(body()), 200);
    }));

    await client.fetchSurface(
      surfaceType: 'paywall',
      surfaceSlug: 'pro_upgrade',
    );

    expect(sent['sdkBuiltInsCanonicalBase64'], ambient);
  });

  test('an incomplete snapshot omits the carrier without consulting ambient',
      () async {
    var ambientCalls = 0;
    SurfaceCanonicalCarrierProvider.installBuiltIns(() {
      ambientCalls += 1;
      return ambient;
    });
    late Map<String, dynamic> sent;
    final client = clientFor(delivery.client((request) async {
      sent = (jsonDecode(request.body) as Map).cast();
      return http.Response(jsonEncode(body()), 200);
    }));

    await withSurfaceDeliveryObservations(
      cell:
          SurfaceDeliveryObservationCell(() async => _snapshot(platform: null)),
      resolve: () => client.fetchSurface(
        surfaceType: 'paywall',
        surfaceSlug: 'pro_upgrade',
      ),
    );

    expect((sent.containsKey('sdkBuiltInsCanonicalBase64'), ambientCalls),
        (false, 0));
  });

  test('repeated requests share one observation within a presentation',
      () async {
    SurfaceCanonicalCarrierProvider.installBuiltIns(() => ambient);
    var reads = 0;
    final cell = SurfaceDeliveryObservationCell(() async {
      reads += 1;
      return _snapshot(build: 42 + reads);
    });
    final sent = <Map<String, dynamic>>[];
    final client = clientFor(delivery.client((request) async {
      sent.add((jsonDecode(request.body) as Map).cast());
      return http.Response(jsonEncode(body()), 200);
    }));
    expect(reads, 0);
    expect(cell.valueIfRead, isNull);

    await withSurfaceDeliveryObservations(
      cell: cell,
      resolve: () async {
        for (var attempt = 0; attempt < 2; attempt++) {
          await client.fetchSurface(
            surfaceType: 'paywall',
            surfaceSlug: 'pro_upgrade',
          );
        }
      },
    );

    expect({
      'reads': reads,
      'carriers':
          sent.map((request) => request['sdkBuiltInsCanonicalBase64']).toList(),
    }, {
      'reads': 1,
      'carriers':
          List.filled(2, _snapshot(build: 43).canonicalBuiltInsBase64()),
    });
  });

  test('overlapping requests share one in-flight observation', () async {
    SurfaceCanonicalCarrierProvider.installBuiltIns(() => ambient);
    var reads = 0;
    final ready = Completer<SurfaceDeliveryObservations>();
    final cell = SurfaceDeliveryObservationCell(() {
      reads += 1;
      return ready.future;
    });
    final sent = <Map<String, dynamic>>[];
    final client = clientFor(delivery.client((request) async {
      sent.add((jsonDecode(request.body) as Map).cast());
      return http.Response(jsonEncode(body()), 200);
    }));
    final pending = withSurfaceDeliveryObservations(
      cell: cell,
      resolve: () {
        final first = client.fetchSurface(
            surfaceType: 'paywall', surfaceSlug: 'pro_upgrade');
        final second = client.fetchSurface(
            surfaceType: 'paywall', surfaceSlug: 'pro_upgrade');
        return Future.wait([first, second]);
      },
    );
    while (reads == 0) {
      await Future<void>.value();
    }
    expect(sent, isEmpty);
    ready.complete(_snapshot());
    await pending;
    expect(reads, 1);
    expect(sent, hasLength(2));
    expect(sent.map((request) => request['sdkBuiltInsCanonicalBase64']),
        everyElement(_snapshot().canonicalBuiltInsBase64()));
  });

  test('typed screen retries share one observation across all three leases',
      () async {
    SurfaceCanonicalCarrierProvider.installBuiltIns(() => ambient);
    var generation = 0;
    var keyCalls = 0;
    SurfaceAssignmentKeyProvider.install(
      key: () async {
        keyCalls += 1;
        return 'credential.screen.1';
      },
      identityGeneration: () => generation,
    );
    final fixture = stringScreenFixture();
    final sent = <Map<String, dynamic>>[];
    final client = clientFor(fixture.hostedDelivery.client((request) async {
      sent.add((jsonDecode(request.body) as Map).cast());
      // Drift the identity after the device has been read and the fetch made,
      // so the retry is forced past the read rather than before it.
      if (sent.length < 3) generation += 1;
      return http.Response(
        SurfaceScreenDeliveryDescriptorV1Codec.encodeCanonicalJson(
            fixture.delivery(hostedBlob: fixture.blob, publishedRevision: 8)),
        200,
      );
    }));
    var reads = 0;
    final resolved = await withSurfaceDeliveryObservations(
      cell: SurfaceDeliveryObservationCell(() async {
        reads += 1;
        return _snapshot();
      }),
      resolve: () => RestageScreenResolver(
        apiKey: 'rs_pk_test',
        environment: RestageEnvironment.values.first,
        rpcClientProvider: () => client,
      ).resolve(fixture.ref),
    );
    expect(resolved.origin, SurfaceScreenOrigin.hosted);
    expect(keyCalls, 3);
    expect(sent, hasLength(3));
    expect(reads, 1);
    expect(
      sent.map((body) => body['sdkBuiltInsCanonicalBase64']).toSet(),
      hasLength(1),
    );
  });

  test('a presentation with no observation source never reads the device',
      () async {
    var reads = 0;
    final cell = SurfaceDeliveryObservationCell(() async {
      reads += 1;
      return _snapshot();
    });
    late Map<String, dynamic> sent;
    final client = clientFor(delivery.client((request) async {
      sent = (jsonDecode(request.body) as Map).cast();
      return http.Response(jsonEncode(body()), 200);
    }));

    await withSurfaceDeliveryObservations(
      cell: cell,
      resolve: () => client.fetchSurface(
        surfaceType: 'paywall',
        surfaceSlug: 'pro_upgrade',
      ),
    );

    expect(sent.containsKey('sdkBuiltInsCanonicalBase64'), isFalse);
    expect(reads, 0);
  });

  test('no request and no measurement registration means zero reads', () {
    var reads = 0;
    final cell = SurfaceDeliveryObservationCell(() async {
      reads += 1;
      return _snapshot();
    });

    withSurfaceDeliveryObservations(
      cell: cell,
      resolve: () {},
    );

    expect(reads, 0);
    expect(cell.valueIfRead, isNull);
  });

  test('a new presentation observes changed country and build values',
      () async {
    SurfaceCanonicalCarrierProvider.installBuiltIns(() => ambient);
    final sent = <Map<String, dynamic>>[];
    final client = clientFor(delivery.client((request) async {
      sent.add((jsonDecode(request.body) as Map).cast());
      return http.Response(jsonEncode(body()), 200);
    }));
    final first = _snapshot();
    await withSurfaceDeliveryObservations(
      cell: SurfaceDeliveryObservationCell(() async => first),
      resolve: () => client.fetchSurface(
        surfaceType: 'paywall',
        surfaceSlug: 'pro_upgrade',
      ),
    );
    final second = _snapshot(country: 'DE', build: 43);
    await withSurfaceDeliveryObservations(
      cell: SurfaceDeliveryObservationCell(() async => second),
      resolve: () => client.fetchSurface(
        surfaceType: 'paywall',
        surfaceSlug: 'pro_upgrade',
      ),
    );

    expect({
      'countries': [first.presentationCountry, second.presentationCountry],
      'documents': sent
          .map((request) => _document(request['sdkBuiltInsCanonicalBase64']))
          .toList(),
      'carriersDiffer': sent[0]['sdkBuiltInsCanonicalBase64'] !=
          sent[1]['sdkBuiltInsCanonicalBase64'],
    }, {
      'countries': ['SE', 'DE'],
      'documents': [
        {
          'appBuildOrdinal': 42,
          'country': 'se',
          'deviceClass': 'phone',
          'platform': 'ios',
          'sdkApiLevel': 3
        },
        {
          'appBuildOrdinal': 43,
          'country': 'de',
          'deviceClass': 'phone',
          'platform': 'ios',
          'sdkApiLevel': 3
        },
      ],
      'carriersDiffer': true,
    });
  });

  test('typed screen resolutions share the scoped carrier across async calls',
      () async {
    final fixture = stringScreenFixture();
    final surfaceRequests = <Map<String, dynamic>>[];
    var ambientCalls = 0;
    SurfaceCanonicalCarrierProvider.installBuiltIns(() {
      ambientCalls += 1;
      return ambient;
    });
    final client = clientFor(fixture.hostedDelivery.client((request) async {
      surfaceRequests.add((jsonDecode(request.body) as Map).cast());
      return http.Response(
        SurfaceScreenDeliveryDescriptorV1Codec.encodeCanonicalJson(
          fixture.delivery(hostedBlob: fixture.blob, publishedRevision: 8),
        ),
        200,
      );
    }));
    final observations = _snapshot();

    await withSurfaceDeliveryObservations(
      cell: SurfaceDeliveryObservationCell(() async => observations),
      resolve: () async {
        for (var attempt = 0; attempt < 2; attempt++) {
          final resolver = RestageScreenResolver(
            apiKey: 'rs_pk_test',
            environment: RestageEnvironment.values.first,
            rpcClientProvider: () => client,
          );
          await resolver.resolve(fixture.ref);
        }
      },
    );

    expect({
      'ambientCalls': ambientCalls,
      'carriers': surfaceRequests
          .map((request) => request['sdkBuiltInsCanonicalBase64'])
          .toList(),
    }, {
      'ambientCalls': 0,
      'carriers': List.filled(2, observations.canonicalBuiltInsBase64()),
    });
  });
}
