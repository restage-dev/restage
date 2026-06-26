import 'dart:convert';

import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  group('FlowDocumentCompatibility', () {
    test('reordered semantic content is free', () {
      expect(
        FlowDocumentCompatibility.classify(
          from: _document(),
          to: _document(reorderStates: true),
        ),
        FlowCompatibilityClassification.free,
      );
    });

    test('adding an unreachable state is invalid before classification', () {
      expect(
        () => FlowDocumentCompatibility.diff(
          from: _document(),
          to: _document(
            extraStates: {
              'orphan': const EndFlowState(result: {'completed': true}),
            },
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('adding a reachable transition and state is additive', () {
      final report = FlowDocumentCompatibility.diff(
        from: _document(),
        to: _document(
          welcomeTransitions: {
            'next': const FlowTransition.goto('done'),
            'learnMore': const FlowTransition.goto('info'),
          },
          extraArtifacts: {'info': _artifact('info.rfw')},
          extraStates: {
            'info': const ScreenFlowState(
              screen: 'info',
              on: {'next': FlowTransition.goto('done')},
            ),
          },
        ),
      );

      expect(report.classification, FlowCompatibilityClassification.additive);
      expect(
        report.changes.map((change) => change.code),
        contains('stateAdded'),
      );
      expect(
        report.changes.map((change) => change.code),
        contains('transitionAdded'),
      );
    });

    test('retargeting an old transition through an equivalent path forwards',
        () {
      final report = FlowDocumentCompatibility.diff(
        from: _document(),
        to: _document(
          welcomeTransitions: {
            'next': const FlowTransition.goto('ready'),
          },
          extraArtifacts: {'ready': _artifact('ready.rfw')},
          extraStates: {
            'ready': const ScreenFlowState(
              screen: 'ready',
              on: {'finish': FlowTransition.goto('done')},
            ),
          },
        ),
      );

      expect(report.classification, FlowCompatibilityClassification.forwarding);
      expect(
        report.changes.map((change) => change.code),
        contains('transitionRetargeted'),
      );
    });

    test('retargeting an old transition to an incompatible terminal breaks',
        () {
      final report = FlowDocumentCompatibility.diff(
        from: _document(),
        to: _document(
          states: {
            'welcome': const ScreenFlowState(
              screen: 'welcome',
              on: {'next': FlowTransition.goto('failed')},
            ),
            'failed': const EndFlowState(result: {'failed': true}),
          },
        ),
      );

      expect(report.classification, FlowCompatibilityClassification.breaking);
    });

    test('removing reachable transitions is breaking', () {
      expect(
        FlowDocumentCompatibility.classify(
          from: _document(),
          to: _document(
            welcomeTransitions: const {'skip': FlowTransition.goto('done')},
          ),
        ),
        FlowCompatibilityClassification.breaking,
      );
    });

    test('flow-state changes classify by existing key compatibility', () {
      expect(
        FlowDocumentCompatibility.classify(
          from: _document(flowState: _flowState()),
          to: _document(
            flowState: {
              ..._flowState(),
              'count': const FlowStateDeclaration(
                type: FlowDataType.int,
                classification: FlowStateClassification.internal,
                defaultValue: 0,
              ),
            },
          ),
        ),
        FlowCompatibilityClassification.additive,
      );
      expect(
        FlowDocumentCompatibility.classify(
          from: _document(),
          to: _document(
            flowState: const {
              'flag': FlowStateDeclaration(
                type: FlowDataType.bool,
                classification: FlowStateClassification.internal,
              ),
            },
          ),
        ),
        FlowCompatibilityClassification.breaking,
      );
      expect(
        FlowDocumentCompatibility.classify(
          from: _document(flowState: _flowState()),
          to: _document(),
        ),
        FlowCompatibilityClassification.breaking,
      );
    });

    test('host-seedable flips classify by direction', () {
      const seedable = {
        'completed': FlowStateDeclaration(
          type: FlowDataType.bool,
          classification: FlowStateClassification.exportable,
          defaultValue: false,
          hostSeedable: true,
        ),
      };
      const nonSeedable = {
        'completed': FlowStateDeclaration(
          type: FlowDataType.bool,
          classification: FlowStateClassification.exportable,
          defaultValue: false,
        ),
      };

      // false -> true: gaining seedability is a compatible addition; an old
      // host that never seeds is unaffected.
      final added = FlowDocumentCompatibility.diff(
        from: _document(flowState: nonSeedable),
        to: _document(flowState: seedable),
      );
      expect(added.classification, FlowCompatibilityClassification.additive);
      expect(
        added.changes.map((change) => change.code),
        contains('flowStateSeedabilityChanged'),
      );

      // true -> false: removing seedability rejects an existing host seed
      // (fail-closed) -> breaking. The asymmetry must not collapse.
      final removed = FlowDocumentCompatibility.diff(
        from: _document(flowState: seedable),
        to: _document(flowState: nonSeedable),
      );
      expect(removed.classification, FlowCompatibilityClassification.breaking);
      expect(
        removed.changes.map((change) => change.code),
        contains('flowStateSeedabilityChanged'),
      );
    });

    test('outbound declarations classify old decoder compatibility', () {
      const outbound = FlowOutboundDeclarations(
        terminalResult: FlowOutboundPayloadDeclaration(
          fields: {
            'completed': FlowOutboundField(
              type: FlowDataType.bool,
              ref: StateFlowOutboundRef(key: 'completed'),
            ),
          },
        ),
      );

      expect(
        FlowDocumentCompatibility.classify(
          from: _document(flowState: _flowState(), outbound: outbound),
          to: _document(flowState: _flowState()),
        ),
        FlowCompatibilityClassification.breaking,
      );
      expect(
        FlowDocumentCompatibility.classify(
          from: _document(flowState: _flowState()),
          to: _document(flowState: _flowState(), outbound: outbound),
        ),
        FlowCompatibilityClassification.additive,
      );
    });

    test('legacy terminal passthrough changes are breaking', () {
      final legacyJson = _documentJson()
        ..remove('flowState')
        ..remove('outbound');
      final explicitDefaultDenyJson = _documentJson()
        ..remove('flowState')
        ..['outbound'] = <String, Object?>{};
      final from = FlowDocumentCodec.decodeJson(jsonEncode(legacyJson));
      final to = FlowDocumentCodec.decodeJson(
        jsonEncode(explicitDefaultDenyJson),
      );

      final report = FlowDocumentCompatibility.diff(from: from, to: to);

      expect(report.classification, FlowCompatibilityClassification.breaking);
      expect(
        report.changes.map((change) => change.code),
        contains('legacyTerminalResultPassthroughChanged'),
      );
    });

    test('adding a decision branch that can intercept default is breaking', () {
      expect(
        FlowDocumentCompatibility.classify(
          from: _document(
            initial: 'branch',
            flowState: _flowState(),
            states: const {
              'branch': DecisionFlowState(
                branches: [],
                defaultBranch: FlowBranchTarget(target: 'done'),
              ),
              'done': EndFlowState(result: {'completed': true}),
            },
          ),
          to: _document(
            initial: 'branch',
            flowState: _flowState(),
            states: const {
              'branch': DecisionFlowState(
                branches: [
                  FlowBranch(
                    when: FlowBranchPredicate(
                      fields: {
                        'completed': EqualsFlowPredicateCondition(
                          value: LiteralFlowValueSource(
                            type: FlowDataType.bool,
                            value: true,
                          ),
                        ),
                      },
                    ),
                    target: 'failed',
                  ),
                ],
                defaultBranch: FlowBranchTarget(target: 'done'),
              ),
              'done': EndFlowState(result: {'completed': true}),
              'failed': EndFlowState(result: {'failed': true}),
            },
          ),
        ),
        FlowCompatibilityClassification.breaking,
      );
    });

    test('sub-flow unavailable branch changes are breaking', () {
      final childHash = FlowContentHash.parse(_hash);
      final before = _document(
        initial: 'profile',
        states: {
          'profile': SubFlowState(
            flow: 'profile_child',
            version: 1,
            schemaVersion: 1,
            minClient: 3,
            contentHash: childHash,
            input: const {},
            onComplete: const [],
            defaultBranch: const FlowBranchTarget(target: 'done'),
            subFlowUnavailable: const FlowBranchTarget(target: 'fallback'),
          ),
          'fallback': const EndFlowState(result: {'completed': false}),
          'done': const EndFlowState(result: {'completed': true}),
        },
      );
      final after = _document(
        initial: 'profile',
        states: {
          'profile': SubFlowState(
            flow: 'profile_child',
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

      final report = FlowDocumentCompatibility.diff(from: before, to: after);

      expect(report.classification, FlowCompatibilityClassification.breaking);
      expect(
        report.changes.map((change) => change.code),
        contains('subFlowUnavailableRemoved'),
      );
    });

    test('terminal result fields classify by old decoder compatibility', () {
      expect(
        FlowDocumentCompatibility.classify(
          from: _document(),
          to: _document(
            doneResult: const {
              'completed': true,
              'plan': 'pro',
            },
          ),
        ),
        FlowCompatibilityClassification.additive,
      );
      expect(
        FlowDocumentCompatibility.classify(
          from: _document(
            doneResult: const {
              'completed': true,
              'plan': 'pro',
            },
          ),
          to: _document(),
        ),
        FlowCompatibilityClassification.breaking,
      );
    });

    test('changing initial state is breaking', () {
      expect(
        FlowDocumentCompatibility.classify(
          from: _document(),
          to: _document(
            initial: 'done',
            states: const {
              'done': EndFlowState(result: {'completed': true}),
            },
          ),
        ),
        FlowCompatibilityClassification.breaking,
      );
    });

    test('raising schemaVersion or minClient is forwarding', () {
      expect(
        FlowDocumentCompatibility.classify(
          from: _document(),
          to: _document(schemaVersion: 2),
        ),
        FlowCompatibilityClassification.forwarding,
      );
      expect(
        FlowDocumentCompatibility.classify(
          from: _document(),
          to: _document(minClient: 4),
        ),
        FlowCompatibilityClassification.forwarding,
      );
    });

    test('screen artifact changes are reported', () {
      final report = FlowDocumentCompatibility.diff(
        from: _document(),
        to: _document(
          artifacts: {
            'welcome': _artifact('welcome_v2.rfw'),
          },
        ),
      );

      expect(report.classification, FlowCompatibilityClassification.additive);
      expect(
        report.changes.map((change) => change.code),
        contains('screenArtifactChanged'),
      );
    });
  });

  group('FlowDocumentValidation graph rules', () {
    test('rejects screenless graph cycles', () {
      final document = _document(
        initial: 'branchA',
        states: {
          'branchA': const DecisionFlowState(
            branches: [],
            defaultBranch: FlowBranchTarget(target: 'branchB'),
          ),
          'branchB': const DecisionFlowState(
            branches: [],
            defaultBranch: FlowBranchTarget(target: 'branchA'),
          ),
          'done': const EndFlowState(result: {'completed': true}),
        },
      );

      expect(
        FlowDocumentValidation.validate(document),
        _containsIssueCode('screenlessCycle'),
      );
    });

    test('rejects writes to undeclared or mismatched flow-state keys', () {
      final document = _document(
        flowState: _flowState(),
        welcomeTransitions: {
          'next': const GotoFlowTransition(
            'done',
            stateWrites: {
              'missing': FlowStateWrite(
                type: FlowDataType.bool,
                value: LiteralFlowValueSource(
                  type: FlowDataType.bool,
                  value: true,
                ),
              ),
              'completed': FlowStateWrite(
                type: FlowDataType.string,
                value: LiteralFlowValueSource(
                  type: FlowDataType.string,
                  value: 'yes',
                ),
              ),
            },
          ),
        },
      );

      final issues = FlowDocumentValidation.validate(document);

      expect(issues, _containsIssueCode('missingFlowStateDeclaration'));
      expect(issues, _containsIssueCode('stateWriteTypeMismatch'));
    });

    test('rejects decision predicate fields not declared in flow state', () {
      final document = _document(
        initial: 'branch',
        flowState: _flowState(),
        states: {
          'branch': const DecisionFlowState(
            branches: [
              FlowBranch(
                when: FlowBranchPredicate(
                  fields: {
                    'missing': EqualsFlowPredicateCondition(
                      value: LiteralFlowValueSource(
                        type: FlowDataType.bool,
                        value: true,
                      ),
                    ),
                  },
                ),
                target: 'done',
              ),
            ],
            defaultBranch: FlowBranchTarget(target: 'done'),
          ),
          'done': const EndFlowState(result: {'completed': true}),
        },
      );

      expect(
        FlowDocumentValidation.validate(document),
        _containsIssueCode('missingFlowStateDeclaration'),
      );
    });

    test('rejects value refs outside their source context', () {
      final eventWriteDocument = _document(
        flowState: _flowState(),
        welcomeTransitions: {
          'next': const GotoFlowTransition(
            'done',
            stateWrites: {
              'completed': FlowStateWrite(
                type: FlowDataType.bool,
                value: ActionResultFlowValueSource(key: 'granted'),
              ),
            },
          ),
        },
      );
      final decisionWriteDocument = _document(
        initial: 'branch',
        flowState: _flowState(),
        states: const {
          'branch': DecisionFlowState(
            branches: [],
            defaultBranch: FlowBranchTarget(
              target: 'done',
              stateWrites: {
                'completed': FlowStateWrite(
                  type: FlowDataType.bool,
                  value: EventFlowValueSource(key: 'completed'),
                ),
              },
            ),
          ),
          'done': EndFlowState(result: {'completed': true}),
        },
      );

      expect(
        FlowDocumentValidation.validate(eventWriteDocument),
        _containsIssueCode('invalidValueSourceContext'),
      );
      expect(
        FlowDocumentValidation.validate(decisionWriteDocument),
        _containsIssueCode('invalidValueSourceContext'),
      );
    });

    test('rejects direct sub-flow recursion', () {
      final document = _document(
        initial: 'profile',
        states: {
          'profile': SubFlowState(
            flow: 'first_run',
            version: 1,
            schemaVersion: 1,
            minClient: 3,
            contentHash: FlowContentHash.parse(_hash),
            input: const {},
            onComplete: const [],
            defaultBranch: const FlowBranchTarget(target: 'done'),
          ),
          'done': const EndFlowState(result: {'completed': true}),
        },
      );

      expect(
        FlowDocumentValidation.validate(document),
        _containsIssueCode('subFlowCycle'),
      );
    });
  });
}

Matcher _containsIssueCode(String code) {
  return contains(
    isA<FlowDocumentValidationIssue>().having(
      (issue) => issue.code,
      'code',
      code,
    ),
  );
}

Map<String, FlowStateDeclaration> _flowState() {
  return const {
    'completed': FlowStateDeclaration(
      type: FlowDataType.bool,
      classification: FlowStateClassification.exportable,
      defaultValue: false,
    ),
  };
}

FlowDocument _document({
  String initial = 'welcome',
  int schemaVersion = 1,
  int minClient = 3,
  Map<String, FlowStateDeclaration> flowState = const {},
  FlowOutboundDeclarations outbound = const FlowOutboundDeclarations(),
  Map<String, ScreenArtifact>? artifacts,
  Map<String, ScreenArtifact> extraArtifacts = const {},
  Map<String, FlowTransition>? welcomeTransitions,
  Map<String, FlowState>? states,
  Map<String, FlowState> extraStates = const {},
  Map<String, Object?> doneResult = const {'completed': true},
  bool reorderStates = false,
}) {
  final baseStates = states ??
      {
        'welcome': ScreenFlowState(
          screen: 'welcome',
          on: welcomeTransitions ?? const {'next': FlowTransition.goto('done')},
        ),
        'done': EndFlowState(result: doneResult),
      };
  final mergedStates = {
    ...baseStates,
    ...extraStates,
  };
  return FlowDocument(
    flow: 'first_run',
    version: 1,
    schemaVersion: schemaVersion,
    minClient: minClient,
    initial: initial,
    flowState: flowState,
    outbound: outbound,
    screenArtifacts: {
      ...(artifacts ?? {'welcome': _artifact('welcome.rfw')}),
      ...extraArtifacts,
    },
    states: reorderStates
        ? {
            for (final entry in mergedStates.entries.toList().reversed)
              entry.key: entry.value,
          }
        : mergedStates,
  );
}

ScreenArtifact _artifact(String path) {
  return ScreenArtifact(
    path: path,
    version: 1,
    schemaVersion: 1,
    minClient: 3,
    contentHash: FlowContentHash.parse(_hash),
  );
}

const _hash = 'sha256:3a6eb0790f39ac87c94f3856b2dd2c5d110e6811602261a9a923'
    'd3bb23adc8b7';

Map<String, Object?> _documentJson() {
  return jsonDecode(FlowDocumentCodec.encodePrettyJson(_document()))
      as Map<String, Object?>;
}
