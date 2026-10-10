import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/host_tags.restage.g.dart';

@Screen(id: 'host_tags', surface: Surface.general)
final class HostTags extends StatelessWidget {
  const HostTags({required this.tags, super.key});

  final List<String> tags;

  static const pick = SurfaceEvent<String>('pick');

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (final tag in tags)
            TextButton(
              onPressed: surfaceEvent(pick, tag),
              child: Text(tag),
            ),
        ],
      );
}
