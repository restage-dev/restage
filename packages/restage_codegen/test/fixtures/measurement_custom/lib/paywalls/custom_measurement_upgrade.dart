import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/custom_measurement_upgrade.restage.g.dart';

@Paywall(id: 'custom_measurement_upgrade')
final class CustomMeasurementUpgrade extends StatelessWidget {
  const CustomMeasurementUpgrade({super.key});

  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: context.surfaceEvent(_Events.upgrade),
        child: const Text('Upgrade'),
      );
}

abstract final class _Events {
  static const upgrade = SurfaceEvent<void>('upgrade');
}
