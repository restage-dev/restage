import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:logging/logging.dart';
import 'package:restage_codegen/builder.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  group('OnboardingFlowBuilder', () {
    test('emits descriptor, empty actions, and canonical flow JSON', () async {
      final sources = _firstRunSources();
      final readerWriter = await _readerWriterWith(sources);

      final result = await testBuilders(
        [
          onboardingScreenBuilder(BuilderOptions.empty),
          onboardingFlowBuilder(BuilderOptions.empty),
        ],
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      final generated = result.readerWriter.testing.readString(
        AssetId(
          'apps_examples',
          'lib/onboarding/flows/first_run.rsflow.g.dart',
        ),
      );
      expect(
        generated,
        allOf(
          contains("part of 'first_run.dart';"),
          contains('abstract final class FirstRunFlowDescriptor'),
          contains('OnboardingFlowRef<FirstRunResult>'),
          contains('decodeResult: FirstRunFlowDescriptor._decodeResult'),
          contains('final class FirstRunResult'),
          contains('final class FirstRunActions'),
          isNot(contains('FlowActionHandler')),
        ),
      );
      expect(generated, contains('static FirstRunResult _decodeResult('));
      final jsonBytes = result.readerWriter.testing.readBytes(
        AssetId('apps_examples', 'assets/onboarding/flows/first_run.flow.json'),
      );
      expect(jsonBytes, _canonicalFirstRunFlowJson());
    });

    test('generated decoder accepts canonical result and rejects bad maps',
        () async {
      final sources = _firstRunSources();
      final readerWriter = await _readerWriterWith(sources);

      final result = await testBuilders(
        [
          onboardingScreenBuilder(BuilderOptions.empty),
          onboardingFlowBuilder(BuilderOptions.empty),
        ],
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      final generated = result.readerWriter.testing.readString(
        AssetId(
          'apps_examples',
          'lib/onboarding/flows/first_run.rsflow.g.dart',
        ),
      );

      expect(
        generated,
        allOf(
          contains(
            "if (result.length != 1 || !result.containsKey('completed'))",
          ),
          contains("final completed = result['completed'];"),
          contains('if (completed is! bool)'),
          contains('return FirstRunResult(completed: completed);'),
        ),
      );
      await _assertGeneratedResultDecoderRuns(generated);
    });

    test('generated empty-result decoder uses const empty DTO constructor',
        () async {
      final sources = _singleScreenFlowSources(resultExpression: '{}');
      final readerWriter = await _readerWriterWith(sources);

      final result = await testBuilders(
        [
          onboardingScreenBuilder(BuilderOptions.empty),
          onboardingFlowBuilder(BuilderOptions.empty),
        ],
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      final generated = result.readerWriter.testing.readString(
        AssetId(
          'apps_examples',
          'lib/onboarding/flows/first_run.rsflow.g.dart',
        ),
      );

      expect(
        generated,
        allOf(
          contains('static FirstRunResult _decodeResult('),
          contains('if (result.isNotEmpty)'),
          contains('return const FirstRunResult();'),
        ),
      );
    });

    test('screen artifact contentHash matches emitted .rfw bytes', () async {
      final sources = _firstRunSources();
      final readerWriter = await _readerWriterWith(sources);

      final result = await testBuilders(
        [
          onboardingScreenBuilder(BuilderOptions.empty),
          onboardingFlowBuilder(BuilderOptions.empty),
        ],
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );

      final flowBytes = result.readerWriter.testing.readBytes(
        AssetId('apps_examples', 'assets/onboarding/flows/first_run.flow.json'),
      );
      final welcomeBytes = result.readerWriter.testing.readBytes(
        AssetId('apps_examples', 'assets/onboarding/screens/welcome.rfw'),
      );
      final decoded = FlowDocumentCodec.decodeJson(utf8.decode(flowBytes));
      final expectedHash = FlowContentHash.compute(welcomeBytes).value;

      expect(
        decoded.screenArtifacts['welcome']?.contentHash.value,
        expectedHash,
      );
      expect(
        decoded.screenArtifacts.keys,
        containsAll(['welcome', 'permissions', 'ready']),
      );
    });

    test('emits flow state and outbound declarations', () async {
      final sources = _firstRunSourcesWithOutbound();
      final readerWriter = await _readerWriterWith(sources);

      final result = await testBuilders(
        [
          onboardingScreenBuilder(BuilderOptions.empty),
          onboardingFlowBuilder(BuilderOptions.empty),
        ],
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );

      final flowBytes = result.readerWriter.testing.readBytes(
        AssetId('apps_examples', 'assets/onboarding/flows/first_run.flow.json'),
      );
      final decoded = FlowDocumentCodec.decodeJson(utf8.decode(flowBytes));
      final customEvent =
          decoded.outbound.customEvents['analyticsTap']!.fields['ctaId']!;

      expect(
        decoded.flowState['completed']?.classification,
        FlowStateClassification.exportable,
      );
      expect(
        decoded.outbound.terminalResult.fields['completed']?.ref,
        isA<StateFlowOutboundRef>().having(
          (ref) => ref.key,
          'key',
          'completed',
        ),
      );
      expect(
        customEvent.ref,
        isA<EventFlowOutboundRef>().having(
          (ref) => ref.key,
          'key',
          'ctaId',
        ),
      );
    });

    test('lowers a paywall screen ref into a flow screen state', () async {
      final sources = _paywallStepFlowSources();
      final readerWriter = await _readerWriterWith(sources);
      final paywallBytes = Uint8List.fromList([1, 2, 3, 4]);
      readerWriter.testing.writeBytes(
        AssetId(
          'apps_examples',
          'assets/onboarding/screens/paywall_serene.rfw',
        ),
        paywallBytes,
      );

      final result = await testBuilders(
        [
          onboardingScreenBuilder(BuilderOptions.empty),
          onboardingFlowBuilder(BuilderOptions.empty),
        ],
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );

      final flowBytes = result.readerWriter.testing.readBytes(
        AssetId('apps_examples', 'assets/onboarding/flows/first_run.flow.json'),
      );
      final decoded = FlowDocumentCodec.decodeJson(utf8.decode(flowBytes));
      final welcome = decoded.states['welcome']! as ScreenFlowState;
      final paywall = decoded.states['paywall_serene']! as ScreenFlowState;

      expect(welcome.on['next']?.target, 'paywall_serene');
      expect(paywall.screen, 'paywall_serene');
      expect(paywall.on['purchase']?.target, 'done');
      expect(
        decoded.screenArtifacts['paywall_serene']?.path,
        'paywall_serene.rfw',
      );
      expect(
        decoded.screenArtifacts['paywall_serene']?.contentHash,
        FlowContentHash.compute(paywallBytes),
      );
    });

    test('lowers decision and sub-flow graph nodes with child result filtering',
        () async {
      final childFlowJson = _profileChildFlowJson();
      final sources = _graphFlowSources(childFlowJson);
      final readerWriter = await _readerWriterWith(sources);

      final result = await testBuilders(
        [
          onboardingScreenBuilder(BuilderOptions.empty),
          onboardingFlowBuilder(BuilderOptions.empty),
        ],
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );

      final flowBytes = result.readerWriter.testing.readBytes(
        AssetId('apps_examples', 'assets/onboarding/flows/first_run.flow.json'),
      );
      final decoded = FlowDocumentCodec.decodeJson(utf8.decode(flowBytes));
      final welcome = decoded.states['welcome']! as ScreenFlowState;
      final branch = decoded.states['branch']! as DecisionFlowState;
      final profile = decoded.states['profile']! as SubFlowState;
      final completedWrite =
          profile.onComplete.single.stateWrites['completed']!;

      expect(welcome.on['next']?.target, 'branch');
      expect(branch.branches.single.target, 'profile');
      expect(profile.flow, 'profile_child');
      expect(
        profile.contentHash,
        FlowContentHash.computeString(childFlowJson),
      );
      expect(
        profile.input['parentIsPro'],
        isA<StateFlowValueSource>().having(
          (source) => source.key,
          'key',
          'isPro',
        ),
      );
      expect(
        decoded.outbound.subFlowResult.fields['accepted']?.ref,
        isA<EventFlowOutboundRef>().having(
          (ref) => ref.key,
          'key',
          'accepted',
        ),
      );
      expect(
        completedWrite.value,
        isA<SubFlowResultFlowValueSource>().having(
          (source) => source.key,
          'key',
          'accepted',
        ),
      );
    });

    test('invalid outbound refs fail before JSON emission', () async {
      final sources = _firstRunSourcesWithOutbound(
        includeCompletedState: false,
      );
      final logs = <LogRecord>[];
      final readerWriter = await _readerWriterWith(sources);

      final result = await testBuilders(
        [
          onboardingScreenBuilder(BuilderOptions.empty),
          onboardingFlowBuilder(BuilderOptions.empty),
        ],
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        onLog: logs.add,
      );

      expect(result.succeeded, isFalse);
      expect(
        logs.map((log) => log.message).join('\n'),
        allOf(
          contains('missingFlowStateDeclaration'),
          contains(r'$.outbound.terminalResult.fields.completed.ref'),
        ),
      );
    });

    test('missing imported generated screen descriptor fails before JSON',
        () async {
      final sources = _firstRunSources()
        ..remove('apps_examples|lib/onboarding/screens/ready.dart');
      final logs = <LogRecord>[];
      final readerWriter = await _readerWriterWith(sources);

      final result = await testBuilders(
        [
          onboardingScreenBuilder(BuilderOptions.empty),
          onboardingFlowBuilder(BuilderOptions.empty),
        ],
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        onLog: logs.add,
      );
      expect(result.succeeded, isFalse);
      expect(
        logs.map((log) => log.message).join('\n'),
        contains('missingScreenDescriptor'),
      );
    });

    test(
        'a syntax error preventing flow discovery still fails the build '
        'instead of silently skipping', () async {
      // The builder resolves with `allowSyntaxErrors: true`. A malformed token
      // severe enough that no `@OnboardingFlow` class is discovered would
      // otherwise hit the no-flow early-return and silently produce no flow
      // document — the flow the author intended simply absent. The
      // syntactic-error pass runs before that early-return, so the malformed
      // flow source is diagnosed and the build fails.
      final sources = _firstRunSources();
      sources['apps_examples|lib/onboarding/flows/first_run.dart'] = '''
import 'package:restage/restage.dart';

import '../screens/permissions.dart';
import '../screens/ready.dart';
import '../screens/welcome.dart';

part 'first_run.rsflow.g.dart';

@OnboardingFlow(id: 'first_run', version: 1, minClient: 3)
final class extends RestageFlow {
  const FirstRunFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');

    return flow(
      initial: WelcomeScreenDescriptor.ref,
      states: [
        end(done, result: {'completed': true}),
      ],
    );
  }
}
''';
      final logs = <LogRecord>[];
      final readerWriter = await _readerWriterWith(sources);

      final result = await testBuilders(
        [
          onboardingScreenBuilder(BuilderOptions.empty),
          onboardingFlowBuilder(BuilderOptions.empty),
        ],
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        onLog: logs.add,
      );

      expect(result.succeeded, isFalse);
      expect(
        logs.map((log) => log.message).join('\n'),
        contains('[malformedSourceInput]'),
      );
    });

    test('local OnboardingFlow annotation lookalikes are ignored', () async {
      const source = '''
part 'first_run.rsflow.g.dart';

@OnboardingFlow(id: 'first_run', version: 1, minClient: 3)
final class FirstRunFlow {
  const FirstRunFlow();
}

final class OnboardingFlow {
  const OnboardingFlow({
    required this.id,
    this.version = 1,
    this.minClient = 3,
  });

  final String id;
  final int version;
  final int minClient;
}
''';
      final readerWriter = await _readerWriterWith({
        'apps_examples|lib/onboarding/flows/first_run.dart': source,
      });

      final result = await testBuilder(
        onboardingFlowBuilder(BuilderOptions.empty),
        {'apps_examples|lib/onboarding/flows/first_run.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: const {},
      );

      expect(result.succeeded, isTrue);
    });

    test('string-target graph edges are not emitted in generated JSON',
        () async {
      final sources = _firstRunSources();
      final readerWriter = await _readerWriterWith(sources);

      final result = await testBuilders(
        [
          onboardingScreenBuilder(BuilderOptions.empty),
          onboardingFlowBuilder(BuilderOptions.empty),
        ],
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );

      final flowBytes = result.readerWriter.testing.readBytes(
        AssetId('apps_examples', 'assets/onboarding/flows/first_run.flow.json'),
      );
      final json = jsonDecode(utf8.decode(flowBytes)) as Map<String, Object?>;
      final states = json['states']! as Map<String, Object?>;
      for (final state in states.values.cast<Map<String, Object?>>()) {
        if (state['kind'] != 'screen') continue;
        final transitions = state['on']! as Map<String, Object?>;
        for (final transition
            in transitions.values.cast<Map<String, Object?>>()) {
          expect(states, contains(transition['target']));
        }
      }
    });

    test('emits action contracts and result predicates for action transitions',
        () async {
      final sources = _actionTransitionSources();
      final readerWriter = await _readerWriterWith(sources);

      final result = await testBuilders(
        [
          onboardingScreenBuilder(BuilderOptions.empty),
          onboardingFlowBuilder(BuilderOptions.empty),
        ],
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );

      final flowBytes = result.readerWriter.testing.readBytes(
        AssetId('apps_examples', 'assets/onboarding/flows/first_run.flow.json'),
      );
      final generated = result.readerWriter.testing.readString(
        AssetId(
          'apps_examples',
          'lib/onboarding/flows/first_run.rsflow.g.dart',
        ),
      );
      final json = jsonDecode(utf8.decode(flowBytes)) as Map<String, Object?>;
      final actions = json['actions']! as Map<String, Object?>;
      final states = json['states']! as Map<String, Object?>;
      final welcome = states['welcome']! as Map<String, Object?>;
      final on = welcome['on']! as Map<String, Object?>;
      final transition = on['next']! as Map<String, Object?>;

      expect(actions.keys, ['requestNotifications']);
      expect(actions, isNot(contains('unusedAction')));
      expect(
        actions['requestNotifications'],
        containsPair('argsSchemaHash', _emptyObjectArgsHash),
      );
      expect(
        actions['requestNotifications'],
        containsPair('resultSchemaHash', _boolResultHash),
      );
      expect(
        actions['requestNotifications'],
        containsPair('argsSchema', {
          'kind': 'object',
          'fields': <String, Object?>{},
        }),
      );
      expect(
        actions['requestNotifications'],
        containsPair('resultSchema', {'kind': 'bool'}),
      );
      expect(
        generated,
        allOf(
          contains('argsSchema: const FlowActionSchema.object({})'),
          contains('resultSchema: const FlowActionSchema.bool()'),
        ),
      );
      expect(
        transition,
        containsPair('resultPredicate', {
          'kind': 'boolEquals',
          'value': true,
        }),
      );
    });

    test('declared unused actions get real generated descriptors and hashes',
        () async {
      final sources = _actionTransitionSources();
      final readerWriter = await _readerWriterWith(sources);

      final result = await testBuilders(
        [
          onboardingScreenBuilder(BuilderOptions.empty),
          onboardingFlowBuilder(BuilderOptions.empty),
        ],
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );

      final generated = result.readerWriter.testing.readString(
        AssetId(
          'apps_examples',
          'lib/onboarding/flows/first_run.rsflow.g.dart',
        ),
      );

      expect(
        generated,
        allOf(
          contains('static final FlowActionDescriptor<void, bool> '
              'unusedActionDescriptor'),
          contains("actionName: 'unusedAction'"),
          contains('argsSchema: const FlowActionSchema.object({})'),
          contains('resultSchema: const FlowActionSchema.bool()'),
          isNot(contains(_zeroHash)),
        ),
      );
    });

    test('authored idempotent actions preserve contract and binding metadata',
        () async {
      final sources = _actionTransitionSources(
        actionRef: "FlowActionRef<void, bool>('requestNotifications', "
            'idempotent: true)',
      );
      final readerWriter = await _readerWriterWith(sources);

      final result = await testBuilders(
        [
          onboardingScreenBuilder(BuilderOptions.empty),
          onboardingFlowBuilder(BuilderOptions.empty),
        ],
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );

      final flowBytes = result.readerWriter.testing.readBytes(
        AssetId('apps_examples', 'assets/onboarding/flows/first_run.flow.json'),
      );
      final generated = result.readerWriter.testing.readString(
        AssetId(
          'apps_examples',
          'lib/onboarding/flows/first_run.rsflow.g.dart',
        ),
      );
      final json = jsonDecode(utf8.decode(flowBytes)) as Map<String, Object?>;
      final actions = json['actions']! as Map<String, Object?>;

      expect(
        actions['requestNotifications'],
        containsPair('idempotent', true),
      );
      expect(
        generated,
        allOf(
          contains('idempotent: true'),
          contains('idempotent: requestNotificationsDescriptor.idempotent'),
        ),
      );
    });

    test('Dart enum action schemas fail closed before object lowering',
        () async {
      final cases = <String, String>{
        'argument': '''
  static const choosePermission =
      FlowActionRef<PermissionChoice, bool>('choosePermission');
''',
        'result': '''
  static const choosePermission =
      FlowActionRef<void, PermissionChoice>('choosePermission');
''',
      };

      for (final entry in cases.entries) {
        final sources = _actionTransitionSources(
          extraActionRefs: entry.value,
          resultClass: 'enum PermissionChoice { granted, denied }',
        );
        final logs = <LogRecord>[];
        final readerWriter = await _readerWriterWith(sources);

        final result = await testBuilders(
          [
            onboardingScreenBuilder(BuilderOptions.empty),
            onboardingFlowBuilder(BuilderOptions.empty),
          ],
          sources,
          rootPackage: 'apps_examples',
          readerWriter: readerWriter,
          onLog: logs.add,
        );

        expect(result.succeeded, isFalse, reason: entry.key);
        expect(
          logs.map((log) => log.message).join('\n'),
          allOf(
            contains('unsupported action schema enum type'),
            contains('PermissionChoice'),
          ),
          reason: entry.key,
        );
      }
    });

    test('unsupported action schema field names fail closed', () async {
      final cases = <String, String>{
        'non-ASCII': 'mañana',
        'dollar': r'$granted',
      };

      for (final entry in cases.entries) {
        final sources = _actionTransitionSources(
          extraActionRefs: '''
  static const badSchema =
      FlowActionRef<void, PermissionResult>('badSchema');
''',
          resultClass: '''
final class PermissionResult {
  const PermissionResult({required this.${entry.value}});
  final bool ${entry.value};
}
''',
        );
        final logs = <LogRecord>[];
        final readerWriter = await _readerWriterWith(sources);

        final result = await testBuilders(
          [
            onboardingScreenBuilder(BuilderOptions.empty),
            onboardingFlowBuilder(BuilderOptions.empty),
          ],
          sources,
          rootPackage: 'apps_examples',
          readerWriter: readerWriter,
          onLog: logs.add,
        );

        expect(result.succeeded, isFalse, reason: entry.key);
        final joined = logs.map((log) => log.message).join('\n');
        if (entry.key == 'non-ASCII') {
          // A non-ASCII character in an identifier is a genuine syntax error,
          // so the never-emit-wrong syntactic-error floor catches it before the
          // action-schema validator runs. Still fail-closed — just an earlier,
          // more fundamental diagnostic than the schema-string one.
          expect(
            joined,
            allOf(
              contains('malformedSourceInput'),
              contains('Illegal character'),
            ),
            reason: entry.key,
          );
        } else {
          expect(
            joined,
            allOf(
              contains('unsupported action schema string'),
              contains('ASCII'),
              contains(entry.value),
            ),
            reason: entry.key,
          );
        }
      }
    });

    test('non-void action args fail until generated decoders exist', () async {
      final cases = <String, ({String actionRef, String source})>{
        'list': (
          actionRef:
              "FlowActionRef<List<List<int>>, bool>('requestNotifications')",
          source: '',
        ),
        'object': (
          actionRef: "FlowActionRef<ActionArgs, bool>('requestNotifications')",
          source: '''
final class ActionArgs {
  const ActionArgs({required this.count});
  final int count;
}
''',
        ),
      };

      for (final entry in cases.entries) {
        final sources = _actionTransitionSources(
          actionRef: entry.value.actionRef,
          resultClass: entry.value.source,
        );
        final logs = <LogRecord>[];
        final readerWriter = await _readerWriterWith(sources);

        final result = await testBuilders(
          [
            onboardingScreenBuilder(BuilderOptions.empty),
            onboardingFlowBuilder(BuilderOptions.empty),
          ],
          sources,
          rootPackage: 'apps_examples',
          readerWriter: readerWriter,
          onLog: logs.add,
        );

        expect(result.succeeded, isFalse, reason: entry.key);
        expect(
          logs.map((log) => log.message).join('\n'),
          allOf(
            contains('unsupported action argument type'),
            contains(
              'Generated action argument decoders support only '
              'FlowActionRef<void, R>',
            ),
          ),
          reason: entry.key,
        );
      }
    });

    test('negated bool action result predicates lower to boolEquals false',
        () async {
      final sources = _actionTransitionSources(
        resultPredicate: '(result) => !result',
      );
      final readerWriter = await _readerWriterWith(sources);

      final result = await testBuilders(
        [
          onboardingScreenBuilder(BuilderOptions.empty),
          onboardingFlowBuilder(BuilderOptions.empty),
        ],
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );

      final flowBytes = result.readerWriter.testing.readBytes(
        AssetId('apps_examples', 'assets/onboarding/flows/first_run.flow.json'),
      );
      final json = jsonDecode(utf8.decode(flowBytes)) as Map<String, Object?>;
      final states = json['states']! as Map<String, Object?>;
      final welcome = states['welcome']! as Map<String, Object?>;
      final on = welcome['on']! as Map<String, Object?>;
      final transition = on['next']! as Map<String, Object?>;

      expect(
        transition,
        containsPair('resultPredicate', {
          'kind': 'boolEquals',
          'value': false,
        }),
      );
    });

    test(
        'lowercase subflow alias still fails with public-safe unsupported '
        'runtime feature diagnostic', () async {
      final sources = _actionSources();
      final logs = <LogRecord>[];
      final readerWriter = await _readerWriterWith(sources);

      final result = await testBuilders(
        [
          onboardingScreenBuilder(BuilderOptions.empty),
          onboardingFlowBuilder(BuilderOptions.empty),
        ],
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        onLog: logs.add,
      );
      expect(result.succeeded, isFalse);
      expect(
        logs.map((log) => log.message).join('\n'),
        allOf(
          contains('unsupportedFlowRuntimeFeature'),
          isNot(contains('unsupportedInPhase1')),
          isNot(contains('run is not lowered')),
          isNot(contains('result is not lowered')),
          contains('subflow'),
        ),
      );
    });

    test('unsupported action result predicates fail deterministically',
        () async {
      final sources = _actionTransitionSources(
        resultPredicate: '(result) => result == true',
      );
      final logs = <LogRecord>[];
      final readerWriter = await _readerWriterWith(sources);

      final result = await testBuilders(
        [
          onboardingScreenBuilder(BuilderOptions.empty),
          onboardingFlowBuilder(BuilderOptions.empty),
        ],
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        onLog: logs.add,
      );

      expect(result.succeeded, isFalse);
      expect(
        logs.map((log) => log.message).join('\n'),
        allOf(
          contains('unsupported action result predicate'),
          contains('(result) => result == true'),
        ),
      );
    });

    test('mutable object predicate fields fail contract lowering', () async {
      final sources = _actionTransitionSources(
        actionRef:
            "FlowActionRef<void, NotificationResult>('requestNotifications')",
        resultPredicate: '(result) => result.granted',
        resultClass: '''
final class NotificationResult {
  NotificationResult({required this.granted});
  bool granted;
}
''',
      );
      final logs = <LogRecord>[];
      final readerWriter = await _readerWriterWith(sources);

      final result = await testBuilders(
        [
          onboardingScreenBuilder(BuilderOptions.empty),
          onboardingFlowBuilder(BuilderOptions.empty),
        ],
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        onLog: logs.add,
      );

      expect(result.succeeded, isFalse);
      expect(
        logs.map((log) => log.message).join('\n'),
        allOf(
          contains('unsupported action result predicate'),
          contains('result.granted'),
        ),
      );
    });

    test('duplicate action wire ids fail before lowering', () async {
      final sources = _actionTransitionSources(
        extraActionRefs: '''
  static const duplicateNotifications =
      FlowActionRef<void, bool>('requestNotifications');
''',
      );
      final logs = <LogRecord>[];
      final readerWriter = await _readerWriterWith(sources);

      final result = await testBuilders(
        [
          onboardingScreenBuilder(BuilderOptions.empty),
          onboardingFlowBuilder(BuilderOptions.empty),
        ],
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        onLog: logs.add,
      );

      expect(result.succeeded, isFalse);
      expect(
        logs.map((log) => log.message).join('\n'),
        allOf(
          contains('duplicate action id "requestNotifications"'),
          contains('duplicateNotifications'),
        ),
      );
    });

    test('invalid result field names fail closed before output', () async {
      final sources =
          _singleScreenFlowSources(resultExpression: "{'class': true}");
      final logs = <LogRecord>[];
      final readerWriter = await _readerWriterWith(sources);

      final result = await testBuilders(
        [
          onboardingScreenBuilder(BuilderOptions.empty),
          onboardingFlowBuilder(BuilderOptions.empty),
        ],
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        onLog: logs.add,
      );

      expect(result.succeeded, isFalse);
      expect(
        logs.map((log) => log.message).join('\n'),
        allOf(
          contains('unsupported result key'),
          contains('class'),
        ),
      );
    });

    test('result keys that collide with Object members fail closed', () async {
      for (final key in ['toString', 'runtimeType', 'hashCode']) {
        final sources =
            _singleScreenFlowSources(resultExpression: "{'$key': true}");
        final logs = <LogRecord>[];
        final readerWriter = await _readerWriterWith(sources);

        final result = await testBuilders(
          [
            onboardingScreenBuilder(BuilderOptions.empty),
            onboardingFlowBuilder(BuilderOptions.empty),
          ],
          sources,
          rootPackage: 'apps_examples',
          readerWriter: readerWriter,
          onLog: logs.add,
        );

        expect(result.succeeded, isFalse, reason: key);
        expect(
          logs.map((log) => log.message).join('\n'),
          allOf(
            contains('unsupported result key'),
            contains(key),
          ),
          reason: key,
        );
      }
    });

    for (final entry in <String, String>{
      'non-literal map': 'payload',
      'non-string key': '{1: true}',
      'collection if': "{if (true) 'completed': true}",
      'collection spread': "{...{'completed': true}}",
      'null value': "{'completed': null}",
      'double value': "{'completed': 1.5}",
      'unsupported expression value': "{'completed': DateTime.now()}",
    }.entries) {
      test('unsupported result payload ${entry.key} fails closed', () async {
        final sources = _singleScreenFlowSources(
          resultExpression: entry.value,
          extraBuildFlowStatements: entry.key == 'non-literal map'
              ? "final payload = {'completed': true};"
              : '',
        );
        final logs = <LogRecord>[];
        final readerWriter = await _readerWriterWith(sources);

        final result = await testBuilders(
          [
            onboardingScreenBuilder(BuilderOptions.empty),
            onboardingFlowBuilder(BuilderOptions.empty),
          ],
          sources,
          rootPackage: 'apps_examples',
          readerWriter: readerWriter,
          onLog: logs.add,
        );

        expect(result.succeeded, isFalse, reason: entry.key);
        expect(
          logs.map((log) => log.message).join('\n'),
          contains('unsupported result literal'),
          reason: entry.key,
        );
      });
    }

    test('nested and list terminal result fields fail before decoder emission',
        () async {
      final cases = <String, String>{
        'list': "{'completed': true, 'scores': [1, 2]}",
        'map': "{'completed': true, 'profile': {'id': 'abc'}}",
      };

      for (final entry in cases.entries) {
        final sources = _singleScreenFlowSources(
          resultExpression: entry.value,
        );
        final logs = <LogRecord>[];
        final readerWriter = await _readerWriterWith(sources);

        final result = await testBuilders(
          [
            onboardingScreenBuilder(BuilderOptions.empty),
            onboardingFlowBuilder(BuilderOptions.empty),
          ],
          sources,
          rootPackage: 'apps_examples',
          readerWriter: readerWriter,
          onLog: logs.add,
        );

        expect(result.succeeded, isFalse, reason: entry.key);
        expect(
          logs.map((log) => log.message).join('\n'),
          contains('unsupported result literal'),
          reason: entry.key,
        );
      }
    });

    for (final entry in <String, String>{
      'top-level duplicate': "{'completed': true, 'completed': false}",
      'nested duplicate':
          "{'profile': {'completed': true, 'completed': false}}",
    }.entries) {
      test('duplicate result map key ${entry.key} fails closed', () async {
        final sources = _singleScreenFlowSources(
          resultExpression: entry.value,
        );
        final logs = <LogRecord>[];
        final readerWriter = await _readerWriterWith(sources);

        final result = await testBuilders(
          [
            onboardingScreenBuilder(BuilderOptions.empty),
            onboardingFlowBuilder(BuilderOptions.empty),
          ],
          sources,
          rootPackage: 'apps_examples',
          readerWriter: readerWriter,
          onLog: logs.add,
        );

        expect(result.succeeded, isFalse, reason: entry.key);
        expect(
          logs.map((log) => log.message).join('\n'),
          contains('duplicate result key'),
          reason: entry.key,
        );
      });
    }

    test('duplicate screen states fail closed before JSON emission', () async {
      final sources = _duplicateScreenSources();
      final logs = <LogRecord>[];
      final readerWriter = await _readerWriterWith(sources);

      final result = await testBuilders(
        [
          onboardingScreenBuilder(BuilderOptions.empty),
          onboardingFlowBuilder(BuilderOptions.empty),
        ],
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        onLog: logs.add,
      );

      expect(result.succeeded, isFalse);
      expect(
        logs.map((log) => log.message).join('\n'),
        allOf(
          contains('duplicate screen state'),
          contains('welcome'),
        ),
      );
    });

    test('local event aliases fail closed instead of using alias name',
        () async {
      final sources = _eventAliasSources();
      final logs = <LogRecord>[];
      final readerWriter = await _readerWriterWith(sources);

      final result = await testBuilders(
        [
          onboardingScreenBuilder(BuilderOptions.empty),
          onboardingFlowBuilder(BuilderOptions.empty),
        ],
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        onLog: logs.add,
      );

      expect(result.succeeded, isFalse);
      expect(
        logs.map((log) => log.message).join('\n'),
        allOf(
          contains('Expected a static OnboardingEvent field reference'),
          contains('nextEvent'),
        ),
      );
    });

    test('non-event const descriptors fail closed in transition events',
        () async {
      final sources = _eventExpressionSources('WelcomeScreenDescriptor.ref');
      final logs = <LogRecord>[];
      final readerWriter = await _readerWriterWith(sources);

      final result = await testBuilders(
        [
          onboardingScreenBuilder(BuilderOptions.empty),
          onboardingFlowBuilder(BuilderOptions.empty),
        ],
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        onLog: logs.add,
      );

      expect(result.succeeded, isFalse);
      expect(
        logs.map((log) => log.message).join('\n'),
        allOf(
          contains('Expected a static OnboardingEvent field reference'),
          contains('WelcomeScreenDescriptor.ref'),
        ),
      );
    });

    test('local OnboardingEvent lookalikes fail closed in transition events',
        () async {
      final sources = _shadowEventSources();
      final logs = <LogRecord>[];
      final readerWriter = await _readerWriterWith(sources);

      final result = await testBuilders(
        [
          onboardingScreenBuilder(BuilderOptions.empty),
          onboardingFlowBuilder(BuilderOptions.empty),
        ],
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        onLog: logs.add,
      );

      expect(result.succeeded, isFalse);
      expect(
        logs.map((log) => log.message).join('\n'),
        allOf(
          contains('Expected a static OnboardingEvent field reference'),
          contains('fake'),
        ),
      );
    });

    test('unresolved screen event references fail closed', () async {
      final sources = _eventExpressionSources('WelcomeScreen.nxt');
      final logs = <LogRecord>[];
      final readerWriter = await _readerWriterWith(sources);

      final result = await testBuilders(
        [
          onboardingScreenBuilder(BuilderOptions.empty),
          onboardingFlowBuilder(BuilderOptions.empty),
        ],
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        onLog: logs.add,
      );

      expect(result.succeeded, isFalse);
      expect(
        logs.map((log) => log.message).join('\n'),
        allOf(
          contains('Expected a static OnboardingEvent field reference'),
          contains('WelcomeScreen.nxt'),
        ),
      );
    });

    test('states list collection control fails closed before JSON emission',
        () async {
      final cases = <String, String>{
        'if': '''
        if (true)
          screen(WelcomeScreenDescriptor.ref)
              .on(WelcomeScreen.next)
              .goTo(done),
        ''',
        'for': '''
        for (final item in [1])
          screen(WelcomeScreenDescriptor.ref)
              .on(WelcomeScreen.next)
              .goTo(done),
        ''',
        'spread': '''
        ...[
          screen(WelcomeScreenDescriptor.ref)
              .on(WelcomeScreen.next)
              .goTo(done),
        ],
        ''',
      };

      for (final entry in cases.entries) {
        final sources = _statesSource(entry.value);
        final logs = <LogRecord>[];
        final readerWriter = await _readerWriterWith(sources);

        final result = await testBuilders(
          [
            onboardingScreenBuilder(BuilderOptions.empty),
            onboardingFlowBuilder(BuilderOptions.empty),
          ],
          sources,
          rootPackage: 'apps_examples',
          readerWriter: readerWriter,
          onLog: logs.add,
        );

        expect(result.succeeded, isFalse, reason: entry.key);
        expect(
          logs.map((log) => log.message).join('\n'),
          contains('unsupported states list entry'),
          reason: entry.key,
        );
      }
    });

    test('duplicate or multiple end states fail closed before JSON emission',
        () async {
      final cases = <String, String>{
        'duplicate end id': '''
        screen(WelcomeScreenDescriptor.ref)
            .on(WelcomeScreen.next)
            .goTo(done),
        end(done, result: {'completed': true}),
        end(done, result: {'completed': false}),
        ''',
        'multiple end ids': '''
        screen(WelcomeScreenDescriptor.ref)
            .on(WelcomeScreen.next)
            .goTo(done),
        end(done, result: {'completed': true}),
        end(cancelled, result: {'completed': false}),
        ''',
      };

      for (final entry in cases.entries) {
        final sources = _statesSource(
          entry.value,
          extraEndStates: "final cancelled = endState('cancelled');",
        );
        final logs = <LogRecord>[];
        final readerWriter = await _readerWriterWith(sources);

        final result = await testBuilders(
          [
            onboardingScreenBuilder(BuilderOptions.empty),
            onboardingFlowBuilder(BuilderOptions.empty),
          ],
          sources,
          rootPackage: 'apps_examples',
          readerWriter: readerWriter,
          onLog: logs.add,
        );

        expect(result.succeeded, isFalse, reason: entry.key);
        expect(
          logs.map((log) => log.message).join('\n'),
          contains('exactly one end state'),
          reason: entry.key,
        );
      }
    });
  });
}

Matcher _canonicalFirstRunFlowJson() => predicate<List<int>>(
      (bytes) {
        final source = utf8.decode(bytes);
        final decoded = FlowDocumentCodec.decodeJson(source);
        expect(
          source,
          utf8.decode(FlowDocumentCodec.encodeCanonicalJson(decoded)),
        );
        expect(decoded.flow, 'first_run');
        expect(decoded.initial, 'welcome');
        expect(
          decoded.states.values.map((state) => state.kind.wireName),
          everyElement(anyOf('screen', 'end')),
        );
        return true;
      },
      'canonical first_run.flow.json',
    );

const _emptyObjectArgsHash = 'sha256:590f015bf5e877b53e3501b7e12ad48'
    'a11158d4c5b696f9a82593c4f3272411a';
const _boolResultHash = 'sha256:b381695502a4099cf3610d182b471a25'
    '62086e5e8bdb11f4426f63ba512542b3';
const _zeroHash = 'sha256:00000000000000000000000000000000'
    '00000000000000000000000000000000';

Future<TestReaderWriter> _readerWriterWith(Map<String, String> sources) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  for (final entry in sources.entries) {
    readerWriter.testing.writeString(AssetId.parse(entry.key), entry.value);
  }
  return readerWriter;
}

