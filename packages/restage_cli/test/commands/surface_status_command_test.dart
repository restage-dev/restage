import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/api/byte_data_wire.dart';
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
          'draftOrigin': 'code',
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
          final decoded = jsonDecode(request.body) as Map<String, dynamic>;
          if (decoded['method'] == 'surfaceStatus') body = decoded;
          return http.Response(
            jsonEncode({
              '__className__': 'SurfaceStatusView',
              'surfaceType': 'message',
              'surfaceSlug': 'recap',
              'environmentSlug': 'staging',
              'liveVersion': 2,
              'locked': false,
              'deliveryShape': 'blob',
              'draftOrigin': 'code',
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

    test('says when the draft was edited after publishing from code', () async {
      Future<String> run(Map<String, Object?> fields) async {
        final out = StringBuffer();
        final client = mockHttpClient(
          (_) => http.Response(
            jsonEncode({
              '__className__': 'SurfaceStatusView',
              'surfaceType': 'paywall',
              'surfaceSlug': 'pro',
              'environmentSlug': 'production',
              'liveVersion': 2,
              'locked': false,
              'deliveryShape': 'blob',
              'draftOrigin': 'code',
              'versions': <Object>[],
              ...fields,
            }),
            200,
          ),
        );
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
        return out.toString();
      }

      final edited = await run({
        'draftOrigin': 'editor',
        'editedAfterCode': true,
      });
      expect(edited, contains('draft: editor'));
      expect(edited, contains('Edited after publishing from code'));

      final fromCode = await run({
        'draftOrigin': 'code',
        'editedAfterCode': false,
      });
      expect(fromCode, contains('draft: code'));
      expect(fromCode, isNot(contains('Edited after publishing from code')));
    });

    test('prints the line an app writes to show the live version', () async {
      final out = StringBuffer();
      final runner = CommandRunner<int>('restage', '')
        ..addCommand(
          SurfaceStatusCommand(
            stdout: out,
            stderr: StringBuffer(),
            interactive: const NonInteractive(),
            fixedSurfaceType: SurfaceType.onboarding,
            credentialStore: fakeStore,
            httpClient: mockHttpClient(
              (req) => http.Response(
                jsonEncode({
                  '__className__': 'SurfaceStatusResult',
                  'surfaceType': 'onboarding',
                  'surfaceSlug': 'lumen_onboarding',
                  'environmentSlug': 'production',
                  'liveVersion': 1,
                  'locked': false,
                  'deliveryShape': 'flow',
                  'draftOrigin': 'code',
                  'sourceKind': 'flowGraph',
                  'versions': [
                    {
                      '__className__': 'SurfaceVersionResult',
                      'version': 1,
                      'publishedAt': '2026-09-01T10:00:00.000Z',
                      'contentHash': 'abc123def456',
                      'isActive': true,
                      'mountName': 'LumenOnboardingFlowSurface',
                    },
                  ],
                }),
                200,
              ),
            ),
          ),
        );
      final code = await runner.run([
        'status',
        'lumen_onboarding',
        '--project',
        'p',
        '--app',
        'a',
        '--env',
        'production',
      ]);
      expect(code, 0);
      expect(
        out.toString(),
        contains('  in your app: LumenOnboardingFlowSurface(...)\n'),
      );
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
        final client = scriptedHttpClient(
          [
            scopeTargetStep({
              'environmentTargetId': 12,
              'namedEnvironmentId': 22,
              'environmentSlug': 'staging',
              'runtimePlane': 'sandbox',
            }, inspect: (body) => expect(body['method'], 'read')),
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
                  'draftOrigin': 'code',
                  'versions': <Map<String, dynamic>>[],
                }),
                200,
              );
            },
            (req) => http.Response(jsonEncode(_reachWire()), 200),
          ],
          withDefaultTargetDiscovery: false,
          withDefaultSurfaceReach: false,
        );

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

    group('without --type outside the manifest', () {
      Future<(int?, String, List<Map<String, dynamic>>)> run(
        Map<String, List<String>> slugsByType,
      ) async {
        final bodies = <Map<String, dynamic>>[];
        final client = mockHttpClient((request) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          bodies.add(body);
          if (body['method'] == 'list') {
            final type = body['surfaceType'] as String;
            return http.Response(
              jsonEncode([
                for (final slug in slugsByType[type] ?? const <String>[])
                  {
                    '__className__': 'SurfaceSummary',
                    'surfaceType': type,
                    'slug': slug,
                    'name': slug,
                    'draftUpdatedAt': '2026-05-01T12:34:56.000Z',
                    'publishedVersionByEnvironment': <String, int?>{},
                  },
              ]),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              '__className__': 'SurfaceStatusResult',
              'surfaceType': body['surfaceType'],
              'surfaceSlug': 'pro',
              'environmentSlug': 'production',
              'liveVersion': 2,
              'locked': false,
              'deliveryShape': 'blob',
              'draftOrigin': 'code',
              'versions': <Object>[],
            }),
            200,
          );
        });
        final err = StringBuffer();
        final runner = CommandRunner<int>('restage', '')
          ..addCommand(
            SurfaceStatusCommand(
              stdout: StringBuffer(),
              stderr: err,
              interactive: const NonInteractive(),
              credentialStore: fakeStore,
              httpClient: client,
            ),
          );
        final code = await runner.run([
          'status',
          'pro',
          '-C',
          tempDir.path,
          '--project',
          'p',
          '--app',
          'a',
          '--env',
          'production',
        ]);
        return (code, err.toString(), bodies);
      }

      test('looks the type up on the server by id', () async {
        final (code, err, bodies) = await run({
          'paywall': ['pro'],
          'onboarding': ['welcome'],
        });
        expect(code, 0, reason: err);
        final status = bodies.singleWhere(
          (body) => body['method'] == 'surfaceStatus',
        );
        expect(status['surfaceType'], 'paywall');
        expect(status['surfaceSlug'], 'pro');
      });

      test('names every type when the id is ambiguous', () async {
        final (code, err, bodies) = await run({
          'paywall': ['pro'],
          'message': ['pro'],
        });
        expect(code, 1);
        expect(
          err,
          contains(
            'Surface "pro" exists as more than one type: message, paywall. '
            'Pass --type <type> to choose one.',
          ),
        );
        expect(
          bodies.where((body) => body['method'] == 'surfaceStatus'),
          isEmpty,
        );
      });

      test('says so when no type has the id', () async {
        final (code, err, _) = await run(const {});
        expect(code, 1);
        expect(err, contains('No surface "pro" exists in app "a".'));
      });
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
          'draftOrigin': 'code',
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

  group('surface status reach', () {
    http.Client client(List<String> methods) =>
        mockHttpClient(withDefaultSurfaceReach: false, (request) {
          final method =
              (jsonDecode(request.body) as Map<String, dynamic>)['method']!
                  as String;
          methods.add(method);
          if (method == 'readSurfaceReach') {
            return http.Response(jsonEncode(_reachWire()), 200);
          }
          return http.Response(
            jsonEncode({
              '__className__': 'SurfaceStatusView',
              'surfaceType': 'survey',
              'surfaceSlug': 'nps',
              'environmentSlug': 'production',
              'liveVersion': 5,
              'locked': false,
              'deliveryShape': 'blob',
              'draftOrigin': 'code',
              'versions': <Object>[],
            }),
            200,
          );
        });

    Future<(int, String)> run(
      http.Client http,
      List<String> args, {
      Future<void> Function(Duration)? sleep,
    }) async {
      final out = StringBuffer();
      final runner = CommandRunner<int>('restage', '')
        ..addCommand(
          SurfaceStatusCommand(
            stdout: out,
            stderr: StringBuffer(),
            interactive: const NonInteractive(),
            credentialStore: fakeStore,
            httpClient: http,
            sleep: sleep,
          ),
        );
      final code = await runner.run([
        'status',
        'nps',
        '--type',
        'survey',
        '-C',
        tempDir.path,
        '--project',
        'p',
        '--app',
        'a',
        '--env',
        'production',
        ...args,
      ]);
      return (code!, out.toString());
    }

    test('status states how far the live version reached devices', () async {
      final methods = <String>[];
      final (code, out) = await run(client(methods), const []);
      expect(code, 0);
      expect(methods.where((m) => m == 'readSurfaceReach'), hasLength(1));
      expect(
        out,
        contains(
          'reach: v5 reached 1,240 of 1,610 active devices (77%) · 2 h after publish',
        ),
      );
      expect(out, contains('  Views since publish: 81% v5'));
      expect(out, contains("Can't render v5 · ios build 41 · 70 devices"));
      expect(out, contains('Sent v4 by rule holiday · 120 devices'));
      expect(
        out,
        contains('Not opened since v5 went live · on v4 · 150 devices'),
      );
      expect(out, contains('Not fetched yet · 30 devices'));
      expect(out, contains('1 smaller group hidden for privacy'));
    });

    test('--watch reads again on its interval and stops at its span', () async {
      final methods = <String>[];
      final waits = <Duration>[];
      final (code, _) = await run(client(methods), const [
        '--watch',
      ], sleep: (d) async => waits.add(d));
      expect(code, 0);
      expect(
        methods.where((m) => m == 'readSurfaceReach'),
        hasLength(surfaceReachWatchPolls),
      );
      expect(waits.toSet(), {surfaceReachWatchInterval});
      expect(waits, hasLength(surfaceReachWatchPolls - 1));
    });
  });
}

String _reachWire() {
  final asOf = DateTime.utc(2026, 10, 17, 12);
  final reach = {
    'asOfMicros': asOf.microsecondsSinceEpoch,
    'disclosureFloor': 5,
    'liveVersion': 5,
    'liveSinceMicros': asOf
        .subtract(const Duration(hours: 2))
        .microsecondsSinceEpoch,
    'devices': 1610,
    'reached': 1240,
    'stragglers': [
      {
        'reason': 'cantRender',
        'version': 5,
        'devices': 70,
        'platform': 'ios',
        'appBuild': 41,
        'fallback': 'bundled',
      },
      {'reason': 'routed', 'version': 4, 'devices': 120, 'routeId': 'holiday'},
      {'reason': 'notOpened', 'version': 4, 'devices': 150},
      {'reason': 'notFetched', 'version': 5, 'devices': 30},
    ],
    'hiddenStragglerRows': 1,
    'viewsSinceLive': 1610,
    'liveViewsSinceLive': 1304,
    'liveViewShareSinceLive': 8099,
  };
  return encodeByteDataWire(utf8.encode(jsonEncode(reach)));
}
