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
      );

      expect(EntitlementSummary.fromJson(summary.toJson()), summary);
    });

    test('JSON round-trips nullable expiry', () {
      final summary = EntitlementSummary(
        entitlementId: 'lifetime',
        status: 'active',
        productId: 'lifetime',
        source: 'storeNotification',
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
      });

      expect(summary.status, 'unknown');
      expect(summary.source, 'unknown');
      expect(summary.isEntitled, isFalse);
    });

    test('constructor throws ArgumentError on an unknown status', () {
      expect(
        () => EntitlementSummary(
          entitlementId: 'pro',
          status: 'bogus',
          productId: 'premium.monthly',
          source: 'clientReport',
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
        }),
        returnsNormally,
      );
    });
  });
}
