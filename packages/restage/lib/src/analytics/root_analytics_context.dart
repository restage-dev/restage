import 'dart:collection';

import 'package:meta/meta.dart';
import 'package:restage_shared/restage_shared.dart';

import '../events/surface_assignment.dart';
import 'analytics_identity.dart';

/// Immutable root-presentation fields attached to one successfully painted
/// surface artifact.
///
/// This type is package-internal. Public events keep their existing payloads;
/// the analytics bridge uses this context as the authoritative attribution
/// source.
@immutable
final class RootAnalyticsEventContext {
  const RootAnalyticsEventContext({
    required this.identityGeneration,
    required this.surface,
    required this.surfaceId,
    required this.surfaceVersion,
    required this.surfaceSessionId,
    this.sourceKind,
    this.payloadKind,
    this.canonicalEventId,
    this.canonicalOccurredAt,
  });

  final int identityGeneration;
  final String surface;
  final String surfaceId;
  final String surfaceVersion;
  final String surfaceSessionId;
  final SurfaceSourceKind? sourceKind;
  final SurfacePayloadKind? payloadKind;
  final String? canonicalEventId;
  final DateTime? canonicalOccurredAt;

  RootAnalyticsEventContext withCanonicalSnapshot({
    required String eventId,
    required DateTime occurredAt,
  }) =>
      RootAnalyticsEventContext(
        identityGeneration: identityGeneration,
        surface: surface,
        surfaceId: surfaceId,
        surfaceVersion: surfaceVersion,
        surfaceSessionId: surfaceSessionId,
        sourceKind: sourceKind,
        payloadKind: payloadKind,
        canonicalEventId: eventId,
        canonicalOccurredAt: occurredAt,
      );
}

/// Attribution captured synchronously at event-fire time.
///
/// A binding is always authoritative when present. [context] is null before
/// paint and after identity retirement, which forces root session and
/// presentation fields to null without losing the actual surface type/id.
@immutable
final class RootAnalyticsEventBinding {
  RootAnalyticsEventBinding.presented({
    required this.attribution,
    required this.context,
    this.sourceKind,
    this.payloadKind,
  })  : surface = attribution.surfaceType.wireName,
        surfaceId = attribution.surfaceId;

  RootAnalyticsEventBinding.anonymous({
    required this.surface,
    required this.surfaceId,
    this.sourceKind,
    this.payloadKind,
  })  : attribution = SurfaceEventAttribution(
          surfaceId: surfaceId,
          surfaceType: Surface.fromWireName(surface),
        ),
        context = null;

  final String surface;
  final String surfaceId;
  final SurfaceSourceKind? sourceKind;
  final SurfacePayloadKind? payloadKind;
  final SurfaceEventAttribution attribution;
  final RootAnalyticsEventContext? context;
}

/// An owner that can bind its presentation context around a synchronous event
/// fire.
abstract interface class RootAnalyticsContextSource {
  T runWithEventContext<T>(T Function() action);
}

/// Surface owner used before paint, after retirement, or without a renderable
/// artifact. It preserves the actual surface type/id while forcing all root
/// presentation fields to null.
@immutable
final class RootAnalyticsAnonymousContext
    implements RootAnalyticsContextSource {
  const RootAnalyticsAnonymousContext({
    required this.surface,
    required this.surfaceId,
    this.sourceKind,
    this.payloadKind,
  });

  final String surface;
  final String surfaceId;
  final SurfaceSourceKind? sourceKind;
  final SurfacePayloadKind? payloadKind;

  @override
  T runWithEventContext<T>(T Function() action) =>
      RootAnalyticsRuntime._runWithBinding(
        RootAnalyticsEventBinding.anonymous(
          surface: surface,
          surfaceId: surfaceId,
          sourceKind: sourceKind,
          payloadKind: payloadKind,
        ),
        action,
      );
}

/// Internal artifact metadata keyed by the controller that owns it.
///
/// Keeping this outside the exported controller API lets a surface stage the
/// root document's version even while a child frame is current.
abstract final class RootAnalyticsArtifactRegistry {
  static final Expando<_RootAnalyticsArtifact> _artifacts =
      Expando<_RootAnalyticsArtifact>('root analytics artifact');

  static void recordRootArtifact({
    required Object owner,
    required int version,
    required String contentHash,
    SurfaceAssignment? assignment,
  }) {
    _artifacts[owner] = _RootAnalyticsArtifact(
      surfaceVersion: version.toString(),
      contentHash: contentHash,
      assignment: assignment,
    );
  }

