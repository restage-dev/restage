import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Restage.debugReset();
  });

  group('Restage.debugReconcileFromServer transition matrix', () {
    late List<RestageEvent> received;

    setUp(() {
      received = <RestageEvent>[];
      Restage.events.listen(received.add);
    });

    test('first sync, server has active → EntitlementGranted + adds to set',
        () async {
      Restage.debugReconcileFromServer([
        EntitlementSummary(
          entitlementId: 'pro',
          status: 'active',
          productId: 'monthly',
          source: 'clientReport',
          expiresAtMs: 100,
        ),
      ]);
      await pumpEventQueue();

      expect(received, hasLength(1));
      expect(received.single, isA<EntitlementGranted>());
      final granted = received.single as EntitlementGranted;
      expect(granted.entitlementId, 'pro');
      expect(granted.productId, 'monthly');
      expect(granted.expiresAtMs, 100);
      expect(Restage.currentEntitlements.map((e) => e.id), contains('pro'));
    });

    test('first sync, server has expired → no event, not in set', () async {
      Restage.debugReconcileFromServer([
        EntitlementSummary(
          entitlementId: 'pro',
          status: 'expired',
          productId: 'monthly',
          source: 'storeNotification',
        ),
      ]);
      await pumpEventQueue();

      expect(received, isEmpty);
      expect(Restage.currentEntitlements, isEmpty);
    });

    test('second sync, same active state with same expiry → no event',
        () async {
      Restage.debugReconcileFromServer([
        EntitlementSummary(
          entitlementId: 'pro',
          status: 'active',
          productId: 'monthly',
          source: 'clientReport',
          expiresAtMs: 100,
        ),
      ]);
      await pumpEventQueue();
      received.clear();

      Restage.debugReconcileFromServer([
        EntitlementSummary(
          entitlementId: 'pro',
          status: 'active',
          productId: 'monthly',
          source: 'clientReport',
          expiresAtMs: 100,
        ),
      ]);
      await pumpEventQueue();

      expect(received, isEmpty);
      expect(Restage.currentEntitlements.map((e) => e.id), contains('pro'));
    });

    test(
        'second sync, active with later expiry (auto-renewal) → SubscriptionRenewed',
        () async {
      Restage.debugReconcileFromServer([
        EntitlementSummary(
          entitlementId: 'pro',
          status: 'active',
          productId: 'monthly',
          source: 'clientReport',
          expiresAtMs: 100,
        ),
      ]);
      await pumpEventQueue();
      received.clear();

      Restage.debugReconcileFromServer([
        EntitlementSummary(
          entitlementId: 'pro',
          status: 'active',
          productId: 'monthly',
          source: 'storeNotification',
          expiresAtMs: 200,
        ),
      ]);
      await pumpEventQueue();

      expect(received, hasLength(1));
      expect(received.single, isA<SubscriptionRenewed>());
      final renewed = received.single as SubscriptionRenewed;
      expect(renewed.entitlementId, 'pro');
      expect(renewed.productId, 'monthly');
      expect(Restage.currentEntitlements.map((e) => e.id), contains('pro'));
    });

    test('second sync, active → expired → SubscriptionLapsed + removed',
        () async {
      Restage.debugReconcileFromServer([
        EntitlementSummary(
          entitlementId: 'pro',
          status: 'active',
          productId: 'monthly',
          source: 'clientReport',
          expiresAtMs: 100,
        ),
      ]);
      await pumpEventQueue();
      received.clear();

      Restage.debugReconcileFromServer([
        EntitlementSummary(
          entitlementId: 'pro',
          status: 'expired',
          productId: 'monthly',
          source: 'storeNotification',
        ),
      ]);
      await pumpEventQueue();

      expect(received, hasLength(1));
      expect(received.single, isA<SubscriptionLapsed>());
      expect(Restage.currentEntitlements, isEmpty);
    });

    test('second sync, active → refunded → EntitlementRevoked(refunded)',
        () async {
      Restage.debugReconcileFromServer([
        EntitlementSummary(
          entitlementId: 'pro',
          status: 'active',
          productId: 'monthly',
          source: 'clientReport',
        ),
      ]);
      await pumpEventQueue();
      received.clear();

      Restage.debugReconcileFromServer([
        EntitlementSummary(
          entitlementId: 'pro',
          status: 'refunded',
          productId: 'monthly',
          source: 'storeNotification',
        ),
      ]);
      await pumpEventQueue();

      expect(received, hasLength(1));
      expect(received.single, isA<EntitlementRevoked>());
      final revoked = received.single as EntitlementRevoked;
      expect(revoked.reason, RevokeReason.refunded);
      expect(Restage.currentEntitlements, isEmpty);
    });

    test('second sync, expired → active (re-subscribe) → SubscriptionRenewed',
        () async {
      Restage.debugReconcileFromServer([
        EntitlementSummary(
          entitlementId: 'pro',
          status: 'expired',
          productId: 'monthly',
          source: 'storeNotification',
        ),
      ]);
      await pumpEventQueue();
      received.clear();

      Restage.debugReconcileFromServer([
        EntitlementSummary(
          entitlementId: 'pro',
          status: 'active',
          productId: 'monthly',
          source: 'clientReport',
          expiresAtMs: 500,
        ),
      ]);
      await pumpEventQueue();

      expect(received, hasLength(1));
      expect(received.single, isA<SubscriptionRenewed>());
      expect(Restage.currentEntitlements.map((e) => e.id), contains('pro'));
    });

    test('second sync, refunded → active → SubscriptionRenewed', () async {
      Restage.debugReconcileFromServer([
        EntitlementSummary(
          entitlementId: 'pro',
          status: 'refunded',
          productId: 'monthly',
          source: 'storeNotification',
        ),
      ]);
      await pumpEventQueue();
      received.clear();

      Restage.debugReconcileFromServer([
        EntitlementSummary(
          entitlementId: 'pro',
          status: 'active',
          productId: 'monthly',
          source: 'clientReport',
        ),
      ]);
      await pumpEventQueue();

      expect(received, hasLength(1));
      expect(received.single, isA<SubscriptionRenewed>());
      expect(Restage.currentEntitlements.map((e) => e.id), contains('pro'));
    });

    test(
        'third sync, was tracked but absent from response → SubscriptionLapsed',
        () async {
      Restage.debugReconcileFromServer([
        EntitlementSummary(
          entitlementId: 'pro',
          status: 'active',
          productId: 'monthly',
          source: 'clientReport',
        ),
      ]);
      await pumpEventQueue();
      received.clear();

      Restage.debugReconcileFromServer([]);
      await pumpEventQueue();

      expect(received, hasLength(1));
      expect(received.single, isA<SubscriptionLapsed>());
      final lapsed = received.single as SubscriptionLapsed;
      expect(lapsed.entitlementId, 'pro');
      expect(lapsed.productId, 'monthly');
      expect(Restage.currentEntitlements, isEmpty);
    });

    test(
        'graceful-unknown status: server returns "unknown" → not entitled, no event',
        () async {
      Restage.debugReconcileFromServer([
        EntitlementSummary(
          entitlementId: 'pro',
          status: 'unknown',
          productId: 'monthly',
          source: 'storeNotification',
        ),
      ]);
      await pumpEventQueue();

      expect(received, isEmpty);
      expect(Restage.currentEntitlements, isEmpty);
    });

    test(
        'first sync confirms an entitlement already optimistically granted → no event',
        () async {
      Restage.configure(
        apiKey: 'rs_pk_test',
        products: const [
          RestageProduct(
            id: 'monthly',
            slot: 'primary',
            entitlement: 'pro',
          ),
        ],
      );
      Restage.grantEntitlementForProduct('monthly', EntitlementSource.purchase);
      await pumpEventQueue();
      received.clear();

      Restage.debugReconcileFromServer([
        EntitlementSummary(
          entitlementId: 'pro',
          status: 'active',
          productId: 'monthly',
          source: 'clientReport',
          expiresAtMs: 100,
        ),
      ]);
      await pumpEventQueue();

      expect(received, isEmpty,
          reason: 'the optimistic grant already fired EntitlementGranted');
      expect(Restage.currentEntitlements.map((e) => e.id), contains('pro'));
      // Source preserved from the optimistic-grant path; not overwritten
      // by the reconcile.
      expect(
        Restage.currentEntitlements.single.source,
        EntitlementSource.purchase,
      );
    });

    test(
        're-subscribe after lapse with optimistic grant → SubscriptionRenewed fires (no second EntitlementGranted)',
        () async {
      Restage.configure(
        apiKey: 'rs_pk_test',
        products: const [
          RestageProduct(
            id: 'monthly',
            slot: 'primary',
            entitlement: 'pro',
          ),
        ],
      );
      // 1. Server reports active → EntitlementGranted (via debugReconcile).
      Restage.debugReconcileFromServer([
        EntitlementSummary(
          entitlementId: 'pro',
          status: 'active',
          productId: 'monthly',
          source: 'clientReport',
        ),
      ]);
      await pumpEventQueue();
      // 2. Server reports expired → SubscriptionLapsed.
      Restage.debugReconcileFromServer([
        EntitlementSummary(
          entitlementId: 'pro',
          status: 'expired',
          productId: 'monthly',
          source: 'storeNotification',
        ),
      ]);
      await pumpEventQueue();
      // 3. User re-subscribes via the paywall — optimistic grant fires
      //    EntitlementGranted and populates _entitlementsById.
      Restage.grantEntitlementForProduct('monthly', EntitlementSource.purchase);
      await pumpEventQueue();
      received.clear();

      // 4. Server confirms the re-subscribe via the next sync. The
      //    transition is expired → active AND _entitlementsById already
      //    holds it from the optimistic path. The lifecycle event still
      //    needs to fire (host wants the renewal signal); the
      //    entitlement-grant event must NOT re-fire (optimistic path
      //    already sent one).
      Restage.debugReconcileFromServer([
        EntitlementSummary(
          entitlementId: 'pro',
          status: 'active',
          productId: 'monthly',
          source: 'clientReport',
          expiresAtMs: 500,
        ),
      ]);
      await pumpEventQueue();

      expect(received.whereType<SubscriptionRenewed>(), hasLength(1));
      expect(received.whereType<EntitlementGranted>(), isEmpty);
      expect(Restage.currentEntitlements.map((e) => e.id), contains('pro'));
      // Source preserved from the optimistic-grant path, not overwritten
      // by the reconcile.
      expect(
        Restage.currentEntitlements.single.source,
        EntitlementSource.purchase,
      );
    });

    test('multiple entitlements: each transition fires independently',
        () async {
      Restage.debugReconcileFromServer([
        EntitlementSummary(
          entitlementId: 'pro',
          status: 'active',
          productId: 'monthly',
          source: 'clientReport',
        ),
        EntitlementSummary(
          entitlementId: 'premium',
          status: 'active',
          productId: 'annual',
          source: 'clientReport',
        ),
      ]);
      await pumpEventQueue();
      received.clear();

      Restage.debugReconcileFromServer([
        EntitlementSummary(
          entitlementId: 'pro',
          status: 'expired',
          productId: 'monthly',
          source: 'storeNotification',
        ),
        EntitlementSummary(
          entitlementId: 'premium',
          status: 'refunded',
          productId: 'annual',
          source: 'storeNotification',
        ),
      ]);
      await pumpEventQueue();

      expect(received, hasLength(2));
      expect(
        received.whereType<SubscriptionLapsed>().single.entitlementId,
        'pro',
      );
      expect(
        received.whereType<EntitlementRevoked>().single.entitlementId,
        'premium',
      );
      expect(Restage.currentEntitlements, isEmpty);
    });
  });

  group('Restage.syncEntitlements with no entitlement client', () {
    test('no-op when baseUrl was not configured', () async {
      Restage.configure(apiKey: 'rs_pk_test');

      await Restage.syncEntitlements();

      expect(Restage.currentEntitlements, isEmpty);
    });
  });

  group('Restage.syncEntitlements integration', () {
    test('parses server response and reconciles into the local set', () async {
      Restage.configure(
        apiKey: 'rs_pk_test',
        baseUrl: 'https://example.com',
      );
      Restage.debugRestageRpcClient = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: MockClient((req) async {
          return http.Response(
            jsonEncode(<String, Object?>{
              'entitlements': <Object?>[
                <String, Object?>{
                  'entitlementId': 'pro',
                  'status': 'active',
                  'productId': 'monthly',
                  'source': 'storeNotification',
                  'expiresAtMs': 1000,
                },
              ],
            }),
            200,
          );
        }),
      );

      await Restage.syncEntitlements();
      await pumpEventQueue();

      expect(Restage.currentEntitlements.map((e) => e.id), contains('pro'));
    });

    test(
        'transport failure preserves local entitlements (does not falsely lapse)',
        () async {
      Restage.configure(
        apiKey: 'rs_pk_test',
        baseUrl: 'https://example.com',
        products: const [
          RestageProduct(
            id: 'monthly',
            slot: 'primary',
            entitlement: 'pro',
          ),
        ],
      );
      Restage.grantEntitlementForProduct('monthly', EntitlementSource.purchase);
      // Seed the SDK's view of the server's last-reported state so the
      // entitlement is "tracked" — exactly the operational scenario
      // where an HTTP failure would otherwise falsely lapse it.
      Restage.debugReconcileFromServer([
        EntitlementSummary(
          entitlementId: 'pro',
          status: 'active',
          productId: 'monthly',
          source: 'storeNotification',
        ),
      ]);
      await pumpEventQueue();
      final received = <RestageEvent>[];
      Restage.events.listen(received.add);

      Restage.debugRestageRpcClient = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: MockClient((req) async => http.Response('', 503)),
      );

      await Restage.syncEntitlements();
      await pumpEventQueue();

      // Local entitlement preserved — no false lapse from a transient
      // HTTP failure.
      expect(Restage.currentEntitlements.map((e) => e.id), contains('pro'));
      expect(received.whereType<SubscriptionLapsed>(), isEmpty);
      expect(received.whereType<EntitlementRevoked>(), isEmpty);
    });
  });
}
