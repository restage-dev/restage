import 'package:flutter/widgets.dart';

import 'event_dispatch_admission.dart';
import '../flow/flow_descriptors.dart';
import 'authoring_dispatch_access.dart';
import 'authoring_refusal_diagnostic.dart';
import 'onboarding_event_dispatcher.dart';
import 'paywall_event_dispatch.dart';

/// Returns a callback that fires a flow event.
///
/// In a codegen-built flow screen, this call is replaced at build time
/// with a descriptor event reference and never executes at runtime.
@Deprecated('Use surfaceEvent instead.')
void Function([Object?]) onboardingEvent<T, V extends T>(
  SurfaceEvent<T> event, [
  V? value,
]) {
  final access = captureAuthoringDispatcherAccess(
    () => surfaceEventDispatcherFor(event.id),
  );
  return _flowEvent(
    AuthoringHelperKind.onboardingEvent,
    event,
    value,
    dispatcher: access.dispatcher,
    captureRefusal: access.refusal,
    refusalDetail: access.detail,
  );
}

/// Returns a screen-event callback; widget callback values replace [value].
/// Codegen replaces this call with a descriptor event reference.
///
/// Outside a flow, a paywall receives it as `PaywallCustomEvent` named
/// `event.id`, with a map value as its args or any other value as
/// `args['value']`.
void Function([Object?]) surfaceEvent<T, V extends T>(
  SurfaceEvent<T> event, [
  V? value,
]) {
  // A standalone paywall owns the events it builds.
  if (RestagePaywallEventDispatchAuthority.isBuildingStandalone) {
    return _paywallEvent(event, value);
  }
  final access = captureAuthoringDispatcherAccess(
    () => surfaceEventDispatcherFor(event.id),
  );
  if (access.dispatcher == null &&
      access.refusal == AuthoringRefusalKind.missingDispatcher &&
      RestagePaywallEventDispatchAuthority.hasDispatcher) {
    return _paywallEvent(event, value);
  }
  return _flowEvent(
    AuthoringHelperKind.surfaceEvent,
    event,
    value,
    dispatcher: access.dispatcher,
    captureRefusal: access.refusal,
    refusalDetail: access.detail,
  );
}

void Function([Object?]) _paywallEvent<T, V extends T>(
  SurfaceEvent<T> event,
  V? value,
) {
  void onRefused(AuthoringRefusalKind refusal) => reportAuthoringRefusal(
        helper: AuthoringHelperKind.surfaceEvent,
        refusal: refusal,
      );
  final paywall = RestagePaywallEventDispatchAuthority.capture(
    onRefused: onRefused,
  );
  return ([Object? widgetValue = _noWidgetValue]) {
    if (paywall == null) {
      onRefused(AuthoringRefusalKind.missingDispatcher);
      return;
    }
    final dispatched =
        identical(widgetValue, _noWidgetValue) ? value : widgetValue;
    paywall(
        event.id,
        switch (dispatched) {
          null => const <String, Object?>{},
          final Map<String, Object?> args => args,
          _ => <String, Object?>{'value': dispatched},
        });
  };
}

/// Returns a flow event callback bound to the nearest mounted dispatcher.
void Function([Object?]) surfaceEventWithContext<T, V extends T>(
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
    refusalDetail: access.detail,
  );
}

void Function([Object?]) _flowEvent<T, V extends T>(
  AuthoringHelperKind helper,
  SurfaceEvent<T> event,
  V? value, {
  required SurfaceEventHandler? dispatcher,
  required AuthoringRefusalKind? captureRefusal,
  String? refusalDetail,
}) {
  void onRefused(AuthoringRefusalKind refusal, [String? detail]) {
    reportAuthoringRefusal(
      helper: helper,
      refusal: refusal,
      detail: detail,
    );
  }

  return ([Object? widgetValue = _noWidgetValue]) {
    if (dispatcher != null) {
      final dispatched =
          identical(widgetValue, _noWidgetValue) ? value : widgetValue;
      RestageFlowEventDispatchRegistry.runWithControllerEventRefusal<void>(
        body: () => dispatcher(event.id, dispatched),
        onRefused: () => onRefused(AuthoringRefusalKind.callbackRefused),
      );
      return;
    }
    onRefused(
      captureRefusal ?? AuthoringRefusalKind.missingDispatcher,
      refusalDetail,
    );
  };
}

// Marks a call that carried no widget value.
const Object _noWidgetValue = Object();
