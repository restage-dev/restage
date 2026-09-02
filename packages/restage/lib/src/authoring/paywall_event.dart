import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'authoring_refusal_diagnostic.dart';
import 'event_dispatcher.dart';
import 'paywall_event_dispatch.dart';

/// Returns a callback that fires a paywall event with the given [name] and
/// optional [args].
///
/// In a codegen-built paywall, this call is replaced at build time with an
/// RFW `event 'name' { ... }` reference and never executes at runtime.
///
/// In a non-codegen runtime context (e.g. local debug preview via `runApp`
/// of an annotated paywall class), the returned callback captures the exact
/// [RestagePaywallEventDispatcher] registration that built it. It refuses once
/// that registration is replaced or disposed.
///
/// If no dispatcher is mounted at construction time, the callback asserts
/// in debug builds (developers see the misuse loudly) and reports through
/// [FlutterError] in release so crash-reporters surface it. A no-codegen,
/// no-dispatcher tap should not silently no-op in production.
///
/// The codegen pattern-matches on the function identifier (`paywallEvent`),
/// the literal first argument (the event name), and the literal `args:` map.
VoidCallback paywallEvent(
  String name, {
  Map<String, Object?> args = const <String, Object?>{},
}) {
  void onRefused(AuthoringRefusalKind refusal) {
    reportAuthoringRefusal(
      helper: AuthoringHelperKind.paywallEvent,
      refusal: refusal,
    );
  }

  final dispatcher = RestagePaywallEventDispatchAuthority.capture(
    onRefused: onRefused,
  );
  return () {
    if (dispatcher != null) {
      dispatcher(name, args);
      return;
    }
    onRefused(AuthoringRefusalKind.missingDispatcher);
  };
}
