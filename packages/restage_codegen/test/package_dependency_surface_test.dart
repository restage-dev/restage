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
        'meta',
        'package_config',
        'path',
        'restage_measurement_schema',
        'restage_shared',
        'rfw_catalog_compiler',
        'rfw_catalog_schema',
      },
      reason: 'The committed measurement schema dependency is allowed; '
          'restage_codegen must not gain further published dependencies.',
    );
    expect(
      devDependencies,
      contains('yaml'),
      reason: 'YAML remains a test-only build.yaml parser.',
    );
  });
}
