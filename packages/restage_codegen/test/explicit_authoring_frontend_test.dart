import 'dart:io';

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:path/path.dart' as p;
import 'package:restage_codegen/src/onboarding/flow_definition_frontend.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const _fixtureRoot = 'test/fixtures/explicit_authoring';

void main() {
  group('analyzer-resolved authoring frontend', () {
    test('normalizes the minimal linear graph and derived flow identity',
        () async {
      final result = await _inspectFlow(
        'linear/new',
        'lib/onboarding/flows/welcome_flow.dart',
      );

      expect(result.issues, isEmpty, reason: _issues(result));
      final flow = result.flows.single;
      expect(flow.id, 'welcome_flow');
      expect(flow.hasExplicitId, isFalse);
      expect(flow.surface, Surface.onboarding);
      expect(flow.isCanonical, isTrue);
      expect(flow.declaration, isA<TopLevelVariableElement>());

      final graph = flow.graph!;
      expect(graph.initial, 'welcome');
      expect(
        graph.states.keys,
        containsAll(<String>['welcome', 'profile', 'done']),
      );
      expect(graph.states['done'], isA<EndFlowState>());
      expect(graph.screens.keys, containsAll(<String>['welcome', 'profile']));
    });

    test('preserves typed state references across branches and outbound policy',
        () async {
      final result = await _inspectFlow(
        'branching/new',
        'lib/survey/flows/setup_survey.dart',
      );

      expect(result.issues, isEmpty, reason: _issues(result));
      final graph = result.flows.single.graph!;
      expect(graph.flowState['answer']!.type, FlowDataType.string);
      expect(
        graph.flowState['answer']!.classification,
        FlowStateClassification.exportable,
      );
      expect(graph.flowState['returningUser']!.type, FlowDataType.bool);
      expect(
        graph.flowState['returningUser']!.classification,
        FlowStateClassification.internal,
      );
      expect(graph.flowState['returningUser']!.hostSeedable, isTrue);
      expect(graph.outbound.surveyAnswers.fields.keys, contains('answer'));
      expect(graph.outbound.terminalResult.fields.keys, contains('answer'));
      expect(graph.states['route'], isA<DecisionFlowState>());
      expect(graph.states['done'], isA<EndFlowState>());
    });

    test('converges multiple completion paths on one terminal identity',
        () async {
      final result = await _inspectFlow(
        'completion/new',
        'lib/onboarding/flows/completion_paths.dart',
      );

      expect(result.issues, isEmpty, reason: _issues(result));
      final graph = result.flows.single.graph!;
      expect(graph.states['done'], isA<EndFlowState>());
      for (final screenId in <String>['accepted', 'declined']) {
        final state = graph.states[screenId];
        expect(state, isA<ScreenFlowState>());
        final transitions = (state! as ScreenFlowState).on.values;
        expect(transitions, hasLength(1));
        expect(transitions.single, isA<GotoFlowTransition>());
        expect((transitions.single as GotoFlowTransition).target, 'done');
      }
    });

    test('normalizes node references, host actions, and subflows', () async {
      final cycle = await _inspectFlow(
        'cycle/new',
        'lib/onboarding/flows/retry_flow.dart',
      );
      expect(cycle.issues, isEmpty, reason: _issues(cycle));
      expect(
        cycle.flows.single.graph!.states['retry'],
        isA<DecisionFlowState>(),
      );

      final action = await _inspectFlow(
        'action/new',
        'lib/onboarding/flows/permission_flow.dart',
      );
      expect(action.issues, isEmpty, reason: _issues(action));
      expect(
        action.flows.single.graph!.actions.keys,
        contains('requestNotifications'),
      );

      final subflow = await _inspectFlow(
        'subflow/new',
        'lib/onboarding/flows/account_setup.dart',
      );
      expect(subflow.issues, isEmpty, reason: _issues(subflow));
      expect(
        subflow.flows.single.graph!.states['profile'],
        isA<SubFlowState>(),
      );
    });

    test('keeps paywall composition category-neutral', () async {
      final result = await _inspectFlow(
        'paywall_cross_category',
        'lib/general/flows/general_offer.dart',
      );

      expect(result.issues, isEmpty, reason: _issues(result));
      final flow = result.flows.single;
      expect(flow.surface, Surface.general);
      expect(flow.graph!.screens.keys, contains('paywall_general_premium'));
      final paywall = flow.graph!.screens['paywall_general_premium']!;
      expect(paywall.isPaywall, isTrue);
      expect(paywall.effectiveSurface, Surface.general);
    });

    test('derives omitted IDs and preserves authoritative explicit IDs',
        () async {
      final derived = await _inspectFlow(
        'identity/new',
        'lib/general/flows/derived_flow.dart',
      );
      expect(derived.issues, isEmpty, reason: _issues(derived));
      expect(derived.flows.single.id, 'derived_flow');
      expect(derived.flows.single.hasExplicitId, isFalse);
      expect(derived.flows.single.graph!.screens['derived_notice'], isNotNull);

      final moved = await _inspectFlow(
        'identity/new',
        'lib/message/flows/moved_flow.dart',
      );
      expect(moved.issues, isEmpty, reason: _issues(moved));
      expect(moved.flows.single.id, 'stable_flow');
      expect(moved.flows.single.hasExplicitId, isTrue);
      expect(moved.flows.single.graph!.screens['stable_notice'], isNotNull);
    });

    test('allows a neutral screen to inherit each containing flow category',
        () async {
      final onboarding = await _inspectFlow(
        'categories/new',
        'lib/onboarding/flows/neutral_welcome.dart',
      );
      expect(onboarding.issues, isEmpty, reason: _issues(onboarding));
      final onboardingScreen =
          onboarding.flows.single.graph!.screens['welcome']!;
      expect(onboardingScreen.declaredSurface, isNull);
      expect(onboardingScreen.effectiveSurface, Surface.onboarding);

      final message = await _inspectFlow(
        'categories/new',
        'lib/message/flows/neutral_welcome.dart',
      );
      expect(message.issues, isEmpty, reason: _issues(message));
      final messageScreen = message.flows.single.graph!.screens['welcome']!;
      expect(messageScreen.declaredSurface, isNull);
      expect(messageScreen.effectiveSurface, Surface.message);
    });

    test('rejects categorized screen mismatch and divergent terminals',
        () async {
      final mismatch = await _inspectFlow(
        'categories/new',
        'lib/onboarding/flows/mismatch.dart',
      );
      expect(mismatch.issues, isNotEmpty);
      expect(
        mismatch.issues.map((issue) => issue.message).join('\n'),
        contains('surface message'),
      );

      final terminals = await _inspectFlow(
        'negative/two_terminals',
        'lib/onboarding/flows/two_terminals.dart',
      );
      expect(terminals.issues, isNotEmpty);
      expect(
        terminals.issues.map((issue) => issue.message).join('\n'),
        contains('one terminal identity'),
      );

      final duplicateFlow = await _inspectFlow(
        'negative/duplicate_implicit_flow.dart',
        'lib/duplicate_implicit_flow.dart',
      );
      expect(duplicateFlow.issues, isNotEmpty);
      expect(
        duplicateFlow.issues.map((issue) => issue.message).join('\n'),
        contains('At most one canonical @FlowGraph declaration'),
      );
    });
  });
}

