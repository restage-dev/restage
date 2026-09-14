// @dart=3.13
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

// ignore: uri_has_not_been_generated
part 'restage.generated/measurement_configuration.restage.g.dart';

@Screen(id: 'measurement_configuration', surface: Surface.general)
final class MeasurementConfigurationScreen extends StatelessWidget {
  const MeasurementConfigurationScreen({super.key});

  static const activate = SurfaceEvent<void>('activate');

  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: surfaceEvent(activate),
    child: const Text('Activate'),
  );
}
