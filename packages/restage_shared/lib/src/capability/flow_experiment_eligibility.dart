part of '../../flow_experiment.dart';

/// Revision of the V1 flow-experiment admission predicate.
///
/// This revision is independent from the blob-render gate revision.
const int kFlowExperimentGateLogicRevisionV1 = 1;

/// Mandatory out-of-contract integrity proofs supplied by artifact loaders.
///
/// These booleans are deliberately not V1 JSON fields. A trusted artifact
/// loader must verify the payload frame, every screen blob, and its RFW bytes
/// before asking the pure evaluator for an eligibility decision.
@immutable
final class FlowExperimentArtifactIntegrityV1 {
  /// Creates explicit integrity preconditions with no permissive defaults.
  const FlowExperimentArtifactIntegrityV1({
    required this.payloadIntegrityVerified,
    required this.screenIntegrityVerified,
    required this.rfwIntegrityVerified,
  });

  /// Whether the enclosing surface payload passed its integrity checks.
  final bool payloadIntegrityVerified;

  /// Whether every referenced screen blob matched its exact metadata/hash.
  final bool screenIntegrityVerified;

  /// Whether every referenced screen decoded under the installed RFW runtime.
  final bool rfwIntegrityVerified;

  bool get _allVerified =>
      payloadIntegrityVerified &&
      screenIntegrityVerified &&
      rfwIntegrityVerified;
}

/// One resolver-produced exact flow closure evaluated as a unit.
@immutable
final class FlowExperimentClosureV1 {
  /// Creates an immutable closure snapshot.
  factory FlowExperimentClosureV1({
    required FlowExperimentDocumentContractV1 root,
    required int rootCapability,
    required List<FlowExperimentDocumentContractV1> documents,
    required FlowExperimentArtifactIntegrityV1 integrity,
  }) {
    return FlowExperimentClosureV1._(
      root: root,
      rootCapability: rootCapability,
      documents: List.unmodifiable(documents),
      integrity: integrity,
    );
  }

  const FlowExperimentClosureV1._({
    required this.root,
    required this.rootCapability,
    required this.documents,
    required this.integrity,
  });

  /// The resolved root node. Active candidates may use a newer version.
  final FlowExperimentDocumentContractV1 root;

  /// Requested root descriptor floor retained across active resolution.
  final int rootCapability;

  /// Root plus every exact reachable descendant.
  final List<FlowExperimentDocumentContractV1> documents;

  /// Integrity facts proven outside the V1 JSON grammar.
  final FlowExperimentArtifactIntegrityV1 integrity;
}

/// Complete pure input to the shared V1 eligibility predicate.
@immutable
final class FlowExperimentVerdictInputV1 {
  /// Creates a deep-frozen evaluator input.
  factory FlowExperimentVerdictInputV1({
    required FlowExperimentClosureV1 clientBaselineClosure,
    required FlowExperimentClosureV1 candidateArmClosure,
    required InstalledCapability installedCapability,
    required List<FlowActionBindingFingerprintV1> actionBindings,
    required List<String> installedSignals,
    required Surface surfaceType,
    required FlowDeliveryMode deliveryMode,
    required int flowGateRevision,
  }) {
    return FlowExperimentVerdictInputV1._(
      clientBaselineClosure: clientBaselineClosure,
      candidateArmClosure: candidateArmClosure,
      installedCapability: installedCapability,
      actionBindings: List.unmodifiable(actionBindings),
      installedSignals: List.unmodifiable(installedSignals),
      surfaceType: surfaceType,
      deliveryMode: deliveryMode,
      flowGateRevision: flowGateRevision,
    );
  }

  const FlowExperimentVerdictInputV1._({
    required this.clientBaselineClosure,
    required this.candidateArmClosure,
    required this.installedCapability,
    required this.actionBindings,
    required this.installedSignals,
    required this.surfaceType,
    required this.deliveryMode,
    required this.flowGateRevision,
  });

