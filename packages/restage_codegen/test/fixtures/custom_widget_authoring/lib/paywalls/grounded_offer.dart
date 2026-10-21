import 'package:apps_examples/widgets/app_widgets.dart';
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/grounded_offer.restage.g.dart';

@Paywall(completesOn: [GroundedOffer.startTrial])
class GroundedOffer extends StatelessWidget {
  const GroundedOffer({required this.terms, super.key});

  final List<String> terms;

  static const startTrial = SurfaceEvent<void>('start_trial');

  @override
  Widget build(BuildContext context) => AppGround(
        child: Column(
          children: [
            const AppText('Go further', large: true),
            AppButton(
              label: 'Start trial',
              onPressed: paywallEvent('start_trial'),
            ),
            TextButton(
              onPressed: paywallEvent('close'),
              child: const Text('Not now'),
            ),
            AppLegal(paragraphs: terms, widths: const [1.0, 2.5]),
          ],
        ),
      );
}
