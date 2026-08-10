import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('published dependency surface matches the pre-Phase-3 contract', () {
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
        'restage_shared',
        'rfw_catalog_compiler',
        'rfw_catalog_schema',
      },
      reason: 'Phase 3 may not expand restage_codegen published dependencies.',
    );
    expect(
      devDependencies,
      contains('yaml'),
      reason: 'YAML remains a test-only build.yaml parser.',
    );
  });
}
