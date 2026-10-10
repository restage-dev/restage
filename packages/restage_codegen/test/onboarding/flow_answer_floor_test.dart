import 'dart:convert';

import 'package:build/build.dart';
import 'package:restage_codegen/builder.dart';
import 'package:restage_codegen/src/onboarding/flow_definition_frontend.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_codegen/src/surface_publication/package_surface_compiler_builder.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../helpers.dart';

const _screen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
part 'restage.generated/goal_screen.restage.g.dart';
@Screen(id: 'goal_screen', surface: Surface.onboarding)
final class GoalScreen extends StatelessWidget {
  const GoalScreen({super.key});
  static const choose = SurfaceEvent<String>('choose');
  @override
  Widget build(BuildContext context) =>
      FilledButton(onPressed: surfaceEvent(choose, 'focus'), child: const Text('Focus'));
}
''';

String _classFlow({String delivery = ''}) => '''
import 'package:restage/restage.dart';
import '../screens/goal_screen.dart';
part 'restage.generated/goal_flow.restage.g.dart';
@FlowGraph(id: 'goal_flow', surface: Surface.onboarding$delivery)
final class GoalFlow extends RestageFlow {
  const GoalFlow();
  @override
  FlowDef buildFlow() {
    final done = endState('done');
    return flow(
      initial: goalScreenRef,
      flowState: const {'goal': FlowStateDeclaration(type: FlowDataType.string, classification: FlowStateClassification.exportable)},
      outbound: const FlowOutboundDeclarations(surveyAnswers: FlowOutboundPayloadDeclaration(fields: {'goal': FlowOutboundField(type: FlowDataType.string, ref: StateFlowOutboundRef(key: 'goal'))})),
      measurementAnswers: const {'goal': FlowAnswerMeasurement.category(outcomeKey: 'onboarding.goal', propertyName: 'goal', categoryLabels: {'focus': 'Focus'})},
      states: [
        screen(goalScreenRef).on(GoalScreen.choose).capture('goal').goTo(done),
        end(done, result: {}),
      ],
    );
  }
}
''';

void main() {
  test('a typed onboarding flow that measures answers requires the floor',
      () async {
    final sources = <String, String>{
      'apps_examples|lib/onboarding/screens/goal_screen.dart': _screen,
      'apps_examples|lib/onboarding/flows/goal_flow.dart': _classFlow(),
    };
    final readerWriter =
        await readerWriterWithFilesystemSources(rootPackage: 'apps_examples');
    for (final builder in [
      onboardingScreenBuilder(BuilderOptions.empty),
      onboardingFlowBuilder(BuilderOptions.empty),
      const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
    ]) {
      final result = await testBuilder(
        builder,
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    }

    final document = FlowDocumentCodec.decodeJson(
      readerWriter.testing.readString(
        AssetId('apps_examples', 'assets/onboarding/flows/goal_flow.flow.json'),
      ),
    );
    expect(document.minClient, kSurfaceFeatureClientFloor);

    final handoff = RestageSurfacePublicationBundle.fromJson(
      jsonDecode(
        readerWriter.testing.readString(
          AssetId(
              'apps_examples', kRestageSurfacePublicationCompilerBundlePath),
        ),
      ),
    );
    expect(handoff.valid, isTrue, reason: handoff.errors.join('\n'));
    final part = utf8.decode(
      handoff.ownedOutputs.entries
          .singleWhere(
              (entry) => entry.key.endsWith('goal_flow.restage.g.dart'))
          .value,
    );
    expect(part, contains('minClient: $kSurfaceFeatureClientFloor,'));
  });

  test('a general flow that measures answers is refused by name', () async {
    final sources = <String, String>{
      'apps_examples|lib/onboarding/screens/goal_screen.dart': _screen,
      'apps_examples|lib/onboarding/flows/goal_flow.dart': _classFlow(
        delivery: ', delivery: FlowDeliveryMode.general',
      ),
    };
    final readerWriter =
        await readerWriterWithFilesystemSources(rootPackage: 'apps_examples');
    await testBuilder(
      onboardingScreenBuilder(BuilderOptions.empty),
      sources,
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );
    final logs = <String>[];
    await testBuilder(
      onboardingFlowBuilder(BuilderOptions.empty),
      sources,
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
      onLog: (record) => logs.add(record.message),
    );
    expect(
      logs.join('\n'),
      contains(kGeneralFlowMeasurementAnswersRefusal),
    );
  });
}