  static String surfaceVersionFor(Object owner) {
    final artifact = _artifacts[owner];
    if (artifact == null) {
      throw StateError('A root artifact must be recorded before presentation.');
    }
    return artifact.surfaceVersion;
  }

  static SurfaceAssignment? assignmentFor(Object owner) =>
      _artifacts[owner]?.assignment;

  static bool isSameArtifact(Object firstOwner, Object secondOwner) {
    final first = _artifacts[firstOwner];
    final second = _artifacts[secondOwner];
    return first != null &&
        second != null &&
        first.contentHash == second.contentHash;
  }

  static void forget(Object owner) {
    _artifacts[owner] = null;
  }
}

@immutable
final class _RootAnalyticsArtifact {
  const _RootAnalyticsArtifact({
    required this.surfaceVersion,
    required this.contentHash,
    required this.assignment,
  });

  final String surfaceVersion;
  final String contentHash;
  final SurfaceAssignment? assignment;
}

/// Process-local owner of internal root presentation contexts.
///
/// Presentations are independent objects rather than one mutable global slot,
/// so overlapping roots and refresh candidates cannot overwrite one another.
abstract final class RootAnalyticsRuntime {
  static AnalyticsIdentity? _identity;
  static int _authorityEpoch = 0;
  static int _publicEpoch = 0;
  static final Set<RootAnalyticsPresentation> _presentations =
      HashSet<RootAnalyticsPresentation>.identity();
  static final List<RootAnalyticsEventBinding> _eventBindings =
      <RootAnalyticsEventBinding>[];
  static final Map<_SurfaceAttributionKey, Map<Object, _ActiveAttribution>>
      _activeAttributions =
      <_SurfaceAttributionKey, Map<Object, _ActiveAttribution>>{};
  static final Map<_SurfaceAttributionKey,
          ({SurfaceEventAttribution attribution, bool isCertain})>
      _lastAttributions = {};

  /// Test-only factory for exercising cold identity lookup races.
  @visibleForTesting
  static AnalyticsIdentity Function()? debugIdentityFactory;

  /// Test-only wall clock used for paint-time canonical snapshots.
  @visibleForTesting
  static DateTime Function() debugClock = DateTime.now;

  /// Test-only scheduler for holding paywall impression callbacks.
  static void Function(void Function())? debugPostFrameScheduler;

  static AnalyticsIdentity createIdentity() =>
      debugIdentityFactory?.call() ?? AnalyticsIdentity();

  static void install({required AnalyticsIdentity identity}) {
    if (_identity != null && !identical(_identity, identity)) {
      retireAuthority();
    }
    _identity = identity;
  }

  static RootAnalyticsPresentation createPresentation({
    required String surface,
    required String surfaceId,
    SurfaceSourceKind? sourceKind,
    SurfacePayloadKind? payloadKind,
    Object? owner,
  }) {
    final identity = _identity;
    final presentation = RootAnalyticsPresentation._(
      surface: surface,
      surfaceId: surfaceId,
      sourceKind: sourceKind,
      payloadKind: payloadKind,
      identity: identity,
      identityGeneration: identity?.generation,
      authorityEpoch: _authorityEpoch,
      publicEpoch: _publicEpoch,
    );
    presentation._mountOwner = owner ?? presentation;
    _presentations.add(presentation);
    return presentation;
  }

  static RootAnalyticsEventBinding? get currentEventBinding =>
      _eventBindings.isEmpty ? null : _eventBindings.last;

  static T _runWithBinding<T>(
    RootAnalyticsEventBinding binding,
    T Function() action,
  ) {
    _eventBindings.add(binding);
    try {
      return action();
    } finally {
      _eventBindings.removeLast();
    }
  }

  /// Retires every installed root synchronously at an actor boundary.
  static void retireAll() {
    _retirePublicAttribution();
    _retirePresentations();
  }

  /// Permanently retires all contexts minted by the current analytics
  /// authority, even if the same identity object is installed again later.
  static void retireAuthority() {
    _authorityEpoch += 1;
    _retirePublicAttribution();
    _retirePresentations();
    _identity = null;
  }

