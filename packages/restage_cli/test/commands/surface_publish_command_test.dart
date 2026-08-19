import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/api/surface_publication_api.dart';
import 'package:restage_cli/src/cli.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../_helpers/publication_fixtures.dart';
import '../_helpers/test_fixtures.dart';

void main() {
  late Directory tempDir;
  late FileCredentialStore store;
  late StringBuffer stdout;
  late StringBuffer stderr;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('surface_pub_manifest_');
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

  Future<void> seedProject() async {
    await seedCredential(store);
    await seedRestageConfig(
      tempDir,
      'demo',
      'mobile',
      defaultEnvironment: 'dev',
    );
  }

  test(
    'publishes the selected generated entry through one typed operation',
    () async {
      await seedProject();
      final entry = await seedGeneratedPaywall(tempDir);

      var operationCalls = 0;
      final client = scriptedHttpClient([
        (request) {
          operationCalls++;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['method'], surfacePublicationUploadMethod);
          expect(body.containsKey('bytes'), isFalse);
          expect(body.containsKey('surfaceSlug'), isFalse);
          final wireUpload = body['upload'] as Map<String, dynamic>;
          expect(wireUpload['__className__'], 'SurfacePublicationUpload');
          final requestJson = wireUpload['canonicalJson'] as String;
          final upload = SurfacePublicationUploadRequestV1Codec.decodeJson(
            requestJson,
          );
          expect(upload.publication.surface, entry.publication.surface);
          expect(upload.publication.slug, entry.publication.slug);
          expect(upload.publication.sourceKind, entry.publication.sourceKind);
          expect(upload.publication.payloadKind, entry.publication.payloadKind);
          expect(upload.publication.payloadKind.wireName, 'blob');
          return http.Response(
            jsonEncode({
              'family': {
                '__className__': 'SurfaceContractFamilyReference',
                'surfaceType': entry.publication.surface.wireName,
                'surfaceSlug': entry.publication.slug,
                'sourceKind': entry.publication.sourceKind.wireName,
              },
              'storedPublishedRevision': 3,
              'activePublishedRevision': 3,
              'identityFrozen': false,
            }),
            200,
          );
        },
      ]);

      final exitCode = await runArgs([
        'surface',
        'publish',
        entry.publication.slug,
        '-C',
        tempDir.path,
      ], client: client);

      expect(exitCode, 0);
      expect(operationCalls, 1);
      expect(
        stdout.toString(),
        contains(
          'stored revision 3; active revision 3; identity frozen: false.',
        ),
      );
      expect(stderr.toString(), contains('catalog content version 2'));
    },
  );

  test(
    'publication output keeps a frozen stored revision separate from an older active revision',
    () async {
      await seedProject();
      final entry = await seedGeneratedPaywall(tempDir, slug: 'frozen');
      final client = scriptedHttpClient([
        (request) => http.Response(
          jsonEncode({
            'family': {
              '__className__': 'SurfaceContractFamilyReference',
              'surfaceType': entry.publication.surface.wireName,
              'surfaceSlug': entry.publication.slug,
              'sourceKind': entry.publication.sourceKind.wireName,
            },
            'storedPublishedRevision': 9,
            'activePublishedRevision': 4,
            'identityFrozen': true,
          }),
          200,
        ),
      ]);

      final exitCode = await runArgs([
        'surface',
        'publish',
        entry.publication.slug,
        '-C',
        tempDir.path,
      ], client: client);

      expect(exitCode, 0);
      expect(
        stdout.toString(),
        contains(
          'stored revision 9; active revision 4; identity frozen: true.',
        ),
      );
      expect(stdout.toString(), isNot(contains('as revision')));
    },
  );

  test(
    'publication output reports no active revision after a frozen publish',
    () async {
      await seedProject();
      final entry = await seedGeneratedPaywall(tempDir, slug: 'killed');
      final client = scriptedHttpClient([
        (request) => http.Response(
          jsonEncode({
            'family': {
              '__className__': 'SurfaceContractFamilyReference',
              'surfaceType': entry.publication.surface.wireName,
              'surfaceSlug': entry.publication.slug,
              'sourceKind': entry.publication.sourceKind.wireName,
            },
            'storedPublishedRevision': 10,
            'activePublishedRevision': null,
            'identityFrozen': true,
          }),
          200,
        ),
      ]);

      final exitCode = await runArgs([
        'surface',
        'publish',
        entry.publication.slug,
        '-C',
        tempDir.path,
      ], client: client);

      expect(exitCode, 0);
      expect(
        stdout.toString(),
        contains(
          'stored revision 10; active revision none; identity frozen: true.',
        ),
      );
    },
  );

  test(
    '--type validates the generated identity and cannot reclassify it',
    () async {
      await seedProject();
      final entry = await seedGeneratedPaywall(tempDir);
      var networkCalls = 0;
      final client = MockClient((_) async {
        networkCalls++;
        return http.Response('unexpected', 500);
      });

      final exitCode = await runArgs([
        'surface',
        'publish',
        entry.publication.slug,
        '--type',
        'onboarding',
        '-C',
        tempDir.path,
      ], client: client);

      expect(exitCode, 1);
      expect(networkCalls, 0);
      expect(
        stderr.toString(),
        contains('generated manifest is authoritative'),
      );
    },
  );

  test('a stale declared artifact fails before network I/O', () async {
    await seedProject();
    final entry = await seedGeneratedPaywall(tempDir);
    final blobPath = entry.artifacts
        .firstWhere(
          (artifact) =>
              artifact.role == SurfacePublicationArtifactRoleV1.screenBlob,
        )
        .path;
    // Rebuild the bundle around different screen bytes so only the
    // cross-layer comparison against the index and manifest can catch it.
    await rewriteBundleEntryBytes(
      tempDir,
      bundlePath: GeneratedOutputLayout.generatedDirectory.bundlePathFor(
        fixtureLibraryPath,
      ),
      entryPath: blobPath,
      bytes: ordinaryRfwBlob().reversed.toList(),
    );
    var networkCalls = 0;
    final client = MockClient((_) async {
      networkCalls++;
      return http.Response('unexpected', 500);
    });

    final exitCode = await runArgs([
      'surface',
      'publish',
      entry.publication.slug,
      '-C',
      tempDir.path,
    ], client: client);

    expect(exitCode, 1);
    expect(networkCalls, 0);
    expect(stderr.toString(), contains('bundle entry hash mismatch'));
  });

  test('the invalid marker fails before network I/O', () async {
    await seedProject();
    File(p.join(tempDir.path, 'assets/restage/surface-publication.invalid'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('invalid generated output');

    var networkCalls = 0;
    final client = MockClient((_) async {
      networkCalls++;
      return http.Response('unexpected', 500);
    });
    final exitCode = await runArgs([
      'surface',
      'publish',
      'feedback',
      '-C',
      tempDir.path,
    ], client: client);

    expect(exitCode, 1);
    expect(networkCalls, 0);
    expect(
      stderr.toString(),
      contains('Generated publication output is invalid'),
    );
  });

  test('ordinary --path is no longer a publication option', () async {
    await seedProject();
    var networkCalls = 0;
    final client = MockClient((_) async {
      networkCalls++;
      return http.Response('unexpected', 500);
    });

    final exitCode = await runArgs([
      'surface',
      'publish',
      'feedback',
      '--path',
      'assets/other.rfw',
      '-C',
      tempDir.path,
    ], client: client);

    expect(exitCode, 1);
    expect(networkCalls, 0);
    expect(stderr.toString(), contains('Could not find an option named'));
  });

  test('missing manifest has no directory fallback', () async {
    await seedProject();
    final fallback = File(
      p.join(tempDir.path, 'assets', 'paywalls', 'feedback.rfw'),
    )..parent.createSync(recursive: true);
    await fallback.writeAsBytes(ordinaryRfwBlob());
    var networkCalls = 0;
    final client = MockClient((_) async {
      networkCalls++;
      return http.Response('unexpected', 500);
    });

    final exitCode = await runArgs([
      'surface',
      'publish',
      'feedback',
      '-C',
      tempDir.path,
    ], client: client);

    expect(exitCode, 1);
    expect(networkCalls, 0);
    expect(
      stderr.toString(),
      contains('No generated publication output index'),
    );
  });
}
