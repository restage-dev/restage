import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'account.rsscreen.g.dart';

@Screen()
final class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  static const profile = SurfaceEvent<void>('profile');

  @override
  Widget build(BuildContext context) => const Text('Account');
}
