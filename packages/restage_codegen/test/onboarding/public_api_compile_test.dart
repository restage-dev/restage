import 'dart:io';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:logging/logging.dart';
import 'package:restage_codegen/builder.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  test('public README documents the current asset-backed flow API', () {
    final readme = _readFlutterSdkReadme();

    expect(readme, isNot(contains('Pre-implementation')));
    expect(readme, isNot(contains('Restage servers')));
    expect(readme, isNot(contains("Restage.configure(apiKey: 'rs_pk_...')")));
    expect(readme, isNot(contains('use Restage servers')));
    expect(readme, contains('RestageOnboarding'));
    expect(readme, contains('OnboardingFlowRef<'));
    expect(readme, contains('FlowUnavailablePolicy'));
    expect(readme, contains('FlowActionRegistry'));
    expect(readme, contains('onComplete'));
    expect(readme, contains('AssetFlowResolver'));
    expect(readme, contains('AssetVariantResolver'));
    expect(readme, contains('missing, extra, or mistyped result'));
    expect(readme, contains('fields so bad terminal results fail closed'));
    expect(readme, isNot(contains('?? false')));
  });

  test('public SDK and codegen sources avoid internal roadmap wording', () {
    final root = _repoRoot();
    final files = [
      File('${root.path}/packages/restage/README.md'),
      ..._dartFilesIn(Directory('${root.path}/packages/restage/lib')),
      ..._dartFilesIn(Directory('${root.path}/packages/restage_codegen/lib')),
    ];
    final banned = <Pattern>[
      'Pre-implementation',
      'Restage servers',
      // Assembled from fragments so this guard does not itself carry the
      // contiguous internal tokens it scans the public source for.
      ['docs/', 'super', 'powers'].join(),
      ['cc', '2', 'cc'].join(),
      'HARD STOP',
      'internal project',
      'unsupportedInPhase1',
      RegExp(r'\bE0\b'),
      RegExp(r'\bADR\b'),
      RegExp(r'\bPhase [0-9]\b'),
      RegExp(r'\bthis release\b'),
      RegExp(r'\bfuture release\b'),
      RegExp(r'\blater release\b'),
      RegExp(r'\bcurrent release\b'),
      RegExp(r'\bfuture enhancement\b'),
      RegExp(r'\bfuture revision\b'),
      RegExp(r'\bfuture codegen\b'),
      RegExp(r'\bchapter design\b'),
      RegExp(r'\beditor-time\b'),
      RegExp(r'\bv0\b'),
      RegExp(r'\bretro\b'),
    ];

    for (final file in files) {
      final content = file.readAsStringSync();
      for (final pattern in banned) {
        expect(
          content,
          isNot(contains(pattern)),
          reason: '${file.path} contains public-bound phrase $pattern',
        );
      }
    }
  });

  test('public onboarding usage snippet compiles through SDK exports',
      () async {
    const source = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

abstract final class FirstRunFlowDescriptor {
  static final OnboardingFlowRef<FirstRunResult> ref =
      OnboardingFlowRef<FirstRunResult>(
    id: 'first_run',
    version: 1,
    minClient: 3,
    decodeResult: _decodeResult,
  );

  static FirstRunResult _decodeResult(Map<String, Object?> result) {
    if (result.length != 1 || result['completed'] is! bool) {
      throw const FormatException('Invalid first_run result.');
    }
    return FirstRunResult(completed: result['completed']! as bool);
  }
}

final class FirstRunResult {
  const FirstRunResult({required this.completed});

  final bool completed;
}

final class NotificationResult {
  const NotificationResult({required this.granted});

  final bool granted;
}

final class FirstRunActions implements FlowActionRegistry {
  FirstRunActions({
    required FlowActionHandler<void, NotificationResult>
        requestNotifications,
  }) : flowActionBindings = {
          'requestNotifications': FlowActionBinding<void, NotificationResult>(
            descriptor: requestNotificationsDescriptor,
            actionName: requestNotificationsDescriptor.actionName,
            contractVersion: requestNotificationsDescriptor.contractVersion,
            argsSchema: requestNotificationsDescriptor.argsSchema,
            resultSchema: requestNotificationsDescriptor.resultSchema,
            minClient: requestNotificationsDescriptor.minClient,
            idempotent: requestNotificationsDescriptor.idempotent,
            handler: requestNotifications,
            decodeArgs: (_) {},
            encodeResult: (value) => {'granted': value.granted},
          ),
        };

  static const FlowActionDescriptor<void, NotificationResult>
      requestNotificationsDescriptor =
      FlowActionDescriptor<void, NotificationResult>(
    actionName: 'requestNotifications',
    contractVersion: 1,
    argsSchema: FlowActionSchema.object({}),
    resultSchema: FlowActionSchema.object({
      'granted': FlowActionSchemaField(
        required: true,
        schema: FlowActionSchema.bool(),
      ),
    }),
    minClient: 3,
    idempotent: false,
  );

  @override
  final Map<String, FlowActionBinding<dynamic, dynamic>> flowActionBindings;
}

final class PublicOnboardingUsage extends StatelessWidget {
  const PublicOnboardingUsage({super.key});

  @override
  Widget build(BuildContext context) {
    return RestageOnboarding<FirstRunResult>(
      flow: FirstRunFlowDescriptor.ref,
      actions: FirstRunActions(
        requestNotifications: (_, context) async {
          final operationId = context.operationId;
          return NotificationResult(granted: operationId.isNotEmpty);
        },
      ),
      unavailable: FlowUnavailablePolicy.fallback(
        builder: (context, error) => Text(error.reason),
      ),
      onFlowUnavailable: (error) {
        final events = <RestageEvent>[
          FlowUnavailable(
            flowId: error.flowId,
            flowVersion: error.flowVersion,
            reason: error.reason,
            message: error.message,
          ),
          const FlowCustomEvent(
            flowId: 'first_run',
            flowVersion: 1,
            eventName: 'cta_tapped',
            fields: {'cta': 'notifications'},
          ),
          const FlowStarted(flowId: 'first_run', flowVersion: 1),
          const FlowCompleted(flowId: 'first_run', flowVersion: 1),
        ];
        for (final event in events) {
          event.toMap();
        }
      },
      onComplete: (result) {
        result.completed;
      },
    );
  }
}
''';

    await _assertSourcesAnalyze({
      'apps_examples|lib/onboarding/public_usage.dart': source,
    });
  });

  test('generated action bindings implement the SDK registry', () async {
    const screen = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'welcome.rsscreen.g.dart';

@OnboardingSource(id: 'welcome')
final class WelcomeScreen extends StatelessWidget {
  static const next = OnboardingEvent<void>('next');
  const WelcomeScreen({super.key});
  @override
  Widget build(BuildContext context) => const Center();
}
''';

    const flow = '''
import 'package:restage/restage.dart';

import '../screens/welcome.dart';

part 'first_run.rsflow.g.dart';

@OnboardingFlow(id: 'first_run', version: 1, minClient: 3)
final class FirstRunFlow extends RestageFlow {
  static const requestNotifications =
      FlowActionRef<void, NotificationResult>('requestNotifications');

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
            .result((result) => result.granted)
            .goTo(done),
        end(done, result: {'completed': true}),
      ],
    );
  }
}

final class NotificationResult {
  const NotificationResult({required this.granted});
  final bool granted;
}
''';

    final sources = {
      'apps_examples|lib/onboarding/screens/welcome.dart': screen,
      'apps_examples|lib/onboarding/flows/first_run.dart': flow,
    };
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    for (final entry in sources.entries) {
      readerWriter.testing.writeString(AssetId.parse(entry.key), entry.value);
    }

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
      AssetId('apps_examples', 'lib/onboarding/flows/first_run.rsflow.g.dart'),
    );
    expect(
      generated,
      allOf([
        contains('final class FirstRunActions implements FlowActionRegistry'),
        contains('required FlowActionHandler<void, NotificationResult> '
            'requestNotifications'),
        contains('final Map<String, FlowActionBinding<dynamic, dynamic>> '
            'flowActionBindings;'),
        contains("'requestNotifications': "
            'FlowActionBinding<void, NotificationResult>('),
        contains("actionName: 'requestNotifications'"),
        contains('contractVersion: 1'),
        contains('argsSchema: const FlowActionSchema.object({})'),
        // The result schema renders multi-line under the formatter (the emitted
        // descriptor is now formatted), so assert its structural pieces rather
        // than a whitespace-fragile single-line literal.
        contains('resultSchema: const FlowActionSchema.object({'),
        contains("'granted': FlowActionSchemaField("),
        contains('required: true,'),
        contains('schema: FlowActionSchema.bool(),'),
        contains('minClient: 3'),
        contains('idempotent: false'),
        contains('handler: requestNotifications'),
        contains('idempotent: requestNotificationsDescriptor.idempotent'),
        contains('decodeArgs: (_) {},'),
        contains("encodeResult: (value) => {'granted': value.granted},"),
        // The long descriptor declaration wraps across lines under the
        // formatter (type on one line, name + assignment on the next).
        contains('static final FlowActionDescriptor<void, NotificationResult>'),
        contains('requestNotificationsDescriptor ='),
        contains('descriptor: requestNotificationsDescriptor,'),
        contains('decodeResult: FirstRunFlowDescriptor._decodeResult'),
        isNot(contains('typedef FlowActionHandler')),
        isNot(
          contains('final FlowActionHandler<void, NotificationResult> '
              'requestNotifications;'),
        ),
        isNot(
          contains('FlowActionHandler<void, NotificationResult> get '
              'requestNotifications'),
        ),
      ]),
    );
    await _assertGeneratedFixtureAnalyzes(result, sources);
  });

  test('idempotent action refs compile and preserve generated metadata',
      () async {
    final sources = _actionFixtureSources(
      actionOptions: ', idempotent: true',
    );
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    for (final source in sources.entries) {
      readerWriter.testing.writeString(
        AssetId.parse(source.key),
        source.value,
      );
    }

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
      AssetId('apps_examples', 'lib/onboarding/flows/first_run.rsflow.g.dart'),
    );
    expect(
      generated,
      allOf(
        contains('idempotent: true'),
        contains('idempotent: requestNotificationsDescriptor.idempotent'),
      ),
    );
    await _assertGeneratedFixtureAnalyzes(result, sources);
  });

  test('generated public API compile fixture exposes decodeResult', () async {
    const screen = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'welcome.rsscreen.g.dart';

@OnboardingSource(id: 'welcome')
final class WelcomeScreen extends StatelessWidget {
  static const next = OnboardingEvent<void>('next');
  const WelcomeScreen({super.key});
  @override
  Widget build(BuildContext context) => const Center();
}
''';

    const flow = '''
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
        end(done, result: {'completed': true}),
      ],
    );
  }
}
''';

    final sources = {
      'apps_examples|lib/onboarding/screens/welcome.dart': screen,
      'apps_examples|lib/onboarding/flows/first_run.dart': flow,
    };
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    for (final entry in sources.entries) {
      readerWriter.testing.writeString(AssetId.parse(entry.key), entry.value);
    }

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
      AssetId('apps_examples', 'lib/onboarding/flows/first_run.rsflow.g.dart'),
    );

    expect(
      generated,
      allOf(
        contains('OnboardingFlowRef<FirstRunResult>'),
        contains('decodeResult: FirstRunFlowDescriptor._decodeResult'),
      ),
    );
    await _assertGeneratedFixtureAnalyzes(result, sources);
  });

  test('SDK action support symbol collisions reject generated output',
      () async {
    final cases = <String, String>{
      'FlowActionHandler':
          'typedef FlowActionHandler<I, O> = O Function(I input);',
      'FlowActionBinding': 'final class FlowActionBinding<I, O> { '
          'const FlowActionBinding(); }',
      'FlowActionRegistry': 'abstract interface class FlowActionRegistry {}',
      'FlowActionSchema': 'final class FlowActionSchema { '
          'const FlowActionSchema(); }',
      'FlowActionSchemaField': 'final class FlowActionSchemaField { '
          'const FlowActionSchemaField(); }',
      'FlowActionDescriptor': 'final class FlowActionDescriptor<I, O> { '
          'const FlowActionDescriptor(); }',
    };

    for (final entry in cases.entries) {
      final sources = _actionFixtureSources(extraFlowSource: entry.value);
      final logs = <LogRecord>[];
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      for (final source in sources.entries) {
        readerWriter.testing.writeString(
          AssetId.parse(source.key),
          source.value,
        );
      }

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
          contains('generatedSymbolCollision'),
          contains(entry.key),
        ),
        reason: entry.key,
      );
    }
  });

  test('invalid action wire names reject generated output', () async {
    final cases = <String, String>{
      'apostrophe': "request's",
      'leading digit': '9bad',
    };

    for (final entry in cases.entries) {
      final sources = _actionFixtureSources(actionName: entry.value);
      final logs = <LogRecord>[];
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      for (final source in sources.entries) {
        readerWriter.testing.writeString(
          AssetId.parse(source.key),
          source.value,
        );
      }

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
          contains('invalid action id'),
          contains(entry.value),
        ),
        reason: entry.key,
      );
    }
  });

  test('nested generic action args fail until generated decoders exist',
      () async {
    const screen = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'welcome.rsscreen.g.dart';

@OnboardingSource(id: 'welcome')
final class WelcomeScreen extends StatelessWidget {
  static const next = OnboardingEvent<void>('next');
  const WelcomeScreen({super.key});
  @override
  Widget build(BuildContext context) => const Center();
}
''';

    const flow = '''
import 'package:restage/restage.dart';

import '../screens/welcome.dart';

part 'first_run.rsflow.g.dart';

@OnboardingFlow(id: 'first_run', version: 1, minClient: 3)
final class FirstRunFlow extends RestageFlow {
  static const hydrateProfile =
      FlowActionRef<List<List<int>>, NotificationResult>('hydrateProfile');

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
        end(done, result: {'completed': true}),
      ],
    );
  }
}

final class NotificationResult {
  const NotificationResult({required this.granted});
  final bool granted;
}
''';

    final sources = {
      'apps_examples|lib/onboarding/screens/welcome.dart': screen,
      'apps_examples|lib/onboarding/flows/first_run.dart': flow,
    };
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    for (final entry in sources.entries) {
      readerWriter.testing.writeString(AssetId.parse(entry.key), entry.value);
    }

    final logs = <LogRecord>[];
    final result = await testBuilders(
      [
        onboardingScreenBuilder(BuilderOptions.empty),
        onboardingFlowBuilder(BuilderOptions.empty),
      ],
      sources,
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
      onLog: logs.add,
    );

    expect(result.succeeded, isFalse);
    expect(
      logs.map((log) => log.message).join('\n'),
      allOf(
        contains('unsupported action argument type'),
        contains('List<List<int>>'),
        contains(
          'Generated action argument decoders support only '
          'FlowActionRef<void, R>',
        ),
      ),
    );
  });

  test('void result action bindings encode a null payload', () async {
    const screen = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'welcome.rsscreen.g.dart';

@OnboardingSource(id: 'welcome')
final class WelcomeScreen extends StatelessWidget {
  static const next = OnboardingEvent<void>('next');
  const WelcomeScreen({super.key});
  @override
  Widget build(BuildContext context) => const Center();
}
''';

    const flow = '''
import 'package:restage/restage.dart';

import '../screens/welcome.dart';

part 'first_run.rsflow.g.dart';

@OnboardingFlow(id: 'first_run', version: 1, minClient: 3)
final class FirstRunFlow extends RestageFlow {
  static const logImpression =
      FlowActionRef<void, void>('logImpression');

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
        end(done, result: {'completed': true}),
      ],
    );
  }
}
''';

    final sources = {
      'apps_examples|lib/onboarding/screens/welcome.dart': screen,
      'apps_examples|lib/onboarding/flows/first_run.dart': flow,
    };
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    for (final entry in sources.entries) {
      readerWriter.testing.writeString(AssetId.parse(entry.key), entry.value);
    }

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
      AssetId('apps_examples', 'lib/onboarding/flows/first_run.rsflow.g.dart'),
    );
    expect(
      generated,
      allOf(
        contains("'logImpression': FlowActionBinding<void, void>("),
        contains('encodeResult: (_) => null,'),
        isNot(contains('encodeResult: (value) => value,')),
      ),
    );
    await _assertGeneratedFixtureAnalyzes(result, sources);
  });

  test('local FlowActionRef lookalikes are ignored by action generation',
      () async {
    const screen = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'welcome.rsscreen.g.dart';

@OnboardingSource(id: 'welcome')
final class WelcomeScreen extends StatelessWidget {
  static const next = OnboardingEvent<void>('next');
  const WelcomeScreen({super.key});
  @override
  Widget build(BuildContext context) => const Center();
}
''';

    const flow = '''
import 'package:restage/restage.dart';

import '../screens/welcome.dart';

part 'first_run.rsflow.g.dart';

@OnboardingFlow(id: 'first_run', version: 1, minClient: 3)
final class FirstRunFlow extends RestageFlow {
  static const fakeAction =
      FlowActionRef<void, NotificationResult>('fakeAction');

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
        end(done, result: {'completed': true}),
      ],
    );
  }
}

final class FlowActionRef<I, O> {
  const FlowActionRef(this.id);
  final String id;
}

final class NotificationResult {
  const NotificationResult({required this.granted});
  final bool granted;
}
''';

    final sources = {
      'apps_examples|lib/onboarding/screens/welcome.dart': screen,
      'apps_examples|lib/onboarding/flows/first_run.dart': flow,
    };
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    for (final entry in sources.entries) {
      readerWriter.testing.writeString(AssetId.parse(entry.key), entry.value);
    }

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
      AssetId('apps_examples', 'lib/onboarding/flows/first_run.rsflow.g.dart'),
    );
    expect(
      generated,
      allOf(
        contains('final class FirstRunActions {\n  const FirstRunActions();'),
        isNot(contains('fakeAction')),
        isNot(contains('FlowActionHandler')),
      ),
    );
    await _assertGeneratedFixtureAnalyzes(result, sources);
  });

  test('action named _handlers does not collide with generated storage',
      () async {
    const screen = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'welcome.rsscreen.g.dart';

@OnboardingSource(id: 'welcome')
final class WelcomeScreen extends StatelessWidget {
  static const next = OnboardingEvent<void>('next');
  const WelcomeScreen({super.key});
  @override
  Widget build(BuildContext context) => const Center();
}
''';

    const flow = '''
import 'package:restage/restage.dart';

import '../screens/welcome.dart';

part 'first_run.rsflow.g.dart';

@OnboardingFlow(id: 'first_run', version: 1, minClient: 3)
final class FirstRunFlow extends RestageFlow {
  static const _handlers =
      FlowActionRef<void, NotificationResult>('handlers');

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
        end(done, result: {'completed': true}),
      ],
    );
  }
}

