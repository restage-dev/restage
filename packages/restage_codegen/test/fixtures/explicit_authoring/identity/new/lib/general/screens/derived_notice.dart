import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'derived_notice.rsscreen.g.dart';

@Screen(surface: Surface.general)
final class DerivedNotice extends StatelessWidget {
  const DerivedNotice({super.key});

  static const dismiss = SurfaceEvent<void>('dismiss');

  @override
  Widget build(BuildContext context) => const Text('Derived');
}
