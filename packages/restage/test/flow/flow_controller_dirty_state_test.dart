import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_shared/restage_shared.dart';

import 'flow_test_support.dart';

RestageFlowController<FirstRunResult> _controller(ResolvedFlow flow) =>
    RestageFlowController<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: StaticFlowResolver(flow),
      actions: null,
      onEvent: (_) {},
      onComplete: (_) {},
      onUnavailable: (_) {},
    );

/// A linear welcome->profile->done flow whose `next` transition records a
/// state write (an answer), so the transition contributes user state. The
/// written key is declared in [FlowDocument.flowState] so the document passes
/// validation.
ResolvedFlow _stateWritingFlow() {
  final document = flowDocument(
    legacyTerminalResultPassthrough: false,
    outbound: const FlowOutboundDeclarations(
      terminalResult: FlowOutboundPayloadDeclaration(
        fields: {
          'completed': FlowOutboundField(
            type: FlowDataType.bool,
            ref: EventFlowOutboundRef(key: 'completed'),
          ),
        },
      ),
    ),
    states: const {
      'welcome': ScreenFlowState(
        screen: 'welcome',
        on: {
          'next': GotoFlowTransition(
            'profile',
            stateWrites: {
              'answer': FlowStateWrite(
                type: FlowDataType.bool,
                value: LiteralFlowValueSource(
                  type: FlowDataType.bool,
                  value: true,
                ),
              ),
            },
          ),
        },
      ),
      'profile': ScreenFlowState(
        screen: 'profile',
        on: {'finish': FlowTransition.goto('done')},
      ),
      'done': EndFlowState(result: {'completed': true}),
    },
  ).copyWith(
    flowState: const {
      'answer': FlowStateDeclaration(
        type: FlowDataType.bool,
        classification: FlowStateClassification.internal,
      ),
    },
  );
  return resolvedFlow(document: document);
}

void main() {
  setUp(Restage.debugReset);

  test('pristine on the first screen; dirty after navigating past it',
      () async {
    final controller = _controller(resolvedFlow());
    await controller.load();
    expect(controller.hasUserContributedState, isFalse);

    controller.handleEvent('next', const <String, Object?>{});
    await Future<void>.delayed(Duration.zero);
    expect(controller.hasUserContributedState, isTrue);
  });

  test(
      'a state-writing transition marks dirty, and dirtiness survives a back '
      'to the first screen (the history branch alone would read clean)',
      () async {
    final controller = _controller(_stateWritingFlow());
    await controller.load();
    expect(controller.hasUserContributedState, isFalse);

    controller.handleEvent('next', const <String, Object?>{});
    await Future<void>.delayed(Duration.zero);
    expect(controller.hasUserContributedState, isTrue);

    // Pop back to the first screen: history length returns to 1, so only the
    // recorded state write can keep the surface dirty.
    controller.back();
    await Future<void>.delayed(Duration.zero);
    expect(controller.canBack, isFalse); // back at the first screen
    expect(controller.hasUserContributedState, isTrue);
  });

  test('a plain navigation with no state write is clean again after a back',
      () async {
    final controller = _controller(resolvedFlow());
    await controller.load();
    controller.handleEvent('next', const <String, Object?>{});
    await Future<void>.delayed(Duration.zero);
    expect(controller.hasUserContributedState, isTrue); // via history depth

    controller.back();
    await Future<void>.delayed(Duration.zero);
    expect(controller.hasUserContributedState, isFalse); // no state contributed
  });
}
