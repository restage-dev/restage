import 'dart:async';

import 'package:flutter/foundation.dart' show setEquals;
import 'package:meta/meta.dart' show internal, visibleForTesting;
import 'package:restage_shared/restage_shared.dart';

import '../restage_rpc_client/restage_rpc_client.dart'
    show SurfaceStamp, SurfaceStampRateLimited;
import '../runtime/restage.dart';
import 'surface_refresh_trigger.dart';
import 'surface_update_channel.dart';

/// A mounted surface's participation in live refresh: identity, effective
/// triggers, the swap-safety gate, and the apply callback.
@internal
final class SurfaceRefreshHandle {
  /// Creates a handle. [canSwap] is the swap-safety gate; [refresh] re-resolves
  /// and (when content changed) re-renders. Both are owned by the surface.
  SurfaceRefreshHandle({
    required this.surface,
    required this.triggers,
    required this.canSwap,
    required this.refresh,
    this.renderedVersion,
    this.stampable = false,
    this.localValidity,
    this.localBoundary,
    this.invalidateLocal,
    this.placementState,
    this.probePlacement,
    this.invalidatePlacement,
    this.renderedSurface,
    this.placementWatch,
  });

  /// Wire identity of the mounted surface.
  final SurfaceRef surface;

  /// The effective ambient triggers for this surface (already resolved).
  final Set<SurfaceRefreshTrigger> triggers;

  /// The swap-safety gate: false while the surface has user interaction or
  /// contributed state, is busy, or has a locked assignment.
  final bool Function() canSwap;

  /// Re-resolve and (when content changed) re-render. Must never throw into
  /// an error UI — a failed refresh keeps the current render.
  final Future<void> Function() refresh;

  /// The published version currently rendered, or `null` for a resolution
  /// without a published version.
  final int? Function()? renderedVersion;

  /// Whether this surface can be freshness-probed against the hosted backend
  /// (it renders from the hosted resolver, and a service is configured). When
  /// true, the registry fetches the active-version stamp before a full
  /// re-resolve and skips the re-resolve if the version is unchanged.
  final bool stampable;

  /// Returned placement bounds and frozen inputs, checked independently of
  /// remote refresh triggers. This performs no routing evaluation.
  final bool Function()? localValidity;
  final DateTime? Function()? localBoundary;
  final Future<void> Function()? invalidateLocal;
  bool _localHandled = false;

  /// Reads only the host's accepted placement decision, never a candidate.
  final PlacementRefreshStateV1? Function()? placementState;

  /// Checks the exact accepted decision through the configured delivery owner.
  final Future<PlacementRefreshProbeV1> Function(PlacementRefreshStateV1)?
      probePlacement;

  /// Removes future cache use independently of the visible swap gate.
  final Future<void> Function()? invalidatePlacement;

  /// The accepted selected surface for legacy surface-only channels.
  final SurfaceRef Function()? renderedSurface;

  /// Explicit scoped token association for the accepted decision.
  final PlacementDeliveryWatchV1? Function()? placementWatch;

  PlacementRefreshStateV1? _acceptedPlacement;
  PlacementDeliveryWatchV1? _acceptedWatch;
  int _generation = 0;
  bool _refreshing = false;
}

/// Process-wide registry of mounted, refresh-capable surfaces. Producers
/// (explicit reload, app-resume sweep, update-channel emissions) route
/// through here; the handle's gate decides application. No producer applies
/// content directly — everything passes through [_fire]'s gate.
@internal
final class SurfaceRefreshRegistry {
  /// Creates a registry. Use [instance] in production; a fresh instance is
  /// only for isolated tests.
  SurfaceRefreshRegistry({DateTime Function()? now})
      : _now = now ?? DateTime.now;

  /// The process-wide registry.
  static final SurfaceRefreshRegistry instance =
      SurfaceRefreshRegistry(now: Restage.placementNow);

  final List<SurfaceRefreshHandle> _handles = [];
  final DateTime Function() _now;
  Timer? _localAlarm;
  bool _backgrounded = false;
  bool _checkingLocal = false;

  /// Bounds detection of clock, zone and optional-input changes while active.
  static const localClockCheckInterval = Duration(seconds: 30);
  final Map<SurfaceRefreshHandle, _ChannelSubscriptions> _channelSubs = {};

  /// Registers a mounted surface. When the handle opted into the update
  /// channel and one is configured, opens a per-surface subscription whose
  /// emissions fire the handle through the gate.
  void register(SurfaceRefreshHandle handle) {
    if (_handles.contains(handle)) return;
    handle._acceptedPlacement = _snapshot(handle.placementState?.call());
    handle._acceptedWatch = _snapshotWatch(
        handle._acceptedPlacement, handle.placementWatch?.call());
    _handles.add(handle);
    _subscribe(handle);
    _scheduleLocalAlarm();
  }

