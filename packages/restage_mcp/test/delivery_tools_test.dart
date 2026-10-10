import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/api.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    hide RuntimePlane;
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '_support/delivery_fixtures.dart';
import '_support/fake_backend.dart';
import '_support/harness.dart';

void main() {
  late Directory home;
  late FileCredentialStore store;
  setUp(() async {
    home = await Directory.systemTemp.createTemp('delivery-tools-');
    store = FileCredentialStore('${home.path}/credentials');
    await store.write(
      const Credential(
        endpoint: 'http://localhost:8080/',
        kind: CredentialKind.authKey,
        authToken: 'keyId:delivery_tool_session_token_value',
      ),
    );
  });
  tearDown(() => home.delete(recursive: true));

  test(
    'named source warnings remain exact and live consent does not invent their acknowledgement',
    () async {
      final impact = warningImpact(placementScope());
      final review = policyReview(impact.scope, impact: impact);
      final request = DeliveryPolicyPublishRequestV1(
        reviewRef: review.reviewRef,
        operationId: operationId,
      );
      final acknowledgement = DeliveryMeasurementImpactAcknowledgementV1(
        reviewDigest: impact.digest,
        warningCodes: impact.warningCodes,
      );
      final acknowledged = DeliveryPolicyPublishRequestV1(
        reviewRef: review.reviewRef,
        operationId: operationId,
        measurementAcknowledgement: acknowledgement,
      );
      final sent = <DeliveryPolicyPublishRequestV1>[];
      final connection = await connectServer(
        store: store,
        httpClient: fakeBackend((call) async {
          if (call.method == 'review') {
            return http.Response(
              jsonEncode(encodeByteDataWire(review.canonicalBytes)),
              200,
            );
          }
          final decoded = DeliveryPolicyPublishRequestV1.fromCanonicalBytes(
            decodeByteDataWire(
              call.body['requestBytes'],
              malformed: FormatException.new,
            ),
          );
          sent.add(decoded);
          final result = decoded.measurementAcknowledgement == null
              ? const DeliveryPolicyPublishResultV1.refused(
                  'measurementAcknowledgementRequired',
                )
              : DeliveryPolicyPublishResultV1.applied(review.candidateRevision);
          return http.Response(
            jsonEncode(encodeByteDataWire(result.canonicalBytes)),
            200,
          );
        }),
      );
      final reviewRequest = DeliveryPolicyReviewRequestV1(
        scope: review.scope,
        expectedHeadOrdinal: null,
        candidatePlan: review.candidatePlan,
        reason: review.reason,
      );
      final frozen = await connection.callTool(
        CallToolRequest(
          name: 'restage_delivery_policy_review',
          arguments: {
            ...targetArguments(),
            'requestJson': utf8.decode(reviewRequest.canonicalBytes),
          },
        ),
      );
      expect(text(frozen), utf8.decode(review.canonicalBytes));
      final refused = await connection.callTool(
        CallToolRequest(
          name: 'restage_delivery_policy_publish',
          arguments: {
            ...targetArguments(),
            'requestJson': utf8.decode(request.canonicalBytes),
            'confirmLive': true,
          },
        ),
      );
      expect(refused.isError, true);
      expect(sent.single.measurementAcknowledgement, isNull);
      final accepted = await connection.callTool(
        CallToolRequest(
          name: 'restage_delivery_policy_publish',
          arguments: {
            ...targetArguments(),
            'requestJson': utf8.decode(acknowledged.canonicalBytes),
          },
        ),
      );
      expect(accepted.isError ?? false, false);
      expect(sent.last.measurementAcknowledgement, acknowledgement);
    },
  );

  test(
    'every registered delivery read preserves exact public requests and results',
    () async {
      final placement = placementScope();
      final surface = surfaceScope();
      final publication = DeliveryPublicationReferenceV1(
        surface: DeliverySurfaceReferenceV1(
          surfaceIdentity: surface.root.surface!,
          family: surface.family,
        ),
        publishedVersion: 7,
        payloadFormatVersion: 2,
        contentHash: CanonicalDigest('e' * 64),
      );
      final fitRequest = DeliveryPolicyFitReadRequestV1.forPublication(
        publication: publication,
        pageSize: 2,
        cursor: 'opaque-fit-start',
      );
      final query = PlacementObservedHistoryQueryV1(
        placement: placement.root.placement!.key,
        fromMicros: 10,
        untilMicros: 100,
        bucket: PlacementHistoryBucketV1.hour,
      );
      final inputs = DeliverySimulationInputsV1(
        localNow: LocalCivilDateTimeV1.parse('2027-01-04T09:30:00'),
        sdkBuiltInsCanonicalBytes: CanonicalJsonCodec.encode({
          'channel': 'organic',
          'daysSinceInstall': 8,
        }),
      );
      final cases = <(DeliveryOperation, CanonicalValue, CanonicalValue)>[
        (
          DeliveryOperation.placementList,
          PlacementDirectoryRequestV1(
            target: sampleTarget(),
            limit: 2,
            cursor: 'opaque-directory-start',
          ),
          PlacementDirectoryPageV1(
            target: sampleTarget(),
            cut: directoryCut(),
            reportingCutoffMicros: 80,
            status: PlacementDirectoryStatusV1.available,
            items: const [],
            nextCursor: 'opaque-directory-next',
          ),
        ),
        (
          DeliveryOperation.placementRead,
          PlacementReadRequestV1(target: sampleTarget(), key: query.placement),
          PlacementReadV1(
            target: sampleTarget(),
            key: query.placement,
            cut: directoryCut(),
            reportingCutoffMicros: 80,
            status: PlacementReadStatusV1.notFound,
            authorityStatus: PlacementAuthorityStatusV1.available,
            surfaces: const [],
            placementExperimentRequirement:
                PlacementExperimentRequirementV1.absent,
            placementExperiments: const [],
          ),
        ),
        (
          DeliveryOperation.placementObservedHistory,
          PlacementObservedHistoryReadRequestV1(
            target: sampleTarget(),
            query: query,
          ),
          PlacementObservedHistoryV1(
            target: sampleTarget(),
            placement: query.placement,
            coverage: PlacementHistoryCoverageV1.unavailableHistoric,
            requestedFromMicros: 10,
            requestedUntilMicros: 100,
            retainedFromMicros: null,
            publicationGeneration: 7,
            publishedAsOfMicros: 190,
            validUntilMicros: 300,
            rows: const [],
          ),
        ),
        (
          DeliveryOperation.placementSimulate,
          PlacementSimulationPageRequestV1(
            target: sampleTarget(),
            keys: [query.placement],
            inputs: inputs,
          ),
          PlacementSimulationPageV1(
            target: sampleTarget(),
            cut: directoryCut(),
            status: PlacementDirectoryStatusV1.available,
            evaluatedKeys: [query.placement],
            probes: [
              PlacementSimulationProbeV1(
                key: query.placement,
                reason: 'cohortUnavailable',
                decisions: [
                  DeliveryPolicySimulationV1(
                    scope: placement,
                    reason: 'selected',
                  ),
                  DeliveryPolicySimulationV1(
                    scope: surface,
                    reason: 'cohortUnavailable',
                  ),
                ],
              ),
            ],
          ),
        ),
        (
          DeliveryOperation.deliveryPolicyRead,
          DeliveryPolicyReadRequestV1(scope: surface),
          DeliveryPolicyReadV1(scope: surface),
        ),
        (
          DeliveryOperation.deliveryPolicyTimeline,
          DeliveryPolicyTimelineRequestV1(scope: surface),
          DeliveryPolicyTimelineV1(
            policy: policyRead(surface, 3),
            plan: policyPlan(surface),
          ),
        ),
        (
          DeliveryOperation.deliveryPolicyHistory,
          DeliveryPolicyHistoryRequestV1(
            scope: placement,
            beforeOrdinal: 6,
            pageSize: 2,
          ),
          DeliveryPolicyHistoryV1(
            scope: placement,
            revisions: [policyRead(placement, 5), policyRead(placement, 4)],
            nextBeforeOrdinal: 4,
          ),
        ),
        (
          DeliveryOperation.deliveryPolicyFit,
          fitRequest,
          DeliveryPolicyFitReadV1(
            request: fitRequest,
            authorityDigest: CanonicalDigest('f' * 64),
            nextCursor: 'opaque-fit-next',
            entries: [
              DeliveryPolicyFitEntryV1(
                scope: placement,
                publication: publication,
                verdictCanonicalBytes: CanonicalJsonCodec.encode({
                  'reason': 'contractMismatch',
                  'status': 'incompatible',
                }),
              ),
            ],
          ),
        ),
        (
          DeliveryOperation.deliveryPolicySimulate,
          DeliveryPolicySimulationRequestV1(scope: surface, inputs: inputs),
          DeliveryPolicySimulationV1(
            scope: surface,
            reason: 'cohortUnavailable',
          ),
        ),
      ];
      var next = 0;
      final calls = <BackendCall>[];
      final connection = await connectServer(
        store: store,
        httpClient: fakeBackend((call) async {
          final (operation, request, result) = cases[next++];
          expect(call.endpoint, operation.rpcOwner);
          expect(call.method, operation.rpcMethod);
          expect(
            decodeByteDataWire(
              call.body['requestBytes'],
              malformed: FormatException.new,
            ),
            request.canonicalBytes,
          );
          expect(call.body['environmentTargetId'], 42);
          return http.Response(
            jsonEncode(encodeByteDataWire(result.canonicalBytes)),
            200,
          );
        }, calls: calls),
      );
      for (final (operation, request, result) in cases) {
        final output = await connection.callTool(
          CallToolRequest(
            name: operation.mcpName,
            arguments: {
              ...targetArguments(),
              'requestJson': utf8.decode(request.canonicalBytes),
            },
          ),
        );
        expect(output.isError ?? false, false, reason: text(output));
        expect(text(output), utf8.decode(result.canonicalBytes));
      }
      expect(next, cases.length);
      expect(
        calls.where(
          (c) => c.endpoint != 'scope' && c.endpoint != 'environment',
        ),
        hasLength(cases.length),
      );
    },
  );

  test(
    'registered review undo and publish preserve the server review and stale-head conflict',
    () async {
      final review = policyReview(placementScope());
      final undo = policyReview(review.scope, expectedHeadOrdinal: 2);
      final requests = <CanonicalValue>[
        DeliveryPolicyReviewRequestV1(
          scope: review.scope,
          expectedHeadOrdinal: null,
          candidatePlan: review.candidatePlan,
          reason: review.reason,
        ),
        DeliveryPolicyPublishRequestV1(
          reviewRef: review.reviewRef,
          operationId: operationId,
        ),
        DeliveryPolicyUndoReviewRequestV1(
          scope: undo.scope,
          expectedHeadOrdinal: 2,
          restoreOrdinal: 1,
          reason: undo.reason,
        ),
      ];
      final results = <CanonicalValue>[
        review,
        DeliveryPolicyPublishResultV1.conflict(policyRevision(review.scope, 2)),
        undo,
      ];
      final operations = [
        DeliveryOperation.deliveryPolicyReview,
        DeliveryOperation.deliveryPolicyPublish,
        DeliveryOperation.deliveryPolicyUndoReview,
      ];
      var next = 0;
      final connection = await connectServer(
        store: store,
        httpClient: fakeBackend((call) async {
          expect(call.endpoint, 'deliveryPolicy');
          expect(call.method, operations[next].rpcMethod);
          expect(
            decodeByteDataWire(
              call.body['requestBytes'],
              malformed: FormatException.new,
            ),
            requests[next].canonicalBytes,
          );
          return http.Response(
            jsonEncode(encodeByteDataWire(results[next++].canonicalBytes)),
            200,
          );
        }),
      );
      for (var i = 0; i < operations.length; i++) {
        final output = await connection.callTool(
          CallToolRequest(
            name: operations[i].mcpName,
            arguments: {
              ...targetArguments(),
              'requestJson': utf8.decode(requests[i].canonicalBytes),
            },
          ),
        );
        expect(output.isError ?? false, i == 1);
        expect(text(output), utf8.decode(results[i].canonicalBytes));
      }
      expect(next, 3);
    },
  );

  test(
    'policy publish live guard refuses before mutation and accepts the same reviewed reference',
    () async {
      final review = policyReview(placementScope(live: true));
      final request = DeliveryPolicyPublishRequestV1(
        reviewRef: review.reviewRef,
        operationId: operationId,
      );
      final calls = <BackendCall>[];
      final connection = await connectServer(
        store: store,
        httpClient: fakeBackend(
          (call) async => http.Response(
            jsonEncode(
              encodeByteDataWire(
                DeliveryPolicyPublishResultV1.applied(
                  review.candidateRevision,
                ).canonicalBytes,
              ),
            ),
            200,
          ),
          calls: calls,
        ),
      );
      final args = {
        ...targetArguments(live: true),
        'requestJson': utf8.decode(request.canonicalBytes),
      };
      final refused = await connection.callTool(
        CallToolRequest(
          name: 'restage_delivery_policy_publish',
          arguments: args,
        ),
      );
      expect(refused.isError, true);
      expect(text(refused), contains('confirmLive'));
      expect(calls.where((c) => c.endpoint == 'deliveryPolicy'), isEmpty);
      final accepted = await connection.callTool(
        CallToolRequest(
          name: 'restage_delivery_policy_publish',
          arguments: {...args, 'confirmLive': true},
        ),
      );
      expect(accepted.isError ?? false, false, reason: text(accepted));
      expect(
        calls.where(
          (c) => c.endpoint == 'deliveryPolicy' && c.method == 'publish',
        ),
        hasLength(1),
      );
    },
  );

  test(
    'target mismatch is refused before RPC and typed service refusal retains original reason',
    () async {
      final calls = <BackendCall>[];
      final connection = await connectServer(
        store: store,
        httpClient: fakeBackend(
          (call) async => typedError('SurfaceRoutingRejectedException', {
            'reason': 'cursorStale',
          }),
          calls: calls,
        ),
      );
      final mismatch = DeliveryPolicyReadRequestV1(
        scope: placementScope(live: true),
      );
      final refused = await connection.callTool(
        CallToolRequest(
          name: 'restage_delivery_policy_read',
          arguments: {
            ...targetArguments(),
            'requestJson': utf8.decode(mismatch.canonicalBytes),
          },
        ),
      );
      expect(refused.isError, true);
      expect(calls.where((c) => c.endpoint == 'deliveryPolicy'), isEmpty);
      final request = DeliveryPolicyReadRequestV1(scope: placementScope());
      final response = await connection.callTool(
        CallToolRequest(
          name: 'restage_delivery_policy_read',
          arguments: {
            ...targetArguments(),
            'requestJson': utf8.decode(request.canonicalBytes),
          },
        ),
      );
      expect(response.isError, true);
      expect(text(response), contains('cursorStale'));
    },
  );
}