final class NotificationResult {
  const NotificationResult({required this.granted});
  final bool granted;
}
''';

    final sources = {
      'apps_examples|lib/onboarding/screens/welcome.dart': screen,
      'apps_examples|lib/onboarding/flows/first_run.dart': flow,
    };
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    for (final entry in sources.entries) {
      readerWriter.testing.writeString(AssetId.parse(entry.key), entry.value);
    }

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
      AssetId('apps_examples', 'lib/onboarding/flows/first_run.rsflow.g.dart'),
    );
    expect(
      generated,
      allOf(
        contains('final class FirstRunActions implements FlowActionRegistry'),
        contains('final Map<String, FlowActionBinding<dynamic, dynamic>> '
            'flowActionBindings;'),
        contains('required FlowActionHandler<void, NotificationResult> '
            'handlers'),
        contains("'handlers': FlowActionBinding<void, NotificationResult>("),
        isNot(
          contains('required FlowActionHandler<void, NotificationResult> '
              '_handlers'),
        ),
        isNot(contains('final Map<String, Object> _handlers;')),
      ),
    );
    await _assertGeneratedFixtureAnalyzes(result, sources);
  });

  test('action parameter names avoid Dart keywords after underscore stripping',
      () async {
    const screen = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'welcome.rsscreen.g.dart';

@OnboardingSource(id: 'welcome')
final class WelcomeScreen extends StatelessWidget {
  static const next = OnboardingEvent<void>('next');
  const WelcomeScreen({super.key});
  @override
  Widget build(BuildContext context) => const Center();
}
''';

    const flow = '''
import 'package:restage/restage.dart';

import '../screens/welcome.dart';

part 'first_run.rsflow.g.dart';

@OnboardingFlow(id: 'first_run', version: 1, minClient: 3)
final class FirstRunFlow extends RestageFlow {
  static const _class =
      FlowActionRef<void, NotificationResult>('x');

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
        end(done, result: {'completed': true}),
      ],
    );
  }
}

final class NotificationResult {
  const NotificationResult({required this.granted});
  final bool granted;
}
''';

    final sources = {
      'apps_examples|lib/onboarding/screens/welcome.dart': screen,
      'apps_examples|lib/onboarding/flows/first_run.dart': flow,
    };
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    for (final entry in sources.entries) {
      readerWriter.testing.writeString(AssetId.parse(entry.key), entry.value);
    }

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
      AssetId('apps_examples', 'lib/onboarding/flows/first_run.rsflow.g.dart'),
    );
    expect(
      generated,
      allOf(
        contains(
          'required FlowActionHandler<void, NotificationResult> handler',
        ),
        contains("'x': FlowActionBinding<void, NotificationResult>("),
        contains('handler: handler'),
        isNot(
          contains(
            'required FlowActionHandler<void, NotificationResult> class',
          ),
        ),
      ),
    );
    await _assertGeneratedFixtureAnalyzes(result, sources);
  });

  test(
      'action named like generated actions class is renamed but keeps '
      'wire name', () async {
    const screen = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'welcome.rsscreen.g.dart';

@OnboardingSource(id: 'welcome')
final class WelcomeScreen extends StatelessWidget {
  static const next = OnboardingEvent<void>('next');
  const WelcomeScreen({super.key});
  @override
  Widget build(BuildContext context) => const Center();
}
''';

    const flow = '''
import 'package:restage/restage.dart';

import '../screens/welcome.dart';

part 'first_run.rsflow.g.dart';

@OnboardingFlow(id: 'first_run', version: 1, minClient: 3)
final class FirstRunFlow extends RestageFlow {
  static const FirstRunActions =
      FlowActionRef<void, NotificationResult>('FirstRunActions');

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
        end(done, result: {'completed': true}),
      ],
    );
  }
}

