import 'package:flutter/foundation.dart';

enum AuthoringHelperKind {
  paywallEvent,
  surfaceEvent,
  onboardingEvent,
  surfaceEventWithContext,
}

enum AuthoringRefusalKind {
  missingDispatcher,
  ambiguousDispatcher,
  callbackRefused,
}

void reportAuthoringRefusal({
  required AuthoringHelperKind helper,
  required AuthoringRefusalKind refusal,
  @visibleForTesting bool? throwOnRefusal,
  @visibleForTesting void Function(FlutterErrorDetails details)? reportError,
}) {
  final helperName = switch (helper) {
    AuthoringHelperKind.paywallEvent => 'paywallEvent',
    AuthoringHelperKind.surfaceEvent => 'surfaceEvent',
    AuthoringHelperKind.onboardingEvent => 'onboardingEvent',
    AuthoringHelperKind.surfaceEventWithContext => 'surfaceEventWithContext',
  };
  final reason = switch (refusal) {
    AuthoringRefusalKind.missingDispatcher => 'no dispatcher is available',
    AuthoringRefusalKind.ambiguousDispatcher =>
      'dispatcher ownership is ambiguous',
    AuthoringRefusalKind.callbackRefused => 'callback dispatch is not admitted',
  };
  final message =
      '[restage] $helperName refused authored event dispatch: $reason.';
  if (throwOnRefusal ?? kDebugMode) throw AssertionError(message);
  (reportError ?? FlutterError.reportError)(
    FlutterErrorDetails(
      exception: StateError(message),
      library: 'restage',
      context: ErrorDescription('handling an authored event callback'),
    ),
  );
}