Future<FlowFrontendResult> _inspectFlow(
  String scenario,
  String targetPath,
) async {
  final sources = _loadScenario(scenario);
  final writer = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  for (final entry in sources.entries) {
    writer.testing.writeString(AssetId.parse(entry.key), entry.value);
  }

  FlowFrontendResult? inspected;
  await testBuilder(
    _ProbeBuilder((library, assetId) async {
      if (assetId.path != targetPath) return;
      inspected = await inspectFlowDefinitions(library, assetId);
    }),
    sources,
    rootPackage: 'apps_examples',
    readerWriter: writer,
  );
  return inspected ??
      (throw StateError('No frontend result for $scenario/$targetPath'));
}

Map<String, String> _loadScenario(String scenario) {
  final scenarioPath = '$_fixtureRoot/$scenario';
  final singleFile = File(scenarioPath);
  if (singleFile.existsSync()) {
    return <String, String>{
      'apps_examples|lib/${p.basename(singleFile.path)}':
          singleFile.readAsStringSync(),
    };
  }
  final scenarioRoot = Directory(scenarioPath);
  final libRoot = Directory(p.join(scenarioRoot.path, 'lib'));
  final root = libRoot.existsSync() ? libRoot : scenarioRoot;
  expect(
    root.existsSync(),
    isTrue,
    reason: 'missing fixture root ${root.path}',
  );
  final sources = <String, String>{};
  for (final entity in root.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (entity.path.endsWith('.g.dart')) continue;
    final relative = p.relative(entity.path, from: root.path);
    sources['apps_examples|lib/$relative'] = entity.readAsStringSync();
  }
  return sources;
}

String _issues(FlowFrontendResult result) =>
    result.issues.map((issue) => '${issue.code}: ${issue.message}').join('\n');

final class _ProbeBuilder implements Builder {
  _ProbeBuilder(this.onLibrary);

  final Future<void> Function(LibraryElement library, AssetId assetId)
      onLibrary;

  @override
  Map<String, List<String>> get buildExtensions => const {
        '.dart': ['.explicit_authoring_frontend_probe'],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    await onLibrary(await buildStep.inputLibrary, buildStep.inputId);
  }
}
