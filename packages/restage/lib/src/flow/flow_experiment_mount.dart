import 'dart:async';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:restage_shared/flow_experiment.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/rfw.dart' show decodeLibraryBlob;

import '../resolver/surface_assignment_key_provider.dart';
import '../runtime/builtin_catalog_capabilities.dart';
import '../runtime/library_runtime_registry.dart';
import '../runtime/restage.dart';
import 'flow_descriptors.dart';
import 'flow_experiment_artifact_metadata.dart';
import 'flow_resolver.dart';

typedef FlowMountSeedCapture = FlowMountLeaseSeed Function();
typedef FlowAssignmentKeyResolver = FutureOr<String?> Function();
typedef FlowCandidatePromotionBarrier = FutureOr<void> Function();

/// Creates one isolated experiment resolver for one root presentation.
@internal
abstract interface class FlowExperimentMountFactory {
  bool get experimentMountsEnabled;

  FlowExperimentPresentationResolver createExperimentPresentation({
    required OnboardingFlowRef<Object?> flow,
    required FlowMountSeedCapture captureSeed,
  });

  FlowResolver createUnassignedFallbackResolver();
}

/// Per-presentation active resolver and paint-publication authority.
@internal
abstract interface class FlowExperimentPresentationAuthority {
  bool revalidate(FlowMountRevalidationBoundary boundary);

  void publishHostedLastGood();

  void abandonHostedLastGood();

  void disposePresentation();
}

/// Per-presentation active resolver joined to its publication authority.
@internal
abstract interface class FlowExperimentPresentationResolver
    implements
        FlowResolver,
        ActiveArmFlowResolver,
        FlowExperimentPresentationAuthority {}

/// Captures the production mutable authorities for one root presentation.
///
/// Action and signal registries are host-owned and may be hand-written, so the
/// SDK cannot require a new public generation getter. This source owns
/// monotonic per-presentation generations that advance whenever their complete
/// compatibility evidence changes. The deep values are still frozen into every
/// seed and remain the authoritative compatibility inputs.
@internal
final class FlowMountRuntimeSeedSource {
  FlowMountRuntimeSeedSource({
    required this.flow,
    required this.actions,
    required this.installedSignalNames,
  });

  final OnboardingFlowRef<Object?> flow;
  final FlowActionRegistry? actions;
  final Set<String> installedSignalNames;

  List<FlowActionBindingFingerprintV1>? _previousActionBindings;
  List<String>? _previousSignals;
  int _actionGeneration = 0;
  int _signalGeneration = 0;

  FlowMountLeaseSeed capture() {
    final bindings = actions?.flowActionBindings ??
        const <String, FlowActionBinding<dynamic, dynamic>>{};
    final signals = <String>{...installedSignalNames};
    final registry = actions;
    if (registry is FlowSignalRegistry) {
      signals.addAll((registry as FlowSignalRegistry).installedSignalNames);
    }

    final actionFingerprints = _fingerprintActionBindings(bindings);
    final signalSnapshot = signals.toList()..sort();
    final previousActions = _previousActionBindings;
    if (previousActions != null &&
        !_actionBindingsEqual(previousActions, actionFingerprints)) {
      _actionGeneration += 1;
    }
    final previousSignals = _previousSignals;
    if (previousSignals != null &&
        !_stringsEqual(previousSignals, signalSnapshot)) {
      _signalGeneration += 1;
    }
    _previousActionBindings =
        List<FlowActionBindingFingerprintV1>.unmodifiable(actionFingerprints);
    _previousSignals = List<String>.unmodifiable(signalSnapshot);

    return FlowMountLeaseSeed.capture(
      flow: flow,
      deliveryMode: flow.deliveryMode,
      assignmentKeyProviderGeneration:
          SurfaceAssignmentKeyProvider.configurationGeneration,
      analyticsIdentityGeneration:
          SurfaceAssignmentKeyProvider.analyticsIdentityGeneration,
      configurationGeneration: Restage.configurationGeneration,
      libraryGeneration: LibraryRuntimeRegistry.generation,
      actionGeneration: _actionGeneration,
      signalGeneration: _signalGeneration,
      builtInCatalogVersion: RestageBuiltInCatalogCapabilities.currentVersion,
      installedLibraries: LibraryRuntimeRegistry.installedSnapshot(),
      actionBindings: bindings,
      installedSignals: signals,
    );
  }
}

