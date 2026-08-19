import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/welcome.restage.g.dart';

@ScreenSource(id: 'welcome')
final class CompatibilityWelcome extends StatelessWidget {
  const CompatibilityWelcome({super.key});

  static const finish = OnboardingEvent<void>('finish');

  @override
  Widget build(BuildContext context) => const Text('Compatibility');
}
