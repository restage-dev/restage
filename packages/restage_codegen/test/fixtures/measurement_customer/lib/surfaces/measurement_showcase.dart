import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import '../widgets/measurement_actions.dart';

part 'restage.generated/measurement_showcase.restage.g.dart';

@Screen(id: 'customer_measurement_showcase', surface: Surface.general)
final class CustomerMeasurementShowcase extends StatelessWidget {
  const CustomerMeasurementShowcase({super.key});

  static const activate = SurfaceEvent<void>('activate');
  static const inspect = SurfaceEvent<void>('inspect');

  @override
  Widget build(BuildContext context) => Column(
        children: [
          FilledButton(
            onPressed: surfaceEvent(activate),
            child: const Text('Ordinary'),
          ),
          InlineAction(onPressed: surfaceEvent(activate)),
          OpaqueAction(onPressed: surfaceEvent(activate)),
          FilledButton(
            key: UniqueKey(),
            onPressed: surfaceEvent(activate),
            child: const Text('Repeated A'),
          ),
          FilledButton(
            onPressed: surfaceEvent(activate),
            child: const Text('Repeated B'),
          ),
          GestureDetector(
            onTap: surfaceEvent(activate),
            onDoubleTap: surfaceEvent(inspect),
            child: const Text('Multi-slot'),
          ),
        ],
      );
}