Future<void> _assertGeneratedResultDecoderRuns(String generated) async {
  final dir = Directory('.dart_tool/onboarding_flow_builder_test')
    ..createSync(recursive: true);
  final script = File('${dir.path}/generated_decoder_check.dart');
  final source = generated.replaceFirst("part of 'first_run.dart';", '''
import 'package:restage/src/flow/flow_descriptors.dart';
''');
  script.writeAsStringSync('''
$source

void main() {
  final decoded = FirstRunFlowDescriptor.ref.decodeResult({'completed': true});
  if (!decoded.completed) {
    throw StateError('canonical result did not decode');
  }
  _rejects(<String, Object?>{});
  _rejects(<String, Object?>{'completed': 'yes'});
  _rejects(<String, Object?>{'completed': true, 'extra': true});
}

void _rejects(Map<String, Object?> result) {
  try {
    FirstRunFlowDescriptor.ref.decodeResult(result);
  } on FormatException {
    return;
  }
  throw StateError('accepted invalid result: \$result');
}
''');

  final result = await Process.run(
    'dart',
    [script.path],
    workingDirectory: Directory.current.path,
  );
  expect(
    result.exitCode,
    0,
    reason: '${result.stdout}\n${result.stderr}',
  );
}

Map<String, String> _firstRunSources() => {
      'apps_examples|lib/onboarding/screens/welcome.dart':
          _screenSource('welcome', 'WelcomeScreen', 'next'),
      'apps_examples|lib/onboarding/screens/permissions.dart':
          _screenSource('permissions', 'PermissionsScreen', 'next'),
      'apps_examples|lib/onboarding/screens/ready.dart':
          _screenSource('ready', 'ReadyScreen', 'start'),
      'apps_examples|lib/onboarding/flows/first_run.dart': '''
import 'package:restage/restage.dart';

import '../screens/permissions.dart';
import '../screens/ready.dart';
import '../screens/welcome.dart';

part 'first_run.rsflow.g.dart';

@OnboardingFlow(id: 'first_run', version: 1, minClient: 3)
final class FirstRunFlow extends RestageFlow {
  const FirstRunFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');

    return flow(
      initial: WelcomeScreenDescriptor.ref,
      states: [
        screen(WelcomeScreenDescriptor.ref)
            .on(WelcomeScreen.next)
            .goTo(PermissionsScreenDescriptor.ref),
        screen(PermissionsScreenDescriptor.ref)
            .on(PermissionsScreen.next)
            .goTo(ReadyScreenDescriptor.ref),
        screen(ReadyScreenDescriptor.ref)
            .on(ReadyScreen.start)
            .goTo(done),
        end(done, result: {'completed': true}),
      ],
    );
  }
}
''',
    };

