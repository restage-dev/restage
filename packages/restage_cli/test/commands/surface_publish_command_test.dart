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
String _activationResponse({
  required int revision,
  int? before,
  List<Map<String, Object?>>? runningExperiments,
}) => jsonEncode({
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
  'runningExperiments': ?runningExperiments,
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

  test('a running experiment is named with how to end it', () async {
    final client = mockHttpClient(
      (request) => http.Response(
        _activationResponse(
          revision: 4,
          runningExperiments: [
            {
              '__className__': 'SurfaceRunningExperiment',
              'experimentId': 'exp-1',
              'experimentLabel': 'Checkout copy',
              'audienceLabel': 'Everyone',
              'lifecycleOrdinal': 2,
            },
            {
              '__className__': 'SurfaceRunningExperiment',
              'experimentId': 'exp-2',
              'lifecycleOrdinal': 5,
            },
          ],
        ),
        200,
      ),
    );

    final code = await runWith(client, ['pro', '--revision', '4']);

    expect(code, 0, reason: err.toString());
    expect(
      err.toString(),
      'Experiment "Checkout copy" (exp-1) is running on this surface. '
      'Devices in its "Everyone" audience keep their arm\'s version until it '
      'ends; every other device gets this version now.\n'
      'Try `restage experiment conclude --experiment-id exp-1 '
      '--expected-lifecycle-ordinal 2 --organization restage --project demo '
      '--app mobile --env staging` to end it.\n'
      'Experiment exp-2 is running on this surface. Devices its audience '
      'admits keep their arm\'s version until it ends; every other device '
      'gets this version now.\n'
      'Try `restage experiment conclude --experiment-id exp-2 '
      '--expected-lifecycle-ordinal 5 --organization restage --project demo '
      '--app mobile --env staging` to end it.\n',
    );
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

  group('when the gateway times out', () {
    /// Activation answers come from [responses] in order; returns the bodies.
    Future<(int?, List<Map<String, dynamic>>)> publishThrough(
      List<http.Response Function()> responses,
    ) async {
      final bodies = <Map<String, dynamic>>[];
      final client = mockHttpClient((request) {
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return responses[bodies.length - 1]();
      });
      final code = await runWith(client, ['pro', '--revision', '6']);
      return (code, bodies);
    }

    http.Response timedOut() => http.Response('error code: 524', 524);
    http.Response published() =>
        http.Response(_activationResponse(revision: 6, before: 5), 200);

    test('the same operation is sent again and its result reported', () async {
      final (code, bodies) = await publishThrough([timedOut, published]);

      expect(code, 0, reason: err.toString());
      expect(out.toString(), contains('Published "pro" at r6'));
      expect(err.toString(), isEmpty);
      expect(bodies, hasLength(2));
      expect(
        bodies.last['measurementProceedBytes'],
        bodies.first['measurementProceedBytes'],
      );
      expect(bodies.first['measurementProceedBytes'], isNotNull);
    });

    test('a lost connection is retried the same way', () async {
      final (code, bodies) = await publishThrough([
        () => throw http.ClientException('Connection closed'),
        published,
      ]);

      expect(code, 0, reason: err.toString());
      expect(bodies, hasLength(2));
    });

    test('a server refusal is reported without a retry', () async {
      final (code, bodies) = await publishThrough([
        () => typedErrorResponse('SurfaceContractFamilyViolation', {
          'code': 'familyNotFound',
          'message': 'The surface has no pushed revision here.',
        }),
      ]);

      expect(code, 1);
      expect(bodies, hasLength(1));
    });

    test('a gateway that keeps timing out still fails', () async {
      final (code, bodies) = await publishThrough([
        timedOut,
        timedOut,
        timedOut,
      ]);

      expect(code, isNot(0));
      expect(bodies, hasLength(3));
      expect(err.toString(), contains('524'));
    });
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
