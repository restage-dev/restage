import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:restage_cli/src/cli.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../_helpers/test_fixtures.dart';

void main() {
  late Directory tempDir;
  late FileCredentialStore store;
  late StringBuffer stdout;
  late StringBuffer stderr;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('catalog_push_');
    store = FileCredentialStore(p.join(tempDir.path, 'credentials'));
    stdout = StringBuffer();
    stderr = StringBuffer();
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Future<void> seedCatalog(String catalogJson) async {
    final file = File(
      p.join(tempDir.path, 'lib', 'src', 'widget_catalog', 'catalog.json'),
    );
    await file.parent.create(recursive: true);
    await file.writeAsString(catalogJson);
  }

  group('restage catalog push', () {
    test('uploads the emitted catalog and prints the stored version', () async {
      await seedCredential(store);
      await seedRestageConfig(tempDir, 'demo', 'mobile');
      const catalogJson = '{"schemaVersion":1,"widgets":[]}';
      await seedCatalog(catalogJson);

      var pushCalls = 0;
      final client = scriptedHttpClient([
        (req) {
          pushCalls++;
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          expect(body['method'], 'push');
          expect(body['projectSlug'], 'demo');
          expect(body['appSlug'], 'mobile');
          expect(body['catalogJson'], catalogJson);
          expect(
            (body['catalogJson'] as String),
            isNot(startsWith("decode('")),
          );
          return http.Response('4', 200);
        },
      ]);

      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: client,
      ).run(['catalog', 'push', '-C', tempDir.path]);

      expect(exitCode, 0);
      expect(pushCalls, 1);
      expect(stdout.toString(), contains('version 4'));
      expect(stderr.toString(), isEmpty);
    });

    test(
      'missing catalog exits 0 with a friendly note and no push call',
      () async {
        await seedCredential(store);
        await seedRestageConfig(tempDir, 'demo', 'mobile');

        var calls = 0;
        final client = scriptedHttpClient([
          (req) {
            calls++;
            return http.Response('1', 200);
          },
        ]);

        final exitCode = await RestageCli(
          stdout: stdout,
          stderr: stderr,
          credentialStore: store,
          httpClient: client,
        ).run(['catalog', 'push', '-C', tempDir.path]);

        expect(exitCode, 0);
        expect(calls, 0);
        expect(stdout.toString().toLowerCase(), contains('nothing to push'));
        expect(stderr.toString(), isEmpty);
      },
    );

    test('invalid catalog typed error prints a clear message', () async {
      await seedCredential(store);
      await seedRestageConfig(tempDir, 'demo', 'mobile');
      await seedCatalog('not a valid catalog');

      final client = scriptedHttpClient([
        (req) => http.Response(
          jsonEncode({
            'className': 'CatalogInvalidException',
            'data': {
              '__className__': 'CatalogInvalidException',
              'message': 'missing widgets',
            },
          }),
          400,
        ),
      ]);

      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: client,
      ).run(['catalog', 'push', '-C', tempDir.path]);

      expect(exitCode, 1);
      expect(stderr.toString(), contains('missing widgets'));
      expect(stderr.toString().toLowerCase(), contains('catalog'));
    });

    test('oversized catalog typed error prints a clear message', () async {
      await seedCredential(store);
      await seedRestageConfig(tempDir, 'demo', 'mobile');
      await seedCatalog('{}');

      final client = scriptedHttpClient([
        (req) => http.Response(
          jsonEncode({
            'className': 'CatalogTooLargeException',
            'data': {
              '__className__': 'CatalogTooLargeException',
              'maxBytes': 524288,
              'actualBytes': 524289,
            },
          }),
          400,
        ),
      ]);

      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: client,
      ).run(['catalog', 'push', '-C', tempDir.path]);

      expect(exitCode, 1);
      expect(stderr.toString().toLowerCase(), contains('too large'));
      expect(stderr.toString(), contains('524288'));
      expect(stderr.toString(), contains('524289'));
    });
  });
}