  /// Clears process-global analytics context state in tests/config teardown.
  static void clear() {
    _authorityEpoch += 1;
    _retirePublicAttribution();
    for (final presentation
        in List<RootAnalyticsPresentation>.of(_presentations)) {
      presentation._disposeWithoutUnregister();
    }
    _presentations.clear();
    _eventBindings.clear();
    _identity = null;
    debugIdentityFactory = null;
    debugClock = DateTime.now;
    debugPostFrameScheduler = null;
  }

  static bool _isCurrentIdentity(
    AnalyticsIdentity? identity,
    int? generation,
    int authorityEpoch,
  ) =>
      identity != null &&
      identical(identity, _identity) &&
      generation == identity.generation &&
      authorityEpoch == _authorityEpoch;

  static void _retirePresentations() {
    for (final presentation in _presentations) {
      presentation._retire();
    }
  }

  static void _unregister(RootAnalyticsPresentation presentation) {
    _presentations.remove(presentation);
  }

  static SurfaceAssignment? assignmentFor({
    required String surface,
    required String surfaceId,
  }) {
    final key = _SurfaceAttributionKey(surface, surfaceId);
    final active = _activeAttributions[key];
    if (active != null && active.isNotEmpty) {
      if (active.length != 1) return null;
      return active.values.single.attribution.assignment;
    }
    final last = _lastAttributions[key];
    return last != null && last.isCertain ? last.attribution.assignment : null;
  }

  static void _activateAttribution(
    RootAnalyticsPresentation presentation,
    Object owner,
    SurfaceEventAttribution attribution,
  ) {
    final key = _SurfaceAttributionKey(
      attribution.surfaceType.wireName,
      attribution.surfaceId,
    );
    final owners = _activeAttributions.putIfAbsent(
      key,
      () => Map<Object, _ActiveAttribution>.identity(),
    );
    owners[owner] = _ActiveAttribution(presentation, attribution);
    _lastAttributions[key] = (attribution: attribution, isCertain: true);
  }

  static void _markAssignmentUnknown(
    RootAnalyticsPresentation presentation,
    Object owner,
    SurfaceEventAttribution uncertain,
  ) {
    final key = _SurfaceAttributionKey(
      uncertain.surfaceType.wireName,
      uncertain.surfaceId,
    );
    final last = _lastAttributions[key];
    if (last != null) {
      _lastAttributions[key] =
          (attribution: last.attribution, isCertain: false);
    }
    final owners = _activeAttributions.putIfAbsent(
      key,
      () => Map<Object, _ActiveAttribution>.identity(),
    );
    owners[owner] = _ActiveAttribution(presentation, uncertain);
  }

  static void _deactivateAttribution(
    RootAnalyticsPresentation presentation,
    Object owner,
    SurfaceEventAttribution? attribution,
  ) {
    if (attribution == null) return;
    final key = _SurfaceAttributionKey(
      attribution.surfaceType.wireName,
      attribution.surfaceId,
    );
    final owners = _activeAttributions[key];
    if (owners == null) return;
    final active = owners[owner];
    if (active == null || !identical(active.presentation, presentation)) return;
    owners.remove(owner);
    if (owners.isEmpty) _activeAttributions.remove(key);
  }

  static void _retirePublicAttribution() {
    _publicEpoch += 1;
    _activeAttributions.clear();
    _lastAttributions.clear();
  }
}

/// One controller/stage-owned root presentation.
///
/// [stage] runs inside the first-paint transaction's ownership commit.
/// [activate] runs only from its successful descendant-paint acknowledgement.
final class RootAnalyticsPresentation implements RootAnalyticsContextSource {
  RootAnalyticsPresentation._({
    required this.surface,
    required this.surfaceId,
    required this.sourceKind,
    required this.payloadKind,
    required AnalyticsIdentity? identity,
    required int? identityGeneration,
    required int authorityEpoch,
    required int publicEpoch,
  })  : _identity = identity,
        _identityGeneration = identityGeneration,
        _authorityEpoch = authorityEpoch,
        _publicEpoch = publicEpoch;

  final String surface;
  final String surfaceId;
  final SurfaceSourceKind? sourceKind;
  final SurfacePayloadKind? payloadKind;
  final AnalyticsIdentity? _identity;
  final int? _identityGeneration;
  final int _authorityEpoch;
  final int _publicEpoch;
  late final Object _mountOwner;

