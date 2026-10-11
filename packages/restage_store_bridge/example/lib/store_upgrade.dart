import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/store_upgrade.restage.g.dart';

final class PaywallPackage {
  const PaywallPackage({
    required this.identifier,
    required this.priceString,
    required this.billingTerms,
  });

  final String identifier;
  final String priceString;
  final String billingTerms;
}

@Paywall()
class StorePaywall extends StatelessWidget {
  const StorePaywall({required this.packages, super.key});

  final List<PaywallPackage> packages;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Choose your plan'),
        const SizedBox(height: 16),
        for (final package in packages)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                onPressed: paywallEvent(
                  'in_app_purchase.purchase',
                  args: {'packageIdentifier': package.identifier},
                ),
                child: Text(package.priceString),
              ),
              Text(package.billingTerms),
              const SizedBox(height: 16),
            ],
          ),
        TextButton(
          onPressed: paywallEvent('in_app_purchase.restore'),
          child: const Text('Restore purchases'),
        ),
      ],
    ),
  );
}
