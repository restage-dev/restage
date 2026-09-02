import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/commands/surface_publish_command.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../_helpers/test_fixtures.dart';

/// The control response returned by `activateSurface`.
String _activationResponse({required int revision}) => jsonEncode({
  '__className__': 'SurfaceContractFamilyOperationResult',
  'family': {
    '__className__': 'SurfaceContractFamilyReference',
    'surfaceType': 'paywall',
    'surfaceSlug': 'pro',
    'sourceKind': 'paywall',
  },
  'publishedRevision': revision,
  'activePublishedRevisionAfter': revision,
  'identityFrozenAfter': false,
});

/// A family history carrying [revisions], newest last so the command cannot
/// pass by taking the first entry.
String _historyResponse(List<int> revisions) => jsonEncode({
  '__className__': 'SurfaceContractFamilyView',
  'family': {
    '__className__': 'SurfaceContractFamilyReference',
    'surfaceType': 'paywall',
    'surfaceSlug': 'pro',
    'sourceKind': 'paywall',
  },
  'payloadKind': 'blob',
  'revisions': [
    for (final revision in revisions)
      {
        '__className__': 'SurfaceContractPublishedRevisionView',
        'publishedRevision': revision,
        'publishedAt': '2026-06-29T18:17:51.000Z',
        'contentHash': 'sha-$revision',
        'minClient': 1,
        'payloadKind': 'blob',
        'isActive': false,
      },
  ],
});

void main() {
  late Directory tempDir;
  late FileCredentialStore store;
  late StringBuffer out;
  late StringBuffer err;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('surface_publish_');
    store = FileCredentialStore(p.join(tempDir.path, 'credentials'));
    await seedCredential(store);
    out = StringBuffer();
    err = StringBuffer();
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  /// Run `publish` against [client], with the target selectors appended.
  Future<int?> runWith(http.Client client, List<String> args) =>
      (CommandRunner<int>('restage', '')..addCommand(
            SurfacePublishCommand(
              stdout: out,
              stderr: err,
              interactive: const NonInteractive(),
              fixedSurfaceType: SurfaceType.paywall,
              credentialStore: store,
              httpClient: client,
            ),
          ))
          .run([
            'publish',
            ...args,
            '--project',
            'demo',
            '--app',
            'mobile',
            '--env',
            'staging',
          ]);

  /// Run `publish` against a client that answers by wire method.
  Future<int?> runPublish(
    List<String> args, {
    required List<int> history,
    void Function(Map<String, dynamic> body)? onActivate,
  }) {
    final client = mockHttpClient((request) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      switch (body['method']) {
        case 'surfaceContractHistory':
          return http.Response(_historyResponse(history), 200);
        case 'activateSurface':
          onActivate?.call(body);
          return http.Response(
            _activationResponse(revision: body['publishedRevision'] as int),
            200,
          );
        default:
          fail('Unexpected wire method ${body['method']}.');
      }
    });
    return runWith(client, args);
  }

  test('publishes one exact non-versioned family revision', () async {
    Map<String, dynamic>? publishBody;
    final code = await runPublish(
      ['pro', '--revision', '3', '--reason', 'restore known good revision'],
      history: const <int>[],
      onActivate: (body) => publishBody = body,
    );

    expect(code, 0, reason: err.toString());
    expect(publishBody, isNotNull);
    expect(publishBody!['method'], 'activateSurface');
    expect(publishBody!['publishedRevision'], 3);
    expect(publishBody!['contractVersion'], isNull);
    expect(publishBody!['reason'], 'restore known good revision');
    expect(out.toString(), contains('Published "pro" at r3'));
    expect(err.toString(), isEmpty);
  });

  test('without --revision it publishes the latest pushed revision', () async {
    Map<String, dynamic>? publishBody;
    final code = await runPublish(
      ['pro'],
      history: const <int>[1, 5, 2],
      onActivate: (body) => publishBody = body,
    );

    expect(code, 0, reason: err.toString());
    expect(publishBody!['publishedRevision'], 5);
    expect(
      out.toString(),
      contains('Latest pushed revision for "pro" in staging: r5.'),
    );
    expect(out.toString(), contains('Published "pro" at r5'));
    expect(err.toString(), isEmpty);
  });

  test('an explicit --revision skips the history lookup', () async {
    final client = mockHttpClient((request) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['method'], isNot('surfaceContractHistory'));
      return http.Response(_activationResponse(revision: 2), 200);
    });

    final code = await runWith(client, ['pro', '--pushed-revision', '2']);

    expect(code, 0, reason: err.toString());
    expect(out.toString(), isNot(contains('Latest pushed revision')));
  });

  test('without --reason it records the default reason', () async {
    Map<String, dynamic>? publishBody;
    final code = await runPublish(
      ['pro', '--revision', '4'],
      history: const <int>[],
      onActivate: (body) => publishBody = body,
    );

    expect(code, 0, reason: err.toString());
    expect(publishBody!['reason'], 'Published from the CLI');
    expect(publishBody!['reason'], kDefaultPublishReason);
    expect(err.toString(), isEmpty);
  });

  test('a family with nothing pushed names the push command', () async {
    final code = await runPublish(['pro'], history: const <int>[]);

    expect(code, 1);
    expect(
      err.toString(),
      contains('No pushed revisions for "pro" in staging.'),
    );
    expect(err.toString(), contains('restage surface push pro'));
  });

  test('disagreeing revision flags are refused before any call', () async {
    final code = await runPublish([
      'pro',
      '--revision',
      '2',
      '--version',
      '3',
    ], history: const <int>[]);

    expect(code, 1);
    expect(err.toString(), contains('Revision flags must agree'));
  });
}
