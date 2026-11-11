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
                  onPressed: context.surfaceEvent(_Events.trial),
                  child: const Text('Start trial'),
                )
              : OutlinedButton(
                  onPressed: context.surfaceEvent(_Events.buy),
                  child: const Text('Buy'),
                ),
        ],
      );
}

abstract final class _Events {
  static const trial = SurfaceEvent<void>('trial');
  static const buy = SurfaceEvent<void>('buy');
}
