import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/api/selector_syntax.dart';
import 'package:restage_cli/src/api/typed_error_models.dart';
import 'package:restage_cli/src/api/typed_error_renderer.dart';
import 'package:restage_cli/src/cli.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:test/test.dart';

import '../_helpers/test_fixtures.dart';

void main() {
  late Directory tempDir;
  late FileCredentialStore store;
  late StringBuffer out;
  late StringBuffer err;
  late List<Map<String, dynamic>> calls;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('surface_draft_cmd_');
    store = FileCredentialStore(p.join(tempDir.path, 'credentials'));
    await seedCredential(store);
    out = StringBuffer();
    err = StringBuffer();
    calls = [];
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Future<int> run(
    List<String> args,
    http.Response Function(Map<String, dynamic> body) respond, {
    bool withEnvironment = true,
  }) =>
      RestageCli(
        stdout: out,
        stderr: err,
        credentialStore: store,
        httpClient: mockHttpClient((request) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          calls.add(body);
          return respond(body);
        }),
      ).run([
        ...args,
        '--project',
        'alpha',
        '--app',
        'mobile',
        if (withEnvironment) ...['--env', 'staging'],
        '-C',
        tempDir.path,
      ]);

  test('draft push stores a new revision and says how to publish it', () async {
    final code = await run(
      ['surface', 'draft', 'push', 'welcome', '--type', 'onboarding'],
      (body) => body['method'] == 'coverage'
          ? http.Response('null', 500)
          : http.Response('4', 200),
    );

    expect(code, 0, reason: err.toString());
    final push = calls.singleWhere((call) => call['method'] == 'publish');
    expect(push['surfaceType'], 'onboarding');
    expect(push['environmentTargetId'], 12);
    expect(
      out.toString(),
      contains(
        'Pushed the draft of "welcome" to staging as r4. Not live yet. Run '
        '`restage surface publish welcome --type onboarding --revision 4` to '
        'publish it.',
      ),
    );
  });

  test('draft push lists unhandled events and names the flag', () async {
    final code = await run(
      ['surface', 'draft', 'push', 'welcome', '--type', 'onboarding'],
      (body) => typedErrorResponse('SurfaceContractFamilyViolation', {
        'code': 'unhandledEvents',
        'message': 'The flow does not handle the event "next".',
        'unhandledEvents': [
          {
            'flow': 'welcome',
            'state': 'intro',
            'screen': 'hello',
            'event': 'next',
          },
        ],
      }),
    );

    expect(code, 1);
    expect(
      err.toString(),
      contains(
        'The flow does not handle the event "next".\n'
        '  Flow "welcome", state "intro", screen "hello", event "next"\n'
        'Run again with --accept-unhandled-events to push it anyway.',
      ),
    );
  });

  test('draft push accepts unhandled events when asked', () async {
    final code = await run(
      [
        'surface',
        'draft',
        'push',
        'welcome',
        '--type',
        'onboarding',
        '--accept-unhandled-events',
      ],
      (body) => body['method'] == 'coverage'
          ? http.Response('null', 500)
          : http.Response('4', 200),
    );

    expect(code, 0, reason: err.toString());
    final push = calls.singleWhere((call) => call['method'] == 'publish');
    expect(push['acceptUnhandledEvents'], isTrue);
  });

  test(
    'draft push says when the user\'s own build covers the surface',
    () async {
      final code = await run(
        ['surface', 'draft', 'push', 'welcome', '--type', 'onboarding'],
        (body) => switch (body['method']) {
          'coverage' => http.Response(
            jsonEncode({
              'requiredLibraries': [
                {'namespace': 'acme.widgets', 'minVersion': 1},
              ],
              'headVersion': null,
              'registeredLibraries': <Object?>[],
            }),
            200,
          ),
          'whoami' => http.Response(jsonEncode({'id': 9}), 200),
          'listHeads' => http.Response(
            jsonEncode({
              'appId': 5,
              'environmentHeads': <Object?>[],
              'personalHeads': [
                {
                  'head': 'user/ada',
                  'ownerDisplayName': 'Ada',
                  'ownerUserInfoId': 9,
                  'updatedAt': DateTime.utc(2030).toIso8601String(),
                  'version': {
                    'renderBundleId': 41,
                    'appId': 5,
                    'version': 1,
                    'contentHash': 'sha256:${'0' * 64}',
                    'engineSetId': '1' * 64,
                    'capabilityManifestJson': jsonEncode({
                      'formatVersion': 1,
                      'catalog': {
                        'libraries': {
                          'acme.widgets': {'capabilityVersion': 1},
                        },
                        'widgets': <Object?>[],
                      },
                    }),
                    'byteLength': 1024,
                    'sourceDirty': false,
                    'uploadedAt': DateTime.utc(2030).toIso8601String(),
                  },
                },
              ],
            }),
            200,
          ),
          _ => http.Response('4', 200),
        },
      );

      expect(code, 0, reason: err.toString());
      expect(
        out.toString(),
        contains(
          'This surface uses widgets from your app (acme.widgets). The '
          'dashboard has no build of mobile for staging yet. Your own build '
          'covers them, so they show in your dashboard preview; `restage build '
          'push --env staging` updates what everyone sees.',
        ),
      );
    },
  );

  test('draft pull writes the draft bytes to --out', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final file = p.join(tempDir.path, 'welcome.draft');
    final code = await run(
      [
        'surface',
        'draft',
        'pull',
        'welcome',
        '--type',
        'onboarding',
        '--out',
        file,
      ],
      (_) => http.Response(
        jsonEncode("decode('${base64Encode(bytes)}', 'base64')"),
        200,
      ),
      withEnvironment: false,
    );

    expect(code, 0, reason: err.toString());
    expect(calls.last['method'], 'load');
    expect(File(file).readAsBytesSync(), bytes);
  });

  test('surface audit prints the surface timeline', () async {
    final code = await run([
      'surface',
      'audit',
      'welcome',
      '--type',
      'onboarding',
    ], (_) => http.Response('[]', 200));

    expect(code, 0, reason: err.toString());
    expect(calls.last['method'], 'listSurfaceHistory');
    expect(out.toString(), startsWith('WHEN\tACTION'));
  });

  http.Response listedAsMessage(Map<String, dynamic> body, http.Response or) {
    if (body['method'] != 'list') return or;
    return http.Response(
      jsonEncode([
        if (body['surfaceType'] == 'message')
          {
            '__className__': 'SurfaceSummary',
            'surfaceType': 'message',
            'slug': 'welcome',
            'name': 'Welcome',
            'draftUpdatedAt': '2026-05-01T12:34:56.000Z',
            'publishedVersionByEnvironment': <String, int?>{},
          },
      ]),
      200,
    );
  }

  test('surface audit without --type looks the type up by id', () async {
    final code = await run([
      'surface',
      'audit',
      'welcome',
    ], (body) => listedAsMessage(body, http.Response('[]', 200)));

    expect(code, 0, reason: err.toString());
    expect(calls.last['method'], 'listSurfaceHistory');
    expect(calls.last['surfaceType'], 'message');
  });

  test('draft pull without --type looks the type up by id', () async {
    final code = await run(
      ['surface', 'draft', 'pull', 'welcome'],
      (body) => listedAsMessage(
        body,
        http.Response(jsonEncode("decode('AQID', 'base64')"), 200),
      ),
      withEnvironment: false,
    );

    expect(code, 0, reason: err.toString());
    expect(calls.last['method'], 'load');
    expect(calls.last['surfaceType'], 'message');
  });

  test('a missing surface reads with the shared sentence', () async {
    final code = await run(
      ['surface', 'audit', 'welcome', '--type', 'onboarding'],
      (_) => http.Response(
        jsonEncode({
          'className': 'SurfaceNotFoundException',
          'data': {
            '__className__': 'SurfaceNotFoundException',
            'surfaceSlug': 'welcome',
          },
        }),
        400,
      ),
    );

    expect(code, 1);
    expect(err.toString(), "Surface 'welcome' not found.\n");
  });

  group('shared target selection', () {
    String refusal(
      TargetSelectionRefusal reason, {
      required SelectorSyntax syntax,
      List<String> organizationSlugs = const [],
    }) => targetSelectionSentence(
      TargetSelectionRefused(
        reason: reason,
        environmentSlug: 'production',
        organizationSlugs: organizationSlugs,
      ),
      syntax,
    );

    test('names the plane argument each caller has', () {
      expect(
        refusal(
          TargetSelectionRefusal.environmentOnBothPlanes,
          syntax: SelectorSyntax.cli,
        ),
        "Environment 'production' exists on both runtime planes. Pass "
        '--plane <sandbox|live>, or set `plane` in restage_config.yaml.',
      );
      expect(
        refusal(
          TargetSelectionRefusal.environmentOnBothPlanes,
          syntax: SelectorSyntax.mcp,
        ),
        "Environment 'production' exists on both runtime planes. Pass "
        'runtimePlane: sandbox or live.',
      );
    });

    test('names the organization argument each caller has', () {
      expect(
        refusal(
          TargetSelectionRefusal.multipleOrganizations,
          syntax: SelectorSyntax.cli,
          organizationSlugs: ['acme', 'restage'],
        ),
        'This project is in more than one of your organizations (acme, '
        'restage). Pass --organization <slug>.',
      );
      expect(
        refusal(
          TargetSelectionRefusal.multipleOrganizations,
          syntax: SelectorSyntax.mcp,
        ),
        'This project is in more than one of your organizations. Pass '
        'organizationId.',
      );
    });

    test('a miss says which environment', () {
      expect(
        refusal(
          TargetSelectionRefusal.environmentNotFound,
          syntax: SelectorSyntax.cli,
        ),
        "Environment 'production' not found.",
      );
      expect(
        refusal(
          TargetSelectionRefusal.noTargetOnPlane,
          syntax: SelectorSyntax.cli,
        ),
        "No target found for environment 'production' on that runtime plane.",
      );
    });
  });

  test('a stale credential names how each caller signs in again', () {
    expect(
      staleCredentialSentence(SelectorSyntax.cli),
      endsWith('Run `restage login` to refresh it.'),
    );
    expect(
      staleCredentialSentence(SelectorSyntax.mcp),
      endsWith('Sign in again with restage_login.'),
    );
  });
}
