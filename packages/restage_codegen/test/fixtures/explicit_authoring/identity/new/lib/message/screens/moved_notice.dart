import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'moved_notice.rsscreen.g.dart';

@Screen(id: 'stable_notice', surface: Surface.message)
final class MovedNotice extends StatelessWidget {
  const MovedNotice({super.key});

  static const dismiss = SurfaceEvent<void>('dismiss');

  @override
  Widget build(BuildContext context) => const Text('Moved');
}
