import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/toggle_plans.restage.g.dart';

@Paywall()
class TogglePlans extends StatefulWidget {
  const TogglePlans({super.key});

  @override
  State<TogglePlans> createState() => _TogglePlansState();
}

class _TogglePlansState extends State<TogglePlans> {
  bool annual = true;

  void selectAnnual() => setState(() => annual = true);

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (final label in const ['Annual', 'Yearly'])
            GestureDetector(
              onTap: selectAnnual,
              child: Text(label),
            ),
          TextButton(
            onPressed: paywallEvent('close'),
            child: const Text('Close'),
          ),
        ],
      );
}
