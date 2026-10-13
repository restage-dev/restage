import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:restage_cli/api.dart';
import 'package:restage_cli/restage_cli.dart';
import 'package:restage_cli/src/tui/console_command_executor.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    hide RuntimePlane;
import 'package:test/test.dart';

import '../_helpers/test_fixtures.dart';
import 'delivery_command_test.dart'
    show surfaceScope, policyReview, warningImpact;
import 'delivery_sample_command_test.dart' show operationId;

DeliveryPolicyReviewV1 routingReview({bool live = false, bool warned = true}) {
  final scope = surfaceScope(live: live);
  return policyReview(
    scope,
    expectedHeadOrdinal: 4,
    impact: warned ? warningImpact(scope) : null,
  );
}

DeliveryPolicyScopeV1 anotherAppScope(DeliveryPolicyScopeV1 scope) {
  final json = scope.toJson();
  ((json['root'] as Map)['surface'] as Map)['target']['appId'] = 99;
  return DeliveryPolicyScopeV1.fromJson(json);
}

class RoutingReviewHarness {
  RoutingReviewHarness._(this.directory, this.store);
  static Future<RoutingReviewHarness> create() async {
    final directory = await Directory.systemTemp.createTemp('routing-review-');
    final store = FileCredentialStore('${directory.path}/credentials');
    await seedCredential(store);
    return RoutingReviewHarness._(directory, store);
  }

  final Directory directory;
  final FileCredentialStore store;
  final stdout = StringBuffer();
  final stderr = StringBuffer();
  final calls = <Map<String, dynamic>>[];
  DeliveryPolicyReviewV1 review = routingReview();
  String? refusal;
  bool invalidReview = false;
  List<int> stored = CanonicalJsonCodec.encode({
    'originalDocuments': ['both branches', 'future snapshot'],
    'timeline': [null, '2027-01-04T09:30:00'],
  });

  http.Client client() => mockHttpClient((request) {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    calls.add(body);
    if (refusal != null) {
      return typedErrorResponse('SurfaceRoutingRejectedException', {
        'reason': refusal,
      });
    }
    switch (body['method']) {
      case 'readRouting':
        return http.Response(
          jsonEncode({
            'empty': false,
            'revisionOrdinal': 4,
            'documentBytes': encodeByteDataWire(stored),
          }),
          200,
        );
      case 'readRoutingRevision':
        return http.Response(
          jsonEncode({
            'revisionOrdinal': body['revisionOrdinal'],
            'publishedAtMicros': 100,
            'documentBytes': encodeByteDataWire(stored),
          }),
          200,
        );
      case 'reviewRouting':
      case 'reviewRouteRollback':
        return http.Response(
          jsonEncode(
            encodeByteDataWire(invalidReview ? [1] : review.canonicalBytes),
          ),
          200,
        );
      case 'previewRouting':
        final simulation = DeliveryPolicySimulationV1(
          scope: review.scope,
          reason: 'identityUnavailable',
          routeId: 'original-route',
        );
        return http.Response(
          jsonEncode({
            'rules': [
              {
                'routeId': 'original-route',
                'matches': true,
                'reason': 'matched',
              },
            ],
            'usesActivePointer': false,
            'deliveryBytes': encodeByteDataWire(simulation.canonicalBytes),
          }),
          200,
        );
      case 'publishRouting':
      case 'rollbackRoute':
        return http.Response(
          jsonEncode({'outcome': 'applied', 'revisionOrdinal': 5}),
          200,
        );
      default:
        fail('Unexpected routing call ${body['method']}');
    }
  });

  Future<String> file(String name, List<int> bytes) async {
    final path = '${directory.path}/$name';
    await File(path).writeAsBytes(bytes);
    return path;
  }

  List<String> arguments(
    String command,
    List<String> flags, {
    bool live = false,
  }) => [
    '--yes',
    'surface',
    'routing',
    command,
    'welcome',
    '--type',
    'onboarding',
    '--project',
    'demo',
    '--app',
    'a',
    '--env',
    live ? 'production' : 'staging',
    '--plane',
    live ? 'live' : 'sandbox',
    '--contract-version',
    '2',
    ...flags,
  ];

