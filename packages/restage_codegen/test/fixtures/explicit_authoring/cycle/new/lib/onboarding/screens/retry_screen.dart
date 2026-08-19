import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'retry_screen.rsscreen.g.dart';

@Screen()
final class RetryScreen extends StatelessWidget {
  const RetryScreen({super.key});

  static const failed = SurfaceEvent<void>('failed');
  static const succeeded = SurfaceEvent<void>('succeeded');

  @override
  Widget build(BuildContext context) => const Text('Retry');
}
