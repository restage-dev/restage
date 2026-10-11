import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:restage/restage.dart';
import 'package:restage_store_bridge/restage_store_bridge.dart';
import 'package:restage_store_bridge_example/custom.dart';
import 'package:restage_store_bridge_example/main.dart' as example;
import 'package:restage_store_bridge_example/store_upgrade.dart';
import 'package:restage_store_bridge_example/restage_surfaces.g.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/hosted_delivery.dart';

const _terms = {
  'trial': r'7 days free then $4.99 each month. Renews until canceled.',
  'standard': r'$4.99 each month. Renews until canceled. No free trial.',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _StorePlatform platform;
  late ProductDetails introductory;
  late ProductDetails standard;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Restage.debugReset();
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    InAppPurchase.instance;
    debugDefaultTargetPlatformOverride = null;
    introductory = _product(r'$0.00');
    standard = _product(r'$4.99');
    platform = _StorePlatform([introductory, standard]);
    InAppPurchasePlatform.instance = platform;
  });

  tearDown(() {
    Restage.debugReset();
    debugDefaultTargetPlatformOverride = null;
  });

  for (final custom in [false, true]) {
    for (final fallback in [false, true]) {
      testWidgets(
        '${custom ? 'custom' : 'default'} ${fallback ? 'hosted refusal with compiled fallback' : 'hosted paywall'} selects exact queried offers and shows terms',
        (tester) async {
          debugDefaultTargetPlatformOverride = TargetPlatform.linux;
          try {
            final requests = configureHostedPaywall(
              definition: storePaywallPlacementDefinition(),
              fixture: 'store_upgrade',
              unavailable: fallback,
            );
            final errors = <Object>[];
            final customProducts = <ProductDetails>[];
            var customRestores = 0;
            InAppPurchaseController createController() =>
                InAppPurchaseController(
                  verifyPurchase: (_) =>
                      throw StateError('No transaction expected.'),
                  deliverPurchase: (_) =>
                      throw StateError('No delivery expected.'),
                  onError: (error, _) => errors.add(error),
                );
            if (!custom) {
              await tester.pumpWidget(
                InAppPurchaseScope(
                  create: createController,
                  child: const SizedBox(),
                ),
              );
            }
            final catalog = await InAppPurchase.instance.queryProductDetails({
              'pro_monthly',
            });
            final packages = Map<String, ProductDetails>.unmodifiable({
              'trial': catalog.productDetails[0],
              'standard': catalog.productDetails[1],
            });
            final paywallPackages = [
              for (final entry in packages.entries)
                PaywallPackage(
                  identifier: entry.key,
                  priceString: entry.value.price,
                  billingTerms: _terms[entry.key]!,
                ),
            ];
            final widget = custom
                ? MaterialApp(
                    home: Scaffold(
                      body: customStorePaywall(
                        packages: packages,
                        paywallPackages: paywallPackages,
                        purchase: (product) async {
                          customProducts.add(product);
                          return null;
                        },
                        restore: () async => customRestores++,
                        onError: (error, _) => errors.add(error),
                      ),
                    ),
                  )
                : InAppPurchaseScope(
                    create: createController,
                    child: MaterialApp(
                      home: Scaffold(
                        body: Builder(
                          builder: (context) => StorePaywallSurface(
                            packages: paywallPackages,
                            onEvent: inAppPurchaseEventHandler(
                              packages: packages,
                              controller: InAppPurchaseScope.of(context),
                              onError: (error, _) => errors.add(error),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );

            await tester.pumpWidget(widget);
            await tester.pumpAndSettle();
            expect(find.byType(RestagePaywall), findsOneWidget);
            expect(requests, isNotEmpty);
            expect(
              requests
                  .expand((request) => request.mounts)
                  .map((mount) => mount.key),
              everyElement(storePaywallPlacementDefinition().key),
            );
            expect(
              find.byType(StorePaywall),
              fallback ? findsOneWidget : findsNothing,
            );
            expect(find.text(r'$0.00'), findsOneWidget);
            expect(find.text(r'$4.99'), findsOneWidget);
            expect(find.text(_terms['trial']!), findsOneWidget);
            expect(find.text(_terms['standard']!), findsOneWidget);

            await tester.tap(find.text(r'$4.99'));
            await tester.pumpAndSettle();
            await tester.tap(find.text(r'$0.00'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Restore purchases'));
            await tester.pumpAndSettle();

            final selected = custom ? customProducts : platform.purchased;
            expect(selected, hasLength(2));
            expect(identical(selected[0], standard), isTrue);
            expect(identical(selected[1], introductory), isTrue);
            expect(custom ? customRestores : platform.restores, 1);
            expect(platform.queried, {'pro_monthly'});
            if (!custom) expect(platform.catalogListeners, [true]);
            expect(errors, isEmpty);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox());
            await tester.pump();
            await tester.runAsync(() async {});
            await tester.pump();
            expect(platform.updates.hasListener, isFalse);
            await tester.runAsync(platform.updates.close);
            debugDefaultTargetPlatformOverride = null;
          }
        },
      );
    }
  }

  for (final target in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      '${target.name} main uses compiled fallback without credentials and handles resume',
      (tester) async {
        debugDefaultTargetPlatformOverride = target;
        platform.products
          ..clear()
          ..addAll([_product(r'$4.99'), _product(r'$39.99', id: 'pro_annual')]);
        try {
          await tester.pumpWidget(const SizedBox());
          await example.main();
          await tester.pumpAndSettle();
          final expected = target == TargetPlatform.android ? 1 : 0;
          expect(platform.restores, expected);
          expect(platform.restoreListeners, everyElement(isTrue));
          expect(platform.catalogListeners, [true]);
          expect(platform.availabilityListeners, [true]);
          expect(platform.updates.hasListener, isTrue);
          expect(find.byType(RestagePaywall), findsOneWidget);
          expect(find.byType(StorePaywall), findsOneWidget);
          await tester.runAsync(() async {
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.paused,
            );
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.resumed,
            );
            await Future<void>.delayed(Duration.zero);
          });
          await tester.pumpAndSettle();
          expect(platform.restores, expected * 2);
          expect(platform.queried, {'pro_monthly', 'pro_annual'});
          tester.element(find.byType(example.StoreExample)).markNeedsBuild();
          await tester.pumpAndSettle();
          expect(platform.catalogListeners, [true]);
          expect(platform.availabilityListeners, [true]);
        } finally {
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
          await tester.runAsync(() async {});
          await tester.pump();
          expect(platform.updates.hasListener, isFalse);
          await tester.runAsync(platform.updates.close);
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }

  testWidgets(
    'hosted plan selection changes and rolls back with the same catalog',
    (tester) async {
      try {
        final packages = Map<String, ProductDetails>.unmodifiable({
          'trial': introductory,
          'standard': standard,
        });
        final paywallPackages = [
          for (final entry in packages.entries)
            PaywallPackage(
              identifier: entry.key,
              priceString: entry.value.price,
              billingTerms: _terms[entry.key]!,
            ),
        ];
        final purchased = <ProductDetails>[];
        var selected = (fixture: 'store_upgrade', version: 1);
        final requests = configureHostedPaywall(
          definition: storePaywallPlacementDefinition(),
          fixture: selected.fixture,
          publication: () => selected,
        );
        for (final (index, fixture, version, price) in [
          (1, 'store_upgrade', 1, r'$0.00'),
          (2, 'featured_store_upgrade', 2, r'$4.99'),
          (3, 'store_upgrade', 1, r'$0.00'),
        ]) {
          selected = (fixture: fixture, version: version);
          final previousRequests = requests.length;
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: KeyedSubtree(
                  key: ValueKey(index),
                  child: customStorePaywall(
                    packages: packages,
                    paywallPackages: paywallPackages,
                    purchase: (product) async {
                      purchased.add(product);
                      return null;
                    },
                    restore: () async {},
                    onError: (error, stack) =>
                        Error.throwWithStackTrace(error, stack),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(requests.length, greaterThan(previousRequests));
          expect(find.byType(StorePaywall), findsNothing);
          expect(find.text(r'$4.99'), findsOneWidget);
          expect(find.text(_terms['standard']!), findsOneWidget);
          expect(
            find.text(r'$0.00'),
            index == 2 ? findsNothing : findsOneWidget,
          );
          expect(
            find.text(_terms['trial']!),
            index == 2 ? findsNothing : findsOneWidget,
          );
          expect(
            find.text('Featured monthly plan'),
            index == 2 ? findsOneWidget : findsNothing,
          );
          await tester.tap(find.text(price));
          await tester.pumpAndSettle();
        }
        expect(purchased, hasLength(3));
        expect(identical(purchased[0], introductory), isTrue);
        expect(identical(purchased[1], standard), isTrue);
        expect(identical(purchased[2], introductory), isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(platform.updates.close);
      }
    },
  );

  testWidgets('Android startup and resume refresh errors reach app onError', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final errors = <Object>[];
    final failure = StateError('refresh');
    platform.restoreError = failure;
    platform.products
      ..clear()
      ..addAll([_product(r'$4.99'), _product(r'$39.99', id: 'pro_annual')]);
    try {
      Restage.configureWithInstalledCatalog(
        surfaces: restageSurfaces,
        analyticsEnabled: false,
        measurementEnabled: false,
      );
      await tester.pumpWidget(
        InAppPurchaseScope(
          create: () => InAppPurchaseController(
            verifyPurchase: (_) => throw StateError('No transaction expected.'),
            deliverPurchase: (_) => throw StateError('No delivery expected.'),
            onError: (error, _) => errors.add(error),
          ),
          child: const example.StoreExample(),
        ),
      );
      await tester.pumpAndSettle();
      expect(errors, [same(failure)]);
      expect(platform.restoreListeners, [true]);
      expect(platform.catalogListeners, [true]);
      await tester.runAsync(() async {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(errors, [same(failure), same(failure)]);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.runAsync(() async {});
      await tester.pump();
      expect(platform.updates.hasListener, isFalse);
      await tester.runAsync(platform.updates.close);
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

ProductDetails _product(String price, {String id = 'pro_monthly'}) =>
    ProductDetails(
      id: id,
      title: 'Plan',
      description: 'Subscription',
      price: price,
      rawPrice: price == r'$0.00' ? 0 : 4.99,
      currencyCode: 'USD',
    );

final class _StorePlatform extends InAppPurchasePlatform {
  _StorePlatform(this.products);

  final List<ProductDetails> products;
  final updates = StreamController<List<PurchaseDetails>>.broadcast();
  final purchased = <ProductDetails>[];
  Set<String>? queried;
  var restores = 0;
  final restoreListeners = <bool>[];
  final availabilityListeners = <bool>[];
  final catalogListeners = <bool>[];
  Object? restoreError;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => updates.stream;

  @override
  Future<bool> isAvailable() async {
    availabilityListeners.add(updates.hasListener);
    return true;
  }

  @override
  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> identifiers,
  ) async {
    catalogListeners.add(updates.hasListener);
    queried = Set.of(identifiers);
    return ProductDetailsResponse(
      productDetails: products,
      notFoundIDs: const [],
    );
  }

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    purchased.add(purchaseParam.productDetails);
    return true;
  }

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    restores++;
    restoreListeners.add(updates.hasListener);
    if (restoreError case final error?) throw error;
  }
}
