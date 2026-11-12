import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/child_fired_offer.restage.g.dart';

Future<bool> purchaseChildPlan() async => true;

@Paywall(completesOn: [ChildFiredOffer.purchased])
class ChildFiredOffer extends StatelessWidget {
  const ChildFiredOffer({super.key});

  static const purchased = SurfaceEvent<void>('purchased');

  @override
  Widget build(BuildContext context) => const Center(child: _BuyButton());
}

class _BuyButton extends StatelessWidget {
  const _BuyButton();

  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: () async {
          final ok = await purchaseChildPlan();
          if (ok && context.mounted) {
            context.surfaceEvent(ChildFiredOffer.purchased)();
          }
        },
        child: const Text('Start trial'),
      );
}
