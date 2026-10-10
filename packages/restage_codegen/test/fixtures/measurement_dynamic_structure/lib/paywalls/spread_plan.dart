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
              onPressed: paywallEvent('annual'),
              child: const Text('Annual'),
            ),
          ] else
            OutlinedButton(
              onPressed: paywallEvent('monthly'),
              child: const Text('Monthly'),
            ),
          TextButton(
            onPressed: paywallEvent('close'),
            child: const Text('Close'),
          ),
        ],
      );
}
