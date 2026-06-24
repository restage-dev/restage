import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../flow/flow_descriptors.dart';
import 'onboarding_event_dispatcher.dart';

/// Returns a callback that fires an onboarding flow event.
///
/// In a codegen-built onboarding screen, this call is replaced at build time
/// with a descriptor event reference and never executes at runtime.
VoidCallback onboardingEvent<T, V extends T>(
  OnboardingEvent<T> event, [
  V? value,
]) {
  final dispatcher = activeOnboardingEventDispatcher();
  return () {
    if (dispatcher != null) {
      dispatcher(event.id, value);
      return;
    }
    _reportNoDispatcher('onboardingEvent', <String, Object?>{
      'eventId': event.id,
      'value': value,
    });
  };
}

void _reportNoDispatcher(String helperName, Map<String, Object?> details) {
  assert(
    false,
    '[restage] $helperName invoked without a '
    'RestageOnboardingEventDispatcher in scope. Either run this widget under '
    'RestageOnboarding(...) or use restage_codegen so the helper is replaced '
    'with a flow event reference at build time. details=$details',
  );
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: StateError(
        '[restage] $helperName invoked without a '
        'RestageOnboardingEventDispatcher: $details',
      ),
      library: 'restage',
      context: ErrorDescription('handling an onboarding authoring helper tap'),
    ),
  );
}
