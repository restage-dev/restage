import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'start.rsscreen.g.dart';

@Screen()
final class StartScreen extends StatelessWidget {
  const StartScreen({super.key});

  static const next = SurfaceEvent<void>('next');

  @override
  Widget build(BuildContext context) => const Text('Start');
}
