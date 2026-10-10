import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart' hide allOf;
import 'package:restage/src/flow/flow_controller.dart'
    show createHostMeasurementFlowController;
import 'package:restage_shared/restage_shared.dart';

import 'flow_test_support.dart';

void main() {
  setUp(Restage.debugReset);

  group('Declared answers on typed flow surfaces', () {
    for (final surface in [
      Surface.onboarding,
      Surface.message,
      Surface.survey,
    ]) {
      test('a typed ${surface.name} flow records its declared answer',
          () async {
        final events = <RestageEvent>[];
        final measured = <(String, Object?)>[];
        FlowUnavailableError? unavailable;
        final controller =
            createHostMeasurementFlowController<Map<String, Object?>>(
          flow: _flowRef(surface),
          resolver: StaticFlowResolver(
            resolvedFlow(document: _answerDocument()),
          ),
          actions: null,
          onRootResolved: (_) async {},
          sanitizeAndRecordEvent: (value) => value,
          onMeasurementAnswer: (question, value) =>
              measured.add((question, value)),
          onEvent: events.add,
          onComplete: (_) {},
          onUnavailable: (error) => unavailable = error,
        );
        addTearDown(controller.dispose);

        await controller.load();
        expect(unavailable, isNull);
        expect(controller.currentScreenId, 'welcome');

        controller.handleEvent('next', const <String, Object?>{});
        await drainFlowTasks();

        expect(measured, [('goal', 'sleep')]);
        expect(
          events.whereType<SurveyQuestionResponded>().map(
                (event) => (event.questionId, event.questionIndex),
              ),
          [('goal', 0)],
        );
      });
    }

    test('a typed paywall flow declaring answers is refused at load', () async {
      FlowUnavailableError? unavailable;
      final controller = RestageFlowController<Map<String, Object?>>(
        flow: _flowRef(Surface.paywall),
        resolver: StaticFlowResolver(resolvedFlow(document: _answerDocument())),
        actions: null,
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (error) => unavailable = error,
      );
      addTearDown(controller.dispose);

      await controller.load();

      expect(unavailable?.reason, 'survey_answers_unsupported');
      expect(controller.currentScreenId, isNull);
    });

    test('a general flow declaring answers is refused at load', () async {
      FlowUnavailableError? unavailable;
      final controller = RestageFlowController<Map<String, Object?>>(
        flow: _flowRef(Surface.onboarding),
        resolver: StaticFlowResolver(
          resolvedFlow(
            document: _answerDocument(deliveryMode: FlowDeliveryMode.general),
          ),
        ),
        actions: null,
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (error) => unavailable = error,
      );
      addTearDown(controller.dispose);

      await controller.load();

      expect(unavailable?.reason, 'survey_answers_unsupported');
      expect(controller.currentScreenId, isNull);
    });

    test('a sub-flow declaring answers is refused', () async {
      final child = _answerDocument(flow: 'child_flow');
      final childHash = FlowContentHash.compute(
        utf8.encode(FlowDocumentCodec.encodePrettyJson(child)),
      );
      final parent = flowDocument(
        states: {
          'welcome': SubFlowState(
            flow: 'child_flow',
            version: 1,
            schemaVersion: 2,
            minClient: 3,
            contentHash: childHash,
            input: const {},
            onComplete: const [],
            defaultBranch: const FlowBranchTarget(target: 'done'),
          ),
          'done': const EndFlowState(result: {}),
        },
      );
      final resolver = _MapFlowResolver({
        'first_run': resolvedFlow(document: parent),
        'child_flow': ResolvedFlow(
          document: child,
          screenBlobs: resolvedFlow().screenBlobs,
          contentHash: childHash,
          cacheHit: false,
        ),
      });
      FlowUnavailableError? unavailable;
      final controller = RestageFlowController<Map<String, Object?>>(
        flow: _flowRef(Surface.onboarding),
        resolver: resolver,
        actions: null,
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (error) => unavailable = error,
      );
      addTearDown(controller.dispose);

      await controller.load();

      expect(unavailable?.reason, 'sub_flow_unavailable');
      expect(
        unavailable?.message,
        contains('survey_answers_not_allowed_in_subflow'),
      );
    });
  });
}

OnboardingFlowRef<Map<String, Object?>> _flowRef(Surface surface) =>
    OnboardingFlowRef<Map<String, Object?>>(
      id: 'first_run',
      version: 1,
      minClient: 3,
      surface: surface,
      decodeResult: (result) => result,
    );

FlowDocument _answerDocument({
  String flow = 'first_run',
  FlowDeliveryMode deliveryMode = FlowDeliveryMode.typed,
}) {
  return flowDocument(flow: flow).copyWith(
    schemaVersion: 2,
    deliveryMode: deliveryMode,
    flowState: const {
      'goal': FlowStateDeclaration(
        type: FlowDataType.string,
        classification: FlowStateClassification.internal,
      ),
    },
    outbound: const FlowOutboundDeclarations(
      surveyAnswers: FlowOutboundPayloadDeclaration(
        fields: {
          'goal': FlowOutboundField(
            type: FlowDataType.string,
            ref: StateFlowOutboundRef(key: 'goal'),
          ),
        },
      ),
    ),
    surveyQuestionOrder: const ['goal'],
    states: const {
      'welcome': ScreenFlowState(
        screen: 'welcome',
        on: {
          'next': GotoFlowTransition(
            'profile',
            stateWrites: {
              'goal': FlowStateWrite(
                type: FlowDataType.string,
                value: LiteralFlowValueSource(
                  type: FlowDataType.string,
                  value: 'sleep',
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
      'done': EndFlowState(result: {}),
    },
  );
}

final class _MapFlowResolver implements FlowResolver {
  const _MapFlowResolver(this.flows);

  final Map<String, ResolvedFlow> flows;

  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) async =>
      flows[flow.id]!;
}
