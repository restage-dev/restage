import 'package:restage_shared/flow_experiment.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import 'flow_experiment_test_support.dart';

void main() {
  group('FlowExperimentEligibilityEvaluator', () {
    test('accepts a valid typed baseline and content-compatible candidate', () {
      final baseline = experimentDocumentContract();
      final candidate = experimentDocumentContract();

      final verdict = evaluate(
        baseline: experimentClosure(root: baseline),
        candidate: experimentClosure(root: candidate),
      );

      expect(verdict, isA<FlowExperimentAccepted>());
    });

    test('accepts a general topology change when all capabilities are present',
        () {
      final baseline = experimentDocumentContract(
        document: experimentDocument(deliveryMode: FlowDeliveryMode.general),
      );
      final candidate = experimentDocumentContract(
        document: experimentDocument(
          version: 2,
          deliveryMode: FlowDeliveryMode.general,
          outbound: const FlowOutboundDeclarations(
            customEvents: {
              'skip': FlowOutboundPayloadDeclaration(),
            },
          ),
        ),
      );

      final verdict = evaluate(
        baseline: experimentClosure(root: baseline),
        candidate: experimentClosure(root: candidate),
        mode: FlowDeliveryMode.general,
        signals: const ['skip'],
      );

      expect(verdict, isA<FlowExperimentAccepted>());
    });

    test('typed mode rejects a contract-surface change', () {
      final baseline = experimentDocumentContract();
      final candidate = experimentDocumentContract(
        document: experimentDocument(
          version: 2,
          outbound: const FlowOutboundDeclarations(
            customEvents: {
              'new_signal': FlowOutboundPayloadDeclaration(),
            },
          ),
        ),
      );

      expect(
        evaluate(
          baseline: experimentClosure(root: baseline),
          candidate: experimentClosure(root: candidate),
        ),
        isA<FlowExperimentRejected>().having(
          (verdict) => verdict.reason,
          'reason',
          FlowExperimentRejectionReason.typedCompatibilityRejected,
        ),
      );
    });

    test('typed mode runs compatibility on every descendant explicitly', () {
      final baselineChild = experimentDocumentContract(
        document: experimentDocument(flow: 'child'),
      );
      final candidateChild = experimentDocumentContract(
        document: experimentDocument(
          flow: 'child',
          outbound: const FlowOutboundDeclarations(
            customEvents: {
              'new_signal': FlowOutboundPayloadDeclaration(),
            },
          ),
        ),
      );
      final baselineRoot = _parentContractForChild(baselineChild);
      final candidateRoot = _parentContractForChild(candidateChild);

      final verdict = evaluate(
        baseline: experimentClosure(
          root: baselineRoot,
          documents: [baselineRoot, baselineChild],
        ),
        candidate: experimentClosure(
          root: candidateRoot,
          documents: [candidateRoot, candidateChild],
        ),
      );

      expect(
        verdict,
        isA<FlowExperimentRejected>()
            .having(
              (value) => value.reason,
              'reason',
              FlowExperimentRejectionReason.typedCompatibilityRejected,
            )
            .having((value) => value.message, 'message', contains('child')),
      );
    });

    test('typed mode rejects a missing descendant correspondence', () {
      final baselineChild = experimentDocumentContract(
        document: experimentDocument(flow: 'baseline_child'),
      );
      final candidateChild = experimentDocumentContract(
        document: experimentDocument(flow: 'candidate_child'),
      );
      final baselineRoot = _parentContractForChild(baselineChild);
      final candidateRoot = _parentContractForChild(candidateChild);

      final verdict = evaluate(
        baseline: experimentClosure(
          root: baselineRoot,
          documents: [baselineRoot, baselineChild],
        ),
        candidate: experimentClosure(
          root: candidateRoot,
          documents: [candidateRoot, candidateChild],
        ),
      );

      expect(
        verdict,
        isA<FlowExperimentRejected>().having(
          (value) => value.reason,
          'reason',
          FlowExperimentRejectionReason.typedCompatibilityRejected,
        ),
      );
    });

    test('requires payload, screen, and RFW integrity preconditions', () {
      final document = experimentDocumentContract();
      const failures = [
        FlowExperimentArtifactIntegrity(
          payloadIntegrityVerified: false,
          screenIntegrityVerified: true,
          rfwIntegrityVerified: true,
        ),
        FlowExperimentArtifactIntegrity(
          payloadIntegrityVerified: true,
          screenIntegrityVerified: false,
          rfwIntegrityVerified: true,
        ),
        FlowExperimentArtifactIntegrity(
          payloadIntegrityVerified: true,
          screenIntegrityVerified: true,
          rfwIntegrityVerified: false,
        ),
      ];

      for (final integrity in failures) {
        final verdict = evaluate(
          baseline: experimentClosure(root: document),
          candidate: experimentClosure(
            root: document,
            integrity: integrity,
          ),
        );
        expect(
          verdict,
          isA<FlowExperimentRejected>().having(
            (value) => value.reason,
            'reason',
            FlowExperimentRejectionReason.artifactIntegrityUnverified,
          ),
        );
      }
    });

    test('checks required libraries on every closure node', () {
      final child = experimentDocumentContract(
        document: experimentDocument(flow: 'child'),
        requiredLibraries: const [
          LibraryRequirement(namespace: 'acme.widgets', minVersion: 2),
        ],
      );
      final root = _parentContractForChild(child);
      final closure = experimentClosure(
        root: root,
        documents: [root, child],
      );

      final missing = evaluate(
        baseline: closure,
        candidate: closure,
      );
      final installed = evaluate(
        baseline: closure,
        candidate: closure,
        capability: InstalledCapability(
          builtInCatalogVersion: 5,
          installedLibraries: const [
            InstalledLibrary(namespace: 'acme.widgets', version: 2),
          ],
        ),
      );

      expect(
        missing,
        isA<FlowExperimentRejected>().having(
          (verdict) => verdict.reason,
          'reason',
          FlowExperimentRejectionReason.requiredLibraryUnsatisfied,
        ),
      );
      expect(installed, isA<FlowExperimentAccepted>());
    });

    test('checks full action fingerprint and supported minimum', () {
      final action = experimentAction(minClient: 2);
      final document = experimentDocumentContract(
        document: experimentDocument(
          actions: {'request_notifications': action},
        ),
      );

      final exact = evaluate(
        baseline: experimentClosure(root: document),
        candidate: experimentClosure(root: document),
        actions: [experimentBinding(minClient: 3)],
      );
      final wrongName = evaluate(
        baseline: experimentClosure(root: document),
        candidate: experimentClosure(root: document),
        actions: [
          experimentBinding(
            actionName: 'different_action',
            minClient: 3,
          ),
        ],
      );
      final matching = experimentBinding(minClient: 3);
      final mismatches = [
        FlowActionBindingFingerprint(
          actionId: matching.actionId,
          actionName: matching.actionName,
          contractVersion: 2,
          argsSchemaHash: matching.argsSchemaHash,
          resultSchemaHash: matching.resultSchemaHash,
          minClient: matching.minClient,
          idempotent: matching.idempotent,
        ),
        FlowActionBindingFingerprint(
          actionId: matching.actionId,
          actionName: matching.actionName,
          contractVersion: matching.contractVersion,
          argsSchemaHash: FlowContentHash.compute(const [1]),
          resultSchemaHash: matching.resultSchemaHash,
          minClient: matching.minClient,
          idempotent: matching.idempotent,
        ),
        FlowActionBindingFingerprint(
          actionId: matching.actionId,
          actionName: matching.actionName,
          contractVersion: matching.contractVersion,
          argsSchemaHash: matching.argsSchemaHash,
          resultSchemaHash: FlowContentHash.compute(const [2]),
          minClient: matching.minClient,
          idempotent: matching.idempotent,
        ),
        FlowActionBindingFingerprint(
          actionId: matching.actionId,
          actionName: matching.actionName,
          contractVersion: matching.contractVersion,
          argsSchemaHash: matching.argsSchemaHash,
          resultSchemaHash: matching.resultSchemaHash,
          minClient: 1,
          idempotent: matching.idempotent,
        ),
        FlowActionBindingFingerprint(
          actionId: matching.actionId,
          actionName: matching.actionName,
          contractVersion: matching.contractVersion,
          argsSchemaHash: matching.argsSchemaHash,
          resultSchemaHash: matching.resultSchemaHash,
          minClient: matching.minClient,
          idempotent: true,
        ),
      ];

      expect(exact, isA<FlowExperimentAccepted>());
      expect(
        wrongName,
        isA<FlowExperimentRejected>().having(
          (verdict) => verdict.reason,
          'reason',
          FlowExperimentRejectionReason.actionBindingUnsatisfied,
        ),
      );
      for (final mismatch in mismatches) {
        expect(
          evaluate(
            baseline: experimentClosure(root: document),
            candidate: experimentClosure(root: document),
            actions: [mismatch],
          ),
          isA<FlowExperimentRejected>().having(
            (verdict) => verdict.reason,
            'reason',
            FlowExperimentRejectionReason.actionBindingUnsatisfied,
          ),
        );
      }
    });

    test('checks installed signals only for general surfaces', () {
      final child = experimentDocumentContract(
        document: experimentDocument(
          flow: 'child',
          deliveryMode: FlowDeliveryMode.general,
          outbound: const FlowOutboundDeclarations(
            customEvents: {
              'skip': FlowOutboundPayloadDeclaration(),
            },
          ),
        ),
      );
      final root = _parentContractForChild(
        child,
        mode: FlowDeliveryMode.general,
      );
      final closure = experimentClosure(
        root: root,
        documents: [root, child],
      );

      final verdict = evaluate(
        baseline: closure,
        candidate: closure,
        mode: FlowDeliveryMode.general,
      );

      expect(
        verdict,
        isA<FlowExperimentRejected>().having(
          (value) => value.reason,
          'reason',
          FlowExperimentRejectionReason.signalUnsatisfied,
        ),
      );
    });

    test('rejects an action result predicate incompatible with its schema', () {
      const action = FlowActionContract(
        actionName: 'request_notifications',
        contractVersion: 1,
        argsSchema: FlowActionSchema.object({}),
        resultSchema: FlowActionSchema.object({}),
        minClient: 1,
        idempotent: false,
      );
      final document = experimentDocumentContract(
        document: _screenActionDocument(action),
      );
      final binding = FlowActionBindingFingerprint(
        actionId: 'request_notifications',
        actionName: action.actionName,
        contractVersion: action.contractVersion,
        argsSchemaHash: action.argsSchemaHash,
        resultSchemaHash: action.resultSchemaHash,
        minClient: action.minClient,
        idempotent: action.idempotent,
      );

      final verdict = evaluate(
        baseline: experimentClosure(root: document),
        candidate: experimentClosure(root: document),
        actions: [binding],
      );

      expect(
        verdict,
        isA<FlowExperimentRejected>().having(
          (value) => value.reason,
          'reason',
          FlowExperimentRejectionReason.actionBindingUnsatisfied,
        ),
      );
    });

    test('checks retained and installed built-in capability floors', () {
      final document = experimentDocumentContract(
        document: experimentDocument(minClient: 6),
      );

      final verdict = evaluate(
        baseline: experimentClosure(root: document, rootCapability: 5),
        candidate: experimentClosure(root: document, rootCapability: 5),
        capability: InstalledCapability(
          builtInCatalogVersion: 5,
          installedLibraries: const [],
        ),
      );

      expect(
        verdict,
        isA<FlowExperimentRejected>().having(
          (value) => value.reason,
          'reason',
          FlowExperimentRejectionReason.capabilityFloorRaised,
        ),
      );
    });

    test('general mode admits a new all-general descendant closure', () {
      final baselineRoot = experimentDocumentContract(
        document: experimentDocument(
          deliveryMode: FlowDeliveryMode.general,
        ),
      );
      final candidateChild = experimentDocumentContract(
        document: experimentDocument(
          flow: 'candidate_child',
          deliveryMode: FlowDeliveryMode.general,
        ),
      );
      final candidateRoot = _parentContractForChild(
        candidateChild,
        mode: FlowDeliveryMode.general,
        version: 2,
      );

      final verdict = evaluate(
        baseline: experimentClosure(root: baselineRoot),
        candidate: experimentClosure(
          root: candidateRoot,
          documents: [candidateRoot, candidateChild],
        ),
        mode: FlowDeliveryMode.general,
      );

      expect(verdict, isA<FlowExperimentAccepted>());
    });

    test('general mode rejects a typed descendant', () {
      final baselineRoot = experimentDocumentContract(
        document: experimentDocument(
          deliveryMode: FlowDeliveryMode.general,
        ),
      );
      final typedChild = experimentDocumentContract(
        document: experimentDocument(flow: 'typed_child'),
      );
      final candidateRoot = _parentContractForChild(
        typedChild,
        mode: FlowDeliveryMode.general,
        version: 2,
      );

      final verdict = evaluate(
        baseline: experimentClosure(root: baselineRoot),
        candidate: experimentClosure(
          root: candidateRoot,
          documents: [candidateRoot, typedChild],
        ),
        mode: FlowDeliveryMode.general,
      );

      expect(
        verdict,
        isA<FlowExperimentRejected>().having(
          (value) => value.reason,
          'reason',
          FlowExperimentRejectionReason.surfaceOrModeMismatch,
        ),
      );
    });

    test('preserves every possibly live host-seedable declaration', () {
      final baseline = experimentDocumentContract(
        document: experimentDocument(
          deliveryMode: FlowDeliveryMode.general,
          flowState: const {
            'country': FlowStateDeclaration(
              type: FlowDataType.string,
              classification: FlowStateClassification.internal,
              hostSeedable: true,
            ),
          },
        ),
      );
      final candidate = experimentDocumentContract(
        document: experimentDocument(
          version: 2,
          deliveryMode: FlowDeliveryMode.general,
        ),
      );

      final verdict = evaluate(
        baseline: experimentClosure(root: baseline),
        candidate: experimentClosure(root: candidate),
        mode: FlowDeliveryMode.general,
      );

      expect(
        verdict,
        isA<FlowExperimentRejected>().having(
          (value) => value.reason,
          'reason',
          FlowExperimentRejectionReason.liveStateAmbiguous,
        ),
      );
    });

    test('rejects subflow state input not definitely available from defaults',
        () {
      final childDocument = experimentDocument(
        flow: 'profile',
        deliveryMode: FlowDeliveryMode.general,
        flowState: const {
          'country': FlowStateDeclaration(
            type: FlowDataType.string,
            classification: FlowStateClassification.internal,
          ),
        },
      );
      final child = experimentDocumentContract(document: childDocument);
      final parentDocument = experimentDocument(
        deliveryMode: FlowDeliveryMode.general,
        flowState: const {
          'country': FlowStateDeclaration(
            type: FlowDataType.string,
            classification: FlowStateClassification.internal,
          ),
        },
        states: {
          'profile': SubFlowState(
            flow: child.flowId,
            version: child.version,
            schemaVersion: child.schemaVersion,
            minClient: child.minClient,
            contentHash: child.contentHash,
            input: const {
              'country': StateFlowValueSource(key: 'country'),
            },
            onComplete: const [],
            defaultBranch: const FlowBranchTarget(target: 'done'),
          ),
          'done': const EndFlowState(result: {'completed': true}),
        },
      );
      final parent = experimentDocumentContract(document: parentDocument);

      final verdict = evaluate(
        baseline: experimentClosure(
          root: parent,
          documents: [parent, child],
        ),
        candidate: experimentClosure(
          root: parent,
          documents: [parent, child],
        ),
        mode: FlowDeliveryMode.general,
      );

      expect(
        verdict,
        isA<FlowExperimentRejected>().having(
          (value) => value.reason,
          'reason',
          FlowExperimentRejectionReason.liveStateAmbiguous,
        ),
      );
    });

    test('accepts definitely available literal subflow input', () {
      final childDocument = experimentDocument(
        flow: 'profile',
        flowState: const {
          'country': FlowStateDeclaration(
            type: FlowDataType.string,
            classification: FlowStateClassification.internal,
          ),
        },
      );
      final child = experimentDocumentContract(document: childDocument);
      final parent = experimentDocumentContract(
        document: experimentDocument(
          states: {
            'profile': SubFlowState(
              flow: child.flowId,
              version: child.version,
              schemaVersion: child.schemaVersion,
              minClient: child.minClient,
              contentHash: child.contentHash,
              input: const {
                'country': LiteralFlowValueSource(
                  type: FlowDataType.string,
                  value: 'US',
                ),
              },
              onComplete: const [],
              defaultBranch: const FlowBranchTarget(target: 'done'),
            ),
            'done': const EndFlowState(result: {'completed': true}),
          },
        ),
      );

      final verdict = evaluate(
        baseline: experimentClosure(
          root: parent,
          documents: [parent, child],
        ),
        candidate: experimentClosure(
          root: parent,
          documents: [parent, child],
        ),
      );

      expect(verdict, isA<FlowExperimentAccepted>());
    });

    test('rejects missing, extra, cyclic, and over-depth closure nodes', () {
      final child = experimentDocumentContract(
        document: experimentDocument(flow: 'child'),
      );
      final parent = experimentDocumentContract(
        document: experimentDocument(
          states: {
            'child': SubFlowState(
              flow: child.flowId,
              version: child.version,
              schemaVersion: child.schemaVersion,
              minClient: child.minClient,
              contentHash: child.contentHash,
              input: const {},
              onComplete: const [],
              defaultBranch: const FlowBranchTarget(target: 'done'),
            ),
            'done': const EndFlowState(result: {'completed': true}),
          },
        ),
      );

      final missing = evaluate(
        baseline: experimentClosure(root: parent, documents: [parent, child]),
        candidate: experimentClosure(root: parent),
      );
      final extra = evaluate(
        baseline: experimentClosure(root: child),
        candidate: experimentClosure(root: child, documents: [child, parent]),
      );
      final cycleB = experimentDocumentContract(
        document: _subFlowParent(
          flow: 'cycle_b',
          childFlow: 'cycle_a',
          childHash: _placeholderHash,
        ),
      );
      final cycleA = experimentDocumentContract(
        document: _subFlowParent(
          flow: 'cycle_a',
          childFlow: cycleB.flowId,
          childHash: cycleB.contentHash,
        ),
      );
      final cyclic = evaluate(
        baseline: experimentClosure(root: child),
        candidate: experimentClosure(
          root: cycleA,
          documents: [cycleA, cycleB],
        ),
      );
      final deep = _deepClosure();
      final overDepth = evaluate(
        baseline: experimentClosure(root: child),
        candidate: deep,
      );

      for (final verdict in [missing, extra, cyclic, overDepth]) {
        expect(
          verdict,
          isA<FlowExperimentRejected>().having(
            (value) => value.reason,
            'reason',
            FlowExperimentRejectionReason.closureInvalid,
          ),
        );
      }
    });

    test('is total and fails closed on a stale gate revision', () {
      final document = experimentDocumentContract();
      final verdict = FlowExperimentEligibilityEvaluator.evaluate(
        FlowExperimentVerdictInput(
          clientBaselineClosure: experimentClosure(root: document),
          candidateArmClosure: experimentClosure(root: document),
          installedCapability: InstalledCapability(
            builtInCatalogVersion: 5,
            installedLibraries: const [],
          ),
          actionBindings: const [],
          installedSignals: const [],
          surfaceType: Surface.onboarding,
          deliveryMode: FlowDeliveryMode.typed,
          flowGateRevision: 999,
        ),
      );

      expect(
        verdict,
        isA<FlowExperimentRejected>().having(
          (value) => value.reason,
          'reason',
          FlowExperimentRejectionReason.unsupportedGateRevision,
        ),
      );
    });
  });
}

