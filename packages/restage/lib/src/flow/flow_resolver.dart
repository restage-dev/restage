import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:restage_shared/restage_shared.dart';

import 'bundled_flow_loader.dart';
import 'flow_descriptors.dart';

/// Resolves onboarding flow descriptors for `RestageOnboarding`.
///
/// A resolver returns a validated flow document plus the exact pinned screen
/// blobs it references. Resolver failures are surfaced as unavailable flows by
/// `RestageOnboarding`.
abstract interface class FlowResolver {
  /// Resolves [flow] into a validated flow document and pinned screen blobs.
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow);
}

/// A validated flow document and the exact screen blobs it references.
///
/// Screen blobs are keyed by screen id after hash and compatibility checks by
/// the resolver. The flow controller treats this object as immutable.
@immutable
final class ResolvedFlow {
  /// Creates an immutable resolved flow.
  ResolvedFlow({
    required FlowDocument document,
    required Map<String, Uint8List> screenBlobs,
    this.contentHash,
    required this.cacheHit,
  })  : document = _freezeDocument(document),
        screenBlobs = Map.unmodifiable({
          for (final entry in screenBlobs.entries)
            entry.key: Uint8List.fromList(entry.value).asUnmodifiableView(),
        });

  const ResolvedFlow._({
    required this.document,
    required this.screenBlobs,
    required this.contentHash,
    required this.cacheHit,
  });

  /// Decoded and validated flow document.
  final FlowDocument document;

  /// Exact RFW screen blobs keyed by screen id.
  final Map<String, Uint8List> screenBlobs;

  /// Hash of the exact encoded flow document artifact, when available.
  final FlowContentHash? contentHash;

  /// Whether this result came from the in-memory identity cache.
  final bool cacheHit;

  ResolvedFlow _withCacheHit() {
    return ResolvedFlow._(
      document: document,
      screenBlobs: screenBlobs,
      contentHash: contentHash,
      cacheHit: true,
    );
  }
}

FlowDocument _freezeDocument(FlowDocument document) {
  return FlowDocument(
    flow: document.flow,
    version: document.version,
    schemaVersion: document.schemaVersion,
    minClient: document.minClient,
    initial: document.initial,
    actions: Map.unmodifiable(document.actions),
    flowState: Map.unmodifiable({
      for (final entry in document.flowState.entries)
        entry.key: _freezeFlowStateDeclaration(entry.value),
    }),
    outbound: _freezeOutboundDeclarations(document.outbound),
    legacyTerminalResultPassthrough: document.legacyTerminalResultPassthrough,
    screenArtifacts: Map.unmodifiable(document.screenArtifacts),
    states: Map.unmodifiable({
      for (final entry in document.states.entries)
        entry.key: _freezeState(entry.value),
    }),
    unsupportedFeatures: Set.unmodifiable(document.unsupportedFeatures),
  );
}

FlowStateDeclaration _freezeFlowStateDeclaration(
  FlowStateDeclaration declaration,
) {
  return FlowStateDeclaration(
    type: declaration.type,
    classification: declaration.classification,
    defaultValue: _freezeJsonValue(declaration.defaultValue),
  );
}

FlowOutboundDeclarations _freezeOutboundDeclarations(
  FlowOutboundDeclarations declarations,
) {
  return FlowOutboundDeclarations(
    actionArgs: _freezeOutboundPayloads(declarations.actionArgs),
    terminalResult: _freezeOutboundPayload(declarations.terminalResult),
    lifecycle: _freezeOutboundPayload(declarations.lifecycle),
    surveyAnswers: _freezeOutboundPayload(declarations.surveyAnswers),
    subFlowResult: _freezeOutboundPayload(declarations.subFlowResult),
    customEvents: _freezeOutboundPayloads(declarations.customEvents),
  );
}

Map<String, FlowOutboundPayloadDeclaration> _freezeOutboundPayloads(
  Map<String, FlowOutboundPayloadDeclaration> declarations,
) {
  return Map.unmodifiable({
    for (final entry in declarations.entries)
      entry.key: _freezeOutboundPayload(entry.value),
  });
}

FlowOutboundPayloadDeclaration _freezeOutboundPayload(
  FlowOutboundPayloadDeclaration declaration,
) {
  return FlowOutboundPayloadDeclaration(
    fields: Map.unmodifiable({
      for (final entry in declaration.fields.entries)
        entry.key: _freezeOutboundField(entry.value),
    }),
  );
}

FlowOutboundField _freezeOutboundField(FlowOutboundField field) {
  return FlowOutboundField(
    type: field.type,
    ref: _freezeOutboundRef(field.ref),
  );
}

FlowOutboundRef _freezeOutboundRef(FlowOutboundRef ref) {
  return switch (ref) {
    StateFlowOutboundRef(:final key, :final path) => StateFlowOutboundRef(
        key: key,
        path: List.unmodifiable(path),
      ),
    EventFlowOutboundRef(:final key, :final path) => EventFlowOutboundRef(
        key: key,
        path: List.unmodifiable(path),
      ),
  };
}

