import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import '../onboarding/flows/minimal_stats.dart';

/// Hosts a surface containing the custom StatBadge widget.
/// The generated mount supports delivered content and a compiled fallback.
class MinimalCustomWidgetDemo extends StatelessWidget {
  /// Creates the custom-widget gallery host.
  const MinimalCustomWidgetDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return MinimalStatsFlowSurface(
      unavailable: const FlowUnavailablePolicy.hide(),
      onComplete: (result) => Navigator.of(context).maybePop(),
      onFlowUnavailable: (error) => Navigator.of(context).maybePop(),
    );
  }
}
