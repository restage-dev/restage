import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'welcome.rsscreen.g.dart';

@Screen()
final class NeutralWelcome extends StatelessWidget {
  const NeutralWelcome({super.key});

  static const finish = SurfaceEvent<void>('finish');

  @override
  Widget build(BuildContext context) => const Text('Welcome');
}
