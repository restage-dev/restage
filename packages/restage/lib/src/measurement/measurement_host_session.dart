import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart'
    show PlacementMountRequestV1;

import 'bundled_measurement_publication_binding_read_port.dart';
import 'measurement_deferred_clock.dart';
import 'bundled_measurement_target_profile_loader.dart';
import 'hosted_measurement_publication_binding_read_port.dart';
import 'measurement_bundled_generated_source_provenance.dart';
import 'measurement_capture_capability.dart';
import 'measurement_cutover_selector.dart';
import 'measurement_event_sanitizer.dart';
import 'measurement_host_construction_owner.dart';
import 'measurement_ingest_transport.dart';
import 'measurement_publication_binding_runtime.dart';
import 'measurement_resolved_publication_provenance.dart';
import 'measurement_rfw_presentation.dart';
import 'measurement_runtime_capture.dart';
import 'measurement_worker_protocol.dart';
import 'presentation_commit.dart';
import '../analytics/root_analytics_context.dart';
import '../events/restage_event.dart';
import 'placement_mount_attribution.dart';
import '../resolver/resolved_paywall_payload.dart';
import '../resolver/surface_resolution_report.dart'
    show SurfaceResolutionSource;
import '../resolver/surface_delivery_observations.dart'
    show SurfaceDeliveryObservations;
import '../runtime/restage.dart';

/// Reserves the existing capture nonce before optional session construction.
@internal
String reserveMeasurementCaptureSessionNonce() => _encodeNonce(
    MeasurementHostSessionConstructionRegistry._authority?.takeNonceBytes() ??
        _secureNonceBytes());

/// Reserves one nonce on the existing capture authority before optional work.
@internal
MountAttributionSnapshotV1? captureMountAttribution(
  PlacementMountRequestV1? mount, {
  Object? resolved,
}) {
  if (mount == null) return null;
  // Hosted content from outside the placement path carries no placement claim.
  if (resolved != null && resolvedPlacementDeliveryFor(resolved) == null) {
    final source =
        surfaceResolutionSourceFor(placementResolvedLeaf(resolved)) ??
            surfaceResolutionSourceFor(resolved);
    if (source == SurfaceResolutionSource.fresh ||
        source == SurfaceResolutionSource.holdLastGood) {
      return null;
    }
  }
  final nonce = reserveMeasurementCaptureSessionNonce();
  return resolved == null
      ? MountAttributionSnapshotV1.original(
          key: mount.key,
          hostContractHash: mount.hostContractHash,
          defaultSurface: mount.defaultSurface,
          mountInstanceNonce: nonce)
      : MountAttributionSnapshotV1.fromResolved(
          resolved: resolved, mount: mount, mountInstanceNonce: nonce);
}

/// Test-visible lifecycle state for the SDK-internal host session.
@internal
enum MeasurementHostSessionDebugState {
  /// No construction authority admitted Measurement work.
  disabled,

  /// The session is still opening; what the mount records is held.
  pending,

  /// An admitted session can receive bounded capture updates.
  active,

  /// The session has reached its terminal lifecycle boundary.
  finalized,
}

/// One removable app-lifecycle observation owned by an admitted session.
@internal
abstract interface class MeasurementHostSessionLifecycleRegistration {
  /// Removes the observation. Implementations must tolerate repeated calls.
  void unregister();
}

/// Internal lifecycle boundary used by production Flutter binding observation
/// and focused controller tests.
@internal
abstract interface class MeasurementHostSessionLifecycleRegistrar {
  /// Registers one session-scoped state callback.
  MeasurementHostSessionLifecycleRegistration register(
    void Function(AppLifecycleState state) callback,
  );
}

/// Construction dependencies for one host-session controller.
///
/// Production constructors use a cryptographically secure nonce source;
/// deterministic nonce injection is restricted to test constructors.
@internal
final class MeasurementHostSessionConstructionAuthority {
  /// Creates the production authority for one governed worker owner.
  MeasurementHostSessionConstructionAuthority.production({
    required MeasurementHostConstructionOwner constructionOwner,
  })  : transport = const MeasurementIngestTransport.disabled(),
        installedCapabilities = MeasurementCaptureInstalledCapabilities.current,
        _nonceBytesSource = _secureNonceBytes,
        _hostedBindingReadPortLookup = _lookupHostedBindingReadPort,
        _bundledTargetProfileLoader = _loadBundledTargetProfile,
        _lifecycleRegistrar = const _WidgetsBindingLifecycleRegistrar(),
        _constructionOwner = constructionOwner;

  /// Creates dormant host-session construction dependencies.
  MeasurementHostSessionConstructionAuthority({
    required this.transport,
    this.installedCapabilities =
        MeasurementCaptureInstalledCapabilities.current,
  })  : _nonceBytesSource = _secureNonceBytes,
        _hostedBindingReadPortLookup = _lookupHostedBindingReadPort,
        _bundledTargetProfileLoader = _loadBundledTargetProfile,
        _lifecycleRegistrar = const _WidgetsBindingLifecycleRegistrar(),
        _constructionOwner = null;

  /// Creates deterministic construction dependencies for focused tests.
  @visibleForTesting
  MeasurementHostSessionConstructionAuthority.forTesting({
    required this.transport,
    required List<int> Function() nonceBytesSource,
    this.installedCapabilities =
        MeasurementCaptureInstalledCapabilities.current,
    MeasurementPublicationBindingReadPort? Function()?
        hostedBindingReadPortLookup,
    Future<BundledMeasurementTargetProfileLoadResult> Function()?
        bundledTargetProfileLoader,
    MeasurementHostSessionLifecycleRegistrar? lifecycleRegistrar,
  })  : _nonceBytesSource = nonceBytesSource,
        _hostedBindingReadPortLookup =
            hostedBindingReadPortLookup ?? _disabledHostedBindingReadPortLookup,
        _bundledTargetProfileLoader =
            bundledTargetProfileLoader ?? _disabledBundledTargetProfileLoader,
        _lifecycleRegistrar =
            lifecycleRegistrar ?? const _DiscardingLifecycleRegistrar(),
        _constructionOwner = null;

  /// Creates a test-only authority whose complete new-only root is owned by
  /// one worker/outbox composition owner.
  ///
  /// The disabled legacy transport is retained solely to keep this internal
  /// authority's pre-existing constructor shape; the worker-owned branch never
  /// reads or invokes it.
  @visibleForTesting
  MeasurementHostSessionConstructionAuthority.forWorkerOwnedDeliveryTesting({
    required MeasurementHostConstructionOwner constructionOwner,
    required List<int> Function() nonceBytesSource,
    this.installedCapabilities =
        MeasurementCaptureInstalledCapabilities.current,
    MeasurementPublicationBindingReadPort? Function()?
        hostedBindingReadPortLookup,
    Future<BundledMeasurementTargetProfileLoadResult> Function()?
        bundledTargetProfileLoader,
    MeasurementHostSessionLifecycleRegistrar? lifecycleRegistrar,
  })  : transport = const MeasurementIngestTransport.disabled(),
        _nonceBytesSource = nonceBytesSource,
        _hostedBindingReadPortLookup =
            hostedBindingReadPortLookup ?? _disabledHostedBindingReadPortLookup,
        _bundledTargetProfileLoader =
            bundledTargetProfileLoader ?? _disabledBundledTargetProfileLoader,
        _lifecycleRegistrar =
            lifecycleRegistrar ?? const _DiscardingLifecycleRegistrar(),
        _constructionOwner = constructionOwner;

