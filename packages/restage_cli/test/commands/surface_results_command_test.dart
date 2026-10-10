import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/commands/surface_results_command.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:test/test.dart';

import '../_helpers/test_fixtures.dart';

/// The target the shared discovery fixture resolves for `mobile` + `production`.
final _target = TargetCoordinate(
  organizationId: OrganizationId(7),
  appId: ApplicationId(5),
  environmentTargetId: EnvironmentTargetId(13),
  namedEnvironmentId: NamedEnvironmentId(23),
  runtimePlane: RuntimePlane.live,
);

const _surfaceId = 'surface.v1.welcome';
const _revisionId = 'surface-revision.v1.welcome.3';

/// One reading, built through the contract's own constructors.
SurfaceFunnelViewV1 _view({String? surfaceId, String? surfaceType}) =>
    SurfaceFunnelViewV1.of(
      target: _target,
      surfaceId: surfaceId ?? _surfaceId,
      surfaceType: surfaceType,
      windowStartMicros: 1788000000000000,
      windowEndExclusiveMicros: 1788600000000000,
      asOfMicros: 1788600000000001,
      disclosureFloor: 5,
      versions: [
        SurfaceFunnelVersionV1.of(
          surfaceRevisionId: _revisionId,
          revisionOrdinal: 3,
          publishedAtMicros: 1787900000000000,
          status: SurfaceFunnelVersionStatusV1.available,
          disclosure: SurfaceFunnelDisclosureV1.disclosed,
          counts: SurfaceFunnelCountsV1.of(
            eligibleRoots: 5000,
            views: 5000,
            completions: 525,
            skips: 240,
            dismissals: 310,
            reachedAnotherStep: 4100,
            completeRoots: 4900,
            pendingRoots: 60,
            unavailableRoots: 40,
            path: 'counts',
          ),
          unattributedDismissals: 12,
          stateTransitions: const {
            'intro': ['plan'],
            'plan': <String>[],
          },
          steps: [
            SurfaceFunnelStepV1.of(
              stateId: 'intro',
              screenArtifactId: 'intro-screen',
              screenContentHash: 'a' * 64,
              screenVersion: 3,
              disclosure: SurfaceFunnelDisclosureV1.disclosed,
              counts: SurfaceFunnelCountsV1.of(
                eligibleRoots: 5000,
                views: 4900,
                completions: 0,
                skips: 100,
                dismissals: 180,
                reachedAnotherStep: 4100,
                completeRoots: 4900,
                pendingRoots: 60,
                unavailableRoots: 40,
                path: 'counts',
              ),
              transitionTargets: const ['plan'],
              path: 'step',
            ),
            SurfaceFunnelStepV1.of(
              stateId: 'plan',
              screenArtifactId: 'plan-screen',
              screenContentHash: 'b' * 64,
              screenVersion: 3,
              disclosure: SurfaceFunnelDisclosureV1.belowDisclosureFloor,
              path: 'step',
            ),
          ],
          bands: [
            SurfaceFunnelBandV1.of(
              point: MeasurementBreakdownPointV1(
                kindV1: MeasurementBreakdownPointKindV1.pageIndex,
                reference: '0',
                label: 'Intro',
                authoredOrder: 0,
              ),
              disclosure: SurfaceFunnelDisclosureV1.disclosed,
              counts: SurfaceFunnelBandCountsV1.of(
                eligibleRoots: 5000,
                reach: 4900,
                occurrences: 5100,
                continued: 4100,
                completeRoots: 4900,
                pendingRoots: 60,
                unavailableRoots: 40,
                path: 'band',
              ),
              path: 'band',
            ),
          ],
          path: 'version',
        ),
      ],
    );

String _wire(List<int> bytes) => "decode('${base64Encode(bytes)}', 'base64')";

/// The response envelope for a typed refusal.
String _rejection(String reason, String detail) => jsonEncode({
  'className': 'MeasurementReadRejectedException',
  'data': {
    '__className__': 'MeasurementReadRejectedException',
    'reason': reason,
    'detail': detail,
  },
});

