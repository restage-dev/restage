import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/commands/surface_routing_command.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:test/test.dart';

import '../_helpers/test_fixtures.dart';

/// The wire form the service reads byte columns as.
String wire(List<int> bytes) => "decode('${base64Encode(bytes)}', 'base64')";

final _diagnosticsTarget = TargetCoordinate(
  organizationId: OrganizationId(7),
  appId: ApplicationId(8),
  environmentTargetId: EnvironmentTargetId(12),
  namedEnvironmentId: NamedEnvironmentId(22),
  runtimePlane: RuntimePlane.sandbox,
);

MeasurementDeliveryDiagnosticsV1 diagnosticsRead({
  MeasurementDeliveryDiagnosticsSectionV1? servedDefaults,
  MeasurementDeliveryDiagnosticsSectionV1? recordedRefusals,
}) => MeasurementDeliveryDiagnosticsV1(
  target: _diagnosticsTarget,
  surfaceType: MeasurementDeliveryDiagnosticsSurfaceTypeV1.onboarding,
  surfaceSlug: 'welcome',
  contractVersion: 3,
  windowStartDayUtc: DateTime.utc(2026, 9, 1).microsecondsSinceEpoch,
  windowEndDayExclusiveUtc: DateTime.utc(2026, 9, 3).microsecondsSinceEpoch,
  disclosureFloor: measurementDeliveryDiagnosticsDisclosureFloor,
  servedDefaults:
      servedDefaults ??
      MeasurementDeliveryDiagnosticsSectionV1(
        population: MeasurementDeliveryDiagnosticsPopulationV1
            .servedDefaultPresentations,
        coverage: MeasurementDeliveryDiagnosticsCoverageV1
            .observedAdmittedPresentations,
        availability:
            MeasurementDeliveryDiagnosticsAvailabilityV1.partiallyHeld,
        reasons: [
          MeasurementDeliveryDiagnosticsReasonCountV1(
            reason: 'frozen',
            observedCount: 5,
          ),
          MeasurementDeliveryDiagnosticsReasonCountV1(reason: 'futureDefault'),
        ],
      ),
  recordedRefusals:
      recordedRefusals ??
      MeasurementDeliveryDiagnosticsSectionV1(
        population:
            MeasurementDeliveryDiagnosticsPopulationV1.recordedServerRefusals,
        coverage: MeasurementDeliveryDiagnosticsCoverageV1
            .observedRecordedServerRefusals,
        availability: MeasurementDeliveryDiagnosticsAvailabilityV1.held,
        reasons: [
          MeasurementDeliveryDiagnosticsReasonCountV1(
            reason: 'audienceUndecided',
          ),
        ],
      ),
);