  /// Internal ingest transport used only at lifecycle boundaries.
  final MeasurementIngestTransport transport;

  /// Typed local capability authority for this SDK build.
  final MeasurementCaptureInstalledCapabilities installedCapabilities;

  final List<int> Function() _nonceBytesSource;
  final MeasurementPublicationBindingReadPort? Function()
      _hostedBindingReadPortLookup;
  final Future<BundledMeasurementTargetProfileLoadResult> Function()
      _bundledTargetProfileLoader;
  final MeasurementHostSessionLifecycleRegistrar _lifecycleRegistrar;
  final MeasurementHostConstructionOwner? _constructionOwner;

  List<int> takeNonceBytes() => _nonceBytesSource();
}

/// One complete test-only host construction choice for a future cutover.
///
/// The old-only branch intentionally provides no Measurement construction
/// authority. A later composition owner can use the same selector to choose
/// its whole pre-cutover root, while this dormant host seam continues to keep
/// the replacement path disabled.
@internal
final class MeasurementHostSessionCutoverInstallation {
  MeasurementHostSessionCutoverInstallation.oldOnly({
    required MeasurementCutoverGeneration generation,
  })  : _selector = MeasurementCutoverSelector.oldOnly(generation: generation),
        _constructionAuthority = null;

  MeasurementHostSessionCutoverInstallation.newOnly({
    required MeasurementCutoverGeneration generation,
    required MeasurementHostSessionConstructionAuthority constructionAuthority,
  })  : _selector = MeasurementCutoverSelector.newOnly(generation: generation),
        _constructionAuthority = constructionAuthority;

  final MeasurementCutoverSelector _selector;
  final MeasurementHostSessionConstructionAuthority? _constructionAuthority;

  /// The immutable selector carried by this complete installation.
  @visibleForTesting
  MeasurementCutoverSelector get selector => _selector;

  MeasurementHostSessionConstructionAuthority? get _selectedAuthority =>
      _selector.select(
        oldRoot: () => null,
        newRoot: () => _constructionAuthority!,
      );
}

MeasurementPublicationBindingReadPort? _lookupHostedBindingReadPort() {
  final client = Restage.activeRpcClient;
  if (client == null) return null;
  return HostedMeasurementPublicationBindingReadPort(client: client);
}

Future<BundledMeasurementTargetProfileLoadResult> _loadBundledTargetProfile() =>
    BundledMeasurementTargetProfileLoader.load();

MeasurementPublicationBindingReadPort? _disabledHostedBindingReadPortLookup() =>
    null;

Future<BundledMeasurementTargetProfileLoadResult>
    _disabledBundledTargetProfileLoader() =>
        Future<BundledMeasurementTargetProfileLoadResult>.error(
          StateError('No bundled target-profile test loader is installed'),
        );

List<int> _secureNonceBytes() {
  final random = Random.secure();
  return List<int>.generate(32, (_) => random.nextInt(256), growable: false);
}

final class _WidgetsBindingLifecycleRegistrar
    implements MeasurementHostSessionLifecycleRegistrar {
  const _WidgetsBindingLifecycleRegistrar();

  @override
  MeasurementHostSessionLifecycleRegistration register(
    void Function(AppLifecycleState state) callback,
  ) {
    final observer = _MeasurementHostSessionLifecycleObserver(callback);
    WidgetsBinding.instance.addObserver(observer);
    return _WidgetsBindingLifecycleRegistration(observer);
  }
}

final class _MeasurementHostSessionLifecycleObserver
    with WidgetsBindingObserver {
  _MeasurementHostSessionLifecycleObserver(this.callback);

  final void Function(AppLifecycleState state) callback;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => callback(state);
}

final class _WidgetsBindingLifecycleRegistration
    implements MeasurementHostSessionLifecycleRegistration {
  _WidgetsBindingLifecycleRegistration(this._observer);

  _MeasurementHostSessionLifecycleObserver? _observer;

  @override
  void unregister() {
    final observer = _observer;
    if (observer == null) return;
    _observer = null;
    WidgetsBinding.instance.removeObserver(observer);
  }
}

final class _DiscardingLifecycleRegistrar
    implements MeasurementHostSessionLifecycleRegistrar {
  const _DiscardingLifecycleRegistrar();

  @override
  MeasurementHostSessionLifecycleRegistration register(
    void Function(AppLifecycleState state) callback,
  ) =>
      const _DiscardingLifecycleRegistration();
}

final class _DiscardingLifecycleRegistration
    implements MeasurementHostSessionLifecycleRegistration {
  const _DiscardingLifecycleRegistration();

  @override
  void unregister() {}
}

/// Construction authority shared by host owners, with isolated test overrides.
@internal
abstract final class MeasurementHostSessionConstructionRegistry {
  static MeasurementHostSessionCutoverInstallation? _installation;
  static MeasurementHostSessionConstructionAuthority? _productionAuthority;

  /// Replaces the configured production authority without changing test overrides.
  static void installProduction(
      MeasurementHostSessionConstructionAuthority? authority) {
    _productionAuthority = authority;
  }

  static final MeasurementCutoverGeneration _focusedTestGeneration =
      MeasurementCutoverGeneration(
    releaseId: 'focused-test',
    cutoverGeneration: 0,
  );

  static MeasurementHostSessionConstructionAuthority? get _authority {
    final installation = _installation;
    return installation == null
        ? _productionAuthority
        : installation._selectedAuthority;
  }

  /// The currently installed test seam, if any.
  @visibleForTesting
  static MeasurementHostSessionCutoverInstallation?
      get installedCutoverInstallationForTest => _installation;

  /// Temporarily installs an authority for one focused test.
  ///
  /// This compatibility helper always wraps [authority] in one new-only
  /// selector; it cannot install independent roots.
  @visibleForTesting
  static void Function() installForTest(
    MeasurementHostSessionConstructionAuthority authority,
  ) =>
      installCutoverInstallationForTest(
        MeasurementHostSessionCutoverInstallation.newOnly(
          generation: _focusedTestGeneration,
          constructionAuthority: authority,
        ),
      );

  /// Temporarily installs one complete cutover choice for a focused test.
  ///
  /// Production has no setter for this value. The returned callback restores
  /// the exact preceding installation and is idempotent.
  @visibleForTesting
  static void Function() installCutoverInstallationForTest(
    MeasurementHostSessionCutoverInstallation installation,
  ) {
    final previous = _installation;
    _installation = installation;
    var restored = false;
    return () {
      if (restored) return;
      _installation = previous;
      restored = true;
    };
  }
}

/// Exact-only host-session opening request.
///
/// A host can supply either one immutable hosted binding reference with its
/// exact read port, or one generated bundled locator with its exact bundled
/// read port. No constructor accepts raw graph, manifest, or revision fields.
@internal
final class MeasurementHostSessionOpenRequest {
  /// Opens from one exact hosted publication binding reference.
  MeasurementHostSessionOpenRequest.hosted({
    required MeasurementPublicationBindingReferenceV1 bindingReference,
    required MeasurementPublicationBindingReadPort bindingReadPort,
  })  : _bindingReference = bindingReference,
        _hostedBindingReadPort = bindingReadPort,
        _generatedPublicationLocator = null,
        _bundledBindingReadPort = null;