Map<String, String> _firstRunSourcesWithOutbound({
  bool includeCompletedState = true,
}) =>
    {
      'apps_examples|lib/onboarding/screens/welcome.dart':
          _screenSource('welcome', 'WelcomeScreen', 'next'),
      'apps_examples|lib/onboarding/screens/permissions.dart':
          _screenSource('permissions', 'PermissionsScreen', 'next'),
      'apps_examples|lib/onboarding/screens/ready.dart':
          _screenSource('ready', 'ReadyScreen', 'start'),
      'apps_examples|lib/onboarding/flows/first_run.dart': '''
import 'package:restage/restage.dart';

import '../screens/permissions.dart';
import '../screens/ready.dart';
import '../screens/welcome.dart';

part 'first_run.rsflow.g.dart';

@OnboardingFlow(id: 'first_run', version: 1, minClient: 3)
final class FirstRunFlow extends RestageFlow {
  const FirstRunFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');

    return flow(
      initial: WelcomeScreenDescriptor.ref,
      flowState: const {
        ${includeCompletedState ? "'completed': FlowStateDeclaration(type: FlowDataType.bool, classification: FlowStateClassification.exportable)," : ""}
        'secret': FlowStateDeclaration(
          type: FlowDataType.string,
          classification: FlowStateClassification.internal,
        ),
      },
      outbound: const FlowOutboundDeclarations(
        terminalResult: FlowOutboundPayloadDeclaration(
          fields: {
            'completed': FlowOutboundField(
              type: FlowDataType.bool,
              ref: StateFlowOutboundRef(key: 'completed'),
            ),
          },
        ),
        customEvents: {
          'analyticsTap': FlowOutboundPayloadDeclaration(
            fields: {
              'ctaId': FlowOutboundField(
                type: FlowDataType.string,
                ref: EventFlowOutboundRef(key: 'ctaId'),
              ),
            },
          ),
        },
      ),
      states: [
        screen(WelcomeScreenDescriptor.ref)
            .on(WelcomeScreen.next)
            .goTo(PermissionsScreenDescriptor.ref),
        screen(PermissionsScreenDescriptor.ref)
            .on(PermissionsScreen.next)
            .goTo(ReadyScreenDescriptor.ref),
        screen(ReadyScreenDescriptor.ref)
            .on(ReadyScreen.start)
            .goTo(done),
        end(done, result: {'completed': true, 'secret': 'do-not-emit'}),
      ],
    );
  }
}
''',
    };

