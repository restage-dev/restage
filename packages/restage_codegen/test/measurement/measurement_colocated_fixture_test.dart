// Two surfaces authored in one library share one generated part, and both
// still get a Measurement route plan.

import 'dart:io';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:path/path.dart' as p;
import 'package:restage_codegen/builder.dart';
import 'package:restage_codegen/src/measurement/measurement_compiler_output.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../helpers.dart';

const _fixtureRoot = 'test/fixtures/measurement_colocated';
const _package = 'apps_examples';
const _sourcePath = 'lib/surfaces/colocated_notices.dart';
const _firstSlug = 'first_colocated_notice';
const _secondSlug = 'second_colocated_notice';

void main() {
  test('colocated surfaces each get their own stamped route plan', () async {
    final output = await _compileFixture();

    expect(output.valid, isTrue, reason: output.errors.join('\n'));
    expect(
      output.publications.map((publication) => publication.selector.slug),
      unorderedEquals(<String>[_firstSlug, _secondSlug]),
    );
    for (final publication in output.publications) {
      expect(
        publication.routePlan.routes,
        isNotEmpty,
        reason: '${publication.selector.slug} planned no route',
      );
      expect(
        publication.routePlan.privacyPolicyRevisionId.value,
        kMeasurementDefaultPrivacyPolicyRevisionId,
      );
    }
  });

  test('the two colocated surfaces get distinct Measurement identities',
      () async {
    final output = await _compileFixture();
    final carriers = [
      for (final publication in output.publications)
        ...publication.routePlan.routes.map((route) => route.carrier),
    ];
    expect(carriers, isNotEmpty);
    expect(
      carriers.toSet(),
      hasLength(carriers.length),
      reason: 'sharing a generated part must not merge two surfaces',
    );
  });
}

Future<RestageMeasurementCompilerOutputV1> _compileFixture() async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: _package,
  );
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
  );
  expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
  return RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
    readerWriter.testing.readBytes(
      AssetId(_package, kRestageMeasurementCompilerOutputPath),
    ),
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