  /// Opens from one exact generated bundled publication locator.
  MeasurementHostSessionOpenRequest.bundled({
    required MeasurementBundledGeneratedPublicationLocatorV1
        generatedPublicationLocator,
    required BundledMeasurementPublicationBindingReadPort bindingReadPort,
  })  : _bindingReference = null,
        _hostedBindingReadPort = null,
        _generatedPublicationLocator = generatedPublicationLocator,
        _bundledBindingReadPort = bindingReadPort;

  final MeasurementPublicationBindingReferenceV1? _bindingReference;
  final MeasurementPublicationBindingReadPort? _hostedBindingReadPort;
  final MeasurementBundledGeneratedPublicationLocatorV1?
      _generatedPublicationLocator;
  final BundledMeasurementPublicationBindingReadPort? _bundledBindingReadPort;

  Future<MeasurementPublicationBindingRuntimeResolution> _resolveExact() {
    final bindingReference = _bindingReference;
    final hostedBindingReadPort = _hostedBindingReadPort;
    if (bindingReference != null && hostedBindingReadPort != null) {
      return MeasurementPublicationBindingRuntimeResolver
          .requestAndResolveExact(
        bindingReference: bindingReference,
        bindingReadPort: hostedBindingReadPort,
      );
    }

    final generatedPublicationLocator = _generatedPublicationLocator;
    final bundledBindingReadPort = _bundledBindingReadPort;
    if (generatedPublicationLocator != null && bundledBindingReadPort != null) {
      return MeasurementPublicationBindingRuntimeResolver
          .resolveBundledExactGeneratedPublicationLocator(
        generatedPublicationLocator: generatedPublicationLocator,
        bindingReadPort: bundledBindingReadPort,
      );
    }
    throw StateError('An exact host-session request is incomplete');
  }
}

