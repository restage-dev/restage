import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/default_policy_showcase.restage.g.dart';

@Screen(id: 'default_policy_showcase', surface: Surface.general)
final class DefaultPolicyShowcase extends StatelessWidget {
  const DefaultPolicyShowcase({super.key});

  static const activate = SurfaceEvent<void>('activate');
  static const inspect = SurfaceEvent<void>('inspect');

  @override
  Widget build(BuildContext context) => Column(
        children: [
          FilledButton(
            onPressed: context.surfaceEvent(activate),
            child: const Text('Activate'),
          ),
          GestureDetector(
            onTap: context.surfaceEvent(inspect),
            child: const Text('Inspect'),
          ),
        ],
      );
}
