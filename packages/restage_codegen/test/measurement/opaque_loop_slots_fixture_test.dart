// Taps inside an opaque widget's list slot fed by a loop over host data are
// planned and emitted together.

import 'dart:io';

import 'package:build/build.dart';
import 'package:path/path.dart' as p;
import 'package:restage_codegen/builder.dart';
import 'package:restage_codegen/src/measurement/measurement_compiler_output.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../helpers.dart';

const _fixtureRoot = 'test/fixtures/opaque_loop_slots';
const _package = 'apps_examples';
const _fixtureDartPaths = <String>[
  'lib/widgets/day_tile.dart',
  'lib/widgets/habit_row.dart',
  'lib/widgets/library.dart',
  'lib/widgets/reorderable_column.dart',
  'lib/surfaces/habit_list.dart',
];

void main() {
  test('taps in an opaque list slot under a host-data loop build', () async {
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: _package,
    );
    final logs = <String>[];
    final result = await testBuilders(
      [
        restageSourceRosterBuilder(
          _builderOptions('restage_codegen:restage_source_roster'),
        ),
        userCatalogJsonBuilder(BuilderOptions.empty),
        restagePackageSurfaceCompilerBuilder(
          _builderOptions('restage_codegen:restage_package_surface_compiler'),
        ),
        restageGeneratedDartBuilder(
          _builderOptions('restage_codegen:generated_dart'),
        ),
        restageOutputsBuilder(_builderOptions('restage_codegen:outputs')),
      ],
      {
        for (final path in _fixtureDartPaths)
          '$_package|$path':
              File(p.join(_fixtureRoot, path)).readAsStringSync(),
      },
      rootPackage: _package,
      readerWriter: readerWriter,
      flattenOutput: true,
      onLog: (record) => logs.add(record.message),
    );
    final log = [...logs, ...result.errors].join('\n');
    expect(result.succeeded, isTrue, reason: log);
    final output = RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
      readerWriter.testing.readBytes(
        AssetId(_package, kRestageMeasurementCompilerOutputPath),
      ),
    );
    final publication = output.publications.single;
    final taps = publication.routePlan.routes
        .where((route) => route.orderedCaptureV1?.lifecycleChannel == null);
    expect(taps, hasLength(8), reason: 'onReorder and the 7 day taps');
  });
}

BuilderOptions _builderOptions(String builderKey) {
  final document = loadYaml(
    File(p.join(_fixtureRoot, 'build.yaml')).readAsStringSync(),
  ) as YamlMap;
  final options =
      ((((document['targets'] as YamlMap)[r'$default'] as YamlMap)['builders']
          as YamlMap)[builderKey] as YamlMap)['options'] as YamlMap;
  return BuilderOptions(
    {for (final entry in options.entries) entry.key as String: entry.value},
    isRoot: true,
  );
}
