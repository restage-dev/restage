import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/app_fired_offer.restage.g.dart';

Future<bool> purchasePlan() async => true;

@Paywall(completesOn: [AppFiredOffer.purchased])
class AppFiredOffer extends StatelessWidget {
  const AppFiredOffer({super.key});

  static const purchased = SurfaceEvent<void>('purchased');

  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: () async {
          final ok = await purchasePlan();
          if (ok && context.mounted) context.surfaceEvent(purchased)();
        },
        child: const Text('Start trial'),
      );
}