  void _subscribe(SurfaceRefreshHandle handle, {bool replace = false}) {
    final channel = Restage.configuredUpdateChannel;
    if (_backgrounded ||
        channel == null ||
        !handle.triggers.contains(SurfaceRefreshTrigger.updateChannel) ||
        (!replace && _channelSubs.containsKey(handle))) {
      return;
    }
    final previous = _channelSubs[handle];
    final next = _ChannelSubscriptions(handle._generation);
    _channelSubs[handle] = next;
    final placement = handle._acceptedPlacement;
    if (placement != null && channel is DeliveryUpdateChannel) {
      final probe = handle.probePlacement;
      for (final scope in placement.dependencies) {
        try {
          next.subscriptions.add(channel
              .watchDelivery(scope,
                  watch: handle._acceptedWatch,
                  reconnectProbe: probe == null ? null : () => probe(placement))
              .listen(
            (changed) {
              if (changed == scope) {
                unawaited(_onUpdate(handle, next));
              }
            },
            onError: (Object _) {},
          ));
        } catch (_) {
          // A failed scope leaves explicit reload and resume available.
        }
      }
    } else {
      try {
        final surface = handle.renderedSurface?.call() ?? handle.surface;
        next.subscriptions.add(channel.watch(surface).listen(
          (update) {
            if (update.surface == surface) {
              unawaited(_onUpdate(handle, next));
            }
          },
          onError: (Object _) {},
        ));
      } catch (_) {
        // A custom channel cannot prevent other configured refresh triggers.
      }
    }
    previous?.cancel();
    if (next.subscriptions.isEmpty) {
      _channelSubs.remove(handle);
    }
  }

  bool _isCurrent(SurfaceRefreshHandle handle, int generation) =>
      _handles.contains(handle) && handle._generation == generation;

  bool _isCurrentSubscription(
          SurfaceRefreshHandle handle, _ChannelSubscriptions subscription) =>
      !_backgrounded &&
      !subscription.retired &&
      _isCurrent(handle, subscription.generation);

  Future<void> _onUpdate(
      SurfaceRefreshHandle handle, _ChannelSubscriptions subscription) async {
    if (!_isCurrentSubscription(handle, subscription)) return;
    try {
      if (handle._acceptedPlacement != null) {
        await handle.invalidatePlacement?.call();
      }
      if (!_isCurrentSubscription(handle, subscription)) return;
      await _fire(handle,
          skipStamp: true,
          generation: subscription.generation,
          placementInvalidated: true);
    } catch (_) {
      // Failed invalidation leaves the current presentation intact.
    }
  }

  /// Replaces watches only after the host has accepted a new decision.
  @internal
  void acceptedPlacementChanged(SurfaceRefreshHandle handle) {
    if (!_handles.contains(handle)) return;
    final next = _snapshot(handle.placementState?.call());
    final nextWatch = _snapshotWatch(next, handle.placementWatch?.call());
    final previous = handle._acceptedPlacement;
    if (next?.mount == previous?.mount &&
        next?.decisionIdentityDigest == previous?.decisionIdentityDigest &&
        setEquals(next?.dependencies, previous?.dependencies) &&
        nextWatch == handle._acceptedWatch) {
      return;
    }
    handle._acceptedPlacement = next;
    handle._acceptedWatch = nextWatch;
    handle._generation++;
    _subscribe(handle, replace: true);
  }

  /// Unregisters a surface and cancels any update-channel subscription.
  void unregister(SurfaceRefreshHandle handle) {
    _handles.remove(handle);
    handle._generation++;
    _channelSubs.remove(handle)?.cancel();
    _scheduleLocalAlarm();
  }

  /// Explicit reload: every mounted handle (optionally slug-filtered),
  /// independent of trigger sets, still gated by canSwap.
  Future<void> reload({String? slug}) =>
      _sweep(_handles.where((h) => slug == null || h.surface.slug == slug));

  /// Pauses every update-channel subscription when the app backgrounds.
  /// The handles stay registered; [onAppResumed] reopens them.
  void onAppBackgrounded() {
    _backgrounded = true;
    _localAlarm?.cancel();
    _localAlarm = null;
    for (final handle in _handles) {
      handle._generation++;
    }
    for (final sub in _channelSubs.values) {
      sub.cancel();
    }
    _channelSubs.clear();
  }

  /// Reopens paused update-channel subscriptions, then checks every surface
  /// with an app-resume or update-channel trigger for a newer version.
  Future<void> onAppResumed() async {
    _backgrounded = false;
    await checkLocalValidity();
    for (final handle in List.of(_handles)) {
      _subscribe(handle);
    }
    await _sweep(_handles.where(
      (h) =>
          h.triggers.contains(SurfaceRefreshTrigger.appResume) ||
          h.triggers.contains(SurfaceRefreshTrigger.updateChannel),
    ));
  }

  /// Re-arms validity after a newly committed presentation.
  @internal
  void localValidityChanged(SurfaceRefreshHandle handle) {
    if (!_handles.contains(handle)) return;
    handle._localHandled = false;
    _scheduleLocalAlarm();
  }

