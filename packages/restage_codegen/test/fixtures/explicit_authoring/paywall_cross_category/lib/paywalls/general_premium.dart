import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'general_premium.rsscreen.g.dart';

@Paywall(id: 'general_premium')
final class GeneralPaywall extends StatelessWidget {
  const GeneralPaywall({super.key});

  @override
  Widget build(BuildContext context) => const Text('Paywall');
}