/// SDK-internal controller for one dormant host capture session.
@internal
final class MeasurementHostSessionController
    implements MeasurementRfwPresentationSink {
  MeasurementHostSessionController._disabled({bool failed = false})
      : _debugState = MeasurementHostSessionDebugState.disabled,
        _openFailed = failed;

  MeasurementHostSessionController._active({
    required MeasurementRuntimeCaptureSession captureSession,
    required MeasurementPresentationRouteHandle presentationRouteHandle,
    required MeasurementRuntimeRouteTable routeTable,
    required MeasurementIngestTransport transport,
    String? routingSelectionReceipt,
  })  : _captureSession = captureSession,
        _presentationRouteHandle = presentationRouteHandle,
        _routeTable = routeTable,
        _transport = transport,
        _routingSelectionReceipt = routingSelectionReceipt,
        _debugState = MeasurementHostSessionDebugState.active;

  MeasurementHostSessionController._pending({
    required bool workerOwned,
    required MeasurementMountClock clock,
  })  : _debugState = MeasurementHostSessionDebugState.pending,
        _pendingRoute = MeasurementPendingPresentationRoute(),
        _pendingReady = Completer<void>(),
        _pendingWorkerOwned = workerOwned,
        _pendingClock = clock {
    _pendingRoute!
      ..clock = (() => clock.elapsedMicros)
      ..replayAt =
          (at, replay) => MeasurementDeferredClock.atHeld(clock, at, replay);
  }

  MeasurementHostSessionController._workerOwned({
    required MeasurementHostConstructionSession constructionSession,
    required MeasurementPresentationRouteHandle presentationRouteHandle,
  })  : _constructionSession = constructionSession,
        _presentationRouteHandle = presentationRouteHandle,
        _debugState = MeasurementHostSessionDebugState.active;

  /// Consults the nullable construction authority before any Measurement work.
  static Future<MeasurementHostSessionController> open(
    MeasurementHostSessionOpenRequest request,
  ) async {
    if (!Restage.isMeasurementEnabled) {
      return MeasurementHostSessionController._disabled();
    }
    final authority = MeasurementHostSessionConstructionRegistry._authority;
    if (authority == null) return MeasurementHostSessionController._disabled();
    final attempt = _OpenAttempt();
    return _openWithAuthority(request, authority, attempt)
        .whenComplete(attempt.finish);
  }

  /// Opens Measurement for a resolved artifact after checking construction authority.
  /// Uses hosted provenance first, then a verified bundled profile and locator.
  static Future<MeasurementHostSessionController> openForResolvedArtifact(
    Object resolvedOrPayload, {
    Future<SurfaceDeliveryObservations?> Function()? presentationObservations,
    MountAttributionSnapshotV1? mountAttribution,
  }) {
    final attempt = _OpenAttempt();
    return _openForResolvedArtifact(
      resolvedOrPayload,
      attempt,
      presentationObservations: presentationObservations,
      mountAttribution: mountAttribution,
    ).whenComplete(attempt.finish);
  }

  /// How long a whole open may take before it fails.
  static const Duration openFailureBound = Duration(seconds: 30);

  /// How long an open waits for presentation observations before going on
  /// without them.
  static const Duration presentationObservationsWait = Duration(seconds: 5);

  /// The most entries a pending session holds before its session opens.
  static const int pendingEntryLimit = 256;

  /// Opens Measurement in the background; the returned session never delays
  /// paint.
  ///
  /// Until the session opens it holds the first-paint outcome and up to
  /// [pendingEntryLimit] recorded entries, and replays them on open, however
  /// long opening takes. A session that fails to open drops what it held; an
  /// open not finished within [openFailureBound] fails.
  static MeasurementHostSessionController openDeferred(
    Object resolvedOrPayload, {
    Future<SurfaceDeliveryObservations?> Function()? presentationObservations,
    MountAttributionSnapshotV1? mountAttribution,
  }) {
    if (!Restage.isMeasurementEnabled) {
      return MeasurementHostSessionController._disabled();
    }
    final authority = MeasurementHostSessionConstructionRegistry._authority;
    if (authority == null) return MeasurementHostSessionController._disabled();
    final owner = authority._constructionOwner;
    final sinceMount =
        owner?.startMountClock() ?? MeasurementMountClock.stopwatch();
    final pending = MeasurementHostSessionController._pending(
      workerOwned: owner != null,
      clock: sinceMount,
    );
    pending._observePendingLifecycle(authority._lifecycleRegistrar);
    final attempt = _OpenAttempt()
      ..lifecycleObserved = pending._pendingLifecycleRegistration != null;
    pending._pendingIsCurrent = attempt.isCurrent;
    // The session counts from the mount, so held entries keep their times.
    unawaited(MeasurementDeferredClock.withBase(
      sinceMount,
      () => _openForResolvedArtifact(
        resolvedOrPayload,
        attempt,
        presentationObservations: presentationObservations,
        mountAttribution: mountAttribution,
      ),
    ).whenComplete(attempt.finish).then(pending._adoptOpened,
        onError: (Object _) => pending._dropPending(failed: true)));
    return pending;
  }

  static Future<MeasurementHostSessionController> _openForResolvedArtifact(
    Object resolvedOrPayload,
    _OpenAttempt attempt, {
    Future<SurfaceDeliveryObservations?> Function()? presentationObservations,
    MountAttributionSnapshotV1? mountAttribution,
  }) async {
    if (!Restage.isMeasurementEnabled) {
      return MeasurementHostSessionController._disabled();
    }
    final authority = MeasurementHostSessionConstructionRegistry._authority;
    if (authority == null) return MeasurementHostSessionController._disabled();
    if (authority._constructionOwner != null) {
      attempt.readObservations(presentationObservations);
    }

    try {
      final provenanceOwner = switch (resolvedOrPayload) {
        BlobPaywallPayload(:final variant) => variant,
        FlowPaywallPayload(:final flow) => flow,
        _ => resolvedOrPayload,
      };
      final routingSelectionReceipt =
          routingSelectionReceiptFor(provenanceOwner);
      final canonicalAssignment = measurementExperimentAssignmentFor(
        provenanceOwner,
      );
      final registrationFingerprint =
          measurementRegistrationFingerprintFor(provenanceOwner);
      final experimentAssignment = canonicalAssignment == null
          ? null
          : MeasurementExperimentAssignmentV1.fromJson({
              'kind': 'measurementExperimentAssignment',
              'outcomeLinkCarrier': canonicalAssignment.outcomeLinkCarrier,
              'schemaVersion': kMeasurementSchemaVersion,
            });
      final hostedReference = measurementPublicationBindingReferenceFor(
        provenanceOwner,
      );
      if ((canonicalAssignment != null ||
              resolvedPlacementDeliveryFor(provenanceOwner) != null) &&
          hostedReference == null) {
        return MeasurementHostSessionController._disabled();
      }
      if (hostedReference != null) {
        final hostedReadPort = authority._hostedBindingReadPortLookup();
        if (hostedReadPort == null) {
          return MeasurementHostSessionController._disabled();
        }
        return await _openWithAuthority(
          MeasurementHostSessionOpenRequest.hosted(
            bindingReference: hostedReference,
            bindingReadPort: hostedReadPort,
          ),
          authority,
          attempt,
          experimentAssignment: experimentAssignment,
          registrationFingerprint: registrationFingerprint,
          routingSelectionReceipt: routingSelectionReceipt,
          mountAttribution: mountAttribution,
        );
      }

      final bundledProfile =
          await attempt.bound(authority._bundledTargetProfileLoader());
      final generatedPublicationLocator =
          await resolveBundledExactGeneratedPublicationLocatorFor(
        resolvedOrPayload,
        bindingReadPort: bundledProfile.bindingReadPort,
      );
      if (generatedPublicationLocator == null) {
        return MeasurementHostSessionController._disabled();
      }
      return await _openWithAuthority(
        MeasurementHostSessionOpenRequest.bundled(
          generatedPublicationLocator: generatedPublicationLocator,
          bindingReadPort: bundledProfile.bindingReadPort,
        ),
        authority,
        attempt,
        experimentAssignment: experimentAssignment,
        routingSelectionReceipt: routingSelectionReceipt,
        mountAttribution: mountAttribution,
      );
    } on Object {
      return MeasurementHostSessionController._disabled(failed: true);
    }
  }

  static Future<MeasurementHostSessionController> _openWithAuthority(
    MeasurementHostSessionOpenRequest request,
    MeasurementHostSessionConstructionAuthority authority,
    _OpenAttempt attempt, {
    MeasurementExperimentAssignmentV1? experimentAssignment,
    String? registrationFingerprint,
    String? routingSelectionReceipt,
    MountAttributionSnapshotV1? mountAttribution,
  }) async {
    try {
      final resolution = await attempt.bound(request._resolveExact());
      final resolvedMount = resolution.resolvedMount;
      final routeTable = resolution.routeTable;
      if (!resolution.isAccepted ||
          resolvedMount == null ||
          routeTable == null) {
        return MeasurementHostSessionController._disabled(
          failed: resolution.readResult
              is MeasurementPublicationBindingTransportUnavailable,
        );
      }

      final publishedContext =
          MeasurementCapturePublishedContext.fromResolvedMount(resolvedMount);
      final admission = MeasurementCaptureCapabilityGate.evaluate(
        capabilityDescription: MeasurementCaptureCapabilityDescription(
          descriptionSchemaVersion:
              kMeasurementCaptureCapabilityDescriptionSchemaVersion,
          capabilityId: kMeasurementCaptureCapabilityId,
          capabilityRevision: kMeasurementCaptureCapabilityRevision,
          measurementSchemaVersion: publishedContext.measurementSchemaVersion,
          publishedContext: publishedContext,
        ),
        publishedContext: publishedContext,
        installedCapabilities: authority.installedCapabilities,
      );
      if (!admission.admitted) {
        return MeasurementHostSessionController._disabled();
      }

      final constructionOwner = authority._constructionOwner;
      final captureNonce = mountAttribution?.mountInstanceNonce ??
          _encodeNonce(authority.takeNonceBytes());
      if (constructionOwner != null) {
        final observations = await attempt.observations();
        attempt.throwIfExpired();
        final presentationContext = observations == null
            ? null
            : MeasurementPresentationContextV1(
                presentationCountry: observations.presentationCountry,
                platform: observations.platform,
                appBuildOrdinal: observations.appBuildOrdinal,
                deviceClass: observations.deviceClass,
              );
        final opened = await attempt.bound(
            constructionOwner.openSessionResult(
              resolvedMount: resolvedMount,
              routeTable: routeTable,
              capabilityAdmission: admission,
              experimentAssignment: experimentAssignment,
              registrationFingerprint: registrationFingerprint,
              presentationContext: presentationContext,
              routingSelectionReceipt: routingSelectionReceipt,
              attribution: mountAttribution?.attribution,
              assignment: mountAttribution?.assignment,
              captureSessionNonceSource: () => captureNonce,
              isCurrent: attempt.isCurrent,
            ),
            discardLate: (late) => late.session?.abortBeforeSuccessfulPaint());
        final constructionSession = opened.session;
        if (constructionSession == null) {
          return MeasurementHostSessionController._disabled(
            failed: opened.failed || !attempt.isCurrent(),
          );
        }
        final sink = _FirstPaintSink(constructionSession);
        final controller = MeasurementHostSessionController._workerOwned(
          constructionSession: constructionSession,
          presentationRouteHandle: MeasurementPresentationRouteHandle.open(
            publishedSurfaceRevision: resolvedMount.publishedSurfaceRevision,
            captureSink: sink,
            observer: constructionSession.presentationAttemptObserver,
            onUncommittedAbort: constructionSession.abortBeforeSuccessfulPaint,
          ),
        );
        sink.onPresented = controller._scheduleFirstPaintCheckpoint;
        controller._purchaseExposure = (
          captureSessionNonce: captureNonce,
          publicationBindingReference:
              resolvedMount.publicationContextRef.bindingReference,
        );
        if (!attempt.lifecycleObserved &&
            !controller._startLifecycleObservation(
              authority._lifecycleRegistrar,
            )) {
          controller._disableAfterConstructionFailure();
          return MeasurementHostSessionController._disabled(failed: true);
        }
        return controller;
      }

      final captureSession = MeasurementRuntimeCaptureSession(
        bounds: MeasurementFactFrameBounds(
          maximumCounterValue: kMaximumMeasurementCounterValue,
          maximumPresentedPoints: kMaximumMeasurementPresentedPointCount,
          maximumInteractionCounters:
              kMaximumMeasurementInteractionCounterCount,
          maximumMissingnessEntries: kMaximumMeasurementMissingnessEntryCount,
        ),
        captureSessionNonce: MeasurementCaptureSessionNonce(captureNonce),
        publicationContextRef: resolvedMount.publicationContextRef,
        experimentAssignment: experimentAssignment,
        attribution: mountAttribution?.attribution,
        assignment: mountAttribution?.assignment,
        routeTable: routeTable,
        sequence: 1,
      );
      final sink = _FirstPaintSink(captureSession);
      final controller = MeasurementHostSessionController._active(
        captureSession: captureSession,
        presentationRouteHandle: MeasurementPresentationRouteHandle.open(
          publishedSurfaceRevision: resolvedMount.publishedSurfaceRevision,
          captureSink: sink,
        ),
        routeTable: routeTable,
        transport: authority.transport,
        routingSelectionReceipt: routingSelectionReceipt,
      );
      sink.onPresented = controller._scheduleFirstPaintCheckpoint;
      controller._purchaseExposure = (
        captureSessionNonce: captureNonce,
        publicationBindingReference:
            resolvedMount.publicationContextRef.bindingReference,
      );
      if (!attempt.lifecycleObserved &&
          !controller._startLifecycleObservation(
            authority._lifecycleRegistrar,
          )) {
        controller._disableAfterConstructionFailure();
        return MeasurementHostSessionController._disabled(failed: true);
      }
      return controller;
    } on Object {
      return MeasurementHostSessionController._disabled(failed: true);
    }
  }

  MeasurementHostSessionDebugState _debugState;
  bool _openFailed = false;

  // Pending mode: set only on a session returned by [openDeferred].
  MeasurementPendingPresentationRoute? _pendingRoute;
  bool _pendingWorkerOwned = false;
  Completer<void>? _pendingReady;
  MeasurementMountClock? _pendingClock;
  List<
      ({
        int at,
        void Function(MeasurementHostSessionController opened) entry
      })>? _pendingEntries = [];
  bool _pendingOverflowLogged = false;
  final MeasurementDeferredPresentationBinder _pendingBinder =
      MeasurementDeferredPresentationBinder();
  Completer<MeasurementIngestTransportOutcome?>? _pendingTeardown;
  MeasurementHostSessionController? _opened;
  MeasurementHostSessionLifecycleRegistration? _pendingLifecycleRegistration;
  AppLifecycleState? _pendingLifecycle;
  bool Function()? _pendingIsCurrent;
  int _heldOutcomes = 0;
  void Function(MeasurementHostSessionController)? _pendingPointEventBinding;

  MeasurementRuntimeCaptureSession? _captureSession;
  MeasurementHostConstructionSession? _constructionSession;
  MeasurementPresentationRouteHandle? _presentationRouteHandle;
  MeasurementRuntimeRouteTable? _routeTable;
  bool _completed = false;
  MeasurementIngestTransport? _transport;
  String? _routingSelectionReceipt;
  MeasurementHostSessionLifecycleRegistration? _lifecycleRegistration;
  final Set<Future<void>> _pendingLifecycleCheckpoints = <Future<void>>{};
  bool _backgroundCheckpointIssued = false;
  Timer? _firstPaintCheckpoint;
  Future<MeasurementIngestTransportOutcome?>? _teardownFuture;
  ({
    String captureSessionNonce,
    MeasurementPublicationBindingReferenceV1 publicationBindingReference
  })? _purchaseExposure;

  /// Exposes lifecycle state only to focused internal tests.
  @visibleForTesting
  MeasurementHostSessionDebugState get debugState =>
      _opened?.debugState ?? _debugState;

  /// Worker-backed session exposed only to focused construction-plane tests.
  @visibleForTesting
  MeasurementHostConstructionSession? get debugConstructionSession =>
      _opened?._constructionSession ?? _constructionSession;

  /// Entries a pending session holds, for focused tests.
  @visibleForTesting
  int get debugPendingEntryCount => _pendingEntries?.length ?? 0;

  bool get _isPending =>
      _debugState == MeasurementHostSessionDebugState.pending;

  /// Holds [entry] for replay on open; returns false once the session opened.
  bool _holdPending(void Function(MeasurementHostSessionController) entry) {
    if (!_isPending) return false;
    final entries = _pendingEntries!;
    if (entries.length >= pendingEntryLimit) {
      if (!_pendingOverflowLogged) {
        _pendingOverflowLogged = true;
        debugPrint(
          '[restage] measurement held $pendingEntryLimit entries before its '
          'session opened; later entries are dropped',
        );
      }
      return true;
    }
    entries.add((at: _pendingClock!.elapsedMicros, entry: entry));
    return true;
  }

  // The root's one lifecycle observation: it keeps the latest foreground or
  // background state while pending, and passes to the session it opens.
  void _observePendingLifecycle(
    MeasurementHostSessionLifecycleRegistrar registrar,
  ) {
    try {
      _pendingLifecycleRegistration = registrar.register((state) {
        final opened = _opened;
        if (opened != null) return opened._handleLifecycleState(state);
        if (!_isPending) return;
        switch (state) {
          case AppLifecycleState.resumed:
          case AppLifecycleState.hidden:
          case AppLifecycleState.paused:
            _pendingLifecycle = state;
          case AppLifecycleState.inactive:
          case AppLifecycleState.detached:
            return;
        }
      });
    } on Object {
      // Without observation a background before open is not checkpointed.
    }
  }

  void _endPendingLifecycle() {
    try {
      _pendingLifecycleRegistration?.unregister();
    } on Object {
      // Observer removal cannot affect the host.
    }
    _pendingLifecycleRegistration = null;
  }

  void _adoptOpened(MeasurementHostSessionController opened) {
    final handle = opened._presentationRouteHandle;
    if (opened._debugState != MeasurementHostSessionDebugState.active ||
        handle == null) {
      _dropPending(failed: opened._openFailed);
      return;
    }
    // A reset or erasure since mount: never file this presentation under it.
    if (!(_pendingIsCurrent?.call() ?? true)) {
      opened._disableAfterConstructionFailure();
      _dropPending(failed: true);
      return;
    }
    _opened = opened;
    _debugState = MeasurementHostSessionDebugState.active;
    _pendingPointEventBinding?.call(opened);
    _pendingPointEventBinding = null;
    final route = _pendingRoute!..bind(handle);
    _pendingBinder.resolve(opened._constructionSession);
    final entries = _pendingEntries!;
    _pendingEntries = null;
    // Everything held replays in the order it happened, the paint included.
    final paintAt = route.heldPaintAt;
    for (final (:at, :entry) in entries) {
      if (paintAt != null && at >= paintAt) route.replayHeldPaint();
      try {
        MeasurementDeferredClock.atHeld(
            _pendingClock!, at, () => entry(opened));
      } on Object {
        // A replayed entry cannot affect the mounted host.
      }
    }
    route.replayHeldPaint();
    if (opened._lifecycleRegistration == null) {
      opened._lifecycleRegistration = _pendingLifecycleRegistration;
      _pendingLifecycleRegistration = null;
    } else {
      _endPendingLifecycle();
    }
    final teardown = _pendingTeardown;
    final lifecycle = _pendingLifecycle;
    _pendingLifecycle = null;
    if (teardown != null) {
      _pendingTeardown = null;
      teardown.complete(opened.teardown());
    } else if (lifecycle != null) {
      opened._handleLifecycleState(lifecycle);
    }
    _releasePendingWaiters();
  }

  void _releasePendingWaiters() {
    final ready = _pendingReady;
    if (ready != null && !ready.isCompleted) ready.complete();
  }

  void _dropPending({required bool failed}) {
    if (!_isPending) return;
    _debugState = MeasurementHostSessionDebugState.disabled;
    if (kDebugMode &&
        failed &&
        (_pendingRoute!.holdsPaint ||
            _pendingEntries!.isNotEmpty ||
            _heldOutcomes > 0)) {
      debugPrint('[restage] measurement session did not open; this '
          'presentation is not measured');
    }
    _pendingEntries = null;
    _pendingPointEventBinding = null;
    _endPendingLifecycle();
    _pendingLifecycle = null;
    _pendingBinder.resolve(null);
    _pendingTeardown?.complete(null);
    _pendingTeardown = null;
    _releasePendingWaiters();
  }

  bool _startLifecycleObservation(
    MeasurementHostSessionLifecycleRegistrar registrar,
  ) {
    try {
      _lifecycleRegistration = registrar.register(_handleLifecycleState);
      return true;
    } on Object {
      return false;
    }
  }

  void _disableAfterConstructionFailure() {
    _debugState = MeasurementHostSessionDebugState.disabled;
    _cancelFirstPaintCheckpoint();
    try {
      _lifecycleRegistration?.unregister();
    } on Object {
      // A construction-plane cleanup failure cannot affect business rendering.
    }
    _lifecycleRegistration = null;
    _presentationRouteHandle?.supersede();
    _captureSession = null;
    _constructionSession?.abortBeforeSuccessfulPaint();
    _constructionSession = null;
    _presentationRouteHandle = null;
    _routeTable = null;
    _transport = null;
  }

  void _handleLifecycleState(AppLifecycleState state) {
    if (_debugState != MeasurementHostSessionDebugState.active) return;
    try {
      switch (state) {
        case AppLifecycleState.resumed:
          _backgroundCheckpointIssued = false;
          return;
        case AppLifecycleState.hidden:
        case AppLifecycleState.paused:
          if (_backgroundCheckpointIssued) return;
          _backgroundCheckpointIssued = true;
          _cancelFirstPaintCheckpoint();
          final checkpointFuture = checkpoint().then<void>((_) {});
          _pendingLifecycleCheckpoints.add(checkpointFuture);
          unawaited(
            checkpointFuture.whenComplete(
              () => _pendingLifecycleCheckpoints.remove(checkpointFuture),
            ),
          );
          return;
        case AppLifecycleState.inactive:
        case AppLifecycleState.detached:
          return;
      }
    } on Object {
      // Lifecycle observation is never allowed to interfere with the host.
    }
  }

  /// How long after the first successful paint the presented frame is sent,
  /// so a surface left on screen is counted before the app backgrounds or the
  /// surface closes.
  static const Duration firstPaintCheckpointDelay = Duration(seconds: 3);

  void _scheduleFirstPaintCheckpoint() {
    if (_debugState != MeasurementHostSessionDebugState.active ||
        _backgroundCheckpointIssued ||
        _firstPaintCheckpoint != null) {
      return;
    }
    _firstPaintCheckpoint = Timer(firstPaintCheckpointDelay, () {
      if (_debugState != MeasurementHostSessionDebugState.active ||
          _backgroundCheckpointIssued) {
        return;
      }
      unawaited(checkpoint());
    });
  }

  // Leaves the timer non-null, so a presentation sends this frame once.
  void _cancelFirstPaintCheckpoint() => _firstPaintCheckpoint?.cancel();

  /// Wraps an admitted root with the exact successful-first-paint hook.
  Widget wrapRootSubtree(Widget child) {
    final pendingRoute = _pendingRoute;
    if (pendingRoute != null) {
      return _DeferredMeasurementRoot(session: this, child: child);
    }
    final presentationRouteHandle = _presentationRouteHandle;
    if (_debugState != MeasurementHostSessionDebugState.active ||
        presentationRouteHandle == null) {
      return child;
    }
    final constructionSession = _constructionSession;
    if (constructionSession != null) {
      return MeasurementRfwPresentationBinderScope(
        binder: constructionSession,
        child: MeasurementPresentationCommitHook(
          routeHandle: presentationRouteHandle,
          child: child,
        ),
      );
    }
    return MeasurementRfwPresentationScope(
      sink: this,
      child: MeasurementPresentationCommitHook(
        routeHandle: presentationRouteHandle,
        child: child,
      ),
    );
  }

  /// Binds worker-acknowledged point events to the immutable presentation
  /// snapshot owned by the successful root paint.
  void bindPointEventContext(
    RootAnalyticsDeferredContext context, {
    void Function(RestageEvent, RootAnalyticsDeferredContext)? emitEvent,
  }) {
    final opened = _opened;
    if (opened != null) {
      opened.bindPointEventContext(context, emitEvent: emitEvent);
      return;
    }
    if (_isPending) {
      _pendingPointEventBinding = (opened) =>
          opened.bindPointEventContext(context, emitEvent: emitEvent);
      return;
    }
    _constructionSession?.bindPointEventSink((route, value) {
      final RestageEvent event;
      switch (value) {
        case MeasurementWorkerAppendValue.presentation:
          event = SurfacePointPresented(
            occurrenceId: route.occurrenceId,
            lineageId: route.lineageId,
          );
        case MeasurementWorkerAppendValue.interaction:
          event = SurfacePointInteracted(
            occurrenceId: route.occurrenceId,
            lineageId: route.lineageId,
          );
        case MeasurementWorkerAppendValue.completion:
        case MeasurementWorkerAppendValue.skip:
        case MeasurementWorkerAppendValue.dismiss:
          return;
      }
      final ownerEmitter = emitEvent;
      if (ownerEmitter == null) {
        context.runWithEventContext(() => Restage.fireEvent(event));
      } else {
        ownerEmitter(event, context);
      }
    });
  }

  /// Sanitizes one event before returning the value for ordinary host logic.
  ///
  /// Measurement failures are isolated to this event occurrence and never
  /// escape into the host callback path.
  Object? sanitizeAndRecordEvent(Object? rawValue) {
    final opened = _opened;
    if (opened != null) return opened.sanitizeAndRecordEvent(rawValue);
    try {
      final sanitized = MeasurementEventSanitizer.sanitize(rawValue);
      if (sanitized.carrierStatus ==
              MeasurementEventCarrierStatus.exactV1Carrier &&
          sanitized.rawV1CarrierForResolution != null) {
        _recordInteractionCarrier(
          sanitized.rawV1CarrierForResolution!,
          item: sanitized.itemValueForResolution,
        );
      }
      return sanitized.businessValue;
    } on Object {
      return _businessSafeEventFallback(rawValue);
    }
  }

  /// Receives one successful private RFW presentation probe.
  @override
  void recordPresentedCarrier(String rawCarrier) {
    final opened = _opened;
    if (opened != null) return opened.recordPresentedCarrier(rawCarrier);
    if (_holdPending((o) => o.recordPresentedCarrier(rawCarrier))) return;
    if (_constructionSession != null) return;
    final captureSession = _captureSession;
    final routeTable = _routeTable;
    if (_debugState != MeasurementHostSessionDebugState.active ||
        captureSession == null ||
        routeTable == null) {
      return;
    }
    try {
      final route = routeTable.resolveOpaqueRoute(
        context: routeTable.mountedArtifactContext,
        token: OpaqueMeasurementEventSlotToken(rawCarrier),
      );
      if (route != null) captureSession.recordPresentation(route);
    } on Object {
      return;
    }
  }

  void _recordInteractionCarrier(String rawCarrier, {String? item}) {
    if (_holdPending(
        (o) => o._recordInteractionCarrier(rawCarrier, item: item))) {
      return;
    }
    final constructionSession = _constructionSession;
    if (constructionSession != null) {
      constructionSession.recordInteractionCarrier(rawCarrier, item: item);
      return;
    }
    final captureSession = _captureSession;
    final routeTable = _routeTable;
    if (_debugState != MeasurementHostSessionDebugState.active ||
        captureSession == null ||
        routeTable == null) {
      return;
    }
    try {
      final route = routeTable.resolveOpaqueRoute(
        context: routeTable.mountedArtifactContext,
        token: OpaqueMeasurementEventSlotToken(rawCarrier),
      );
      if (route != null) {
        captureSession.recordInteraction(route, itemValueV1: item);
      }
    } on Object {
      return;
    }
  }

  void recordAnswer(String questionId, Object? rawValue) {
    final opened = _opened;
    if (opened != null) return opened.recordAnswer(questionId, rawValue);
    if (_holdPending((o) => o.recordAnswer(questionId, rawValue))) return;
    final construction = _constructionSession;
    if (construction != null) {
      construction.recordAnswer(questionId, rawValue);
      return;
    }
    final table = _routeTable;
    final capture = _captureSession;
    if (_debugState != MeasurementHostSessionDebugState.active ||
        table == null ||
        capture == null) return;
    final published = table.orderedCaptureV1?.routes
        .where((route) => route.declaredAnswerV1?.questionId == questionId)
        .singleOrNull;
    final value = published?.declaredAnswerV1?.capture(rawValue);
    if (value == null || published?.answerCarrier == null) return;
    final route = table.resolveOpaqueRoute(
        context: table.mountedArtifactContext,
        token: OpaqueMeasurementEventSlotToken(published!.answerCarrier!));
    if (route != null) capture.recordAnswer(route, value);
  }

  /// Marks this presentation completed, as app code firing a completesOn event
  /// does: its end records completion, whatever the user taps afterwards.
  void noteCompletion() {
    final opened = _opened;
    if (opened != null) return opened.noteCompletion();
    if (_holdPending((o) => o.noteCompletion())) return;
    _completed = true;
  }

  /// Whether this presentation ends as completed, for tests.
  @visibleForTesting
  bool get debugCompleted => _opened?.debugCompleted ?? _completed;

  /// Records how the surface ended: completion when app code fired a
  /// completing event, otherwise dismiss.
  void recordSurfaceEnd() {
    final opened = _opened;
    if (opened != null) return opened.recordSurfaceEnd();
    if (_holdPending((o) => o.recordSurfaceEnd())) return;
    recordLifecycle(_completed
        ? MeasurementOccurrenceChannelV1.completion
        : MeasurementOccurrenceChannelV1.dismiss);
  }

  bool _rootLifecyclePresented = false;

  /// Resolves a real root or screen callback inside this session's publication.
  void recordLifecycle(MeasurementOccurrenceChannelV1 channel,
      {String? screenId}) {
    final opened = _opened;
    if (opened != null) {
      return opened.recordLifecycle(channel, screenId: screenId);
    }
    if (_holdPending((o) => o.recordLifecycle(channel, screenId: screenId))) {
      return;
    }
    final construction = _constructionSession;
    if (construction != null) {
      construction.recordLifecycle(channel, screenId: screenId);
      return;
    }
    if (_debugState != MeasurementHostSessionDebugState.active) return;
    if (channel == MeasurementOccurrenceChannelV1.presentation &&
        screenId != null) recordLifecycle(channel);
    if (channel == MeasurementOccurrenceChannelV1.presentation &&
        screenId == null &&
        _rootLifecyclePresented) return;
    final mapping = _routeTable?.orderedCaptureV1?.routes
        .map((route) => route.lifecycle)
        .where(
            (route) => route?.channel == channel && route?.screenId == screenId)
        .singleOrNull;
    if (mapping == null) return;
    if (channel == MeasurementOccurrenceChannelV1.presentation &&
        screenId == null) _rootLifecyclePresented = true;
    recordDeclaredOccurrenceCarrier(mapping.carrier, channel);
  }

  /// Records an actual lifecycle event with its exact published route carrier.
  void recordDeclaredOccurrenceCarrier(
      String rawCarrier, MeasurementOccurrenceChannelV1 channel) {
    final opened = _opened;
    if (opened != null) {
      return opened.recordDeclaredOccurrenceCarrier(rawCarrier, channel);
    }
    if (_holdPending(
        (o) => o.recordDeclaredOccurrenceCarrier(rawCarrier, channel))) {
      return;
    }
    final construction = _constructionSession;
    if (construction != null) {
      construction.recordDeclaredOccurrenceCarrier(rawCarrier, channel);
      return;
    }
    final table = _routeTable;
    final capture = _captureSession;
    if (_debugState != MeasurementHostSessionDebugState.active ||
        table == null ||
        capture == null) return;
    try {
      final route = table.resolveOpaqueRoute(
          context: table.mountedArtifactContext,
          token: OpaqueMeasurementEventSlotToken(rawCarrier));
      if (route != null) {
        if (channel == MeasurementOccurrenceChannelV1.presentation) {
          capture.recordPresentation(route);
        } else {
          capture.recordDeclaredOccurrence(route, channel);
        }
      }
    } on Object {
      return;
    }
  }

  /// Orders an outcome report after this presentation's pending delivery.
  Future<void> flushForOutcome() async {
    await _pendingReady?.future;
    final opened = _opened;
    if (opened != null) return opened.flushForOutcome();
    await (_teardownFuture ?? checkpoint());
  }

  /// Delivers this exact presentation before exposing its outcome coordinates.
  Future<
      ({
        String captureSessionNonce,
        MeasurementPublicationBindingReferenceV1 publicationBindingReference
      })?> preparePurchaseExposure() async {
    if (_isPending) _heldOutcomes += 1;
    await flushForOutcome();
    return _opened?._purchaseExposure ?? _purchaseExposure;
  }

  /// Emits and submits one nonterminal cumulative frame when active.
  Future<MeasurementIngestTransportOutcome?> checkpoint() async {
    final opened = _opened;
    if (opened != null) return opened.checkpoint();
    final constructionSession = _constructionSession;
    if (constructionSession != null) {
      try {
        await constructionSession.checkpoint();
      } on Object {
        // The worker-owned path remains observational.
      }
      return null;
    }
    final captureSession = _captureSession;
    if (_debugState != MeasurementHostSessionDebugState.active ||
        captureSession == null) {
      return null;
    }
    try {
      return await _submit(captureSession.checkpoint());
    } on Object {
      return null;
    }
  }

  /// Finalizes and submits one terminal frame at most once.
  Future<MeasurementIngestTransportOutcome?> teardown() {
    final opened = _opened;
    if (opened != null) return opened.teardown();
    if (_isPending) {
      return (_pendingTeardown ??=
              Completer<MeasurementIngestTransportOutcome?>())
          .future;
    }
    final existing = _teardownFuture;
    if (existing != null) return existing;
    if (_debugState != MeasurementHostSessionDebugState.active) {
      return Future<MeasurementIngestTransportOutcome?>.value();
    }
    final future = _teardownActive();
    _teardownFuture = future;
    return future;
  }

  Future<MeasurementIngestTransportOutcome?> _teardownActive() async {
    _debugState = MeasurementHostSessionDebugState.finalized;
    _backgroundCheckpointIssued = true;
    _cancelFirstPaintCheckpoint();
    try {
      _lifecycleRegistration?.unregister();
    } on Object {
      // Finalization remains authoritative even if observer removal fails.
    }
    _lifecycleRegistration = null;
    _presentationRouteHandle?.abandon();
    final lifecycleCheckpoints = List<Future<void>>.of(
      _pendingLifecycleCheckpoints,
    );
    if (lifecycleCheckpoints.isNotEmpty) {
      try {
        await Future.wait(lifecycleCheckpoints);
      } on Object {
        // Checkpoint failure cannot suppress the one terminal frame.
      }
    }
    final captureSession = _captureSession;
    final constructionSession = _constructionSession;
    if (constructionSession != null) {
      try {
        await constructionSession.teardown();
      } on Object {
        // A worker failure never reopens legacy collection.
      }
      _constructionSession = null;
      return null;
    }
    if (captureSession == null) return null;
    try {
      return await _submit(captureSession.teardown());
    } on Object {
      return null;
    }
  }

  Future<MeasurementIngestTransportOutcome?> _submit(
    MeasurementFactFrame frame,
  ) async {
    final transport = _transport;
    if (transport == null) return null;
    try {
      return await transport.submit(
        MeasurementIngestSubmission.fromFactFrame(frame,
            routingSelectionReceipt: _routingSelectionReceipt),
      );
    } on Object {
      return const MeasurementIngestTransportUnavailable(
        MeasurementIngestUnavailableReason.transportFailure,
      );
    }
  }
}