  RootAnalyticsEventContext? _staged;
  RootAnalyticsEventContext? _active;
  SurfaceEventAttribution? _stagedAttribution;
  SurfaceEventAttribution? _activeAttribution;
  SurfaceEventAttribution? _uncertainAttribution;
  final List<void Function(RootAnalyticsDeferredContext)> _activationCallbacks =
      <void Function(RootAnalyticsDeferredContext)>[];
  bool _activated = false;
  bool _disposed = false;

  bool get isIdentityCurrent =>
      !_disposed &&
      RootAnalyticsRuntime._isCurrentIdentity(
        _identity,
        _identityGeneration,
        _authorityEpoch,
      );

  bool get isInvalidatedByIdentityReset =>
      _disposed ||
      _publicEpoch != RootAnalyticsRuntime._publicEpoch ||
      (_identity != null &&
          !RootAnalyticsRuntime._isCurrentIdentity(
            _identity,
            _identityGeneration,
            _authorityEpoch,
          ));

  bool get isActive =>
      _activeAttribution != null &&
      _publicEpoch == RootAnalyticsRuntime._publicEpoch;

  /// Retires accessor certainty without acknowledging a native fallback paint.
  void markAssignmentUnknown() {
    if (_disposed ||
        _activated ||
        _publicEpoch != RootAnalyticsRuntime._publicEpoch) {
      return;
    }
    final uncertain = SurfaceEventAttribution(
      surfaceId: surfaceId,
      surfaceType: Surface.fromWireName(surface),
    );
    _uncertainAttribution = uncertain;
    RootAnalyticsRuntime._markAssignmentUnknown(this, _mountOwner, uncertain);
  }

  void stage({
    required String? surfaceVersion,
    SurfaceAssignment? assignment,
  }) {
    if (surfaceVersion != null && surfaceVersion.isEmpty) {
      throw ArgumentError.value(
        surfaceVersion,
        'surfaceVersion',
        'must not be empty',
      );
    }
    if (_disposed || _stagedAttribution != null || _activated) {
      return;
    }
    if (_publicEpoch != RootAnalyticsRuntime._publicEpoch) return;
    _stagedAttribution = SurfaceEventAttribution(
      surfaceId: surfaceId,
      surfaceType: Surface.fromWireName(surface),
      surfaceVersion: surfaceVersion,
      assignment: assignment,
    );
    if (_identity == null || !isIdentityCurrent || surfaceVersion == null) {
      return;
    }
    final identity = _identity;
    _staged = RootAnalyticsEventContext(
      identityGeneration: _identityGeneration!,
      surface: surface,
      surfaceId: surfaceId,
      surfaceVersion: surfaceVersion,
      surfaceSessionId: identity.newEventId(),
      sourceKind: sourceKind,
      payloadKind: payloadKind,
    );
  }

  void activate() {
    if (_disposed || _activated) return;
    _activated = true;
    final staged = _staged;
    final stagedAttribution = _stagedAttribution;
    if (stagedAttribution != null &&
        _publicEpoch == RootAnalyticsRuntime._publicEpoch) {
      _activeAttribution = stagedAttribution;
      RootAnalyticsRuntime._activateAttribution(
        this,
        _mountOwner,
        stagedAttribution,
      );
    }
    if (staged != null && isIdentityCurrent) {
      final active = staged.withCanonicalSnapshot(
        eventId: _identity!.newEventId(),
        occurredAt: RootAnalyticsRuntime.debugClock().toUtc(),
      );
      _active = active;
    }
    final deferred = captureDeferredContext();
    final callbacks = List<void Function(RootAnalyticsDeferredContext)>.of(
      _activationCallbacks,
    );
    _activationCallbacks.clear();
    for (final callback in callbacks) {
      callback(deferred);
    }
  }

  void abandon() {
    if (_activated) return;
    _staged = null;
    _stagedAttribution = null;
    _activationCallbacks.clear();
  }

  /// Runs [callback] with the exact owner snapshot as soon as descendant paint
  /// activates this presentation. A presentation born without analytics still
  /// supplies an anonymous owner so public lifecycle events remain intact.
  void captureDeferredContextOnActivation(
    void Function(RootAnalyticsDeferredContext) callback,
  ) {
    if (_disposed) return;
    if (_activated) {
      callback(captureDeferredContext());
      return;
    }
    _activationCallbacks.add(callback);
  }

