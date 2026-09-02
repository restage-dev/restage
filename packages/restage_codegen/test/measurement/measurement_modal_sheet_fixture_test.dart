// A surface whose callback becomes a declarative sheet compiles unmeasured,
// with a diagnostic naming the idiom — never a build break.

import 'dart:io';

import 'package:build/build.dart';
import 'package:path/path.dart' as p;
import 'package:restage_codegen/builder.dart';
import 'package:restage_codegen/src/measurement/measurement_compiler_output.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../helpers.dart';
import 'measurement_fixture_helpers.dart';

const _fixtureRoot = 'test/fixtures/measurement_modal_sheet';
const _package = 'apps_examples';
const _sourcePath = 'lib/surfaces/sheet_notice.dart';
const _bundlePath = 'assets/restage/bundles/lib/surfaces/sheet_notice.rsbundle';
const _slug = 'sheet_notice';

void main() {
  test('a sheet-opening callback leaves the surface unmeasured', () async {
    final compiled = await _compileFixture();

    expect(
      compiled.output.valid,
      isTrue,
      reason: compiled.output.errors.join('\n'),
    );
    expect(
      compiled.output.publications,
      isEmpty,
      reason: 'a surface Measurement cannot resolve must get no partial plan',
    );
    expect(
      compiled.log,
      contains('Measurement is unavailable for'),
      reason: 'the boundary must name the surface, not skip silently',
    );
    expect(
      compiled.log,
      contains('modal-sheet lowering'),
      reason: 'the diagnostic must name the idiom, not just fail vaguely',
    );
    expect(compiled.log, contains('compiles unmeasured'));
    expectUnmeasuredScreenPublication(
      readerWriter: compiled.readerWriter,
      packageName: _package,
      sourcePath: _sourcePath,
      bundlePath: _bundlePath,
      surface: Surface.general,
      slug: _slug,
    );
  });
}

class _Compiled {
  const _Compiled(this.output, this.log, this.readerWriter);
  final RestageMeasurementCompilerOutputV1 output;
  final String log;
  final TestReaderWriter readerWriter;
}

Future<_Compiled> _compileFixture() async {
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
      '$_package|$_sourcePath':
          File(p.join(_fixtureRoot, _sourcePath)).readAsStringSync(),
    },
    rootPackage: _package,
    readerWriter: readerWriter,
    flattenOutput: true,
    onLog: (record) => logs.add(record.message),
  );
  expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
  return _Compiled(
    RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
      readerWriter.testing.readBytes(
        AssetId(_package, kRestageMeasurementCompilerOutputPath),
      ),
    ),
    logs.join('\n'),
    readerWriter,
  );
}

BuilderOptions _builderOptions(String builderKey) {
  final document = loadYaml(
    File(p.join(_fixtureRoot, 'build.yaml')).readAsStringSync(),
  );
  final root = _yamlMap(document, 'build.yaml');
  final targets = _yamlMap(root['targets'], 'build.yaml.targets');
  final defaultTarget = _yamlMap(
    targets[r'$default'],
    r'build.yaml.targets.$default',
  );
  final builders = _yamlMap(
    defaultTarget['builders'],
    r'build.yaml.targets.$default.builders',
  );
  final builder = _yamlMap(builders[builderKey], 'builder $builderKey');
  final options = _yamlMap(builder['options'], 'builder $builderKey options');
  return BuilderOptions({
    for (final entry in options.entries)
      _stringKey(entry.key, 'builder $builderKey option'):
          _yamlValue(entry.value),
  });
}

Map<Object?, Object?> _yamlMap(Object? value, String path) {
  if (value is! YamlMap) throw StateError('$path must be a map.');
  return value;
}

Object? _yamlValue(Object? value) => switch (value) {
      YamlMap() => {
          for (final entry in value.entries)
            entry.key as String: _yamlValue(entry.value),
        },
      YamlList() => [for (final entry in value) _yamlValue(entry)],
      _ => value,
    };

String _stringKey(Object? value, String path) {
  if (value is! String) throw StateError('$path key must be a string.');
  return value;
}
