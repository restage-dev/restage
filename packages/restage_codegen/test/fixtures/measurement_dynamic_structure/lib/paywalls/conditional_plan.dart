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
                  onPressed: paywallEvent('annual'),
                  child: const Text('Annual'),
                )
              : OutlinedButton(
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
