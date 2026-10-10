import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/cli.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:test/test.dart';

import '../_helpers/test_fixtures.dart';

void main() {
  late Directory root;
  late FileCredentialStore store;
  late StringBuffer out;
  late StringBuffer err;

  Map<String, Object?> version(
    int number, {
    String? commit,
    bool dirty = false,
  }) => <String, Object?>{
    'renderBundleId': 40 + number,
    'appId': 5,
    'version': number,
    'contentHash': 'sha256:${'0' * 64}',
    'engineSetId': '1' * 64,
    'capabilityManifestJson': jsonEncode(<String, Object?>{
      'formatVersion': 1,
      'catalog': <String, Object?>{
        'libraries': <String, Object?>{},
        'widgets': <Object?>[],
      },
    }),
    'byteLength': 1024,
    'sourceCommit': ?commit,
    'sourceDirty': dirty,
    'uploadedAt': DateTime.utc(2030).toIso8601String(),
  };

  http.Client backend({
    List<Object?> environmentHeads = const [],
    List<Object?> personalHeads = const [],
    List<Map<String, dynamic>>? calls,
  }) => mockHttpClient((request) {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    calls?.add(body);
    expect(body['method'], 'listHeads');
    return http.Response(
      jsonEncode(<String, Object?>{
        'appId': 5,
        'environmentHeads': environmentHeads,
        'personalHeads': personalHeads,
      }),
      200,
    );
  });

  Future<int?> run(http.Client client, [List<String> args = const []]) =>
      RestageCli(
        stdout: out,
        stderr: err,
        credentialStore: store,
        httpClient: client,
      ).run(['build', 'list', '-C', root.path, ...args]);

  setUp(() async {
    root = await Directory.systemTemp.createTemp('build_list_test_');
    store = FileCredentialStore(p.join(root.path, 'credentials'));
    await seedCredential(store);
    await seedRestageConfig(root, 'demo', 'mobile');
    out = StringBuffer();
    err = StringBuffer();
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('lists each environment build and each personal build', () async {
    final calls = <Map<String, dynamic>>[];
    final code = await run(
      backend(
        calls: calls,
        environmentHeads: [
          <String, Object?>{
            'appId': 5,
            'namedEnvironmentId': 22,
            'head': 'staging',
            'version': version(4, commit: 'a91f2c3d4e5f6071'),
            'updatedAt': DateTime.utc(2030, 1, 2).toIso8601String(),
          },
        ],
        personalHeads: [
          <String, Object?>{
            'appId': 5,
            'ownerUserInfoId': 3,
            'ownerDisplayName': 'Jake',
            'handle': 'jake',
            'head': 'user/jake',
            'version': version(2, dirty: true, commit: 'b1c2d3e4'),
            'updatedAt': DateTime.utc(2030, 1, 3).toIso8601String(),
          },
        ],
      ),
    );

    expect(code, 0, reason: err.toString());
    expect(calls.single['projectSlug'], 'demo');
    expect(calls.single['appSlug'], 'mobile');
    expect(
      out.toString(),
      'staging\tversion 4\ta91f2c3\t2030-01-02T00:00:00.000Z\n'
      'user/jake\tversion 2\tb1c2d3e (local changes)\t2030-01-03T00:00:00.000Z\t'
      'Jake\n',
    );
  });

  test('an app with no builds says how to push one', () async {
    final code = await run(backend());

    expect(code, 0, reason: err.toString());
    expect(
      out.toString(),
      'No builds yet. Run `restage build push --env <slug>` to push one.\n',
    );
  });

  test('--organization picks the organization', () async {
    final code = await run(backend(), ['--organization', 'restage', '--json']);

    expect(code, 0, reason: err.toString());
    expect(jsonDecode(out.toString()), isEmpty);
  });

  group('a restage_config.yaml without project', () {
    setUp(() async {
      await File(
        p.join(root.path, 'restage_config.yaml'),
      ).writeAsString('plane: sandbox\n');
    });

    test('takes the slugs from flags', () async {
      final calls = <Map<String, dynamic>>[];
      final code = await run(backend(calls: calls), [
        '--project',
        'demo',
        '--app',
        'mobile',
      ]);

      expect(code, 0, reason: err.toString());
      expect(calls.single['projectSlug'], 'demo');
      expect(calls.single['appSlug'], 'mobile');
    });

    test('names the missing key and the fix', () async {
      final code = await run(backend(), ['--app', 'mobile']);

      expect(code, 1);
      expect(
        err.toString(),
        'restage_config.yaml has no `project`. Add `project: <slug>` to it, '
        'or pass --project <slug>.\n',
      );
    });
  });

  test('a malformed restage_config.yaml is a clean error', () async {
    await File(
      p.join(root.path, 'restage_config.yaml'),
    ).writeAsString('project: 123\napp: mobile\n');

    final code = await run(backend());

    expect(code, 1);
    expect(
      err.toString(),
      'Could not read restage_config.yaml: Expected `project` to be a string, '
      'got int.\n',
    );
  });
}
