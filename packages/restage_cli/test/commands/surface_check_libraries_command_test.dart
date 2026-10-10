import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/cli.dart';
import 'package:restage_cli/src/commands/surface_check_libraries_command.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_cli/src/libraries/library_contract_check.dart';
import 'package:test/test.dart';

import '../_helpers/test_fixtures.dart';

void main() {
  late Directory tempDir;
  late FileCredentialStore store;
  late StringBuffer stdout;
  late StringBuffer stderr;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('check_libraries_');
    store = FileCredentialStore(p.join(tempDir.path, 'credentials'));
    stdout = StringBuffer();
    stderr = StringBuffer();
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Future<void> writeSnapshot(
    String namespace,
    int version, {
    required int compatibleSince,
  }) async {
    final file = File(
      p.join(
        tempDir.path,
        '.restage',
        'library-contracts',
        namespace,
        'v$version.json',
      ),
    );
    await file.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'namespace': namespace,
        'capabilityVersion': version,
        'compatibleSince': compatibleSince,
        'widgets': <String, Object?>{},
      }),
    );
  }

  Map<String, Object?> liveItem({
    required String kind,
    required int minVersion,
    String environment = 'production',
    String surfaceType = 'paywall',
    String surfaceSlug = 'main',
    int publishedRevision = 7,
    Map<String, Object?> extra = const {},
  }) => {
    'environmentId': 1,
    'environmentSlug': environment,
    'kind': kind,
    'surfaceType': surfaceType,
    'surfaceSlug': surfaceSlug,
    'publishedRevision': publishedRevision,
    'requiredLibraries': [
      {'namespace': 'app', 'minVersion': minVersion},
    ],
    ...extra,
  };

  http.Client liveServer(List<Map<String, Object?>> items) =>
      mockHttpClient((request) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['method'] != 'liveLibraryRequirements') {
          throw StateError('Unexpected method: ${body['method']}');
        }
        expect(body['projectSlug'], 'demo');
        expect(body['appSlug'], 'mobile');
        return http.Response(jsonEncode({'items': items}), 200);
      });

  Future<int> check(http.Client client, [List<String> extra = const []]) =>
      (CommandRunner<int>('restage', 'test')..addCommand(
            SurfaceCheckLibrariesCommand(
              stdout: stdout,
              stderr: stderr,
              interactive: const NonInteractive(),
              credentialStore: store,
              httpClient: client,
            ),
          ))
          .run(['check-libraries', '-C', tempDir.path, ...extra])
          .then((code) => code ?? 0);

  group('restage surface check-libraries', () {
    test('lists a running experiment arm a declared break stops', () async {
      await seedCredential(store);
      await seedRestageConfig(tempDir, 'demo', 'mobile');
      await writeSnapshot('app', 3, compatibleSince: 1);
      await writeSnapshot('app', 4, compatibleSince: 4);

      final exitCode = await check(
        liveServer([
          liveItem(
            kind: 'experimentArm',
            minVersion: 3,
            extra: {
              'experimentId': 'winter-sale',
              'experimentLabel': 'Winter sale',
              'armId': 'b',
              'armLabel': 'B',
            },
          ),
          liveItem(kind: 'serving', minVersion: 4, publishedRevision: 8),
        ]),
      );

      expect(exitCode, 1);
      expect(
        stdout.toString(),
        'production\n'
        '  Experiment Winter sale arm B (paywall main v7) needs library app '
        'v3. This build renders v4 and later.\n',
      );
    });

    test('names delivery rules and serving versions, by environment', () async {
      await seedCredential(store);
      await seedRestageConfig(tempDir, 'demo', 'mobile');
      await writeSnapshot('app', 2, compatibleSince: 2);

      final exitCode = await check(
        liveServer([
          liveItem(kind: 'serving', minVersion: 1, environment: 'staging'),
          liveItem(
            kind: 'deliveryRule',
            minVersion: 1,
            publishedRevision: 3,
            extra: {'routeId': 'returning-users', 'versionLabel': 'Spring'},
          ),
        ]),
      );

      expect(exitCode, 1);
      expect(
        stdout.toString(),
        'production\n'
        '  Delivery rule returning-users (paywall main v3 (Spring)) needs '
        'library app v1. This build renders v2 and later.\n'
        'staging\n'
        '  Serving paywall main v7 needs library app v1. This build renders v2 '
        'and later.\n',
      );
    });

    test('passes when every live version still renders', () async {
      await seedCredential(store);
      await seedRestageConfig(tempDir, 'demo', 'mobile');
      await writeSnapshot('app', 4, compatibleSince: 4);

      final exitCode = await check(
        liveServer([liveItem(kind: 'serving', minVersion: 4)]),
      );

      expect(exitCode, 0);
      expect(stdout.toString(), 'All versions in use render on this build.\n');
    });

    test(
      'says so without asking the server when there are no contracts',
      () async {
        final exitCode = await check(
          mockHttpClient((_) => fail('no request without contracts')),
        );

        expect(exitCode, 0);
        expect(
          stdout.toString(),
          'No library contracts in .restage/library-contracts.\n',
        );
      },
    );

    test('emits the findings as JSON', () async {
      await seedCredential(store);
      await seedRestageConfig(tempDir, 'demo', 'mobile');
      await writeSnapshot('app', 4, compatibleSince: 4);

      final exitCode = await check(
        liveServer([
          liveItem(
            kind: 'experimentArm',
            minVersion: 3,
            extra: {'experimentId': 'winter-sale', 'armId': 'b'},
          ),
        ]),
        ['--json'],
      );

      expect(exitCode, 1);
      final json = jsonDecode(stdout.toString()) as List<dynamic>;
      expect(json, hasLength(1));
      expect(json.single, containsPair('kind', 'experimentArm'));
      expect(json.single, containsPair('namespace', 'app'));
      expect(json.single, containsPair('minVersion', 3));
      expect(json.single, containsPair('compatibleSince', 4));
    });
  });

  group('local library contracts', () {
    test('take compatibleSince from the highest snapshot', () async {
      await writeSnapshot('app', 3, compatibleSince: 3);
      await writeSnapshot('app', 5, compatibleSince: 4);
      await writeSnapshot('promo', 1, compatibleSince: 1);

      expect(localCompatibleSince(tempDir), {'app': 4, 'promo': 1});
    });

    test('refuse a malformed snapshot', () async {
      final file = File(
        p.join(tempDir.path, '.restage', 'library-contracts', 'app', 'v2.json'),
      );
      await file.create(recursive: true);
      await file.writeAsString('{"namespace": "app"}');

      expect(() => localCompatibleSince(tempDir), throwsFormatException);
    });
  });

  group('restage doctor', () {
    test('WARNs for each live version this build stops rendering', () async {
      await seedCredential(store);
      await seedRestageConfig(tempDir, 'demo', 'mobile');
      await writeSnapshot('app', 4, compatibleSince: 4);

      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: mockHttpClient((request) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (body['method'] == 'liveLibraryRequirements') {
            return http.Response(
              jsonEncode({
                'items': [
                  liveItem(
                    kind: 'experimentArm',
                    minVersion: 3,
                    extra: {'experimentId': 'winter-sale', 'armId': 'b'},
                  ),
                ],
              }),
              200,
            );
          }
          return http.Response(jsonEncode(<Object?>[]), 200);
        }),
      ).run(['doctor', '--directory', tempDir.path]);

      expect(exitCode, 0);
      expect(
        stdout.toString(),
        contains(
          'WARN  Library contracts\n'
          '      production: Experiment winter-sale arm b (paywall main v7) '
          'needs library app v3. This build renders v4 and later.\n',
        ),
      );
    });
  });
}