@internal
@immutable
final class FlowMountLeaseSeed {
  factory FlowMountLeaseSeed.capture({
    required OnboardingFlowRef<Object?> flow,
    required FlowDeliveryMode deliveryMode,
    required int assignmentKeyProviderGeneration,
    required int analyticsIdentityGeneration,
    required int configurationGeneration,
    required int libraryGeneration,
    required int actionGeneration,
    required int signalGeneration,
    required int builtInCatalogVersion,
    required List<InstalledLibrary> installedLibraries,
    required Map<String, FlowActionBinding<dynamic, dynamic>> actionBindings,
    required Set<String> installedSignals,
  }) {
    return FlowMountLeaseSeed._(
      surfaceType: flow.surfaceType,
      flowId: flow.id,
      flowVersion: flow.version,
      minimumClient: flow.minClient,
      deliveryMode: deliveryMode,
      assignmentKeyProviderGeneration: assignmentKeyProviderGeneration,
      analyticsIdentityGeneration: analyticsIdentityGeneration,
      configurationGeneration: configurationGeneration,
      libraryGeneration: libraryGeneration,
      actionGeneration: actionGeneration,
      signalGeneration: signalGeneration,
      installedCapability: InstalledCapability(
        builtInCatalogVersion: builtInCatalogVersion,
        installedLibraries: List<InstalledLibrary>.of(installedLibraries),
      ),
      actionBindings: _fingerprintActionBindings(actionBindings),
      installedSignals: installedSignals.toList()..sort(),
    );
  }

  FlowMountLeaseSeed._({
    required this.surfaceType,
    required this.flowId,
    required this.flowVersion,
    required this.minimumClient,
    required this.deliveryMode,
    required this.assignmentKeyProviderGeneration,
    required this.analyticsIdentityGeneration,
    required this.configurationGeneration,
    required this.libraryGeneration,
    required this.actionGeneration,
    required this.signalGeneration,
    required this.installedCapability,
    required List<FlowActionBindingFingerprintV1> actionBindings,
    required List<String> installedSignals,
  })  : actionBindings = List.unmodifiable(actionBindings),
        installedSignals = List.unmodifiable(installedSignals);

  final Surface surfaceType;
  final String flowId;
  final int flowVersion;
  final int minimumClient;
  final FlowDeliveryMode deliveryMode;
  final int assignmentKeyProviderGeneration;
  final int analyticsIdentityGeneration;
  final int configurationGeneration;
  final int libraryGeneration;
  final int actionGeneration;
  final int signalGeneration;
  final InstalledCapability installedCapability;
  final List<FlowActionBindingFingerprintV1> actionBindings;
  final List<String> installedSignals;

  bool sameIdentityAs(FlowMountLeaseSeed other) {
    return surfaceType == other.surfaceType &&
        flowId == other.flowId &&
        flowVersion == other.flowVersion &&
        minimumClient == other.minimumClient &&
        deliveryMode == other.deliveryMode &&
        assignmentKeyProviderGeneration ==
            other.assignmentKeyProviderGeneration &&
        analyticsIdentityGeneration == other.analyticsIdentityGeneration &&
        configurationGeneration == other.configurationGeneration &&
        libraryGeneration == other.libraryGeneration &&
        actionGeneration == other.actionGeneration &&
        signalGeneration == other.signalGeneration &&
        installedCapability == other.installedCapability &&
        _actionBindingsEqual(actionBindings, other.actionBindings) &&
        _stringsEqual(installedSignals, other.installedSignals);
  }
}

enum FlowMountSnapshotRejection {
  seedDrift,
  closureInvalid,
}

sealed class FlowMountSnapshotOutcome {
  const FlowMountSnapshotOutcome();
}

