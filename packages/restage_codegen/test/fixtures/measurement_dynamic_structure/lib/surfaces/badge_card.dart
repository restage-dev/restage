import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import '../widgets/dynamic_widgets.dart';

part 'restage.generated/badge_card.restage.g.dart';

@Screen(id: 'badge_card', surface: Surface.general)
final class BadgeCardScreen extends StatelessWidget {
  const BadgeCardScreen({super.key});

  static const open = SurfaceEvent<void>('open');

  @override
  Widget build(BuildContext context) => Column(
        children: [
          BadgeCard(title: 'Pro', badge: 'Popular', onTap: surfaceEvent(open)),
        ],
      );
}