Map<String, String> _paywallStepFlowSources() => {
      'apps_examples|lib/onboarding/screens/welcome.dart':
          _screenSource('welcome', 'WelcomeScreen', 'next'),
      'apps_examples|lib/onboarding/flows/first_run.dart': '''
import 'package:restage/restage.dart';

import '../screens/welcome.dart';

part 'first_run.rsflow.g.dart';

@OnboardingFlow(id: 'first_run', version: 1, minClient: 3)
final class FirstRunFlow extends RestageFlow {
  const FirstRunFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');

    return flow(
      initial: WelcomeScreenDescriptor.ref,
      states: [
        screen(WelcomeScreenDescriptor.ref)
            .on(WelcomeScreen.next)
            .goTo(paywallScreen('serene')),
        screen(paywallScreen('serene'))
            .on(PaywallFlowEvents.purchase)
            .goTo(done),
        end(done, result: {'completed': true}),
      ],
    );
  }
}
''',
    };

Map<String, String> _graphFlowSources(String childFlowJson) => {
      'apps_examples|lib/onboarding/screens/welcome.dart':
          _screenSource('welcome', 'WelcomeScreen', 'next'),
      'apps_examples|assets/onboarding/flows/profile_child.flow.json':
          childFlowJson,
      'apps_examples|lib/onboarding/flows/first_run.dart': '''
import 'package:restage/restage.dart';

import '../screens/welcome.dart';

part 'first_run.rsflow.g.dart';

@OnboardingFlow(id: 'first_run', version: 1, minClient: 3)
final class FirstRunFlow extends RestageFlow {
  const FirstRunFlow();

  @override
  FlowDef buildFlow() {
    final branch = flowNode('branch');
    final profile = flowNode('profile');
    final done = endState('done');

    return flow(
      initial: WelcomeScreenDescriptor.ref,
      flowState: const {
        'isPro': FlowStateDeclaration(
          type: FlowDataType.bool,
          classification: FlowStateClassification.internal,
          defaultValue: true,
        ),
        'completed': FlowStateDeclaration(
          type: FlowDataType.bool,
          classification: FlowStateClassification.exportable,
        ),
      },
      outbound: const FlowOutboundDeclarations(
        subFlowResult: FlowOutboundPayloadDeclaration(
          fields: {
            'accepted': FlowOutboundField(
              type: FlowDataType.bool,
              ref: EventFlowOutboundRef(key: 'accepted'),
            ),
          },
        ),
        terminalResult: FlowOutboundPayloadDeclaration(
          fields: {
            'completed': FlowOutboundField(
              type: FlowDataType.bool,
              ref: StateFlowOutboundRef(key: 'completed'),
            ),
          },
        ),
      ),
      states: [
        screen(WelcomeScreenDescriptor.ref)
            .on(WelcomeScreen.next)
            .goTo(branch),
        decision(
          branch,
          branches: [
            flowBranch(
              when: const FlowBranchPredicate(
                fields: {
                  'isPro': EqualsFlowPredicateCondition(
                    value: LiteralFlowValueSource(
                      type: FlowDataType.bool,
                      value: true,
                    ),
                  ),
                },
              ),
              target: profile,
            ),
          ],
          defaultBranch: flowBranchTarget(
            done,
            stateWrites: const {
              'completed': FlowStateWrite(
                type: FlowDataType.bool,
                value: LiteralFlowValueSource(
                  type: FlowDataType.bool,
                  value: false,
                ),
              ),
            },
          ),
        ),
        subFlow(
          profile,
          flow: profileChildFlow,
          input: const {
            'parentIsPro': StateFlowValueSource(key: 'isPro'),
          },
          onComplete: [
            flowBranch(
              when: const FlowBranchPredicate(
                fields: {
                  'accepted': EqualsFlowPredicateCondition(
                    value: LiteralFlowValueSource(
                      type: FlowDataType.bool,
                      value: true,
                    ),
                  ),
                },
              ),
              target: done,
              stateWrites: const {
                'completed': FlowStateWrite(
                  type: FlowDataType.bool,
                  value: SubFlowResultFlowValueSource(key: 'accepted'),
                ),
              },
            ),
          ],
          defaultBranch: flowBranchTarget(
            done,
            stateWrites: const {
              'completed': FlowStateWrite(
                type: FlowDataType.bool,
                value: LiteralFlowValueSource(
                  type: FlowDataType.bool,
                  value: false,
                ),
              ),
            },
          ),
        ),
        end(done, result: {}),
      ],
    );
  }
}

const profileChildFlow = OnboardingFlowRef<Map<String, Object?>>(
  id: 'profile_child',
  version: 1,
  minClient: 3,
  decodeResult: _decodeProfileChild,
);

Map<String, Object?> _decodeProfileChild(Map<String, Object?> result) {
  return result;
}
''',
    };

