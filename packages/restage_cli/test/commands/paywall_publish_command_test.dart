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
    tempDir = await Directory.systemTemp.createTemp('paywall_pub_manifest_');
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
    'publishes a generated paywall with one strict upload operation',
    () async {
      await seedProject();
      final entry = await seedGeneratedPaywall(tempDir, slug: 'premium');
      var operationCalls = 0;
      final client = scriptedHttpClient([
        (request) {
          operationCalls++;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['method'], surfacePublicationUploadMethod);
          final wireUpload = body['upload'] as Map<String, dynamic>;
          expect(wireUpload['__className__'], 'SurfacePublicationUpload');
          final upload = SurfacePublicationUploadRequestV1Codec.decodeJson(
            wireUpload['canonicalJson'] as String,
          );
          expect(upload.publication.sourceKind, SurfaceSourceKind.paywall);
          expect(upload.publication.surface, Surface.paywall);
          expect(upload.publication.slug, entry.publication.slug);
          return http.Response(
            jsonEncode({
              'family': {
                '__className__': 'SurfaceContractFamilyReference',
                'surfaceType': entry.publication.surface.wireName,
                'surfaceSlug': entry.publication.slug,
                'sourceKind': entry.publication.sourceKind.wireName,
              },
              'storedPublishedRevision': 4,
              'activePublishedRevision': 4,
              'identityFrozen': false,
            }),
            200,
          );
        },
      ]);

      final exitCode = await runArgs([
        'paywall',
        'publish',
        'premium',
        '-C',
        tempDir.path,
      ], client: client);

      expect(exitCode, 0);
      expect(operationCalls, 1);
      expect(
        stdout.toString(),
        contains(
          'stored revision 4; active revision 4; identity frozen: false.',
        ),
      );
      expect(stderr.toString(), contains('catalog content version 2'));
    },
  );

  test(
    'paywall publication reports a frozen stored revision with no active pointer',
    () async {
      await seedProject();
      final entry = await seedGeneratedPaywall(tempDir, slug: 'frozen_offer');
      final client = scriptedHttpClient([
        (request) => http.Response(
          jsonEncode({
            'family': {
              '__className__': 'SurfaceContractFamilyReference',
              'surfaceType': entry.publication.surface.wireName,
              'surfaceSlug': entry.publication.slug,
              'sourceKind': entry.publication.sourceKind.wireName,
            },
            'storedPublishedRevision': 8,
            'activePublishedRevision': null,
            'identityFrozen': true,
          }),
          200,
        ),
      ]);

      final exitCode = await runArgs([
        'paywall',
        'publish',
        entry.publication.slug,
        '-C',
        tempDir.path,
      ], client: client);

      expect(exitCode, 0);
      expect(
        stdout.toString(),
        contains(
          'stored revision 8; active revision none; identity frozen: true.',
        ),
      );
      expect(stdout.toString(), isNot(contains('as revision')));
    },
  );

  test('paywall publication has no raw --path bypass', () async {
    await seedProject();
    var networkCalls = 0;
    final client = MockClient((_) async {
      networkCalls++;
      return http.Response('unexpected', 500);
    });

    final exitCode = await runArgs([
      'paywall',
      'publish',
      'premium',
      '--path',
      'assets/paywalls/premium.rfw',
      '-C',
      tempDir.path,
    ], client: client);

    expect(exitCode, 1);
    expect(networkCalls, 0);
    expect(stderr.toString(), contains('Could not find an option named'));
  });

  test('paywall publication requires a generated manifest entry', () async {
    await seedProject();
    var networkCalls = 0;
    final client = MockClient((_) async {
      networkCalls++;
      return http.Response('unexpected', 500);
    });

    final exitCode = await runArgs([
      'paywall',
      'publish',
      'premium',
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

  test(
    'a non-paywall generated identity cannot enter the paywall command',
    () async {
      await seedProject();
      final blob = ordinaryRfwBlob();
      final sidecar = CapabilitySidecar(
        blobSha256: CapabilitySidecar.hashBlob(blob),
        manifest: CapabilityManifest(
          builtInFloor: 1,
          requiredLibraries: const [],
        ),
      );
      final payload = BlobSurfacePayload(minClient: 1, blob: blob);
      final slug = 'ordinary_screen';
      final blobPath = 'assets/restage/generated/$slug/screen.rfw';
      final sidecarPath =
          'assets/restage/generated/$slug/screen.capability.json';
      await _write(tempDir, blobPath, blob);
      final sidecarBytes = utf8.encode(jsonEncode(sidecar.toJson()));
      await _write(tempDir, sidecarPath, sidecarBytes);
      final eventContract = SurfaceScreenEventSchemaV1(events: const []);
      final eventContractHash = SurfaceScreenEventContractHashV1.hash(
        eventContract,
      );
      final entry = SurfacePublicationManifestEntryV1(
        publication: SurfacePublicationV1(
          surface: Surface.paywall,
          slug: slug,
          sourceKind: SurfaceSourceKind.screen,
          payloadKind: SurfacePayloadKind.blob,
          payloadContentHash: payload.contentHash,
          contractVersion: 1,
          capabilities: sidecar.manifest,
          eventContract: eventContract,
          eventContractHash: eventContractHash,
          contractFingerprint: SurfaceScreenContractFingerprintV1.hash(
            sourceKind: SurfaceSourceKind.screen,
            payloadKind: SurfacePayloadKind.blob,
            capabilities: sidecar.manifest,
            eventContractHash: eventContractHash,
          ),
        ),
        artifacts: [
          SurfacePublicationArtifactV1(
            contentHash: CapabilitySidecar.hashBlob(blob),
            path: blobPath,
            role: SurfacePublicationArtifactRoleV1.screenBlob,
            id: slug,
          ),
          SurfacePublicationArtifactV1(
            contentHash: CapabilitySidecar.hashBlob(sidecarBytes),
            path: sidecarPath,
            role: SurfacePublicationArtifactRoleV1.capabilitySidecar,
            id: slug,
          ),
        ],
      );
      await writeGeneratedOutput(tempDir, [entry]);

      var networkCalls = 0;
      final client = MockClient((_) async {
        networkCalls++;
        return http.Response('unexpected', 500);
      });
      final exitCode = await runArgs([
        'paywall',
        'publish',
        slug,
        '-C',
        tempDir.path,
      ], client: client);

      expect(exitCode, 1);
      expect(networkCalls, 0);
      expect(stderr.toString(), contains('not a specialized paywall source'));
    },
  );
  test('the deprecated paywall command accepts a .dart path too', () async {
    await seedProject();
    final premium = await seedGeneratedPaywall(
      tempDir,
      slug: 'premium',
      sources: const <String>['lib/paywalls/premium.dart'],
    );
    final trial = await seedGeneratedPaywall(
      tempDir,
      slug: 'trial',
      sources: const <String>['lib/paywalls/trial.dart'],
    );
    await writeGeneratedOutput(tempDir, [premium, trial]);

    final slugs = <String>[];
    final client = scriptedHttpClient([
      (request) {
        final upload =
            (jsonDecode(request.body) as Map<String, dynamic>)['upload']
                as Map<String, dynamic>;
        slugs.add(
          SurfacePublicationUploadRequestV1Codec.decodeJson(
            upload['canonicalJson'] as String,
          ).publication.slug,
        );
        return http.Response(
          jsonEncode({
            'family': {
              '__className__': 'SurfaceContractFamilyReference',
              'surfaceType': 'paywall',
              'surfaceSlug': 'trial',
              'sourceKind': 'paywall',
            },
            'storedPublishedRevision': 1,
            'activePublishedRevision': 1,
            'identityFrozen': false,
          }),
          200,
        );
      },
    ]);

    final exitCode = await runArgs([
      'paywall',
      'publish',
      'lib/paywalls/trial.dart',
      '-C',
      tempDir.path,
    ], client: client);

    expect(exitCode, 0);
    expect(slugs, <String>['trial']);
  });
  test('the paywall command publishes every paywall in a file under --all, '
      'and still refuses a non-paywall surface', () async {
    await seedProject();
    final monthly = await seedGeneratedPaywall(
      tempDir,
      slug: 'monthly',
      sources: const <String>['lib/paywalls/plans.dart'],
    );
    final annual = await seedGeneratedPaywall(
      tempDir,
      slug: 'annual',
      sources: const <String>['lib/paywalls/plans.dart'],
    );
    // Declared in the same file but not a paywall. The per-entry guard has to
    // hold across a multi-entry set, not just the single-entry one.
    final banner = await seedGeneratedPaywall(
      tempDir,
      slug: 'banner',
      sources: const <String>['lib/messages/banner.dart'],
      surface: Surface.message,
    );
    await writeGeneratedOutput(tempDir, [annual, banner, monthly]);

    final slugs = <String>[];
    http.Response record(http.Request request) {
      slugs.add(publishedSlugOf(request));
      return publishSucceeded(slugs.last);
    }

    final exitCode = await runArgs([
      'paywall',
      'publish',
      'lib/paywalls/plans.dart',
      '-C',
      tempDir.path,
      '--all',
    ], client: scriptedHttpClient([record, record]));

    expect(exitCode, 0);
    expect(slugs, <String>['annual', 'monthly']);
    expect(stdout.toString(), contains('Published 2 paywalls to dev.'));

    // A message surface never enters the paywall command, by path or by name.
    stderr.clear();
    final refused = await runArgs([
      'paywall',
      'publish',
      'lib/messages/banner.dart',
      '-C',
      tempDir.path,
      '--all',
    ], client: scriptedHttpClient([]));

    expect(refused, 1);
    expect(stderr.toString(), contains('is a paywall surface'));
  });
}

Future<void> _write(Directory root, String packagePath, List<int> bytes) async {
  final file = File(p.join(root.path, packagePath));
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes);
}
