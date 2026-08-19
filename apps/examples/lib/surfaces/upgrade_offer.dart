import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@Paywall()
final class UpgradeOffer extends StatelessWidget {
  const UpgradeOffer({super.key});

  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: paywallPurchase(slot: 'primary'),
        child: const Text('Upgrade'),
      );
}
