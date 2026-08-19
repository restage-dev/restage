import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'duplicate_explicit.rsscreen.g.dart';

@Screen(id: 'same_notice', surface: Surface.general)
final class FirstExplicitScreen extends StatelessWidget {
  const FirstExplicitScreen({super.key});

  @override
  Widget build(BuildContext context) => const Text('First');
}

@Screen(id: 'same_notice', surface: Surface.general)
final class SecondExplicitScreen extends StatelessWidget {
  const SecondExplicitScreen({super.key});

  @override
  Widget build(BuildContext context) => const Text('Second');
}
