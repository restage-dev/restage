import 'dart:io';

import 'package:restage_cli/src/config/restage_config.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('RestageConfig.fromYaml', () {
    test('round-trips a 3-field document', () {
      const src = '''
project: my-project
app: my-app
defaultEnvironment: staging
''';
      final config = RestageConfig.fromYaml(src);
      expect(config.project, 'my-project');
      expect(config.app, 'my-app');
      expect(config.defaultEnvironment, 'staging');
    });

    test('tolerates an omitted defaultEnvironment', () {
      const src = '''
project: my-project
app: my-app
''';
      final config = RestageConfig.fromYaml(src);
      expect(config.defaultEnvironment, isNull);
    });

    test('throws on missing required keys', () {
      const src = '''
project: my-project
''';
      expect(
        () => RestageConfig.fromYaml(src),
        throwsA(isA<RestageConfigFormatException>()),
      );
    });

    test('throws on a non-string value for a required key', () {
      const src = '''
project: 123
app: my-app
''';
      expect(
        () => RestageConfig.fromYaml(src),
        throwsA(isA<RestageConfigFormatException>()),
      );
    });
  });

  group('RestageConfig.toYaml', () {
    test('produces a readable, parseable document', () {
      const config = RestageConfig(
        project: 'p',
        app: 'a',
        defaultEnvironment: 'dev',
      );
      final yaml = config.toYaml();
      final parsed = RestageConfig.fromYaml(yaml);
      expect(parsed.project, 'p');
      expect(parsed.app, 'a');
      expect(parsed.defaultEnvironment, 'dev');
    });

    test('omits the defaultEnvironment key when null', () {
      const config = RestageConfig(project: 'p', app: 'a');
      final yaml = config.toYaml();
      expect(yaml, isNot(contains('defaultEnvironment')));
    });
  });

  group('loadRestageConfig', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('mc_load_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('discovers a config in the starting directory', () async {
      final config = File(p.join(tempDir.path, 'restage_config.yaml'));
      await config.writeAsString('project: p\napp: a\n');

      final result = await loadRestageConfig(from: tempDir);

      expect(result, isNotNull);
      expect(result!.config.project, 'p');
      expect(result.source.path, config.path);
    });

    test('walks up to find a config in an ancestor directory', () async {
      final config = File(p.join(tempDir.path, 'restage_config.yaml'));
      await config.writeAsString('project: p\napp: a\n');
      final nested = Directory(p.join(tempDir.path, 'a', 'b', 'c'));
      await nested.create(recursive: true);

      final result = await loadRestageConfig(from: nested);

      expect(result, isNotNull);
      expect(result!.source.path, config.path);
    });

    test('returns null when no config is found above the start', () async {
      final result = await loadRestageConfig(from: tempDir);
      expect(result, isNull);
    });

    test('propagates a format exception when the file is malformed', () async {
      final config = File(p.join(tempDir.path, 'restage_config.yaml'));
      await config.writeAsString('project: p\n'); // missing required `app`

      await expectLater(
        loadRestageConfig(from: tempDir),
        throwsA(isA<RestageConfigFormatException>()),
      );
    });
  });
}
