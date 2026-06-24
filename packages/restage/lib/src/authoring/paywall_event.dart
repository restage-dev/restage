import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'event_dispatcher.dart';

/// Returns a callback that fires a paywall event with the given [name] and
/// optional [args].
///
/// In a codegen-built paywall, this call is replaced at build time with an
/// RFW `event 'name' { ... }` reference and never executes at runtime.
///
/// In a non-codegen runtime context (e.g. local debug preview via `runApp`
/// of an annotated paywall class), the returned callback delivers
/// `(name, args)` to the [RestagePaywallEventDispatcher] that was active
/// when this call was made (during the host's `build()`). The dispatcher
/// is captured at construction time so a sibling paywall mounting between
/// build and tap can't steal events.
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
  // Capture the active dispatcher now (at build time), not at tap time.
  // A sibling paywall mounted between build and tap would otherwise steal
  // events via the stack-top read.
  final dispatcher = activeDispatcher();
  return () {
    if (dispatcher != null) {
      dispatcher(name, args);
      return;
    }
    _reportNoDispatcher('paywallEvent', <String, Object?>{
      'name': name,
      'args': args,
    });
  };
}

/// Surfaces a no-dispatcher invocation. In debug, asserts loudly so
/// developers catch a non-codegen paywall mistake. In release, routes
/// through [FlutterError] so crash-reporters at least see the event
/// rather than the tap silently no-op'ing.
void _reportNoDispatcher(String helperName, Map<String, Object?> details) {
  assert(
      false,
      '[restage] $helperName invoked without a RestagePaywallEventDispatcher '
      'in scope. Either run this widget under RestagePaywall(...) or use '
      'restage_codegen so the helper is replaced with an RFW reference at '
      'build time. details=$details');
  FlutterError.reportError(FlutterErrorDetails(
    exception: StateError(
      '[restage] $helperName invoked without a RestagePaywallEventDispatcher: '
      '$details',
    ),
    library: 'restage',
    context: ErrorDescription('handling a paywall authoring helper tap'),
  ));
}
