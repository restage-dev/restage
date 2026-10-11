import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:restage/restage.dart';
import 'package:restage_revenuecat/restage_revenuecat.dart';

import 'revenuecat_upgrade.dart';
import 'restage_surfaces.g.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Purchases.configure(PurchasesConfiguration(
      const String.fromEnvironment('REVENUECAT_API_KEY')));
  Restage.configureWithInstalledCatalog(
    apiKey: const String.fromEnvironment('RESTAGE_API_KEY'),
    baseUrl: const String.fromEnvironment('RESTAGE_BASE_URL'),
    surfaces: restageSurfaces,
  );
  final offering = (await Purchases.getOfferings()).current;
  runApp(MaterialApp(
      home: Scaffold(
          body: offering == null
              ? const Center(child: Text('No current RevenueCat offering.'))
              : RevenueCatExample(offering: offering))));
}

class RevenueCatExample extends StatelessWidget {
  const RevenueCatExample({required this.offering, super.key});

  final Offering offering;

  @override
  Widget build(BuildContext context) => RevenueCatPaywallSurface(
        packages: [
          for (final package in offering.availablePackages)
            PaywallPackage(
                identifier: package.identifier,
                priceString: package.storeProduct.priceString),
        ],
        onEvent: revenueCatEventHandler(
          offering: offering,
          onCustomerInfo: (info) {
            if (!context.mounted) return;
            final subscribed = info.entitlements.active.containsKey('pro');
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(
                    subscribed ? 'Pro is active.' : 'Purchases updated.')));
          },
          onError: (error, _) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(error.toString())));
          },
        ),
      );
}