final class NotificationResult {
  const NotificationResult({required this.granted});
  final bool granted;
}
''';

    final sources = {
      'apps_examples|lib/onboarding/screens/welcome.dart': screen,
      'apps_examples|lib/onboarding/flows/first_run.dart': flow,
    };
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    for (final entry in sources.entries) {
      readerWriter.testing.writeString(AssetId.parse(entry.key), entry.value);
    }

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
      AssetId('apps_examples', 'lib/onboarding/flows/first_run.rsflow.g.dart'),
    );
    expect(
      generated,
      allOf(
        contains(
          'required FlowActionHandler<void, NotificationResult> '
          'firstRunActions',
        ),
        contains("actionName: 'FirstRunActions'"),
        contains("'FirstRunActions': "
            'FlowActionBinding<void, NotificationResult>('),
        contains('handler: firstRunActions'),
        isNot(
          contains(
            'required FlowActionHandler<void, NotificationResult> '
            'FirstRunActions',
          ),
        ),
      ),
    );
    await _assertGeneratedFixtureAnalyzes(result, sources);
  });
}

Map<String, String> _actionFixtureSources({
  String actionName = 'requestNotifications',
  String actionOptions = '',
  String extraFlowSource = '',
}) =>
    {
      'apps_examples|lib/onboarding/screens/welcome.dart': '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'welcome.rsscreen.g.dart';

@OnboardingSource(id: 'welcome')
final class WelcomeScreen extends StatelessWidget {
  static const next = OnboardingEvent<void>('next');
  const WelcomeScreen({super.key});
  @override
  Widget build(BuildContext context) => const Center();
}
''',
      'apps_examples|lib/onboarding/flows/first_run.dart': '''
import 'package:restage/restage.dart';

import '../screens/welcome.dart';

part 'first_run.rsflow.g.dart';

@OnboardingFlow(id: 'first_run', version: 1, minClient: 3)
final class FirstRunFlow extends RestageFlow {
  static const requestNotifications =
      FlowActionRef<void, NotificationResult>("$actionName"$actionOptions);

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
        end(done, result: {'completed': true}),
      ],
    );
  }
}

final class NotificationResult {
  const NotificationResult({required this.granted});
  final bool granted;
}

$extraFlowSource
''',
    };

