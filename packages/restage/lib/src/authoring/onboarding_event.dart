import 'package:flutter/widgets.dart';

import 'event_dispatch_admission.dart';
import 'event_dispatcher.dart' show paywallEventDispatcherAt;
import '../flow/flow_descriptors.dart';
import 'authoring_dispatch_access.dart';
import 'authoring_refusal_diagnostic.dart';
import 'onboarding_event_dispatcher.dart';

/// Authored surface events fired from a widget's own [BuildContext].
extension SurfaceEventContext on BuildContext {
  /// Returns a callback that fires [event] on the surface this widget is
  /// built in. A widget callback value replaces [value], or joins a map
  /// [value] as its `value` entry.
  ///
  /// The surface is found when the callback runs, from this context, without
  /// depending on it. Codegen replaces this call with a descriptor event
  /// reference. Outside a flow, a paywall receives it as `PaywallCustomEvent`
  /// named `event.id`, with a map value as its args or any other value as
  /// `args['value']`.
  void Function([Object?]) surfaceEvent<T, V extends T>(
    SurfaceEvent<T> event, [
    V? value,
  ]) {
    final context = this;
    return ([Object? widgetValue = _noWidgetValue]) => fireSurfaceEventAt(
          context,
          event.id,
          withWidgetValue(value, widgetValue),
        );
  }
}

/// [value] as a callback that received [widgetValue] fires it, as a
/// delivered design does: the widget value replaces [value], or joins a map
/// [value] under `value`.
Object? withWidgetValue(Object? value, Object? widgetValue) {
  if (identical(widgetValue, _noWidgetValue)) return value;
  return value is Map<String, Object?>
      ? <String, Object?>{...value, 'value': widgetValue}
      : widgetValue;
}

/// Marks a callback invoked with no widget value.
const Object noWidgetValue = _noWidgetValue;

/// Fires the event [id] with [value] on the surface [context] is built in:
/// the nearer of its surface dispatcher and a standalone paywall. A
/// [recorded] event's refusals name the generated mount.
void fireSurfaceEventAt(
  BuildContext context,
  String id,
  Object? value, {
  bool recorded = false,
}) {
  // A generated mount's own context, however the build passes it on, fires
  // on the surface the mount shows.
  if (_recordedHosts[context] case final host?) {
    final shown = host.context;
    if (shown == null || !shown.mounted) {
      reportAuthoringRefusal(refusal: AuthoringRefusalKind.recordedHostGone);
      return;
    }
    context = shown;
    recorded = true;
  }
  void refuse(AuthoringRefusalKind refusal, [String? detail]) =>
      reportAuthoringRefusal(
        refusal: refusal,
        detail: detail,
        recorded: recorded,
      );
  if (!context.mounted) {
    refuse(AuthoringRefusalKind.unmountedContext);
    return;
  }
  final surface = surfaceEventDispatcherDepth(context);
  final paywall = paywallEventDispatcherAt(
    context,
    onRefused: (refusal) => refuse(refusal),
  );
  final chosen = paywall != null && (surface == null || paywall.depth > surface)
      ? paywall.depth
      : surface;
  // A surface that no longer shows what the callback was built in refuses.
  if (chosen != null && !isEventEpochCurrent(context, above: chosen)) {
    refuse(AuthoringRefusalKind.callbackRefused);
    return;
  }
  if (paywall != null && (surface == null || paywall.depth > surface)) {
    paywall.dispatch(
      id,
      switch (value) {
        null => const <String, Object?>{},
        final Map<String, Object?> args => args,
        _ => <String, Object?>{'value': value},
      },
    );
    return;
  }
  final access = captureAuthoringDispatcherAccess(
    () => surfaceEventDispatcherOf(context),
  );
  final dispatcher = access.dispatcher;
  if (dispatcher == null) {
    refuse(
      access.refusal ?? AuthoringRefusalKind.missingDispatcher,
      access.detail,
    );
    return;
  }
  RestageFlowEventDispatchRegistry.runWithControllerEventRefusal<void>(
    body: () => dispatcher(id, value),
    onRefused: () => refuse(AuthoringRefusalKind.callbackRefused),
  );
}

// Marks a call that carried no widget value.
const Object _noWidgetValue = Object();

final Expando<_RecordedHost> _recordedHosts = Expando<_RecordedHost>();

// Every surface bound for one generated mount, in the order they bound.
final class _RecordedHost {
  final List<BuildContext> _bound = [];

