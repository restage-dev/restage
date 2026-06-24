import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

/// Maps a paywall [event] to a short line the demo host shows as a `SnackBar`,
/// so every tappable element in a *delivered* paywall gives visible feedback
/// instead of silently doing nothing.
///
/// This is demo affordance feedback, not real behavior: a production app starts
/// an actual purchase flow, restores entitlements, or opens the Terms / Privacy
/// page here. The example only confirms the tap was received so the surface
/// never reads as broken.
///
/// Returns `null` for events the host handles elsewhere (a [PaywallLoadFailed]
/// is shown through the paywall's `errorBuilder`, not a SnackBar) or does not
/// surface, so the caller can skip the SnackBar for those.
String? demoPaywallEventLabel(RestageEvent event) {
  if (event is PurchaseInitiated) {
    return 'Starting purchase: ${event.productId}';
  }
  if (event is PaywallCustomEvent) {
    return switch (event.eventName) {
      'restore' => 'Restore requested',
      'terms' || 'terms_of_service' => 'Would open the Terms of Service',
      'privacy' || 'privacy_policy' => 'Would open the Privacy Policy',
      'subscription_info' => 'Would open the subscription details',
      _ => 'Event: ${event.eventName}',
    };
  }
  return null;
}

/// Shows a `SnackBar` for [event] (via [demoPaywallEventLabel]) so a tap on a
/// delivered paywall has a visible result in the demo. No-ops for events that
/// produce no label (for example a load failure, surfaced through the paywall's
/// `errorBuilder` instead).
void showDemoPaywallEventFeedback(BuildContext context, RestageEvent event) {
  final label = demoPaywallEventLabel(event);
  if (label == null) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(label),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
}
