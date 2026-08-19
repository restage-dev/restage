import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/account.restage.g.dart';

@ScreenSource(id: 'account')
final class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  static const profile = OnboardingEvent<void>('profile');

  @override
  Widget build(BuildContext context) => const Text('Account');
}
