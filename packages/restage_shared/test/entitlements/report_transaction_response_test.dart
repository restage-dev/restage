import 'package:restage_shared/commerce.dart';
import 'package:test/test.dart';

void main() {
  group('CommerceReportResponse', () {
    test('round-trips ordinary and verified purchase state', () {
      final response = CommerceReportResponse(
        outcome: 'verified',
        purchaserState: CommercePurchaserStateResponse(
          status: 'current',
          entitlements: [
            EntitlementSummary(
              entitlementId: 'pro',
              status: 'active',
              productId: 'pro.monthly.us',
              source: 'clientReport',
              providerEnvironment: 'production',
            ),
          ],
          retrievedAt: DateTime.utc(2026, 9, 5, 12),
        ),
        verifiedPurchaseState: CommercePurchaserStateResponse(
          status: 'current',
          entitlements: [
            EntitlementSummary(
              entitlementId: 'purchase-pro',
              status: 'active',
              productId: 'pro.monthly.us',
              source: 'clientReport',
              providerEnvironment: 'production',
            ),
          ],
          retrievedAt: DateTime.utc(2026, 9, 5, 12),
        ),
      );

      expect(CommerceReportResponse.fromJson(response.toJson()), response);
    });

    test('keeps verified purchase state absent when proof is unavailable', () {
      final response = CommerceReportResponse(
        outcome: 'pending',
        purchaserState: CommercePurchaserStateResponse(
          status: 'current',
          entitlements: const [],
          retrievedAt: DateTime.utc(2026, 9, 5, 12),
        ),
      );

      expect(response.toJson(), isNot(contains('verifiedPurchaseState')));
      expect(
        CommerceReportResponse.fromJson(response.toJson())
            .verifiedPurchaseState,
        isNull,
      );
    });

    test(
        'groups same-product occurrences and retains explicit empty revocation',
        () {
      final order =
          DateTime.utc(2026, 10, 20, 12, 0, 0, 0, 7).microsecondsSinceEpoch;
      final granted = CommerceVerifiedPurchase(
        storeTransactionId: 'receipt-a',
        productId: 'window',
        providerEnvironment: 'sandbox',
        kind: 'oneTimePurchase',
        outcome: 'granted',
        outcomeOrder: order,
        entitlements: const [],
        expiresAtMs: 1800000000000,
        fulfillments: [
          CommerceFulfillmentSummary(
              id: 'line-a',
              productId: 'window',
              quantity: 7,
              providerEnvironment: 'sandbox'),
          CommerceFulfillmentSummary(
              id: 'line-b',
              productId: 'window',
              quantity: 2,
              providerEnvironment: 'sandbox'),
        ],
      );
      final revoked = CommerceVerifiedPurchase(
        storeTransactionId: 'receipt-b',
        productId: 'window',
        providerEnvironment: 'sandbox',
        kind: 'oneTimePurchase',
        outcome: 'revoked',
        outcomeOrder: order + 1,
        entitlements: const [],
        fulfillments: const [],
      );
      final response = CommerceReportResponse(
        outcome: 'verified',
        purchaserState: CommercePurchaserStateResponse(
            status: 'current',
            entitlements: const [],
            retrievedAt: DateTime.utc(2026, 10, 20)),
        verifiedPurchases: [granted, revoked],
      );
      final decoded = CommerceReportResponse.fromJson(response.toJson());
      expect(decoded, response);
      expect(decoded.hashCode, response.hashCode);
      expect(decoded.verifiedPurchases!.map((e) => e.storeTransactionId),
          ['receipt-a', 'receipt-b']);
      expect(
          decoded.verifiedPurchases!.first.fulfillments.map((e) => e.quantity),
          [7, 2]);
      expect(decoded.verifiedPurchases!.first.expiresAtMs, 1800000000000);
      expect(decoded.verifiedPurchases!.map((e) => e.outcomeOrder),
          [order, order + 1]);
      final later = CommerceVerifiedPurchase.fromJson(
          {...granted.toJson(), 'outcomeOrder': order + 1});
      expect(later, isNot(granted));
      expect(decoded.verifiedPurchases!.last.outcome, 'revoked');
      expect(decoded.verifiedPurchases!.last.fulfillments, isEmpty);
      expect(() => decoded.verifiedPurchases!.clear(), throwsUnsupportedError);
      expect(() => decoded.verifiedPurchases!.first.fulfillments.clear(),
          throwsUnsupportedError);
    });

    test('distinguishes unavailable grouping from an explicit empty list', () {
      final state = CommercePurchaserStateResponse(
          status: 'current',
          entitlements: const [],
          retrievedAt: DateTime.utc(2026, 10, 20));
      final absent =
          CommerceReportResponse(outcome: 'verified', purchaserState: state);
      expect(absent.toJson(), isNot(contains('verifiedPurchases')));
      expect(
          CommerceReportResponse.fromJson(
                  {...absent.toJson(), 'verifiedPurchases': null})
              .verifiedPurchases,
          isNull);
      final empty = CommerceReportResponse(
          outcome: 'verified',
          purchaserState: state,
          verifiedPurchases: const []);
      expect(CommerceReportResponse.fromJson(empty.toJson()).verifiedPurchases,
          isEmpty);
      expect(empty, isNot(absent));
      for (final value in [
        1,
        'bad',
        <String, dynamic>{},
        [null]
      ]) {
        expect(
            () => CommerceReportResponse.fromJson(
                {...absent.toJson(), 'verifiedPurchases': value}),
            throwsArgumentError);
      }
    });

    test('requires exact scope, retained order, and closed grant outcomes', () {
      final valid = CommerceVerifiedPurchase(
        storeTransactionId: 'receipt',
        productId: 'window',
        providerEnvironment: 'production',
        kind: 'oneTimePurchase',
        outcome: 'expired',
        outcomeOrder: DateTime.utc(2026, 10, 20).microsecondsSinceEpoch,
        entitlements: const [],
      ).toJson();
      final missingOrder = {...valid}..remove('outcomeOrder');
      expect(() => CommerceVerifiedPurchase.fromJson(missingOrder),
          throwsArgumentError);
      for (final value in [null, 0, -1, '1', 1.5, true]) {
        expect(
            () => CommerceVerifiedPurchase.fromJson(
                {...valid, 'outcomeOrder': value}),
            throwsArgumentError);
      }
      expect(
          () => CommerceVerifiedPurchase.fromJson(
              {...valid, 'kind': 'subscription', 'outcome': 'unknown'}),
          throwsArgumentError);
      for (final edit in [
        {'providerEnvironment': null},
        {'providerEnvironment': 'unknown'},
        {'outcome': 'unknown'},
        {'outcome': 'pending'},
        {'kind': 'other'},
        {'storeTransactionId': ''},
      ]) {
        expect(() => CommerceVerifiedPurchase.fromJson({...valid, ...edit}),
            throwsArgumentError);
      }
      expect(
          CommerceVerifiedPurchase.fromJson({
            ...valid,
            'kind': 'subscription',
            'outcome': 'unknown',
            'outcomeOrder': null,
          }).entitlements,
          isEmpty);
      final active = CommerceFulfillmentSummary(
          id: 'line',
          productId: 'window',
          quantity: 1,
          providerEnvironment: 'production');
      expect(
          () => CommerceVerifiedPurchase.fromJson({
                ...valid,
                'fulfillments': [active.toJson()]
              }),
          throwsArgumentError);
      expect(
          () => CommerceVerifiedPurchase.fromJson({
                ...valid,
                'kind': 'subscription',
                'outcome': 'granted',
                'outcomeOrder': null,
                'fulfillments': [active.toJson()]
              }),
          throwsArgumentError);
    });

    test('restore truncation is additive, strict, and part of value equality',
        () {
      final state = CommercePurchaserStateResponse(
        status: 'current',
        entitlements: const [],
        retrievedAt: DateTime.utc(2026, 10, 21),
      );
      final complete =
          CommerceReportResponse(outcome: 'verified', purchaserState: state);
      expect(complete.restoreHistoryTruncated, isFalse);
      expect(complete.toJson(), isNot(contains('restoreHistoryTruncated')));
      final truncated = CommerceReportResponse(
        outcome: 'verified',
        purchaserState: state,
        restoreHistoryTruncated: true,
      );
      final decoded = CommerceReportResponse.fromJson(truncated.toJson());
      expect(decoded.restoreHistoryTruncated, isTrue);
      expect(decoded, truncated);
      expect(decoded.hashCode, truncated.hashCode);
      expect(decoded, isNot(complete));
      expect(
          CommerceReportResponse.fromJson(
              {...complete.toJson(), 'restoreHistoryTruncated': false}),
          complete);
      for (final value in [null, 0, 1, 'true', <String, dynamic>{}]) {
        expect(
            () => CommerceReportResponse.fromJson(
                {...complete.toJson(), 'restoreHistoryTruncated': value}),
            throwsArgumentError);
      }
    });

    test('normalizes an unknown response outcome', () {
      final response = CommerceReportResponse.fromJson(
        const <String, dynamic>{
          'outcome': 'settled_later',
          'purchaserState': <String, dynamic>{
            'status': 'current',
            'entitlements': <dynamic>[],
            'retrievedAt': '2026-09-05T12:00:00.000Z',
          },
        },
      );

      expect(response.outcome, 'unknown');
    });
  });
}