// One open's shared deadline and the authority it was started under.
final class _OpenAttempt {
  _OpenAttempt() : isCurrent = Restage.captureEventAuthority() {
    _deadline = Timer(
      MeasurementHostSessionController.openFailureBound,
      _expired.complete,
    );
  }

  final bool Function() isCurrent;
  final _expired = Completer<void>();
  late final Timer _deadline;
  Future<SurfaceDeliveryObservations?>? _observations;

  /// Whether the pending root already observes the app lifecycle.
  bool lifecycleObserved = false;

  void finish() => _deadline.cancel();

  /// Fails the open once its deadline has passed.
  void throwIfExpired() {
    if (_expired.isCompleted) {
      throw TimeoutException(
        'Measurement open',
        MeasurementHostSessionController.openFailureBound,
      );
    }
  }

  /// Fails [step] at the deadline; a later result goes to [discardLate].
  Future<T> bound<T>(Future<T> step, {void Function(T late)? discardLate}) {
    final result = Completer<T>();
    step.then((value) {
      if (result.isCompleted) {
        discardLate?.call(value);
      } else {
        result.complete(value);
      }
    }, onError: (Object error, StackTrace stack) {
      if (!result.isCompleted) result.completeError(error, stack);
    });
    void expire([Object? _]) {
      if (result.isCompleted) return;
      result.completeError(TimeoutException(
        'Measurement open',
        MeasurementHostSessionController.openFailureBound,
      ));
    }

    if (_expired.isCompleted) {
      expire();
    } else {
      unawaited(_expired.future.then(expire));
    }
    return result.future;
  }

