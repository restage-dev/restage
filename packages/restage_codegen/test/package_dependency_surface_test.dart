import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('published dependency surface stays frozen', () {
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
      reason: 'restage_codegen must not gain published dependencies.',
    );
    expect(
      devDependencies,
      contains('yaml'),
      reason: 'YAML remains a test-only build.yaml parser.',
    );
  });
}
