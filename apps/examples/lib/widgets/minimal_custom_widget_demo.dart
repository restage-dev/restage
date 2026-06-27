import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import '../onboarding/flows/minimal_stats.dart';

/// Gallery host for the custom-widget starter.
///
/// It renders a small delivered surface (`starter_stats`) that uses your own
/// `@RestageWidget` ([StatBadge]). The badge's composition is inlined into the
/// blob, so what you see is *your* widget rendered through RFW as real Flutter
/// widgets from a server-delivered blob — not a local widget mount.
class MinimalCustomWidgetDemo extends StatelessWidget {
  /// Creates the custom-widget gallery host.
  const MinimalCustomWidgetDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return RestageOnboarding<MinimalStatsResult>(
      flow: MinimalStatsFlowDescriptor.ref,
      unavailable: const FlowUnavailablePolicy.hide(),
      onComplete: (result) => Navigator.of(context).maybePop(),
      onFlowUnavailable: (error) => Navigator.of(context).maybePop(),
    );
  }
}
