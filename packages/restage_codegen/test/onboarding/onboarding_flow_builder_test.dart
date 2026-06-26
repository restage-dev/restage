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
      // A flow with no host-seedable key emits no seed builder.
      expect(generated, isNot(contains('implements FlowSeed')));
      expect(generated, isNot(contains('FirstRunSeed')));
      final jsonBytes = result.readerWriter.testing.readBytes(
        AssetId('apps_examples', 'assets/onboarding/flows/first_run.flow.json'),
      );
      expect(jsonBytes, _canonicalFirstRunFlowJson());
    });

    test('emits a typed FlowSeed builder exposing only host-seedable keys',
        () async {
      final sources = _hostSeedSources();
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
          contains('final class FirstRunSeed implements FlowSeed'),
          contains('const FirstRunSeed({'),
          contains('this.isReturningUser'),
          contains('final bool? isReturningUser;'),
          contains('Map<String, Object?> toFlowState()'),
          contains("if (isReturningUser != null) 'isReturningUser'"),
          // The non-seedable 'tier' key must not be a seed parameter.
          isNot(contains('tier')),
        ),
      );
    });

    test('a host-seedable key that is not a safe Dart identifier fails closed',
        () async {
      // The wire identifier rule admits hyphens and reserved/Object/method
      // names, but a seed key is interpolated into the generated seed builder
      // as a Dart field name, constructor parameter, and map key. An unsafe key
      // must fail the build loudly (the dev renames it), never emit broken Dart.
      for (final badKey in <String>[
        'ab-test', // hyphen — invalid Dart identifier
        'return', // reserved word
        'runtimeType', // Object member — field/getter clash
        'toFlowState', // clashes with the generated method
      ]) {
        final sources = _hostSeedSources(seedKey: badKey);
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

        expect(result.succeeded, isFalse, reason: badKey);
        final joined = logs.map((log) => log.message).join('\n');
        expect(
          joined,
          allOf(
            contains('host-seedable'),
            contains(badKey),
          ),
          reason: badKey,
        );
      }
    });

    test(
        'a host-seedable key equal to the generated seed class name fails '
        'closed', () async {
      // 'FirstRunSeed' is a valid Dart identifier, but it equals the generated
      // seed builder class name, so as a field it would collide with the class.
      final sources = _hostSeedSources(seedKey: 'FirstRunSeed');
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
          contains('host-seedable'),
          contains('FirstRunSeed'),
        ),
      );
    });

    test(
        'an author class colliding with the generated seed builder fails '
        'closed', () async {
      final sources = _hostSeedSources(
        extraDeclarations: 'final class FirstRunSeed {}',
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
          contains('generatedSymbolCollision'),
          contains('FirstRunSeed'),
        ),
      );
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

  group('OnboardingFlowBuilder branching', () {
    Future<FlowDocument> buildBranchingDoc(Map<String, String> sources) async {
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
      final bytes = result.readerWriter.testing.readBytes(
        AssetId(
          'apps_examples',
          'assets/onboarding/flows/branching.flow.json',
        ),
      );
      return FlowDocumentCodec.decodeJson(utf8.decode(bytes));
    }

    Future<String> buildBranchingFailure(Map<String, String> sources) async {
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
      return logs.map((log) => log.message).join('\n');
    }

    test('chained .on() lowers to one screen state with a multi-key on map',
        () async {
      final doc = await buildBranchingDoc(_forkSources());
      final goal = doc.states['goal']! as ScreenFlowState;
      expect(goal.on.keys, containsAll(<String>['sleep', 'focus']));
      expect(goal.on['sleep']!.target, 'rating');
      expect(goal.on['focus']!.target, 'rating');
    });

    test('.write() lowers to a LiteralFlowValueSource state write', () async {
      final doc = await buildBranchingDoc(_forkSources());
      final sleep = (doc.states['goal']! as ScreenFlowState).on['sleep']!
          as GotoFlowTransition;
      final write = sleep.stateWrites['goal']!;
      expect(write.type, FlowDataType.string);
      final value = write.value as LiteralFlowValueSource;
      expect(value.type, FlowDataType.string);
      expect(value.value, 'sleep');
      final focus = (doc.states['goal']! as ScreenFlowState).on['focus']!
          as GotoFlowTransition;
      expect(
        (focus.stateWrites['goal']!.value as LiteralFlowValueSource).value,
        'focus',
      );
    });

    test('.capture() lowers to a reserved-value EventFlowValueSource write',
        () async {
      final doc = await buildBranchingDoc(_forkSources());
      final submit = (doc.states['rating']! as ScreenFlowState).on['submit']!
          as GotoFlowTransition;
      final write = submit.stateWrites['rating']!;
      expect(write.type, FlowDataType.int);
      final value = write.value as EventFlowValueSource;
      // Capture reads the reserved event-value key; the flow-state slot is
      // 'rating'.
      expect(value.key, kCapturedEventValueKey);
      expect(value.path, isEmpty);
    });

    test('an action-gate transition carries a state write', () async {
      final doc = await buildBranchingDoc(_actionWriteSources());
      final next = (doc.states['welcome']! as ScreenFlowState).on['next']!
          as ActionFlowTransition;
      expect(next.action, 'requestNotifications');
      final write = next.stateWrites['granted']!;
      expect(write.type, FlowDataType.bool);
      expect((write.value as LiteralFlowValueSource).value, true);
    });

    test('a forking flow emits canonical, round-trippable JSON', () async {
      final readerWriter = await _readerWriterWith(_forkSources());
      final result = await testBuilders(
        [
          onboardingScreenBuilder(BuilderOptions.empty),
          onboardingFlowBuilder(BuilderOptions.empty),
        ],
        _forkSources(),
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      final bytes = result.readerWriter.testing.readBytes(
        AssetId(
          'apps_examples',
          'assets/onboarding/flows/branching.flow.json',
        ),
      );
      final source = utf8.decode(bytes);
      final decoded = FlowDocumentCodec.decodeJson(source);
      expect(
        source,
        utf8.decode(FlowDocumentCodec.encodeCanonicalJson(decoded)),
      );
    });

    test('the forking flow matches its committed byte-golden', () async {
      final readerWriter = await _readerWriterWith(_forkSources());
      final result = await testBuilders(
        [
          onboardingScreenBuilder(BuilderOptions.empty),
          onboardingFlowBuilder(BuilderOptions.empty),
        ],
        _forkSources(),
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      final actual = result.readerWriter.testing.readString(
        AssetId(
          'apps_examples',
          'assets/onboarding/flows/branching.flow.json',
        ),
      );
      final regen = Platform.environment['REGEN_CODEGEN_GOLDENS'] == '1';
      final golden = File('test/fixtures/goldens/branching.flow.json');
      if (regen) {
        golden.writeAsStringSync(actual);
      }
      expect(
        actual,
        golden.readAsStringSync(),
        reason: 'Forking-flow golden drift. Regenerate with '
            'REGEN_CODEGEN_GOLDENS=1 only when intended.',
      );
    });

    test('two .on() for the same event on one screen fails closed', () async {
      final messages = await buildBranchingFailure(_duplicateEventSources());
      expect(messages, contains('duplicate'));
      expect(messages, contains('sleep'));
    });

    test('a capture targeting an undeclared flowState key fails closed',
        () async {
      final messages = await buildBranchingFailure(_undeclaredKeySources());
      expect(messages, contains('flowState'));
    });

    test('a capture on a non-scalar event fails closed', () async {
      final messages = await buildBranchingFailure(_nonScalarCaptureSources());
      expect(messages, contains('scalar'));
    });

    test(
        'a .write() whose literal type mismatches the declared flowState '
        'type fails closed', () async {
      final messages = await buildBranchingFailure(_typeMismatchWriteSources());
      expect(messages, contains("write('goal')"));
      expect(messages, contains('produces string'));
      expect(messages, contains("flowState declares 'goal' as int"));
    });

    test(
        'a .capture() whose event type mismatches the declared flowState '
        'type fails closed', () async {
      final messages =
          await buildBranchingFailure(_typeMismatchCaptureSources());
      expect(messages, contains("capture('rating')"));
      expect(messages, contains('produces int'));
      expect(messages, contains("flowState declares 'rating' as string"));
    });
  });

  group('OnboardingFlowBuilder predicate sugar', () {
    Future<FlowDocument> buildDoc(Map<String, String> sources) async {
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
      final bytes = result.readerWriter.testing.readBytes(
        AssetId(
          'apps_examples',
          'assets/onboarding/flows/decision_route.flow.json',
        ),
      );
      return FlowDocumentCodec.decodeJson(utf8.decode(bytes));
    }

    Future<String> buildFailure(Map<String, String> sources) async {
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
      return logs.map((log) => log.message).join('\n');
    }

    FlowBranchPredicate whenOf(FlowDocument doc, int branchIndex) {
      final decision = doc.states['route']! as DecisionFlowState;
      return decision.branches[branchIndex].when;
    }

    test('state().equals() lowers byte-identically to the raw wire predicate',
        () async {
      final doc = await buildDoc(_sugarOperatorsSources());
      // branch 0: state('goal').equals('sleep')
      expect(
        _canonicalWhen(whenOf(doc, 0)),
        _canonicalWhen(
          const FlowBranchPredicate(
            fields: {
              'goal': EqualsFlowPredicateCondition(
                value: LiteralFlowValueSource(
                  type: FlowDataType.string,
                  value: 'sleep',
                ),
              ),
            },
          ),
        ),
      );
    });

    test('every operator + state-ref RHS lowers byte-identically to raw wire',
        () async {
      final doc = await buildDoc(_sugarOperatorsSources());
      // branch 1: state('goal').notEquals('focus')
      expect(
        _canonicalWhen(whenOf(doc, 1)),
        _canonicalWhen(
          const FlowBranchPredicate(
            fields: {
              'goal': NotEqualsFlowPredicateCondition(
                value: LiteralFlowValueSource(
                  type: FlowDataType.string,
                  value: 'focus',
                ),
              ),
            },
          ),
        ),
      );
      // branch 2: state('rating').atLeast(4)
      expect(
        _canonicalWhen(whenOf(doc, 2)),
        _canonicalWhen(
          const FlowBranchPredicate(
            fields: {
              'rating': GreaterThanOrEqualsFlowPredicateCondition(
                value: LiteralFlowValueSource(
                  type: FlowDataType.int,
                  value: 4,
                ),
              ),
            },
          ),
        ),
      );
      // branch 3: state('goal').oneOf(['sleep', 'focus'])
      expect(
        _canonicalWhen(whenOf(doc, 3)),
        _canonicalWhen(
          const FlowBranchPredicate(
            fields: {
              'goal': InFlowPredicateCondition(
                values: [
                  LiteralFlowValueSource(
                    type: FlowDataType.string,
                    value: 'sleep',
                  ),
                  LiteralFlowValueSource(
                    type: FlowDataType.string,
                    value: 'focus',
                  ),
                ],
              ),
            },
          ),
        ),
      );
      // branch 4: state('goal').isSet()
      expect(
        _canonicalWhen(whenOf(doc, 4)),
        _canonicalWhen(
          const FlowBranchPredicate(
            fields: {'goal': ExistsFlowPredicateCondition(exists: true)},
          ),
        ),
      );
      // branch 5: state('goal').equals(state('preferred')) — state-ref RHS
      expect(
        _canonicalWhen(whenOf(doc, 5)),
        _canonicalWhen(
          const FlowBranchPredicate(
            fields: {
              'goal': EqualsFlowPredicateCondition(
                value: StateFlowValueSource(key: 'preferred'),
              ),
            },
          ),
        ),
      );
      // branch 7: state('rating').atLeast(-5) — a negative int literal must
      // lower the same as the runtime leg (both legs accept negative ints).
      expect(
        _canonicalWhen(whenOf(doc, 7)),
        _canonicalWhen(
          const FlowBranchPredicate(
            fields: {
              'rating': GreaterThanOrEqualsFlowPredicateCondition(
                value: LiteralFlowValueSource(
                  type: FlowDataType.int,
                  value: -5,
                ),
              ),
            },
          ),
        ),
      );
      // branch 8: state('rating').atLeast((4)) — a parenthesized literal lowers
      // the same as a bare literal (the runtime sees the unwrapped value).
      expect(
        _canonicalWhen(whenOf(doc, 8)),
        _canonicalWhen(
          const FlowBranchPredicate(
            fields: {
              'rating': GreaterThanOrEqualsFlowPredicateCondition(
                value: LiteralFlowValueSource(type: FlowDataType.int, value: 4),
              ),
            },
          ),
        ),
      );
      // branch 9: state('goal').equals('sl' 'eep') — adjacent string literals
      // fold to one string, the same as the runtime leg.
      expect(
        _canonicalWhen(whenOf(doc, 9)),
        _canonicalWhen(
          const FlowBranchPredicate(
            fields: {
              'goal': EqualsFlowPredicateCondition(
                value: LiteralFlowValueSource(
                  type: FlowDataType.string,
                  value: 'sleep',
                ),
              ),
            },
          ),
        ),
      );
      // branch 10: state('rating').atLeast(-(5)) — a parenthesized negative
      // int lowers the same as a bare negative (operand parens are unwrapped).
      expect(
        _canonicalWhen(whenOf(doc, 10)),
        _canonicalWhen(
          const FlowBranchPredicate(
            fields: {
              'rating': GreaterThanOrEqualsFlowPredicateCondition(
                value: LiteralFlowValueSource(
                  type: FlowDataType.int,
                  value: -5,
                ),
              ),
            },
          ),
        ),
      );
    });

    test('allOf merges distinct single-field predicates into one branch',
        () async {
      final doc = await buildDoc(_sugarOperatorsSources());
      // branch 6: allOf([rating.atLeast(4), isPro.equals(true)])
      final when = whenOf(doc, 6);
      expect(when.fields.keys, containsAll(<String>['rating', 'isPro']));
      expect(when.fields, hasLength(2));
      expect(
        when.fields['rating'],
        isA<GreaterThanOrEqualsFlowPredicateCondition>(),
      );
      expect(when.fields['isPro'], isA<EqualsFlowPredicateCondition>());
    });

    test('allOf with two conditions on the same field fails closed', () async {
      final messages = await buildFailure(_allOfSameFieldSources());
      expect(messages, contains('allOf'));
      expect(messages, contains('age'));
    });

    test('a comparison operator on a non-int literal fails closed', () async {
      final messages = await buildFailure(_comparisonNonIntSources());
      expect(messages, contains('greaterThan'));
    });

    test('a non-Restage state().<op>() chain is not reinterpreted as sugar',
        () async {
      // A same-named customer `state(...)` returning a different predicate must
      // NOT be silently lowered to our wire — element resolution rejects it, so
      // it falls to the raw-constructor path and fails the build loud.
      final messages = await buildFailure(_nonSdkStateSources());
      expect(messages, contains('FlowBranchPredicate'));
    });

    test('capture -> decision -> branch lowers to the routing wire', () async {
      final doc = await buildDoc(_decisionRouteSources());
      // the captured 'goal' write on the screen transition
      final goal = (doc.states['goal']! as ScreenFlowState).on['goalChosen']!
          as GotoFlowTransition;
      final write = goal.stateWrites['goal']!;
      expect((write.value as EventFlowValueSource).key, kCapturedEventValueKey);
      // the decision routes on the captured value
      final decision = doc.states['route']! as DecisionFlowState;
      final sleep = decision.branches.single;
      final condition =
          sleep.when.fields['goal']! as EqualsFlowPredicateCondition;
      expect((condition.value as LiteralFlowValueSource).value, 'sleep');
      expect(sleep.target, 'sleep');
      expect(decision.defaultBranch.target, 'done');
    });

    test('the decision-route flow matches its committed byte-golden', () async {
      final readerWriter = await _readerWriterWith(_decisionRouteSources());
      final result = await testBuilders(
        [
          onboardingScreenBuilder(BuilderOptions.empty),
          onboardingFlowBuilder(BuilderOptions.empty),
        ],
        _decisionRouteSources(),
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      final actual = result.readerWriter.testing.readString(
        AssetId(
          'apps_examples',
          'assets/onboarding/flows/decision_route.flow.json',
        ),
      );
      final regen = Platform.environment['REGEN_CODEGEN_GOLDENS'] == '1';
      final golden = File('test/fixtures/goldens/decision_route.flow.json');
      if (regen) {
        golden.writeAsStringSync(actual);
      }
      expect(
        actual,
        golden.readAsStringSync(),
        reason: 'Decision-route golden drift. Regenerate with '
            'REGEN_CODEGEN_GOLDENS=1 only when intended.',
      );
    });
  });
}

/// Canonically encodes a branch predicate by wrapping it in an identical
/// minimal decision document, so two predicates can be compared byte-for-byte.
/// The wrapper declares the fields the convergence predicates reference so the
/// document validates.
String _canonicalWhen(FlowBranchPredicate when) {
  final document = FlowDocument(
    flow: 'conv',
    version: 1,
    schemaVersion: 1,
    minClient: 1,
    initial: 'route',
    flowState: const {
      'goal': FlowStateDeclaration(
        type: FlowDataType.string,
        classification: FlowStateClassification.internal,
      ),
      'rating': FlowStateDeclaration(
        type: FlowDataType.int,
        classification: FlowStateClassification.internal,
      ),
      'isPro': FlowStateDeclaration(
        type: FlowDataType.bool,
        classification: FlowStateClassification.internal,
      ),
      'preferred': FlowStateDeclaration(
        type: FlowDataType.string,
        classification: FlowStateClassification.internal,
      ),
    },
    screenArtifacts: const {},
    states: {
      'route': DecisionFlowState(
        branches: [FlowBranch(when: when, target: 'end')],
        defaultBranch: const FlowBranchTarget(target: 'end'),
      ),
      'end': const EndFlowState(result: {}),
    },
  );
  return utf8.decode(FlowDocumentCodec.encodeCanonicalJson(document));
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

Map<String, String> _hostSeedSources({
  String seedKey = 'isReturningUser',
  String extraDeclarations = '',
}) =>
    {
      'apps_examples|lib/onboarding/screens/welcome.dart':
          _screenSource('welcome', 'WelcomeScreen', 'next'),
      'apps_examples|lib/onboarding/screens/ready.dart':
          _screenSource('ready', 'ReadyScreen', 'start'),
      'apps_examples|lib/onboarding/flows/first_run.dart': '''
import 'package:restage/restage.dart';

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
        '$seedKey': FlowStateDeclaration(
          type: FlowDataType.bool,
          classification: FlowStateClassification.internal,
          hostSeedable: true,
        ),
        // Not host-seedable: must NOT become a seed-builder parameter.
        'tier': FlowStateDeclaration(
          type: FlowDataType.string,
          classification: FlowStateClassification.internal,
        ),
      },
      states: [
        screen(WelcomeScreenDescriptor.ref)
            .on(WelcomeScreen.next)
            .goTo(ReadyScreenDescriptor.ref),
        screen(ReadyScreenDescriptor.ref)
            .on(ReadyScreen.start)
            .goTo(done),
        end(done, result: {'completed': true}),
      ],
    );
  }
}

$extraDeclarations
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

// Test-only no-op methods named after the two builder-method names the flow
// runtime rejects (`action`, `subflow`). They exist solely so the source below
// resolves, letting the build reach the unsupported-runtime-feature guard,
// which flags those names regardless of who defines them.
extension RejectedBuilderMethodNames<T> on ScreenEventTransitionBuilder<T> {
  ScreenEventTransitionBuilder<T> action<I, O>(FlowActionRef<I, O> action) {
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

String _eventsScreenSource(
  String id,
  String className,
  Map<String, String> events,
) {
  final fields = events.entries
      .map(
        (e) => '  static const ${e.key} = '
            "OnboardingEvent<${e.value}>('${e.key}');",
      )
      .join('\n');
  final first = events.keys.first;
  return '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part '$id.rsscreen.g.dart';

@OnboardingSource(id: '$id')
final class $className extends StatelessWidget {
$fields

  const $className({super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: ElevatedButton(
          onPressed: onboardingEvent($className.$first),
          child: const Text('$className'),
        ),
      );
}
''';
}

Map<String, String> _forkSources() => {
      'apps_examples|lib/onboarding/screens/goal.dart': _eventsScreenSource(
        'goal',
        'GoalScreen',
        const {'sleep': 'void', 'focus': 'void'},
      ),
      'apps_examples|lib/onboarding/screens/rating.dart': _eventsScreenSource(
        'rating',
        'RatingScreen',
        const {'submit': 'int'},
      ),
      'apps_examples|lib/onboarding/flows/branching.dart': '''
import 'package:restage/restage.dart';

import '../screens/goal.dart';
import '../screens/rating.dart';

part 'branching.rsflow.g.dart';

@FlowSource(id: 'branching', version: 1)
final class BranchingFlow extends RestageFlow {
  const BranchingFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');

    return flow(
      initial: GoalScreenDescriptor.ref,
      flowState: const {
        'goal': FlowStateDeclaration(
          type: FlowDataType.string,
          classification: FlowStateClassification.internal,
        ),
        'rating': FlowStateDeclaration(
          type: FlowDataType.int,
          classification: FlowStateClassification.internal,
        ),
      },
      states: [
        screen(GoalScreenDescriptor.ref)
            .on(GoalScreen.sleep)
            .write('goal', 'sleep')
            .goTo(RatingScreenDescriptor.ref)
            .on(GoalScreen.focus)
            .write('goal', 'focus')
            .goTo(RatingScreenDescriptor.ref),
        screen(RatingScreenDescriptor.ref)
            .on(RatingScreen.submit)
            .capture('rating')
            .goTo(done),
        end(done, result: {'completed': true}),
      ],
    );
  }
}
''',
    };

Map<String, String> _decisionRouteSources() => {
      'apps_examples|lib/onboarding/screens/goal.dart': _eventsScreenSource(
        'goal',
        'GoalScreen',
        const {'goalChosen': 'String'},
      ),
      'apps_examples|lib/onboarding/screens/sleep.dart': _eventsScreenSource(
        'sleep',
        'SleepScreen',
        const {'ack': 'void'},
      ),
      'apps_examples|lib/onboarding/flows/decision_route.dart': '''
import 'package:restage/restage.dart';

import '../screens/goal.dart';
import '../screens/sleep.dart';

part 'decision_route.rsflow.g.dart';

@FlowSource(id: 'decision_route', version: 1)
final class DecisionRouteFlow extends RestageFlow {
  const DecisionRouteFlow();

  @override
  FlowDef buildFlow() {
    final route = flowNode('route');
    final done = endState('done');

    return flow(
      initial: GoalScreenDescriptor.ref,
      flowState: const {
        'goal': FlowStateDeclaration(
          type: FlowDataType.string,
          classification: FlowStateClassification.internal,
        ),
      },
      states: [
        screen(GoalScreenDescriptor.ref)
            .on(GoalScreen.goalChosen)
            .capture('goal')
            .goTo(route),
        decision(
          route,
          branches: [
            flowBranch(
              when: state('goal').equals('sleep'),
              target: SleepScreenDescriptor.ref,
            ),
          ],
          defaultBranch: flowBranchTarget(done),
        ),
        screen(SleepScreenDescriptor.ref).on(SleepScreen.ack).goTo(done),
        end(done, result: {}),
      ],
    );
  }
}
''',
    };

Map<String, String> _sugarOperatorsSources() => {
      'apps_examples|lib/onboarding/screens/start.dart': _eventsScreenSource(
        'start',
        'StartScreen',
        const {'begin': 'void'},
      ),
      'apps_examples|lib/onboarding/flows/decision_route.dart': '''
import 'package:restage/restage.dart';

import '../screens/start.dart';

part 'decision_route.rsflow.g.dart';

@FlowSource(id: 'decision_route', version: 1)
final class DecisionRouteFlow extends RestageFlow {
  const DecisionRouteFlow();

  @override
  FlowDef buildFlow() {
    final route = flowNode('route');
    final done = endState('done');

    return flow(
      initial: StartScreenDescriptor.ref,
      flowState: const {
        'goal': FlowStateDeclaration(
          type: FlowDataType.string,
          classification: FlowStateClassification.internal,
        ),
        'rating': FlowStateDeclaration(
          type: FlowDataType.int,
          classification: FlowStateClassification.internal,
        ),
        'isPro': FlowStateDeclaration(
          type: FlowDataType.bool,
          classification: FlowStateClassification.internal,
        ),
        'preferred': FlowStateDeclaration(
          type: FlowDataType.string,
          classification: FlowStateClassification.internal,
        ),
      },
      states: [
        screen(StartScreenDescriptor.ref).on(StartScreen.begin).goTo(route),
        decision(
          route,
          branches: [
            flowBranch(when: state('goal').equals('sleep'), target: done),
            flowBranch(when: state('goal').notEquals('focus'), target: done),
            flowBranch(when: state('rating').atLeast(4), target: done),
            flowBranch(
              when: state('goal').oneOf(['sleep', 'focus']),
              target: done,
            ),
            flowBranch(when: state('goal').isSet(), target: done),
            flowBranch(
              when: state('goal').equals(state('preferred')),
              target: done,
            ),
            flowBranch(
              when: allOf([
                state('rating').atLeast(4),
                state('isPro').equals(true),
              ]),
              target: done,
            ),
            flowBranch(when: state('rating').atLeast(-5), target: done),
            flowBranch(when: state('rating').atLeast((4)), target: done),
            flowBranch(when: state('goal').equals('sl' 'eep'), target: done),
            flowBranch(when: state('rating').atLeast(-(5)), target: done),
          ],
          defaultBranch: flowBranchTarget(done),
        ),
        end(done, result: {}),
      ],
    );
  }
}
''',
    };

Map<String, String> _allOfSameFieldSources() => {
      'apps_examples|lib/onboarding/screens/start.dart': _eventsScreenSource(
        'start',
        'StartScreen',
        const {'begin': 'void'},
      ),
      'apps_examples|lib/onboarding/flows/decision_route.dart': '''
import 'package:restage/restage.dart';

import '../screens/start.dart';

part 'decision_route.rsflow.g.dart';

@FlowSource(id: 'decision_route', version: 1)
final class DecisionRouteFlow extends RestageFlow {
  const DecisionRouteFlow();

  @override
  FlowDef buildFlow() {
    final route = flowNode('route');
    final done = endState('done');

    return flow(
      initial: StartScreenDescriptor.ref,
      flowState: const {
        'age': FlowStateDeclaration(
          type: FlowDataType.int,
          classification: FlowStateClassification.internal,
        ),
      },
      states: [
        screen(StartScreenDescriptor.ref).on(StartScreen.begin).goTo(route),
        decision(
          route,
          branches: [
            flowBranch(
              when: allOf([
                state('age').atLeast(18),
                state('age').atMost(65),
              ]),
              target: done,
            ),
          ],
          defaultBranch: flowBranchTarget(done),
        ),
        end(done, result: {}),
      ],
    );
  }
}
''',
    };

Map<String, String> _comparisonNonIntSources() => {
      'apps_examples|lib/onboarding/screens/start.dart': _eventsScreenSource(
        'start',
        'StartScreen',
        const {'begin': 'void'},
      ),
      'apps_examples|lib/onboarding/flows/decision_route.dart': '''
import 'package:restage/restage.dart';

import '../screens/start.dart';

part 'decision_route.rsflow.g.dart';

@FlowSource(id: 'decision_route', version: 1)
final class DecisionRouteFlow extends RestageFlow {
  const DecisionRouteFlow();

  @override
  FlowDef buildFlow() {
    final route = flowNode('route');
    final done = endState('done');

    return flow(
      initial: StartScreenDescriptor.ref,
      flowState: const {
        'age': FlowStateDeclaration(
          type: FlowDataType.int,
          classification: FlowStateClassification.internal,
        ),
      },
      states: [
        screen(StartScreenDescriptor.ref).on(StartScreen.begin).goTo(route),
        decision(
          route,
          branches: [
            flowBranch(when: state('age').greaterThan('old'), target: done),
          ],
          defaultBranch: flowBranchTarget(done),
        ),
        end(done, result: {}),
      ],
    );
  }
}
''',
    };

Map<String, String> _nonSdkStateSources() => {
      'apps_examples|lib/onboarding/screens/start.dart': _eventsScreenSource(
        'start',
        'StartScreen',
        const {'begin': 'void'},
      ),
      'apps_examples|lib/onboarding/flows/decision_route.dart': '''
import 'package:restage/restage.dart' hide state;

import '../screens/start.dart';

part 'decision_route.rsflow.g.dart';

// A customer construct that happens to spell `state(...).equals(...)` but is
// NOT the Restage SDK sugar.
class _CustomRef {
  const _CustomRef();
  FlowBranchPredicate equals(Object value) =>
      const FlowBranchPredicate(fields: {});
}

_CustomRef state(String key) => const _CustomRef();

@FlowSource(id: 'decision_route', version: 1)
final class DecisionRouteFlow extends RestageFlow {
  const DecisionRouteFlow();

  @override
  FlowDef buildFlow() {
    final route = flowNode('route');
    final done = endState('done');

    return flow(
      initial: StartScreenDescriptor.ref,
      flowState: const {
        'goal': FlowStateDeclaration(
          type: FlowDataType.string,
          classification: FlowStateClassification.internal,
        ),
      },
      states: [
        screen(StartScreenDescriptor.ref).on(StartScreen.begin).goTo(route),
        decision(
          route,
          branches: [
            flowBranch(when: state('goal').equals('sleep'), target: done),
          ],
          defaultBranch: flowBranchTarget(done),
        ),
        end(done, result: {}),
      ],
    );
  }
}
''',
    };

Map<String, String> _actionWriteSources() => {
      'apps_examples|lib/onboarding/screens/welcome.dart':
          _screenSource('welcome', 'WelcomeScreen', 'next'),
      'apps_examples|lib/onboarding/flows/branching.dart': '''
import 'package:restage/restage.dart';

import '../screens/welcome.dart';

part 'branching.rsflow.g.dart';

@FlowSource(id: 'branching', version: 1)
final class BranchingFlow extends RestageFlow {
  static const requestNotifications =
      FlowActionRef<void, bool>('requestNotifications');

  const BranchingFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');

    return flow(
      initial: WelcomeScreenDescriptor.ref,
      flowState: const {
        'granted': FlowStateDeclaration(
          type: FlowDataType.bool,
          classification: FlowStateClassification.internal,
        ),
      },
      states: [
        screen(WelcomeScreenDescriptor.ref)
            .on(WelcomeScreen.next)
            .run(requestNotifications)
            .result((result) => result)
            .write('granted', true)
            .goTo(done),
        end(done, result: {'completed': true}),
      ],
    );
  }
}
''',
    };

Map<String, String> _duplicateEventSources() => {
      'apps_examples|lib/onboarding/screens/goal.dart': _eventsScreenSource(
        'goal',
        'GoalScreen',
        const {'sleep': 'void'},
      ),
      'apps_examples|lib/onboarding/screens/rating.dart': _eventsScreenSource(
        'rating',
        'RatingScreen',
        const {'submit': 'void'},
      ),
      'apps_examples|lib/onboarding/flows/branching.dart': '''
import 'package:restage/restage.dart';

import '../screens/goal.dart';
import '../screens/rating.dart';

part 'branching.rsflow.g.dart';

@FlowSource(id: 'branching', version: 1)
final class BranchingFlow extends RestageFlow {
  const BranchingFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');

    return flow(
      initial: GoalScreenDescriptor.ref,
      states: [
        screen(GoalScreenDescriptor.ref)
            .on(GoalScreen.sleep)
            .goTo(RatingScreenDescriptor.ref)
            .on(GoalScreen.sleep)
            .goTo(done),
        screen(RatingScreenDescriptor.ref)
            .on(RatingScreen.submit)
            .goTo(done),
        end(done, result: {'completed': true}),
      ],
    );
  }
}
''',
    };

Map<String, String> _undeclaredKeySources() => {
      'apps_examples|lib/onboarding/screens/rating.dart': _eventsScreenSource(
        'rating',
        'RatingScreen',
        const {'submit': 'int'},
      ),
      'apps_examples|lib/onboarding/flows/branching.dart': '''
import 'package:restage/restage.dart';

import '../screens/rating.dart';

part 'branching.rsflow.g.dart';

@FlowSource(id: 'branching', version: 1)
final class BranchingFlow extends RestageFlow {
  const BranchingFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');

    return flow(
      initial: RatingScreenDescriptor.ref,
      states: [
        screen(RatingScreenDescriptor.ref)
            .on(RatingScreen.submit)
            .capture('rating')
            .goTo(done),
        end(done, result: {'completed': true}),
      ],
    );
  }
}
''',
    };

Map<String, String> _nonScalarCaptureSources() => {
      'apps_examples|lib/onboarding/screens/welcome.dart':
          _screenSource('welcome', 'WelcomeScreen', 'next'),
      'apps_examples|lib/onboarding/flows/branching.dart': '''
import 'package:restage/restage.dart';

import '../screens/welcome.dart';

part 'branching.rsflow.g.dart';

@FlowSource(id: 'branching', version: 1)
final class BranchingFlow extends RestageFlow {
  const BranchingFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');

    return flow(
      initial: WelcomeScreenDescriptor.ref,
      flowState: const {
        'x': FlowStateDeclaration(
          type: FlowDataType.string,
          classification: FlowStateClassification.internal,
        ),
      },
      states: [
        screen(WelcomeScreenDescriptor.ref)
            .on(WelcomeScreen.next)
            .capture('x')
            .goTo(done),
        end(done, result: {'completed': true}),
      ],
    );
  }
}
''',
    };

Map<String, String> _typeMismatchWriteSources() => {
      'apps_examples|lib/onboarding/screens/goal.dart': _eventsScreenSource(
        'goal',
        'GoalScreen',
        const {'sleep': 'void'},
      ),
      'apps_examples|lib/onboarding/flows/branching.dart': '''
import 'package:restage/restage.dart';

import '../screens/goal.dart';

part 'branching.rsflow.g.dart';

@FlowSource(id: 'branching', version: 1)
final class BranchingFlow extends RestageFlow {
  const BranchingFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');

    return flow(
      initial: GoalScreenDescriptor.ref,
      // 'goal' is declared int, but the screen writes a String literal into it.
      flowState: const {
        'goal': FlowStateDeclaration(
          type: FlowDataType.int,
          classification: FlowStateClassification.internal,
        ),
      },
      states: [
        screen(GoalScreenDescriptor.ref)
            .on(GoalScreen.sleep)
            .write('goal', 'sleep')
            .goTo(done),
        end(done, result: {'completed': true}),
      ],
    );
  }
}
''',
    };

Map<String, String> _typeMismatchCaptureSources() => {
      'apps_examples|lib/onboarding/screens/rating.dart': _eventsScreenSource(
        'rating',
        'RatingScreen',
        const {'submit': 'int'},
      ),
      'apps_examples|lib/onboarding/flows/branching.dart': '''
import 'package:restage/restage.dart';

import '../screens/rating.dart';

part 'branching.rsflow.g.dart';

@FlowSource(id: 'branching', version: 1)
final class BranchingFlow extends RestageFlow {
  const BranchingFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');

    return flow(
      initial: RatingScreenDescriptor.ref,
      // 'rating' is declared String, but submit is an OnboardingEvent<int>.
      flowState: const {
        'rating': FlowStateDeclaration(
          type: FlowDataType.string,
          classification: FlowStateClassification.internal,
        ),
      },
      states: [
        screen(RatingScreenDescriptor.ref)
            .on(RatingScreen.submit)
            .capture('rating')
            .goTo(done),
        end(done, result: {'completed': true}),
      ],
    );
  }
}
''',
    };