final class FlowMountSnapshotSealed extends FlowMountSnapshotOutcome {
  const FlowMountSnapshotSealed(this.snapshot);

  final FlowMountContractSnapshot snapshot;
}

final class FlowMountSnapshotRejected extends FlowMountSnapshotOutcome {
  const FlowMountSnapshotRejected(this.reason);

  final FlowMountSnapshotRejection reason;
}

@internal
final class FlowMountContractSnapshotBuilder {
  const FlowMountContractSnapshotBuilder({
    required this.captureSeed,
    required this.resolveAssignmentKey,
    required this.resolver,
  });

  final FlowMountSeedCapture captureSeed;
  final FlowAssignmentKeyResolver resolveAssignmentKey;
  final FlowResolver resolver;

  Future<FlowMountSnapshotOutcome> seal() async {
    try {
      final seed = captureSeed();
      final assignmentKey = await resolveAssignmentKey();
      if (!_seedIsCurrent(seed, captureSeed)) {
        return const FlowMountSnapshotRejected(
          FlowMountSnapshotRejection.seedDrift,
        );
      }

      final loaded = await _FlowExperimentClosureLoader(
        seed: seed,
        captureSeed: captureSeed,
        resolver: resolver,
      ).loadBaseline();
      if (!_seedIsCurrent(seed, captureSeed)) {
        return const FlowMountSnapshotRejected(
          FlowMountSnapshotRejection.seedDrift,
        );
      }
      final contract = FlowExperimentClientContractV1(
        surfaceType: seed.surfaceType,
        deliveryMode: seed.deliveryMode,
        descriptor: FlowExperimentDescriptorV1(
          id: seed.flowId,
          version: seed.flowVersion,
          minClient: seed.minimumClient,
        ),
        documents: loaded.documents,
        installedCapability: seed.installedCapability,
        actionBindings: seed.actionBindings,
        installedSignals: seed.installedSignals,
      );
      return FlowMountSnapshotSealed(FlowMountContractSnapshot(
        seed: seed,
        assignmentKey: assignmentKey,
        clientBaselineClosure: loaded.toClosure(seed.minimumClient),
        contract: contract,
        baselineRoot: loaded.rootFlow,
        baselineResolver: _PinnedFlowResolver(
          surfaceType: seed.surfaceType,
          flows: loaded.flows,
        ),
      ));
    } on _SeedDrift {
      return const FlowMountSnapshotRejected(
        FlowMountSnapshotRejection.seedDrift,
      );
    } on Object {
      return const FlowMountSnapshotRejected(
        FlowMountSnapshotRejection.closureInvalid,
      );
    }
  }
}

enum FlowMountRevalidationBoundary {
  request,
  uploadRetry,
  candidatePrefetch,
  fallback,
  pendingPromotion,
  cachePublication,
  firstPaint,
}

@internal
@immutable
final class FlowMountContractSnapshot {
  FlowMountContractSnapshot({
    required this.seed,
    required this.assignmentKey,
    required this.clientBaselineClosure,
    required this.contract,
    required this.baselineRoot,
    required this.baselineResolver,
  })  : _canonicalBytes =
            Uint8List.fromList(contract.canonicalBytes).asUnmodifiableView(),
        contentHash = contract.contentHash;

  final FlowMountLeaseSeed seed;
  final String? assignmentKey;
  final FlowExperimentClosureV1 clientBaselineClosure;
  final FlowExperimentClientContractV1 contract;
  final ResolvedFlow baselineRoot;
  final FlowResolver baselineResolver;
  final Uint8List _canonicalBytes;
  final FlowContentHash contentHash;

  Uint8List get canonicalBytes => _canonicalBytes;

  bool revalidate(
    FlowMountRevalidationBoundary boundary,
    FlowMountLeaseSeed current,
  ) =>
      seed.sameIdentityAs(current);

  Uint8List? bytesForRetry(
    FlowMountRevalidationBoundary boundary,
    FlowMountLeaseSeed current,
  ) =>
      revalidate(boundary, current)
          ? Uint8List.fromList(_canonicalBytes).asUnmodifiableView()
          : null;
}

