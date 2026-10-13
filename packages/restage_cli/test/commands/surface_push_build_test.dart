import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/commands/surface_push_command.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../_helpers/publication_fixtures.dart';
import '../_helpers/test_fixtures.dart';

void main() {
  late Directory app;
  late Directory home;
  late FileCredentialStore store;
  late StringBuffer out;
  late StringBuffer err;

  /// A backend that accepts the push and lists [heads] for the app.
  http.Client backend({required List<Object?> heads, List<String>? methods}) =>
      mockHttpClient((request) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        methods?.add(body['method'] as String);
        if (body['method'] == 'listHeads') {
          return http.Response(
            jsonEncode(<String, Object?>{
              'appId': 5,
              'environmentHeads': heads,
              'personalHeads': <Object?>[],
            }),
            200,
          );
        }
        return publishSucceeded(
          'pro_upgrade',
          storedRevision: 3,
          activeRevision: 3,
        );
      });

  Map<String, Object?> stagingHead(
    Map<String, int> libraries,
  ) => <String, Object?>{
    'head': 'staging',
    'updatedAt': DateTime.utc(2030).toIso8601String(),
    'version': <String, Object?>{
      'renderBundleId': 44,
      'appId': 5,
      'version': 4,
      'contentHash': 'sha256:${'0' * 64}',
      'engineSetId': '1' * 64,
      'capabilityManifestJson': jsonEncode(<String, Object?>{
        'formatVersion': 1,
        'catalog': <String, Object?>{
          'libraries': <String, Object?>{
            for (final entry in libraries.entries)
              entry.key: <String, Object?>{'capabilityVersion': entry.value},
          },
          'widgets': <Object?>[],
        },
      }),
      'byteLength': 1024,
      'sourceDirty': false,
      'uploadedAt': DateTime.utc(2030).toIso8601String(),
    },
  };

  Future<int?> push(
    List<String> args, {
    required http.Client client,
    Command<int> Function()? buildCommand,
  }) {
    final command = SurfacePushCommand(
      stdout: out,
      stderr: err,
      interactive: const NonInteractive(),
      credentialStore: store,
      httpClient: client,
      buildCommand: buildCommand,
    );
    return (CommandRunner<int>(
      'restage',
      '',
    )..addCommand(command)).run(['push', ...args, '-C', app.path]);
  }

  setUp(() async {
    app = await Directory.systemTemp.createTemp('surface_push_build_');
    home = await Directory.systemTemp.createTemp('surface_push_build_home_');
    store = FileCredentialStore(p.join(home.path, 'credentials'));
    await seedCredential(store);
    out = StringBuffer();
    err = StringBuffer();
    File(p.join(app.path, 'restage_config.yaml')).writeAsStringSync(
      'project: demo\napp: mobile\ndefaultEnvironment: staging\n',
    );
    await seedGeneratedPaywall(
      app,
      requiredLibraries: const [
        LibraryRequirement(namespace: 'acme.widgets', minVersion: 2),
      ],
    );
  });

  tearDown(() {
    app.deleteSync(recursive: true);
    home.deleteSync(recursive: true);
  });

  test('a push says when the dashboard has no build for its widgets', () async {
    final code = await push(['pro_upgrade'], client: backend(heads: const []));

    expect(code, 0, reason: err.toString());
    expect(
      out.toString(),
      contains(
        'This surface uses widgets from your app (acme.widgets). The '
        'dashboard has no build of mobile for staging yet',
      ),
    );
  });

  test('a push whose widgets the build covers says nothing', () async {
    final code = await push(
      ['pro_upgrade'],
      client: backend(
        heads: [
          stagingHead(const {'acme.widgets': 2}),
        ],
      ),
    );

    expect(code, 0, reason: err.toString());
    expect(out.toString(), isNot(contains('widgets from your app')));
  });

  test('a surface built from the catalog alone never asks', () async {
    await seedGeneratedPaywall(app, slug: 'pro_upgrade');
    final methods = <String>[];
    final code = await push([
      'pro_upgrade',
    ], client: backend(heads: const [], methods: methods));

    expect(code, 0, reason: err.toString());
    expect(methods, isNot(contains('listHeads')));
    expect(out.toString(), isNot(contains('widgets from your app')));
  });

  test('--build pushes the build to the same environment first', () async {
    final seen = <List<String>>[];
    final code = await push(
      ['pro_upgrade', '--build'],
      client: backend(
        heads: [
          stagingHead(const {'acme.widgets': 2}),
        ],
      ),
      buildCommand: () => _FakeBuildCommand(seen, exitCode: 0),
    );

    expect(code, 0, reason: err.toString());
    expect(seen, hasLength(1));
    expect(seen.single, containsAllInOrder(<String>['--env', 'staging']));
    expect(seen.single, containsAllInOrder(<String>['--app', 'mobile']));
    expect(out.toString(), contains('Pushing the build of mobile to staging'));
    expect(out.toString(), contains('Pushed pro_upgrade'));
  });

  test('a build that fails stops the push before any surface goes', () async {
    final methods = <String>[];
    final code = await push(
      ['pro_upgrade', '--build'],
      client: backend(heads: const [], methods: methods),
      buildCommand: () => _FakeBuildCommand(<List<String>>[], exitCode: 1),
    );

    expect(code, 1);
    expect(methods, isNot(contains('publishPublication')));
  });
}

/// Stands in for `restage build`; its `push` records what it was asked.
final class _FakeBuildCommand extends Command<int> {
  _FakeBuildCommand(List<List<String>> seen, {required int exitCode}) {
    addSubcommand(_FakeBuildPushCommand(seen, exitCode: exitCode));
  }

  @override
  String get name => 'build';

  @override
  String get description => '';
}

final class _FakeBuildPushCommand extends Command<int> {
  _FakeBuildPushCommand(this._seen, {required int exitCode})
    : _exitCode = exitCode {
    argParser
      ..addOption('project')
      ..addOption('app')
      ..addOption('organization')
      ..addOption('env')
      ..addOption('directory', abbr: 'C')
      ..addFlag('record-git', negatable: false);
  }

  final List<List<String>> _seen;
  final int _exitCode;

  @override
  String get name => 'push';

  @override
  String get description => '';

  @override
  Future<int> run() async {
    _seen.add(argResults!.arguments);
    return _exitCode;
  }
}