  /// Starts the observations read so it overlaps the rest of the open.
  void readObservations(
    Future<SurfaceDeliveryObservations?> Function()? read,
  ) {
    if (read == null) return;
    try {
      _observations = read().then<SurfaceDeliveryObservations?>(
        (value) => value,
        onError: (Object _) => null,
      );
    } on Object {
      _observations = null;
    }
  }

  /// The observations, or null when they are not ready in time.
  Future<SurfaceDeliveryObservations?> observations() async {
    final reading = _observations;
    if (reading == null) return null;
    final ready = Completer<SurfaceDeliveryObservations?>();
    final wait = Timer(
      MeasurementHostSessionController.presentationObservationsWait,
      () => ready.isCompleted ? null : ready.complete(null),
    );
    unawaited(reading.then((value) {
      if (!ready.isCompleted) ready.complete(value);
    }));
    try {
      return await bound(ready.future);
    } on Object {
      return null;
    } finally {
      wait.cancel();
    }
  }
}

String _encodeNonce(List<int> bytes) {
  if (bytes.length != 32 || bytes.any((value) => value < 0 || value > 255)) {
    throw ArgumentError.value(
      bytes,
      'nonceBytes',
      'Expected exactly 32 unsigned nonce bytes',
    );
  }
  final encoded = base64UrlEncode(bytes);
  final padding = encoded.indexOf('=');
  return padding == -1 ? encoded : encoded.substring(0, padding);
}

