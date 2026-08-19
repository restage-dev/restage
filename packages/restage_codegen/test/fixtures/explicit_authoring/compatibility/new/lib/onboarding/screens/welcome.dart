import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'welcome.rsscreen.g.dart';

@Screen()
final class CompatibilityWelcome extends StatelessWidget {
  const CompatibilityWelcome({super.key});

  static const finish = SurfaceEvent<void>('finish');

  @override
  Widget build(BuildContext context) => const Text('Compatibility');
}
