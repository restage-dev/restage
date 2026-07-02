import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/commands/surface_rollback_command.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../_helpers/test_fixtures.dart';

void main() {
  late Directory tempDir;
  late FileCredentialStore fakeStore;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('surface_rollback_');
    fakeStore = FileCredentialStore(p.join(tempDir.path, 'credentials'));
    await seedCredential(fakeStore);
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  // Default status has blob shape, liveVersion 3, and published versions
  // 1–3 so tests can target version 1 as a known-good rollback target.
  http.Response statusResponse({
    String deliveryShape = 'blob',
    int? liveVersion = 3,
    List<Map<String, dynamic>> versions = const [
      {
        'version': 1,
        'publishedAt': '2026-01-01T00:00:00.000Z',
        'contentHash': 'aaa',
        'isActive': false,
      },
      {
        'version': 2,
        'publishedAt': '2026-01-02T00:00:00.000Z',
        'contentHash': 'bbb',
        'isActive': false,
      },
      {
        'version': 3,
        'publishedAt': '2026-01-03T00:00:00.000Z',
        'contentHash': 'ccc',
        'isActive': true,
      },
    ],
  }) => http.Response(
    jsonEncode({
      '__className__': 'SurfaceStatusResult',
      'surfaceType': 'paywall',
      'surfaceSlug': 'pro',
      'environmentSlug': 'staging',
      'liveVersion': liveVersion,
      'locked': false,
      'deliveryShape': deliveryShape,
      'versions': versions,
    }),
    200,
  );

  http.Response rollbackOkResponse() => http.Response('', 200);

  // The informational preflight the command calls after version validation and
  // before the confirm. Default is the common compatible case.
  http.Response preflightResponse({
    String classification = 'compatible',
    List<String> blockingChanges = const [],
  }) => http.Response(
    jsonEncode({
      '__className__': 'RollbackPreflightView',
      'surfaceType': 'paywall',
      'surfaceSlug': 'pro',
      'environmentSlug': 'staging',
      'toVersion': 1,
      'classification': classification,
      'blockingChanges': blockingChanges,
    }),
    200,
  );

  CommandRunner<int> makeRunner({
    required StringSink stdout,
    required StringSink stderr,
    required http.Client httpClient,
    Interactive interactive = const NonInteractive(),
    SurfaceType? fixedSurfaceType = SurfaceType.paywall,
  }) {
    final runner = CommandRunner<int>('restage', '');
    runner.addCommand(
      SurfaceRollbackCommand(
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

  // Shared positional args and required flags for all tests.
  List<String> baseArgs({
    String slug = 'pro',
    String env = 'staging',
    String toVersion = '1',
    String reason = 'x',
    bool yes = true,
    bool freeze = false,
    String project = 'p',
    String app = 'a',
  }) => [
    'rollback',
    slug,
    '--to-version',
    toVersion,
    '--env',
    env,
    '--reason',
    reason,
    if (yes) '--yes',
    if (freeze) '--freeze',
    '--project',
    project,
    '--app',
    app,
  ];

  group('surface rollback', () {
    test(
      '(a) rollback pro --to-version 1 --env staging --reason x --yes '
      'calls rollbackSurface(toVersion:1, lockAfter:false) and exits 0',
      () async {
        Map<String, dynamic>? capturedBody;
        final client = scriptedHttpClient([
          (req) {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            expect(body['method'], 'surfaceStatus');
            return statusResponse();
          },
          (req) {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            expect(body['method'], 'rollbackPreflight');
            return preflightResponse();
          },
          (req) {
            capturedBody = jsonDecode(req.body) as Map<String, dynamic>;
            return rollbackOkResponse();
          },
        ]);

        final out = StringBuffer();
        final code = await makeRunner(
          stdout: out,
          stderr: StringBuffer(),
          httpClient: client,
        ).run(baseArgs());

        expect(code, 0);
        expect(capturedBody, isNotNull);
        expect(capturedBody!['method'], 'rollbackSurface');
        expect(capturedBody!['toVersion'], 1);
        expect(capturedBody!['lockAfter'], false);
        expect(out.toString(), contains('Rolled back "pro"'));
        expect(out.toString(), contains('v1'));
        expect(out.toString(), isNot(contains('(frozen)')));
      },
    );

    test('(b) --freeze passes lockAfter:true in rollback request', () async {
      Map<String, dynamic>? capturedBody;
      final client = scriptedHttpClient([
        (_) => statusResponse(),
        (_) => preflightResponse(),
        (req) {
          capturedBody = jsonDecode(req.body) as Map<String, dynamic>;
          return rollbackOkResponse();
        },
      ]);

      final out = StringBuffer();
      final code = await makeRunner(
        stdout: out,
        stderr: StringBuffer(),
        httpClient: client,
      ).run(baseArgs(freeze: true));

      expect(code, 0);
      expect(capturedBody!['lockAfter'], true);
      expect(out.toString(), contains('(frozen)'));
    });

    test('(c) a flow surface rolls back now (gate-1 relaxed) — preflight + '
        'rollback are called, exits 0', () async {
      var rollbackCalled = false;
      final client = scriptedHttpClient([
        (_) => statusResponse(deliveryShape: 'flow'), // default versions 1–3
        (req) {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          expect(body['method'], 'rollbackPreflight');
          return preflightResponse();
        },
        (req) {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          if (body['method'] == 'rollbackSurface') rollbackCalled = true;
          return rollbackOkResponse();
        },
      ]);

      final out = StringBuffer();
      final code = await makeRunner(
        stdout: out,
        stderr: StringBuffer(),
        httpClient: client,
      ).run(baseArgs());

      expect(code, 0);
      expect(rollbackCalled, isTrue);
      expect(out.toString(), contains('Rolled back "pro"'));
    });

    test('(d) missing --to-version exits 1, rollback NOT called', () async {
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
            'rollback',
            'pro',
            // intentionally no --to-version
            '--env', 'staging',
            '--reason', 'x',
            '--yes',
            '--project', 'p',
            '--app', 'a',
          ]);

      expect(code, 1);
      expect(err.toString(), contains('--to-version'));
      expect(apiCalled, isFalse);
    });

    test(
      '(e) --env production --yes exits 1 (prod guardrail), rollback NOT called',
      () async {
        var rollbackCalled = false;
        final client = scriptedHttpClient([
          // Status + preflight run before confirmDestructive.
          (_) => statusResponse(),
          (_) => preflightResponse(),
          (req) {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            if (body['method'] == 'rollbackSurface') rollbackCalled = true;
            return rollbackOkResponse();
          },
        ]);

        final err = StringBuffer();
        final code = await makeRunner(
          stdout: StringBuffer(),
          stderr: err,
          httpClient: client,
        ).run(baseArgs(env: 'production'));

        expect(code, 1);
        expect(err.toString(), contains('production'));
        expect(rollbackCalled, isFalse);
      },
    );

    test(
      '(f) --to-version 99 not in versions exits 1, rollback NOT called',
      () async {
        var rollbackCalled = false;
        final client = scriptedHttpClient([
          (_) => statusResponse(), // versions: 1, 2, 3
          (req) {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            if (body['method'] == 'rollbackSurface') rollbackCalled = true;
            return rollbackOkResponse();
          },
        ]);

        final err = StringBuffer();
        final code = await makeRunner(
          stdout: StringBuffer(),
          stderr: err,
          httpClient: client,
        ).run(baseArgs(toVersion: '99'));

        expect(code, 1);
        expect(err.toString(), contains('v99'));
        expect(err.toString(), contains('not found'));
        expect(rollbackCalled, isFalse);
      },
    );

    test(
      '(g) interactive decline prints Aborted. and exits 1, rollback NOT called',
      () async {
        var rollbackCalled = false;
        final client = scriptedHttpClient([
          (_) => statusResponse(), // status + preflight run before the confirm
          (_) => preflightResponse(),
          (req) {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            if (body['method'] == 'rollbackSurface') rollbackCalled = true;
            return rollbackOkResponse();
          },
        ]);

        final out = StringBuffer();
        final code = await makeRunner(
          stdout: out,
          stderr: StringBuffer(),
          httpClient: client,
          interactive: _FakeInteractive(confirmAnswer: false),
        ).run(baseArgs(yes: false)); // no --yes → goes to interactive confirm

        expect(code, 1);
        expect(out.toString(), contains('Aborted.'));
        expect(rollbackCalled, isFalse);
      },
    );

    test(
      '(h) SurfaceVersionNotFoundException body from rollback RPC prints clean '
      'message and exits 1',
      () async {
        // The rollback API returns a SurfaceVersionNotFoundException even for
        // a version that passed local validation (e.g. a concurrent delete).
        // This exercises the decoder + renderSurfaceException path end-to-end.
        final versionNotFoundBody = jsonEncode({
          'className': 'SurfaceVersionNotFoundException',
          'data': {
            '__className__': 'SurfaceVersionNotFoundException',
            'surfaceSlug': 'pro',
            'environmentSlug': 'staging',
            'version': 1, // wire key is 'version'
          },
        });
        final client = scriptedHttpClient([
          (_) => statusResponse(), // versions 1–3 pass local validation
          (_) => preflightResponse(),
          (_) => http.Response(versionNotFoundBody, 400),
        ]);

        final err = StringBuffer();
        final code = await makeRunner(
          stdout: StringBuffer(),
          stderr: err,
          httpClient: client,
        ).run(baseArgs()); // --to-version 1 passes local check

        expect(code, isNonZero);
        // Must be a legible message — not a stack trace or debug toString().
        final msg = err.toString();
        expect(msg, contains('v1'));
        expect(msg, contains('not found'));
        expect(
          msg,
          isNot(contains('SurfaceVersionNotFound(')),
        ); // no debug repr
      },
    );

    test(
      '(i) a flow-shaped paywall target (unsupportedTargetShape) is refused at '
      'the preflight — exits 1, rollback NOT called',
      () async {
        var rollbackCalled = false;
        final client = scriptedHttpClient([
          (_) => statusResponse(),
          (_) => preflightResponse(classification: 'unsupportedTargetShape'),
          (req) {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            if (body['method'] == 'rollbackSurface') rollbackCalled = true;
            return rollbackOkResponse();
          },
        ]);

        final err = StringBuffer();
        final code = await makeRunner(
          stdout: StringBuffer(),
          stderr: err,
          httpClient: client,
        ).run(baseArgs());

        expect(code, 1);
        expect(err.toString(), contains('flow-shaped version'));
        expect(err.toString(), contains("isn't"));
        expect(rollbackCalled, isFalse);
      },
    );

    test(
      '(j) a contractChange preflight surfaces a cohort-impact warning + the '
      'proxy caveat in the confirm prompt, then proceeds',
      () async {
        final client = scriptedHttpClient([
          (_) => statusResponse(deliveryShape: 'flow'),
          (_) => preflightResponse(
            classification: 'contractChange',
            blockingChanges: const [r'minClientRaised @ $.minClient: floor up'],
          ),
          (_) => rollbackOkResponse(),
        ]);

        final out = StringBuffer();
        final code = await makeRunner(
          stdout: out,
          stderr: StringBuffer(),
          httpClient: client,
          interactive: const _FakeInteractive(confirmAnswer: true),
        ).run(baseArgs(yes: false)); // interactive → the impact line is shown

        expect(code, 0);
        final shown = out.toString();
        expect(shown, contains('Cohort impact'));
        expect(shown, contains('fall back to their bundled copy'));
        expect(shown, contains('minClientRaised'));
        expect(shown, contains('re-checks against its own bundled copy'));
      },
    );

    test(
      '(k) a backend SurfaceRollbackUnsupportedException (defense-in-depth) '
      'prints the residual flow-shaped-paywall message and exits 1',
      () async {
        final unsupportedBody = jsonEncode({
          'className': 'SurfaceRollbackUnsupportedException',
          'data': {
            '__className__': 'SurfaceRollbackUnsupportedException',
            'surfaceSlug': 'pro',
          },
        });
        final client = scriptedHttpClient([
          (_) => statusResponse(),
          // The preflight says compatible, but the backend still refuses (a
          // race / poisoned row) — the error renderer must use the residual
          // wording, not the retired "active-flow delivery" message.
          (_) => preflightResponse(),
          (_) => http.Response(unsupportedBody, 400),
        ]);

        final err = StringBuffer();
        final code = await makeRunner(
          stdout: StringBuffer(),
          stderr: err,
          httpClient: client,
        ).run(baseArgs());

        expect(code, 1);
        expect(err.toString(), contains('flow-shaped version'));
        expect(err.toString(), isNot(contains('active-flow delivery')));
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