enum FlowCandidatePrefetchRejection {
  prefetchFailed,
  parityRejected,
  serverVerdictMismatch,
  seedDrift,
}

sealed class FlowCandidatePrefetchOutcome {
  const FlowCandidatePrefetchOutcome();
}

final class FlowCandidatePrefetchAccepted extends FlowCandidatePrefetchOutcome {
  const FlowCandidatePrefetchAccepted._({
    required this.candidateRoot,
    required this.resolver,
    required this.candidateClosure,
    required this.verdict,
  });

  final ResolvedFlow candidateRoot;
  final FlowResolver resolver;
  final FlowExperimentClosureV1 candidateClosure;
  final FlowExperimentVerdictV1 verdict;

  FlowCandidatePrefetchAccepted asCacheHit() {
    final cacheHitResolver = (resolver as _PinnedFlowResolver).asCacheHit();
    final cacheHitRoot =
        cacheHitResolver._flows[_documentIdentity(candidateRoot.document)]!;
    return FlowCandidatePrefetchAccepted._(
      candidateRoot: cacheHitRoot,
      resolver: cacheHitResolver,
      candidateClosure: candidateClosure,
      verdict: verdict,
    );
  }
}

final class FlowCandidatePrefetchRejected extends FlowCandidatePrefetchOutcome {
  const FlowCandidatePrefetchRejected(this.reason);

  final FlowCandidatePrefetchRejection reason;
}

@internal
abstract final class FlowCandidatePrefetcher {
  static Future<FlowCandidatePrefetchOutcome> prefetch({
    required FlowMountContractSnapshot snapshot,
    required FlowMountSeedCapture captureSeed,
    required ResolvedFlow candidateRoot,
    required FlowResolver resolver,
    required bool serverVerdictAccepted,
    FlowCandidatePromotionBarrier? beforePromotion,
  }) async {
    try {
      if (!_snapshotIsCurrent(
        snapshot,
        FlowMountRevalidationBoundary.candidatePrefetch,
        captureSeed,
      )) {
        return const FlowCandidatePrefetchRejected(
          FlowCandidatePrefetchRejection.seedDrift,
        );
      }
      final loaded = await _FlowExperimentClosureLoader(
        seed: snapshot.seed,
        captureSeed: captureSeed,
        resolver: resolver,
      ).loadCandidate(candidateRoot);
      if (!_snapshotIsCurrent(
        snapshot,
        FlowMountRevalidationBoundary.candidatePrefetch,
        captureSeed,
      )) {
        return const FlowCandidatePrefetchRejected(
          FlowCandidatePrefetchRejection.seedDrift,
        );
      }

      final closure = loaded.toClosure(snapshot.seed.minimumClient);
      final verdict = FlowExperimentEligibilityEvaluatorV1.evaluate(
        FlowExperimentVerdictInputV1(
          clientBaselineClosure: snapshot.clientBaselineClosure,
          candidateArmClosure: closure,
          installedCapability: snapshot.seed.installedCapability,
          actionBindings: snapshot.seed.actionBindings,
          installedSignals: snapshot.seed.installedSignals,
          surfaceType: snapshot.seed.surfaceType,
          deliveryMode: snapshot.seed.deliveryMode,
          flowGateRevision: kFlowExperimentGateLogicRevisionV1,
        ),
      );
      if (!verdict.accepted) {
        return const FlowCandidatePrefetchRejected(
          FlowCandidatePrefetchRejection.parityRejected,
        );
      }
      if (!serverVerdictAccepted) {
        return const FlowCandidatePrefetchRejected(
          FlowCandidatePrefetchRejection.serverVerdictMismatch,
        );
      }
      if (beforePromotion != null) {
        await beforePromotion();
      }
      if (!_snapshotIsCurrent(
        snapshot,
        FlowMountRevalidationBoundary.pendingPromotion,
        captureSeed,
      )) {
        return const FlowCandidatePrefetchRejected(
          FlowCandidatePrefetchRejection.seedDrift,
        );
      }
      return FlowCandidatePrefetchAccepted._(
        candidateRoot: loaded.rootFlow,
        resolver: _PinnedFlowResolver(
          surfaceType: snapshot.seed.surfaceType,
          flows: loaded.flows,
        ),
        candidateClosure: closure,
        verdict: verdict,
      );
    } on _SeedDrift {
      return const FlowCandidatePrefetchRejected(
        FlowCandidatePrefetchRejection.seedDrift,
      );
    } on Object {
      return const FlowCandidatePrefetchRejected(
        FlowCandidatePrefetchRejection.prefetchFailed,
      );
    }
  }
}

