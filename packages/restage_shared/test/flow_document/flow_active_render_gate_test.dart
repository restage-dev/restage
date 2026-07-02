import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

// The render-gate goldens ARE the spec (TDD). They encode the ratified
// change-code -> {ACCEPT, REJECT} verdict table (cc2cc seq 14/15): ACCEPT only a
// content-only `screenArtifactChanged` at an unchanged capability floor (plus
// identical documents); REJECT every other diff() change, any per-artifact
// capability-floor raise, and any invalid input (fail-closed, never throws).
void main() {
  group('FlowActiveRenderGate.evaluate', () {
    group('ACCEPT — content-OTA + identity', () {
      test('identical documents are accepted', () {
        expect(
          FlowActiveRenderGate.evaluate(
            client: _document(),
            active: _document(),
          ).accepted,
          isTrue,
        );
      });

      test(
        'a screen-artifact content change at the same floor is accepted '
        '(the content-OTA case the chapter exists for)',
        () {
          final verdict = FlowActiveRenderGate.evaluate(
            client: _document(),
            active: _document(
              screenArtifacts: {
                'welcome': _artifact(
                  path: 'welcome.rfw',
                  hash: _altHash,
                ),
              },
            ),
          );
          expect(verdict, isA<FlowActiveRenderAccepted>());
        },
      );

      test('a copy/layout change (artifact version + content bump) is accepted',
          () {
        final verdict = FlowActiveRenderGate.evaluate(
          client: _document(),
          active: _document(
            screenArtifacts: {
              'welcome': _artifact(
                path: 'welcome.rfw',
                version: 2,
                hash: _altHash,
              ),
            },
          ),
        );
        expect(verdict.accepted, isTrue);
      });

      test('multiple screen-artifact content changes (same floor) are accepted',
          () {
        final verdict = FlowActiveRenderGate.evaluate(
          client: _twoScreenDocument(),
          active: _twoScreenDocument(
            welcome: _artifact(path: 'welcome.rfw', hash: _altHash),
            info: _artifact(path: 'info.rfw', hash: _altHash2),
          ),
        );
        expect(verdict.accepted, isTrue);
      });
    });

    group('REJECT — contract-surface expansion', () {
      test('a declared host action added is rejected', () {
        final verdict = FlowActiveRenderGate.evaluate(
          client: _document(),
          active: _document(
            actions: {
              'grant': const FlowActionContract(
                actionName: 'grant',
                contractVersion: 1,
                argsSchema: _emptyArgsSchema,
                resultSchema: _boolResultSchema,
                minClient: 3,
                idempotent: false,
              ),
            },
            welcomeOn: const {
              'next': FlowTransition.goto('done'),
              'grant': ActionFlowTransition(
                action: 'grant',
                resultPredicate: BoolEqualsActionResultPredicate(value: true),
                target: 'done',
              ),
            },
          ),
        );
        expect(verdict.accepted, isFalse);
        expect(
          (verdict as FlowActiveRenderRejected).reason,
          FlowActiveRenderRejectionReason.contractSurfaceExpanded,
        );
        expect(
          verdict.blockingChanges.map((c) => c.code),
          contains('actionAdded'),
        );
      });

      test('an action contract change is rejected', () {
        final verdict = FlowActiveRenderGate.evaluate(
          client: _actionDocument(result: const FlowActionSchema.bool()),
          active: _actionDocument(result: const FlowActionSchema.int()),
        );
        expect(verdict.accepted, isFalse);
        expect(
          _codes(verdict),
          contains('actionChanged'),
        );
      });

      test(
          'a terminal-result key added is rejected (the additive-but-unsafe '
          'heart; the exact decoder fails on the extra key)', () {
        final verdict = FlowActiveRenderGate.evaluate(
          client: _document(),
          active: _document(
            doneResult: const {'completed': true, 'tier': 'free'},
          ),
        );
        expect(verdict.accepted, isFalse);
        expect(
          _codes(verdict),
          contains('terminalResultAdded'),
        );
      });

      test('a terminal-result field type change is rejected', () {
        final verdict = FlowActiveRenderGate.evaluate(
          client: _document(),
          active: _document(doneResult: const {'completed': 1}),
        );
        expect(verdict.accepted, isFalse);
        expect(
          _codes(verdict),
          contains('terminalResultChanged'),
        );
      });

      test('an outbound field added is rejected (data minimization)', () {
        final verdict = FlowActiveRenderGate.evaluate(
          client: _document(flowState: _flowState()),
          active: _document(
            flowState: _flowState(),
            outbound: const FlowOutboundDeclarations(
              terminalResult: FlowOutboundPayloadDeclaration(
                fields: {
                  'completed': FlowOutboundField(
                    type: FlowDataType.bool,
                    ref: StateFlowOutboundRef(key: 'completed'),
                  ),
                },
              ),
            ),
          ),
        );
        expect(verdict.accepted, isFalse);
        expect(
          _codes(verdict),
          contains('outboundFieldAdded'),
        );
      });

      test('an outbound payload group added is rejected (data minimization)',
          () {
        final verdict = FlowActiveRenderGate.evaluate(
          client: _document(flowState: _flowState()),
          active: _document(
            flowState: _flowState(),
            outbound: const FlowOutboundDeclarations(
              customEvents: {
                'analyticsTap': FlowOutboundPayloadDeclaration(
                  fields: {
                    'campaign': FlowOutboundField(
                      type: FlowDataType.string,
                      ref: EventFlowOutboundRef(key: 'campaign'),
                    ),
                  },
                ),
              },
            ),
          ),
        );
        expect(verdict.accepted, isFalse);
        expect(
          _codes(verdict),
          contains('outboundPayloadAdded'),
        );
      });

      test('a flow-state key added is rejected', () {
        final verdict = FlowActiveRenderGate.evaluate(
          client: _document(flowState: _flowState()),
          active: _document(
            flowState: {
              ..._flowState(),
              'count': const FlowStateDeclaration(
                type: FlowDataType.int,
                classification: FlowStateClassification.internal,
                defaultValue: 0,
              ),
            },
          ),
        );
        expect(verdict.accepted, isFalse);
        expect(
          _codes(verdict),
          contains('flowStateAdded'),
        );
      });

      test('a reachable state + transition added is rejected', () {
        final verdict = FlowActiveRenderGate.evaluate(
          client: _document(),
          active: _document(
            screenArtifacts: {
              'welcome': _artifact(path: 'welcome.rfw'),
              'info': _artifact(path: 'info.rfw'),
            },
            welcomeOn: const {
              'next': FlowTransition.goto('done'),
              'learnMore': FlowTransition.goto('info'),
            },
            states: {
              'welcome': const ScreenFlowState(
                screen: 'welcome',
                on: {
                  'next': FlowTransition.goto('done'),
                  'learnMore': FlowTransition.goto('info'),
                },
              ),
              'info': const ScreenFlowState(
                screen: 'info',
                on: {'next': FlowTransition.goto('done')},
              ),
              'done': const EndFlowState(result: {'completed': true}),
            },
          ),
        );
        expect(verdict.accepted, isFalse);
        expect(
          _codes(verdict),
          contains('stateAdded'),
        );
      });

      test('a signature-preserving retarget (diff: forwarding) is rejected',
          () {
        final verdict = FlowActiveRenderGate.evaluate(
          client: _document(),
          active: _document(
            screenArtifacts: {
              'welcome': _artifact(path: 'welcome.rfw'),
              'ready': _artifact(path: 'ready.rfw'),
            },
            welcomeOn: const {'next': FlowTransition.goto('ready')},
            states: {
              'welcome': const ScreenFlowState(
                screen: 'welcome',
                on: {'next': FlowTransition.goto('ready')},
              ),
              'ready': const ScreenFlowState(
                screen: 'ready',
                on: {'finish': FlowTransition.goto('done')},
              ),
              'done': const EndFlowState(result: {'completed': true}),
            },
          ),
        );
        expect(verdict.accepted, isFalse);
        expect(
          _codes(verdict),
          contains('transitionRetargeted'),
        );
      });

      test('a decision branch added is rejected', () {
        final verdict = FlowActiveRenderGate.evaluate(
          client: _decisionDocument(extraBranch: false),
          active: _decisionDocument(extraBranch: true),
        );
        expect(verdict.accepted, isFalse);
        expect(
          _codes(verdict),
          contains('branchAdded'),
        );
      });

      test('the initial state changing is rejected', () {
        final verdict = FlowActiveRenderGate.evaluate(
          client: _document(),
          active: _document(
            initial: 'start',
            screenArtifacts: {
              'start': _artifact(path: 'start.rfw'),
              'welcome': _artifact(path: 'welcome.rfw'),
            },
            states: {
              'start': const ScreenFlowState(
                screen: 'start',
                on: {'next': FlowTransition.goto('welcome')},
              ),
              'welcome': const ScreenFlowState(
                screen: 'welcome',
                on: {'next': FlowTransition.goto('done')},
              ),
              'done': const EndFlowState(result: {'completed': true}),
            },
          ),
        );
        expect(verdict.accepted, isFalse);
        expect(
          _codes(verdict),
          contains('initialChanged'),
        );
      });

      test('the flow id changing is rejected', () {
        final verdict = FlowActiveRenderGate.evaluate(
          client: _document(),
          active: _document(flow: 'other_flow'),
        );
        expect(verdict.accepted, isFalse);
        expect(
          _codes(verdict),
          contains('flowChanged'),
        );
      });

      test(
          'a sub-flow reference change is rejected (sub-flows stay '
          'exact-pinned)', () {
        final verdict = FlowActiveRenderGate.evaluate(
          client: _subFlowDocument(childHash: _hash),
          active: _subFlowDocument(childHash: _altHashValue),
        );
        expect(verdict.accepted, isFalse);
        expect(
          _codes(verdict),
          contains('subFlowChanged'),
        );
      });

      test('the document minClient being raised is rejected', () {
        final verdict = FlowActiveRenderGate.evaluate(
          client: _document(),
          active: _document(minClient: 5),
        );
        expect(verdict.accepted, isFalse);
        expect(
          _codes(verdict),
          contains('minClientRaised'),
        );
      });
    });

    group(
        'REJECT — capability floor raised (the diff() granularity-gap closure)',
        () {
      test(
          'a screen-artifact whose own minClient rose above the client floor '
          'is rejected (proves the per-artifact floor guard)', () {
        final verdict = FlowActiveRenderGate.evaluate(
          client: _document(),
          active: _document(
            // document floor unchanged (default 3); only the artifact rises
            screenArtifacts: {
              'welcome': _artifact(
                path: 'welcome.rfw',
                minClient: 5,
                hash: _altHash,
              ),
            },
          ),
        );
        expect(verdict.accepted, isFalse);
        expect(
          (verdict as FlowActiveRenderRejected).reason,
          FlowActiveRenderRejectionReason.capabilityFloorRaised,
        );
      });

      test('a screen-artifact whose schemaVersion changed is rejected', () {
        final verdict = FlowActiveRenderGate.evaluate(
          client: _document(),
          active: _document(
            screenArtifacts: {
              'welcome': _artifact(
                path: 'welcome.rfw',
                schemaVersion: 2,
                hash: _altHash,
              ),
            },
          ),
        );
        expect(verdict.accepted, isFalse);
        expect(
          (verdict as FlowActiveRenderRejected).reason,
          FlowActiveRenderRejectionReason.capabilityFloorRaised,
        );
      });
    });

    group('BOUNDARY — subset terminal still fails the exact decoder', () {
      test(
          'an active terminal result that is a strict subset of the client '
          '(fewer keys) is rejected — the generated decoder fails on length',
          () {
        final verdict = FlowActiveRenderGate.evaluate(
          client: _document(
            doneResult: const {'completed': true, 'tier': 'free'},
          ),
          active: _document(),
        );
        expect(verdict.accepted, isFalse);
        expect(
          _codes(verdict),
          contains('terminalResultRemoved'),
        );
      });
    });

    group('FAIL-CLOSED — invalid input never throws', () {
      test('an invalid active document is rejected as documentInvalid', () {
        final verdict = FlowActiveRenderGate.evaluate(
          client: _document(),
          active: _invalidDocument(),
        );
        expect(verdict.accepted, isFalse);
        expect(
          (verdict as FlowActiveRenderRejected).reason,
          FlowActiveRenderRejectionReason.documentInvalid,
        );
      });

      test('an invalid client document is rejected as documentInvalid', () {
        final verdict = FlowActiveRenderGate.evaluate(
          client: _invalidDocument(),
          active: _document(),
        );
        expect(verdict.accepted, isFalse);
        expect(
          (verdict as FlowActiveRenderRejected).reason,
          FlowActiveRenderRejectionReason.documentInvalid,
        );
      });
    });

    group('verdict value-equality (public-SPI convention)', () {
      test('two accepted verdicts are equal; accepted != rejected', () {
        expect(
          const FlowActiveRenderAccepted(),
          const FlowActiveRenderAccepted(),
        );
        expect(
          const FlowActiveRenderAccepted() ==
              const FlowActiveRenderRejected(
                reason: FlowActiveRenderRejectionReason.documentInvalid,
                message: 'x',
              ),
          isFalse,
        );
      });

      test('two rejections with the same reason + message are equal', () {
        expect(
          const FlowActiveRenderRejected(
            reason: FlowActiveRenderRejectionReason.capabilityFloorRaised,
            message: 'floor',
          ),
          const FlowActiveRenderRejected(
            reason: FlowActiveRenderRejectionReason.capabilityFloorRaised,
            message: 'floor',
          ),
        );
      });
    });

    group('anti-drift census tripwire', () {
      test(
          'the predicate accepts exactly {screenArtifactChanged} among the '
          'censused diff() change codes', () {
        // The 41 distinct codes FlowDocumentCompatibility.diff() can emit
        // (census 2026-06-27, read from flow_document_compatibility.dart). The
        // change codes are String literals, so a NEW code in diff() will not
        // mechanically trip this test — but the predicate is fail-closed by
        // construction (any code not in `accepted` REJECTs), so safety holds
        // regardless. This census is the conscious-decision tripwire: if diff()
        // grows a code, add it here and decide its verdict (the default is
        // REJECT). The `_richMismatch` assertion below catches a new code that
        // a broad diff happens to emit.
        const censused = {
          'flowChanged',
          'schemaVersionRaised',
          'schemaVersionLowered',
          'minClientRaised',
          'initialChanged',
          'legacyTerminalResultPassthroughChanged',
          'actionRemoved',
          'actionChanged',
          'actionAdded',
          'flowStateRemoved',
          'flowStateChanged',
          'flowStateSeedabilityChanged',
          'flowStateAdded',
          'outboundPayloadRemoved',
          'outboundPayloadAdded',
          'outboundFieldRemoved',
          'outboundFieldChanged',
          'outboundFieldAdded',
          'screenArtifactRemoved',
          'screenArtifactChanged',
          'screenArtifactAdded',
          'stateRemoved',
          'stateKindChanged',
          'stateAdded',
          'unsupportedStateChanged',
          'screenChanged',
          'transitionRemoved',
          'transitionAdded',
          'transitionChanged',
          'transitionRetargeted',
          'subFlowChanged',
          'subFlowUnavailableAdded',
          'subFlowUnavailableRemoved',
          'branchChanged',
          'branchRetargeted',
          'branchRemoved',
          'branchAdded',
          'branchTargetChanged',
          'terminalResultRemoved',
          'terminalResultChanged',
          'terminalResultAdded',
        };
        const accepted = {'screenArtifactChanged'};
        expect(censused.length, 41);
        expect(censused.containsAll(accepted), isTrue);

        // A broad mismatch must reject, and every blocking code it emits must
        // be in the censused universe (a new un-censused code trips this).
        final verdict = FlowActiveRenderGate.evaluate(
          client: _document(flowState: _flowState()),
          active: _richMismatch(),
        );
        expect(verdict.accepted, isFalse);
        final emitted = _codes(verdict);
        expect(emitted, isNotEmpty);
        for (final code in emitted) {
          expect(
            censused,
            contains(code),
            reason: 'un-censused diff() code: $code',
          );
        }
      });
    });

    group('DOA-client baseline (documented; out of the compatibility domain)',
        () {
      // These pairs are runtime-INVALID on BOTH sides (client == active). The
      // gate ACCEPTS them because, as a COMPATIBILITY gate, it asks only
      // whether the active document's contract is a subset of the client's —
      // and it is (they are identical). Such a client cannot render its own
      // bundled document (the runtime rejects it at startup), so this is
      // unreachable against a valid client baseline; the runtime's validity
      // checks reject the active document independently (the binding downstream
      // backstop). Pinned as deliberate, documented behavior so the boundary
      // cannot silently drift. See the FlowActiveRenderGate doc-comment.
      test(
          'client == active at an unsupported document schemaVersion is '
          'accepted (runtime rejects it independently)', () {
        final document = _document(schemaVersion: 2);
        expect(
          FlowActiveRenderGate.evaluate(
            client: document,
            active: document,
          ).accepted,
          isTrue,
        );
      });

      test(
          'client == active with an inconsistent action/result predicate is '
          'accepted (runtime rejects it independently)', () {
        final document = _actionDocument(result: const FlowActionSchema.int());
        expect(
          FlowActiveRenderGate.evaluate(
            client: document,
            active: document,
          ).accepted,
          isTrue,
        );
      });
    });
  });
}

