import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/failure.restage.g.dart';

@ScreenSource(id: 'failure')
final class FailureScreen extends StatelessWidget {
  const FailureScreen({super.key});

  static const finish = OnboardingEvent<void>('finish');

  @override
  Widget build(BuildContext context) => const Text('Failure');
}
