import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/offer_intro.restage.g.dart';

@ScreenSource(id: 'offer_intro')
final class OfferIntroScreen extends StatelessWidget {
  const OfferIntroScreen({super.key});

  static const next = OnboardingEvent<void>('next');

  @override
  Widget build(BuildContext context) => const Text('Offer');
}