  /// Exact client-bundled baseline closure.
  final FlowExperimentClosureV1 clientBaselineClosure;

  /// Trusted-resolver candidate closure.
  final FlowExperimentClosureV1 candidateArmClosure;

  /// Installed renderer capability.
  final InstalledCapability installedCapability;

  /// Installed action mount fingerprints.
  final List<FlowActionBindingFingerprintV1> actionBindings;

  /// Installed general-surface signal names.
  final List<String> installedSignals;

  /// Surface category anchored by the mount.
  final Surface surfaceType;

  /// Delivery mode anchored by the mount.
  final FlowDeliveryMode deliveryMode;

  /// Evaluator revision included in verdict identity.
  final int flowGateRevision;
}

/// Total V1 flow-experiment eligibility result.
sealed class FlowExperimentVerdictV1 {
  const FlowExperimentVerdictV1();

  /// Whether the candidate can be assigned and rendered.
  bool get accepted;
}

/// The baseline and candidate are compatible from documents/capabilities alone.
@immutable
final class FlowExperimentAcceptedV1 extends FlowExperimentVerdictV1 {
  /// Creates an accepted decision.
  const FlowExperimentAcceptedV1();

  @override
  bool get accepted => true;
}

/// A fail-closed V1 eligibility decision.
@immutable
final class FlowExperimentRejectedV1 extends FlowExperimentVerdictV1 {
  /// Creates a typed rejection.
  const FlowExperimentRejectedV1({
    required this.reason,
    required this.message,
  });

  /// Stable rejection category.
  final FlowExperimentRejectionReasonV1 reason;

  /// Diagnostic suitable for internal logs.
  final String message;

  @override
  bool get accepted => false;
}

/// Why a V1 flow candidate was ineligible.
enum FlowExperimentRejectionReasonV1 {
  /// The verdict revision is stale or unsupported.
  unsupportedGateRevision,

  /// A mandatory loader-owned integrity proof is absent.
  artifactIntegrityUnverified,

  /// A closure is incomplete, contains extras/cycles, or exceeds depth four.
  closureInvalid,

  /// A FlowDocument or wrapper failed production validation.
  documentInvalid,

  /// Surface, mode, root identity, or retained descriptor floor differs.
  surfaceOrModeMismatch,

  /// A document, screen, or action requires unavailable built-in capability.
  capabilityFloorRaised,

  /// A required custom widget library is absent, unversioned, or too old.
  requiredLibraryUnsatisfied,

  /// A declared action has no compatible installed binding.
  actionBindingUnsatisfied,

  /// A general document declares a signal the host did not install.
  signalUnsatisfied,

  /// Typed delivery changed a client-observable contract surface.
  typedCompatibilityRejected,

  /// Eligibility would depend on unknown live host or sub-flow state.
  liveStateAmbiguous,

  /// The supplied capability snapshot contains duplicate or invalid identities.
  malformedInput,
}

