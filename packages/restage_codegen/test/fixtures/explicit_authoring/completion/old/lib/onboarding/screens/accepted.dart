import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/accepted.restage.g.dart';

@ScreenSource(id: 'accepted')
final class AcceptedScreen extends StatelessWidget {
  const AcceptedScreen({super.key});

  static const finish = OnboardingEvent<void>('finish');

  @override
  Widget build(BuildContext context) => const Text('Accepted');
}
