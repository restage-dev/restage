import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'explore.rsscreen.g.dart';

@ScreenSource(id: 'explore')
final class ExploreScreen extends StatelessWidget {
  const ExploreScreen({super.key});

  static const finish = OnboardingEvent<void>('finish');

  @override
  Widget build(BuildContext context) => const Text('Explore');
}