String _profileChildFlowJson() {
  const document = FlowDocument(
    flow: 'profile_child',
    version: 1,
    schemaVersion: 1,
    minClient: 3,
    initial: 'branch',
    flowState: {
      'parentIsPro': FlowStateDeclaration(
        type: FlowDataType.bool,
        classification: FlowStateClassification.internal,
        defaultValue: false,
      ),
    },
    outbound: FlowOutboundDeclarations(
      terminalResult: FlowOutboundPayloadDeclaration(
        fields: {
          'accepted': FlowOutboundField(
            type: FlowDataType.bool,
            ref: EventFlowOutboundRef(key: 'accepted'),
          ),
        },
      ),
    ),
    screenArtifacts: {},
    states: {
      'branch': DecisionFlowState(
        branches: [
          FlowBranch(
            when: FlowBranchPredicate(
              fields: {
                'parentIsPro': EqualsFlowPredicateCondition(
                  value: LiteralFlowValueSource(
                    type: FlowDataType.bool,
                    value: true,
                  ),
                ),
              },
            ),
            target: 'accepted',
          ),
        ],
        defaultBranch: FlowBranchTarget(target: 'declined'),
      ),
      'accepted': EndFlowState(result: {'accepted': true}),
      'declined': EndFlowState(result: {'accepted': false}),
    },
  );
  FlowDocumentValidation.checkValid(document);
  return utf8.decode(FlowDocumentCodec.encodeCanonicalJson(document));
}