Future<void> _assertGeneratedFixtureAnalyzes(
  TestBuilderResult result,
  Map<String, String> sources,
) async {
  final resolvedSources = {
    ...sources,
    'apps_examples|lib/onboarding/screens/welcome.rsscreen.g.dart':
        result.readerWriter.testing.readString(
      AssetId(
        'apps_examples',
        'lib/onboarding/screens/welcome.rsscreen.g.dart',
      ),
    ),
    'apps_examples|lib/onboarding/flows/first_run.rsflow.g.dart':
        result.readerWriter.testing.readString(
      AssetId('apps_examples', 'lib/onboarding/flows/first_run.rsflow.g.dart'),
    ),
  };

  await resolveSources(
    resolvedSources,
    (resolver) async {
      final library = await resolver.libraryFor(
        AssetId('apps_examples', 'lib/onboarding/flows/first_run.dart'),
      );
      final resolved =
          await library.session.getResolvedLibraryByElement(library);
      if (resolved is! ResolvedLibraryResult) {
        throw StateError('Generated fixture did not resolve.');
      }
      final errors = [
        for (final unit in resolved.units)
          for (final diagnostic in unit.diagnostics)
            if (diagnostic.severity == Severity.error)
              diagnostic.problemMessage.messageText(includeUrl: false),
      ];
      expect(errors, isEmpty);
    },
    resolverFor: 'apps_examples|lib/onboarding/flows/first_run.dart',
    rootPackage: 'apps_examples',
    readAllSourcesFromFilesystem: true,
  );
}

