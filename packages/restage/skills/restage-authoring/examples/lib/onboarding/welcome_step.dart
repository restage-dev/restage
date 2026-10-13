import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/welcome_step.restage.g.dart';

/// First onboarding step. A plain `@Screen()` takes the flow's category.
@Screen()
final class WelcomeStep extends StatelessWidget {
  const WelcomeStep({super.key});

  static const next = SurfaceEvent<void>('next');

  @override
  Widget build(BuildContext context) => Center(
        child: FilledButton(
          onPressed: surfaceEvent(next),
          child: const Text('Get started'),
        ),
      );
}
