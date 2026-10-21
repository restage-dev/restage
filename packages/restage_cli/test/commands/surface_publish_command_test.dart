import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/commands/surface_publish_command.dart';
import 'package:restage_cli/src/commands/surface_publish_operation.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../_helpers/test_fixtures.dart';

/// The control response returned by `activateSurface`.
String _activationResponse({required int revision, int? before}) => jsonEncode({
  '__className__': 'SurfaceContractFamilyOperationResult',
  'family': {
    '__className__': 'SurfaceContractFamilyReference',
    'surfaceType': 'paywall',
    'surfaceSlug': 'pro',
    'sourceKind': 'paywall',
  },
  'publishedRevision': revision,
  'activePublishedRevisionBefore': ?before,
  'activePublishedRevisionAfter': revision,
  'identityFrozenAfter': false,
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

  /// Run `publish` against a client whose `activateSurface` stands in for
  /// the server: a null revision activates the newest of [history].
  Future<int?> runPublish(
    List<String> args, {
    required List<int> history,
    void Function(Map<String, dynamic> body)? onActivate,
  }) {
    final client = mockHttpClient((request) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['method'], 'activateSurface');
      onActivate?.call(body);
      final revision =
          body['publishedRevision'] as int? ??
          (history.isEmpty ? null : history.reduce(max));
      if (revision == null) {
        return typedErrorResponse('SurfaceContractFamilyViolation', {
          'code': 'familyNotFound',
          'message': 'The surface has no pushed revision here.',
        });
      }
      return http.Response(_activationResponse(revision: revision), 200);
    });
    return runWith(client, args);
  }

  group('on the live plane', () {
    Future<int?> runLive(
      List<String> global, {
      required void Function() onActivate,
    }) =>
        (CommandRunner<int>('restage', '')
              ..argParser.addFlag('yes', negatable: false)
              ..addCommand(
                SurfacePublishCommand(
                  stdout: out,
                  stderr: err,
                  interactive: const NonInteractive(),
                  fixedSurfaceType: Surface.paywall,
                  credentialStore: store,
                  httpClient: mockHttpClient((request) {
                    onActivate();
                    return http.Response(_activationResponse(revision: 3), 200);
                  }),
                ),
              ))
            .run([
              ...global,
              'publish',
              'pro',
              '--revision',
              '3',
              '--project',
              'demo',
              '--app',
              'mobile',
              '--env',
              'production',
              '--plane',
              'live',
            ]);

    test('a non-interactive publish without --yes is refused', () async {
      var activated = false;
      final code = await runLive(const [], onActivate: () => activated = true);

      expect(code, 1);
      expect(activated, isFalse);
      expect(
        err.toString(),
        contains(
          'This changes what the live plane serves. Run interactively, or '
          'pass --yes.',
        ),
      );
    });

    test('--yes is consent', () async {
      var activated = false;
      final code = await runLive(const [
        '--yes',
      ], onActivate: () => activated = true);

      expect(code, 0, reason: err.toString());
      expect(activated, isTrue);
    });
  });

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
    expect(publishBody!.containsKey('contractVersion'), isFalse);
    expect(publishBody!['reason'], 'restore known good revision');
    expect(out.toString(), contains('Published "pro" at r3'));
    expect(out.toString(), contains('Reach: No version is live.'));
    expect(
      out.toString(),
      contains(
        'Watch it climb: restage surface status pro --type paywall --watch',
      ),
    );
    expect(err.toString(), isEmpty);
  });

  test('without --revision the server publishes the newest revision', () async {
    Map<String, dynamic>? publishBody;
    final code = await runPublish(
      ['pro'],
      history: const <int>[1, 5, 2],
      onActivate: (body) => publishBody = body,
    );

    expect(code, 0, reason: err.toString());
    expect(publishBody!['publishedRevision'], isNull);
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

  test('publishing the live revision says nothing changed', () async {
    final client = mockHttpClient(
      (request) =>
          http.Response(_activationResponse(revision: 6, before: 6), 200),
    );

    final code = await runWith(client, ['pro', '--revision', '6']);

    expect(code, 0, reason: err.toString());
    expect(
      out.toString(),
      contains('"pro" r6 is already live in staging. Devices see no change.'),
    );
    expect(out.toString(), isNot(contains('Published "pro"')));
  });

  test('publishing over another live revision reads as a publish', () async {
    final client = mockHttpClient(
      (request) =>
          http.Response(_activationResponse(revision: 6, before: 5), 200),
    );

    final code = await runWith(client, ['pro', '--revision', '6']);

    expect(code, 0, reason: err.toString());
    expect(out.toString(), contains('Published "pro" at r6'));
    expect(out.toString(), isNot(contains('already live')));
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

  test('a family with nothing pushed reads the server refusal', () async {
    final code = await runPublish(['pro'], history: const <int>[]);

    expect(code, 1);
    expect(err.toString(), 'The surface has no pushed revision here.\n');
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