/// Shared pure evaluator for typed and general V1 flow candidates.
abstract final class FlowExperimentEligibilityEvaluatorV1 {
  /// Evaluates [input] without IO and never throws to the caller.
  static FlowExperimentVerdictV1 evaluate(
    FlowExperimentVerdictInputV1 input,
  ) {
    try {
      if (input.flowGateRevision != kFlowExperimentGateLogicRevisionV1) {
        return FlowExperimentRejectedV1(
          reason: FlowExperimentRejectionReasonV1.unsupportedGateRevision,
          message: 'Unsupported flow gate revision '
              '${input.flowGateRevision}.',
        );
      }
      if (!input.clientBaselineClosure.integrity._allVerified ||
          !input.candidateArmClosure.integrity._allVerified) {
        return const FlowExperimentRejectedV1(
          reason: FlowExperimentRejectionReasonV1.artifactIntegrityUnverified,
          message: 'Payload, screen, and RFW integrity must all be verified.',
        );
      }

      final installed =
          _canonicalInstalledCapability(input.installedCapability);
      final actions = _canonicalActionBindings(input.actionBindings);
      final signals = _canonicalSignals(input.installedSignals).toSet();
      final actionMap = <String, FlowActionBindingFingerprintV1>{
        for (final action in actions) action.actionId: action,
      };

      final baseline = _validateEligibilityClosure(
        closure: input.clientBaselineClosure,
        installed: installed,
        actions: actionMap,
        signals: signals,
        expectedSurface: input.surfaceType,
        expectedMode: input.deliveryMode,
      );
      final candidate = _validateEligibilityClosure(
        closure: input.candidateArmClosure,
        installed: installed,
        actions: actionMap,
        signals: signals,
        expectedSurface: input.surfaceType,
        expectedMode: input.deliveryMode,
      );

      if (baseline.root.flowId != candidate.root.flowId ||
          baseline.root.surfaceType != candidate.root.surfaceType ||
          baseline.rootCapability != candidate.rootCapability) {
        return const FlowExperimentRejectedV1(
          reason: FlowExperimentRejectionReasonV1.surfaceOrModeMismatch,
          message: 'Candidate root identity or retained capability differs.',
        );
      }

      _checkHostStatePreservation(
        baseline.root.flowDocument,
        candidate.root.flowDocument,
      );

      switch (input.deliveryMode) {
        case FlowDeliveryMode.typed:
          _checkTypedClosureCompatibility(baseline, candidate);
        case FlowDeliveryMode.general:
          _checkEveryGeneralNode(baseline, label: 'baseline');
          _checkEveryGeneralNode(candidate, label: 'candidate');
      }
      return const FlowExperimentAcceptedV1();
    } on _EligibilityFailure catch (failure) {
      return FlowExperimentRejectedV1(
        reason: failure.reason,
        message: failure.message,
      );
    } on FormatException catch (error) {
      return FlowExperimentRejectedV1(
        reason: FlowExperimentRejectionReasonV1.malformedInput,
        message: 'Malformed evaluator input: ${error.message}',
      );
    } on Object catch (error) {
      return FlowExperimentRejectedV1(
        reason: FlowExperimentRejectionReasonV1.documentInvalid,
        message: 'Flow eligibility evaluation failed closed: $error',
      );
    }
  }
}

_ValidatedClosure _validateEligibilityClosure({
  required FlowExperimentClosureV1 closure,
  required InstalledCapability installed,
  required Map<String, FlowActionBindingFingerprintV1> actions,
  required Set<String> signals,
  required Surface expectedSurface,
  required FlowDeliveryMode expectedMode,
}) {
  if (closure.rootCapability < 1) {
    throw const _EligibilityFailure(
      FlowExperimentRejectionReasonV1.closureInvalid,
      'Root capability must be positive.',
    );
  }
  if (closure.documents.isEmpty) {
    throw const _EligibilityFailure(
      FlowExperimentRejectionReasonV1.closureInvalid,
      'Closure contains no documents.',
    );
  }

  final byIdentity = <String, FlowExperimentDocumentContractV1>{};
  for (final document in closure.documents) {
    final identity = _documentIdentity(document);
    if (byIdentity.containsKey(identity)) {
      throw _EligibilityFailure(
        FlowExperimentRejectionReasonV1.closureInvalid,
        'Duplicate closure document identity $identity.',
      );
    }
    byIdentity[identity] = document;
  }
  final rootIdentity = _documentIdentity(closure.root);
  final canonicalRoot = byIdentity[rootIdentity];
  if (canonicalRoot == null ||
      canonicalRoot.contentHash != closure.root.contentHash) {
    throw const _EligibilityFailure(
      FlowExperimentRejectionReasonV1.closureInvalid,
      'Closure root is not an exact member of its document set.',
    );
  }

  final reached = <String>{};
  _walkEligibilityClosure(
    node: canonicalRoot,
    availableCapability: closure.rootCapability,
    expectedSurface: expectedSurface,
    expectedMode: expectedMode,
    installed: installed,
    actions: actions,
    signals: signals,
    byIdentity: byIdentity,
    reached: reached,
    path: <String>{},
    depth: 0,
  );
  if (reached.length != byIdentity.length) {
    throw const _EligibilityFailure(
      FlowExperimentRejectionReasonV1.closureInvalid,
      'Closure contains unreachable documents.',
    );
  }
  return _ValidatedClosure(
    root: canonicalRoot,
    rootCapability: closure.rootCapability,
    documentsByIdentity: Map.unmodifiable(byIdentity),
  );
}

