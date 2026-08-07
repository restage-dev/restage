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

/// Decode the backend `decode('<base64>', 'base64')` wire form, then unwrap
/// the canonical [BlobSurfacePayload] frame to its inner blob. Paywalls publish
/// through the surface store, so the wire `bytes` are the wrapped frame.
List<int> _innerBlobOf(String wire) {
  final base64Slice = wire.substring(8, wire.length - 12);
  final payload = SurfacePayload.decode(base64Decode(base64Slice));
  return (payload as BlobSurfacePayload).blob;
}

void main() {
  late Directory tempDir;
  late FileCredentialStore store;
  late StringBuffer stdout;
  late StringBuffer stderr;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('paywall_pub_');
    store = FileCredentialStore(p.join(tempDir.path, 'credentials'));
    stdout = StringBuffer();
    stderr = StringBuffer();
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<void> seedCatalog(String catalogJson) async {
    final file = File(
      p.join(tempDir.path, 'lib', 'src', 'widget_catalog', 'catalog.json'),
    );
    await file.parent.create(recursive: true);
    await file.writeAsString(catalogJson);
  }

  group('restage paywall publish', () {
    test('missing positional name exits 1 with a usage hint', () async {
      await seedCredential(store);
      await seedRestageConfig(
        tempDir,
        'demo',
        'mobile',
        defaultEnvironment: 'dev',
      );

      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
      ).run(['paywall', 'publish', '-C', tempDir.path]);

      expect(exitCode, 1);
      expect(stderr.toString().toLowerCase(), contains('name'));
    });

    test('happy path: save + publish → "Published ... as version N"', () async {
      await seedCredential(store);
      await seedRestageConfig(
        tempDir,
        'demo',
        'mobile',
        defaultEnvironment: 'dev',
      );
      final bytes = ordinaryRfwBlob();
      await seedRfw(tempDir, 'hello', bytes);

      var saveCalls = 0;
      var publishCalls = 0;
      final client = scriptedHttpClient([
        (req) {
          saveCalls++;
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          expect(body['method'], 'save');
          expect(body['surfaceType'], 'paywall');
          expect(body['projectSlug'], 'demo');
          expect(body['appSlug'], 'mobile');
          expect(body['appId'], 5);
          expect(body['surfaceSlug'], 'hello');
          // The wire format for bytes is the backend `decode('<base64>',
          // 'base64')` string, wrapping the canonical blob-surface frame.
          final wireBytes = body['bytes'] as String;
          expect(wireBytes, startsWith("decode('"));
          expect(wireBytes, endsWith("', 'base64')"));
          expect(_innerBlobOf(wireBytes), bytes);
          return http.Response('null', 200);
        },
        (req) {
          publishCalls++;
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          expect(body['method'], 'publish');
          expect(body['environmentSlug'], 'dev');
          return http.Response('5', 200);
        },
      ]);

      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: client,
      ).run(['paywall', 'publish', 'hello', '-C', tempDir.path]);

      expect(exitCode, 0);
      expect(saveCalls, 1);
      expect(publishCalls, 1);
      final out = stdout.toString();
      expect(out, contains('Published'));
      expect(out, contains('hello'));
      expect(out, contains('dev'));
      expect(out, contains('5'));
    });

    test('flow paywall: uploads a FlowSurfacePayload frame — byte-transparent, '
        'never re-wrapped inside a blob', () async {
      await seedCredential(store);
      await seedRestageConfig(
        tempDir,
        'demo',
        'mobile',
        defaultEnvironment: 'dev',
      );
      await seedPaywallFlow(tempDir, slug: 'fluent_pro');

      var saveCalls = 0;
      var publishCalls = 0;
      final client = scriptedHttpClient([
        (req) {
          saveCalls++;
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          expect(body['method'], 'save');
          expect(body['surfaceSlug'], 'fluent_pro');
          final wire = body['bytes'] as String;
          final payload = SurfacePayload.decode(
            base64Decode(wire.substring(8, wire.length - 12)),
          );
          // HQ-2 guardrail: the convenience command uploads the flow's
          // canonical frame; it must NOT re-wrap the flow bytes inside a
          // BlobSurfacePayload (which would re-create the dead-nav trap at the
          // save layer).
          expect(payload, isA<FlowSurfacePayload>());
          return http.Response('null', 200);
        },
        (req) {
          publishCalls++;
          return http.Response('3', 200);
        },
      ]);

      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: client,
      ).run(['paywall', 'publish', 'fluent_pro', '-C', tempDir.path]);

      expect(exitCode, 0);
      expect(saveCalls, 1);
      expect(publishCalls, 1);
    });

    test('--path overrides the default resolved location', () async {
      await seedCredential(store);
      await seedRestageConfig(
        tempDir,
        'demo',
        'mobile',
        defaultEnvironment: 'dev',
      );
      final altPath = File(p.join(tempDir.path, 'custom', 'hello.rfw'));
      await altPath.parent.create(recursive: true);
      final bytes = ordinaryRfwBlob();
      await altPath.writeAsBytes(bytes);
      await seedCapabilitySidecar(altPath.path);

      final client = scriptedHttpClient([
        (req) {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          expect(body['method'], 'save');
          final wireBytes = body['bytes'] as String;
          // The raw blob is wrapped in the canonical blob-surface frame before
          // upload; unwrap it back to assert the source bytes.
          expect(_innerBlobOf(wireBytes), bytes);
          return http.Response('null', 200);
        },
        (req) => http.Response('1', 200),
      ]);

      final exitCode =
          await RestageCli(
            stdout: stdout,
            stderr: stderr,
            credentialStore: store,
            httpClient: client,
          ).run([
            'paywall',
            'publish',
            'hello',
            '--path',
            altPath.path,
            '-C',
            tempDir.path,
          ]);

      expect(exitCode, 0);
    });

    test('resolves configured organization before save and publish', () async {
      await seedCredential(store);
      await seedRestageConfig(
        tempDir,
        'demo',
        'mobile',
        defaultEnvironment: 'dev',
        organization: 'restage',
      );
      await seedRfw(tempDir, 'hello', ordinaryRfwBlob());

      Map<String, dynamic>? saveBody;
      Map<String, dynamic>? publishBody;
      final client = scriptedHttpClient([
        (req) {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          expect(body['method'], 'listMine');
          return http.Response(
            jsonEncode([
              {
                'organizationId': 7,
                'slug': 'restage',
                'name': 'Restage',
                'role': 'owner',
              },
            ]),
            200,
          );
        },
        (req) => activeAppDiscoveryResponse(
          req,
          appSlug: 'mobile',
          projectSlug: 'demo',
        ),
        (req) {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          expect(body['method'], 'listEnvironmentTargets');
          expect(body['organizationId'], 7);
          return http.Response(
            jsonEncode([
              {
                'environmentTargetId': 11,
                'namedEnvironmentId': 21,
                'environmentSlug': 'dev',
                'runtimePlane': 'sandbox',
              },
            ]),
            200,
          );
        },
        (req) {
          saveBody = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response('null', 200);
        },
        (req) {
          publishBody = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response('5', 200);
        },
      ], withDefaultTargetDiscovery: false);

      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: client,
      ).run(['paywall', 'publish', 'hello', '-C', tempDir.path]);

      expect(exitCode, 0);
      expect(saveBody, isNotNull);
      expect(saveBody!['method'], 'save');
      expect(saveBody!['organizationId'], 7);
      expect(saveBody!['appId'], 5);
      expect(publishBody, isNotNull);
      expect(publishBody!['method'], 'publish');
      expect(publishBody!['organizationId'], 7);
    });

    test('missing .rfw file → exit 1 with the resolved path', () async {
      await seedCredential(store);
      await seedRestageConfig(
        tempDir,
        'demo',
        'mobile',
        defaultEnvironment: 'dev',
      );

      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
      ).run(['paywall', 'publish', 'missing', '-C', tempDir.path]);

      expect(exitCode, 1);
      expect(stderr.toString(), contains('missing.rfw'));
    });

    test('--env overrides the config default', () async {
      await seedCredential(store);
      await seedRestageConfig(
        tempDir,
        'demo',
        'mobile',
        defaultEnvironment: 'dev',
      );
      await seedRfw(tempDir, 'hello', ordinaryRfwBlob(), minClient: 1);

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
          ).run([
            'paywall',
            'publish',
            'hello',
            '--env',
            'staging',
            '-C',
            tempDir.path,
          ]);

      expect(exitCode, 0);
      expect(publishBody['environmentSlug'], 'staging');
    });

    test('--non-interactive without --env (and no defaultEnvironment) '
        'exits 1 with "Required: --env"', () async {
      await seedCredential(store);
      await seedRestageConfig(
        tempDir,
        'demo',
        'mobile',
      ); // no defaultEnvironment
      await seedRfw(tempDir, 'hello', ordinaryRfwBlob(), minClient: 1);

      final exitCode =
          await RestageCli(
            stdout: stdout,
            stderr: stderr,
            credentialStore: store,
          ).run([
            '--non-interactive',
            'paywall',
            'publish',
            'hello',
            '-C',
            tempDir.path,
          ]);

      expect(exitCode, 1);
      expect(stderr.toString(), contains('--env'));
    });

    test('interactive prompt picks env when missing', () async {
      await seedCredential(store);
      // No defaultEnvironment so the command must prompt.
      await seedRestageConfig(tempDir, 'demo', 'mobile');
      await seedRfw(tempDir, 'hello', ordinaryRfwBlob());

      late Map<String, dynamic> publishBody;
      final client = scriptedHttpClient([
        (req) => http.Response('null', 200),
        (req) {
          publishBody = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response('1', 200);
        },
      ]);

      // The interactive factory below feeds a scripted line: `staging`.
      final exitCode = await RestageCli(
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
      ).run(['paywall', 'publish', 'hello', '-C', tempDir.path]);

      expect(exitCode, 0);
      expect(publishBody['environmentSlug'], 'staging');
    });

    test('surfaces PublishConflict on publish call', () async {
      await seedCredential(store);
      await seedRestageConfig(
        tempDir,
        'demo',
        'mobile',
        defaultEnvironment: 'dev',
      );
      await seedRfw(tempDir, 'hello', ordinaryRfwBlob());

      final client = scriptedHttpClient([
        (req) => http.Response('null', 200),
        (req) => http.Response(
          jsonEncode({
            'className': 'SurfacePublishConflictException',
            'data': {
              '__className__': 'SurfacePublishConflictException',
              'surfaceSlug': 'hello',
              'environmentSlug': 'dev',
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
      ).run(['paywall', 'publish', 'hello', '-C', tempDir.path]);

      expect(exitCode, 1);
      final err = stderr.toString().toLowerCase();
      expect(err, contains('race'));
      expect(err, contains('retry'));
    });

    test('save succeeds but publish fails (transport): exit 2 + '
        'draft-uploaded hint', () async {
      await seedCredential(store);
      await seedRestageConfig(
        tempDir,
        'demo',
        'mobile',
        defaultEnvironment: 'dev',
      );
      await seedRfw(tempDir, 'hello', ordinaryRfwBlob());

      final client = scriptedHttpClient([
        (req) => http.Response('null', 200),
        (req) => http.Response('boom', 500),
      ]);

      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: client,
      ).run(['paywall', 'publish', 'hello', '-C', tempDir.path]);

      expect(exitCode, 2);
      final err = stderr.toString().toLowerCase();
      // Hint clarifies the draft is on the server AND that the retry
      // re-runs the full upload+publish (it's not a publish-only path).
      expect(err, contains('draft is on the server'));
      expect(err, contains('re-uploads'));
      expect(err, contains('restage paywall publish'));
    });

    test(
      'uploads the widget catalog after a successful publish when present',
      () async {
        await seedCredential(store);
        await seedRestageConfig(
          tempDir,
          'demo',
          'mobile',
          defaultEnvironment: 'dev',
        );
        await seedRfw(tempDir, 'hello', ordinaryRfwBlob(), minClient: 1);
        const catalogJson = '{"schemaVersion":1,"widgets":[]}';
        await seedCatalog(catalogJson);

        var catalogCalls = 0;
        final client = scriptedHttpClient([
          (req) => http.Response('null', 200),
          (req) => http.Response('2', 200),
          (req) {
            catalogCalls++;
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            expect(body['method'], 'push');
            expect(body['projectSlug'], 'demo');
            expect(body['appSlug'], 'mobile');
            expect(body['catalogJson'], catalogJson);
            return http.Response('8', 200);
          },
        ]);

        final exitCode = await RestageCli(
          stdout: stdout,
          stderr: stderr,
          credentialStore: store,
          httpClient: client,
        ).run(['paywall', 'publish', 'hello', '-C', tempDir.path]);

        expect(exitCode, 0);
        expect(catalogCalls, 1);
        expect(stdout.toString(), contains('Published hello'));
        expect(stderr.toString(), isEmpty);
      },
    );

    test('skips the widget catalog silently when it is absent', () async {
      await seedCredential(store);
      await seedRestageConfig(
        tempDir,
        'demo',
        'mobile',
        defaultEnvironment: 'dev',
      );
      await seedRfw(tempDir, 'hello', ordinaryRfwBlob(), minClient: 1);

      final client = scriptedHttpClient([
        (req) => http.Response('null', 200),
        (req) => http.Response('2', 200),
      ]);

      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: client,
      ).run(['paywall', 'publish', 'hello', '-C', tempDir.path]);

      expect(exitCode, 0);
      expect(stdout.toString(), contains('Published hello'));
      expect(stderr.toString(), isEmpty);
    });

    test('catalog push failure warns but does not fail the publish', () async {
      await seedCredential(store);
      await seedRestageConfig(
        tempDir,
        'demo',
        'mobile',
        defaultEnvironment: 'dev',
      );
      await seedRfw(tempDir, 'hello', ordinaryRfwBlob());
      await seedCatalog('{"schemaVersion":1,"widgets":[]}');

      var catalogCalls = 0;
      final client = scriptedHttpClient([
        (req) => http.Response('null', 200),
        (req) => http.Response('2', 200),
        (req) {
          catalogCalls++;
          return http.Response('temporary error', 500);
        },
      ]);

      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: client,
      ).run(['paywall', 'publish', 'hello', '-C', tempDir.path]);

      expect(exitCode, 0);
      expect(catalogCalls, 1);
      expect(stdout.toString(), contains('Published hello'));
      expect(stderr.toString().toLowerCase(), contains('warning'));
      expect(stderr.toString().toLowerCase(), contains('widget catalog'));
    });

    test('surfaces PaywallNotFound on the publish call', () async {
      await seedCredential(store);
      await seedRestageConfig(
        tempDir,
        'demo',
        'mobile',
        defaultEnvironment: 'dev',
      );
      await seedRfw(tempDir, 'hello', ordinaryRfwBlob());

      // Save returns null (success); publish reports the surface not found.
      // (Useful as a sanity check — the canonical not-found exit happens when
      // the row is deleted between save and publish.)
      final client = scriptedHttpClient([
        (req) => http.Response('null', 200),
        (req) => http.Response(
          jsonEncode({
            'className': 'SurfaceNotFoundException',
            'data': {
              '__className__': 'SurfaceNotFoundException',
              'surfaceSlug': 'hello',
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
      ).run(['paywall', 'publish', 'hello', '-C', tempDir.path]);

      expect(exitCode, 1);
      expect(stderr.toString(), contains('hello'));
      expect(stderr.toString().toLowerCase(), contains('paywall'));
    });

    test('not signed in → exit 1 with login hint', () async {
      await seedRestageConfig(
        tempDir,
        'demo',
        'mobile',
        defaultEnvironment: 'dev',
      );
      await seedRfw(tempDir, 'hello', ordinaryRfwBlob());

      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
      ).run(['paywall', 'publish', 'hello', '-C', tempDir.path]);

      expect(exitCode, 1);
      expect(stderr.toString(), contains('restage login'));
    });
  });
}
