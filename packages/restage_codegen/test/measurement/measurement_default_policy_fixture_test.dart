// An app whose `build.yaml` names no Measurement option still gets a route
// plan, because the compiler stamps the policy it ships with.

import 'dart:io';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:path/path.dart' as p;
import 'package:restage_codegen/builder.dart';
import 'package:restage_codegen/src/measurement/measurement_compiler_output.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../helpers.dart';

const _fixtureRoot = 'test/fixtures/measurement_default_policy';
const _package = 'apps_examples';
const _screenSourcePath = 'lib/surfaces/default_policy_showcase.dart';
const _screenSlug = 'default_policy_showcase';

void main() {
  test('a build naming no policy still emits a stamped route plan', () async {
    final output = await _compileFixture();

    expect(output.valid, isTrue, reason: output.errors.join('\n'));
    expect(output.policy, isNotNull);
    expect(output.policy!.toJson(), <String, Object?>{
      'collectionBudgetRevisionId':
          kMeasurementDefaultCollectionBudgetRevisionId,
      'minimumMeasurementClient': kMeasurementDefaultMinimumClient,
      'privacyPolicyRevisionId': kMeasurementDefaultPrivacyPolicyRevisionId,
    });

    expect(output.publications, hasLength(1));
    final publication = output.publications.single;
    expect(publication.selector.slug, _screenSlug);
    expect(publication.routePlan.routes, isNotEmpty);
    expect(
      publication.routePlan.privacyPolicyRevisionId.value,
      kMeasurementDefaultPrivacyPolicyRevisionId,
    );
    expect(
      publication.routePlan.collectionBudgetRevisionId.value,
      kMeasurementDefaultCollectionBudgetRevisionId,
    );
    expect(
      publication.routePlan.minimumMeasurementClient,
      kMeasurementDefaultMinimumClient,
    );
  });

  test('the fixture names no Measurement option anywhere', () {
    final buildYaml =
        File(p.join(_fixtureRoot, 'build.yaml')).readAsStringSync();
    for (final option in const [
      kMeasurementMinimumClientOption,
      kMeasurementPrivacyPolicyRevisionOption,
      kMeasurementCollectionBudgetRevisionOption,
    ]) {
      expect(
        buildYaml,
        isNot(contains(option)),
        reason: 'The fixture proves the unconfigured path; configuring it '
            'would prove the override instead.',
      );
    }
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
      '$_package|$_screenSourcePath':
          File(p.join(_fixtureRoot, _screenSourcePath)).readAsStringSync(),
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
