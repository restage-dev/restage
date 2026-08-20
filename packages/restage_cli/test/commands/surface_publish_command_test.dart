import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/api/surface_publication_api.dart';
import 'package:restage_cli/src/cli.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
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

  Future<int> runArgs(
    List<String> args, {
    http.Client? client,
    List<String>? answers,
  }) {
    final scripted = List<String>.from(answers ?? const <String>[]);
    return RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
      httpClient: client,
      interactiveFactory: answers == null
          ? null
          : (_) => RealInteractive(
              readLine: () async =>
                  scripted.isEmpty ? null : scripted.removeAt(0),
              stdout: stdout,
              isInteractiveOverride: true,
            ),
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

  /// The slug each scripted publish call carried, in call order.
  List<String> publishedSlugs(List<http.Request> requests) =>
      requests.map(publishedSlugOf).toList();

  /// Seed two surfaces declared in one file plus one declared elsewhere, so
  /// a path match can be wrong by over- or under-selecting.
  Future<void> seedSharedSourceFile() async {
    final upsell = await seedGeneratedPaywall(
      tempDir,
      slug: 'upsell',
      sources: const <String>['lib/paywalls/bundle.dart'],
    );
    final crossSell = await seedGeneratedPaywall(
      tempDir,
      slug: 'cross_sell',
      sources: const <String>['lib/paywalls/bundle.dart'],
    );
    final solo = await seedGeneratedPaywall(
      tempDir,
      slug: 'solo',
      sources: const <String>['lib/paywalls/solo.dart'],
    );
    await writeGeneratedOutput(tempDir, [crossSell, solo, upsell]);
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

  test('a .dart path publishes the one surface declared in it', () async {
    await seedProject();
    await seedSharedSourceFile();
    final requests = <http.Request>[];
    final client = scriptedHttpClient([
      (request) {
        requests.add(request);
        return publishSucceeded('solo');
      },
    ]);

    final exitCode = await runArgs([
      'surface',
      'publish',
      'lib/paywalls/solo.dart',
      '-C',
      tempDir.path,
    ], client: client);

    expect(exitCode, 0);
    expect(publishedSlugs(requests), <String>['solo']);
  });

  test('an absolute path resolves the same publication', () async {
    await seedProject();
    await seedSharedSourceFile();
    final requests = <http.Request>[];
    final client = scriptedHttpClient([
      (request) {
        requests.add(request);
        return publishSucceeded('solo');
      },
    ]);

    final exitCode = await runArgs([
      'surface',
      'publish',
      p.join(tempDir.path, 'lib', 'paywalls', 'solo.dart'),
      '-C',
      tempDir.path,
    ], client: client);

    expect(exitCode, 0);
    expect(publishedSlugs(requests), <String>['solo']);
  });

  test(
    'an ambiguous path without a terminal fails with exact commands',
    () async {
      await seedProject();
      await seedSharedSourceFile();
      final client = scriptedHttpClient([]);

      final exitCode = await runArgs([
        'surface',
        'publish',
        'lib/paywalls/bundle.dart',
        '-C',
        tempDir.path,
        '--non-interactive',
      ], client: client);

      expect(exitCode, 1);
      final message = stderr.toString();
      expect(message, contains('restage surface publish cross_sell'));
      expect(message, contains('restage surface publish upsell'));
      expect(
        message,
        contains('restage surface publish lib/paywalls/bundle.dart --all'),
      );
      expect(message, isNot(contains('solo')));
    },
  );

  test('the printed commands stay runnable when a slug repeats across '
      'categories', () async {
    await seedProject();
    // The same slug in two categories: manifest identity is surface + slug,
    // so `publish welcome` alone would come back ambiguous.
    final paywall = await seedGeneratedPaywall(
      tempDir,
      slug: 'welcome',
      sources: const <String>['lib/shared/welcome.dart'],
    );
    final message = await seedGeneratedPaywall(
      tempDir,
      slug: 'welcome',
      sources: const <String>['lib/shared/welcome.dart'],
      surface: Surface.message,
    );
    await writeGeneratedOutput(tempDir, [message, paywall]);

    final exitCode = await runArgs([
      'surface',
      'publish',
      'lib/shared/welcome.dart',
      '-C',
      tempDir.path,
      '--non-interactive',
    ], client: scriptedHttpClient([]));

    expect(exitCode, 1);
    final printed = stderr.toString();
    expect(printed, contains('restage surface publish welcome --type message'));
    expect(printed, contains('restage surface publish welcome --type paywall'));
  });

  test('--all publishes every surface the file declares', () async {
    await seedProject();
    await seedSharedSourceFile();
    final requests = <http.Request>[];
    final client = scriptedHttpClient([
      for (final slug in <String>['cross_sell', 'upsell'])
        (request) {
          requests.add(request);
          return publishSucceeded(slug);
        },
    ]);

    final exitCode = await runArgs([
      'surface',
      'publish',
      'lib/paywalls/bundle.dart',
      '-C',
      tempDir.path,
      '--all',
    ], client: client);

    expect(exitCode, 0);
    expect(publishedSlugs(requests), <String>['cross_sell', 'upsell']);
    expect(stdout.toString(), contains('Published 2 surfaces to dev.'));
  });

  test('an ambiguous path prompts, and the pick selects one surface', () async {
    await seedProject();
    await seedSharedSourceFile();
    final requests = <http.Request>[];
    final client = scriptedHttpClient([
      (request) {
        requests.add(request);
        return publishSucceeded('upsell');
      },
    ]);

    final exitCode = await runArgs(
      ['surface', 'publish', 'lib/paywalls/bundle.dart', '-C', tempDir.path],
      client: client,
      answers: <String>['2'],
    );

    expect(exitCode, 0);
    expect(publishedSlugs(requests), <String>['upsell']);
    expect(stdout.toString(), contains('paywall/upsell'));
  });

  test('the prompt also offers publishing every surface in the file', () async {
    await seedProject();
    await seedSharedSourceFile();
    final requests = <http.Request>[];
    final client = scriptedHttpClient([
      for (final slug in <String>['cross_sell', 'upsell'])
        (request) {
          requests.add(request);
          return publishSucceeded(slug);
        },
    ]);

    final exitCode = await runArgs(
      ['surface', 'publish', 'lib/paywalls/bundle.dart', '-C', tempDir.path],
      client: client,
      answers: <String>['3'],
    );

    expect(exitCode, 0);
    expect(publishedSlugs(requests), <String>['cross_sell', 'upsell']);
    expect(
      stdout.toString(),
      contains('all 2 surfaces produced by lib/paywalls/bundle.dart'),
    );
  });

  test('--all reports the capability warning for every surface, not just the '
      'first', () async {
    await seedProject();
    // Distinct minClient values, so a warning emitted for the wrong surface
    // is distinguishable from one emitted for the right surface.
    final first = await seedGeneratedPaywall(
      tempDir,
      slug: 'aaa',
      minClient: 2,
      sources: const <String>['lib/paywalls/bundle.dart'],
    );
    final second = await seedGeneratedPaywall(
      tempDir,
      slug: 'bbb',
      minClient: 5,
      sources: const <String>['lib/paywalls/bundle.dart'],
    );
    await writeGeneratedOutput(tempDir, [first, second]);

    final client = scriptedHttpClient([
      for (final slug in <String>['aaa', 'bbb'])
        (request) => publishSucceeded(slug),
    ]);

    final exitCode = await runArgs([
      'surface',
      'publish',
      'lib/paywalls/bundle.dart',
      '-C',
      tempDir.path,
      '--all',
    ], client: client);

    expect(exitCode, 0);
    final warnings = stderr.toString();
    expect(warnings, contains('catalog content version 2'));
    expect(warnings, contains('catalog content version 5'));
  });

  test(
    'a transport failure mid-run reports the same partial-run summary',
    () async {
      await seedProject();
      final first = await seedGeneratedPaywall(
        tempDir,
        slug: 'aaa',
        sources: const <String>['lib/paywalls/bundle.dart'],
      );
      final second = await seedGeneratedPaywall(
        tempDir,
        slug: 'bbb',
        sources: const <String>['lib/paywalls/bundle.dart'],
      );
      await writeGeneratedOutput(tempDir, [first, second]);

      final client = scriptedHttpClient([
        (request) => publishSucceeded('aaa'),
        // A malformed body exercises the FormatException arm, which reports
        // through a different catch than the typed-API arm.
        (request) => http.Response('not json', 200),
      ]);

      final exitCode = await runArgs([
        'surface',
        'publish',
        'lib/paywalls/bundle.dart',
        '-C',
        tempDir.path,
        '--all',
      ], client: client);

      expect(exitCode, isNot(0));
      expect(stderr.toString(), contains('Published 1 of 2; failed on bbb.'));
    },
  );

  test('--all is refused for an id, which already names one surface', () async {
    await seedProject();
    await seedSharedSourceFile();
    final client = scriptedHttpClient([]);

    final exitCode = await runArgs([
      'surface',
      'publish',
      'solo',
      '-C',
      tempDir.path,
      '--all',
    ], client: client);

    expect(exitCode, 1);
    expect(stderr.toString(), contains('is a surface id'));
  });

  test(
    'a failure mid-run reports what published and what was not attempted',
    () async {
      await seedProject();
      final first = await seedGeneratedPaywall(
        tempDir,
        slug: 'aaa',
        sources: const <String>['lib/paywalls/bundle.dart'],
      );
      final second = await seedGeneratedPaywall(
        tempDir,
        slug: 'bbb',
        sources: const <String>['lib/paywalls/bundle.dart'],
      );
      final third = await seedGeneratedPaywall(
        tempDir,
        slug: 'ccc',
        sources: const <String>['lib/paywalls/bundle.dart'],
      );
      await writeGeneratedOutput(tempDir, [first, second, third]);

      var calls = 0;
      final client = scriptedHttpClient([
        (request) {
          calls++;
          return publishSucceeded('aaa');
        },
        (request) {
          calls++;
          return http.Response('{"error":"boom"}', 500);
        },
      ]);

      final exitCode = await runArgs([
        'surface',
        'publish',
        'lib/paywalls/bundle.dart',
        '-C',
        tempDir.path,
        '--all',
      ], client: client);

      expect(exitCode, isNot(0));
      expect(calls, 2);
      expect(
        stderr.toString(),
        contains('Published 1 of 3; failed on bbb; not attempted: ccc.'),
      );
    },
  );
}
