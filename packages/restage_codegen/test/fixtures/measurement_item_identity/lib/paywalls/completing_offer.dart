import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/completing_offer.restage.g.dart';

@Paywall(completesOn: [CompletingOffer.subscribe])
class CompletingOffer extends StatelessWidget {
  const CompletingOffer({super.key});

  static const subscribe = SurfaceEvent<Map<String, Object?>>('subscribe');

  @override
  Widget build(BuildContext context) => Column(
        children: [
          FilledButton(
            onPressed: paywallEvent('subscribe'),
            child: const Text('Subscribe'),
          ),
          TextButton(
            onPressed: paywallEvent('close'),
            child: const Text('Not now'),
          ),
        ],
      );
}
