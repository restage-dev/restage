import 'package:apps_examples/widgets/app_widgets.dart';
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/plan_picker.restage.g.dart';

@Paywall(completesOn: [PlanPicker.subscribe])
class PlanPicker extends StatefulWidget {
  const PlanPicker({required this.yearlyPrice, super.key});

  final String yearlyPrice;

  static const subscribe = SurfaceEvent<String>('subscribe');

  static const close = SurfaceEvent<void>('close');

  @override
  State<PlanPicker> createState() => _PlanPickerState();
}

class _PlanPickerState extends State<PlanPicker> {
  bool yearly = true;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          AppText('Only ${widget.yearlyPrice} a year'),
          AppButton(
            label: 'Subscribe',
            onPressed: surfaceEvent(PlanPicker.subscribe, 'yearly'),
          ),
          TextButton(
            onPressed: surfaceEvent(PlanPicker.close),
            child: const Text('Not now'),
          ),
        ],
      );
}
