import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'declined.rsscreen.g.dart';

@ScreenSource(id: 'declined')
final class DeclinedScreen extends StatelessWidget {
  const DeclinedScreen({super.key});

  static const finish = OnboardingEvent<void>('finish');

  @override
  Widget build(BuildContext context) => const Text('Declined');
}
