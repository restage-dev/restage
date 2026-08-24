import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/premium.restage.g.dart';

@Paywall()
final class PremiumPaywall extends StatelessWidget {
  const PremiumPaywall({super.key});

  static const complete = SurfaceEvent<void>('complete');

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: paywallEvent('complete'),
      child: const Text('Upgrade'),
    );
  }
}
