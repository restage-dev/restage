part of 'restage_event.dart';

/// Where the content a mount first painted came from.
enum SurfaceLoadSource {
  /// Content the service delivered for this mount, including the answer to
  /// this launch's startup request.
  delivered('delivered'),

  /// Content already on the device: an earlier delivery, including one an
  /// earlier mount received in this launch.
  saved('saved'),

  /// The original built into the app: the compiled surface, the bundled
  /// copy, or the mount's fallback builder. Content from a custom resolver
  /// that does not report its source also counts as original.
  original('original');

  const SurfaceLoadSource(this.wireName);

  /// Stable name for analytics and serialization.
  final String wireName;
}

/// Why a mount could paint nothing.
enum SurfaceLoadFailureReason {
  /// No content was available: none delivered, none saved, no original.
  unavailable('unavailable'),

  /// The content was rejected as invalid or incompatible with this app.
  invalid('invalid'),

  /// The content failed while building or rendering.
  renderError('render_error'),

  /// Any other failure.
  unknown('unknown');

  const SurfaceLoadFailureReason(this.wireName);

  /// Stable name for analytics and serialization.
  final String wireName;
}

/// Fired when a mount starts loading its content.
///
/// Placements, paywalls, generated surfaces, screens and flows fire it. A
/// paywall or placement rebuilt with a different placement starts a new load,
/// and so does a screen or flow rebuilt with a different surface or a new
/// resolver object, and a flow also for a different placement, a different set
/// of installed signals, or an `actions` registry with different contracts,
/// including a change between none and one. A new `actions` object with the
/// same contracts does not start one. Each
/// load is followed by at most one [SurfaceLoadCompleted] or
/// [SurfaceLoadFailed], and by none if the mount is disposed before it first
/// paints or a flow finishes without showing a screen. A mount that never
/// paints, such as one kept offstage, reports no terminal until it paints.
/// Callbacks receive it after the current frame's work, never during a build.
/// No order is guaranteed relative to the paywall load events.
@immutable
final class SurfaceLoadStarted extends RestageEvent {
  /// Creates a load-started event.
  const SurfaceLoadStarted({
    required this.surfaceId,
    required this.surface,
    super.firedAt,
    super.attribution,
  });

  @override
  String get name => 'surface_load_started';

  /// The surface or placement identifier the mount loads.
  @override
  final String surfaceId;

  /// The category the mount declares.
  final Surface surface;

  @override
  Surface get surfaceType => surface;

  @override
  Map<String, Object?> toMap() => <String, Object?>{
        'name': name,
        'surfaceId': surfaceId,
        'surface': surface.wireName,
        if (firedAt != null) 'firedAt': firedAt!.toIso8601String(),
      };
}

/// Fired after the frame in which a load first painted content.
///
/// [source] says what painted. When the mount paints its original, for
/// example because nothing is published or delivery missed the first-launch
/// wait, the load completes with [SurfaceLoadSource.original]. Content that
/// replaces it later, such as a live refresh, does not fire this event again.
@immutable
final class SurfaceLoadCompleted extends RestageEvent {
  /// Creates a load-completed event.
  const SurfaceLoadCompleted({
    required this.surfaceId,
    required this.surface,
    required this.source,
    required this.elapsed,
    required this.firstLaunchWaitPassed,
    required this.freshWindowPassed,
    super.firedAt,
    super.attribution,
  });

  @override
  String get name => 'surface_load_completed';

  /// The surface or placement identifier the mount loads.
  @override
  final String surfaceId;

  /// The category the mount declares.
  final Surface surface;

  @override
  Surface get surfaceType => surface;

  /// Where the painted content came from.
  final SurfaceLoadSource source;

  /// Time from the start of the load to its first paint.
  final Duration elapsed;

  /// Whether the first-launch wait had passed when the mount chose what to
  /// show.
  final bool firstLaunchWaitPassed;

  /// Whether the fresh window had passed when the mount chose what to show.
  /// The window runs for every load, whether or not saved content exists.
  final bool freshWindowPassed;

  @override
  Map<String, Object?> toMap() => <String, Object?>{
        'name': name,
        'surfaceId': surfaceId,
        'surface': surface.wireName,
        'source': source.wireName,
        'elapsedMs': elapsed.inMilliseconds,
        'firstLaunchWaitPassed': firstLaunchWaitPassed,
        'freshWindowPassed': freshWindowPassed,
        if (firedAt != null) 'firedAt': firedAt!.toIso8601String(),
      };
}

/// Fired after the frame in which a load settled on its error state or on
/// nothing.
///
/// A mount fails when it has no delivered, saved or original content to show,
/// or when content fails to render and the mount paints its error state or
/// nothing in its place.
@immutable
final class SurfaceLoadFailed extends RestageEvent {
  /// Creates a load-failed event.
  const SurfaceLoadFailed({
    required this.surfaceId,
    required this.surface,
    required this.reason,
    required this.elapsed,
    this.detail,
    super.firedAt,
    super.attribution,
  });

  @override
  String get name => 'surface_load_failed';

  /// The surface or placement identifier the mount loads.
  @override
  final String surfaceId;

  /// The category the mount declares.
  final Surface surface;

  @override
  Surface get surfaceType => surface;

  /// Why nothing could paint.
  final SurfaceLoadFailureReason reason;

  /// A diagnostic code from the mount: a snake_case SDK code such as
  /// `decode_failed`, or a custom resolver's error code, unchanged. Its values
  /// are not part of the API and may change.
  final String? detail;

  /// Time from the start of the load to the failure.
  final Duration elapsed;

  @override
  Map<String, Object?> toMap() => <String, Object?>{
        'name': name,
        'surfaceId': surfaceId,
        'surface': surface.wireName,
        'reason': reason.wireName,
        if (detail != null) 'detail': detail,
        'elapsedMs': elapsed.inMilliseconds,
        if (firedAt != null) 'firedAt': firedAt!.toIso8601String(),
      };
}
