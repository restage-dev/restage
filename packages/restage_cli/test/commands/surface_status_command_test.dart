import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/commands/surface_status_command.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../_helpers/test_fixtures.dart';

void main() {
  late Directory tempDir;
  late FileCredentialStore fakeStore;
  late http.Client fakeStatusClient;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('surface_status_');
    fakeStore = FileCredentialStore(p.join(tempDir.path, 'credentials'));
    await seedCredential(fakeStore);
    fakeStatusClient = mockHttpClient((req) {
      return http.Response(
        jsonEncode({
          '__className__': 'SurfaceStatusResult',
          'surfaceType': 'paywall',
          'surfaceSlug': 'pro',
          'environmentSlug': 'production',
          'liveVersion': 2,
          'locked': false,
          'deliveryShape': 'blob',
          'versions': [
            {
              '__className__': 'SurfaceVersionResult',
              'version': 2,
              'publishedAt': '2026-06-01T10:00:00.000Z',
              'contentHash': 'abc123def456',
              'isActive': true,
            },
            {
              '__className__': 'SurfaceVersionResult',
              'version': 1,
              'publishedAt': '2026-05-01T08:00:00.000Z',
              'contentHash': 'aaa111bbb222',
              'isActive': false,
            },
          ],
        }),
        200,
      );
    });
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('surface status / paywall status', () {
    test('status prints live version + shape + versions', () async {
      final out = StringBuffer();
      final runner = CommandRunner<int>('restage', '')
        ..addCommand(
          SurfaceStatusCommand(
            stdout: out,
            stderr: StringBuffer(),
            interactive: const NonInteractive(),
            fixedSurfaceType: SurfaceType.paywall,
            credentialStore: fakeStore,
            httpClient: fakeStatusClient,
          ),
        );
      final code = await runner.run([
        'status',
        'pro',
        '--project',
        'p',
        '--app',
        'a',
        '--env',
        'production',
      ]);
      expect(code, 0);
      expect(out.toString(), contains('live: v2'));
      expect(out.toString(), contains('blob'));
    });

    test('version rows appear in output with active marker', () async {
      final out = StringBuffer();
      final runner = CommandRunner<int>('restage', '')
        ..addCommand(
          SurfaceStatusCommand(
            stdout: out,
            stderr: StringBuffer(),
            interactive: const NonInteractive(),
            fixedSurfaceType: SurfaceType.paywall,
            credentialStore: fakeStore,
            httpClient: fakeStatusClient,
          ),
        );
      await runner.run([
        'status',
        'pro',
        '--project',
        'p',
        '--app',
        'a',
        '--env',
        'production',
      ]);
      final output = out.toString();
      expect(output, contains('v2'));
      expect(output, contains('(active)'));
      expect(output, contains('abc123def456'));
    });

    test('generic surface group works with --type', () async {
      final out = StringBuffer();
      final runner = CommandRunner<int>('restage', '')
        ..addCommand(
          SurfaceStatusCommand(
            stdout: out,
            stderr: StringBuffer(),
            interactive: const NonInteractive(),
            credentialStore: fakeStore,
            httpClient: fakeStatusClient,
          ),
        );
      final code = await runner.run([
        'status',
        'pro',
        '--type',
        'paywall',
        '--project',
        'p',
        '--app',
        'a',
        '--env',
        'production',
      ]);
      expect(code, 0);
      expect(out.toString(), contains('live: v2'));
    });

    test('missing --type in generic mode → exit 1 with --type hint', () async {
      final err = StringBuffer();
      final runner = CommandRunner<int>('restage', '')
        ..addCommand(
          SurfaceStatusCommand(
            stdout: StringBuffer(),
            stderr: err,
            interactive: const NonInteractive(),
            credentialStore: fakeStore,
            httpClient: fakeStatusClient,
          ),
        );
      final code = await runner.run([
        'status',
        'pro',
        '--project',
        'p',
        '--app',
        'a',
        '--env',
        'production',
      ]);
      expect(code, 1);
      expect(err.toString(), contains('--type'));
    });

    test('missing positional slug → exit 1', () async {
      final err = StringBuffer();
      final runner = CommandRunner<int>('restage', '')
        ..addCommand(
          SurfaceStatusCommand(
            stdout: StringBuffer(),
            stderr: err,
            interactive: const NonInteractive(),
            fixedSurfaceType: SurfaceType.paywall,
            credentialStore: fakeStore,
            httpClient: fakeStatusClient,
          ),
        );
      final code = await runner.run([
        'status',
        '--project',
        'p',
        '--app',
        'a',
        '--env',
        'production',
      ]);
      expect(code, 1);
      expect(err.toString().toLowerCase(), contains('slug'));
    });

    test('not signed in → exit 1 with login hint', () async {
      final noCredStore = FileCredentialStore(p.join(tempDir.path, 'no_cred'));
      final err = StringBuffer();
      final runner = CommandRunner<int>('restage', '')
        ..addCommand(
          SurfaceStatusCommand(
            stdout: StringBuffer(),
            stderr: err,
            interactive: const NonInteractive(),
            fixedSurfaceType: SurfaceType.paywall,
            credentialStore: noCredStore,
            httpClient: fakeStatusClient,
          ),
        );
      final code = await runner.run([
        'status',
        'pro',
        '--project',
        'p',
        '--app',
        'a',
        '--env',
        'production',
      ]);
      expect(code, 1);
      expect(err.toString(), contains('restage login'));
    });
  });
}
