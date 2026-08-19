import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/colocated.restage.g.dart';

@Screen(id: 'first_notice', surface: Surface.general)
final class FirstColocatedNotice extends StatelessWidget {
  const FirstColocatedNotice({super.key});

  static const dismiss = SurfaceEvent<void>('dismiss');

  @override
  Widget build(BuildContext context) => const Text('First');
}

@Screen(id: 'second_notice', surface: Surface.general)
final class SecondColocatedNotice extends StatelessWidget {
  const SecondColocatedNotice({super.key});

  static const dismiss = SurfaceEvent<void>('dismiss');

  @override
  Widget build(BuildContext context) => const Text('Second');
}
