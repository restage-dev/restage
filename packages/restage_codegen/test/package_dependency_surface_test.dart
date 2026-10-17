import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('published dependency surface matches the committed compiler contract',
      () {
    final pubspec =
        loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
    final dependencies =
        (pubspec['dependencies'] as YamlMap).keys.whereType<String>().toSet();
    final devDependencies = (pubspec['dev_dependencies'] as YamlMap)
        .keys
        .whereType<String>()
        .toSet();

    expect(
      dependencies,
      const {
        'analyzer',
        'build',
        'collection',
        'crypto',
        'dart_style',
        'glob',
        'logging',
        'meta',
        'package_config',
        'path',
        'pub_semver',
        'restage_compiler_core',
        'restage_measurement_schema',
        'restage_shared',
        'rfw_catalog_compiler',
        'rfw_catalog_schema',
        // Reads build.yaml; every consumer already resolves it through
        // build_runner.
        'yaml',
      },
      reason: 'Every package lib imports is declared, and restage_codegen '
          'must not gain further published dependencies.',
    );
    expect(
      devDependencies.intersection(dependencies),
      isEmpty,
      reason: 'A package is either published or test-only.',
    );
  });
}
