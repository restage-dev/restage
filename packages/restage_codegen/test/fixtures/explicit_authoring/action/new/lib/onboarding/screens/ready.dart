import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'ready.rsscreen.g.dart';

@Screen()
final class ReadyScreen extends StatelessWidget {
  const ReadyScreen({super.key});

  static const finish = SurfaceEvent<void>('finish');

  @override
  Widget build(BuildContext context) => const Text('Ready');
}
