import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  group('EntitlementSyncResponse', () {
    test('JSON round-trips with multiple entitlement summaries', () {
      final response = EntitlementSyncResponse(
        entitlements: [
          EntitlementSummary(
            entitlementId: 'pro',
            status: 'active',
            productId: 'monthly',
            source: 'storeNotification',
            expiresAtMs: 1234567890,
          ),
          EntitlementSummary(
            entitlementId: 'premium',
            status: 'expired',
            productId: 'annual',
            source: 'clientReport',
          ),
        ],
      );

      final json = response.toJson();
      final parsed = EntitlementSyncResponse.fromJson(json);

      expect(parsed, response);
    });

    test('JSON serializes an empty entitlements list explicitly', () {
      final response = EntitlementSyncResponse();

      final json = response.toJson();

      expect(json['entitlements'], isEmpty);
      expect(EntitlementSyncResponse.fromJson(json), response);
    });

    test('fromJson treats a missing entitlements key as empty', () {
      final parsed = EntitlementSyncResponse.fromJson(const {});

      expect(parsed.entitlements, isEmpty);
    });

    test('fromJson rejects a non-list entitlements value', () {
      expect(
        () => EntitlementSyncResponse.fromJson(const {'entitlements': 'pro'}),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('fromJson rejects an entry that is not a map', () {
      expect(
        () => EntitlementSyncResponse.fromJson(const {
          'entitlements': [
            {
              'entitlementId': 'pro',
              'status': 'active',
              'productId': 'monthly',
              'source': 'clientReport',
            },
            'not-an-object',
          ],
        }),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('graceful-unknown status propagates through inner summary parsing',
        () {
      final parsed = EntitlementSyncResponse.fromJson(const {
        'entitlements': [
          {
            'entitlementId': 'pro',
            'status': 'something-the-sdk-does-not-yet-know',
            'productId': 'monthly',
            'source': 'storeNotification',
          },
        ],
      });

      expect(parsed.entitlements, hasLength(1));
      expect(parsed.entitlements.first.status, 'unknown');
      expect(parsed.entitlements.first.isEntitled, isFalse);
    });

    test('value equality differs when entitlement order differs', () {
      final a = EntitlementSyncResponse(
        entitlements: [
          EntitlementSummary(
            entitlementId: 'pro',
            status: 'active',
            productId: 'm',
            source: 'clientReport',
          ),
          EntitlementSummary(
            entitlementId: 'premium',
            status: 'active',
            productId: 'a',
            source: 'clientReport',
          ),
        ],
      );
      final b = EntitlementSyncResponse(
        entitlements: [
          EntitlementSummary(
            entitlementId: 'premium',
            status: 'active',
            productId: 'a',
            source: 'clientReport',
          ),
          EntitlementSummary(
            entitlementId: 'pro',
            status: 'active',
            productId: 'm',
            source: 'clientReport',
          ),
        ],
      );

      expect(a, isNot(b));
    });

    test('primary constructor stores an unmodifiable entitlements list', () {
      final list = [
        EntitlementSummary(
          entitlementId: 'pro',
          status: 'active',
          productId: 'm',
          source: 'clientReport',
        ),
      ];
      final response = EntitlementSyncResponse(entitlements: list);
      expect(
        () => response.entitlements.add(
          EntitlementSummary(
            entitlementId: 'x',
            status: 'active',
            productId: 'y',
            source: 'clientReport',
          ),
        ),
        throwsUnsupportedError,
      );
    });
  });
}