final class _PinnedFlowResolver implements FlowResolver {
  _PinnedFlowResolver({
    required this.surfaceType,
    required Map<String, ResolvedFlow> flows,
  }) : _flows = Map.unmodifiable(flows);

  final Surface surfaceType;
  final Map<String, ResolvedFlow> _flows;

  _PinnedFlowResolver asCacheHit() {
    return _PinnedFlowResolver(
      surfaceType: surfaceType,
      flows: {
        for (final entry in _flows.entries)
          entry.key: _resolvedFlowAsCacheHit(entry.value),
      },
    );
  }

  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) async {
    final resolved = flow.surfaceType == surfaceType
        ? _flows[_documentIdentityParts(flow.id, flow.version)]
        : null;
    if (resolved == null) {
      throw FlowUnavailableError(
        flowId: flow.id,
        flowVersion: flow.version,
        reason: 'not_pinned',
        message: 'Flow "${flow.id}" version ${flow.version} was not pinned.',
      );
    }
    return resolved;
  }
}

ResolvedFlow _resolvedFlowAsCacheHit(ResolvedFlow flow) {
  return ResolvedFlow(
    document: flow.document,
    screenBlobs: flow.screenBlobs,
    contentHash: flow.contentHash,
    cacheHit: true,
    assignment: flow.assignment,
  );
}

final class _FlowExperimentClosureLoader {
  _FlowExperimentClosureLoader({
    required this.seed,
    required this.captureSeed,
    required this.resolver,
  }) : _metadataProvider = resolver is FlowExperimentArtifactMetadataProvider
            ? resolver as FlowExperimentArtifactMetadataProvider
            : null;

  final FlowMountLeaseSeed seed;
  final FlowMountSeedCapture captureSeed;
  final FlowResolver resolver;
  final FlowExperimentArtifactMetadataProvider? _metadataProvider;
  final Map<String, _LoadedDocument> _loaded = {};
  var _allPayloadIntegrityVerified = true;

  Future<_LoadedClosure> loadBaseline() async {
    final root = await resolver.resolve<Object?>(OnboardingFlowRef<Object?>(
      id: seed.flowId,
      version: seed.flowVersion,
      minClient: seed.minimumClient,
      surface: seed.surfaceType,
      decodeResult: _identityResult,
    ));
    _checkSeed();
    await _visit(
      root,
      expected: _ExpectedDocument(
        flowId: seed.flowId,
        version: seed.flowVersion,
      ),
      depth: 0,
      path: const {},
    );
    _checkSeed();
    return _closure(root);
  }

  Future<_LoadedClosure> loadCandidate(ResolvedFlow root) async {
    await _visit(
      root,
      expected: _ExpectedDocument(flowId: seed.flowId),
      depth: 0,
      path: const {},
    );
    _checkSeed();
    return _closure(root);
  }

  _LoadedClosure _closure(ResolvedFlow root) {
    final identity = _documentIdentity(root.document);
    final rootDocument = _loaded[identity];
    if (rootDocument == null) {
      throw const FormatException('Resolved closure omitted its root.');
    }
    return _LoadedClosure(
      root: rootDocument.contract,
      rootFlow: rootDocument.flow,
      documents: [
        for (final loaded in _loaded.values) loaded.contract,
      ],
      flows: {
        for (final entry in _loaded.entries) entry.key: entry.value.flow,
      },
      integrity: FlowExperimentArtifactIntegrityV1(
        payloadIntegrityVerified: _allPayloadIntegrityVerified,
        screenIntegrityVerified: true,
        rfwIntegrityVerified: true,
      ),
    );
  }

