import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/goal_step.restage.g.dart';

/// Asks for a goal. Each answer carries a value.
@Screen()
final class GoalStep extends StatelessWidget {
  const GoalStep({super.key});

  static const pick = SurfaceEvent<String>('pick');

  @override
  Widget build(BuildContext context) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FilledButton(
            onPressed: surfaceEvent(pick, 'focus'),
            child: const Text('Focus better'),
          ),
          FilledButton(
            onPressed: surfaceEvent(pick, 'sleep'),
            child: const Text('Sleep better'),
          ),
        ],
      );
}
