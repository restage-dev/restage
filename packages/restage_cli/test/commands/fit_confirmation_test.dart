import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:restage_cli/api.dart';
import 'package:restage_cli/src/api/typed_error_renderer.dart'
    show fitSharePercent;
import 'package:restage_cli/src/commands/surface_publish_command.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:test/test.dart';

import '../_helpers/test_fixtures.dart';

Map<String, dynamic> _fitFields({bool noneFit = false}) => {
  'verdict': noneFit ? 'noneFit' : 'someFit',
  'environment': 'staging',
  if (!noneFit) 'share': 0.62,
  'builds': {
    'items': [
      {
        'platform': 'ios',
        'appVersion': '2.3.0',
        'uploaded': false,
        'fits': false,
      },
      {'uploaded': true, 'fits': false},
      {
        'platform': 'ios',
        'appVersion': '2.4.0',
        'uploaded': false,
        'fits': true,
      },
    ],
  },
};

http.Response _fitResponse({bool noneFit = false}) => typedErrorResponse(
  'SurfaceFitNeedsConfirmationException',
  _fitFields(noneFit: noneFit),
);

String _activated() => jsonEncode({
  '__className__': 'SurfaceContractFamilyOperationResult',
  'family': {
    '__className__': 'SurfaceContractFamilyReference',
    'surfaceType': 'paywall',
    'surfaceSlug': 'pro',
    'sourceKind': 'paywall',
  },
  'publishedRevision': 3,
  'activePublishedRevisionAfter': 3,
  'identityFrozenAfter': false,
});

class _Asks implements Interactive {
  _Asks({required this.answer});
  final bool answer;
  final List<String> questions = [];

  @override
  bool get isInteractive => true;

  @override
  Future<bool> confirm(String question, {bool defaultYes = false}) async {
    questions.add(question);
    return answer;
  }

  @override
  Future<String> prompt(String question, {String? defaultValue}) async =>
      defaultValue ?? '';

  @override
  Future<T> select<T>(
    String question,
    List<({String label, T value})> options, {
    T? defaultValue,
  }) async => defaultValue ?? options.first.value;

  @override
  Future<String> secret(String question) async => '';

  @override
  Spinner spinner(String message) => throw UnimplementedError();
}

