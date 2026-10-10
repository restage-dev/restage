import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/main_hosted_surface_demo.dart';

/// De-risks the dev-only hosted-paywall demo entrypoint: the bundled
/// `narrate_membership.rfw`, re-packaged as a blob surface envelope and served by the
/// in-app [FakeSurfaceServer], resolves cleanly back through a real
/// [RestageVariantResolver] and decodes — so the self-contained `flutter run`
/// renders the hosted paywall rather than the fail-closed fallback.
void main() {
  setUp(Restage.debugReset);

  testWidgets(
      'the fake surface server delivers the bundled narrate_membership paywall',
      (tester) async {
    final envelope = await buildPaywallSurfaceEnvelope('narrate_membership');
    final resolver = RestageVariantResolver(
      apiKey: 'rs_pk_demo',
      environment: RestageEnvironment.sandbox,
      baseUrl: 'https://fake-surfaces.local',
      httpClient: FakeSurfaceServer(envelope),
    );

    final variant = await resolver.resolve('narrate_membership');

    // A successful resolve means the served envelope decoded, asserted a blob
    // payload, matched the requested identity, and passed the capability floor.
    // The returned bytes are the bundled `narrate_membership.rfw` (a paywall the
    // gallery test renders), so the demo renders it rather than failing closed.
    expect(variant.paywallId, 'narrate_membership');
    expect(variant.bytes, isNotEmpty);
    expect(variant.cacheHit, isFalse);

    final bundled =
        await const AssetVariantResolver().resolve('narrate_membership');
    expect(variant.bytes, bundled.bytes);
  });

  group('hostedSurfaceConfigurationProblem', () {
    String? problem({
      String baseUrl = '',
      String apiKey = '',
      String surfaceSlug = '',
      String surfaceType = 'paywall',
    }) =>
        hostedSurfaceConfigurationProblem(
          baseUrl: baseUrl,
          apiKey: apiKey,
          surfaceSlug: surfaceSlug,
          surfaceType: surfaceType,
        );

    test('accepts the self-contained default', () {
      expect(problem(), isNull);
    });

    test('accepts a backend paywall named by slug', () {
      expect(
        problem(
          baseUrl: 'https://backend.example',
          apiKey: 'rs_pk_sandbox_x',
          surfaceSlug: 'pulse_paywall',
        ),
        isNull,
      );
    });

    test('requires a key and a slug with a backend', () {
      expect(
        problem(baseUrl: 'https://backend.example', surfaceSlug: 'a'),
        contains('RESTAGE_API_KEY'),
      );
      expect(
        problem(baseUrl: 'https://backend.example', apiKey: 'rs_pk_x'),
        contains('RESTAGE_SURFACE'),
      );
    });

    test('names the known types for an unknown one', () {
      final message = problem(surfaceType: 'banner');
      expect(message, contains('"banner"'));
      expect(message, contains('paywall'));
      expect(message, contains('survey'));
    });

    test('points flow types at their generated mount', () {
      expect(problem(surfaceType: 'onboarding'), contains('generated'));
    });
  });
}