Map<String, String> _actionSources() => {
      'apps_examples|lib/onboarding/screens/welcome.dart':
          _screenSource('welcome', 'WelcomeScreen', 'next'),
      'apps_examples|lib/onboarding/flows/first_run.dart': '''
import 'package:restage/restage.dart';

import '../screens/welcome.dart';

part 'first_run.rsflow.g.dart';

@OnboardingFlow(id: 'first_run', version: 1, minClient: 3)
final class FirstRunFlow extends RestageFlow {
  static const requestNotifications =
      FlowActionRef<void, bool>('requestNotifications');

  const FirstRunFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');

    return flow(
      initial: WelcomeScreenDescriptor.ref,
      states: [
        screen(WelcomeScreenDescriptor.ref)
            .on(WelcomeScreen.next)
            .run(requestNotifications)
            .result((result) => result)
            .action(requestNotifications)
            .decision((event) => true)
            .subFlow(nestedFlow)
            .subflow(nestedFlow)
            .goTo(done),
        end(done, result: {'completed': true}),
      ],
    );
  }
}

const nestedFlow = OnboardingFlowRef<void>(
  id: 'nested',
  version: 1,
  minClient: 3,
  decodeResult: _decodeNested,
);

void _decodeNested(Map<String, Object?> result) {}

extension LaterPhaseTransitionApi<T> on ScreenEventTransitionBuilder<T> {
  ScreenEventTransitionBuilder<T> action<I, O>(FlowActionRef<I, O> action) {
    return this;
  }

  ScreenEventTransitionBuilder<T> decision(bool Function(T event) predicate) {
    return this;
  }

  ScreenEventTransitionBuilder<T> subFlow<R>(OnboardingFlowRef<R> flow) {
    return this;
  }

  ScreenEventTransitionBuilder<T> subflow<R>(OnboardingFlowRef<R> flow) {
    return this;
  }
}
''',
    };

