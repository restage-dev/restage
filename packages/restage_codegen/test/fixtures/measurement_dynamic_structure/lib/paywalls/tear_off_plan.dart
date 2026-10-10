import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/tear_off_plan.restage.g.dart';

@Paywall()
class TearOffPlan extends StatefulWidget {
  const TearOffPlan({super.key});

  @override
  State<TearOffPlan> createState() => _TearOffPlanState();
}

class _TearOffPlanState extends State<TearOffPlan> {
  bool annual = true;

  void selectAnnual() => setState(() => annual = true);

  @override
  Widget build(BuildContext context) => Column(
        children: [
          GestureDetector(
            onTap: selectAnnual,
            child: const Text('Annual'),
          ),
          TextButton(
            onPressed: paywallEvent('close'),
            child: const Text('Close'),
          ),
        ],
      );
}