  Future<void> _visit(
    ResolvedFlow resolved, {
    required _ExpectedDocument expected,
    required int depth,
    required Set<String> path,
  }) async {
    final document = resolved.document;
    final identity = _documentIdentity(document);
    if (path.contains(identity)) {
      throw FormatException('Flow closure contains a cycle at $identity.');
    }
    _validateResolved(resolved, expected);

    final existing = _loaded[identity];
    if (existing != null) {
      if (existing.flow.contentHash != resolved.contentHash) {
        throw FormatException(
          'Flow closure contains inconsistent pins for $identity.',
        );
      }
    } else {
      final metadata = _metadataProvider?.metadataFor(resolved);
      if (metadata == null) {
        throw FormatException(
          'Flow resolver omitted experiment artifact metadata for $identity.',
        );
      }
      _allPayloadIntegrityVerified &= metadata.payloadIntegrityVerified;
      _loaded[identity] = _LoadedDocument(
        flow: resolved,
        contract: FlowExperimentDocumentContractV1(
          surfaceType: seed.surfaceType,
          flowId: document.flow,
          version: document.version,
          schemaVersion: document.schemaVersion,
          minClient: document.minClient,
          contentHash: resolved.contentHash!,
          requiredLibraries: metadata.requiredLibraries,
          flowDocument: document,
        ),
      );
    }

    final nextPath = {...path, identity};
    for (final state in document.states.values) {
      if (state is! SubFlowState) continue;
      if (depth >= 4) {
        throw const FormatException(
          'Flow closure exceeds maximum sub-flow depth 4.',
        );
      }
      final childIdentity = _documentIdentityParts(state.flow, state.version);
      final cached = _loaded[childIdentity]?.flow;
      final ResolvedFlow child;
      if (cached != null) {
        child = cached;
      } else {
        child = await resolver.resolve<Object?>(OnboardingFlowRef<Object?>(
          id: state.flow,
          version: state.version,
          minClient: state.minClient,
          surface: seed.surfaceType,
          decodeResult: _identityResult,
        ));
        _checkSeed();
      }
      await _visit(
        child,
        expected: _ExpectedDocument.fromSubFlow(state),
        depth: depth + 1,
        path: nextPath,
      );
      _checkSeed();
    }
  }

  void _validateResolved(
    ResolvedFlow resolved,
    _ExpectedDocument expected,
  ) {
    final document = resolved.document;
    if (document.flow != expected.flowId ||
        (expected.version != null && document.version != expected.version) ||
        (expected.schemaVersion != null &&
            document.schemaVersion != expected.schemaVersion) ||
        (expected.minClient != null &&
            document.minClient != expected.minClient) ||
        document.deliveryMode != seed.deliveryMode) {
      throw FormatException(
        'Resolved flow "${document.flow}" does not match its exact pin.',
      );
    }
    final contentHash = resolved.contentHash;
    final actualHash = FlowContentHash.compute(
      FlowDocumentCodec.encodeCanonicalJson(document),
    );
    if (contentHash == null ||
        contentHash != actualHash ||
        (expected.contentHash != null && contentHash != expected.contentHash)) {
      throw FormatException(
        'Resolved flow "${document.flow}" has an invalid content hash.',
      );
    }
    final issues = FlowDocumentValidation.validate(document);
    if (issues.isNotEmpty) {
      throw FormatException(
        'Resolved flow "${document.flow}" failed validation: '
        '${issues.join('; ')}.',
      );
    }
    if (resolved.screenBlobs.length != document.screenArtifacts.length) {
      throw FormatException(
        'Resolved flow "${document.flow}" has an incomplete screen set.',
      );
    }
    for (final entry in document.screenArtifacts.entries) {
      final bytes = resolved.screenBlobs[entry.key];
      if (bytes == null ||
          FlowContentHash.compute(bytes) != entry.value.contentHash) {
        throw FormatException(
          'Resolved flow "${document.flow}" has an invalid screen blob.',
        );
      }
      decodeLibraryBlob(bytes);
    }
  }

