import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'explore.rsscreen.g.dart';

@Screen()
final class ExploreScreen extends StatelessWidget {
  const ExploreScreen({super.key});

  static const finish = SurfaceEvent<void>('finish');

  @override
  Widget build(BuildContext context) => const Text('Explore');
}
