import 'dart:convert';
import 'dart:io';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:glob/glob.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:restage_codegen/builder.dart';
import 'package:restage_codegen/src/neutral_part_directive.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const _fixtureRoot = 'test/fixtures/explicit_authoring';

const _nonDefaultLegacyFlowSource = '''
import 'package:restage/restage.dart';

part 'restage.generated/upgraded.restage.g.dart';

@FlowSource(
  id: 'upgraded',
  version: 4,
  minClient: 7,
  delivery: FlowDeliveryMode.general,
)
class UpgradedFlow {}
''';

void main() {
  group('explicit-authoring compiler diagnostics', () {
    test('rejects multiple implicit declarations in one library', () async {
      final result = await _compileScenario('negative/duplicate_implicit.dart');
      _expectDiagnostic(result, 'implicit');
    });

    test('rejects duplicate explicit source identities', () async {
      final result = await _compileScenario('negative/duplicate_explicit.dart');
      _expectDiagnostic(result, 'duplicate');
    });

    test('rejects ambiguous implicit flow IDs in one library', () async {
      final result =
          await _compileScenario('negative/duplicate_implicit_flow.dart');
      _expectDiagnostic(result, 'implicit');
    });

    test('rejects categorized screen mismatch and divergent terminals',
        () async {
      final categories = await _compileScenario('categories/new');
      _expectDiagnostic(categories, 'surface message');

      final terminals = await _compileScenario('negative/two_terminals');
      _expectDiagnostic(terminals, 'one terminal identity');
    });
  });

  test('emits precise migration warnings for deprecated source frontends',
      () async {
    final sources = <String, String>{
      ..._loadScenario('paywall/old'),
      'apps_examples|lib/onboarding/flows/upgraded.dart':
          _nonDefaultLegacyFlowSource,
    };
    final writer = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final logs = <LogRecord>[];
    final result = await testBuilder(
      restageSourceRosterBuilder(BuilderOptions.empty),
      sources,
      rootPackage: 'apps_examples',
      readerWriter: writer,
      onLog: logs.add,
    );

    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    _expectMigrationWarning(
      logs,
      sourcePath: 'lib/onboarding/screens/offer_intro.dart',
      deprecated: '@ScreenSource',
      replacement: '@Screen(id: "offer_intro", surface: Surface.onboarding)',
    );
    _expectMigrationWarning(
      logs,
      sourcePath: 'lib/onboarding/flows/first_run_flow.dart',
      deprecated: '@FlowSource',
      replacement:
          '@FlowGraph(id: "first_run_flow", surface: Surface.onboarding)',
    );
    _expectMigrationWarning(
      logs,
      sourcePath: 'lib/paywalls/premium.dart',
      deprecated: '@PaywallSource',
      replacement: '@Paywall(id: "premium")',
    );
    _expectMigrationWarning(
      logs,
      sourcePath: 'lib/onboarding/flows/upgraded.dart',
      deprecated: '@FlowSource',
      replacement: '@FlowGraph(id: "upgraded", surface: Surface.onboarding, '
          'version: 4, minClient: 7, delivery: FlowDeliveryMode.general)',
    );
  });

  test(
      'compiles general screens, general flows, explicit IDs, and '
      'colocated sources', () async {
    final result = await _compileScenario('identity/new');
    expect(
      result.succeeded,
      isTrue,
      reason: 'identity/new failed:\n${_logs[result] ?? '<no build log>'}',
    );

    final outputs = await _outputs(result);
    final descriptors = outputs.entries
        .where(
          (entry) => entry.key.endsWith(kNeutralGeneratedPartSuffix),
        )
        .map(_decodeOutput)
        .join('\n');
    expect(descriptors, contains('derived_flow'));
    expect(descriptors, contains('stable_flow'));
    expect(descriptors, contains('stable_notice'));
    expect(descriptors, contains('first_notice'));
    expect(descriptors, contains('second_notice'));
    expect(
      outputs.keys.any((path) => path.endsWith('.flow.json')),
      isTrue,
      reason: 'identity/new emitted no canonical flow artifact',
    );
  });

  test('composes a paywall into a general flow without a category fence',
      () async {
    final result = await _compileScenario('paywall_cross_category');
    expect(
      result.succeeded,
      isTrue,
      reason: 'paywall_cross_category failed:\n'
          '${_logs[result] ?? '<no build log>'}',
    );

    final outputs = await _outputs(result);
    expect(
      outputs.keys.any((path) => path.endsWith('.flow.json')),
      isTrue,
      reason: 'paywall_cross_category emitted no canonical flow artifact',
    );

    // A surface-typed paywall owns no generated part of its own — composing it
    // into a flow is the FLOW's business, so that is where the composition has
    // to be visible. Asserting it on the paywall's own descriptor would be
    // asserting a file the approved design does not produce.
    final flowArtifacts = outputs.entries
        .where(
          (entry) =>
              entry.key.endsWith('.flow.json') ||
              entry.key.endsWith(kNeutralGeneratedPartSuffix),
        )
        .map(_decodeOutput)
        .join('\n');
    expect(
      flowArtifacts,
      contains('general_premium'),
      reason: 'the general flow must embed the paywall across the category '
          'boundary; emitted flow artifacts were:\n$flowArtifacts',
    );
  });
}

