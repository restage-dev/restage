import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/config/restage_config.dart';
import 'package:restage_cli/src/credentials/credential.dart';
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

    test('old config without organization and endpoint still loads', () {
      const src = '''
project: my-project
app: my-app
''';
      final config = RestageConfig.fromYaml(src);
      expect(config.organization, isNull);
      expect(config.endpoint, isNull);
      expect(config.plane, isNull);
      expect(config.recordGit, isNull);
    });

    test('declareAssets round-trips; flutterRoot is read, never written', () {
      const config = RestageConfig(
        project: 'p',
        app: 'a',
        declareAssets: true,
        flutterRoot: '/opt/flutter',
      );

      final yaml = config.toYaml();
      expect(RestageConfig.fromYaml(yaml).declareAssets, isTrue);
      expect(yaml, isNot(contains('flutterRoot')));
      expect(
        RestageConfig.fromYaml(
          'project: p\napp: a\nflutterRoot: ../sdk\n',
        ).flutterRoot,
        '../sdk',
      );
    });

    test('recordGit round-trips and refuses a value that is not a flag', () {
      const config = RestageConfig(project: 'p', app: 'a', recordGit: true);

      expect(RestageConfig.fromYaml(config.toYaml()).recordGit, isTrue);
      expect(
        RestageConfig.fromYaml(
          'project: p\napp: a\nrecordGit: false\n',
        ).recordGit,
        isFalse,
      );
      expect(
        () => RestageConfig.fromYaml(
          'project: p\napp: a\nrecordGit: yes please\n',
        ),
        throwsA(isA<RestageConfigFormatException>()),
      );
    });

    test('plane round-trips and refuses an unknown plane', () {
      const config = RestageConfig(
        project: 'p',
        app: 'a',
        plane: RuntimePlane.sandbox,
      );
      expect(config.toYaml(), contains('plane: sandbox'));
      expect(
        RestageConfig.fromYaml(config.toYaml()).plane,
        RuntimePlane.sandbox,
      );
      expect(
        RestageConfig.fromYaml('project: p\napp: a\nplane: live\n').plane,
        RuntimePlane.live,
      );
      expect(
        () => RestageConfig.fromYaml('project: p\napp: a\nplane: prod\n'),
        throwsA(isA<RestageConfigFormatException>()),
      );
    });

    test('resolved IDs round-trip and reject invalid hints', () {
      const config = RestageConfig(
        project: 'p',
        app: 'a',
        organizationId: 7,
        appId: 5,
        environmentTargetId: 12,
        namedEnvironmentId: 22,
      );
      final parsed = RestageConfig.fromYaml(config.toYaml());
      expect(parsed.organizationId, 7);
      expect(parsed.appId, 5);
      expect(parsed.environmentTargetId, 12);
      expect(parsed.namedEnvironmentId, 22);
      expect(
        () => RestageConfig.fromYaml('project: p\napp: a\nappId: -5\n'),
        throwsA(isA<RestageConfigFormatException>()),
      );
      expect(config.withConfirmedOrganizationId(8).appId, isNull);
      expect(config.withConfirmedAppIds(7, 6).environmentTargetId, isNull);
      expect(config.withConfirmedAppIds(7, 5).environmentTargetId, 12);
    });

    test('leaves missing project and app unset', () {
      final config = RestageConfig.fromYaml('plane: sandbox\n');

      expect(config.project, isNull);
      expect(config.app, isNull);
      expect(config.toYaml(), isNot(contains('project:')));
      expect(config.toYaml(), isNot(contains('app:')));
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

    test('round-trips optional organization, endpoint and plane', () {
      const config = RestageConfig(
        project: 'p',
        app: 'a',
        defaultEnvironment: 'staging',
        organization: 'default',
        endpoint: 'https://api.restage.dev/',
        plane: RuntimePlane.live,
      );
      final yaml = config.toYaml();
      final parsed = RestageConfig.fromYaml(yaml);
      expect(parsed.project, 'p');
      expect(parsed.app, 'a');
      expect(parsed.defaultEnvironment, 'staging');
      expect(parsed.organization, 'default');
      expect(parsed.endpoint, 'https://api.restage.dev/');
      expect(parsed.plane, RuntimePlane.live);
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
      await config.writeAsString('project: p\napp: 7\n');

      await expectLater(
        loadRestageConfig(from: tempDir),
        throwsA(isA<RestageConfigFormatException>()),
      );
    });
  });

  group('example project config', () {
    for (final example in const [
      'apps/examples',
      'packages/restage_widgetbook_example',
    ]) {
      test('$example leaves restage_config.yaml to restage init', () async {
        final dir = Directory(p.join(_locateCheckoutRoot().path, example));

        final tracked = await Process.run('git', [
          'ls-files',
          '--',
          'restage_config.yaml',
        ], workingDirectory: dir.path);
        expect(tracked.exitCode, 0, reason: '${tracked.stderr}');
        expect((tracked.stdout as String).trim(), isEmpty);

        final ignore = File(p.join(dir.path, '.gitignore')).readAsLinesSync();
        expect(ignore, contains('restage_config.yaml'));

        final readme = File(p.join(dir.path, 'README.md')).readAsStringSync();
        expect(readme, contains('restage init'));
      });
    }
  });

  group('resolveApiEndpoint', () {
    test('uses the credential endpoint when no config is loaded', () {
      final endpoint = resolveApiEndpoint(
        config: null,
        credential: _credential(endpoint: 'https://safe.example.com/'),
      );

      expect(endpoint, Uri.parse('https://safe.example.com/'));
    });

    test('uses the credential endpoint when config has no endpoint', () {
      final endpoint = resolveApiEndpoint(
        config: const RestageConfig(project: 'p', app: 'a'),
        credential: _credential(endpoint: 'https://safe.example.com/'),
      );

      expect(endpoint, Uri.parse('https://safe.example.com/'));
    });

    test('allows a config endpoint that matches the credential endpoint', () {
      final endpoint = resolveApiEndpoint(
        config: const RestageConfig(
          project: 'p',
          app: 'a',
          endpoint: 'https://safe.example.com/api',
        ),
        credential: _credential(endpoint: 'https://safe.example.com/api/'),
      );

      expect(endpoint, Uri.parse('https://safe.example.com/api/'));
    });

    test('treats an empty root path and slash root path as equivalent', () {
      final endpoint = resolveApiEndpoint(
        config: const RestageConfig(
          project: 'p',
          app: 'a',
          endpoint: 'https://safe.example.com/',
        ),
        credential: _credential(endpoint: 'https://safe.example.com'),
      );

      expect(endpoint, Uri.parse('https://safe.example.com/'));
    });

    test('rejects a malformed config endpoint with a config error', () {
      expect(
        () => resolveApiEndpoint(
          config: const RestageConfig(
            project: 'p',
            app: 'a',
            endpoint: 'https://[bad',
          ),
          credential: _credential(endpoint: 'https://safe.example.com/'),
        ),
        throwsA(
          isA<EndpointFormatException>().having(
            (e) => e.toString(),
            'message',
            allOf(
              contains('Invalid endpoint in restage_config.yaml'),
              contains('https://[bad'),
            ),
          ),
        ),
      );
    });

    test('rejects a config endpoint that differs from the credential', () {
      expect(
        () => resolveApiEndpoint(
          config: const RestageConfig(
            project: 'p',
            app: 'a',
            endpoint: 'https://evil.example.com/',
          ),
          credential: _credential(endpoint: 'https://safe.example.com/'),
        ),
        throwsA(
          isA<EndpointMismatchException>()
              .having(
                (e) => e.configEndpoint,
                'config endpoint',
                Uri.parse('https://evil.example.com/'),
              )
              .having(
                (e) => e.credentialEndpoint,
                'credential endpoint',
                Uri.parse('https://safe.example.com/'),
              )
              .having(
                (e) => e.toString(),
                'message',
                contains('restage login --endpoint https://evil.example.com/'),
              ),
        ),
      );
    });
  });
}

Credential _credential({required String endpoint}) => Credential(
  endpoint: endpoint,
  kind: CredentialKind.authKey,
  authToken: 'kid:secret',
);

Directory _locateCheckoutRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 8; i++) {
    if (File(
      p.join(dir.path, 'apps', 'examples', 'pubspec.yaml'),
    ).existsSync()) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  throw StateError(
    'Could not locate the checkout root from ${Directory.current}',
  );
}
