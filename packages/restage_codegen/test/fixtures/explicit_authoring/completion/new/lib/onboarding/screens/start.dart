import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/start.restage.g.dart';

@Screen()
final class StartScreen extends StatelessWidget {
  const StartScreen({super.key});

  static const accept = SurfaceEvent<void>('accept');
  static const decline = SurfaceEvent<void>('decline');

  @override
  Widget build(BuildContext context) => const Text('Start');
}
