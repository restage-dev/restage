import 'dart:convert';
import 'dart:io';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:glob/glob.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:restage_codegen/builder.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const _fixtureRoot = 'test/fixtures/explicit_authoring';

void main() {
  group('old/new exact parity', () {
    for (final scenario in <String>[
      'linear',
      'branching',
      'completion',
      'cycle',
      'action',
      'subflow',
      'paywall',
      'compatibility',
    ]) {
      test('$scenario preserves canonical artifacts and identities', () async {
        final oldResult = await _compileScenario('$scenario/old');
        final newResult = await _compileScenario('$scenario/new');

        _expectSuccessful(oldResult, '$scenario old authoring');
        _expectSuccessful(newResult, '$scenario new authoring');

        final oldOutputs = await _outputs(oldResult);
        final newOutputs = await _outputs(newResult);

        final oldCanonical = _canonicalArtifacts(oldOutputs);
        final newCanonical = _canonicalArtifacts(newOutputs);
        expect(newCanonical.keys, orderedEquals(oldCanonical.keys));
        for (final path in oldCanonical.keys) {
          expect(
            newCanonical[path],
            oldCanonical[path],
            reason: 'canonical artifact drift at $path',
          );
        }

        final oldDescriptors = _descriptorArtifacts(oldOutputs);
        final newDescriptors = _descriptorArtifacts(newOutputs);
        expect(newDescriptors.keys, orderedEquals(oldDescriptors.keys));
        for (final path in oldDescriptors.keys) {
          final oldIdentity = _stableDescriptorIdentity(oldDescriptors[path]!);
          final newIdentity = _stableDescriptorIdentity(newDescriptors[path]!);
          expect(
            newIdentity,
            containsAll(oldIdentity),
            reason: 'descriptor identity drift at $path',
          );
        }

        _expectFlowDocumentsAgree(oldCanonical, newCanonical);
      });
    }
  });
}

Future<TestBuilderResult> _compileScenario(String scenario) async {
  final sources = _loadScenario(scenario);
  final readerWriter = await _readerWriterWith(sources);
  final logs = <LogRecord>[];
  final result = await testBuilders(
    [
      restageCodegenBuilder(BuilderOptions.empty),
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
    readerWriter: readerWriter,
    flattenOutput: true,
    onLog: logs.add,
  );
  if (!result.succeeded && logs.isNotEmpty) {
    // Keep the raw build log attached to the result for a useful assertion
    // failure without converting expected builder diagnostics into a skip.
    _logs[result] = logs.map((entry) => entry.message).join('\n');
  }
  return result;
}

final _logs = <TestBuilderResult, String>{};

void _expectSuccessful(TestBuilderResult result, String label) {
  expect(
    result.succeeded,
    isTrue,
    reason: '$label failed:\n${_logs[result] ?? '<no build log>'}',
  );
}

Map<String, String> _loadScenario(String scenario) {
  final root = Directory('$_fixtureRoot/$scenario/lib');
  expect(
    root.existsSync(),
    isTrue,
    reason: 'missing fixture root ${root.path}',
  );

  final result = <String, String>{};
  for (final entity in root.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (entity.path.endsWith('.g.dart')) continue;
    final relative = p.relative(entity.path, from: root.path);
    result['apps_examples|lib/$relative'] = entity.readAsStringSync();
  }
  return result;
}

Future<TestReaderWriter> _readerWriterWith(Map<String, String> sources) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  for (final entry in sources.entries) {
    readerWriter.testing.writeString(AssetId.parse(entry.key), entry.value);
  }
  return readerWriter;
}

Future<Map<String, String>> _outputs(TestBuilderResult result) async {
  final ids = result.readerWriter.testing.assets
      .where((id) => id.package == 'apps_examples')
      .where((id) => Glob('assets/**').matches(id.path))
      .toList();
  final outputs = <String, String>{};
  for (final id in ids
    ..sort((left, right) => left.path.compareTo(right.path))) {
    outputs[id.path] = base64Encode(result.readerWriter.testing.readBytes(id));
  }

  final generatedIds = result.readerWriter.testing.assets
      .where((id) => id.package == 'apps_examples')
      .where((id) => Glob('lib/**/*.g.dart').matches(id.path))
      .toList();
  for (final id in generatedIds
    ..sort((left, right) => left.path.compareTo(right.path))) {
    outputs[id.path] = result.readerWriter.testing.readString(id);
  }
  return outputs;
}

Map<String, String> _canonicalArtifacts(Map<String, String> outputs) =>
    outputs.entries
        .where(
      (entry) =>
          entry.key.endsWith('.flow.json') ||
          entry.key.endsWith('.rfwtxt') ||
          entry.key.endsWith('.rfw') ||
          entry.key.endsWith('.capability.json'),
    )
        .fold(<String, String>{}, (result, entry) {
      result[entry.key] = entry.value;
      return result;
    });

Map<String, String> _descriptorArtifacts(Map<String, String> outputs) =>
    outputs.entries
        .where(
      (entry) =>
          entry.key.endsWith('.rsscreen.g.dart') ||
          entry.key.endsWith('.rsflow.g.dart'),
    )
        .fold(<String, String>{}, (result, entry) {
      result[entry.key] = entry.value;
      return result;
    });

Set<String> _stableDescriptorIdentity(String source) {
  final values = <String>{};
  final fields = RegExp(
    r'\b(id|slug|artifactPath|path|version|minClient|contractVersion|'
    r'surfaceType|surface|deliveryMode):\s*([^,\n)]+)',
  );
  for (final match in fields.allMatches(source)) {
    final key = match.group(1)!;
    final value = match.group(2)!.trim();
    final normalizedKey = switch (key) {
      'id' || 'slug' => 'identity',
      'artifactPath' || 'path' => 'artifact',
      'version' || 'contractVersion' => 'version',
      'surfaceType' || 'surface' => 'surface',
      _ => key,
    };
    values.add('$normalizedKey=$value');
  }
  return values;
}

void _expectFlowDocumentsAgree(
  Map<String, String> oldOutputs,
  Map<String, String> newOutputs,
) {
  final oldFlows = oldOutputs.entries.where(
    (entry) => entry.key.endsWith('.flow.json'),
  );
  for (final oldFlow in oldFlows) {
    final newFlow = newOutputs[oldFlow.key];
    expect(
      newFlow,
      isNotNull,
      reason: 'missing new flow ${oldFlow.key}',
    );
    final oldDocument = FlowDocumentCodec.decodeJson(
      utf8.decode(base64Decode(oldFlow.value)),
    );
    final newDocument = FlowDocumentCodec.decodeJson(
      utf8.decode(base64Decode(newFlow!)),
    );
    expect(newDocument.flow, oldDocument.flow);
    expect(newDocument.initial, oldDocument.initial);
    expect(newDocument.states.keys, orderedEquals(oldDocument.states.keys));
    expect(
      newDocument.screenArtifacts.keys,
      orderedEquals(oldDocument.screenArtifacts.keys),
    );
  }
}