void _checkTypedClosureCompatibility(
  _ValidatedClosure baseline,
  _ValidatedClosure candidate,
) {
  final candidateToBaseline = <String, String>{};
  final baselineToCandidate = <String, String>{};
  final visitedPairs = <String>{};

  void visit(
    FlowExperimentDocumentContractV1 baselineNode,
    FlowExperimentDocumentContractV1 candidateNode,
    String path,
  ) {
    final baselineIdentity = _documentIdentity(baselineNode);
    final candidateIdentity = _documentIdentity(candidateNode);
    final priorBaseline = candidateToBaseline[candidateIdentity];
    final priorCandidate = baselineToCandidate[baselineIdentity];
    if ((priorBaseline != null && priorBaseline != baselineIdentity) ||
        (priorCandidate != null && priorCandidate != candidateIdentity)) {
      throw _EligibilityFailure(
        FlowExperimentRejectionReasonV1.typedCompatibilityRejected,
        'Typed descendant correspondence is ambiguous at "$path".',
      );
    }
    candidateToBaseline[candidateIdentity] = baselineIdentity;
    baselineToCandidate[baselineIdentity] = candidateIdentity;

    final pairIdentity = '$baselineIdentity\u0001$candidateIdentity';
    if (!visitedPairs.add(pairIdentity)) return;

    final baselineSubFlows = _subFlowStatesByStateId(
      baselineNode.flowDocument,
    );
    final candidateSubFlows = _subFlowStatesByStateId(
      candidateNode.flowDocument,
    );
    final stateIds = <String>{
      ...baselineSubFlows.keys,
      ...candidateSubFlows.keys,
    }.toList()
      ..sort(_compareUnsignedUtf8);
    for (final stateId in stateIds) {
      final baselineState = baselineSubFlows[stateId];
      final candidateState = candidateSubFlows[stateId];
      if (baselineState == null ||
          candidateState == null ||
          baselineState.flow != candidateState.flow ||
          baselineState.version != candidateState.version) {
        throw _EligibilityFailure(
          FlowExperimentRejectionReasonV1.typedCompatibilityRejected,
          'Typed descendant correspondence is missing at "$path.$stateId".',
        );
      }
      final baselineChild = baseline.documentsByIdentity[_documentIdentityParts(
        baselineNode.surfaceType,
        baselineState.flow,
        baselineState.version,
      )];
      final candidateChild =
          candidate.documentsByIdentity[_documentIdentityParts(
        candidateNode.surfaceType,
        candidateState.flow,
        candidateState.version,
      )];
      if (baselineChild == null || candidateChild == null) {
        throw _EligibilityFailure(
          FlowExperimentRejectionReasonV1.typedCompatibilityRejected,
          'Typed descendant correspondence is incomplete at '
          '"$path.$stateId".',
        );
      }
      visit(baselineChild, candidateChild, '$path.$stateId');
    }

    final verdict = FlowActiveRenderGate.evaluate(
      client: baselineNode.flowDocument,
      active: candidateNode.flowDocument,
    );
    if (!verdict.accepted) {
      throw _EligibilityFailure(
        FlowExperimentRejectionReasonV1.typedCompatibilityRejected,
        'Typed compatibility rejected node "${candidateNode.flowId}" at '
        '"$path".',
      );
    }
  }

  visit(baseline.root, candidate.root, r'$root');
  if (candidateToBaseline.length != candidate.documentsByIdentity.length ||
      baselineToCandidate.length != baseline.documentsByIdentity.length) {
    throw const _EligibilityFailure(
      FlowExperimentRejectionReasonV1.typedCompatibilityRejected,
      'Typed closures do not have complete one-to-one descendant '
      'correspondence.',
    );
  }
}