String _readFlutterSdkReadme() {
  return File('${_repoRoot().path}/packages/restage/README.md')
      .readAsStringSync();
}

Directory _repoRoot() {
  var directory = Directory.current;
  while (true) {
    final readme = File('${directory.path}/packages/restage/README.md');
    if (readme.existsSync()) {
      return directory;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('Could not locate packages/restage/README.md.');
    }
    directory = parent;
  }
}

Iterable<File> _dartFilesIn(Directory directory) sync* {
  for (final entity in directory.listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      yield entity;
    }
  }
}

Future<void> _assertSourcesAnalyze(Map<String, String> sources) async {
  await resolveSources(
    sources,
    (resolver) async {
      final library = await resolver.libraryFor(
        AssetId('apps_examples', 'lib/onboarding/public_usage.dart'),
      );
      final resolved =
          await library.session.getResolvedLibraryByElement(library);
      if (resolved is! ResolvedLibraryResult) {
        throw StateError('Public API fixture did not resolve.');
      }
      final errors = [
        for (final unit in resolved.units)
          for (final diagnostic in unit.diagnostics)
            if (diagnostic.severity == Severity.error)
              diagnostic.problemMessage.messageText(includeUrl: false),
      ];
      expect(errors, isEmpty);
    },
    resolverFor: 'apps_examples|lib/onboarding/public_usage.dart',
    rootPackage: 'apps_examples',
    readAllSourcesFromFilesystem: true,
  );
}
