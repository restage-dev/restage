import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@Paywall()
final class StatefulChoice extends StatefulWidget {
  const StatefulChoice({super.key});

  @override
  State<StatefulChoice> createState() => _StatefulChoiceState();
}

class _StatefulChoiceState extends State<StatefulChoice> {
  bool annualSelected = true;

  void selectMonthly() => setState(() => annualSelected = false);

  @override
  Widget build(BuildContext context) => Column(
        children: [
          GestureDetector(
            onTap: selectMonthly,
            child: const Text('Monthly'),
          ),
          FilledButton(
            onPressed: context.surfaceEvent(_Events.close),
            child: const Text('Close'),
          ),
        ],
      );
}

abstract final class _Events {
  static const close = SurfaceEvent<void>('close');
}