Map<String, SubFlowState> _subFlowStatesByStateId(FlowDocument document) {
  final subFlows = <String, SubFlowState>{};
  for (final entry in document.states.entries) {
    final state = entry.value;
    if (state is SubFlowState) subFlows[entry.key] = state;
  }
  return subFlows;
}

void _checkEveryGeneralNode(
  _ValidatedClosure closure, {
  required String label,
}) {
  for (final node in closure.documentsByIdentity.values) {
    // GeneralFlowRenderGate is a standalone marker-admission check for each
    // resolved node. General mode intentionally has no structural
    // baseline/candidate correspondence, so each node proves its own marker
    // integrity instead of borrowing the root as a synthetic client.
    final verdict = GeneralFlowRenderGate.evaluate(
      client: node.flowDocument,
      active: node.flowDocument,
    );
    if (!verdict.accepted) {
      throw _EligibilityFailure(
        FlowExperimentRejectionReasonV1.documentInvalid,
        'General render gate rejected $label node "${node.flowId}".',
      );
    }
  }
}

void _walkEligibilityClosure({
  required FlowExperimentDocumentContractV1 node,
  required int availableCapability,
  required Surface expectedSurface,
  required FlowDeliveryMode expectedMode,
  required InstalledCapability installed,
  required Map<String, FlowActionBindingFingerprintV1> actions,
  required Set<String> signals,
  required Map<String, FlowExperimentDocumentContractV1> byIdentity,
  required Set<String> reached,
  required Set<String> path,
  required int depth,
}) {
  final identity = _documentIdentity(node);
  if (path.contains(identity)) {
    throw _EligibilityFailure(
      FlowExperimentRejectionReasonV1.closureInvalid,
      'Closure contains a cycle at $identity.',
    );
  }
  _validateDocumentAdmission(
    node: node,
    availableCapability: availableCapability,
    expectedSurface: expectedSurface,
    expectedMode: expectedMode,
    installed: installed,
    actions: actions,
    signals: signals,
  );

  reached.add(identity);
  final nextPath = {...path, identity};
  final document = node.flowDocument;
  for (final state in document.states.values) {
    if (state is! SubFlowState) continue;
    final childIdentity = _documentIdentityParts(
      expectedSurface,
      state.flow,
      state.version,
    );
    if (nextPath.contains(childIdentity)) {
      throw _EligibilityFailure(
        FlowExperimentRejectionReasonV1.closureInvalid,
        'Closure contains an indirect cycle at $childIdentity.',
      );
    }
    if (depth >= _maxFlowExperimentClosureDepth) {
      throw const _EligibilityFailure(
        FlowExperimentRejectionReasonV1.closureInvalid,
        'Closure exceeds maximum sub-flow depth 4.',
      );
    }
    final child = byIdentity[childIdentity];
    if (child == null) {
      throw _EligibilityFailure(
        FlowExperimentRejectionReasonV1.closureInvalid,
        'Missing exact child "${state.flow}".',
      );
    }
    if (child.schemaVersion != state.schemaVersion ||
        child.minClient != state.minClient ||
        child.contentHash != state.contentHash) {
      throw _EligibilityFailure(
        FlowExperimentRejectionReasonV1.closureInvalid,
        'Child "${state.flow}" does not match its exact pinned reference.',
      );
    }
    _checkDefiniteSubFlowInputs(
      parent: document,
      state: state,
      child: child.flowDocument,
    );
    _walkEligibilityClosure(
      node: child,
      availableCapability: state.minClient,
      expectedSurface: expectedSurface,
      expectedMode: expectedMode,
      installed: installed,
      actions: actions,
      signals: signals,
      byIdentity: byIdentity,
      reached: reached,
      path: nextPath,
      depth: depth + 1,
    );
  }
}