void main() {
  late Directory tempDir;
  late FileCredentialStore store;
  late StringBuffer out;
  late StringBuffer err;
  late List<Map<String, dynamic>> calls;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('fit_confirmation_');
    store = FileCredentialStore(p.join(tempDir.path, 'credentials'));
    await seedCredential(store);
    out = StringBuffer();
    err = StringBuffer();
    calls = [];
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  /// `surface publish` against a server that holds the first activation for
  /// a fit confirmation and accepts the one that carries `acceptFit`.
  Future<int?> publish({
    List<String> global = const [],
    Interactive interactive = const NonInteractive(),
    bool noneFit = false,
  }) =>
      (CommandRunner<int>('restage', '')
            ..argParser.addFlag('yes', negatable: false)
            ..addCommand(
              SurfacePublishCommand(
                stdout: out,
                stderr: err,
                interactive: interactive,
                fixedSurfaceType: Surface.paywall,
                credentialStore: store,
                httpClient: mockHttpClient((request) {
                  final body = jsonDecode(request.body) as Map<String, dynamic>;
                  calls.add(body);
                  return body['acceptFit'] == true
                      ? http.Response(_activated(), 200)
                      : _fitResponse(noneFit: noneFit);
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
            'staging',
          ]);

  group('surface publish', () {
    test('without --yes it names the builds and asks for --yes', () async {
      final code = await publish();

      expect(code, 1);
      expect(calls, hasLength(1));
      expect(err.toString(), '''
Not every app version can show this.
62% of users are on versions that can.
  ios 2.3.0
  Uploaded build
Use --yes to go ahead.
''');
    });

    test('none fit has its own title and no share line', () async {
      await publish(noneFit: true);

      expect(
        err.toString(),
        startsWith('No app version in use can show this yet.\n  ios 2.3.0'),
      );
      expect(err.toString(), isNot(contains('of users')));
    });

    test('--yes resends the same call with acceptFit', () async {
      final code = await publish(global: const ['--yes']);

      expect(code, 0, reason: err.toString());
      expect(calls, hasLength(2));
      expect(calls[0].containsKey('acceptFit'), isFalse);
      expect(calls[1]['acceptFit'], isTrue);
      expect(calls[1]['publishedRevision'], calls[0]['publishedRevision']);
      expect(err.toString(), contains('Not every app version can show this.'));
      expect(out.toString(), contains('Published "pro" at r3'));
    });

    test('an interactive yes goes ahead', () async {
      final asks = _Asks(answer: true);
      final code = await publish(interactive: asks);

      expect(code, 0, reason: err.toString());
      expect(asks.questions, ['Publish anyway?']);
      expect(calls, hasLength(2));
      expect(out.toString(), contains('Not every app version can show this.'));
    });

    test('an interactive no stops after one call', () async {
      final code = await publish(interactive: _Asks(answer: false));

      expect(code, 1);
      expect(calls, hasLength(1));
      expect(out.toString(), contains('Aborted.'));
      expect(err.toString(), isNot(contains('Use --yes')));
    });
  });

  test('the share reads 0%, <1%, whole percents, and never 100%', () {
    expect(fitSharePercent(0), '0%');
    expect(fitSharePercent(0.004), '<1%');
    expect(fitSharePercent(0.005), '1%');
    expect(fitSharePercent(0.62), '62%');
    expect(fitSharePercent(0.996), '99%');
  });

  group('RestageApi', () {
    RestageApi api(http.Client client, [FitDecider? decider]) => RestageApi(
      endpoint: Uri.parse('https://api.test/'),
      httpClient: client,
      fitDecider: decider,
    );

    for (final (endpoint, method) in [
      ('surface', 'activateSurface'),
      ('deliveryPolicy', 'publish'),
      ('experimentAuthoring', 'resumeExperiment'),
      ('somethingNew', 'goLive'),
    ]) {
      test(
        '$endpoint.$method is sent again with acceptFit once accepted',
        () async {
          final sent = <Map<String, dynamic>>[];
          final client = api(
            mockHttpClient((request) {
              final body = jsonDecode(request.body) as Map<String, dynamic>;
              sent.add(body);
              return body['acceptFit'] == true
                  ? http.Response('"ok"', 200)
                  : _fitResponse();
            }),
            (needs) async {
              expect(needs.noneFit, isFalse);
              expect(needs.share, 0.62);
              return true;
            },
          );

          expect(await client.call(endpoint, method, {'x': 1}), 'ok');
          expect(sent.map((b) => b['acceptFit']), [null, true]);
          expect(sent.last['x'], 1);
        },
      );
    }

    test('an error that is not a fit report is never asked about', () async {
      var asked = false;
      final client = api(mockHttpClient((_) => http.Response('{}', 400)), (
        _,
      ) async {
        asked = true;
        return true;
      });

      await expectLater(
        client.call('surface', 'activateSurface', {}),
        throwsA(isA<RestageApiException>()),
      );
      expect(asked, isFalse);
    });

    test('a no keeps the server answer', () async {
      final client = api(
        mockHttpClient((_) => _fitResponse()),
        (_) async => false,
      );

      await expectLater(
        client.call('surface', 'activateSurface', {}),
        throwsA(isA<RestageApiException>()),
      );
    });

    test('a call that already carries acceptFit is not asked again', () async {
      var calls = 0;
      final client = api(
        mockHttpClient((_) {
          calls++;
          return _fitResponse();
        }),
        (_) async => true,
      );

      await expectLater(
        client.call('surface', 'activateSurface', {}),
        throwsA(isA<RestageApiException>()),
      );
      expect(calls, 2);
    });

    test('a call sent with acceptFit from the start is never held', () async {
      final sent = <Map<String, dynamic>>[];
      final client = api(
        mockHttpClient((request) {
          sent.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response('"ok"', 200);
        }),
      );

      await client.call('surface', 'activateSurface', {'acceptFit': true});
      expect(sent, hasLength(1));
    });
  });
}