FlowExperimentVerdict evaluate({
  required FlowExperimentClosure baseline,
  required FlowExperimentClosure candidate,
  InstalledCapability? capability,
  List<FlowActionBindingFingerprint> actions = const [],
  List<String> signals = const [],
  FlowDeliveryMode mode = FlowDeliveryMode.typed,
}) {
  return FlowExperimentEligibilityEvaluator.evaluate(
    FlowExperimentVerdictInput(
      clientBaselineClosure: baseline,
      candidateArmClosure: candidate,
      installedCapability: capability ??
          InstalledCapability(
            builtInCatalogVersion: 5,
            installedLibraries: const [],
          ),
      actionBindings: actions,
      installedSignals: signals,
      surfaceType: Surface.onboarding,
      deliveryMode: mode,
      flowGateRevision: kFlowExperimentGateLogicRevisionV1,
    ),
  );
}

final FlowContentHash _placeholderHash = FlowContentHash.parse(
  'sha256:${List.filled(64, '0').join()}',
);

FlowDocument _subFlowParent({
  required String flow,
  required String childFlow,
  required FlowContentHash childHash,
}) {
  return experimentDocument(
    flow: flow,
    states: {
      'child': SubFlowState(
        flow: childFlow,
        version: 1,
        schemaVersion: 1,
        minClient: 3,
        contentHash: childHash,
        input: const {},
        onComplete: const [],
        defaultBranch: const FlowBranchTarget(target: 'done'),
      ),
      'done': const EndFlowState(result: {'completed': true}),
    },
  );
}

