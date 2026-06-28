import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/commands/surface_lock_command.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../_helpers/test_fixtures.dart';

void main() {
  late Directory tempDir;
  late FileCredentialStore fakeStore;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('surface_lock_');
    fakeStore = FileCredentialStore(p.join(tempDir.path, 'credentials'));
    await seedCredential(fakeStore);
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  http.Response lockOkResponse() => http.Response('', 200);

  CommandRunner<int> makeRunner({
    required bool lock,
    required StringSink stdout,
    required StringSink stderr,
    required http.Client httpClient,
    Interactive interactive = const NonInteractive(),
    SurfaceType? fixedSurfaceType = SurfaceType.paywall,
  }) {
    final runner = CommandRunner<int>('restage', '');
    runner.addCommand(
      SurfaceLockCommand(
        lock: lock,
        stdout: stdout,
        stderr: stderr,
        interactive: interactive,
        fixedSurfaceType: fixedSurfaceType,
        credentialStore: fakeStore,
        httpClient: httpClient,
      ),
    );
    return runner;
  }

  group('surface freeze / unfreeze', () {
    test(
      '(a) freeze pro --env production --reason x calls setLock(locked:true) '
      'and exits 0 (no confirmation — reversible)',
      () async {
        Map<String, dynamic>? capturedBody;
        final client = mockHttpClient((req) {
          capturedBody = jsonDecode(req.body) as Map<String, dynamic>;
          return lockOkResponse();
        });

        final out = StringBuffer();
        final code =
            await makeRunner(
              lock: true,
              stdout: out,
              stderr: StringBuffer(),
              httpClient: client,
            ).run([
              'freeze',
              'pro',
              '--env',
              'production',
              '--reason',
              'x',
              '--project',
              'p',
              '--app',
              'a',
            ]);

        expect(code, 0);
        expect(capturedBody, isNotNull);
        expect(capturedBody!['method'], 'setSurfaceLock');
        expect(capturedBody!['locked'], true);
        expect(out.toString(), contains('Froze "pro"'));
        expect(out.toString(), contains('production'));
      },
    );

    test('(b) unfreeze calls setLock(locked:false) and exits 0', () async {
      Map<String, dynamic>? capturedBody;
      final client = mockHttpClient((req) {
        capturedBody = jsonDecode(req.body) as Map<String, dynamic>;
        return lockOkResponse();
      });

      final out = StringBuffer();
      final code =
          await makeRunner(
            lock: false,
            stdout: out,
            stderr: StringBuffer(),
            httpClient: client,
          ).run([
            'unfreeze',
            'pro',
            '--env',
            'staging',
            '--reason',
            'x',
            '--project',
            'p',
            '--app',
            'a',
          ]);

      expect(code, 0);
      expect(capturedBody, isNotNull);
      expect(capturedBody!['method'], 'setSurfaceLock');
      expect(capturedBody!['locked'], false);
      expect(out.toString(), contains('Unfroze "pro"'));
    });

    test(
      '(c) missing --reason exits 1 with Required: --reason, setLock not called',
      () async {
        var apiCalled = false;
        final client = mockHttpClient((req) {
          apiCalled = true;
          return http.Response('', 500);
        });

        final err = StringBuffer();
        final code =
            await makeRunner(
              lock: true,
              stdout: StringBuffer(),
              stderr: err,
              httpClient: client,
            ).run([
              'freeze',
              'pro',
              '--env',
              'staging',
              '--project',
              'p',
              '--app',
              'a',
              // intentionally no --reason
            ]);

        expect(code, 1);
        expect(err.toString(), contains('Required:'));
        expect(err.toString(), contains('--reason'));
        expect(apiCalled, isFalse);
      },
    );
  });
}
