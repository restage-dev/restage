import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/offer.restage.g.dart';

@Screen()
final class GeneralOfferScreen extends StatelessWidget {
  const GeneralOfferScreen({super.key});

  static const showPaywall = SurfaceEvent<void>('show_paywall');

  @override
  Widget build(BuildContext context) => const Text('Offer');
}
