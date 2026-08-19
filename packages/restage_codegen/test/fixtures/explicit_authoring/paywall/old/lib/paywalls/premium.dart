import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/premium.restage.g.dart';

@PaywallSource(id: 'premium')
final class PremiumPaywall extends StatelessWidget {
  const PremiumPaywall({super.key});

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: paywallPurchase(slot: 'primary'),
      child: const Text('Upgrade'),
    );
  }
}
