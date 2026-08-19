import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'offer_intro.rsscreen.g.dart';

@Screen()
final class OfferIntroScreen extends StatelessWidget {
  const OfferIntroScreen({super.key});

  static const next = SurfaceEvent<void>('next');

  @override
  Widget build(BuildContext context) => const Text('Offer');
}
