// @dart=3.13
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import '../widgets/acme.dart';

part 'restage.generated/premium.restage.g.dart';

@Paywall()
final class PremiumPaywall extends StatelessWidget {
  const PremiumPaywall({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const AcmeTag(label: 'Pro'),
        const AcmeTag(label: 'Max', tone: 0.5),
        const AcmeChip(text: 'Hi'),
        const AcmeBanner(title: 'Sale'),
        const AcmeBanner(title: 'New', fill: Colors.red),
        FilledButton(onPressed: paywallEvent('buy'), child: const Text('Buy')),
      ],
    );
  }
}
