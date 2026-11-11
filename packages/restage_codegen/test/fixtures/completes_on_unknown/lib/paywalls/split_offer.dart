import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/split_offer.restage.g.dart';

@Paywall(completesOn: [SplitOffer.startTrial])
class SplitOffer extends StatelessWidget {
  const SplitOffer({required this.enabled, super.key});

  final bool enabled;

  static const startTrial = SurfaceEvent<void>('start_trial');
  static const later = SurfaceEvent<void>('later');

  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: enabled ? context.surfaceEvent(startTrial) : context.surfaceEvent(later),
        child: const Text('Start trial'),
      );
}
