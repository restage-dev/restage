import 'package:flutter/widgets.dart';

import 'event_dispatch_admission.dart';
import '../flow/flow_descriptors.dart';
import 'authoring_dispatch_access.dart';
import 'authoring_refusal_diagnostic.dart';
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
  final access = captureAuthoringDispatcherAccess(
    activeSurfaceEventDispatcher,
  );
  return _flowEvent(
    AuthoringHelperKind.onboardingEvent,
    event,
    value,
    dispatcher: access.dispatcher,
    captureRefusal: access.refusal,
  );
}

/// Returns a callback that fires a neutral flow screen event.
///
/// In a codegen-built screen, this call is replaced at build time with a
/// descriptor event reference and never executes at runtime.
VoidCallback surfaceEvent<T, V extends T>(
  SurfaceEvent<T> event, [
  V? value,
]) {
  final access = captureAuthoringDispatcherAccess(
    activeSurfaceEventDispatcher,
  );
  return _flowEvent(
    AuthoringHelperKind.surfaceEvent,
    event,
    value,
    dispatcher: access.dispatcher,
    captureRefusal: access.refusal,
  );
}

/// Returns a flow event callback bound to the nearest mounted dispatcher.
VoidCallback surfaceEventWithContext<T, V extends T>(
  BuildContext context,
  SurfaceEvent<T> event, [
  V? value,
]) {
  final access = captureAuthoringDispatcherAccess(
    () => surfaceEventDispatcherOf(context),
  );
  return _flowEvent(
    AuthoringHelperKind.surfaceEventWithContext,
    event,
    value,
    dispatcher: access.dispatcher,
    captureRefusal: access.refusal,
  );
}

VoidCallback _flowEvent<T, V extends T>(
  AuthoringHelperKind helper,
  SurfaceEvent<T> event,
  V? value, {
  required SurfaceEventHandler? dispatcher,
  required AuthoringRefusalKind? captureRefusal,
}) {
  void onRefused(AuthoringRefusalKind refusal) {
    reportAuthoringRefusal(
      helper: helper,
      refusal: refusal,
    );
  }

  return () {
    if (dispatcher != null) {
      RestageFlowEventDispatchRegistry.runWithControllerEventRefusal<void>(
        body: () => dispatcher(event.id, value),
        onRefused: () => onRefused(AuthoringRefusalKind.callbackRefused),
      );
      return;
    }
    onRefused(captureRefusal ?? AuthoringRefusalKind.missingDispatcher);
  };
}