Iterable<String> _codes(FlowActiveRenderVerdict verdict) {
  return (verdict as FlowActiveRenderRejected)
      .blockingChanges
      .map((c) => c.code);
}

// ---------------------------------------------------------------------------
// In-memory document factories (the `_document(...)` convention).
// ---------------------------------------------------------------------------

const _hash = 'sha256:3a6eb0790f39ac87c94f3856b2dd2c5d110e6811602261a9a923'
    'd3bb23adc8b7';

final FlowContentHash _altHash =
    FlowContentHash.computeString('welcome screen, revision 2');
final FlowContentHash _altHash2 =
    FlowContentHash.computeString('info screen, revision 2');
final String _altHashValue =
    FlowContentHash.computeString('collect_email child v2').value;

ScreenArtifact _artifact({
  required String path,
  int version = 1,
  int schemaVersion = 1,
  int minClient = 3,
  FlowContentHash? hash,
}) {
  return ScreenArtifact(
    path: path,
    version: version,
    schemaVersion: schemaVersion,
    minClient: minClient,
    contentHash: hash ?? FlowContentHash.parse(_hash),
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
  String flow = 'first_run',
  String initial = 'welcome',
  int minClient = 3,
  int schemaVersion = 1,
  Map<String, ScreenArtifact>? screenArtifacts,
  Map<String, FlowState>? states,
  Map<String, FlowActionContract> actions = const {},
  Map<String, FlowStateDeclaration> flowState = const {},
  FlowOutboundDeclarations outbound = const FlowOutboundDeclarations(),
  Map<String, Object?> doneResult = const {'completed': true},
  Map<String, FlowTransition>? welcomeOn,
}) {
  return FlowDocument(
    flow: flow,
    version: 1,
    schemaVersion: schemaVersion,
    minClient: minClient,
    initial: initial,
    actions: actions,
    flowState: flowState,
    outbound: outbound,
    screenArtifacts:
        screenArtifacts ?? {'welcome': _artifact(path: 'welcome.rfw')},
    states: states ??
        {
          'welcome': ScreenFlowState(
            screen: 'welcome',
            on: welcomeOn ?? const {'next': FlowTransition.goto('done')},
          ),
          'done': EndFlowState(result: doneResult),
        },
  );
}

