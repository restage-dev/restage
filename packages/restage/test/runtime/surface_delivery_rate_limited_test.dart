import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:restage/restage.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';

import '../surface_screen/surface_screen_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(Restage.debugReset);

  test('a configured runtime exposes a general-surface 429 while falling back',
      () async {
    Restage.configure(
      apiKey: 'rs_pk_test',
      baseUrl: 'https://surfaces.example.com',
      analyticsEnabled: false,
    );
    final events = <RestageEvent>[];
    final subscription = Restage.events.listen(events.add);
    addTearDown(subscription.cancel);
    final fixture = stringScreenFixture(
      surface: Surface.general,
      slug: 'feature_announcement',
    );
    final fallback = FixedBundledScreenResolver(fixture.bundled());
    final client = RestageRpcClient(
      baseUrl: 'https://surfaces.example.com',
      apiKey: 'rs_pk_test',
      httpClient: fixture.hostedDelivery.client(
        (_) async => http.Response(
          'not json',
          429,
          headers: {'Retry-After': '7'},
        ),
      ),
    );
    final resolver = RestageScreenResolver(
      apiKey: 'rs_pk_test',
      environment: RestageEnvironment.production,
      baseUrl: 'https://surfaces.example.com',
      assetFallback: fallback,
      rpcClientProvider: () => client,
    );

    final resolved = await resolver.resolve(fixture.ref);
    await Future<void>.delayed(Duration.zero);

    expect(resolved.origin, SurfaceScreenOrigin.bundled);
    expect(resolved.contentHash, fixture.contentHash);
    expect(fallback.calls, 1);
    expect(fixture.hostedDelivery.artifactRequests, isEmpty);
    final throttles = events.whereType<SurfaceDeliveryRateLimited>().toList();
    expect(throttles, hasLength(1));
    expect(throttles.single.surface, Surface.general);
    expect(throttles.single.surfaceId, 'feature_announcement');
    expect(throttles.single.retryAfter, const Duration(seconds: 7));
    expect(throttles.single.firedAt?.isUtc, isTrue);
  });
}
