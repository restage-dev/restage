import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:restage/restage.dart';
import 'package:restage_store_bridge/restage_store_bridge.dart';

import 'store_upgrade.dart';
import 'restage_surfaces.g.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Restage.configureWithInstalledCatalog(
    apiKey: const String.fromEnvironment('RESTAGE_API_KEY'),
    baseUrl: const String.fromEnvironment('RESTAGE_BASE_URL'),
    surfaces: restageSurfaces,
  );
  runApp(
    InAppPurchaseScope(
      create: () => InAppPurchaseController(
        verifyPurchase: verifyPurchase,
        deliverPurchase: deliverPurchase,
        onError: reportError,
      ),
      child: const StoreExample(),
    ),
  );
}

// App integration: validate store evidence with your trusted purchase service.
Future<bool> verifyPurchase(PurchaseDetails purchase) =>
    throw UnsupportedError('Connect your app purchase verifier.');

// App integration: deliver idempotently by verified transaction identity.
Future<void> deliverPurchase(PurchaseDetails purchase) =>
    throw UnsupportedError('Connect your app entitlement or content delivery.');

void reportError(Object error, StackTrace stackTrace) {
  debugPrint('Store error: $error');
  debugPrintStack(stackTrace: stackTrace);
}

class StoreExample extends StatefulWidget {
  const StoreExample({super.key});

  @override
  State<StoreExample> createState() => _StoreExampleState();
}

class _StoreExampleState extends State<StoreExample> {
  late final Future<Map<String, ProductDetails>> _packages;

  @override
  void initState() {
    super.initState();
    _packages = _loadPackages().onError<Object>((error, stackTrace) {
      reportError(error, stackTrace);
      Error.throwWithStackTrace(error, stackTrace);
    });
  }

  Future<Map<String, ProductDetails>> _loadPackages() async {
    if (!await InAppPurchase.instance.isAvailable()) {
      throw StateError('The store is unavailable on this device.');
    }
    final catalog = await InAppPurchase.instance.queryProductDetails({
      'pro_monthly',
      'pro_annual',
    });
    if (catalog.error case final error?) throw error;
    if (catalog.notFoundIDs.isNotEmpty) {
      throw StateError('Configure pro_monthly and pro_annual in your store.');
    }
    // For multiple offers sharing a SKU, select the intended native offer here.
    return Map<String, ProductDetails>.unmodifiable({
      'monthly': catalog.productDetails.singleWhere(
        (p) => p.id == 'pro_monthly',
      ),
      'annual': catalog.productDetails.singleWhere((p) => p.id == 'pro_annual'),
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = InAppPurchaseScope.of(context);
    return MaterialApp(
      home: Scaffold(
        body: FutureBuilder<Map<String, ProductDetails>>(
          future: _packages,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('${snapshot.error}'));
            }
            final packages = snapshot.data;
            if (packages == null) {
              return const Center(child: CircularProgressIndicator());
            }
            // Replace with accurate localized terms for your products.
            const billingTerms = {
              'monthly':
                  r'$4.99 each month. Renews until canceled. No free trial.',
              'annual':
                  r'$39.99 each year. Renews until canceled. No free trial.',
            };
            return StorePaywallSurface(
              packages: List<PaywallPackage>.unmodifiable([
                for (final entry in packages.entries)
                  PaywallPackage(
                    identifier: entry.key,
                    priceString: entry.value.price,
                    billingTerms: billingTerms[entry.key]!,
                  ),
              ]),
              onEvent: inAppPurchaseEventHandler(
                packages: packages,
                controller: store,
                onError: reportError,
              ),
            );
          },
        ),
      ),
    );
  }
}
