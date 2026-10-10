import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/conditional_tags.restage.g.dart';

@Screen(id: 'conditional_tags', surface: Surface.general)
final class ConditionalTags extends StatelessWidget {
  const ConditionalTags({
    required this.tags,
    required this.enabled,
    required this.eligible,
    super.key,
  });

  final List<String> tags;
  final bool enabled;
  final bool eligible;

  static const pick = SurfaceEvent<String>('pick');

  @override
  Widget build(BuildContext context) {
    final canPick = enabled && eligible;
    return Column(
      children: [
        for (final tag in tags)
          if (canPick)
            GestureDetector(
              onTap: surfaceEvent(pick, tag),
              child: Text(tag),
            )
          else
            GestureDetector(
              onTap: surfaceEvent(pick, 'fallback'),
              child: const Text('Fallback'),
            ),
      ],
    );
  }
}
