import 'dart:convert';
import 'dart:io';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:glob/glob.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:restage_codegen/builder.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const _fixtureRoot = 'test/fixtures/explicit_authoring';

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
          (entry) =>
              entry.key.endsWith('.rsscreen.g.dart') ||
              entry.key.endsWith('.rsflow.g.dart'),
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
    final descriptors = outputs.entries
        .where(
          (entry) =>
              entry.key.endsWith('.rsscreen.g.dart') ||
              entry.key.endsWith('.rsflow.g.dart'),
        )
        .map(_decodeOutput)
        .join('\n');
    expect(descriptors, contains('general_premium'));
    expect(
      outputs.keys.any((path) => path.endsWith('.flow.json')),
      isTrue,
      reason: 'paywall_cross_category emitted no canonical flow artifact',
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
