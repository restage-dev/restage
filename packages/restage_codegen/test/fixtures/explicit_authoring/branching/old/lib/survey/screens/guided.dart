import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/guided.restage.g.dart';

@ScreenSource(id: 'guided')
final class GuidedScreen extends StatelessWidget {
  const GuidedScreen({super.key});

  static const finish = OnboardingEvent<void>('finish');

  @override
  Widget build(BuildContext context) => const Text('Guided');
}