void _validateDocumentAdmission({
  required FlowExperimentDocumentContractV1 node,
  required int availableCapability,
  required Surface expectedSurface,
  required FlowDeliveryMode expectedMode,
  required InstalledCapability installed,
  required Map<String, FlowActionBindingFingerprintV1> actions,
  required Set<String> signals,
}) {
  final document = node.flowDocument;
  if (node.surfaceType != expectedSurface ||
      document.deliveryMode != expectedMode) {
    throw const _EligibilityFailure(
      FlowExperimentRejectionReasonV1.surfaceOrModeMismatch,
      'Closure node crosses the anchored surface or delivery mode.',
    );
  }
  if (document.schemaVersion != _flowDocumentSchemaVersion) {
    throw const _EligibilityFailure(
      FlowExperimentRejectionReasonV1.documentInvalid,
      'Unsupported FlowDocument schema version.',
    );
  }
  final issues = FlowDocumentValidation.validate(document);
  if (issues.isNotEmpty) {
    throw _EligibilityFailure(
      FlowExperimentRejectionReasonV1.documentInvalid,
      'FlowDocument validation failed: ${issues.join('; ')}.',
    );
  }
  if (document.minClient > availableCapability ||
      document.minClient > installed.builtInCatalogVersion) {
    throw const _EligibilityFailure(
      FlowExperimentRejectionReasonV1.capabilityFloorRaised,
      'FlowDocument exceeds the retained or installed capability floor.',
    );
  }
  for (final artifact in document.screenArtifacts.values) {
    if (artifact.schemaVersion != _flowDocumentSchemaVersion) {
      throw const _EligibilityFailure(
        FlowExperimentRejectionReasonV1.documentInvalid,
        'Unsupported screen artifact schema version.',
      );
    }
    if (artifact.minClient > availableCapability ||
        artifact.minClient > installed.builtInCatalogVersion) {
      throw const _EligibilityFailure(
        FlowExperimentRejectionReasonV1.capabilityFloorRaised,
        'Screen artifact exceeds the available capability floor.',
      );
    }
  }

  for (final requirement in node.requiredLibraries) {
    InstalledLibrary? installedLibrary;
    for (final library in installed.installedLibraries) {
      if (library.namespace == requirement.namespace) {
        installedLibrary = library;
        break;
      }
    }
    final version = installedLibrary?.version;
    if (version == null || version < requirement.minVersion) {
      throw _EligibilityFailure(
        FlowExperimentRejectionReasonV1.requiredLibraryUnsatisfied,
        'Required library "${requirement.namespace}" is unavailable.',
      );
    }
  }

  for (final entry in document.actions.entries) {
    final expected = entry.value;
    final actual = actions[entry.key];
    if (actual == null ||
        actual.actionName != expected.actionName ||
        actual.contractVersion != expected.contractVersion ||
        actual.argsSchemaHash != expected.argsSchemaHash ||
        actual.resultSchemaHash != expected.resultSchemaHash ||
        actual.minClient < expected.minClient ||
        actual.idempotent != expected.idempotent) {
      throw _EligibilityFailure(
        FlowExperimentRejectionReasonV1.actionBindingUnsatisfied,
        'Installed action binding "${entry.key}" does not satisfy the '
        'document contract.',
      );
    }
  }
  _checkActionResultPredicates(document);

  if (expectedMode == FlowDeliveryMode.general) {
    for (final signal in document.outbound.customEvents.keys) {
      if (!signals.contains(signal)) {
        throw _EligibilityFailure(
          FlowExperimentRejectionReasonV1.signalUnsatisfied,
          'General signal "$signal" is not installed.',
        );
      }
    }
  }
}

