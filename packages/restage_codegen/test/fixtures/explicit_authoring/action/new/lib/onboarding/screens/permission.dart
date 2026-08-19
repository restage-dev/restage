import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/permission.restage.g.dart';

@Screen()
final class PermissionScreen extends StatelessWidget {
  const PermissionScreen({super.key});

  static const enable = SurfaceEvent<void>('enable');

  @override
  Widget build(BuildContext context) => const Text('Permission');
}
