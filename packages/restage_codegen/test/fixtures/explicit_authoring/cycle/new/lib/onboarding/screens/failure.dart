import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'failure.rsscreen.g.dart';

@Screen()
final class FailureScreen extends StatelessWidget {
  const FailureScreen({super.key});

  static const finish = SurfaceEvent<void>('finish');

  @override
  Widget build(BuildContext context) => const Text('Failure');
}