  // The surface the mount shows: the earliest bound one still mounted whose
  // content is current.
  BuildContext? get context {
    for (final candidate in _bound) {
      if (candidate.mounted && isEventEpochCurrent(candidate, above: -1)) {
        return candidate;
      }
    }
    return null;
  }
}

/// Fires the event [id] recorded by the generated mount [owner] on the
/// surface that mount hosts. Refuses when no surface hosts it or that
/// surface is gone.
void fireRecordedSurfaceEvent(Object? owner, String id, Object? value) {
  final host = owner == null ? null : _recordedHosts[owner];
  final context = host?.context;
  if (context != null && context.mounted) {
    fireSurfaceEventAt(context, id, value, recorded: true);
    return;
  }
  reportAuthoringRefusal(
    refusal: host == null
        ? AuthoringRefusalKind.recordedWithoutHost
        : AuthoringRefusalKind.recordedHostGone,
  );
}

/// [child], a route the generated mount [owner] pushes, or a step mount
/// pushes from [from], inside the event scopes of the surface the mount
/// shows, so the route's events reach that surface.
Widget recordedRoute(
        {Object? owner, BuildContext? from, required Widget child}) =>
    _RecordedRoute(owner: owner, from: from, child: child);

final class _RecordedRoute extends StatefulWidget {
  const _RecordedRoute({this.owner, this.from, required this.child});

  final Object? owner;
  final BuildContext? from;
  final Widget child;

  @override
  State<_RecordedRoute> createState() => _RecordedRouteState();
}

final class _RecordedRouteState extends State<_RecordedRoute> {
  // The surface's scopes, nearest first, captured once as the route first
  // builds; the surface may be gone by a later build.
  // Null when no surface hosts the mount: the route then refuses.
  List<(BuildContext, RestageEventScope)>? _scopes;
  bool _captured = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_captured) return;
    _captured = true;
    _scopes = _capture();
  }

  List<(BuildContext, RestageEventScope)>? _capture() {
    final host = widget.from ??
        (widget.owner == null ? null : _recordedHosts[widget.owner!]?.context);
    if (host == null || !host.mounted) return null;
    final navigator = Navigator.maybeOf(context)?.context;
    if (navigator == null) return const [];
    // A navigator inside the surface already has its scopes above it.
    var inside = false;
    navigator.visitAncestorElements((element) {
      inside = identical(element, host);
      return !inside;
    });
    if (inside) return const [];
    final scopes = <(BuildContext, RestageEventScope)>[];
    var reached = false;
    if (host case final Element element
        when element.widget is RestageEventScope) {
      scopes.add((element, element.widget as RestageEventScope));
    }
    host.visitAncestorElements((element) {
      if (identical(element, navigator)) {
        reached = true;
        return false;
      }
      if (element.widget case final RestageEventScope scope) {
        scopes.add((element, scope));
      }
      return true;
    });
    return reached ? scopes : const [];
  }

  @override
  Widget build(BuildContext context) {
    final scopes = _scopes;
    // Never the scopes of whatever surface the navigator sits in.
    if (scopes == null) {
      return RestageEventEpoch(isCurrent: () => false, child: widget.child);
    }
    var wrapped = widget.child;
    for (final (element, scope) in scopes) {
      wrapped = scope.wrap(element, wrapped);
    }
    return wrapped;
  }
}

/// Makes its own context the target of the events the generated mount
/// [owner] recorded above it.
final class RecordedEventHost extends StatefulWidget {
  /// Hosts [owner]'s recorded events for [child].
  const RecordedEventHost(
      {super.key, required this.owner, required this.child});

  /// The generated mount whose recorded events this host receives.
  final Object owner;

  /// The surface content.
  final Widget child;

  @override
  State<RecordedEventHost> createState() => _RecordedEventHostState();
}

final class _RecordedEventHostState extends State<RecordedEventHost> {
  @override
  void initState() {
    super.initState();
    _bind(widget.owner);
  }

  @override
  void didUpdateWidget(RecordedEventHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.owner, widget.owner)) return;
    _unbind(oldWidget.owner);
    _bind(widget.owner);
  }

  void _bind(Object owner) =>
      (_recordedHosts[owner] ??= _RecordedHost())._bound.add(context);

  // Removes only this host; another surface bound for the owner stays.
  void _unbind(Object owner) => _recordedHosts[owner]?._bound.removeWhere(
        (bound) => identical(bound, context),
      );

  @override
  void dispose() {
    _unbind(widget.owner);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
