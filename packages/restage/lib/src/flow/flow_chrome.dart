import 'package:flutter/widgets.dart';

/// Visual tokens for the **built-in** flow chrome — the back/skip affordances a
/// flow surface draws by default.
///
/// This is the *Theme* rung of the chrome customization ladder: it restyles the
/// default affordances (the icon, its color, size, and tap padding; the skip
/// label and its text style) **without** changing their layout or position. For
/// per-affordance widget replacement use the *Slots* rung
/// (`backBuilder`/`skipBuilder`); for full layout control use the *Layout* rung
/// (`chromeBuilder`/`persistentChromeBuilder`).
///
/// Every token is optional; a null token keeps the platform-appropriate
/// default the surface would otherwise use.
@immutable
final class FlowChromeTheme {
  /// Creates a chrome theme. Any omitted token falls back to the surface's
  /// platform-appropriate default.
  const FlowChromeTheme({
    this.backIcon,
    this.color,
    this.size,
    this.padding,
    this.skipLabel,
    this.skipTextStyle,
  });

  /// Icon for the back affordance. Null uses the platform-adaptive default
  /// (a thin chevron on iOS/macOS, the standard arrow elsewhere).
  final IconData? backIcon;

  /// Tint for the back/skip affordances. Null uses the default chrome tint.
  final Color? color;

  /// Size of the back icon in logical pixels. Null uses the default.
  final double? size;

  /// Padding around each affordance (its tap target). Null uses the default.
  final EdgeInsetsGeometry? padding;

  /// Text shown on the skip affordance. Null uses the default (`Skip`).
  final String? skipLabel;

  /// Text style for the skip affordance. Null uses the default skip style
  /// (tinted by [color]).
  final TextStyle? skipTextStyle;

  /// Returns a copy of this theme with the given tokens replaced.
  ///
  /// Like `ThemeData.copyWith`, this overrides only the tokens you pass; passing
  /// `null` for a token keeps the existing value rather than clearing it. To
  /// reset a token to its platform default, construct a new [FlowChromeTheme].
  FlowChromeTheme copyWith({
    IconData? backIcon,
    Color? color,
    double? size,
    EdgeInsetsGeometry? padding,
    String? skipLabel,
    TextStyle? skipTextStyle,
  }) {
    return FlowChromeTheme(
      backIcon: backIcon ?? this.backIcon,
      color: color ?? this.color,
      size: size ?? this.size,
      padding: padding ?? this.padding,
      skipLabel: skipLabel ?? this.skipLabel,
      skipTextStyle: skipTextStyle ?? this.skipTextStyle,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is FlowChromeTheme &&
        other.backIcon == backIcon &&
        other.color == color &&
        other.size == size &&
        other.padding == padding &&
        other.skipLabel == skipLabel &&
        other.skipTextStyle == skipTextStyle;
  }

  @override
  int get hashCode => Object.hash(
        backIcon,
        color,
        size,
        padding,
        skipLabel,
        skipTextStyle,
      );
}

/// A runtime-honest snapshot of the flow's chrome-relevant state, passed to the
/// *Layout*-rung builders ([FlowChromeBuilder] / [FlowPersistentChromeBuilder]).
///
/// Carries only signals the runtime can stand behind. There is deliberately no
/// "step N of M": a flow can branch (decision states, sub-flows), so a total
/// step count is not knowable in general — a progress indicator is the author's
/// to derive (they authored the flow's shape and have [screenId]).
@immutable
final class FlowChromeState {
  /// Creates a chrome-state snapshot.
  const FlowChromeState({
    required this.onBack,
    required this.onSkip,
    required this.canBack,
    required this.canSkip,
    required this.isForward,
    required this.screenId,
    required this.isComplete,
    required this.isBusy,
  });

  /// Pops to the previous screen (the controller's history pop). A no-op when
  /// [canBack] is false.
  final VoidCallback onBack;

  /// Requests the reserved skip action. A no-op when [canSkip] is false.
  final VoidCallback onSkip;

  /// Whether there is a prior screen to navigate back to.
  final bool canBack;

  /// Whether the current screen offers a skip destination.
  final bool canSkip;

  /// Whether the most recent / in-flight transition is a forward push (`true`)
  /// rather than a back pop (`false`).
  final bool isForward;

  /// The current screen's state id, or null when no screen is mounted.
  final String? screenId;

  /// Whether the flow has reached an end state and finished. Custom chrome uses
  /// this to collapse once the flow completes.
  final bool isComplete;

  /// Whether an interaction would currently be a no-op because the controller
  /// is mid-work (a transition or host action is in flight). Custom chrome uses
  /// this to keep affordances inert while the flow is busy.
  final bool isBusy;

  // Equality is over the value fields only. [onBack] / [onSkip] are behavioral
  // callbacks (closure identity, not value state) — bound to the controller and
  // rebuilt each frame — so including them would make two otherwise-identical
  // snapshots unequal whenever the callbacks are distinct instances. Custom
  // chrome keys on the value signals (canBack/canSkip/isForward/screenId/
  // isComplete/isBusy); each rebuild still receives fresh, working callbacks.
  @override
  bool operator ==(Object other) {
    return other is FlowChromeState &&
        other.canBack == canBack &&
        other.canSkip == canSkip &&
        other.isForward == isForward &&
        other.screenId == screenId &&
        other.isComplete == isComplete &&
        other.isBusy == isBusy;
  }

  @override
  int get hashCode => Object.hash(
        canBack,
        canSkip,
        isForward,
        screenId,
        isComplete,
        isBusy,
      );
}

/// Builds a single chrome affordance (the *Slots* rung). [onAction] performs
/// the affordance's intent — popping for a back slot, skipping for a skip slot.
/// The SDK positions the returned widget; the widget owns its own
/// [Semantics] (the built-in chrome supplies its own; a custom slot widget must
/// supply its own so it stays screen-reader-reachable).
typedef FlowChromeAffordanceBuilder = Widget Function(
  BuildContext context,
  VoidCallback onAction,
);

/// Lays out the chrome around a single flow screen (the *Layout* rung,
/// per-screen). Lives *inside* the animated slot, so it animates with the
/// screen. [screen] is this screen's rendered widget; compose chrome around or
/// over it (e.g. a [Stack] or [Column]) and return the composed widget.
typedef FlowChromeBuilder = Widget Function(
  BuildContext context,
  FlowChromeState state,
  Widget screen,
);

/// Frames the whole flow (the *Layout* rung, persistent). Lives *outside* the
/// transition, so it stays put while screens animate beneath. [flowBody] is the
/// animated screen stack; compose persistent chrome (a top progress bar, a
/// persistent close) around it and return the framed flow.
typedef FlowPersistentChromeBuilder = Widget Function(
  BuildContext context,
  FlowChromeState state,
  Widget flowBody,
);