Map<String, String> _actionTransitionSources({
  String actionRef = "FlowActionRef<void, bool>('requestNotifications')",
  String extraActionRefs = '',
  String resultPredicate = '(result) => result',
  String resultClass = '',
}) =>
    {
      'apps_examples|lib/onboarding/screens/welcome.dart':
          _screenSource('welcome', 'WelcomeScreen', 'next'),
      'apps_examples|lib/onboarding/flows/first_run.dart': '''
import 'package:restage/restage.dart';

import '../screens/welcome.dart';

part 'first_run.rsflow.g.dart';

@OnboardingFlow(id: 'first_run', version: 1, minClient: 3)
final class FirstRunFlow extends RestageFlow {
  static const requestNotifications =
      $actionRef;
  static const unusedAction =
      FlowActionRef<void, bool>('unusedAction');
$extraActionRefs

  const FirstRunFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');

    return flow(
      initial: WelcomeScreenDescriptor.ref,
      states: [
        screen(WelcomeScreenDescriptor.ref)
            .on(WelcomeScreen.next)
            .run(requestNotifications)
            .result($resultPredicate)
            .goTo(done),
        end(done, result: {'completed': true}),
      ],
    );
  }
}

$resultClass
''',
    };

Map<String, String> _singleScreenFlowSources({
  required String resultExpression,
  String extraBuildFlowStatements = '',
}) =>
    {
      'apps_examples|lib/onboarding/screens/welcome.dart':
          _screenSource('welcome', 'WelcomeScreen', 'next'),
      'apps_examples|lib/onboarding/flows/first_run.dart': '''
import 'package:restage/restage.dart';

import '../screens/welcome.dart';

part 'first_run.rsflow.g.dart';

@OnboardingFlow(id: 'first_run', version: 1, minClient: 3)
final class FirstRunFlow extends RestageFlow {
  const FirstRunFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');
    $extraBuildFlowStatements

    return flow(
      initial: WelcomeScreenDescriptor.ref,
      states: [
        screen(WelcomeScreenDescriptor.ref)
            .on(WelcomeScreen.next)
            .goTo(done),
        end(done, result: $resultExpression),
      ],
    );
  }
}
''',
    };