FlowDocument _twoScreenDocument({
  ScreenArtifact? welcome,
  ScreenArtifact? info,
}) {
  return FlowDocument(
    flow: 'first_run',
    version: 1,
    schemaVersion: 1,
    minClient: 3,
    initial: 'welcome',
    screenArtifacts: {
      'welcome': welcome ?? _artifact(path: 'welcome.rfw'),
      'info': info ?? _artifact(path: 'info.rfw'),
    },
    states: const {
      'welcome': ScreenFlowState(
        screen: 'welcome',
        on: {'next': FlowTransition.goto('info')},
      ),
      'info': ScreenFlowState(
        screen: 'info',
        on: {'next': FlowTransition.goto('done')},
      ),
      'done': EndFlowState(result: {'completed': true}),
    },
  );
}

FlowDocument _decisionDocument({required bool extraBranch}) {
  return FlowDocument(
    flow: 'first_run',
    version: 1,
    schemaVersion: 1,
    minClient: 3,
    initial: 'branch',
    flowState: _flowState(),
    screenArtifacts: const {},
    states: {
      'branch': DecisionFlowState(
        branches: [
          const FlowBranch(
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
            target: 'done',
          ),
          if (extraBranch)
            const FlowBranch(
              when: FlowBranchPredicate(
                fields: {
                  'completed': EqualsFlowPredicateCondition(
                    value: LiteralFlowValueSource(
                      type: FlowDataType.bool,
                      value: false,
                    ),
                  ),
                },
              ),
              target: 'done',
            ),
        ],
        defaultBranch: const FlowBranchTarget(target: 'done'),
      ),
      'done': const EndFlowState(result: {'completed': true}),
    },
  );
}

