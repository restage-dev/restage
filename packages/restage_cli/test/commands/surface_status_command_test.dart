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
    test(
      'a category alone asks the server, which resolves the family',
      () async {
        Map<String, dynamic>? body;
        final client = mockHttpClient((request) {
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              '__className__': 'SurfaceStatusView',
              'surfaceType': 'message',
              'surfaceSlug': 'recap',
              'environmentSlug': 'staging',
              'liveVersion': 2,
              'locked': false,
              'deliveryShape': 'blob',
              'sourceKind': 'screen',
              'contractVersion': 1,
              'versions': <Object>[],
            }),
            200,
          );
        });
        final out = StringBuffer();
        final err = StringBuffer();
        final runner = CommandRunner<int>('restage', '')
          ..addCommand(
            SurfaceStatusCommand(
              stdout: out,
              stderr: err,
              interactive: const NonInteractive(),
              credentialStore: fakeStore,
              httpClient: client,
            ),
          );
        final code = await runner.run([
          'status',
          'recap',
          '--type',
          'message',
          '-C',
          tempDir.path,
          '--project',
          'p',
          '--app',
          'a',
          '--env',
          'staging',
        ]);
        expect(code, 0, reason: err.toString());
        expect(body!['method'], 'surfaceStatus');
        expect(body!['contractVersion'], isNull);
        expect(body!.containsKey('sourceKind'), isFalse);
        expect(out.toString(), contains('live: v2'));
      },
    );

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

    test(
      'sends the configured organization with the target selectors',
      () async {
        await seedRestageConfig(
          tempDir,
          'demo',
          'mobile',
          defaultEnvironment: 'staging',
          organization: 'restage',
        );
        Map<String, dynamic>? capturedStatusBody;
        final client = scriptedHttpClient([
          resolveTargetStep({
            'environmentTargetId': 12,
            'namedEnvironmentId': 22,
            'environmentSlug': 'staging',
            'runtimePlane': 'sandbox',
          }, inspect: (body) => expect(body['organizationSlug'], 'restage')),
          (req) {
            capturedStatusBody = jsonDecode(req.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode({
                '__className__': 'SurfaceStatusResult',
                'surfaceType': 'paywall',
                'surfaceSlug': 'pro',
                'environmentSlug': 'staging',
                'liveVersion': null,
                'locked': false,
                'deliveryShape': 'blob',
                'versions': <Map<String, dynamic>>[],
              }),
              200,
            );
          },
        ], withDefaultTargetDiscovery: false);

        final out = StringBuffer();
        final runner = CommandRunner<int>('restage', '')
          ..addCommand(
            SurfaceStatusCommand(
              stdout: out,
              stderr: StringBuffer(),
              interactive: const NonInteractive(),
              fixedSurfaceType: SurfaceType.paywall,
              credentialStore: fakeStore,
              httpClient: client,
            ),
          );
        final code = await runner.run(['status', 'pro', '-C', tempDir.path]);

        expect(code, 0);
        expect(capturedStatusBody, isNotNull);
        expect(capturedStatusBody!['method'], 'surfaceStatus');
        expect(capturedStatusBody!['projectSlug'], 'demo');
        expect(capturedStatusBody!['appSlug'], 'mobile');
        expect(capturedStatusBody!['organizationId'], 7);
      },
    );

    test('generic surface group requires an explicit source kind', () async {
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
        '--source-kind',
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

    test('missing positional id → exit 1', () async {
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
      expect(err.toString(), contains('Missing positional argument: <id>.'));
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

  group('delivery mode rendering', () {
    http.Client flowStatusClient() => mockHttpClient((req) {
      return http.Response(
        jsonEncode({
          '__className__': 'SurfaceStatusResult',
          'surfaceType': 'onboarding',
          'surfaceSlug': 'first-run',
          'environmentSlug': 'production',
          'liveVersion': 2,
          'locked': false,
          'deliveryShape': 'flow',
          'versions': [
            {
              '__className__': 'SurfaceVersionResult',
              'version': 2,
              'publishedAt': '2026-06-01T10:00:00.000Z',
              'contentHash': 'abc123def456',
              'isActive': true,
              'deliveryMode': 'general',
            },
            {
              '__className__': 'SurfaceVersionResult',
              'version': 1,
              'publishedAt': '2026-05-01T08:00:00.000Z',
              'contentHash': 'aaa111bbb222',
              'isActive': false,
              'deliveryMode': 'typed',
            },
          ],
        }),
        200,
      );
    });

    test('prints per-version delivery mode and the live mode', () async {
      final out = StringBuffer();
      final runner = CommandRunner<int>('restage', '')
        ..addCommand(
          SurfaceStatusCommand(
            stdout: out,
            stderr: StringBuffer(),
            interactive: const NonInteractive(),
            fixedSurfaceType: SurfaceType.onboarding,
            credentialStore: fakeStore,
            httpClient: flowStatusClient(),
          ),
        );
      final code = await runner.run([
        'status',
        'first-run',
        '--project',
        'p',
        '--app',
        'a',
        '--env',
        'production',
      ]);
      expect(code, 0);
      final output = out.toString();
      // Header carries the active version's mode.
      expect(output, contains('mode: general'));
      // Version rows each carry their own mode.
      final v2Row = output
          .split('\n')
          .firstWhere((l) => l.contains('v2 (active)'));
      expect(v2Row, contains('general'));
      final v1Row = output.split('\n').firstWhere((l) => l.contains('v1 '));
      expect(v1Row, contains('typed'));
    });

    test(
      'omits mode when the wire carries none (blob / older server)',
      () async {
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
        expect(out.toString(), isNot(contains('mode:')));
      },
    );
  });
}