  RootAnalyticsDeferredContext captureDeferredContext() =>
      RootAnalyticsDeferredContext._(
        surface: surface,
        surfaceId: surfaceId,
        sourceKind: sourceKind,
        payloadKind: payloadKind,
        identity: _identity,
        identityGeneration: _identityGeneration,
        authorityEpoch: _authorityEpoch,
        publicEpoch: _publicEpoch,
        attribution: _activeAttribution,
        context: isIdentityCurrent ? _active : null,
      );

  @override
  T runWithEventContext<T>(T Function() action) =>
      RootAnalyticsRuntime._runWithBinding(_eventBinding(), action);

  RootAnalyticsEventBinding _eventBinding() {
    final context = isIdentityCurrent ? _active : null;
    final attribution = _publicEpoch == RootAnalyticsRuntime._publicEpoch
        ? _activeAttribution
        : null;
    return attribution == null
        ? RootAnalyticsEventBinding.anonymous(
            surface: surface,
            surfaceId: surfaceId,
            sourceKind: sourceKind,
            payloadKind: payloadKind,
          )
        : RootAnalyticsEventBinding.presented(
            attribution: attribution,
            context: context,
            sourceKind: sourceKind,
            payloadKind: payloadKind,
          );
  }

  void _retire() {
    _staged = null;
    _active = null;
    RootAnalyticsRuntime._deactivateAttribution(
      this,
      _mountOwner,
      _activeAttribution ?? _uncertainAttribution,
    );
    _uncertainAttribution = null;
    _stagedAttribution = null;
    _activeAttribution = null;
    _activationCallbacks.clear();
  }

  void dispose() {
    if (_disposed) return;
    _disposeWithoutUnregister();
    RootAnalyticsRuntime._unregister(this);
  }

  void _disposeWithoutUnregister() {
    _disposed = true;
    _retire();
  }
}

/// Presentation context retained at an async operation's initiation boundary.
///
/// Unmount does not invalidate it. Identity generation is checked later, at
/// outcome fire, so a reset before that fire strips root attribution.
final class RootAnalyticsDeferredContext implements RootAnalyticsContextSource {
  const RootAnalyticsDeferredContext._({
    required this.surface,
    required this.surfaceId,
    required this.sourceKind,
    required this.payloadKind,
    required AnalyticsIdentity? identity,
    required int? identityGeneration,
    required int authorityEpoch,
    required int publicEpoch,
    required SurfaceEventAttribution? attribution,
    required RootAnalyticsEventContext? context,
  })  : _identity = identity,
        _identityGeneration = identityGeneration,
        _authorityEpoch = authorityEpoch,
        _publicEpoch = publicEpoch,
        _attribution = attribution,
        _context = context;

  final String surface;
  final String surfaceId;
  final SurfaceSourceKind? sourceKind;
  final SurfacePayloadKind? payloadKind;
  final AnalyticsIdentity? _identity;
  final int? _identityGeneration;
  final int _authorityEpoch;
  final int _publicEpoch;
  final SurfaceEventAttribution? _attribution;
  final RootAnalyticsEventContext? _context;

  @override
  T runWithEventContext<T>(T Function() action) {
    final context = RootAnalyticsRuntime._isCurrentIdentity(
      _identity,
      _identityGeneration,
      _authorityEpoch,
    )
        ? _context
        : null;
    final attribution =
        _publicEpoch == RootAnalyticsRuntime._publicEpoch ? _attribution : null;
    final binding = attribution == null
        ? RootAnalyticsEventBinding.anonymous(
            surface: surface,
            surfaceId: surfaceId,
            sourceKind: sourceKind,
            payloadKind: payloadKind,
          )
        : RootAnalyticsEventBinding.presented(
            attribution: attribution,
            context: context,
            sourceKind: sourceKind,
            payloadKind: payloadKind,
          );
    return RootAnalyticsRuntime._runWithBinding(binding, action);
  }
}

final class _SurfaceAttributionKey {
  const _SurfaceAttributionKey(this.surface, this.surfaceId);

  final String surface;
  final String surfaceId;

  @override
  bool operator ==(Object other) =>
      other is _SurfaceAttributionKey &&
      other.surface == surface &&
      other.surfaceId == surfaceId;

  @override
  int get hashCode => Object.hash(surface, surfaceId);
}

final class _ActiveAttribution {
  const _ActiveAttribution(this.presentation, this.attribution);

  final RootAnalyticsPresentation presentation;
  final SurfaceEventAttribution attribution;
}