FlowState _freezeState(FlowState state) {
  return switch (state) {
    ScreenFlowState(:final screen, :final on) => ScreenFlowState(
        screen: screen,
        on: Map.unmodifiable({
          for (final entry in on.entries)
            entry.key: _freezeTransition(entry.value),
        }),
      ),
    DecisionFlowState(:final branches, :final defaultBranch) =>
      DecisionFlowState(
        branches: List.unmodifiable(branches.map(_freezeBranch)),
        defaultBranch: _freezeBranchTarget(defaultBranch),
      ),
    SubFlowState(
      :final flow,
      :final version,
      :final schemaVersion,
      :final minClient,
      :final contentHash,
      :final input,
      :final onComplete,
      :final defaultBranch,
      :final subFlowUnavailable,
    ) =>
      SubFlowState(
        flow: flow,
        version: version,
        schemaVersion: schemaVersion,
        minClient: minClient,
        contentHash: contentHash,
        input: _freezeValueSourceMap(input),
        onComplete: List.unmodifiable(onComplete.map(_freezeBranch)),
        defaultBranch: _freezeBranchTarget(defaultBranch),
        subFlowUnavailable: subFlowUnavailable == null
            ? null
            : _freezeBranchTarget(subFlowUnavailable),
      ),
    EndFlowState(:final result) => EndFlowState(
        result: _freezeJsonObject(result),
      ),
    UnsupportedFlowState(:final wireKind, :final raw) => UnsupportedFlowState(
        wireKind: wireKind,
        raw: _freezeJsonObject(raw),
      ),
  };
}

FlowTransition _freezeTransition(FlowTransition transition) {
  return switch (transition) {
    GotoFlowTransition(:final target, :final stateWrites) => GotoFlowTransition(
        target,
        stateWrites: _freezeStateWrites(stateWrites),
      ),
    ActionFlowTransition(
      :final action,
      :final resultPredicate,
      :final target,
      :final stateWrites,
    ) =>
      ActionFlowTransition(
        action: action,
        resultPredicate: resultPredicate,
        target: target,
        stateWrites: _freezeStateWrites(stateWrites),
      ),
  };
}

FlowBranch _freezeBranch(FlowBranch branch) {
  return FlowBranch(
    when: _freezeBranchPredicate(branch.when),
    target: branch.target,
    stateWrites: _freezeStateWrites(branch.stateWrites),
  );
}

FlowBranchTarget _freezeBranchTarget(FlowBranchTarget branch) {
  return FlowBranchTarget(
    target: branch.target,
    stateWrites: _freezeStateWrites(branch.stateWrites),
  );
}

FlowBranchPredicate _freezeBranchPredicate(FlowBranchPredicate predicate) {
  return FlowBranchPredicate(
    fields: Map.unmodifiable({
      for (final entry in predicate.fields.entries)
        entry.key: _freezePredicateCondition(entry.value),
    }),
  );
}

FlowPredicateCondition _freezePredicateCondition(
  FlowPredicateCondition condition,
) {
  return switch (condition) {
    EqualsFlowPredicateCondition(:final value) =>
      EqualsFlowPredicateCondition(value: _freezeValueSource(value)),
    NotEqualsFlowPredicateCondition(:final value) =>
      NotEqualsFlowPredicateCondition(value: _freezeValueSource(value)),
    InFlowPredicateCondition(:final values) => InFlowPredicateCondition(
        values: List.unmodifiable(values.map(_freezeValueSource)),
      ),
    GreaterThanFlowPredicateCondition(:final value) =>
      GreaterThanFlowPredicateCondition(value: _freezeValueSource(value)),
    GreaterThanOrEqualsFlowPredicateCondition(:final value) =>
      GreaterThanOrEqualsFlowPredicateCondition(
        value: _freezeValueSource(value),
      ),
    LessThanFlowPredicateCondition(:final value) =>
      LessThanFlowPredicateCondition(value: _freezeValueSource(value)),
    LessThanOrEqualsFlowPredicateCondition(:final value) =>
      LessThanOrEqualsFlowPredicateCondition(value: _freezeValueSource(value)),
    ExistsFlowPredicateCondition(:final exists) =>
      ExistsFlowPredicateCondition(exists: exists),
  };
}

Map<String, FlowStateWrite> _freezeStateWrites(
  Map<String, FlowStateWrite> stateWrites,
) {
  return Map.unmodifiable({
    for (final entry in stateWrites.entries)
      entry.key: _freezeStateWrite(entry.value),
  });
}

FlowStateWrite _freezeStateWrite(FlowStateWrite stateWrite) {
  return FlowStateWrite(
    type: stateWrite.type,
    value: _freezeValueSource(stateWrite.value),
  );
}

Map<String, FlowValueSource> _freezeValueSourceMap(
  Map<String, FlowValueSource> sources,
) {
  return Map.unmodifiable({
    for (final entry in sources.entries)
      entry.key: _freezeValueSource(entry.value),
  });
}

