import 'package:flutter/foundation.dart';

enum AuthoringRefusalKind {
  missingDispatcher,
  ambiguousDispatcher,
  staleCallback,
  callbackRefused,
  unmountedContext,
  recordedWithoutHost,
  recordedHostGone,
}

void reportAuthoringRefusal({
  required AuthoringRefusalKind refusal,
  String? detail,
  bool recorded = false,
  @visibleForTesting bool? throwOnRefusal,
  @visibleForTesting void Function(FlutterErrorDetails details)? reportError,
}) {
  // A generated mount's event names the fix in the mount, not in a call
  // the author wrote.
  final fromMount = recorded ||
      refusal == AuthoringRefusalKind.recordedWithoutHost ||
      refusal == AuthoringRefusalKind.recordedHostGone;
  const withoutHostHint =
      ' Try regenerating the mount with `dart run build_runner build`.';
  const hostGoneHint =
      " Try keeping the callback only while the mount's surface is shown.";
  // A route a surface pushes is built under the navigator, outside it.
  const routeHint = ' On a route the surface pushes, wrap the route\'s '
      'content in `InheritedTheme.capture(from: context, to: '
      'Navigator.of(context).context).wrap(...)`, with the context that '
      "pushes it. A paywall's next screen that its delivered design shows "
      'keeps its push: try mounting the paywall with its generated '
      "`<Paywall>Surface`, whose copy carries the screen's events.";
  const contextHint = ' Try calling `context.surfaceEvent(...)` with the '
      'context of the widget that builds the button, inside the surface that '
      'handles the event.';
  final (reason, hint) = switch (refusal) {
    AuthoringRefusalKind.missingDispatcher => (
        'no dispatcher is available',
        fromMount ? withoutHostHint : '$contextHint$routeHint',
      ),
    AuthoringRefusalKind.ambiguousDispatcher => (
        'dispatcher ownership is ambiguous',
        ' Try showing the generated mount in one place at a time.',
      ),
    AuthoringRefusalKind.staleCallback => (
        'the flow step that built the callback is no longer current',
        ' Try building the callback in the step that shows it, so a later '
            'step never runs an earlier one\'s callback.',
      ),
    AuthoringRefusalKind.callbackRefused => (
        'callback dispatch is not admitted',
        ' Try firing the event from a tap on the surface that shows it, not '
            'from a callback another surface\'s handler runs.',
      ),
    AuthoringRefusalKind.unmountedContext => (
        'the widget that built the callback is no longer mounted',
        fromMount ? hostGoneHint : contextHint,
      ),
    AuthoringRefusalKind.recordedWithoutHost => (
        "no surface hosts the generated mount's events",
        withoutHostHint,
      ),
    AuthoringRefusalKind.recordedHostGone => (
        'the surface the generated mount showed is no longer mounted',
        hostGoneHint,
      ),
  };
  final who = fromMount
      ? 'A generated mount refused a recorded event'
      : 'context.surfaceEvent refused authored event dispatch';
  final message = '[restage] $who: '
      '$reason${detail == null ? '' : ' ($detail)'}.$hint';
  if (throwOnRefusal ?? kDebugMode) throw AssertionError(message);
  (reportError ?? FlutterError.reportError)(
    FlutterErrorDetails(
      exception: StateError(message),
      library: 'restage',
      context: ErrorDescription('handling an authored event callback'),
    ),
  );
}