  Future<int> run(String command, List<String> flags, {bool live = false}) {
    calls.clear();
    stdout.clear();
    stderr.clear();
    return RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
      httpClient: client(),
    ).run(arguments(command, flags, live: live));
  }

  List<Map<String, dynamic>> get writes => calls
      .where(
        (call) =>
            const {'publishRouting', 'rollbackRoute'}.contains(call['method']),
      )
      .toList();
}

void main() {
  late RoutingReviewHarness h;
  setUp(() async => h = await RoutingReviewHarness.create());
  tearDown(() => h.directory.delete(recursive: true));

  test(
    'registered review retains the complete current candidate and original server review',
    () async {
      final request = DeliveryPolicyReviewRequestV1(
        scope: h.review.scope,
        expectedHeadOrdinal: h.review.expectedHeadOrdinal,
        candidatePlan: h.review.candidatePlan,
        reason: h.review.reason,
      );
      final path = await h.file('request.json', request.canonicalBytes);
      final out = '${h.directory.path}/review.json';
      expect(await h.run('review', ['--request', path, '--out', out]), 0);
      expect(h.calls.single['method'], 'reviewRouting');
      expect(
        decodeByteDataWire(
          h.calls.single['requestBytes'],
          maximumBytes: kMaximumRoutingRequestBytes,
          malformed: (detail) => FormatException(detail),
        ),
        request.canonicalBytes,
      );
      expect(h.calls.single, containsPair('environmentId', 12));
      expect(File(out).readAsBytesSync(), h.review.canonicalBytes);
      expect(h.stdout.toString(), contains('Welcome experiment'));
      expect(h.stdout.toString(), contains('2027-01-04T09:30:00'));
      expect(h.writes, isEmpty);
    },
  );

  test(
    'publish requires separate exact warning approval and carries only the original reviewed reference',
    () async {
      final path = await h.file('review.json', h.review.canonicalBytes);
      final foreign = policyReview(
        anotherAppScope(h.review.scope),
        expectedHeadOrdinal: 4,
      );
      final foreignPath = await h.file('foreign.json', foreign.canonicalBytes);
      expect(await h.run('publish', ['--review', foreignPath]), 1);
      expect(h.calls, isEmpty);
      expect(
        await h.run('publish', [
          '--review',
          path,
          '--operation-id',
          operationId,
        ]),
        1,
      );
      expect(h.writes, isEmpty);
      expect(h.stdout.toString(), contains('Completed welcome'));
      expect(h.stderr.toString(), contains(h.review.digest.hex));
      expect(
        await h.run('publish', [
          '--review',
          path,
          '--reviewed-digest',
          '0' * 64,
        ]),
        1,
      );
      expect(h.calls, isEmpty);
      expect(
        await h.run('publish', [
          '--review',
          path,
          '--reviewed-digest',
          h.review.digest.hex,
          '--operation-id',
          operationId,
        ]),
        0,
      );
      final wire = h.writes.single;
      final request = DeliveryPolicyPublishRequestV1.fromCanonicalBytes(
        decodeByteDataWire(
          wire['documentBytes'],
          maximumBytes: kMaximumRoutingRequestBytes,
          malformed: (detail) => FormatException(detail),
        ),
      );
      expect(request.reviewRef, h.review.reviewRef);
      expect(request.operationId, operationId);
      expect(
        request.measurementAcknowledgement!.acknowledges(
          h.review.measurementImpact,
        ),
        isTrue,
      );
      expect(wire['expectedRevisionOrdinal'], 4);
      expect(wire['operationId'], operationId);
      expect(request.toJson().containsKey('candidatePlan'), isFalse);
      h.refusal = 'review_stale';
      expect(
        await h.run('publish', [
          '--review',
          path,
          '--reviewed-digest',
          h.review.digest.hex,
          '--operation-id',
          operationId,
        ]),
        1,
      );
      expect(h.stderr.toString(), contains('review_stale'));
      expect(h.writes, hasLength(1));
    },
  );

  test(
    'route rollback reviews only the selected original route before exact acknowledged publish',
    () async {
      const flags = [
        '--route-id',
        'original-route',
        '--prior-revision-ordinal',
        '2',
        '--expected-revision-ordinal',
        '4',
      ];
      expect(await h.run('rollback', flags), 1);
      expect(h.calls.single['method'], 'reviewRouteRollback');
      expect(h.writes, isEmpty);
      expect(
        await h.run('rollback', [
          ...flags,
          '--reviewed-digest',
          h.review.digest.hex,
          '--operation-id',
          operationId,
        ]),
        0,
      );
      expect(h.calls.map((call) => call['method']), [
        'reviewRouteRollback',
        'rollbackRoute',
      ]);
      for (final call in h.calls) {
        expect(call['routeId'], 'original-route');
        expect(call['priorRevisionOrdinal'], 2);
        expect(call['expectedRevisionOrdinal'], 4);
        expect(call['contractVersion'], 2);
        expect(call['environmentId'], 12);
        expect(call['organizationId'], 7);
      }
      final publish = DeliveryPolicyPublishRequestV1.fromCanonicalBytes(
        decodeByteDataWire(
          h.writes.single['reviewedPublishRequestBytes'],
          maximumBytes: kMaximumRoutingRequestBytes,
          malformed: (detail) => FormatException(detail),
        ),
      );
      expect(publish.reviewRef, h.review.reviewRef);
      expect(
        publish.measurementAcknowledgement!.acknowledges(
          h.review.measurementImpact,
        ),
        isTrue,
      );
      final out = '${h.directory.path}/route-review.json';
      expect(await h.run('review-rollback', [...flags, '--out', out]), 0);
      expect(File(out).readAsBytesSync(), h.review.canonicalBytes);
      expect(h.writes, isEmpty);
      h.refusal = 'use_whole_policy_review';
      expect(
        await h.run('rollback', [
          ...flags,
          '--reviewed-digest',
          h.review.digest.hex,
        ]),
        1,
      );
      expect(h.calls.single['method'], 'reviewRouteRollback');
      expect(h.stderr.toString(), contains('use_whole_policy_review'));
    },
  );

  test(
    'preview sends only the current simulation request and preserves original evidence',
    () async {
      final request = DeliveryPolicySimulationRequestV1(
        scope: h.review.scope,
        inputs: DeliverySimulationInputsV1(
          localNow: LocalCivilDateTimeV1.parse('2027-01-04T09:30:00'),
          analyticsAnonymousId: 'known-visitor',
        ),
      );
      final path = await h.file('simulation.json', request.canonicalBytes);
      expect(await h.run('preview', ['--document', path, '--json']), 0);
      final call = h.calls.single;
      expect(
        decodeByteDataWire(
          call['documentBytes'],
          maximumBytes: kMaximumRoutingRequestBytes,
          malformed: (detail) => FormatException(detail),
        ),
        request.canonicalBytes,
      );
      expect(call['schemaBytes'], isNull);
      expect(call['requestContextBytes'], isNull);
      expect(call['sdkBuiltInsBytes'], isNull);
      expect(call['audienceBytes'], isEmpty);
      final output = jsonDecode(h.stdout.toString()) as Map<String, dynamic>;
      expect(
        output['simulation'],
        DeliveryPolicySimulationV1(
          scope: h.review.scope,
          reason: 'identityUnavailable',
          routeId: 'original-route',
        ).toJson(),
      );
      expect(h.writes, isEmpty);
    },
  );

  test(
    'old documents, foreign scopes, and misaddressed server reviews cannot publish',
    () async {
      final old = await h.file(
        'old.json',
        CanonicalJsonCodec.encode({'rules': <Object>[]}),
      );
      expect(
        await h.run('publish', ['--document', old, '--expect-no-revision']),
        1,
      );
      expect(h.calls, isEmpty);
      final path = await h.file('review.json', h.review.canonicalBytes);
      expect(
        await h.run('publish', [
          '--review',
          path,
          '--expected-revision-ordinal',
          '3',
          '--reviewed-digest',
          h.review.digest.hex,
        ]),
        1,
      );
      expect(h.calls, isEmpty);
      final original = h.review;
      final request = DeliveryPolicyReviewRequestV1(
        scope: original.scope,
        expectedHeadOrdinal: 4,
        candidatePlan: original.candidatePlan,
        reason: original.reason,
      );
      final requestPath = await h.file('request.json', request.canonicalBytes);
      h.review = policyReview(surfaceScope(live: true), expectedHeadOrdinal: 4);
      expect(
        await h.run('review', [
          '--request',
          requestPath,
          '--out',
          '${h.directory.path}/bad.json',
        ]),
        2,
      );
      expect(h.writes, isEmpty);
      h.review = original;
      final changed = original.toJson();
      ((changed['candidatePlan'] as Map)['snapshots'] as List)
          .first['documentCanonicalBytes'] = base64Encode(
        CanonicalJsonCodec.encode({'changed': true}),
      );
      h.review = DeliveryPolicyReviewV1.fromJson(changed);
      expect(
        await h.run('review', [
          '--request',
          requestPath,
          '--out',
          '${h.directory.path}/changed.json',
        ]),
        2,
      );
      expect(h.writes, isEmpty);
      h.review = original;
      h.invalidReview = true;
      expect(
        await h.run('review-rollback', [
          '--route-id',
          'original-route',
          '--prior-revision-ordinal',
          '2',
          '--expected-revision-ordinal',
          '4',
        ]),
        2,
      );
      expect(h.stderr.toString(), contains('invalid delivery result'));
      expect(h.writes, isEmpty);
    },
  );

  test(
    'current review request byte budget is enforced before the actual RPC',
    () async {
      final request = DeliveryPolicyReviewRequestV1(
        scope: h.review.scope,
        expectedHeadOrdinal: 4,
        candidatePlan: DeliveryPolicyPlanV1(
          scope: h.review.scope,
          snapshots: [
            DeliveryPolicySnapshotInputV1(
              effectiveFromLocal: null,
              documentCanonicalBytes: CanonicalJsonCodec.encode({
                'original': 'x' * kMaximumRoutingRequestBytes,
              }),
            ),
          ],
        ),
        reason: 'Review the complete original plan',
      );
      final path = await h.file('large.json', request.canonicalBytes);
      expect(
        await h.run('review', [
          '--request',
          path,
          '--out',
          '${h.directory.path}/unused.json',
        ]),
        1,
      );
      expect(h.calls, isEmpty);
      expect(
        h.stderr.toString(),
        contains('$kMaximumRoutingRequestBytes bytes'),
      );
    },
  );

  test(
    'read and immutable read-revision preserve the complete opaque schedule above the old document limit',
    () async {
      h.stored = CanonicalJsonCodec.encode({
        'completeOriginalPolicy': 'x' * (1024 * 1024 + 1),
        'originalFutureTimeline': [null, '2027-01-04T09:30:00'],
      });
      final out = '${h.directory.path}/whole.json';
      expect(await h.run('read', ['--out', out]), 0);
      expect(File(out).readAsBytesSync(), h.stored);
      expect(
        await h.run('read-revision', ['--revision-ordinal', '2', '--out', out]),
        0,
      );
      expect(File(out).readAsBytesSync(), h.stored);
      expect(h.calls.single['revisionOrdinal'], 2);
    },
  );

  test(
    'console live consent alone cannot acknowledge policy review warnings',
    () async {
      h.review = routingReview(live: true);
      final path = await h.file('review.json', h.review.canonicalBytes);
      final executor = ConsoleCommandExecutor(
        credentialStore: h.store,
        httpClient: h.client(),
        directory: h.directory,
      );
      final result = await executor.runCommand(
        h.arguments('publish', ['--review', path], live: true),
      );
      expect(result.exitCode, 1);
      expect(result.stdout, contains('Completed welcome'));
      expect(h.writes, isEmpty);
    },
  );
}
