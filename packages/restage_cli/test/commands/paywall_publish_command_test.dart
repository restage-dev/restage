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
      final bytes = <int>[1, 2, 3, 4];
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
      await altPath.writeAsBytes(<int>[9, 9, 9]);
      await seedCapabilitySidecar(altPath.path);

      final client = scriptedHttpClient([
        (req) {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          expect(body['method'], 'save');
          final wireBytes = body['bytes'] as String;
          // The raw blob [9, 9, 9] is wrapped in the canonical blob-surface
          // frame before upload; unwrap it back to assert the source bytes.
          expect(_innerBlobOf(wireBytes), <int>[9, 9, 9]);
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
      await seedRfw(tempDir, 'hello', <int>[1]);

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
      await seedRfw(tempDir, 'hello', <int>[1]);

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
      await seedRfw(tempDir, 'hello', <int>[1]);

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
      await seedRfw(tempDir, 'hello', <int>[1]);

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
      await seedRfw(tempDir, 'hello', <int>[1]);

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

    test('surfaces PaywallNotFound on the publish call', () async {
      await seedCredential(store);
      await seedRestageConfig(
        tempDir,
        'demo',
        'mobile',
        defaultEnvironment: 'dev',
      );
      await seedRfw(tempDir, 'hello', <int>[1]);

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
      await seedRfw(tempDir, 'hello', <int>[1]);

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
