import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/revenuecat_upgrade.restage.g.dart';

final class PaywallPackage {
  const PaywallPackage({required this.identifier, required this.priceString});

  final String identifier;
  final String priceString;
}

@Paywall()
class RevenueCatPaywall extends StatelessWidget {
  static const purchase =
      SurfaceEvent<Map<String, Object?>>('revenuecat.purchase');
  static const restore = SurfaceEvent<void>('revenuecat.restore');

  const RevenueCatPaywall({required this.packages, super.key});

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
              FilledButton(
                onPressed: context.surfaceEvent(RevenueCatPaywall.purchase,
                    {'packageIdentifier': package.identifier}),
                child: Text(package.priceString),
              ),
            TextButton(
              onPressed: context.surfaceEvent(RevenueCatPaywall.restore),
              child: const Text('Restore purchases'),
            ),
          ],
        ),
      );
}
