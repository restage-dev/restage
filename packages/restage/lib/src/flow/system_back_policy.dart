import 'package:flutter/widgets.dart';

/// What happens on a platform system-back gesture (Android predictive back /
/// iOS edge-swipe) once *in-flow* back navigation is exhausted — the user is at
/// a flow's first screen (or a barrier) with no prior screen to pop to.
///
/// While in-flow back is still available the flow always consumes system-back
/// and navigates back; this policy only decides the exhausted case. Set it
/// per-flow (the default is [popHost]).
sealed class SystemBackPolicy {
  const SystemBackPolicy();

  /// Let system-back propagate to the host. The host's own structure then
  /// decides the outcome with no decision on the flow's part: if the flow was
  /// pushed as a route it dismisses back to the host; if the flow is the app
  /// root the app backgrounds (the Android-idiomatic "back at root = leave").
  /// The least-surprising native default.
  static const SystemBackPolicy popHost = _PopHostSystemBackPolicy();

  /// Trap system-back: back at the first screen is a no-op — a mandatory flow
  /// the user cannot back out of.
  const factory SystemBackPolicy.block() = _BlockSystemBackPolicy;

  /// Treat exhausted back as dismissing the flow, via the same reserved `skip`
  /// signal a skip affordance uses (the host's skip handler completes/closes
  /// the flow), without touching the host's navigation stack.
  ///
  /// **Requires a skip destination** — a screen `on['skip']` transition or a
  /// declared `customEvents['skip']`. Without one there is nothing to dismiss
  /// to, so exhausted back is a no-op (the user is effectively trapped, as with
  /// [SystemBackPolicy.block]); the rendering surface logs a debug warning in
  /// that case. Use [popHost] or [block] when the flow has no skip destination.
  const factory SystemBackPolicy.complete() = _CompleteSystemBackPolicy;

  /// Run a host callback when system-back is exhausted — a bespoke escape hatch
  /// (e.g. show a confirm dialog, or `Navigator.of(context).maybePop()`).
  const factory SystemBackPolicy.onExhausted(
    void Function(BuildContext context) handler,
  ) = _CallbackSystemBackPolicy;

  /// Whether system-back should propagate to the host once in-flow back is
  /// exhausted (the surface sets `PopScope.canPop` to this when `!canBack`).
  bool get propagatesToHost => this is _PopHostSystemBackPolicy;

  /// Applies the exhausted-back behavior. [dismiss] routes the reserved skip
  /// signal (used by [SystemBackPolicy.complete]).
  void handleExhausted(
    BuildContext context, {
    required void Function() dismiss,
  }) {
    switch (this) {
      case _PopHostSystemBackPolicy():
      case _BlockSystemBackPolicy():
        break;
      case _CompleteSystemBackPolicy():
        dismiss();
      case _CallbackSystemBackPolicy(:final handler):
        handler(context);
    }
  }
}

final class _PopHostSystemBackPolicy extends SystemBackPolicy {
  const _PopHostSystemBackPolicy();
}

final class _BlockSystemBackPolicy extends SystemBackPolicy {
  const _BlockSystemBackPolicy();
}

final class _CompleteSystemBackPolicy extends SystemBackPolicy {
  const _CompleteSystemBackPolicy();
}

final class _CallbackSystemBackPolicy extends SystemBackPolicy {
  const _CallbackSystemBackPolicy(this.handler);

  final void Function(BuildContext context) handler;
}