  void _checkSeed() {
    if (!_seedIsCurrent(seed, captureSeed)) throw const _SeedDrift();
  }
}

final class _LoadedClosure {
  const _LoadedClosure({
    required this.root,
    required this.rootFlow,
    required this.documents,
    required this.flows,
    required this.integrity,
  });

  final FlowExperimentDocumentContractV1 root;
  final ResolvedFlow rootFlow;
  final List<FlowExperimentDocumentContractV1> documents;
  final Map<String, ResolvedFlow> flows;
  final FlowExperimentArtifactIntegrityV1 integrity;

  FlowExperimentClosureV1 toClosure(int rootCapability) {
    return FlowExperimentClosureV1(
      root: root,
      rootCapability: rootCapability,
      documents: documents,
      integrity: integrity,
    );
  }
}

final class _LoadedDocument {
  const _LoadedDocument({
    required this.flow,
    required this.contract,
  });

  final ResolvedFlow flow;
  final FlowExperimentDocumentContractV1 contract;
}

final class _ExpectedDocument {
  const _ExpectedDocument({
    required this.flowId,
    this.version,
    this.schemaVersion,
    this.minClient,
    this.contentHash,
  });

  factory _ExpectedDocument.fromSubFlow(SubFlowState state) {
    return _ExpectedDocument(
      flowId: state.flow,
      version: state.version,
      schemaVersion: state.schemaVersion,
      minClient: state.minClient,
      contentHash: state.contentHash,
    );
  }

  final String flowId;
  final int? version;
  final int? schemaVersion;
  final int? minClient;
  final FlowContentHash? contentHash;
}

final class _SeedDrift implements Exception {
  const _SeedDrift();
}

bool _seedIsCurrent(
  FlowMountLeaseSeed seed,
  FlowMountSeedCapture captureSeed,
) {
  try {
    return seed.sameIdentityAs(captureSeed());
  } on Object {
    return false;
  }
}

bool _snapshotIsCurrent(
  FlowMountContractSnapshot snapshot,
  FlowMountRevalidationBoundary boundary,
  FlowMountSeedCapture captureSeed,
) {
  try {
    return snapshot.revalidate(boundary, captureSeed());
  } on Object {
    return false;
  }
}

Map<String, Object?> _identityResult(Map<String, Object?> value) => value;

String _documentIdentity(FlowDocument document) =>
    _documentIdentityParts(document.flow, document.version);

String _documentIdentityParts(String flowId, int version) =>
    '$flowId\u0000$version';

bool _stringsEqual(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

bool _actionBindingsEqual(
  List<FlowActionBindingFingerprintV1> left,
  List<FlowActionBindingFingerprintV1> right,
) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    final a = left[index];
    final b = right[index];
    if (a.actionId != b.actionId ||
        a.actionName != b.actionName ||
        a.contractVersion != b.contractVersion ||
        a.argsSchemaHash != b.argsSchemaHash ||
        a.resultSchemaHash != b.resultSchemaHash ||
        a.minClient != b.minClient ||
        a.idempotent != b.idempotent) {
      return false;
    }
  }
  return true;
}

List<FlowActionBindingFingerprintV1> _fingerprintActionBindings(
  Map<String, FlowActionBinding<dynamic, dynamic>> bindings,
) {
  final fingerprints = [
    for (final entry in bindings.entries)
      FlowActionBindingFingerprintV1(
        actionId: entry.key,
        actionName: entry.value.actionName,
        contractVersion: entry.value.contractVersion,
        argsSchemaHash: entry.value.argsSchemaHash,
        resultSchemaHash: entry.value.resultSchemaHash,
        minClient: entry.value.minClient,
        idempotent: entry.value.idempotent,
      ),
  ]..sort((left, right) {
      final idOrder = left.actionId.compareTo(right.actionId);
      return idOrder != 0
          ? idOrder
          : left.actionName.compareTo(right.actionName);
    });
  return fingerprints;
}
