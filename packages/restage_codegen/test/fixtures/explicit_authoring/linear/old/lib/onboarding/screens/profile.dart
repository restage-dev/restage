import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'profile.rsscreen.g.dart';

@ScreenSource(id: 'profile')
final class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  static const finish = OnboardingEvent<void>('finish');

  @override
  Widget build(BuildContext context) => const Text('Profile');
}
