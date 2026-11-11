import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/spread_plan.restage.g.dart';

@Paywall()
class SpreadPlan extends StatefulWidget {
  const SpreadPlan({super.key});

  @override
  State<SpreadPlan> createState() => _SpreadPlanState();
}

class _SpreadPlanState extends State<SpreadPlan> {
  bool annual = true;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          if (annual) ...[
            const Text('Best value'),
            FilledButton(
              onPressed: context.surfaceEvent(_Events.annual),
              child: const Text('Annual'),
            ),
          ] else
            OutlinedButton(
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
