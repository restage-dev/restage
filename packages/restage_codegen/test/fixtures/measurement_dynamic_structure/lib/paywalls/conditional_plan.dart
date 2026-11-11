import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/conditional_plan.restage.g.dart';

@Paywall()
class ConditionalPlan extends StatefulWidget {
  const ConditionalPlan({super.key});

  @override
  State<ConditionalPlan> createState() => _ConditionalPlanState();
}

class _ConditionalPlanState extends State<ConditionalPlan> {
  bool annual = true;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          annual
              ? FilledButton(
                  onPressed: context.surfaceEvent(_Events.annual),
                  child: const Text('Annual'),
                )
              : OutlinedButton(
                  onPressed: context.surfaceEvent(_Events.monthly),
                  child: const Text('Monthly'),
                ),
          TextButton(
            onPressed: context.surfaceEvent(_Events.close),
            child: const Text('Close'),
          ),
        ],
      );
}

abstract final class _Events {
  static const annual = SurfaceEvent<void>('annual');
  static const monthly = SurfaceEvent<void>('monthly');
  static const close = SurfaceEvent<void>('close');
}
