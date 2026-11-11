import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/conditional_offer.restage.g.dart';

@Paywall(completesOn: [ConditionalOffer.startTrial])
class ConditionalOffer extends StatelessWidget {
  const ConditionalOffer({required this.enabled, super.key});

  final bool enabled;

  static const startTrial = SurfaceEvent<void>('start_trial');

  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: enabled ? context.surfaceEvent(startTrial) : null,
        child: const Text('Start trial'),
      );
}
