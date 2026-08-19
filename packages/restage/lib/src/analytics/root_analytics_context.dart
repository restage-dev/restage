import 'dart:collection';

import 'package:meta/meta.dart';
import 'package:restage_shared/restage_shared.dart';

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
    required this.experimentId,
    required this.variantId,
    required this.experimentEpoch,
    this.sourceKind,
    this.payloadKind,
    this.canonicalEventId,
    this.canonicalOccurredAt,
  });

  final int identityGeneration;
  final String surface;
  final String surfaceId;
  final String? surfaceVersion;
  final String surfaceSessionId;
  final String? experimentId;
  final String? variantId;
  final int? experimentEpoch;
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
        experimentId: experimentId,
        variantId: variantId,
        experimentEpoch: experimentEpoch,
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
/// assignment fields to null without losing the actual surface type/id.
@immutable
final class RootAnalyticsEventBinding {
  RootAnalyticsEventBinding.active(RootAnalyticsEventContext context)
      : surface = context.surface,
        surfaceId = context.surfaceId,
        sourceKind = context.sourceKind,
        payloadKind = context.payloadKind,
        context = context;

  const RootAnalyticsEventBinding.anonymous({
    required this.surface,
    required this.surfaceId,
    this.sourceKind,
    this.payloadKind,
  }) : context = null;

  final String surface;
  final String surfaceId;
  final SurfaceSourceKind? sourceKind;
  final SurfacePayloadKind? payloadKind;
  final RootAnalyticsEventContext? context;
}

/// An owner that can bind its presentation context around a synchronous event
/// fire.
abstract interface class RootAnalyticsContextSource {
  T runWithEventContext<T>(T Function() action);
}

/// Surface owner used before paint, after retirement, or without a renderable
/// artifact. It preserves the actual surface type/id while forcing all root
/// presentation and assignment fields to null.
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
  }) {
    _artifacts[owner] = _RootAnalyticsArtifact(
      surfaceVersion: version.toString(),
      contentHash: contentHash,
    );
  }

  static String? surfaceVersionFor(Object owner) =>
      _artifacts[owner]?.surfaceVersion;

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
  });

  final String surfaceVersion;
  final String contentHash;
}

/// Process-local owner of internal root presentation contexts.
///
/// Presentations are independent objects rather than one mutable global slot,
/// so overlapping roots and refresh candidates cannot overwrite one another.
abstract final class RootAnalyticsRuntime {
  static AnalyticsIdentity? _identity;
  static void Function(RootAnalyticsEventContext)? _onSurfacePresented;
  static int _authorityEpoch = 0;
  static final Set<RootAnalyticsPresentation> _presentations =
      HashSet<RootAnalyticsPresentation>.identity();
  static final List<RootAnalyticsEventBinding> _eventBindings =
      <RootAnalyticsEventBinding>[];

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

  static void install({
    required AnalyticsIdentity identity,
    required void Function(RootAnalyticsEventContext) onSurfacePresented,
  }) {
    if (_identity != null && !identical(_identity, identity)) {
      retireAuthority();
    }
    _identity = identity;
    _onSurfacePresented = onSurfacePresented;
  }

  static RootAnalyticsPresentation createPresentation({
    required String surface,
    required String surfaceId,
    SurfaceSourceKind? sourceKind,
    SurfacePayloadKind? payloadKind,
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
    );
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
  static void retireAll() => _retirePresentations();

  /// Permanently retires all contexts minted by the current analytics
  /// authority, even if the same identity object is installed again later.
  static void retireAuthority() {
    _authorityEpoch += 1;
    _retirePresentations();
    _identity = null;
    _onSurfacePresented = null;
  }

  /// Clears process-global analytics context state in tests/config teardown.
  static void clear() {
    _authorityEpoch += 1;
    for (final presentation
        in List<RootAnalyticsPresentation>.of(_presentations)) {
      presentation._disposeWithoutUnregister();
    }
    _presentations.clear();
    _eventBindings.clear();
    _identity = null;
    _onSurfacePresented = null;
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
      presentation._retireForIdentityChange();
    }
  }