final _logs = <TestBuilderResult, String>{};

Future<TestBuilderResult> _compileScenario(String scenario) async {
  final sources = _loadScenario(scenario);
  final writer = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  final logs = <LogRecord>[];
  final result = await testBuilders(
    [
      restageCodegenBuilder(BuilderOptions.empty),
      restageSourceRosterBuilder(BuilderOptions.empty),
      paywallFlowBuilder(BuilderOptions.empty),
      onboardingScreenBuilder(BuilderOptions.empty),
      onboardingFlowBuilder(BuilderOptions.empty),
      messageScreenBuilder(BuilderOptions.empty),
      messageFlowBuilder(BuilderOptions.empty),
      surveyScreenBuilder(BuilderOptions.empty),
      surveyFlowBuilder(BuilderOptions.empty),
      // The one owner of per-library generated Dart. Without it the
      // scenario emits no `.restage.g.dart` at all and every descriptor
      // assertion below passes vacuously over an empty set.
      // Produces the compiler handoff the generated-Dart builder reads;
      // without it that builder silently emits nothing.
      restagePackageSurfaceCompilerBuilder(BuilderOptions.empty),
      restageGeneratedDartBuilder(BuilderOptions.empty),
    ],
    sources,
    rootPackage: 'apps_examples',
    readerWriter: writer,
    flattenOutput: true,
    onLog: logs.add,
  );
  _logs[result] = logs.map((entry) => entry.message).join('\n');
  return result;
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
  expect(
    scenarioRoot.existsSync(),
    isTrue,
    reason: 'missing fixture root ${scenarioRoot.path}',
  );
  final libRoot = Directory(p.join(scenarioRoot.path, 'lib'));
  final sourceRoot = libRoot.existsSync() ? libRoot : scenarioRoot;
  final sources = <String, String>{};
  for (final entity in sourceRoot.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (entity.path.endsWith('.g.dart')) continue;
    final relative = p.relative(entity.path, from: sourceRoot.path);
    sources['apps_examples|lib/$relative'] = entity.readAsStringSync();
  }
  return sources;
}

void _expectDiagnostic(TestBuilderResult result, String fragment) {
  final log = _logs[result] ?? '<no build log>';
  expect(
    result.succeeded,
    isFalse,
    reason: 'unexpected successful build:\n$log',
  );
  expect(log.toLowerCase(), contains(fragment.toLowerCase()));
}

void _expectMigrationWarning(
  Iterable<LogRecord> logs, {
  required String sourcePath,
  required String deprecated,
  required String replacement,
}) {
  final warnings = logs
      .where(
        (record) =>
            record.level == Level.WARNING &&
            record.message.contains(sourcePath) &&
            record.message.contains(deprecated),
      )
      .toList(growable: false);
  expect(
    warnings,
    hasLength(1),
    reason: 'expected one migration warning for $deprecated; logs: '
        '${logs.map((record) => '${record.level}: ${record.message}').join('\n')}',
  );
  expect(
    warnings.single.message,
    allOf(contains(sourcePath), contains(replacement)),
  );
}

Future<Map<String, String>> _outputs(TestBuilderResult result) async {
  final outputs = <String, String>{};
  final assets = result.readerWriter.testing.assets
      .where((id) => id.package == 'apps_examples')
      .where((id) => Glob('assets/**').matches(id.path))
      .toList()
    ..sort((left, right) => left.path.compareTo(right.path));
  for (final id in assets) {
    outputs[id.path] = base64Encode(result.readerWriter.testing.readBytes(id));
  }
  final generated = result.readerWriter.testing.assets
      .where((id) => id.package == 'apps_examples')
      .where((id) => Glob('lib/**/*.g.dart').matches(id.path))
      .toList()
    ..sort((left, right) => left.path.compareTo(right.path));
  for (final id in generated) {
    outputs[id.path] = result.readerWriter.testing.readString(id);
  }
  return outputs;
}

String _decodeOutput(MapEntry<String, String> entry) {
  if (entry.key.startsWith('assets/')) {
    return utf8.decode(base64Decode(entry.value));
  }
  return entry.value;
}
