import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/commands/surface_kill_command.dart';
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
    tempDir = await Directory.systemTemp.createTemp('surface_kill_');
    fakeStore = FileCredentialStore(p.join(tempDir.path, 'credentials'));
    await seedCredential(fakeStore);
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  http.Response statusResponse({int? liveVersion = 1}) => http.Response(
    jsonEncode({
      '__className__': 'SurfaceStatusResult',
      'surfaceType': 'paywall',
      'surfaceSlug': 'pro',
      'environmentSlug': 'staging',
      'liveVersion': liveVersion,
      'locked': false,
      'deliveryShape': 'blob',
      'versions': <Map<String, dynamic>>[],
    }),
    200,
  );

  http.Response killOkResponse() => http.Response('', 200);

  CommandRunner<int> makeRunner({
    required StringSink stdout,
    required StringSink stderr,
    required http.Client httpClient,
    Interactive interactive = const NonInteractive(),
    SurfaceType? fixedSurfaceType = SurfaceType.paywall,
  }) {
    final runner = CommandRunner<int>('restage', '');
    runner.addCommand(
      SurfaceKillCommand(
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

  group('surface kill', () {
    test('(a) kill pro --env staging --reason x --yes calls kill(frozen:false) '
        'and exits 0', () async {
      Map<String, dynamic>? capturedKillBody;
      final client = scriptedHttpClient([
        (req) {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          expect(body['method'], 'surfaceStatus');
          return statusResponse();
        },
        (req) {
          capturedKillBody = jsonDecode(req.body) as Map<String, dynamic>;
          return killOkResponse();
        },
      ]);

      final out = StringBuffer();
      final code =
          await makeRunner(
            stdout: out,
            stderr: StringBuffer(),
            httpClient: client,
          ).run([
            'kill',
            'pro',
            '--env',
            'staging',
            '--reason',
            'x',
            '--yes',
            '--project',
            'p',
            '--app',
            'a',
          ]);

      expect(code, 0);
      expect(capturedKillBody, isNotNull);
      expect(capturedKillBody!['method'], 'killSurface');
      expect(capturedKillBody!['mode'], 'transient');
      expect(out.toString(), contains('Killed "pro"'));
      expect(out.toString(), contains('staging'));
      expect(out.toString(), isNot(contains('(frozen)')));
    });

    test(
      '(b) --frozen passes frozen:true (mode: "frozen") in kill request',
      () async {
        Map<String, dynamic>? capturedKillBody;
        final client = scriptedHttpClient([
          (_) => statusResponse(),
          (req) {
            capturedKillBody = jsonDecode(req.body) as Map<String, dynamic>;
            return killOkResponse();
          },
        ]);

        final out = StringBuffer();
        final code =
            await makeRunner(
              stdout: out,
              stderr: StringBuffer(),
              httpClient: client,
            ).run([
              'kill',
              'pro',
              '--env',
              'staging',
              '--reason',
              'x',
              '--yes',
              '--frozen',
              '--project',
              'p',
              '--app',
              'a',
            ]);

        expect(code, 0);
        expect(capturedKillBody!['mode'], 'frozen');
        expect(out.toString(), contains('(frozen)'));
      },
    );

    test(
      '(c) missing --reason exits 1 with Required: --reason, kill not called',
      () async {
        var apiCalled = false;
        final client = mockHttpClient((req) {
          apiCalled = true;
          return http.Response('', 500);
        });

        final err = StringBuffer();
        final code =
            await makeRunner(
              stdout: StringBuffer(),
              stderr: err,
              httpClient: client,
            ).run([
              'kill',
              'pro',
              '--env',
              'staging',
              '--yes',
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

    test('(d) --env production --yes exits 1 (refused by prod guardrail), '
        'kill not called', () async {
      var killCalled = false;
      final client = scriptedHttpClient([
        // Status is fetched before confirmDestructive runs
        (_) => statusResponse(),
        (req) {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          if (body['method'] == 'killSurface') killCalled = true;
          return killOkResponse();
        },
      ]);

      final err = StringBuffer();
      final code =
          await makeRunner(
            stdout: StringBuffer(),
            stderr: err,
            httpClient: client,
          ).run([
            'kill',
            'pro',
            '--env',
            'production',
            '--reason',
            'x',
            '--yes',
            '--project',
            'p',
            '--app',
            'a',
          ]);

      expect(code, 1);
      expect(err.toString(), contains('production'));
      expect(killCalled, isFalse);
    });

    test(
      '(e) interactive decline prints Aborted. and exits 1, kill NOT called',
      () async {
        var killCalled = false;
        final client = scriptedHttpClient([
          (_) => statusResponse(), // only status is fetched
          (req) {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            if (body['method'] == 'killSurface') killCalled = true;
            return killOkResponse();
          },
        ]);

        final out = StringBuffer();
        final code =
            await makeRunner(
              stdout: out,
              stderr: StringBuffer(),
              httpClient: client,
              interactive: const _FakeInteractive(confirmAnswer: false),
            ).run([
              'kill',
              'pro',
              '--env',
              'staging', // non-prod → interactive path
              '--reason',
              'x',
              // no --yes → goes to interactive confirm
              '--project',
              'p',
              '--app',
              'a',
            ]);

        expect(code, 1);
        expect(out.toString(), contains('Aborted.'));
        expect(killCalled, isFalse);
      },
    );
  });
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

class _FakeInteractive implements Interactive {
  const _FakeInteractive({this.confirmAnswer = false});
  final bool confirmAnswer;

  @override
  bool get isInteractive => true;

  @override
  Future<String> prompt(String question, {String? defaultValue}) async =>
      defaultValue ?? '';

  @override
  Future<bool> confirm(String question, {bool defaultYes = false}) async =>
      confirmAnswer;

  @override
  Future<T> select<T>(
    String question,
    List<({String label, T value})> options, {
    T? defaultValue,
  }) async => defaultValue ?? options.first.value;

  @override
  Future<String> secret(String question) async => '';

  @override
  Spinner spinner(String message) => throw UnimplementedError();
}