  /// Rechecks actual clock/input readings without a hosted request.
  @internal
  @visibleForTesting
  Future<void> checkLocalValidity() async {
    if (_checkingLocal) return;
    _checkingLocal = true;
    try {
      for (final handle in List.of(_handles)) {
        if (!_handles.contains(handle) ||
            handle.localValidity == null ||
            handle._localHandled) {
          continue;
        }
        if (handle.localValidity!()) continue;
        if (handle._refreshing || !handle.canSwap()) continue;
        handle._refreshing = true;
        try {
          await handle.invalidateLocal?.call();
          handle._localHandled = true;
        } catch (_) {
          // A transient staging failure may be retried at the next safe check.
        } finally {
          handle._refreshing = false;
        }
      }
    } finally {
      _checkingLocal = false;
      _scheduleLocalAlarm();
    }
  }

  void _scheduleLocalAlarm() {
    _localAlarm?.cancel();
    _localAlarm = null;
    if (_backgrounded ||
        !_handles.any((handle) =>
            handle.localValidity != null && !handle._localHandled)) {
      return;
    }
    final now = _now().toUtc();
    var delay = localClockCheckInterval;
    for (final handle in _handles) {
      if (handle._localHandled) continue;
      final boundary = handle.localBoundary?.call();
      if (boundary == null) continue;
      final until = boundary.toUtc().difference(now);
      // Expired but locked presentations are checked on the bounded shared
      // clock cadence; they must not keep firing an immediate alarm.
      if (until > Duration.zero && until < delay) delay = until;
    }
    _localAlarm = Timer(delay, () => unawaited(checkLocalValidity()));
  }

  Future<void> _sweep(Iterable<SurfaceRefreshHandle> handles) async {
    for (final handle in List.of(handles)) {
      await _fire(handle);
    }
  }

  Future<void> _fire(
    SurfaceRefreshHandle handle, {
    bool skipStamp = false,
    int? generation,
    bool placementInvalidated = false,
  }) async {
    final capturedGeneration = generation ?? handle._generation;
    if (!_isCurrent(handle, capturedGeneration) ||
        handle._refreshing ||
        !handle.canSwap()) {
      return;
    }
    handle._refreshing = true;
    try {
      final placement = handle._acceptedPlacement;
      if (placement != null && !skipStamp) {
        final probe = await handle.probePlacement?.call(placement) ??
            const PlacementRefreshProbeV1.unavailable();
        if (!_isCurrent(handle, capturedGeneration)) return;
        if (probe is PlacementRefreshRateLimitedV1 ||
            (probe is PlacementRefreshUnchangedV1 &&
                probe.decisionIdentityDigest ==
                    placement.decisionIdentityDigest)) {
          return;
        }
      } else if (placement == null && handle.stampable && !skipStamp) {
        final stamp = await Restage.activeRpcClient?.fetchSurfaceStamp(
          surfaceType: handle.surface.surfaceType,
          surfaceSlug: handle.surface.slug,
        );
        // A rate-limited stamp keeps the current render. An unavailable stamp,
        // no service, a null rendered version, or a stamp that requires a
        // fresh decision falls through to a refresh.
        if (stamp is SurfaceStampRateLimited) return;
        if (stamp is SurfaceStamp &&
            !stamp.requiresResolution &&
            stamp.version == handle.renderedVersion?.call()) {
          return;
        }
      }
      if (!_isCurrent(handle, capturedGeneration)) return;
      if (placement != null && !placementInvalidated) {
        await handle.invalidatePlacement?.call();
      }
      if (!_isCurrent(handle, capturedGeneration) || !handle.canSwap()) return;
      await handle.refresh();
    } catch (_) {
      // Staleness is never an error state: a failed refresh keeps the
      // current render and stays silent.
    } finally {
      handle._refreshing = false;
    }
  }

  /// Clears all handles and cancels all subscriptions. Called from
  /// [Restage.debugReset].
  void debugReset() {
    _localAlarm?.cancel();
    _localAlarm = null;
    _backgrounded = false;
    for (final handle in _handles) {
      handle._generation++;
    }
    for (final sub in _channelSubs.values) {
      sub.cancel();
    }
    _channelSubs.clear();
    _handles.clear();
  }
}

PlacementRefreshStateV1? _snapshot(PlacementRefreshStateV1? state) =>
    state == null
        ? null
        : (
            mount: PlacementMountDescriptorV1.fromJson(state.mount.toJson()),
            decisionIdentityDigest: state.decisionIdentityDigest,
            dependencies: freezeDeliveryDependencyClosureV1(state.dependencies),
          );

PlacementDeliveryWatchV1? _snapshotWatch(
    PlacementRefreshStateV1? state, PlacementDeliveryWatchV1? watch) {
  if (state == null ||
      watch == null ||
      watch.decisionIdentityDigest != state.decisionIdentityDigest ||
      !setEquals(watch.channels.map((channel) => channel.scope).toSet(),
          state.dependencies)) {
    return null;
  }
  return PlacementDeliveryWatchV1(
      decisionIdentityDigest: watch.decisionIdentityDigest,
      channels: watch.channels);
}

final class _ChannelSubscriptions {
  _ChannelSubscriptions(this.generation);

  final int generation;
  final List<StreamSubscription<Object?>> subscriptions = [];
  bool retired = false;

  void cancel() {
    retired = true;
    for (final subscription in subscriptions) {
      unawaited(subscription.cancel());
    }
  }
}