void main() {
  late Directory tempDir;
  late FileCredentialStore store;
  late List<Map<String, dynamic>> sent;

  setUp(() async {
    sent = [];
    tempDir = await Directory.systemTemp.createTemp('surface_results_');
    store = FileCredentialStore(p.join(tempDir.path, 'credentials'));
    await seedCredential(store);
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  /// A route that records the funnel request and answers with [reply].
  http.Client route(http.Response Function(Map<String, dynamic> body) reply) =>
      mockHttpClient((request) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['method'], 'readSurfaceFunnel');
        sent.add(body);
        return reply(body);
      });

  http.Response accepted(Map<String, dynamic> body) =>
      http.Response(jsonEncode(_wire(_view().canonicalBytes)), 200);

  Future<({int code, String out, String err})> run(
    List<String> arguments, {
    http.Client? client,
    DateTime Function()? now,
  }) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final runner = CommandRunner<int>('restage', '')
      ..addCommand(
        SurfaceResultsCommand(
          stdout: out,
          stderr: err,
          interactive: const NonInteractive(),
          credentialStore: store,
          httpClient: client ?? route(accepted),
          now: now,
        ),
      );
    final code = await runner.run([
      'results',
      ...arguments,
      '--project',
      'p',
      '--app',
      'mobile',
      '--env',
      'production',
    ]);
    return (code: code ?? 1, out: out.toString(), err: err.toString());
  }

  group('the window a read asks for', () {
    test('is the pair of instants the caller named', () async {
      final result = await run([
        _surfaceId,
        '--from=2026-09-01T00:00:00Z',
        '--until=2026-09-08T00:00:00Z',
      ]);

      expect(result.code, 0, reason: result.err);
      expect(
        sent.single['windowStartMicros'],
        DateTime.utc(2026, 9).microsecondsSinceEpoch,
      );
      expect(
        sent.single['windowEndExclusiveMicros'],
        DateTime.utc(2026, 9, 8).microsecondsSinceEpoch,
      );
      expect(sent.single['surfaceId'], _surfaceId);
      expect(sent.single['organizationId'], 7);
      expect(sent.single['appId'], 5);
      expect(sent.single['environmentTargetId'], 13);
      expect(sent.single['namedEnvironmentId'], 23);
      expect(sent.single['runtimePlane'], 'live');
    });

    test('reads a local instant as the instant it names', () async {
      await run([_surfaceId, '--from=2026-09-01T02:00:00+02:00']);

      expect(
        sent.single['windowStartMicros'],
        DateTime.utc(2026, 9).microsecondsSinceEpoch,
      );
    });

    test('ends now and runs back $kSurfaceResultsDefaultWindowDays days when '
        'the caller names neither end', () async {
      final now = DateTime.utc(2026, 9, 16, 12, 30);

      final result = await run([_surfaceId], now: () => now);

      expect(result.code, 0, reason: result.err);
      expect(
        sent.single['windowEndExclusiveMicros'],
        now.microsecondsSinceEpoch,
      );
      expect(
        sent.single['windowStartMicros'],
        now
            .subtract(const Duration(days: kSurfaceResultsDefaultWindowDays))
            .microsecondsSinceEpoch,
      );
    });

    test('runs back from the named end when only --until is given', () async {
      await run([_surfaceId, '--until=2026-09-16T00:00:00Z']);

      final until = DateTime.utc(2026, 9, 16);
      expect(
        sent.single['windowEndExclusiveMicros'],
        until.microsecondsSinceEpoch,
      );
      expect(
        sent.single['windowStartMicros'],
        until
            .subtract(const Duration(days: kSurfaceResultsDefaultWindowDays))
            .microsecondsSinceEpoch,
      );
    });

    test('names the flag a caller got wrong, before any request', () async {
      final result = await run([
        _surfaceId,
        '--from=last tuesday',
      ], client: mockHttpClient((request) => fail('The route was reached.')));

      expect(result.code, 1);
      expect(result.err, contains('--from'));
      expect(sent, isEmpty);
    });

    test('refuses an end at or before its start, before any request', () async {
      final result = await run([
        _surfaceId,
        '--from=2026-09-08T00:00:00Z',
        '--until=2026-09-01T00:00:00Z',
      ], client: mockHttpClient((request) => fail('The route was reached.')));

      expect(result.code, 1);
      expect(result.err, contains('windowEndExclusiveMicros'));
      expect(sent, isEmpty);
    });

    test('refuses the same version twice, before any request', () async {
      final result = await run([
        _surfaceId,
        '--version=$_revisionId',
        '--version=$_revisionId',
      ], client: mockHttpClient((request) => fail('The route was reached.')));

      expect(result.code, 1);
      expect(result.err, contains('surfaceRevisionIds'));
      expect(sent, isEmpty);
    });

    test('carries the versions the caller named', () async {
      await run([_surfaceId, '--version=$_revisionId']);

      expect(sent.single['surfaceRevisionIds'], [_revisionId]);
    });

    test('names exactly one surface', () async {
      final result = await run([
        _surfaceId,
        'surface.v1.other',
      ], client: mockHttpClient((request) => fail('The route was reached.')));

      expect(result.code, 1);
      expect(result.err, contains('exactly one surface'));
    });
  });

  group('what the command prints', () {
    test('states each version, its figures, its steps and its bands', () async {
      final result = await run([_surfaceId]);

      expect(result.code, 0, reason: result.err);
      final out = result.out;
      expect(out, contains('Funnel for $_surfaceId, 1 version(s), floor 5:'));
      expect(out, contains('v3 $_revisionId [available]'));
      expect(out, contains('views 5,000 of 5,000'));
      expect(out, contains('completions 525'));
      expect(out, contains('conversion 0.105000000 (525/5000)'));
      expect(out, contains('step intro: views 4,900 of 5,000, onward 4,100'));
      expect(out, contains('-> plan'));
      expect(out, contains('step plan: views <5'));
      expect(out, contains('Intro: reach 4,900 of 5,000'));
      expect(out, contains('drop-off 0.163265306 (800/4900)'));
    });

    test('names the surface type when the service resolved one', () async {
      final result = await run(
        [_surfaceId],
        client: route(
          (body) => http.Response(
            jsonEncode(_wire(_view(surfaceType: 'onboarding').canonicalBytes)),
            200,
          ),
        ),
      );

      expect(result.out, contains('Funnel for $_surfaceId (onboarding)'));
    });

    test(
      'prints the whole reading under --json, exact pairs included',
      () async {
        final result = await run([_surfaceId, '--json']);

        expect(result.code, 0, reason: result.err);
        final decoded = jsonDecode(result.out) as Map<String, Object?>;
        // The printed document is the reading, unchanged.
        expect(
          SurfaceFunnelViewV1.fromJson(decoded).canonicalBytes,
          _view().canonicalBytes,
        );
        final version =
            (decoded['versions']! as List).single as Map<String, Object?>;
        final counts = version['counts']! as Map<String, Object?>;
        final conversion = counts['conversionRate']! as Map<String, Object?>;
        expect(conversion['decimal'], '0.105000000');
        expect(conversion['exact'], {'denominator': '200', 'numerator': '21'});
      },
    );
  });

  group('what the command reports', () {
    test('states a typed refusal once, in the shared wording', () async {
      final result = await run(
        [_surfaceId],
        client: route(
          (body) => http.Response(
            _rejection(
              'windowSpansTooManyPublications',
              'This surface has 91 published versions. Name the versions to '
                  'read.',
            ),
            400,
          ),
        ),
      );

      expect(result.code, 1);
      expect(result.err, contains('The read was refused.'));
      expect(result.err, contains('91 published versions'));
      // Stated once, by the shared renderer, with no second wording beside it.
      expect('The read was refused.'.allMatches(result.err), hasLength(1));
    });

    test(
      'sends the operator back to sign in on a rejected credential',
      () async {
        final result = await run([
          _surfaceId,
        ], client: route((body) => http.Response('', 401)));

        expect(result.code, 1);
        expect(result.err, contains('restage login'));
      },
    );

    test('names the status it could not read', () async {
      final result = await run([
        _surfaceId,
      ], client: route((body) => http.Response('', 500)));

      expect(result.code, 2);
      expect(result.err, contains('HTTP 500'));
    });

    test('refuses a reading bound to another surface', () async {
      final result = await run(
        [_surfaceId],
        client: route(
          (body) => http.Response(
            jsonEncode(
              _wire(_view(surfaceId: 'surface.v1.other').canonicalBytes),
            ),
            200,
          ),
        ),
      );

      expect(result.code, 2);
      expect(result.err, contains('another surface or target'));
    });

    test('refuses bytes that are not the published contract', () async {
      final result = await run(
        [_surfaceId],
        client: route(
          (body) => http.Response(jsonEncode(_wire(utf8.encode('{}'))), 200),
        ),
      );

      expect(result.code, 2);
      expect(result.err, contains('invalid funnel reading'));
    });
  });
}
