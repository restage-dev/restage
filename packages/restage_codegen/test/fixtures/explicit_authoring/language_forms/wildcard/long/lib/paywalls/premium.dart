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
    final title = 'Upgrade';
    return Column(
      children: [
        Text(title),
        const AcmeNote(text: 'Cancel anytime'),
        Switch(value: true, onChanged: (value) => paywallEvent('toggle')),
      ],
    );
  }
}