FlowDocument _subFlowDocument({required String childHash}) {
  return FlowDocument(
    flow: 'first_run',
    version: 1,
    schemaVersion: 1,
    minClient: 3,
    initial: 'profile',
    screenArtifacts: const {},
    states: {
      'profile': SubFlowState(
        flow: 'collect_email',
        version: 1,
        schemaVersion: 1,
        minClient: 3,
        contentHash: FlowContentHash.parse(childHash),
        input: const {},
        onComplete: const [],
        defaultBranch: const FlowBranchTarget(target: 'done'),
      ),
      'done': const EndFlowState(result: {'completed': true}),
    },
  );
}

/// A document that is structurally invalid (a screen references a missing
/// artifact) but constructable — used to prove the gate fails closed rather
/// than throwing.
FlowDocument _invalidDocument() {
  return const FlowDocument(
    flow: 'first_run',
    version: 1,
    schemaVersion: 1,
    minClient: 3,
    initial: 'welcome',
    screenArtifacts: {},
    states: {
      'welcome': ScreenFlowState(
        screen: 'welcome',
        on: {'next': FlowTransition.goto('done')},
      ),
      'done': EndFlowState(result: {'completed': true}),
    },
  );
}

/// A valid document that differs from the `_flowState()` base along many
/// dimensions at once (terminal result, flow-state, a reachable screen), so the
/// census tripwire sees a broad blocking-change set.
FlowDocument _richMismatch() {
  return FlowDocument(
    flow: 'first_run',
    version: 1,
    schemaVersion: 1,
    minClient: 3,
    initial: 'welcome',
    flowState: {
      ..._flowState(),
      'count': const FlowStateDeclaration(
        type: FlowDataType.int,
        classification: FlowStateClassification.internal,
        defaultValue: 0,
      ),
    },
    screenArtifacts: {
      'welcome': _artifact(path: 'welcome.rfw'),
      'info': _artifact(path: 'info.rfw'),
    },
    states: const {
      'welcome': ScreenFlowState(
        screen: 'welcome',
        on: {
          'next': FlowTransition.goto('done'),
          'learnMore': FlowTransition.goto('info'),
        },
      ),
      'info': ScreenFlowState(
        screen: 'info',
        on: {'next': FlowTransition.goto('done')},
      ),
      'done': EndFlowState(result: {'completed': true, 'tier': 'free'}),
    },
  );
}

FlowDocument _actionDocument({required FlowActionSchema result}) {
  return _document(
    actions: {
      'grant': FlowActionContract(
        actionName: 'grant',
        contractVersion: 1,
        argsSchema: _emptyArgsSchema,
        resultSchema: result,
        minClient: 3,
        idempotent: false,
      ),
    },
    welcomeOn: const {
      'next': FlowTransition.goto('done'),
      'grant': ActionFlowTransition(
        action: 'grant',
        resultPredicate: BoolEqualsActionResultPredicate(value: true),
        target: 'done',
      ),
    },
  );
}

const _emptyArgsSchema = FlowActionSchema.object({});
const _boolResultSchema = FlowActionSchema.bool();
