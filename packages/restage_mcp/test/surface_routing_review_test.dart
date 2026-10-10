import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/api.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    hide RuntimePlane;
import 'package:test/test.dart';

import '_support/delivery_fixtures.dart';
import '_support/fake_backend.dart';
import '_support/harness.dart';

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

void main() {
  late Directory directory;
  late FileCredentialStore store;
  late DeliveryPolicyReviewV1 review;
  late List<BackendCall> calls;
  String? refusal;
  bool invalidReview = false;
  late List<int> stored;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('routing-review-');
    store = FileCredentialStore('${directory.path}/credentials');
    await store.write(
      const Credential(
        endpoint: 'http://localhost:8080/',
        kind: CredentialKind.authKey,
        authToken: 'key:secret',
      ),
    );
    review = routingReview();
    calls = [];
    refusal = null;
    invalidReview = false;
    stored = CanonicalJsonCodec.encode({
      'originalDocuments': ['both branches', 'future snapshot'],
      'timeline': [null, '2027-01-04T09:30:00'],
    });
  });
  tearDown(() => directory.delete(recursive: true));

  Future<ServerConnection> connect() => connectServer(
    store: store,
    httpClient: fakeBackend((call) async {
      if (refusal != null) {
        return typedError('SurfaceRoutingRejectedException', {
          'reason': refusal,
        });
      }
      switch (call.method) {
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
              'revisionOrdinal': call.body['revisionOrdinal'],
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
          fail('Unexpected routing call ${call.method}');
      }
    }, calls: calls),
  );

  Map<String, Object?> target({bool live = false}) => {
    ...targetArguments(live: live),
    'surfaceType': 'onboarding',
    'surfaceSlug': 'welcome',
    'contractVersion': 2,
  };
  List<BackendCall> routingCalls() =>
      calls.where((call) => call.endpoint == 'surfaceRouting').toList();
  List<BackendCall> writes() => routingCalls()
      .where(
        (call) =>
            const {'publishRouting', 'rollbackRoute'}.contains(call.method),
      )
      .toList();

  test(
    'actual routing registration advertises only current authoring formats and separate reviews',
    () async {
      final connection = await connect();
      final tools = {
        for (final tool in (await connection.listTools(
          ListToolsRequest(),
        )).tools)
          tool.name: tool,
      };
      for (final name in [
        'restage_review_routing',
        'restage_review_route_rollback',
        'restage_publish_routing',
        'restage_rollback_route',
      ]) {
        expect(tools, contains(name));
        expect(tools[name]!.inputSchema.properties, contains('confirmLive'));
      }
      expect(
        tools['restage_publish_routing']!.inputSchema.properties,
        contains('reviewBase64'),
      );
      expect(
        tools['restage_publish_routing']!.inputSchema.properties,
        isNot(contains('documentBase64')),
      );
      for (final field in [
        'schemaBase64',
        'requestContextBase64',
        'audiencesBase64',
        'sdkBuiltInsBase64',
      ]) {
        expect(
          tools['restage_preview_routing']!.inputSchema.properties,
          isNot(contains(field)),
        );
      }
    },
  );

  test(
    'actual registered review preserves the complete candidate and original safe impact',
    () async {
      final connection = await connect();
      final request = DeliveryPolicyReviewRequestV1(
        scope: review.scope,
        expectedHeadOrdinal: 4,
        candidatePlan: review.candidatePlan,
        reason: review.reason,
      );
      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_review_routing',
          arguments: {
            ...target(),
            'requestBase64': base64Encode(request.canonicalBytes),
          },
        ),
      );
      expect(result.isError, isNot(true));
      expect(routingCalls().single.method, 'reviewRouting');
      expect(
        decodeByteDataWire(
          routingCalls().single.body['requestBytes'],
          maximumBytes: kMaximumRoutingRequestBytes,
          malformed: (detail) => FormatException(detail),
        ),
        request.canonicalBytes,
      );
      expect(result.structuredContent!['policyReview'], review.toJson());
      expect(
        result.structuredContent!['reviewBase64'],
        base64Encode(review.canonicalBytes),
      );
      expect(result.structuredContent!['reviewDigest'], review.digest.hex);
      expect(writes(), isEmpty);
    },
  );

  test(
    'registered publish requires exact separate warning approval and preserves the complete server reference',
    () async {
      final connection = await connect();
      final arguments = {
        ...target(),
        'reviewBase64': base64Encode(review.canonicalBytes),
        'operationId': operationId,
      };
      var result = await connection.callTool(
        CallToolRequest(name: 'restage_publish_routing', arguments: arguments),
      );
      expect(result.isError, isTrue);
      expect(result.structuredContent!['policyReview'], review.toJson());
      expect(result.structuredContent!['acknowledgementRequired'], isTrue);
      expect(writes(), isEmpty);
      result = await connection.callTool(
        CallToolRequest(
          name: 'restage_publish_routing',
          arguments: {...arguments, 'reviewedDigest': '0' * 64},
        ),
      );
      expect(result.isError, isTrue);
      expect(writes(), isEmpty);
      result = await connection.callTool(
        CallToolRequest(
          name: 'restage_publish_routing',
          arguments: {...arguments, 'reviewedDigest': review.digest.hex},
        ),
      );
      expect(result.isError, isNot(true));
      final call = writes().single.body;
      final publish = DeliveryPolicyPublishRequestV1.fromCanonicalBytes(
        decodeByteDataWire(
          call['documentBytes'],
          maximumBytes: kMaximumRoutingRequestBytes,
          malformed: (detail) => FormatException(detail),
        ),
      );
      expect(publish.reviewRef, review.reviewRef);
      expect(publish.operationId, operationId);
      expect(
        publish.measurementAcknowledgement!.acknowledges(
          review.measurementImpact,
        ),
        isTrue,
      );
      expect(call['expectedRevisionOrdinal'], 4);
      expect(call['operationId'], operationId);
      expect(call['environmentId'], 42);
      expect(call['organizationId'], 7);
      refusal = 'review_stale';
      calls.clear();
      result = await connection.callTool(
        CallToolRequest(
          name: 'restage_publish_routing',
          arguments: {...arguments, 'reviewedDigest': review.digest.hex},
        ),
      );
      expect(result.isError, isTrue);
      expect(text(result), contains('review_stale'));
      expect(writes(), hasLength(1));
    },
  );

  test(
    'actual rollback reviews only the original selected route and sends exact reviewed publish bytes',
    () async {
      final connection = await connect();
      final arguments = {
        ...target(),
        'routeId': 'original-route',
        'priorRevisionOrdinal': 2,
        'expectedRevisionOrdinal': 4,
      };
      var result = await connection.callTool(
        CallToolRequest(name: 'restage_rollback_route', arguments: arguments),
      );
      expect(result.isError, isTrue);
      expect(result.structuredContent!['policyReview'], review.toJson());
      expect(writes(), isEmpty);
      calls.clear();
      result = await connection.callTool(
        CallToolRequest(
          name: 'restage_rollback_route',
          arguments: {
            ...arguments,
            'reviewedDigest': review.digest.hex,
            'operationId': operationId,
          },
        ),
      );
      expect(result.isError, isNot(true));
      expect(routingCalls().map((call) => call.method), [
        'reviewRouteRollback',
        'rollbackRoute',
      ]);
      for (final call in routingCalls()) {
        expect(call.body['routeId'], 'original-route');
        expect(call.body['priorRevisionOrdinal'], 2);
        expect(call.body['expectedRevisionOrdinal'], 4);
        expect(call.body['contractVersion'], 2);
      }
      final publish = DeliveryPolicyPublishRequestV1.fromCanonicalBytes(
        decodeByteDataWire(
          writes().single.body['reviewedPublishRequestBytes'],
          maximumBytes: kMaximumRoutingRequestBytes,
          malformed: (detail) => FormatException(detail),
        ),
      );
      expect(publish.reviewRef, review.reviewRef);
      expect(
        publish.measurementAcknowledgement!.acknowledges(
          review.measurementImpact,
        ),
        isTrue,
      );
      calls.clear();
      result = await connection.callTool(
        CallToolRequest(
          name: 'restage_review_route_rollback',
          arguments: arguments,
        ),
      );
      expect(result.isError, isNot(true));
      expect(result.structuredContent!['policyReview'], review.toJson());
      expect(writes(), isEmpty);
      refusal = 'use_whole_policy_review';
      calls.clear();
      result = await connection.callTool(
        CallToolRequest(
          name: 'restage_rollback_route',
          arguments: {...arguments, 'reviewedDigest': review.digest.hex},
        ),
      );
      expect(result.isError, isTrue);
      expect(text(result), contains('use_whole_policy_review'));
      expect(routingCalls().single.method, 'reviewRouteRollback');
    },
  );

  test(
    'actual preview carries one current request and all original simulation evidence',
    () async {
      final connection = await connect();
      final request = DeliveryPolicySimulationRequestV1(
        scope: review.scope,
        inputs: DeliverySimulationInputsV1(
          localNow: LocalCivilDateTimeV1.parse('2027-01-04T09:30:00'),
          analyticsAnonymousId: 'known-visitor',
        ),
      );
      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_preview_routing',
          arguments: {
            ...target(),
            'documentBase64': base64Encode(request.canonicalBytes),
          },
        ),
      );
      expect(result.isError, isNot(true));
      final call = routingCalls().single.body;
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
      expect(
        result.structuredContent!['simulation'],
        DeliveryPolicySimulationV1(
          scope: review.scope,
          reason: 'identityUnavailable',
          routeId: 'original-route',
        ).toJson(),
      );
      expect(writes(), isEmpty);
    },
  );

  test(
    'foreign scopes and invalid or misaddressed server reviews are refused before publication',
    () async {
      final connection = await connect();
      final original = review;
      final foreign = policyReview(
        anotherAppScope(review.scope),
        expectedHeadOrdinal: 4,
      );
      var result = await connection.callTool(
        CallToolRequest(
          name: 'restage_publish_routing',
          arguments: {
            ...target(),
            'reviewBase64': base64Encode(foreign.canonicalBytes),
            'reviewedDigest': foreign.digest.hex,
          },
        ),
      );
      expect(result.isError, isTrue);
      expect(routingCalls(), isEmpty);
      final request = DeliveryPolicyReviewRequestV1(
        scope: original.scope,
        expectedHeadOrdinal: 4,
        candidatePlan: original.candidatePlan,
        reason: original.reason,
      );
      review = foreign;
      calls.clear();
      result = await connection.callTool(
        CallToolRequest(
          name: 'restage_review_routing',
          arguments: {
            ...target(),
            'requestBase64': base64Encode(request.canonicalBytes),
          },
        ),
      );
      expect(result.isError, isTrue);
      expect(text(result), contains('invalid delivery result'));
      expect(writes(), isEmpty);
      review = original;
      final changed = original.toJson();
      ((changed['candidatePlan'] as Map)['snapshots'] as List)
          .first['documentCanonicalBytes'] = base64Encode(
        CanonicalJsonCodec.encode({'changed': true}),
      );
      review = DeliveryPolicyReviewV1.fromJson(changed);
      result = await connection.callTool(
        CallToolRequest(
          name: 'restage_review_routing',
          arguments: {
            ...target(),
            'requestBase64': base64Encode(request.canonicalBytes),
          },
        ),
      );
      expect(result.isError, isTrue);
      expect(text(result), contains('invalid delivery result'));
      expect(writes(), isEmpty);
      review = original;
      invalidReview = true;
      calls.clear();
      result = await connection.callTool(
        CallToolRequest(
          name: 'restage_review_route_rollback',
          arguments: {
            ...target(),
            'routeId': 'original-route',
            'priorRevisionOrdinal': 2,
            'expectedRevisionOrdinal': 4,
          },
        ),
      );
      expect(result.isError, isTrue);
      expect(text(result), contains('invalid delivery result'));
      expect(writes(), isEmpty);
    },
  );

  test(
    'live consent gates actual current mutations and cannot acknowledge warnings',
    () async {
      review = routingReview(live: true);
      final connection = await connect();
      final reviewRequest = DeliveryPolicyReviewRequestV1(
        scope: review.scope,
        expectedHeadOrdinal: 4,
        candidatePlan: review.candidatePlan,
        reason: review.reason,
      );
      for (final name in [
        'restage_review_routing',
        'restage_review_route_rollback',
      ]) {
        final reviewArguments = {
          ...target(live: true),
          if (name == 'restage_review_routing')
            'requestBase64': base64Encode(reviewRequest.canonicalBytes),
          if (name == 'restage_review_route_rollback') ...{
            'routeId': 'original-route',
            'priorRevisionOrdinal': 2,
            'expectedRevisionOrdinal': 4,
          },
        };
        var result = await connection.callTool(
          CallToolRequest(name: name, arguments: reviewArguments),
        );
        expect(result.isError, isTrue);
        expect(routingCalls(), isEmpty);
        result = await connection.callTool(
          CallToolRequest(
            name: name,
            arguments: {...reviewArguments, 'confirmLive': true},
          ),
        );
        expect(result.isError, isNot(true));
        expect(result.structuredContent!['policyReview'], review.toJson());
        expect(writes(), isEmpty);
        calls.clear();
      }
      final arguments = {
        ...target(live: true),
        'reviewBase64': base64Encode(review.canonicalBytes),
        'reviewedDigest': review.digest.hex,
        'operationId': operationId,
      };
      var result = await connection.callTool(
        CallToolRequest(name: 'restage_publish_routing', arguments: arguments),
      );
      expect(result.isError, isTrue);
      expect(routingCalls(), isEmpty);
      final onlyLive = {...arguments, 'confirmLive': true}
        ..remove('reviewedDigest');
      result = await connection.callTool(
        CallToolRequest(name: 'restage_publish_routing', arguments: onlyLive),
      );
      expect(result.isError, isTrue);
      expect(result.structuredContent!['acknowledgementRequired'], isTrue);
      expect(writes(), isEmpty);
      result = await connection.callTool(
        CallToolRequest(
          name: 'restage_publish_routing',
          arguments: {...arguments, 'confirmLive': true},
        ),
      );
      expect(result.isError, isNot(true));
      expect(writes().single.body['environmentId'], 44);
    },
  );

  test(
    'current review request byte budget rejects oversized documents before the actual RPC',
    () async {
      final connection = await connect();
      final request = DeliveryPolicyReviewRequestV1(
        scope: review.scope,
        expectedHeadOrdinal: 4,
        candidatePlan: DeliveryPolicyPlanV1(
          scope: review.scope,
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
      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_review_routing',
          arguments: {
            ...target(),
            'requestBase64': base64Encode(request.canonicalBytes),
          },
        ),
      );
      expect(result.isError, isTrue);
      expect(routingCalls(), isEmpty);
      expect(writes(), isEmpty);
    },
  );

  test(
    'complete opaque reads preserve schedules above the old per-document limit',
    () async {
      stored = CanonicalJsonCodec.encode({
        'completeOriginalPolicy': 'x' * (1024 * 1024 + 1),
        'originalFutureTimeline': [null, '2027-01-04T09:30:00'],
      });
      final connection = await connect();
      for (final name in [
        'restage_read_routing',
        'restage_read_routing_revision',
      ]) {
        final result = await connection.callTool(
          CallToolRequest(
            name: name,
            arguments: {
              ...target(),
              if (name.endsWith('_revision')) 'revisionOrdinal': 2,
            },
          ),
        );
        expect(result.isError, isNot(true));
        expect(
          result.structuredContent!['documentBase64'],
          base64Encode(stored),
        );
      }
    },
  );
}
