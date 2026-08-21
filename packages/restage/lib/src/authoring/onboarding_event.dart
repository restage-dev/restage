import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../flow/flow_descriptors.dart';
import 'onboarding_event_dispatcher.dart';

/// Returns a callback that fires a flow event.
///
/// In a codegen-built flow screen, this call is replaced at build time
/// with a descriptor event reference and never executes at runtime.
@Deprecated('Use surfaceEvent instead.')
VoidCallback onboardingEvent<T, V extends T>(
  SurfaceEvent<T> event, [
  V? value,
]) {
  return _flowEvent('onboardingEvent', event, value);
}

/// Returns a callback that fires a neutral flow screen event.
///
/// In a codegen-built screen, this call is replaced at build time with a
/// descriptor event reference and never executes at runtime.
VoidCallback surfaceEvent<T, V extends T>(
  SurfaceEvent<T> event, [
  V? value,
]) {
  return _flowEvent('surfaceEvent', event, value);
}

VoidCallback _flowEvent<T, V extends T>(
  String helperName,
  SurfaceEvent<T> event,
  V? value,
) {
  final dispatcher = activeSurfaceEventDispatcher();
  return () {
    if (dispatcher != null) {
      dispatcher(event.id, value);
      return;
    }
    _reportNoDispatcher(helperName, <String, Object?>{
      'eventId': event.id,
      'value': value,
    });
  };
}

void _reportNoDispatcher(String helperName, Map<String, Object?> details) {
  assert(
    false,
    '[restage] $helperName invoked without a '
    'RestageEventDispatcher in scope. Either run this widget under '
    'a Restage surface runtime or use restage_codegen so the helper is replaced '
    'with a flow event reference at build time. details=$details',
  );
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: StateError(
        '[restage] $helperName invoked without a '
        'RestageEventDispatcher: $details',
      ),
      library: 'restage',
      context: ErrorDescription('handling a surface authoring helper tap'),
    ),
  );
}