Map<String, String> _duplicateScreenSources() => {
      'apps_examples|lib/onboarding/screens/welcome.dart':
          _screenSource('welcome', 'WelcomeScreen', 'next'),
      'apps_examples|lib/onboarding/flows/first_run.dart': '''
import 'package:restage/restage.dart';

import '../screens/welcome.dart';

part 'first_run.rsflow.g.dart';

@OnboardingFlow(id: 'first_run', version: 1, minClient: 3)
final class FirstRunFlow extends RestageFlow {
  const FirstRunFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');

    return flow(
      initial: WelcomeScreenDescriptor.ref,
      states: [
        screen(WelcomeScreenDescriptor.ref)
            .on(WelcomeScreen.next)
            .goTo(done),
        screen(WelcomeScreenDescriptor.ref)
            .on(WelcomeScreen.next)
            .goTo(done),
        end(done, result: {'completed': true}),
      ],
    );
  }
}
''',
    };

Map<String, String> _eventAliasSources() => {
      'apps_examples|lib/onboarding/screens/welcome.dart':
          _screenSource('welcome', 'WelcomeScreen', 'next'),
      'apps_examples|lib/onboarding/flows/first_run.dart': '''
import 'package:restage/restage.dart';

import '../screens/welcome.dart';

part 'first_run.rsflow.g.dart';

@OnboardingFlow(id: 'first_run', version: 1, minClient: 3)
final class FirstRunFlow extends RestageFlow {
  const FirstRunFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');
    final nextEvent = WelcomeScreen.next;

    return flow(
      initial: WelcomeScreenDescriptor.ref,
      states: [
        screen(WelcomeScreenDescriptor.ref)
            .on(nextEvent)
            .goTo(done),
        end(done, result: {'completed': true}),
      ],
    );
  }
}
''',
    };

Map<String, String> _eventExpressionSources(String eventExpression) => {
      'apps_examples|lib/onboarding/screens/welcome.dart':
          _screenSource('welcome', 'WelcomeScreen', 'next'),
      'apps_examples|lib/onboarding/flows/first_run.dart': '''
import 'package:restage/restage.dart';

import '../screens/welcome.dart';

part 'first_run.rsflow.g.dart';

@OnboardingFlow(id: 'first_run', version: 1, minClient: 3)
final class FirstRunFlow extends RestageFlow {
  const FirstRunFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');

    return flow(
      initial: WelcomeScreenDescriptor.ref,
      states: [
        screen(WelcomeScreenDescriptor.ref)
            .on($eventExpression)
            .goTo(done),
        end(done, result: {'completed': true}),
      ],
    );
  }
}
''',
    };

Map<String, String> _shadowEventSources() => {
      'apps_examples|lib/onboarding/screens/welcome.dart':
          _screenSource('welcome', 'WelcomeScreen', 'next'),
      'apps_examples|lib/onboarding/flows/first_run.dart': '''
import 'package:restage/restage.dart';

import '../screens/welcome.dart';

part 'first_run.rsflow.g.dart';

@OnboardingFlow(id: 'first_run', version: 1, minClient: 3)
final class FirstRunFlow extends RestageFlow {
  static const fake = OnboardingEvent<void>('fake');

  const FirstRunFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');

    return flow(
      initial: WelcomeScreenDescriptor.ref,
      states: [
        screen(WelcomeScreenDescriptor.ref)
            .on(fake)
            .goTo(done),
        end(done, result: {'completed': true}),
      ],
    );
  }
}

final class OnboardingEvent<T> {
  const OnboardingEvent(this.id);
  final String id;
}
''',
    };

Map<String, String> _statesSource(
  String states, {
  String extraEndStates = '',
}) =>
    {
      'apps_examples|lib/onboarding/screens/welcome.dart':
          _screenSource('welcome', 'WelcomeScreen', 'next'),
      'apps_examples|lib/onboarding/flows/first_run.dart': '''
import 'package:restage/restage.dart';

import '../screens/welcome.dart';

part 'first_run.rsflow.g.dart';

@OnboardingFlow(id: 'first_run', version: 1, minClient: 3)
final class FirstRunFlow extends RestageFlow {
  const FirstRunFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');
    $extraEndStates

    return flow(
      initial: WelcomeScreenDescriptor.ref,
      states: [
$states
      ],
    );
  }
}
''',
    };

String _screenSource(String id, String className, String eventName) => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part '$id.rsscreen.g.dart';

@OnboardingSource(id: '$id')
final class $className extends StatelessWidget {
  static const $eventName = OnboardingEvent<void>('$eventName');

  const $className({super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: ElevatedButton(
          onPressed: onboardingEvent($eventName),
          child: const Text('$className'),
        ),
      );
}
''';