FlowExperimentDocumentContract _parentContractForChild(
  FlowExperimentDocumentContract child, {
  FlowDeliveryMode mode = FlowDeliveryMode.typed,
  int version = 1,
}) {
  return experimentDocumentContract(
    document: experimentDocument(
      version: version,
      deliveryMode: mode,
      states: {
        'child': SubFlowState(
          flow: child.flowId,
          version: child.version,
          schemaVersion: child.schemaVersion,
          minClient: child.minClient,
          contentHash: child.contentHash,
          input: const {},
          onComplete: const [],
          defaultBranch: const FlowBranchTarget(target: 'done'),
        ),
        'done': const EndFlowState(result: {'completed': true}),
      },
    ),
  );
}

FlowExperimentClosure _deepClosure() {
  var child = experimentDocumentContract(
    document: experimentDocument(flow: 'depth_5'),
  );
  final documents = <FlowExperimentDocumentContract>[child];
  for (var depth = 4; depth >= 0; depth -= 1) {
    child = experimentDocumentContract(
      document: _subFlowParent(
        flow: 'depth_$depth',
        childFlow: child.flowId,
        childHash: child.contentHash,
      ),
    );
    documents.add(child);
  }
  return experimentClosure(root: child, documents: documents);
}

FlowDocument _screenActionDocument(FlowActionContract action) {
  return FlowDocument(
    flow: 'first_run',
    version: 1,
    schemaVersion: 1,
    minClient: 3,
    initial: 'screen',
    actions: {'request_notifications': action},
    screenArtifacts: {
      'screen': ScreenArtifact(
        path: 'screen.rfw',
        version: 1,
        schemaVersion: 1,
        minClient: 1,
        contentHash: FlowContentHash.compute(const [1, 2, 3]),
      ),
    },
    states: const {
      'screen': ScreenFlowState(
        screen: 'screen',
        on: {
          'next': ActionFlowTransition(
            action: 'request_notifications',
            resultPredicate: BoolEqualsActionResultPredicate(value: true),
            target: 'done',
          ),
        },
      ),
      'done': EndFlowState(result: {'completed': true}),
    },
  );
}
