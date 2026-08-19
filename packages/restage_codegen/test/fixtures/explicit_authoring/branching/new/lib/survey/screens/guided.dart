import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'guided.rsscreen.g.dart';

@Screen()
final class GuidedScreen extends StatelessWidget {
  const GuidedScreen({super.key});

  static const finish = SurfaceEvent<void>('finish');

  @override
  Widget build(BuildContext context) => const Text('Guided');
}
