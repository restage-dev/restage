import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  test('preserves a screen through a decision and applies global skip', () {
    final document = _document(
      initial: 'start',
      outbound: const FlowOutboundDeclarations(
        customEvents: {'skip': FlowOutboundPayloadDeclaration()},
      ),
      states: const {
        'start': ScreenFlowState(
          screen: 'start',
          on: {'next': FlowTransition.goto('decision')},
        ),
        'decision': DecisionFlowState(
          branches: [],
          defaultBranch: FlowBranchTarget(target: 'done'),
        ),
        'done': EndFlowState(result: {}),
      },
    );

    expect(FlowDocumentValidation.validate(document), isEmpty);
    expect(
      FlowScreenLifecycleReachability.analyze(document).channelsFor('start'),
      orderedEquals(FlowScreenLifecycleChannel.values),
    );
  });

  test('clears a parent screen on sub-flow entry before returning', () {
    final document = _document(
      initial: 'before',
      states: {
        'before': const ScreenFlowState(
          screen: 'before',
          on: {'next': FlowTransition.goto('child')},
        ),
        'child': SubFlowState(
          flow: 'child_flow',
          version: 1,
          schemaVersion: 1,
          minClient: 1,
          contentHash: FlowContentHash.compute(<int>[3]),
          input: const {},
          onComplete: const [],
          defaultBranch: const FlowBranchTarget(target: 'after'),
          subFlowUnavailable: const FlowBranchTarget(target: 'done'),
        ),
        'after': const ScreenFlowState(
          screen: 'after',
          on: {'next': FlowTransition.goto('done')},
        ),
        'done': const EndFlowState(result: {}),
      },
    );

    expect(FlowDocumentValidation.validate(document), isEmpty);
    final reachability = FlowScreenLifecycleReachability.analyze(document);
    expect(
      reachability.channelsFor('before'),
      orderedEquals(const [FlowScreenLifecycleChannel.presentation]),
    );
    expect(
      reachability.channelsFor('after'),
      orderedEquals(const [
        FlowScreenLifecycleChannel.presentation,
        FlowScreenLifecycleChannel.completion,
      ]),
    );
  });

  test('does not invent completion for a terminal screen without an end', () {
    final document = _document(
      initial: 'terminal',
      states: const {
        'terminal': ScreenFlowState(screen: 'terminal', on: {}),
      },
    );

    expect(FlowDocumentValidation.validate(document), isEmpty);
    final reachability = FlowScreenLifecycleReachability.analyze(document);
    expect(
      reachability.channelsFor('terminal'),
      orderedEquals(const [FlowScreenLifecycleChannel.presentation]),
    );
  });

  test('recognizes a screen-local skip destination', () {
    final document = _document(
      initial: 'start',
      states: const {
        'start': ScreenFlowState(
          screen: 'start',
          on: {'skip': FlowTransition.goto('done')},
        ),
        'done': EndFlowState(result: {}),
      },
    );

    expect(
      FlowScreenLifecycleReachability.analyze(document).channelsFor('start'),
      orderedEquals(FlowScreenLifecycleChannel.values),
    );
  });
}

FlowDocument _document({
  required String initial,
  required Map<String, FlowState> states,
  FlowOutboundDeclarations outbound = const FlowOutboundDeclarations(),
}) {
  final screens = <String>{
    for (final state in states.values)
      if (state is ScreenFlowState) state.screen,
  };
  return FlowDocument(
    flow: 'reachability',
    version: 1,
    schemaVersion: 1,
    minClient: 1,
    initial: initial,
    outbound: outbound,
    screenArtifacts: {
      for (final screen in screens)
        screen: ScreenArtifact(
          path: '$screen.rfw',
          version: 1,
          schemaVersion: 1,
          minClient: 1,
          contentHash: FlowContentHash.compute(screen.codeUnits),
        ),
    },
    states: states,
  );
}
