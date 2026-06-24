import 'package:flutter/material.dart';

/// Which platform's express-checkout flow this button should
/// represent.
enum ExpressPaymentMethod {
  /// Pick automatically from the runtime platform — `apple` on iOS /
  /// macOS, `google` on Android, neutral fallback elsewhere.
  auto,

  /// Always render the Apple Pay variant.
  apple,

  /// Always render the Google Pay variant.
  google,
}

/// Conversion-CTA button for platform-native express-checkout flows.
///
/// The button picks a payment method (Apple Pay / Google Pay /
/// neutral) and dispatches [onPressed] when tapped — typically wired
/// to a paywall purchase helper. The widget reserves the API surface
/// and catalog metadata used by analytics and the editor; today it
/// renders as a styled Material `FilledButton` with a platform-aware
/// label, while the real platform-rendered express-checkout buttons
/// (with the official Apple Pay / Google Pay assets and the live
/// payment-sheet hand-off) are wired in alongside the billing-channel
/// integration.
class ExpressCheckoutButton extends StatelessWidget {
  /// Const constructor.
  const ExpressCheckoutButton({
    super.key,
    this.onPressed,
    this.paymentMethod = ExpressPaymentMethod.auto,
    this.label,
  });

  /// Fires when the user taps the button. Pass `null` (the default)
  /// to render the button in its disabled state.
  final VoidCallback? onPressed;

  /// Which platform's express-checkout variant to render. Defaults
  /// to [ExpressPaymentMethod.auto].
  final ExpressPaymentMethod paymentMethod;

  /// Overrides the platform-default label (for example
  /// `'Subscribe with Apple Pay'`). When `null`, a sensible default
  /// is chosen based on the resolved payment method.
  final String? label;

  /// Returns the platform-native variant to render, or `null` when no
  /// platform-native variant applies (desktop / unknown platforms,
  /// where the neutral fallback button is shown). The return type
  /// excludes `ExpressPaymentMethod.auto` by construction — `auto` is
  /// an authoring sentinel, never an output of resolution.
  ExpressPaymentMethod? _platformVariant(BuildContext context) {
    switch (paymentMethod) {
      case ExpressPaymentMethod.apple:
        return ExpressPaymentMethod.apple;
      case ExpressPaymentMethod.google:
        return ExpressPaymentMethod.google;
      case ExpressPaymentMethod.auto:
        switch (Theme.of(context).platform) {
          case TargetPlatform.iOS:
          case TargetPlatform.macOS:
            return ExpressPaymentMethod.apple;
          case TargetPlatform.android:
            return ExpressPaymentMethod.google;
          case TargetPlatform.fuchsia:
          case TargetPlatform.linux:
          case TargetPlatform.windows:
            return null;
        }
    }
  }

  String _defaultLabelFor(ExpressPaymentMethod? variant) {
    return switch (variant) {
      ExpressPaymentMethod.apple => 'Buy with Apple Pay',
      ExpressPaymentMethod.google => 'Buy with Google Pay',
      // `auto` is unreachable here — `_platformVariant` never returns
      // it — but the switch needs the case for exhaustiveness. The
      // null branch covers the desktop neutral-fallback path.
      ExpressPaymentMethod.auto || null => 'Continue',
    };
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      child: Text(label ?? _defaultLabelFor(_platformVariant(context))),
    );
  }
}
