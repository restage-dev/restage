import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/combined_condition.restage.g.dart';

@Paywall()
class CombinedCondition extends StatefulWidget {
  const CombinedCondition({super.key});

  @override
  State<CombinedCondition> createState() => _CombinedConditionState();
}

class _CombinedConditionState extends State<CombinedCondition> {
  bool annual = true;
  bool trial = false;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          annual && trial
              ? FilledButton(
                  onPressed: paywallEvent('trial'),
                  child: const Text('Start trial'),
                )
              : OutlinedButton(
                  onPressed: paywallEvent('buy'),
                  child: const Text('Buy'),
                ),
        ],
      );
}
