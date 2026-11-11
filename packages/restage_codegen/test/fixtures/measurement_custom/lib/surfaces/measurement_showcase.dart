import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import '../widgets/measurement_actions.dart';

part 'restage.generated/measurement_showcase.restage.g.dart';

@Screen(id: 'custom_measurement_showcase', surface: Surface.general)
final class CustomMeasurementShowcase extends StatelessWidget {
  const CustomMeasurementShowcase({super.key});

  static const activate = SurfaceEvent<void>('activate');
  static const inspect = SurfaceEvent<void>('inspect');

  @override
  Widget build(BuildContext context) => Column(
        children: [
          FilledButton(
            onPressed: context.surfaceEvent(activate),
            child: const Text('Ordinary'),
          ),
          InlineAction(onPressed: context.surfaceEvent(activate)),
          OpaqueAction(onPressed: context.surfaceEvent(activate)),
          FilledButton(
            key: const ValueKey<String>('original-host-key'),
            onPressed: context.surfaceEvent(activate),
            child: const Text('Repeated A'),
          ),
          FilledButton(
            onPressed: context.surfaceEvent(activate),
            child: const Text('Repeated B'),
          ),
          GestureDetector(
            onTap: context.surfaceEvent(activate),
            onDoubleTap: context.surfaceEvent(inspect),
            child: const Text('Multi-slot'),
          ),
        ],
      );
}
