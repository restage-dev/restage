import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import '../widgets/dynamic_widgets.dart';

part 'restage.generated/pinned_header.restage.g.dart';

@Screen(id: 'pinned_header', surface: Surface.general)
final class PinnedHeaderScreen extends StatelessWidget {
  const PinnedHeaderScreen({super.key});

  static const open = SurfaceEvent<void>('open');

  @override
  Widget build(BuildContext context) => Column(
        children: [
          PinnedHeader(pinned: true, onTap: surfaceEvent(open)),
        ],
      );
}