Object? _businessSafeEventFallback(Object? rawValue) {
  if (rawValue is! Map) return rawValue;
  try {
    final businessValue = <Object?, Object?>{};
    for (final entry in rawValue.entries) {
      final key = entry.key;
      if (key is String && key.startsWith('__restage_measurement_')) {
        continue;
      }
      businessValue[key] = entry.value;
    }
    return businessValue;
  } on Object {
    return const <Object?, Object?>{};
  }
}

/// The root of a surface whose session is still opening. Its shape never
/// changes when the session opens, so the surface does not remount.
final class _DeferredMeasurementRoot extends StatelessWidget {
  const _DeferredMeasurementRoot({required this.session, required this.child});

  final MeasurementHostSessionController session;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final hooked = MeasurementPresentationCommitHook(
      routeHandle: session._pendingRoute!,
      child: child,
    );
    if (!session._pendingWorkerOwned) {
      return MeasurementRfwPresentationScope(sink: session, child: hooked);
    }
    return MeasurementRfwPresentationBinderScope(
      binder: session._pendingBinder,
      child: hooked,
    );
  }
}

// Tells the session when its presentation first paints successfully.
final class _FirstPaintSink implements MeasurementPresentationCaptureSink {
  _FirstPaintSink(this._inner);

  final MeasurementPresentationCaptureSink _inner;
  void Function()? onPresented;

  @override
  void recordSuccessfulPresentation(
    MeasurementSuccessfulPresentationFact fact,
  ) {
    _inner.recordSuccessfulPresentation(fact);
    onPresented?.call();
  }
}