  static void _unregister(RootAnalyticsPresentation presentation) {
    _presentations.remove(presentation);
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
  })  : _identity = identity,
        _identityGeneration = identityGeneration,
        _authorityEpoch = authorityEpoch;

  final String surface;
  final String surfaceId;
  final SurfaceSourceKind? sourceKind;
  final SurfacePayloadKind? payloadKind;
  final AnalyticsIdentity? _identity;
  final int? _identityGeneration;
  final int _authorityEpoch;

  RootAnalyticsEventContext? _staged;
  RootAnalyticsEventContext? _active;
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
      (_identity != null &&
          !RootAnalyticsRuntime._isCurrentIdentity(
            _identity,
            _identityGeneration,
            _authorityEpoch,
          ));

  void stage({
    required String? surfaceVersion,
    String? experimentId,
    String? variantId,
    int? experimentEpoch,
  }) {
    if (_disposed ||
        _identity == null ||
        _staged != null ||
        _activated ||
        !isIdentityCurrent) {
      return;
    }
    final hasCompleteExperimentTriple =
        experimentId != null && variantId != null && experimentEpoch != null;
    final identity = _identity;
    _staged = RootAnalyticsEventContext(
      identityGeneration: _identityGeneration!,
      surface: surface,
      surfaceId: surfaceId,
      surfaceVersion: surfaceVersion,
      surfaceSessionId: identity.newEventId(),
      experimentId: hasCompleteExperimentTriple ? experimentId : null,
      variantId: hasCompleteExperimentTriple ? variantId : null,
      experimentEpoch: hasCompleteExperimentTriple ? experimentEpoch : null,
      sourceKind: sourceKind,
      payloadKind: payloadKind,
    );
  }

  void activate() {
    if (_disposed || _activated) return;
    _activated = true;
    final staged = _staged;
    if (staged != null && isIdentityCurrent) {
      final active = staged.withCanonicalSnapshot(
        eventId: _identity!.newEventId(),
        occurredAt: RootAnalyticsRuntime.debugClock().toUtc(),
      );
      _active = active;
      RootAnalyticsRuntime._onSurfacePresented?.call(active);
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
        context: isIdentityCurrent ? _active : null,
      );

  @override
  T runWithEventContext<T>(T Function() action) =>
      RootAnalyticsRuntime._runWithBinding(_eventBinding(), action);

  RootAnalyticsEventBinding _eventBinding() {
    final context = isIdentityCurrent ? _active : null;
    return context == null
        ? RootAnalyticsEventBinding.anonymous(
            surface: surface,
            surfaceId: surfaceId,
            sourceKind: sourceKind,
            payloadKind: payloadKind,
          )
        : RootAnalyticsEventBinding.active(context);
  }

  void _retireForIdentityChange() {
    _staged = null;
    _active = null;
    _activationCallbacks.clear();
  }

  void dispose() {
    if (_disposed) return;
    _disposeWithoutUnregister();
    RootAnalyticsRuntime._unregister(this);
  }

  void _disposeWithoutUnregister() {
    _disposed = true;
    _staged = null;
    _active = null;
    _activationCallbacks.clear();
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
    required RootAnalyticsEventContext? context,
  })  : _identity = identity,
        _identityGeneration = identityGeneration,
        _authorityEpoch = authorityEpoch,
        _context = context;

  final String surface;
  final String surfaceId;
  final SurfaceSourceKind? sourceKind;
  final SurfacePayloadKind? payloadKind;
  final AnalyticsIdentity? _identity;
  final int? _identityGeneration;
  final int _authorityEpoch;
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
    final binding = context == null
        ? RootAnalyticsEventBinding.anonymous(
            surface: surface,
            surfaceId: surfaceId,
            sourceKind: sourceKind,
            payloadKind: payloadKind,
          )
        : RootAnalyticsEventBinding.active(context);
    return RootAnalyticsRuntime._runWithBinding(binding, action);
  }
}
