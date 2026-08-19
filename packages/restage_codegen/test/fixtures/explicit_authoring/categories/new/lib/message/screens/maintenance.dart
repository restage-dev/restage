import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'maintenance.rsscreen.g.dart';

@Screen(surface: Surface.message)
final class MaintenanceNotice extends StatelessWidget {
  const MaintenanceNotice({super.key});

  static const dismiss = SurfaceEvent<void>('dismiss');

  @override
  Widget build(BuildContext context) => const Text('Maintenance');
}
