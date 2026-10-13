import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'authoring_refusal_diagnostic.dart';
import 'event_dispatcher.dart';
import 'paywall_event_dispatch.dart';

/// Returns a callback that fires [name] with optional [args].
///
/// Codegen replaces literal event names and `args:` maps with RFW events.
/// Local previews retain the creating [RestagePaywallEventDispatcher]
/// registration and refuse calls after it is replaced or disposed.
/// A missing dispatcher asserts in debug and reports through [FlutterError]
/// in release. Value callbacks pass the widget's value as `args['value']`.
void Function([Object?]) paywallEvent(
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
  return ([Object? widgetValue = _noWidgetValue]) {
    if (dispatcher != null) {
      dispatcher(
        name,
        identical(widgetValue, _noWidgetValue)
            ? args
            : <String, Object?>{...args, 'value': widgetValue},
      );
      return;
    }
    onRefused(AuthoringRefusalKind.missingDispatcher);
  };
}

// Marks a call that carried no widget value.
const Object _noWidgetValue = Object();
