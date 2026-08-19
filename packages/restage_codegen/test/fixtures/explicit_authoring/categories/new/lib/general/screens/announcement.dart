import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'announcement.rsscreen.g.dart';

@Screen(surface: Surface.general)
final class FeatureAnnouncement extends StatelessWidget {
  const FeatureAnnouncement({super.key});

  static const dismiss = SurfaceEvent<void>('dismiss');

  @override
  Widget build(BuildContext context) => const Text('Announcement');
}
