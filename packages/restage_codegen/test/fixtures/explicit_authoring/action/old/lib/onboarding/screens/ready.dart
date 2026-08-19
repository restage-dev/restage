import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/ready.restage.g.dart';

@ScreenSource(id: 'ready')
final class ReadyScreen extends StatelessWidget {
  const ReadyScreen({super.key});

  static const finish = OnboardingEvent<void>('finish');

  @override
  Widget build(BuildContext context) => const Text('Ready');
}
