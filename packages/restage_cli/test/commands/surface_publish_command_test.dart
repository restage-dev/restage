import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/cli.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../_helpers/test_fixtures.dart';

void main() {
  late Directory tempDir;
  late FileCredentialStore store;
  late StringBuffer stdout;
  late StringBuffer stderr;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('surface_pub_');
    store = FileCredentialStore(p.join(tempDir.path, 'credentials'));
    stdout = StringBuffer();
    stderr = StringBuffer();
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Future<int> runArgs(List<String> args, {http.Client? client}) {
    return RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
      httpClient: client,
    ).run(args);
  }

  group('restage surface publish', () {
    test('missing positional slug exits 1 with a usage hint', () async {
      await seedCredential(store);
      await seedRestageConfig(
        tempDir,
        'demo',
        'mobile',
        defaultEnvironment: 'dev',
      );

      final exitCode = await runArgs([
        'surface',
        'publish',
        '--type',
        'onboarding',
        '-C',
        tempDir.path,
      ]);

      expect(exitCode, 1);
      expect(stderr.toString().toLowerCase(), contains('slug'));
    });

    test('missing --type exits 1 listing the valid values', () async {
      await seedCredential(store);
      await seedRestageConfig(
        tempDir,
        'demo',
        'mobile',
        defaultEnvironment: 'dev',
      );

      final exitCode = await runArgs([
        'surface',
        'publish',
        'first_run',
        '-C',
        tempDir.path,
      ]);

      expect(exitCode, 1);
      final err = stderr.toString();
      expect(err, contains('--type'));
      expect(err, contains('onboarding'));
      expect(err, contains('message'));
      expect(err, contains('survey'));
    });

    test('invalid --type exits 1 listing the valid values', () async {
      await seedCredential(store);
      await seedRestageConfig(
        tempDir,
        'demo',
        'mobile',
        defaultEnvironment: 'dev',
      );

      final exitCode = await runArgs([
        'surface',
        'publish',
        'first_run',
        '--type',
        'banner',
        '-C',
        tempDir.path,
      ]);

      expect(exitCode, 1);
      final err = stderr.toString();
      expect(err.toLowerCase(), contains('banner'));
      expect(err, contains('onboarding'));
    });

    test(
      'paywall happy path: reads assets/paywalls/<slug>.rfw, save + publish, '
      'stamping the derived minClient floor read from the capability sidecar',
      () async {
        await seedCredential(store);
        await seedRestageConfig(
          tempDir,
          'demo',
          'mobile',
          defaultEnvironment: 'dev',
        );
        await seedRfw(tempDir, 'pro_upgrade', List<int>.generate(48, (i) => i));

        var saveCalls = 0;
        var publishCalls = 0;
        final client = scriptedHttpClient([
          (req) {
            saveCalls++;
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            expect(body['method'], 'save');
            expect(body['surfaceType'], 'paywall');
            expect(body['surfaceSlug'], 'pro_upgrade');
            // The assembled draft must decode as a blob payload carrying the
            // derived capability floor read from the sidecar (seeded at 2).
            final wire = body['bytes'] as String;
            final b64 = wire.substring(
              "decode('".length,
              wire.length - "', 'base64')".length,
            );
            final payload = SurfacePayload.decode(base64Decode(b64));
            expect(payload, isA<BlobSurfacePayload>());
            expect((payload as BlobSurfacePayload).minClient, 2);
            return http.Response('null', 200);
          },
          (req) {
            publishCalls++;
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            expect(body['method'], 'publish');
            expect(body['surfaceType'], 'paywall');
            expect(body['surfaceSlug'], 'pro_upgrade');
            expect(body['environmentSlug'], 'dev');
            return http.Response('2', 200);
          },
        ]);

        final exitCode = await runArgs([
          'surface',
          'publish',
          'pro_upgrade',
          '--type',
          'paywall',
          '-C',
          tempDir.path,
        ], client: client);

        expect(exitCode, 0);
        expect(saveCalls, 1);
        expect(publishCalls, 1);
        final out = stdout.toString();
        expect(out, contains('Published'));
        expect(out, contains('pro_upgrade'));
        expect(out, contains('paywall'));
      },
    );

    test('--type paywall is now advertised in the valid-values list', () async {
      await seedCredential(store);
      await seedRestageConfig(
        tempDir,
        'demo',
        'mobile',
        defaultEnvironment: 'dev',
      );

      // Omit --type so the command prints the valid-values list.
      final exitCode = await runArgs([
        'surface',
        'publish',
        'first_run',
        '-C',
        tempDir.path,
      ]);

      expect(exitCode, 1);
      expect(stderr.toString().toLowerCase(), contains('paywall'));
    });

    test('paywall: missing .rfw → exit 1 with the resolved path', () async {
      await seedCredential(store);
      await seedRestageConfig(
        tempDir,
        'demo',
        'mobile',
        defaultEnvironment: 'dev',
      );

      final exitCode = await runArgs([
        'surface',
        'publish',
        'absent',
        '--type',
        'paywall',
        '-C',
        tempDir.path,
      ]);

      expect(exitCode, 1);
      expect(stderr.toString(), contains('absent.rfw'));
    });

    test('paywall: --path overrides the default .rfw location', () async {
      await seedCredential(store);
      await seedRestageConfig(
        tempDir,
        'demo',
        'mobile',
        defaultEnvironment: 'dev',
      );
      final custom = File(p.join(tempDir.path, 'custom', 'p.rfw'));
      await custom.parent.create(recursive: true);
      await custom.writeAsBytes(List<int>.generate(16, (i) => i));
      await seedCapabilitySidecar(custom.path);

      final client = scriptedHttpClient([
        (req) => http.Response('null', 200),
        (req) => http.Response('1', 200),
      ]);

      final exitCode = await runArgs([
        'surface',
        'publish',
        'pro_upgrade',
        '--type',
        'paywall',
        '--path',
        custom.path,
        '-C',
        tempDir.path,
      ], client: client);

      expect(exitCode, 0);
    });

    test(
      'happy path: save + publish → "Published <slug> (<type>) ..."',
      () async {
        await seedCredential(store);
        await seedRestageConfig(
          tempDir,
          'demo',
          'mobile',
          defaultEnvironment: 'dev',
        );
        await seedSurfaceFlow(tempDir);

        var saveCalls = 0;
        var publishCalls = 0;
        final client = scriptedHttpClient([
          (req) {
            saveCalls++;
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            expect(body['method'], 'save');
            expect(body['projectSlug'], 'demo');
            expect(body['appSlug'], 'mobile');
            expect(body['surfaceType'], 'onboarding');
            expect(body['surfaceSlug'], 'first_run');
            final wireBytes = body['bytes'] as String;
            expect(wireBytes, startsWith("decode('"));
            expect(wireBytes, endsWith("', 'base64')"));
            return http.Response('null', 200);
          },
          (req) {
            publishCalls++;
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            expect(body['method'], 'publish');
            expect(body['surfaceType'], 'onboarding');
            expect(body['surfaceSlug'], 'first_run');
            expect(body['environmentSlug'], 'dev');
            return http.Response('5', 200);
          },
        ]);

        final exitCode = await runArgs([
          'surface',
          'publish',
          'first_run',
          '--type',
          'onboarding',
          '-C',
          tempDir.path,
        ], client: client);

        expect(exitCode, 0);
        expect(saveCalls, 1);
        expect(publishCalls, 1);
        final out = stdout.toString();
        expect(out, contains('Published'));
        expect(out, contains('first_run'));
        expect(out, contains('onboarding'));
        expect(out, contains('dev'));
        expect(out, contains('5'));
      },
    );

    test('--path overrides the default resolved flow location', () async {
      await seedCredential(store);
      await seedRestageConfig(
        tempDir,
        'demo',
        'mobile',
        defaultEnvironment: 'dev',
      );
      // Seed into a nested directory; point --path directly at the flow JSON.
      final nested = Directory(p.join(tempDir.path, 'custom'));
      await nested.create(recursive: true);
      final flowPath = await seedSurfaceFlow(nested);

      final client = scriptedHttpClient([
        (req) => http.Response('null', 200),
        (req) => http.Response('1', 200),
      ]);

      final exitCode = await runArgs([
        'surface',
        'publish',
        'first_run',
        '--type',
        'onboarding',
        '--path',
        flowPath,
        '-C',
        tempDir.path,
      ], client: client);

      expect(exitCode, 0);
    });

    test(
      'missing flow JSON → exit 1 with the resolved path + build_runner',
      () async {
        await seedCredential(store);
        await seedRestageConfig(
          tempDir,
          'demo',
          'mobile',
          defaultEnvironment: 'dev',
        );

        final exitCode = await runArgs([
          'surface',
          'publish',
          'missing',
          '--type',
          'onboarding',
          '-C',
          tempDir.path,
        ]);

        expect(exitCode, 1);
        final err = stderr.toString();
        expect(err, contains('missing.flow.json'));
        expect(err, contains('build_runner'));
      },
    );

    test('missing screen blob → exit 1', () async {
      await seedCredential(store);
      await seedRestageConfig(
        tempDir,
        'demo',
        'mobile',
        defaultEnvironment: 'dev',
      );
      await seedSurfaceFlow(tempDir);
      await File(
        p.join(tempDir.path, 'assets', 'onboarding', 'screens', 'notify.rfw'),
      ).delete();

      final exitCode = await runArgs([
        'surface',
        'publish',
        'first_run',
        '--type',
        'onboarding',
        '-C',
        tempDir.path,
      ]);

      expect(exitCode, 1);
      final err = stderr.toString();
      expect(err, contains('notify.rfw'));
      expect(err, contains('build_runner'));
    });

    test('stale screen blob (hash mismatch) → exit 1', () async {
      await seedCredential(store);
      await seedRestageConfig(
        tempDir,
        'demo',
        'mobile',
        defaultEnvironment: 'dev',
      );
      await seedSurfaceFlow(tempDir);
      await File(
        p.join(tempDir.path, 'assets', 'onboarding', 'screens', 'ready.rfw'),
      ).writeAsBytes(<int>[7, 7, 7]);

      final exitCode = await runArgs([
        'surface',
        'publish',
        'first_run',
        '--type',
        'onboarding',
        '-C',
        tempDir.path,
      ]);

      expect(exitCode, 1);
      expect(stderr.toString().toLowerCase(), contains('stale'));
    });

    test('--env overrides the config default', () async {
      await seedCredential(store);
      await seedRestageConfig(
        tempDir,
        'demo',
        'mobile',
        defaultEnvironment: 'dev',
      );
      await seedSurfaceFlow(tempDir);

      late Map<String, dynamic> publishBody;
      final client = scriptedHttpClient([
        (req) => http.Response('null', 200),
        (req) {
          publishBody = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response('1', 200);
        },
      ]);

      final exitCode = await runArgs([
        'surface',
        'publish',
        'first_run',
        '--type',
        'onboarding',
        '--env',
        'staging',
        '-C',
        tempDir.path,
      ], client: client);

      expect(exitCode, 0);
      expect(publishBody['environmentSlug'], 'staging');
    });

    test(
      '--non-interactive without --env (no default) → "Required: --env"',
      () async {
        await seedCredential(store);
        await seedRestageConfig(tempDir, 'demo', 'mobile');
        await seedSurfaceFlow(tempDir);

        final exitCode = await runArgs([
          '--non-interactive',
          'surface',
          'publish',
          'first_run',
          '--type',
          'onboarding',
          '-C',
          tempDir.path,
        ]);

        expect(exitCode, 1);
        expect(stderr.toString(), contains('--env'));
      },
    );

    test('interactive prompt picks env when missing', () async {
      await seedCredential(store);
      await seedRestageConfig(tempDir, 'demo', 'mobile');
      await seedSurfaceFlow(tempDir);

      late Map<String, dynamic> publishBody;
      final client = scriptedHttpClient([
        (req) => http.Response('null', 200),
        (req) {
          publishBody = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response('1', 200);
        },
      ]);

      final exitCode =
          await RestageCli(
            stdout: stdout,
            stderr: stderr,
            credentialStore: store,
            httpClient: client,
            interactiveFactory: (ArgResults _) {
              final lines = ['staging'];
              return RealInteractive(
                readLine: () async => lines.isEmpty ? null : lines.removeAt(0),
                stdout: stdout,
                isInteractiveOverride: true,
              );
            },
          ).run([
            'surface',
            'publish',
            'first_run',
            '--type',
            'onboarding',
            '-C',
            tempDir.path,
          ]);

      expect(exitCode, 0);
      expect(publishBody['environmentSlug'], 'staging');
    });

    test('surfaces SurfacePublishConflict on the publish call', () async {
      await seedCredential(store);
      await seedRestageConfig(
        tempDir,
        'demo',
        'mobile',
        defaultEnvironment: 'dev',
      );
      await seedSurfaceFlow(tempDir);

      final client = scriptedHttpClient([
        (req) => http.Response('null', 200),
        (req) => http.Response(
          jsonEncode({
            'className': 'SurfacePublishConflictException',
            'data': {
              '__className__': 'SurfacePublishConflictException',
              'surfaceSlug': 'first_run',
              'environmentSlug': 'dev',
            },
          }),
          400,
        ),
      ]);

      final exitCode = await runArgs([
        'surface',
        'publish',
        'first_run',
        '--type',
        'onboarding',
        '-C',
        tempDir.path,
      ], client: client);

      expect(exitCode, 1);
      final err = stderr.toString().toLowerCase();
      expect(err, contains('race'));
      expect(err, contains('retry'));
    });

    test('surfaces SurfaceNotFound on the publish call', () async {
      await seedCredential(store);
      await seedRestageConfig(
        tempDir,
        'demo',
        'mobile',
        defaultEnvironment: 'dev',
      );
      await seedSurfaceFlow(tempDir);

      final client = scriptedHttpClient([
        (req) => http.Response('null', 200),
        (req) => http.Response(
          jsonEncode({
            'className': 'SurfaceNotFoundException',
            'data': {
              '__className__': 'SurfaceNotFoundException',
              'surfaceSlug': 'first_run',
            },
          }),
          400,
        ),
      ]);

      final exitCode = await runArgs([
        'surface',
        'publish',
        'first_run',
        '--type',
        'onboarding',
        '-C',
        tempDir.path,
      ], client: client);

      expect(exitCode, 1);
      expect(stderr.toString(), contains('first_run'));
      expect(stderr.toString().toLowerCase(), contains('surface'));
    });

    test(
      'save ok but publish transport-fails (500): exit 2 + draft hint',
      () async {
        await seedCredential(store);
        await seedRestageConfig(
          tempDir,
          'demo',
          'mobile',
          defaultEnvironment: 'dev',
        );
        await seedSurfaceFlow(tempDir);

        final client = scriptedHttpClient([
          (req) => http.Response('null', 200),
          (req) => http.Response('boom', 500),
        ]);

        final exitCode = await runArgs([
          'surface',
          'publish',
          'first_run',
          '--type',
          'onboarding',
          '-C',
          tempDir.path,
        ], client: client);

        expect(exitCode, 2);
        final err = stderr.toString().toLowerCase();
        expect(err, contains('draft is on the server'));
        expect(err, contains('re-uploads'));
        expect(err, contains('restage surface publish'));
      },
    );

    test('role split: member save ok, admin-only publish denied → '
        'exit 1 + role-aware draft-uploaded message', () async {
      await seedCredential(store);
      await seedRestageConfig(
        tempDir,
        'demo',
        'mobile',
        defaultEnvironment: 'dev',
      );
      await seedSurfaceFlow(tempDir);

      // The backend throws UnauthorizedException when the member role does
      // not satisfy the admin requirement on publish (save already succeeded).
      final client = scriptedHttpClient([
        (req) => http.Response('null', 200),
        (req) => http.Response(
          jsonEncode({
            'className': 'UnauthorizedException',
            'data': {
              '__className__': 'UnauthorizedException',
              'resource': 'demo',
            },
          }),
          400,
        ),
      ]);

      final exitCode = await runArgs([
        'surface',
        'publish',
        'first_run',
        '--type',
        'onboarding',
        '-C',
        tempDir.path,
      ], client: client);

      expect(exitCode, 1);
      final err = stderr.toString().toLowerCase();
      expect(err, contains('draft uploaded'));
      expect(err, contains('admin'));
      expect(err, contains('restage surface publish'));
    });

    test('not signed in → exit 1 with login hint', () async {
      await seedRestageConfig(
        tempDir,
        'demo',
        'mobile',
        defaultEnvironment: 'dev',
      );
      await seedSurfaceFlow(tempDir);

      final exitCode = await runArgs([
        'surface',
        'publish',
        'first_run',
        '--type',
        'onboarding',
        '-C',
        tempDir.path,
      ]);

      expect(exitCode, 1);
      expect(stderr.toString(), contains('restage login'));
    });
  });
}
