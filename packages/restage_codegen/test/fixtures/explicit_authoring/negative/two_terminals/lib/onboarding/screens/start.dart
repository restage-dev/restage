import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/start.restage.g.dart';

@Screen()
final class TerminalStart extends StatelessWidget {
  const TerminalStart({super.key});

  static const finish = SurfaceEvent<void>('finish');
  static const cancel = SurfaceEvent<void>('cancel');

  @override
  Widget build(BuildContext context) => const Text('Start');
}
