import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/ready_step.restage.g.dart';

/// Last step.
@Screen()
final class ReadyStep extends StatelessWidget {
  const ReadyStep({super.key});

  static const finish = SurfaceEvent<void>('finish');

  @override
  Widget build(BuildContext context) => Center(
        child: FilledButton(
          onPressed: surfaceEvent(finish),
          child: const Text('Start'),
        ),
      );
}