FlowValueSource _freezeValueSource(FlowValueSource source) {
  return switch (source) {
    LiteralFlowValueSource(:final type, :final value) =>
      LiteralFlowValueSource(type: type, value: value),
    StateFlowValueSource(:final key, :final path) => StateFlowValueSource(
        key: key,
        path: List.unmodifiable(path),
      ),
    EventFlowValueSource(:final key, :final path) => EventFlowValueSource(
        key: key,
        path: List.unmodifiable(path),
      ),
    ActionResultFlowValueSource(:final key, :final path) =>
      ActionResultFlowValueSource(
        key: key,
        path: List.unmodifiable(path),
      ),
    SubFlowResultFlowValueSource(:final key, :final path) =>
      SubFlowResultFlowValueSource(
        key: key,
        path: List.unmodifiable(path),
      ),
  };
}

Map<String, Object?> _freezeJsonObject(Map<String, Object?> source) {
  return Map.unmodifiable({
    for (final entry in source.entries)
      entry.key: _freezeJsonValue(entry.value),
  });
}

Object? _freezeJsonValue(Object? value) {
  return switch (value) {
    Map<String, Object?>() => _freezeJsonObject(value),
    List<Object?>() => List<Object?>.unmodifiable(
        value.map(_freezeJsonValue),
      ),
    _ => value,
  };
}

/// Error surfaced when an onboarding flow cannot be resolved or rendered.
///
/// `RestageOnboarding` routes this through its required
/// `FlowUnavailablePolicy`, optional callback, and global flow-unavailable
/// event.
final class FlowUnavailableError implements Exception {
  /// Creates an unavailable-flow error.
  const FlowUnavailableError({
    required this.flowId,
    required this.flowVersion,
    required this.reason,
    required this.message,
  });

  /// Stable onboarding flow identifier.
  final String flowId;

  /// Flow descriptor version.
  final int flowVersion;

  /// Machine-readable reason.
  final String reason;

  /// Human-readable diagnostic message.
  final String message;

  @override
  String toString() {
    return 'FlowUnavailableError('
        'flowId: $flowId, '
        'flowVersion: $flowVersion, '
        'reason: $reason, '
        'message: $message'
        ')';
  }
}

/// Resolves onboarding flows from bundled Flutter assets.
///
/// The default flow delivery path loads
/// `assets/onboarding/flows/<id>.flow.json` and each referenced screen from
/// `assets/onboarding/screens/`. Missing, malformed, incompatible, unsupported,
/// or hash-mismatched artifacts throw [FlowUnavailableError].
final class AssetFlowResolver implements FlowResolver {
  /// Creates an asset-backed flow resolver.
  const AssetFlowResolver({AssetBundle? bundle}) : _bundle = bundle;

  static final Expando<Map<String, ResolvedFlow>> _caches = Expando();

  final AssetBundle? _bundle;

  AssetBundle get _effectiveBundle => _bundle ?? rootBundle;

  Map<String, ResolvedFlow> get _cache => _caches[this] ??= {};

  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) async {
    final artifacts = await loadBundledFlowArtifacts(
      bundle: _effectiveBundle,
      flowJsonPath: 'assets/onboarding/flows/${flow.id}.flow.json',
      screenAssetPathPrefix: 'assets/onboarding/screens',
      flowId: flow.id,
      expectedVersion: flow.version,
      supportedMinClient: flow.minClient,
      buildError: (reason, message, [cause]) {
        return _error(flow, reason, message, cause);
      },
    );
    final resolvedDocument = _freezeDocument(artifacts.document);

    final cacheKey = _cacheKey(
      flow,
      artifacts.documentBytes,
      resolvedDocument,
    );
    final cached = _cache[cacheKey];
    if (cached != null) {
      return cached._withCacheHit();
    }

    final resolved = ResolvedFlow(
      document: resolvedDocument,
      screenBlobs: artifacts.screenBlobs,
      contentHash: artifacts.documentHash,
      cacheHit: false,
    );
    _cache[cacheKey] = resolved;
    return resolved;
  }

  String _cacheKey<R>(
    OnboardingFlowRef<R> flow,
    Uint8List documentBytes,
    FlowDocument document,
  ) {
    final documentHash = FlowContentHash.compute(documentBytes).value;
    final artifactEntries = document.screenArtifacts.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final artifactHashes = artifactEntries
        .map((entry) => '${entry.key}=${entry.value.contentHash.value}')
        .join('|');
    return '${flow.id}\u0000${flow.version}\u0000$documentHash'
        '\u0000$artifactHashes';
  }

  FlowUnavailableError _error<R>(
    OnboardingFlowRef<R> flow,
    String reason,
    String message, [
    Object? cause,
  ]) {
    return FlowUnavailableError(
      flowId: flow.id,
      flowVersion: flow.version,
      reason: reason,
      message: cause == null ? message : '$message Cause: $cause',
    );
  }
}