void main() {
  late Directory tempDir;
  late FileCredentialStore fakeStore;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('surface_routing_');
    fakeStore = FileCredentialStore(p.join(tempDir.path, 'credentials'));
    await seedCredential(fakeStore);
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Future<String> seedBytes(String name, List<int> bytes) async {
    final file = File(p.join(tempDir.path, name));
    await file.writeAsBytes(bytes);
    return file.path;
  }

  CommandRunner<int> makeRunner({
    required StringSink stdout,
    required StringSink stderr,
    required http.Client httpClient,
  }) {
    final runner = CommandRunner<int>('restage', '');
    runner.addCommand(
      SurfaceRoutingCommand(
        stdout: stdout,
        stderr: stderr,
        interactive: const NonInteractive(),
        credentialStore: fakeStore,
        httpClient: httpClient,
      ),
    );
    return runner;
  }

  List<String> target() => const [
    '--project',
    'p',
    '--app',
    'a',
    '--env',
    'staging',
  ];

  http.Response json(Map<String, dynamic> body) =>
      http.Response(jsonEncode(body), 200);

  http.Response jsonList(List<dynamic> body) =>
      http.Response(jsonEncode(body), 200);

  http.Response byteData(List<int> bytes) =>
      http.Response(jsonEncode(wire(bytes)), 200);

  http.Response refusal(String reason, {int status = 400}) => http.Response(
    jsonEncode({
      'className': 'SurfaceRoutingRejectedException',
      'data': {
        '__className__': 'SurfaceRoutingRejectedException',
        'reason': reason,
      },
    }),
    status,
  );

  http.Response conflict({int? expected, int? actual}) => http.Response(
    jsonEncode({
      'className': 'SurfaceRoutingConflictException',
      'data': {
        '__className__': 'SurfaceRoutingConflictException',
        'expectedRevisionOrdinal': expected,
        'actualRevisionOrdinal': actual,
      },
    }),
    400,
  );

  http.Response unauthorized() => http.Response(
    jsonEncode({
      'className': 'UnauthorizedException',
      'data': {
        '__className__': 'UnauthorizedException',
        'resource': 'surfaceRouting',
      },
    }),
    403,
  );

  group('target propagation', () {
    test('every read carries the complete target on the routing endpoint, '
        'and the environment is the exact target id', () async {
      Map<String, dynamic>? captured;
      Uri? seenUrl;
      final client = scriptedHttpClient([
        (request) {
          seenUrl = request.url;
          captured = jsonDecode(request.body) as Map<String, dynamic>;
          return json({
            'empty': false,
            'documentBytes': wire(const [1, 2, 3]),
            'revisionOrdinal': 4,
          });
        },
      ]);

      final code =
          await makeRunner(
            stdout: StringBuffer(),
            stderr: StringBuffer(),
            httpClient: client,
          ).run([
            'routing',
            'read',
            'welcome',
            ...target(),
            '--type',
            'onboarding',
            '--contract-version',
            '3',
          ]);

      expect(code, 0);
      expect(seenUrl!.path, endsWith('/surfaceRouting'));
      expect(captured!['method'], 'readRouting');
      expect(captured!['projectSlug'], 'p');
      expect(captured!['appSlug'], 'a');
      expect(captured!['surfaceType'], 'onboarding');
      expect(captured!['surfaceSlug'], 'welcome');
      expect(captured!['contractVersion'], 3);
      expect(captured!['organizationId'], 7);
      // The routing endpoint addresses one concrete environment target, not
      // the named environment (22) above it.
      expect(captured!['environmentId'], 12);
    });

    test('a publish carries the same complete target', () async {
      Map<String, dynamic>? captured;
      final path = await seedBytes('doc.bin', const [9, 9, 9]);
      final client = scriptedHttpClient([
        (request) {
          captured = jsonDecode(request.body) as Map<String, dynamic>;
          return json({'outcome': 'applied', 'revisionOrdinal': 5});
        },
      ]);

      final code =
          await makeRunner(
            stdout: StringBuffer(),
            stderr: StringBuffer(),
            httpClient: client,
          ).run([
            'routing',
            'publish',
            'welcome',
            ...target(),
            '--type',
            'onboarding',
            '--document',
            path,
            '--expected-revision-ordinal',
            '4',
          ]);

      expect(code, 0);
      expect(captured!['method'], 'publishRouting');
      expect(captured!['projectSlug'], 'p');
      expect(captured!['appSlug'], 'a');
      expect(captured!['surfaceType'], 'onboarding');
      expect(captured!['surfaceSlug'], 'welcome');
      expect(captured!['environmentId'], 12);
      expect(captured!['organizationId'], 7);
    });
  });

  test(
    'a live publish without --yes is refused when non-interactive',
    () async {
      var called = false;
      final path = await seedBytes('doc.bin', const [9, 9, 9]);
      final err = StringBuffer();
      final code =
          await makeRunner(
            stdout: StringBuffer(),
            stderr: err,
            httpClient: mockHttpClient((request) {
              called = true;
              return json({'outcome': 'applied', 'revisionOrdinal': 5});
            }),
          ).run([
            'routing',
            'publish',
            'welcome',
            '--project',
            'p',
            '--app',
            'a',
            '--env',
            'production',
            '--plane',
            'live',
            '--type',
            'onboarding',
            '--document',
            path,
            '--expected-revision-ordinal',
            '4',
          ]);

      expect(code, 1);
      expect(called, isFalse);
      expect(err.toString(), contains('changes what the live plane serves'));
    },
  );

  group('the document travels whole and unread', () {
    test('publish sends the file bytes exactly, so both branches of a '
        'percentage route reach the service together', () async {
      // Two destinations in one document. The client never decodes it; the
      // pin is that every byte arrives.
      final document = Uint8List.fromList(
        utf8.encode('{"routes":[{"primary":11,"remainder":12}]}'),
      );
      final path = await seedBytes('percentage.bin', document);
      Map<String, dynamic>? captured;
      final client = scriptedHttpClient([
        (request) {
          captured = jsonDecode(request.body) as Map<String, dynamic>;
          return json({'outcome': 'applied', 'revisionOrdinal': 2});
        },
      ]);

      final code =
          await makeRunner(
            stdout: StringBuffer(),
            stderr: StringBuffer(),
            httpClient: client,
          ).run([
            'routing',
            'publish',
            'welcome',
            ...target(),
            '--type',
            'onboarding',
            '--document',
            path,
            '--expect-no-revision',
          ]);

      expect(code, 0);
      expect(captured!['documentBytes'], wire(document));
    });

    test('read writes the returned bytes back out unchanged', () async {
      final stored = Uint8List.fromList(List<int>.generate(64, (i) => i));
      final out = p.join(tempDir.path, 'out.bin');
      final client = scriptedHttpClient([
        (_) => json({
          'empty': false,
          'documentBytes': wire(stored),
          'revisionOrdinal': 7,
        }),
      ]);

      final code =
          await makeRunner(
            stdout: StringBuffer(),
            stderr: StringBuffer(),
            httpClient: client,
          ).run([
            'routing',
            'read',
            'welcome',
            ...target(),
            '--type',
            'onboarding',
            '--out',
            out,
          ]);

      expect(code, 0);
      expect(File(out).readAsBytesSync(), stored);
    });

    test('preview reports the service classification and never evaluates a '
        'rule locally', () async {
      // The document is not a routing document at all and the request context
      // is empty of anything a rule could read. A client that evaluated
      // locally could not return `matched`; this one prints what it is told.
      final document = await seedBytes('opaque.bin', utf8.encode('not-a-doc'));
      final schema = await seedBytes('schema.bin', const [1]);
      final context = await seedBytes('context.bin', const [2]);
      final audience = await seedBytes('audience.bin', const [3]);
      Map<String, dynamic>? captured;
      final client = scriptedHttpClient([
        (request) {
          captured = jsonDecode(request.body) as Map<String, dynamic>;
          return json({
            'rules': [
              {'routeId': 'r1', 'matches': true, 'reason': 'matched'},
              {'routeId': 'r2', 'matches': false, 'reason': 'disabled'},
            ],
            'deliveryBytes': wire(const [7, 7]),
            'usesActivePointer': false,
          });
        },
      ]);

      final out = StringBuffer();
      final code =
          await makeRunner(
            stdout: out,
            stderr: StringBuffer(),
            httpClient: client,
          ).run([
            'routing',
            'preview',
            'welcome',
            ...target(),
            '--type',
            'onboarding',
            '--document',
            document,
            '--schema',
            schema,
            '--request-context',
            context,
            '--audience',
            audience,
          ]);

      expect(code, 0);
      expect(captured!['method'], 'previewRouting');
      expect(captured!['audienceBytes'], [
        wire(const [3]),
      ]);
      expect(captured!['requestContextBytes'], wire(const [2]));
      expect(out.toString(), contains('r1\tmatch\tmatched'));
      expect(out.toString(), contains('r2\tno match\tdisabled'));
    });
  });

  group('the compare-and-set precondition', () {
    test('the expected ordinal reaches the service exactly', () async {
      final path = await seedBytes('doc.bin', const [1]);
      Map<String, dynamic>? captured;
      final client = scriptedHttpClient([
        (request) {
          captured = jsonDecode(request.body) as Map<String, dynamic>;
          return json({'outcome': 'applied', 'revisionOrdinal': 31});
        },
      ]);

      final code =
          await makeRunner(
            stdout: StringBuffer(),
            stderr: StringBuffer(),
            httpClient: client,
          ).run([
            'routing',
            'publish',
            'welcome',
            ...target(),
            '--type',
            'onboarding',
            '--document',
            path,
            '--expected-revision-ordinal',
            '30',
          ]);

      expect(code, 0);
      expect(captured!['expectedRevisionOrdinal'], 30);
    });

    test('--expect-no-revision sends a null precondition', () async {
      final path = await seedBytes('doc.bin', const [1]);
      Map<String, dynamic>? captured;
      final client = scriptedHttpClient([
        (request) {
          captured = jsonDecode(request.body) as Map<String, dynamic>;
          return json({'outcome': 'applied', 'revisionOrdinal': 1});
        },
      ]);

      final code =
          await makeRunner(
            stdout: StringBuffer(),
            stderr: StringBuffer(),
            httpClient: client,
          ).run([
            'routing',
            'publish',
            'welcome',
            ...target(),
            '--type',
            'onboarding',
            '--document',
            path,
            '--expect-no-revision',
          ]);

      expect(code, 0);
      expect(captured!.containsKey('expectedRevisionOrdinal'), isTrue);
      expect(captured!['expectedRevisionOrdinal'], isNull);
    });

    test('neither precondition is refused before any call', () async {
      final path = await seedBytes('doc.bin', const [1]);
      final err = StringBuffer();
      final code =
          await makeRunner(
            stdout: StringBuffer(),
            stderr: err,
            httpClient: scriptedHttpClient(const []),
          ).run([
            'routing',
            'publish',
            'welcome',
            ...target(),
            '--type',
            'onboarding',
            '--document',
            path,
          ]);

      expect(code, 1);
      expect(err.toString(), contains('exactly one'));
    });

    test('both preconditions together are refused before any call', () async {
      final path = await seedBytes('doc.bin', const [1]);
      final err = StringBuffer();
      final code =
          await makeRunner(
            stdout: StringBuffer(),
            stderr: err,
            httpClient: scriptedHttpClient(const []),
          ).run([
            'routing',
            'publish',
            'welcome',
            ...target(),
            '--type',
            'onboarding',
            '--document',
            path,
            '--expected-revision-ordinal',
            '4',
            '--expect-no-revision',
          ]);

      expect(code, 1);
      expect(err.toString(), contains('exactly one'));
    });

    test('a rollback carries the route, the prior revision, and the '
        'precondition', () async {
      Map<String, dynamic>? captured;
      final client = scriptedHttpClient([
        (request) {
          captured = jsonDecode(request.body) as Map<String, dynamic>;
          return json({'outcome': 'applied', 'revisionOrdinal': 9});
        },
      ]);

      final code =
          await makeRunner(
            stdout: StringBuffer(),
            stderr: StringBuffer(),
            httpClient: client,
          ).run([
            'routing',
            'rollback',
            'welcome',
            ...target(),
            '--type',
            'onboarding',
            '--route-id',
            'welcome-route',
            '--prior-revision-ordinal',
            '6',
            '--expected-revision-ordinal',
            '8',
          ]);

      expect(code, 0);
      expect(captured!['method'], 'rollbackRoute');
      expect(captured!['routeId'], 'welcome-route');
      expect(captured!['priorRevisionOrdinal'], 6);
      expect(captured!['expectedRevisionOrdinal'], 8);
    });
  });

  group('the retry identity', () {
    test('a generated operation id is a canonical version 4 UUID', () async {
      final path = await seedBytes('doc.bin', const [1]);
      Map<String, dynamic>? captured;
      final client = scriptedHttpClient([
        (request) {
          captured = jsonDecode(request.body) as Map<String, dynamic>;
          return json({'outcome': 'applied', 'revisionOrdinal': 1});
        },
      ]);

      final code =
          await makeRunner(
            stdout: StringBuffer(),
            stderr: StringBuffer(),
            httpClient: client,
          ).run([
            'routing',
            'publish',
            'welcome',
            ...target(),
            '--type',
            'onboarding',
            '--document',
            path,
            '--expect-no-revision',
          ]);

      expect(code, 0);
      expect(
        captured!['operationId'] as String,
        matches(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}'
          r'-[0-9a-f]{12}$',
        ),
      );
    });

    test('a supplied operation id is sent unchanged', () async {
      final path = await seedBytes('doc.bin', const [1]);
      const supplied = '3f2504e0-4f89-41d3-9a0c-0305e82c3301';
      Map<String, dynamic>? captured;
      final client = scriptedHttpClient([
        (request) {
          captured = jsonDecode(request.body) as Map<String, dynamic>;
          return json({'outcome': 'replayed', 'revisionOrdinal': 3});
        },
      ]);

      final out = StringBuffer();
      final code =
          await makeRunner(
            stdout: out,
            stderr: StringBuffer(),
            httpClient: client,
          ).run([
            'routing',
            'publish',
            'welcome',
            ...target(),
            '--type',
            'onboarding',
            '--document',
            path,
            '--expect-no-revision',
            '--operation-id',
            supplied,
          ]);

      expect(code, 0);
      expect(captured!['operationId'], supplied);
      expect(out.toString(), contains('replayed at revision 3'));
    });

    test('an operation id that is not a version 4 UUID is refused before '
        'any call', () async {
      final path = await seedBytes('doc.bin', const [1]);
      final err = StringBuffer();
      final code =
          await makeRunner(
            stdout: StringBuffer(),
            stderr: err,
            httpClient: scriptedHttpClient(const []),
          ).run([
            'routing',
            'publish',
            'welcome',
            ...target(),
            '--type',
            'onboarding',
            '--document',
            path,
            '--expect-no-revision',
            '--operation-id',
            'publish-1',
          ]);

      expect(code, 1);
      expect(err.toString(), contains('version 4 UUID'));
    });

    test('the generator does not repeat itself', () {
      final minted = {for (var i = 0; i < 200; i++) newOperationId()};
      expect(minted, hasLength(200));
      expect(minted.every(isCanonicalOperationId), isTrue);
    });
  });

  group('page cursors', () {
    test('a supplied cursor and page size reach the service', () async {
      Map<String, dynamic>? captured;
      final client = scriptedHttpClient([
        (request) {
          captured = jsonDecode(request.body) as Map<String, dynamic>;
          return json({
            'audiences': <dynamic>[],
            'lastPage': true,
            'nextCursor': null,
          });
        },
      ]);

      final code =
          await makeRunner(
            stdout: StringBuffer(),
            stderr: StringBuffer(),
            httpClient: client,
          ).run([
            'routing',
            'list-audiences',
            ...target(),
            '--page-size',
            '25',
            '--cursor',
            'opaque-cursor',
          ]);

      expect(code, 0);
      expect(captured!['method'], 'listAudiences');
      expect(captured!['pageSize'], 25);
      expect(captured!['cursor'], 'opaque-cursor');
    });

    test(
      '--all-pages follows the service cursor and accumulates rows',
      () async {
        final cursors = <Object?>[];
        final client = scriptedHttpClient([
          (request) {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            cursors.add(body['cursor']);
            return json({
              'audiences': [
                {
                  'authorityId': 'a1',
                  'revisionId': 'r1',
                  'revisionOrdinal': 1,
                  'label': 'Trial users in Sweden',
                },
              ],
              'lastPage': false,
              'nextCursor': 'page-2',
            });
          },
          (request) {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            cursors.add(body['cursor']);
            return json({
              'audiences': [
                {
                  'authorityId': 'a2',
                  'revisionId': 'r2',
                  'revisionOrdinal': 2,
                  'label': 'Returning readers',
                },
              ],
              'lastPage': true,
              'nextCursor': null,
            });
          },
        ]);

        final out = StringBuffer();
        final code =
            await makeRunner(
              stdout: out,
              stderr: StringBuffer(),
              httpClient: client,
            ).run([
              'routing',
              'list-audiences',
              ...target(),
              '--all-pages',
              '--json',
            ]);

        expect(code, 0);
        expect(cursors, [null, 'page-2']);
        final decoded = jsonDecode(out.toString()) as Map<String, dynamic>;
        expect(
          (decoded['audiences']! as List<dynamic>).map(
            (a) => (a! as Map<String, dynamic>)['revisionId'],
          ),
          ['r1', 'r2'],
        );
      },
    );

    test('an audience name and description reach the reader', () async {
      final client = scriptedHttpClient([
        (_) => json({
          'audiences': [
            {
              'authorityId': 'a1',
              'revisionId': 'r1',
              'revisionOrdinal': 1,
              'label': 'Trial users in Sweden',
              'description': 'Started a trial, has not converted.',
            },
          ],
          'lastPage': true,
          'nextCursor': null,
        }),
      ]);

      final out = StringBuffer();
      final code = await makeRunner(
        stdout: out,
        stderr: StringBuffer(),
        httpClient: client,
      ).run(['routing', 'list-audiences', ...target(), '--json']);

      expect(code, 0);
      final decoded = jsonDecode(out.toString()) as Map<String, dynamic>;
      final first =
          (decoded['audiences']! as List<dynamic>).single
              as Map<String, dynamic>;
      expect(first['label'], 'Trial users in Sweden');
      expect(first['description'], 'Started a trial, has not converted.');
    });

    test('an audience without a description still reads by its name', () async {
      final client = scriptedHttpClient([
        (_) => json({
          'audiences': [
            {
              'authorityId': 'a1',
              'revisionId': 'r1',
              'revisionOrdinal': 1,
              'label': 'Returning readers',
            },
          ],
          'lastPage': true,
          'nextCursor': null,
        }),
      ]);

      final out = StringBuffer();
      final code = await makeRunner(
        stdout: out,
        stderr: StringBuffer(),
        httpClient: client,
      ).run(['routing', 'list-audiences', ...target()]);

      expect(code, 0);
      expect(out.toString(), contains('Returning readers'));
    });
    test(
      'without --all-pages one page is read and the cursor is offered',
      () async {
        final client = scriptedHttpClient([
          (_) => json({
            'audiences': [
              {
                'authorityId': 'a1',
                'revisionId': 'r1',
                'revisionOrdinal': 1,
                'label': 'Trial users in Sweden',
              },
            ],
            'lastPage': false,
            'nextCursor': 'page-2',
          }),
        ]);

        final out = StringBuffer();
        final code = await makeRunner(
          stdout: out,
          stderr: StringBuffer(),
          httpClient: client,
        ).run(['routing', 'list-audiences', ...target()]);

        expect(code, 0);
        expect(out.toString(), contains('--cursor page-2'));
      },
    );

    test('audience usage pages both arms and reports the lifecycle', () async {
      Map<String, dynamic>? captured;
      final client = scriptedHttpClient([
        (request) {
          captured = jsonDecode(request.body) as Map<String, dynamic>;
          return json({
            'experiments': [
              {
                'ownerAuthorityKind': 'experimentDesign',
                'ownerAuthorityId': 'x1',
                'ownerRevisionId': 'xr1',
                'lifecycle': 'concluded',
              },
            ],
            'routing': [
              {
                'surfaceType': 'onboarding',
                'surfaceSlug': 'welcome',
                'contractVersion': null,
                'revisionOrdinal': 3,
                'routeIds': ['r1', 'r2'],
                'lifecycle': 'active',
              },
            ],
            'lastPage': true,
            'nextCursor': null,
          });
        },
      ]);

      final out = StringBuffer();
      final code =
          await makeRunner(
            stdout: out,
            stderr: StringBuffer(),
            httpClient: client,
          ).run([
            'routing',
            'audience-usage',
            ...target(),
            '--audience-revision-id',
            'aud-rev-1',
          ]);

      expect(code, 0);
      expect(captured!['audienceRevisionId'], 'aud-rev-1');
      expect(out.toString(), contains('experiment\texperimentDesign'));
      expect(out.toString(), contains('concluded'));
      expect(out.toString(), contains('routing\tonboarding welcome'));
      expect(out.toString(), contains('r1,r2'));
    });
  });

  group('refusals', () {
    test('a conflict is reported with both ordinals and no retry', () async {
      final path = await seedBytes('doc.bin', const [1]);
      var calls = 0;
      final client = scriptedHttpClient([
        (_) {
          calls++;
          return conflict(expected: 4, actual: 6);
        },
      ]);

      final err = StringBuffer();
      final code =
          await makeRunner(
            stdout: StringBuffer(),
            stderr: err,
            httpClient: client,
          ).run([
            'routing',
            'publish',
            'welcome',
            ...target(),
            '--type',
            'onboarding',
            '--document',
            path,
            '--expected-revision-ordinal',
            '4',
          ]);

      expect(code, 1);
      expect(calls, 1);
      expect(err.toString(), contains('expected 4'));
      expect(err.toString(), contains('stored revision is 6'));
    });

    test('a first-publish conflict names both sides in words', () async {
      final path = await seedBytes('doc.bin', const [1]);
      final client = scriptedHttpClient([(_) => conflict(actual: 2)]);

      final err = StringBuffer();
      final code =
          await makeRunner(
            stdout: StringBuffer(),
            stderr: err,
            httpClient: client,
          ).run([
            'routing',
            'publish',
            'welcome',
            ...target(),
            '--type',
            'onboarding',
            '--document',
            path,
            '--expect-no-revision',
          ]);

      expect(code, 1);
      expect(err.toString(), contains('expected no revision'));
      expect(err.toString(), contains('stored revision is 2'));
    });

    test('a service refusal is surfaced in the service term', () async {
      final path = await seedBytes('doc.bin', const [1]);
      final client = scriptedHttpClient([(_) => refusal('invalid_document')]);

      final err = StringBuffer();
      final code =
          await makeRunner(
            stdout: StringBuffer(),
            stderr: err,
            httpClient: client,
          ).run([
            'routing',
            'publish',
            'welcome',
            ...target(),
            '--type',
            'onboarding',
            '--document',
            path,
            '--expect-no-revision',
          ]);

      expect(code, 1);
      expect(err.toString(), contains('invalid_document'));
    });

    test('an identity the service will not admit to operator configuration '
        'is refused, and the refusal is final', () async {
      // Operator authorization is the service's decision. The client makes
      // one call, reports what it is told, and neither falls back nor retries.
      var calls = 0;
      final client = scriptedHttpClient([
        (_) {
          calls++;
          return unauthorized();
        },
      ]);

      final err = StringBuffer();
      final out = StringBuffer();
      final code =
          await makeRunner(stdout: out, stderr: err, httpClient: client).run([
            'routing',
            'read',
            'welcome',
            ...target(),
            '--type',
            'onboarding',
          ]);

      expect(code, 1);
      expect(calls, 1);
      expect(
        err.toString(),
        contains('Your role in this organization does not allow this'),
      );
      expect(out.toString(), isEmpty);
    });

    test('a refused mutation makes exactly one call', () async {
      final path = await seedBytes('doc.bin', const [1]);
      var calls = 0;
      final client = scriptedHttpClient([
        (_) {
          calls++;
          return unauthorized();
        },
      ]);

      final code =
          await makeRunner(
            stdout: StringBuffer(),
            stderr: StringBuffer(),
            httpClient: client,
          ).run([
            'routing',
            'publish',
            'welcome',
            ...target(),
            '--type',
            'onboarding',
            '--document',
            path,
            '--expect-no-revision',
          ]);

      expect(code, 1);
      expect(calls, 1);
    });

    test('a missing document file is refused before any call', () async {
      final err = StringBuffer();
      final code =
          await makeRunner(
            stdout: StringBuffer(),
            stderr: err,
            httpClient: scriptedHttpClient(const []),
          ).run([
            'routing',
            'publish',
            'welcome',
            ...target(),
            '--type',
            'onboarding',
            '--document',
            p.join(tempDir.path, 'absent.bin'),
            '--expect-no-revision',
          ]);

      expect(code, 1);
      expect(err.toString(), contains('No file at'));
    });

    test('an empty document is refused before any call', () async {
      final path = await seedBytes('empty.bin', const []);
      final err = StringBuffer();
      final code =
          await makeRunner(
            stdout: StringBuffer(),
            stderr: err,
            httpClient: scriptedHttpClient(const []),
          ).run([
            'routing',
            'publish',
            'welcome',
            ...target(),
            '--type',
            'onboarding',
            '--document',
            path,
            '--expect-no-revision',
          ]);

      expect(code, 1);
      expect(err.toString(), contains('between 1 and'));
    });

    test('a surface type outside the accepted set is refused before any '
        'call', () async {
      final err = StringBuffer();
      final code = await makeRunner(
        stdout: StringBuffer(),
        stderr: err,
        httpClient: scriptedHttpClient(const []),
      ).run(['routing', 'read', 'welcome', ...target(), '--type', 'banner']);

      expect(code, 1);
      expect(err.toString(), contains('Invalid --type "banner"'));
    });

    test('a missing surface slug is refused before any call', () async {
      final err = StringBuffer();
      final code = await makeRunner(
        stdout: StringBuffer(),
        stderr: err,
        httpClient: scriptedHttpClient(const []),
      ).run(['routing', 'read', ...target(), '--type', 'onboarding']);

      expect(code, 1);
      expect(err.toString(), contains('Missing positional argument'));
    });
  });

  group('the empty target', () {
    test(
      'a target with no document reports it and names the first publish',
      () async {
        final client = scriptedHttpClient([
          (_) => json({
            'empty': true,
            'documentBytes': null,
            'revisionOrdinal': null,
          }),
        ]);

        final out = StringBuffer();
        final code =
            await makeRunner(
              stdout: out,
              stderr: StringBuffer(),
              httpClient: client,
            ).run([
              'routing',
              'read',
              'welcome',
              ...target(),
              '--type',
              'onboarding',
            ]);

        expect(code, 0);
        expect(out.toString(), contains('No routing document'));
        expect(out.toString(), contains('--expect-no-revision'));
      },
    );

    test('an empty audience list says so', () async {
      final client = scriptedHttpClient([
        (_) => json({
          'audiences': <dynamic>[],
          'lastPage': true,
          'nextCursor': null,
        }),
      ]);

      final out = StringBuffer();
      final code = await makeRunner(
        stdout: out,
        stderr: StringBuffer(),
        httpClient: client,
      ).run(['routing', 'list-audiences', ...target()]);

      expect(code, 0);
      expect(out.toString(), contains('No audiences at this target.'));
    });
  });

  group('reading one earlier revision', () {
    test('the read carries the complete target and the ordinal, and the '
        'environment is the exact target id', () async {
      Map<String, dynamic>? captured;
      Uri? seenUrl;
      final client = scriptedHttpClient([
        (request) {
          seenUrl = request.url;
          captured = jsonDecode(request.body) as Map<String, dynamic>;
          return json({
            'revisionOrdinal': 4,
            'documentBytes': wire(const [1, 2, 3]),
            'publishedAtMicros': 1757505600000000,
          });
        },
      ]);

      final code =
          await makeRunner(
            stdout: StringBuffer(),
            stderr: StringBuffer(),
            httpClient: client,
          ).run([
            'routing',
            'read-revision',
            'welcome',
            ...target(),
            '--type',
            'onboarding',
            '--revision-ordinal',
            '4',
            '--contract-version',
            '3',
          ]);

      expect(code, 0);
      expect(seenUrl!.path, endsWith('/surfaceRouting'));
      expect(captured!['method'], 'readRoutingRevision');
      expect(captured!['projectSlug'], 'p');
      expect(captured!['appSlug'], 'a');
      expect(captured!['surfaceType'], 'onboarding');
      expect(captured!['surfaceSlug'], 'welcome');
      expect(captured!['revisionOrdinal'], 4);
      expect(captured!['contractVersion'], 3);
      expect(captured!['organizationId'], 7);
      expect(captured!['environmentId'], 12);
    });

    test('the stored bytes are written back out unchanged, and the reader is '
        'told when the revision was published', () async {
      final stored = Uint8List.fromList(List<int>.generate(48, (i) => i * 2));
      final out = p.join(tempDir.path, 'prior.bin');
      final client = scriptedHttpClient([
        (_) => json({
          'revisionOrdinal': 6,
          'documentBytes': wire(stored),
          'publishedAtMicros': 1757505600000000,
        }),
      ]);

      final printed = StringBuffer();
      final code =
          await makeRunner(
            stdout: printed,
            stderr: StringBuffer(),
            httpClient: client,
          ).run([
            'routing',
            'read-revision',
            'welcome',
            ...target(),
            '--type',
            'onboarding',
            '--revision-ordinal',
            '6',
            '--out',
            out,
          ]);

      expect(code, 0);
      expect(File(out).readAsBytesSync(), stored);
      expect(printed.toString(), contains('Revision 6, 48 bytes'));
      expect(printed.toString(), contains('2025-09-10T12:00:00.000Z'));
    });

    test('the JSON result carries the document, the ordinal and the '
        'publication time', () async {
      final client = scriptedHttpClient([
        (_) => json({
          'revisionOrdinal': 2,
          'documentBytes': wire(const [7, 8]),
          'publishedAtMicros': 1757505600000000,
        }),
      ]);

      final printed = StringBuffer();
      final code =
          await makeRunner(
            stdout: printed,
            stderr: StringBuffer(),
            httpClient: client,
          ).run([
            'routing',
            'read-revision',
            'welcome',
            ...target(),
            '--type',
            'onboarding',
            '--revision-ordinal',
            '2',
            '--json',
          ]);

      expect(code, 0);
      final decoded = jsonDecode(printed.toString()) as Map<String, dynamic>;
      expect(decoded['revisionOrdinal'], 2);
      expect(decoded['documentBase64'], base64Encode(const [7, 8]));
      expect(decoded['publishedAtMicros'], 1757505600000000);
    });

    test('an ordinal below one is refused before any call', () async {
      final err = StringBuffer();
      final code =
          await makeRunner(
            stdout: StringBuffer(),
            stderr: err,
            httpClient: scriptedHttpClient(const []),
          ).run([
            'routing',
            'read-revision',
            'welcome',
            ...target(),
            '--type',
            'onboarding',
            '--revision-ordinal',
            '0',
          ]);

      expect(code, 1);
      expect(err.toString(), contains('--revision-ordinal'));
    });

    test('an ordinal the target never published is surfaced in the '
        "service's own term", () async {
      final client = scriptedHttpClient([(_) => refusal('revision_not_found')]);

      final err = StringBuffer();
      final code =
          await makeRunner(
            stdout: StringBuffer(),
            stderr: err,
            httpClient: client,
          ).run([
            'routing',
            'read-revision',
            'welcome',
            ...target(),
            '--type',
            'onboarding',
            '--revision-ordinal',
            '99',
          ]);

      expect(code, 1);
      expect(err.toString(), contains('revision_not_found'));
    });
  });

  group('delivery diagnostics', () {
    test('carries the complete target and a whole UTC window, then preserves '
        'both observed populations in human output', () async {
      Map<String, dynamic>? captured;
      Uri? seenUrl;
      final read = diagnosticsRead();
      final printed = StringBuffer();
      final client = scriptedHttpClient([
        (request) {
          seenUrl = request.url;
          captured = jsonDecode(request.body) as Map<String, dynamic>;
          return byteData(read.canonicalBytes);
        },
      ]);

      final code =
          await makeRunner(
            stdout: printed,
            stderr: StringBuffer(),
            httpClient: client,
          ).run([
            'routing',
            'delivery-diagnostics',
            'welcome',
            ...target(),
            '--type',
            'onboarding',
            '--contract-version',
            '3',
            '--start-date',
            '2026-09-01',
            '--end-date-exclusive',
            '2026-09-03',
          ]);

      expect(code, 0);
      expect(seenUrl!.path, endsWith('/surfaceRouting'));
      expect(captured!['method'], 'readDeliveryDiagnostics');
      expect(captured!['projectSlug'], 'p');
      expect(captured!['appSlug'], 'a');
      expect(captured!['surfaceType'], 'onboarding');
      expect(captured!['surfaceSlug'], 'welcome');
      expect(captured!['environmentId'], 12);
      expect(captured!['organizationId'], 7);
      expect(captured!['contractVersion'], 3);
      expect(
        captured!['windowStartDayUtc'],
        DateTime.utc(2026, 9, 1).microsecondsSinceEpoch,
      );
      expect(
        captured!['windowEndDayExclusiveUtc'],
        DateTime.utc(2026, 9, 3).microsecondsSinceEpoch,
      );
      expect(
        printed.toString(),
        contains('UTC window: 2026-09-01 through 2026-09-03 (end exclusive).'),
      );
      expect(
        printed.toString(),
        contains(
          'Served default presentations (servedDefaultPresentations; '
          'observedAdmittedPresentations; partiallyHeld).',
        ),
      );
      expect(printed.toString(), contains('frozen: 5'));
      expect(printed.toString(), contains('futureDefault: <5'));
      expect(
        printed.toString(),
        contains(
          'Recorded server refusals (recordedServerRefusals; '
          'observedRecordedServerRefusals; held).',
        ),
      );
      expect(printed.toString(), contains('audienceUndecided: <5'));
      expect(printed.toString(), contains('not a census of all requests'));
    });

    test(
      'prints the shared canonical DTO JSON without turning held into zero',
      () async {
        final read = diagnosticsRead();
        final printed = StringBuffer();
        final code =
            await makeRunner(
              stdout: printed,
              stderr: StringBuffer(),
              httpClient: scriptedHttpClient([
                (_) => byteData(read.canonicalBytes),
              ]),
            ).run([
              'routing',
              'delivery-diagnostics',
              'welcome',
              ...target(),
              '--type',
              'onboarding',
              '--contract-version',
              '3',
              '--start-date',
              '2026-09-01',
              '--end-date-exclusive',
              '2026-09-03',
              '--json',
            ]);

        expect(code, 0);
        final output = jsonDecode(printed.toString()) as Map<String, dynamic>;
        expect(output, read.toJson());
        final served = output['servedDefaults']! as Map<String, dynamic>;
        final refusals = output['recordedRefusals']! as Map<String, dynamic>;
        expect(served['population'], 'servedDefaultPresentations');
        expect(refusals['population'], 'recordedServerRefusals');
        expect((served['reasons']! as List).first, {
          'reason': 'frozen',
          'observedCount': 5,
        });
        expect((served['reasons']! as List).last, {'reason': 'futureDefault'});
        expect(refusals['reasons'], [
          {'reason': 'audienceUndecided'},
        ]);
      },
    );

    test('renders unavailable and observed-empty disclosed sections without '
        'manufacturing a zero', () async {
      final read = diagnosticsRead(
        servedDefaults: MeasurementDeliveryDiagnosticsSectionV1(
          population: MeasurementDeliveryDiagnosticsPopulationV1
              .servedDefaultPresentations,
          coverage: MeasurementDeliveryDiagnosticsCoverageV1
              .observedAdmittedPresentations,
          availability:
              MeasurementDeliveryDiagnosticsAvailabilityV1.unavailable,
          reasons: const [],
        ),
        recordedRefusals: MeasurementDeliveryDiagnosticsSectionV1(
          population:
              MeasurementDeliveryDiagnosticsPopulationV1.recordedServerRefusals,
          coverage: MeasurementDeliveryDiagnosticsCoverageV1
              .observedRecordedServerRefusals,
          availability: MeasurementDeliveryDiagnosticsAvailabilityV1.disclosed,
          reasons: const [],
        ),
      );
      final printed = StringBuffer();
      final code =
          await makeRunner(
            stdout: printed,
            stderr: StringBuffer(),
            httpClient: scriptedHttpClient([
              (_) => byteData(read.canonicalBytes),
            ]),
          ).run([
            'routing',
            'delivery-diagnostics',
            'welcome',
            ...target(),
            '--type',
            'onboarding',
            '--contract-version',
            '3',
            '--start-date',
            '2026-09-01',
            '--end-date-exclusive',
            '2026-09-03',
          ]);

      expect(code, 0);
      expect(
        printed.toString(),
        contains('State: unavailable; no retained observation is available'),
      );
      expect(printed.toString(), contains('State: disclosed; every named'));
      expect(
        printed.toString(),
        contains(
          'No observed reasons are present in this disclosed population',
        ),
      );
      expect(printed.toString(), isNot(contains(': 0')));
    });

    test(
      'propagates an authorization refusal from the authorized read',
      () async {
        final error = StringBuffer();
        final code =
            await makeRunner(
              stdout: StringBuffer(),
              stderr: error,
              httpClient: scriptedHttpClient([(_) => unauthorized()]),
            ).run([
              'routing',
              'delivery-diagnostics',
              'welcome',
              ...target(),
              '--type',
              'onboarding',
              '--start-date',
              '2026-09-01',
              '--end-date-exclusive',
              '2026-09-03',
            ]);

        expect(code, 1);
        expect(
          error.toString(),
          contains('Your role in this organization does not allow this'),
        );
      },
    );

    test(
      'refuses absent, invalid, and over-retention windows before a read',
      () async {
        var calls = 0;
        final client = scriptedHttpClient([
          (_) {
            calls++;
            return json({});
          },
        ]);

        final missingStart =
            await makeRunner(
              stdout: StringBuffer(),
              stderr: StringBuffer(),
              httpClient: client,
            ).run([
              'routing',
              'delivery-diagnostics',
              'welcome',
              ...target(),
              '--type',
              'onboarding',
              '--end-date-exclusive',
              '2026-09-03',
            ]);
        final invalidDate =
            await makeRunner(
              stdout: StringBuffer(),
              stderr: StringBuffer(),
              httpClient: client,
            ).run([
              'routing',
              'delivery-diagnostics',
              'welcome',
              ...target(),
              '--type',
              'onboarding',
              '--start-date',
              '2026-02-30',
              '--end-date-exclusive',
              '2026-03-02',
            ]);
        final nonExactDate =
            await makeRunner(
              stdout: StringBuffer(),
              stderr: StringBuffer(),
              httpClient: client,
            ).run([
              'routing',
              'delivery-diagnostics',
              'welcome',
              ...target(),
              '--type',
              'onboarding',
              '--start-date',
              '2026-09-01\n',
              '--end-date-exclusive',
              '2026-09-03',
            ]);
        final tooLong =
            await makeRunner(
              stdout: StringBuffer(),
              stderr: StringBuffer(),
              httpClient: client,
            ).run([
              'routing',
              'delivery-diagnostics',
              'welcome',
              ...target(),
              '--type',
              'onboarding',
              '--start-date',
              '2026-01-01',
              '--end-date-exclusive',
              '2026-04-02',
            ]);

        expect(missingStart, 1);
        expect(invalidDate, 1);
        expect(nonExactDate, 1);
        expect(tooLong, 1);
        expect(calls, 0);
      },
    );

    test('rejects a noncanonical diagnostics response', () async {
      final noncanonical = utf8.encode(
        ' ${utf8.decode(diagnosticsRead().canonicalBytes)}',
      );
      final error = StringBuffer();
      final code =
          await makeRunner(
            stdout: StringBuffer(),
            stderr: error,
            httpClient: scriptedHttpClient([(_) => byteData(noncanonical)]),
          ).run([
            'routing',
            'delivery-diagnostics',
            'welcome',
            ...target(),
            '--type',
            'onboarding',
            '--start-date',
            '2026-09-01',
            '--end-date-exclusive',
            '2026-09-03',
          ]);

      expect(code, 2);
      expect(error.toString(), contains('invalid result'));
    });
  });

  group('delivery flow', () {
    test('carries the target and window, states a held cell as <5, and rounds '
        'the total that holds it', () async {
      Map<String, dynamic>? captured;
      final printed = StringBuffer();
      final start = DateTime.utc(2026, 9, 1).microsecondsSinceEpoch;
      final end = DateTime.utc(2026, 9, 3).microsecondsSinceEpoch;
      final client = scriptedHttpClient([
        (request) {
          captured = jsonDecode(request.body) as Map<String, dynamic>;
          return json({
            'windowStartDayUtc': start,
            'windowEndDayExclusiveUtc': end,
            'cells': [
              {
                'source': 'rule',
                'routeId': 'trial',
                'version': 5,
                'views': 186,
              },
              {'source': 'rule', 'routeId': 'beta', 'version': 5},
              {
                'source': 'experiment',
                'experimentId': 'exp-1',
                'experimentLabel': 'Welcome headline',
                'experimentRunning': true,
                'version': 3,
                'views': 900,
              },
              {
                'source': 'experiment',
                'experimentId': 'exp-2',
                'experimentRunning': true,
                'version': 3,
                'views': 50,
              },
              {
                'source': 'experiment',
                'experimentId': 'exp-old',
                'experimentLabel': 'Offer layout',
                'experimentRunning': false,
                'version': 2,
                'views': 30,
              },
              {'source': 'everyoneElse', 'version': 4, 'views': 8604},
              {'source': 'notRecorded', 'version': 4, 'views': 12},
            ],
          });
        },
      ]);

      final code =
          await makeRunner(
            stdout: printed,
            stderr: StringBuffer(),
            httpClient: client,
          ).run([
            'routing',
            'delivery-flow',
            'welcome',
            ...target(),
            '--type',
            'onboarding',
            '--start-date',
            '2026-09-01',
            '--end-date-exclusive',
            '2026-09-03',
          ]);

      expect(code, 0);
      expect(captured!['method'], 'readDeliveryFlow');
      expect(captured!['surfaceSlug'], 'welcome');
      expect(captured!['environmentId'], 12);
      expect(captured!['organizationId'], 7);
      expect(captured!['windowStartDayUtc'], start);
      expect(captured!['windowEndDayExclusiveUtc'], end);
      final output = printed.toString();
      expect(output, contains('Rule trial, v5: 186'));
      expect(output, contains('Rule beta, v5: <5'));
      expect(output, contains('Experiment Welcome headline, v3: 900'));
      expect(output, contains('\nUnnamed experiment, v3: 50'));
      expect(output, contains('Earlier experiments, v2: 30'));
      expect(output, contains('Everyone else, v4: 8,604'));
      // 9,782 stated beside one held cell: 9,784, to the nearest 100.
      expect(output, contains('≈9,800 views, 12 not recorded'));
      expect(output, isNot(contains('Not recorded, v4')));
      expect(output, isNot(contains('exp-2')));
    });

    test('states the total with any views not recorded', () async {
      Future<String> totalOf(List<Map<String, Object?>> cells) async {
        final printed = StringBuffer();
        final client = scriptedHttpClient([
          (_) => json({
            'windowStartDayUtc': DateTime.utc(
              2026,
              9,
              1,
            ).microsecondsSinceEpoch,
            'windowEndDayExclusiveUtc': DateTime.utc(
              2026,
              9,
              3,
            ).microsecondsSinceEpoch,
            'cells': cells,
          }),
        ]);
        final code =
            await makeRunner(
              stdout: printed,
              stderr: StringBuffer(),
              httpClient: client,
            ).run([
              'routing',
              'delivery-flow',
              'welcome',
              ...target(),
              '--type',
              'onboarding',
              '--start-date',
              '2026-09-01',
              '--end-date-exclusive',
              '2026-09-03',
            ]);
        expect(code, 0);
        return printed.toString().trim().split('\n').last;
      }

      expect(
        await totalOf([
          {'source': 'everyoneElse', 'version': 4, 'views': 13023},
          {'source': 'notRecorded', 'version': 4, 'views': 12},
        ]),
        '13,035 views, 12 not recorded',
      );
      expect(
        await totalOf([
          {'source': 'everyoneElse', 'version': 4, 'views': 13035},
        ]),
        '13,035 views',
      );
      expect(
        await totalOf([
          {'source': 'rule', 'routeId': 'beta', 'version': 5},
          {'source': 'everyoneElse', 'version': 4, 'views': 13035},
        ]),
        '≈13,000 views',
      );
      expect(
        await totalOf([
          {'source': 'rule', 'routeId': 'beta', 'version': 5},
        ]),
        '<5 views',
      );
      expect(
        await totalOf([
          {'source': 'everyoneElse', 'version': 4, 'views': 13023},
          {'source': 'notRecorded', 'version': 4},
        ]),
        '≈13,000 views, <5 not recorded',
      );
      expect(await totalOf([]), 'No views in this period.');
    });

    test('refuses a response that names another window', () async {
      final client = scriptedHttpClient([
        (_) => json({
          'windowStartDayUtc': 1,
          'windowEndDayExclusiveUtc': 2,
          'cells': <Object?>[],
        }),
      ]);
      final code =
          await makeRunner(
            stdout: StringBuffer(),
            stderr: StringBuffer(),
            httpClient: client,
          ).run([
            'routing',
            'delivery-flow',
            'welcome',
            ...target(),
            '--type',
            'onboarding',
            '--start-date',
            '2026-09-01',
            '--end-date-exclusive',
            '2026-09-03',
          ]);
      expect(code, isNot(0));
    });
  });

  group('the command surface', () {
    test('routing --help lists every operation', () async {
      final out = StringBuffer();
      final runner = makeRunner(
        stdout: out,
        stderr: StringBuffer(),
        httpClient: scriptedHttpClient(const []),
      );
      final buffer = StringBuffer(runner.commands['routing']!.usage);
      for (final name in const [
        'list-audiences',
        'audience-usage',
        'read',
        'delivery-diagnostics',
        'delivery-flow',
        'read-revision',
        'preview',
        'publish',
        'rollback',
      ]) {
        expect(buffer.toString(), contains(name));
      }
    });

    test(
      'no operation offers a way to author a document or an audience',
      () async {
        final runner = makeRunner(
          stdout: StringBuffer(),
          stderr: StringBuffer(),
          httpClient: scriptedHttpClient(const []),
        );
        final routing = runner.commands['routing']!;
        expect(routing.subcommands.keys, isNot(contains('save-audience')));
        for (final sub in routing.subcommands.values) {
          expect(sub.argParser.options.keys, isNot(contains('rule')));
          expect(sub.argParser.options.keys, isNot(contains('audience-name')));
        }
      },
    );
  });

  // The service is the only decoder of a routing document. A response that is
  // not the documented shape is a service fault, not an operator mistake.
  test('a malformed service response exits 2', () async {
    final client = scriptedHttpClient([
      (_) => jsonList(const ['not', 'an', 'object']),
    ]);

    final err = StringBuffer();
    final code = await makeRunner(
      stdout: StringBuffer(),
      stderr: err,
      httpClient: client,
    ).run(['routing', 'read', 'welcome', ...target(), '--type', 'onboarding']);

    expect(code, 2);
    expect(err.toString(), contains('invalid result'));
  });
}
