import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

/// Maps a paywall [event] to a short line the demo host shows as a `SnackBar`,
/// so every tappable element in a *delivered* paywall gives visible feedback
/// instead of silently doing nothing.
///
/// This is demo affordance feedback, not real behavior. The example only
/// confirms the tap was received so the surface never reads as broken.
///
/// Returns `null` for events the host handles elsewhere (a [PaywallLoadFailed]
/// shows the paywall's `fallbackBuilder`, not a SnackBar) or does not surface,
/// so the caller can skip the SnackBar for those.
String? demoPaywallEventLabel(RestageEvent event) {
  if (event is PaywallCustomEvent) {
    return switch (event.eventName) {
      'terms' || 'terms_of_service' => 'Would open the Terms of Service',
      'privacy' || 'privacy_policy' => 'Would open the Privacy Policy',
      'subscription_info' => 'Would open the subscription details',
      'restore_purchases' => 'Restore purchases',
      _ => 'Event: ${event.eventName}',
    };
  }
  return null;
}

/// Shows a `SnackBar` for [event] (via [demoPaywallEventLabel]) so a tap on a
/// delivered paywall has a visible result in the demo. No-ops for events that
/// produce no label (for example a load failure, which shows the paywall's
/// `fallbackBuilder` instead).
void showDemoPaywallEventFeedback(BuildContext context, RestageEvent event) {
  final label = demoPaywallEventLabel(event);
  if (label == null) return;
  showDemoFeedback(context, label);
}

/// Shows [label] as a floating `SnackBar`, the demo's stand-in for real
/// behavior.
void showDemoFeedback(BuildContext context, String label) {
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

/// The demo's answers to a paywall's own callbacks: closing returns to the
/// gallery, and every other action shows what an app would do.
final class PaywallDemoActions {
  /// Actions for the paywall shown in [context].
  const PaywallDemoActions(this.context);

  /// The paywall's context.
  final BuildContext context;

  /// Returns to the gallery.
  void close() => Navigator.of(context).maybePop();

  /// Continues with [plan].
  void plan(String plan) => showDemoFeedback(context, 'Continue: $plan');

  /// Continues with [tier] billed per [term].
  void tierTerm(String tier, String term) =>
      showDemoFeedback(context, 'Continue: $tier, $term');

  /// Continues to the purchase.
  void proceed() => showDemoFeedback(context, 'Continue');

  /// Opens the terms of service.
  void terms() => showDemoFeedback(context, 'Would open the Terms of Service');

  /// Opens the privacy policy.
  void privacy() => showDemoFeedback(context, 'Would open the Privacy Policy');

  /// Opens the subscription details.
  void subscriptionInfo() =>
      showDemoFeedback(context, 'Would open the subscription details');

  /// Restores earlier purchases.
  void restore() => showDemoFeedback(context, 'Restore purchases');
}
