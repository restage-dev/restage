import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@Paywall()
final class UpgradeOffer extends StatelessWidget {
  const UpgradeOffer({super.key});

  static const continueFlow = SurfaceEvent<Map<String, Object?>>('continue');

  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: context.surfaceEvent(UpgradeOffer.continueFlow),
        child: const Text('Upgrade'),
      );
}
