import 'package:build/build.dart';
import 'package:logging/logging.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_codegen/src/surface_publication/output_builder.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  const authored = '''
part 'restage.generated/welcome.restage.g.dart';
''';
  const generatedPart = '''
part of '../welcome.dart';
''';

  Future<List<LogRecord>> build(Map<String, Object> extra) async {
    final logs = <LogRecord>[];
    final result = await testBuilder(
      RestageOutputsBuilder(BuilderOptions.empty),
      {
        'fixture|lib/features/welcome.dart': authored,
        'fixture|lib/features/restage.generated/welcome.restage.g.dart':
            generatedPart,
        ...extra,
      },
      rootPackage: 'fixture',
      onLog: logs.add,
    );
    logs.addAll([
      for (final error in result.errors) LogRecord(Level.SEVERE, error, ''),
    ]);
    return logs;
  }

  String messages(List<LogRecord> logs) =>
      logs.map((log) => '${log.message} ${log.error ?? ''}').join('\n');

  test('a refused build never treats a generated part as a source', () async {
    final failed = RestageSurfacePublicationBundle.fromJson({
      'schemaVersion': 2,
      'valid': false,
      'errors': ['a surface failed'],
      'manifest': null,
      'artifacts': <Object>[],
      'borrowedArtifacts': <Object>[],
      'ownedOutputs': <Object>[],
      'artifactLibraryPaths': <Object>[],
      'surfaceWidgetNames': <Object>[],
    });

    final logs = await build({
      'fixture|$kRestageSurfacePublicationCompilerBundlePath':
          failed.encodeCanonicalJson(),
    });

    expect(messages(logs), isNot(contains('restage.generated/')));
  });

  test('a package with no surfaces never treats a generated part as a source',
      () async {
    final logs = await build(const {});

    expect(messages(logs), isNot(contains('restage.generated/')));
  });
}
