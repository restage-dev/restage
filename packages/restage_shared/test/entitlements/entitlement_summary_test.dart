import 'package:restage_shared/src/entitlements/entitlements.dart';
import 'package:test/test.dart';

void main() {
  group('EntitlementSummary', () {
    test('JSON round-trips all fields', () {
      final summary = EntitlementSummary(
        entitlementId: 'pro',
        status: 'active',
        expiresAtMs: 1781870400000,
        productId: 'premium.monthly',
        source: 'clientReport',
        providerEnvironment: 'sandbox',
      );

      expect(EntitlementSummary.fromJson(summary.toJson()), summary);
    });

    test('JSON round-trips nullable expiry', () {
      final summary = EntitlementSummary(
        entitlementId: 'lifetime',
        status: 'active',
        productId: 'lifetime',
        source: 'storeNotification',
        providerEnvironment: 'production',
      );

      final json = summary.toJson();

      expect(json, isNot(contains('expiresAtMs')));
      expect(EntitlementSummary.fromJson(json), summary);
    });

    test('maps unknown server values to unknown and not entitled', () {
      final summary = EntitlementSummary.fromJson(const {
        'entitlementId': 'pro',
        'status': 'inGracePeriod',
        'productId': 'premium.monthly',
        'source': 'serverNotification',
        'providerEnvironment': 'production',
      });

      expect(summary.status, 'unknown');
      expect(summary.source, 'unknown');
      expect(summary.providerEnvironment, 'production');
      expect(summary.isEntitled, isFalse);
    });

    test('constructor throws ArgumentError on an unknown status', () {
      expect(
        () => EntitlementSummary(
          entitlementId: 'pro',
          status: 'bogus',
          productId: 'premium.monthly',
          source: 'clientReport',
          providerEnvironment: 'production',
        ),
        throwsArgumentError,
      );
    });

    test('constructor throws ArgumentError on an unknown source', () {
      expect(
        () => EntitlementSummary(
          entitlementId: 'pro',
          status: 'active',
          productId: 'premium.monthly',
          source: 'bogus',
          providerEnvironment: 'production',
        ),
        throwsArgumentError,
      );
    });

    test('fromJson stays graceful on an unknown status (does not throw)', () {
      // The wire/decode path must keep degrading an unknown future status to
      // 'unknown' rather than throwing — only direct construction fails loud.
      expect(
        () => EntitlementSummary.fromJson(const {
          'entitlementId': 'pro',
          'status': 'something-newer-than-this-sdk',
          'productId': 'premium.monthly',
          'source': 'clientReport',
          'providerEnvironment': 'production',
        }),
        returnsNormally,
      );
    });

    test('JSON requires a verified provider environment', () {
      const json = {
        'entitlementId': 'pro',
        'status': 'active',
        'productId': 'pro.monthly',
        'source': 'clientReport',
      };
      expect(
        () => EntitlementSummary.fromJson(json),
        throwsArgumentError,
      );
      for (final environment in [
        null,
        'unknown',
        'future-environment',
        '',
        1,
      ]) {
        expect(
          () => EntitlementSummary.fromJson({
            ...json,
            'providerEnvironment': environment,
          }),
          throwsArgumentError,
          reason: 'providerEnvironment: $environment',
        );
      }
    });

    test('provider environment participates in state identity', () {
      EntitlementSummary summary(String environment) => EntitlementSummary(
            entitlementId: 'pro',
            status: 'active',
            productId: 'pro.monthly',
            source: 'clientReport',
            providerEnvironment: environment,
          );
      expect(summary('sandbox'), isNot(summary('production')));
      expect(
        EntitlementSummary.fromJson(summary('production').toJson()),
        summary('production'),
      );
      for (final environment in ['unknown', 'unverified']) {
        expect(() => summary(environment), throwsArgumentError);
      }
    });
  });
}
