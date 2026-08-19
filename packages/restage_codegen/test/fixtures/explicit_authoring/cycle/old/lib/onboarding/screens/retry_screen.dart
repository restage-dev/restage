import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'retry_screen.rsscreen.g.dart';

@ScreenSource(id: 'retry_screen')
final class RetryScreen extends StatelessWidget {
  const RetryScreen({super.key});

  static const failed = OnboardingEvent<void>('failed');
  static const succeeded = OnboardingEvent<void>('succeeded');

  @override
  Widget build(BuildContext context) => const Text('Retry');
}
