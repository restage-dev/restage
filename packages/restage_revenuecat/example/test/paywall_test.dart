import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:restage/restage.dart';
import 'package:restage_revenuecat_example/main.dart';
import 'package:restage_revenuecat_example/revenuecat_upgrade.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/hosted_delivery.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('purchases_flutter');
  late List<String> purchased;
  late int restored;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Restage.debugReset();
    purchased = [];
    restored = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'purchasePackage') {
        purchased.add((call.arguments as Map)['packageIdentifier'] as String);
      }
      if (call.method == 'restorePurchases') {
        restored++;
        return _purchaseResult['customerInfo'];
      }
      return _purchaseResult;
    });
  });
  tearDown(() {
    Restage.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  for (final fails in [false, true]) {
    testWidgets('hosted purchase callback tolerates dismissal (fails: $fails)',
        (tester) async {
      final purchase = Completer<Object?>();
      var purchaseStarted = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        purchaseStarted = true;
        return purchase.future;
      });
      final requests = configureHostedPaywall(
        definition: revenueCatPaywallPlacementDefinition(),
        fixture: 'original_paywall',
      );
      try {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: RevenueCatExample(
              offering: Offering('annual', 'Annual', const {}, [
                _package('annual_49', '49,00 €'),
              ]),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        final requestCount = requests.length;
        final fallbackCount = find.byType(RevenueCatPaywall).evaluate().length;
        final titleCount = find.text('Choose your plan').evaluate().length;
        if (find.text('49,00 €').evaluate().length == 1) {
          await tester.tap(find.text('49,00 €'));
        }
        await tester.pumpWidget(const SizedBox());
        if (fails && purchaseStarted) {
          purchase.completeError(PlatformException(code: 'purchase-cancelled'));
        } else {
          purchase.complete(_purchaseResult);
        }
        await tester.pumpAndSettle();
        expect(purchaseStarted, isTrue);
        expect(requestCount, greaterThan(0));
        expect(fallbackCount, 0);
        expect(titleCount, 1);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      }
    });
  }

  testWidgets(
      'hosted refusal uses compiled fallback with live purchase and restore',
      (tester) async {
    final requests = configureHostedPaywall(
      definition: revenueCatPaywallPlacementDefinition(),
      fixture: 'original_paywall',
      unavailable: true,
    );
    try {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RevenueCatExample(
            offering: Offering('holiday', 'Holiday prices', const {}, [
              _package('annual_49', '49,00 €'),
              _package('annual_59', '59,00 €'),
            ]),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(requests, isNotEmpty);
      expect(find.byType(RevenueCatPaywallSurface), findsOneWidget);
      expect(find.byType(RevenueCatPaywall), findsOneWidget);
      expect(find.text('49,00 €'), findsOneWidget);
      expect(find.text('59,00 €'), findsOneWidget);

      await tester.tap(find.text('59,00 €'));
      await tester.pumpAndSettle();
      expect(purchased, ['annual_59']);
      expect(find.text('Purchases updated.'), findsOneWidget);
      await tester.tap(find.text('Restore purchases'));
      await tester.pumpAndSettle();
      expect(restored, 1);
      expect(purchased, ['annual_59']);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    }
  });

  testWidgets('hosted paywall uses live prices through a version and rollback',
      (tester) async {
    final offering = Offering('holiday', 'Holiday prices', const {}, [
      _package('annual_49', '49,00 €'),
      _package('annual_59', '59,00 €'),
    ]);
    var selected = (fixture: 'original_paywall', version: 1);
    final requests = configureHostedPaywall(
      definition: revenueCatPaywallPlacementDefinition(),
      fixture: selected.fixture,
      publication: () => selected,
    );
    try {
      for (final (index, fixture, version, selectedPrice) in [
        (1, 'original_paywall', 1, '49,00 €'),
        (2, 'featured_paywall', 2, '59,00 €'),
        (3, 'original_paywall', 1, '49,00 €'),
      ]) {
        final previousRequests = requests.length;
        selected = (fixture: fixture, version: version);
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: RevenueCatExample(key: ValueKey(index), offering: offering),
          ),
        ));
        await tester.pumpAndSettle();
        final fallbackCount = find.byType(RevenueCatPaywall).evaluate().length;
        final price49Count = find.text('49,00 €').evaluate().length;
        final price59Count = find.text('59,00 €').evaluate().length;
        final featuredCount =
            find.text('Featured annual plan').evaluate().length;
        if (find.text(selectedPrice).evaluate().length == 1) {
          await tester.tap(find.text(selectedPrice));
          await tester.pumpAndSettle();
        }
        final purchaseUpdateCount =
            find.text('Purchases updated.').evaluate().length;
        final exception = tester.takeException();
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        expect(exception, isNull);
        expect(requests.length, greaterThan(previousRequests));
        expect(
          requests.expand((request) => request.mounts).map(
                (mount) => mount.defaultSurface?.slug,
              ),
          contains('revenuecat_upgrade'),
        );
        expect(fallbackCount, 0);
        expect(price59Count, 1);
        expect(price49Count, index == 2 ? 0 : 1);
        expect(featuredCount, index == 2 ? 1 : 0);
        expect(purchaseUpdateCount, 1);
      }
      expect(purchased, ['annual_49', 'annual_59', 'annual_49']);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    }
  });
}

Package _package(String id, String price) => Package(
      id,
      PackageType.custom,
      StoreProduct(
          'pro_$id', 'Annual subscription', 'Annual', 49, price, 'EUR'),
      const PresentedOfferingContext('holiday', null, null),
    );

const _purchaseResult = {
  'customerInfo': {
    'entitlements': {'all': <String, Object>{}, 'active': <String, Object>{}},
    'allPurchaseDates': <String, Object>{},
    'activeSubscriptions': <Object>[],
    'allPurchasedProductIdentifiers': <Object>[],
    'nonSubscriptionTransactions': <Object>[],
    'firstSeen': '2026-01-01T00:00:00Z',
    'originalAppUserId': 'example-customer',
    'allExpirationDates': <String, Object>{},
    'requestDate': '2026-01-01T00:00:00Z',
  },
  'transaction': {
    'transactionIdentifier': 'example-transaction',
    'productIdentifier': 'pro_annual',
    'purchaseDate': '2026-01-01T00:00:00Z',
  },
};
