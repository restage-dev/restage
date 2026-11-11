import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import '../onboarding/common_events.dart';

/// The close button a surface puts in its app bar. It fires
/// [CommonEvents.dismiss] on whichever surface shows it.
class DismissButton extends StatelessWidget {
  /// Const constructor.
  const DismissButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
        onPressed: context.surfaceEvent(CommonEvents.dismiss),
        tooltip: 'Dismiss',
        icon: Icon(
          Icons.close_rounded,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
}