void _checkActionResultPredicates(FlowDocument document) {
  for (final state in document.states.values) {
    if (state is! ScreenFlowState) continue;
    for (final transition in state.on.values) {
      if (transition is! ActionFlowTransition) continue;
      final action = document.actions[transition.action];
      if (action == null) continue;
      final compatible = switch (transition.resultPredicate) {
        BoolEqualsActionResultPredicate() =>
          action.resultSchema is FlowBoolActionSchema,
        ObjectBoolFieldEqualsActionResultPredicate(:final field) =>
          _isRequiredBoolField(action.resultSchema, field),
      };
      if (!compatible) {
        throw _EligibilityFailure(
          FlowExperimentRejectionReasonV1.actionBindingUnsatisfied,
          'Action "${transition.action}" has an incompatible result '
          'predicate.',
        );
      }
    }
  }
}

bool _isRequiredBoolField(FlowActionSchema schema, String field) {
  if (schema is! FlowObjectActionSchema) return false;
  final declared = schema.fields[field];
  return declared != null &&
      declared.required &&
      declared.schema is FlowBoolActionSchema;
}

void _checkHostStatePreservation(
  FlowDocument baseline,
  FlowDocument candidate,
) {
  for (final entry in baseline.flowState.entries) {
    final baselineDeclaration = entry.value;
    if (!baselineDeclaration.hostSeedable) continue;
    final candidateDeclaration = candidate.flowState[entry.key];
    if (candidateDeclaration == null ||
        !candidateDeclaration.hostSeedable ||
        candidateDeclaration.type != baselineDeclaration.type) {
      throw _EligibilityFailure(
        FlowExperimentRejectionReasonV1.liveStateAmbiguous,
        'Candidate does not preserve host-seedable state "${entry.key}".',
      );
    }
  }
}

void _checkDefiniteSubFlowInputs({
  required FlowDocument parent,
  required SubFlowState state,
  required FlowDocument child,
}) {
  for (final entry in state.input.entries) {
    final childDeclaration = child.flowState[entry.key];
    if (childDeclaration == null) {
      throw _EligibilityFailure(
        FlowExperimentRejectionReasonV1.closureInvalid,
        'Sub-flow input "${entry.key}" is not declared by the child.',
      );
    }
    switch (entry.value) {
      case LiteralFlowValueSource(:final type, :final value):
        if (type != childDeclaration.type ||
            !_matchesFlowDataType(type, value)) {
          throw _EligibilityFailure(
            FlowExperimentRejectionReasonV1.closureInvalid,
            'Literal sub-flow input "${entry.key}" has the wrong type.',
          );
        }
      case StateFlowValueSource(:final key, :final path):
        final parentDeclaration = parent.flowState[key];
        if (path.isNotEmpty ||
            parentDeclaration == null ||
            parentDeclaration.defaultValue == null ||
            parentDeclaration.type != childDeclaration.type) {
          throw _EligibilityFailure(
            FlowExperimentRejectionReasonV1.liveStateAmbiguous,
            'Sub-flow input "${entry.key}" is not definitely available from '
            'document defaults.',
          );
        }
      default:
        throw _EligibilityFailure(
          FlowExperimentRejectionReasonV1.liveStateAmbiguous,
          'Sub-flow input "${entry.key}" depends on live runtime state.',
        );
    }
  }
}

bool _matchesFlowDataType(FlowDataType type, Object? value) {
  return switch (type) {
    FlowDataType.bool => value is bool,
    FlowDataType.int => value is int,
    FlowDataType.string => value is String,
  };
}

final class _ValidatedClosure {
  const _ValidatedClosure({
    required this.root,
    required this.rootCapability,
    required this.documentsByIdentity,
  });

  final FlowExperimentDocumentContractV1 root;
  final int rootCapability;
  final Map<String, FlowExperimentDocumentContractV1> documentsByIdentity;
}

final class _EligibilityFailure implements Exception {
  const _EligibilityFailure(this.reason, this.message);

  final FlowExperimentRejectionReasonV1 reason;
  final String message;
}
