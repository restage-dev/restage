import 'dart:async';

import 'package:meta/meta.dart' show internal;

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
  });

  /// Wire identity of the mounted surface.
  final SurfaceRef surface;

  /// The effective ambient triggers for this surface (already resolved).
  final Set<SurfaceRefreshTrigger> triggers;

  /// The swap-safety gate: false while the surface holds user-contributed
  /// state, a store op is in flight, or the render is experiment-assigned.
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
  SurfaceRefreshRegistry();

  /// The process-wide registry.
  static final SurfaceRefreshRegistry instance = SurfaceRefreshRegistry();

  final List<SurfaceRefreshHandle> _handles = [];
  final Map<SurfaceRefreshHandle, StreamSubscription<SurfaceUpdate>>
      _channelSubs = {};

  /// Registers a mounted surface. When the handle opted into the update
  /// channel and one is configured, opens a per-surface subscription whose
  /// emissions fire the handle through the gate.
  void register(SurfaceRefreshHandle handle) {
    _handles.add(handle);
    _subscribe(handle);
  }

  void _subscribe(SurfaceRefreshHandle handle) {
    final channel = Restage.configuredUpdateChannel;
    if (channel != null &&
        handle.triggers.contains(SurfaceRefreshTrigger.updateChannel) &&
        !_channelSubs.containsKey(handle)) {
      try {
        _channelSubs[handle] = channel.watch(handle.surface).listen(
              (_) => unawaited(_fire(handle, skipStamp: true)),
              onError: (Object _) {},
            );
      } catch (_) {
        // A custom channel cannot prevent the surface from registering. Other
        // configured refresh triggers remain available.
      }
    }
  }

  /// Unregisters a surface and cancels any update-channel subscription.
  void unregister(SurfaceRefreshHandle handle) {
    _handles.remove(handle);
    unawaited(_channelSubs.remove(handle)?.cancel());
  }

  /// Explicit reload: every mounted handle (optionally slug-filtered),
  /// independent of trigger sets, still gated by canSwap.
  Future<void> reload({String? slug}) =>
      _sweep(_handles.where((h) => slug == null || h.surface.slug == slug));

  /// Pauses every update-channel subscription when the app backgrounds.
  /// The handles stay registered; [onAppResumed] reopens them.
  void onAppBackgrounded() {
    for (final sub in _channelSubs.values) {
      unawaited(sub.cancel());
    }
    _channelSubs.clear();
  }

  /// Reopens paused update-channel subscriptions, then checks every surface
  /// with an app-resume or update-channel trigger for a newer version.
  Future<void> onAppResumed() async {
    for (final handle in List.of(_handles)) {
      _subscribe(handle);
    }
    await _sweep(_handles.where(
      (h) =>
          h.triggers.contains(SurfaceRefreshTrigger.appResume) ||
          h.triggers.contains(SurfaceRefreshTrigger.updateChannel),
    ));
  }

  Future<void> _sweep(Iterable<SurfaceRefreshHandle> handles) async {
    for (final handle in List.of(handles)) {
      await _fire(handle);
    }
  }

  Future<void> _fire(
    SurfaceRefreshHandle handle, {
    bool skipStamp = false,
  }) async {
    if (handle._refreshing || !handle.canSwap()) return;
    handle._refreshing = true;
    try {
      if (handle.stampable && !skipStamp) {
        final stamp = await Restage.activeRpcClient?.fetchSurfaceStamp(
          surfaceType: handle.surface.surfaceType,
          surfaceSlug: handle.surface.slug,
        );
        // The active version still matches what is on screen. A null stamp
        // (probe failed, or no service configured) or a null rendered version
        // falls through to a full re-resolve, which stays correct.
        if (stamp != null && stamp.version == handle.renderedVersion?.call()) {
          return;
        }
      }
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
    for (final sub in _channelSubs.values) {
      unawaited(sub.cancel());
    }
    _channelSubs.clear();
    _handles.clear();
  }
}
