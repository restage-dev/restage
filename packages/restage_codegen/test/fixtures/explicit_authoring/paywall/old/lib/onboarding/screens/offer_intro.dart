import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'offer_intro.rsscreen.g.dart';

@ScreenSource(id: 'offer_intro')
final class OfferIntroScreen extends StatelessWidget {
  const OfferIntroScreen({super.key});

  static const next = OnboardingEvent<void>('next');

  @override
  Widget build(BuildContext context) => const Text('Offer');
}
