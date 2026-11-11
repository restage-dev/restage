import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/static_plans.restage.g.dart';

@Screen(id: 'static_plans', surface: Surface.general)
final class StaticPlans extends StatelessWidget {
  const StaticPlans({super.key});

  static const pick = SurfaceEvent<String>('pick');
  static const choose = SurfaceEvent<void>('choose');

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (final plan in const ['yearly', 'monthly'])
            TextButton(
              key: ValueKey(plan),
              onPressed: context.surfaceEvent(pick, plan),
              child: Text(plan),
            ),
          for (final label in const ['First', 'Second'])
            OutlinedButton(
              onPressed: context.surfaceEvent(choose),
              child: Text(label),
            ),
          FilledButton(
            onPressed: context.surfaceEvent(choose),
            child: const Text('Alone'),
          ),
        ],
      );
}
