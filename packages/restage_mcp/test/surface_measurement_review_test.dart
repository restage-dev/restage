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

DeliveryMeasurementMutationReviewV1 mutationReview(
  String operation, {
  bool live = false,
  bool changed = false,
  bool refused = false,
  int appId = 11,
}) {
  final reviews =
      [
        for (final slug in ['welcome', 'returning'])
          DeliveryMeasurementImpactReviewV1.fromJson(
            warningImpact(
              DeliveryPolicyScopeV1(
                root: DeliveryRootIdentityV1.placement(
                  PlacementIdentityV1(
                    target: sampleTarget(live: live, appId: appId),
                    key: PlacementKeyV1.named(slug: slug),
                  ),
                ),
                family: const DeliveryFamilySelectorV1.none(),
              ),
            ).toJson()..['operation'] = operation,
          ),
      ]..sort(
        (a, b) => base64Encode(
          a.scope.canonicalBytes,
        ).compareTo(base64Encode(b.scope.canonicalBytes)),
      );
  return DeliveryMeasurementMutationReviewV1(
    operation: operation,
    reviews: reviews,
    dependencyDigest: CanonicalDigest((changed ? 'b' : 'a') * 64),
    refusalCodes: refused ? ['impactAuthorityUnavailable'] : const [],
  );
}

const surfaceArguments = <String, Object?>{
  'projectSlug': 'demo',
  'appSlug': 'mobile',
  'organizationId': 7,
  'environmentSlug': 'staging',
  'runtimePlane': 'sandbox',
  'surfaceType': 'onboarding',
  'surfaceSlug': 'first-run',
  'reason': 'Reviewed surface change',
};

class SurfaceReviewHarness {
  SurfaceReviewHarness._(this.directory, this.store);
  static Future<SurfaceReviewHarness> create() async {
    final directory = await Directory.systemTemp.createTemp(
      'mcp-surface-review-',
    );
    final store = FileCredentialStore('${directory.path}/credentials');
    await store.write(
      const Credential(
        endpoint: 'https://api.test/',
        kind: CredentialKind.authKey,
        authToken: 'keyId:SUPERSECRET',
      ),
    );
    return SurfaceReviewHarness._(directory, store);
  }

  final Directory directory;
  final FileCredentialStore store;
  final calls = <BackendCall>[];
  late DeliveryMeasurementMutationReviewV1 review;
  String? refusal;
  Future<ServerConnection> connect() => connectServer(
    store: store,
    httpClient: fakeBackend(
      (call) async {
        if (call.method == 'reviewDeliveryImpact') {
          return http.Response(
            jsonEncode(encodeByteDataWire(review.canonicalBytes)),
            200,
          );
        }
        if (refusal != null) {
          return typedError('SurfaceRoutingRejectedException', {
            'reason': refusal,
          });
        }
        if (const {
          'activateSurface',
          'rollbackSurface',
        }.contains(call.method)) {
          final revision =
              call.body['publishedRevision'] as int? ??
              call.body['toVersion'] as int? ??
              3;
          return http.Response(
            jsonEncode({
              'family': {
                'surfaceType': 'onboarding',
                'surfaceSlug': 'first-run',
                'sourceKind': 'screen',
                'contractVersion': 2,
              },
              'publishedRevision': revision,
              'activePublishedRevisionBefore': 3,
              'activePublishedRevisionAfter': revision,
              'identityFrozenAfter': false,
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'surfaceType': 'onboarding',
            'surfaceSlug': 'first-run',
            'frozen': false,
            'affectedFamilies': <Object>[],
          }),
          200,
        );
      },
      calls: calls,
      withDefaultSurfaceReview: false,
    ),
  );
  List<BackendCall> get mutations => calls
      .where(
        (call) => const {
          'activateSurface',
          'rollbackSurface',
          'killSurface',
          'setSurfaceLock',
        }.contains(call.method),
      )
      .toList();
  Future<void> dispose() => directory.delete(recursive: true);
}

void main() {
  test(
    'identity-wide governance never carries partial family selectors from metadata',
    () async {
      final h = await SurfaceReviewHarness.create();
      addTearDown(h.dispose);
      h.review = mutationReview('surfaceKill');
      final connection = await h.connect();
      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_kill_surface',
          arguments: {
            ...surfaceArguments,
            'sourceKind': 'screen',
            'contractVersion': 2,
            'reviewedDigest': h.review.digest.hex,
          },
        ),
      );
      expect(
        result.isError,
        isNot(true),
        reason: (result.content.single as TextContent).text,
      );
      final reviewed = h.calls.singleWhere(
        (call) => call.method == 'reviewDeliveryImpact',
      );
      expect(reviewed.body.containsKey('sourceKind'), false);
      expect(reviewed.body.containsKey('contractVersion'), false);
      expect(h.mutations.single.body.containsKey('sourceKind'), false);
      expect(h.mutations.single.body.containsKey('contractVersion'), false);
    },
  );
  for (final (tool, operation, method, arguments, revision, frozen) in [
    (
      'restage_publish_surface',
      'surfaceActivate',
      'activateSurface',
      {'revision': 3, 'sourceKind': 'screen', 'contractVersion': 2},
      3,
      null,
    ),
    (
      'restage_rollback_surface',
      'surfaceRollback',
      'rollbackSurface',
      {
        'toVersion': 1,
        'freeze': true,
        'sourceKind': 'screen',
        'contractVersion': 2,
      },
      1,
      true,
    ),
    (
      'restage_kill_surface',
      'surfaceKill',
      'killSurface',
      {'frozen': true},
      null,
      true,
    ),
    (
      'restage_freeze_surface',
      'surfaceFreeze',
      'setSurfaceLock',
      <String, Object?>{},
      null,
      true,
    ),
    (
      'restage_unfreeze_surface',
      'surfaceFreeze',
      'setSurfaceLock',
      <String, Object?>{},
      null,
      false,
    ),
  ]) {
    test(
      '$tool registered handler uses complete original review and exact proceed',
      () async {
        final h = await SurfaceReviewHarness.create();
        addTearDown(h.dispose);
        h.review = mutationReview(operation);
        final connection = await h.connect();
        final request = {...surfaceArguments, ...arguments};
        final missing = await connection.callTool(
          CallToolRequest(name: tool, arguments: request),
        );
        expect(missing.isError, true);
        expect(h.mutations, isEmpty);
        expect(
          missing.structuredContent!['measurementReview'],
          h.review.toJson(),
        );
        expect(missing.structuredContent!['reviewDigest'], h.review.digest.hex);
        h.calls.clear();
        final accepted = await connection.callTool(
          CallToolRequest(
            name: tool,
            arguments: {
              ...request,
              'reviewedDigest': h.review.digest.hex,
              'operationId': operationId,
            },
          ),
        );
        expect(
          accepted.isError,
          isNot(true),
          reason: (accepted.content.single as TextContent).text,
        );
        final reviewCall = h.calls.singleWhere(
          (call) => call.method == 'reviewDeliveryImpact',
        );
        final mutation = h.mutations.single;
        expect(mutation.method, method);
        expect(reviewCall.endpoint, 'surface');
        expect(reviewCall.body['operation'], operation);
        expect(reviewCall.body['publishedRevision'], revision);
        expect(reviewCall.body['frozen'], frozen);
        for (final key in [
          'projectSlug',
          'appSlug',
          'surfaceType',
          'surfaceSlug',
          'environmentSlug',
          'environmentTargetId',
          'runtimePlane',
          'organizationId',
          'reason',
          'sourceKind',
          'contractVersion',
        ]) {
          expect(reviewCall.body[key], mutation.body[key], reason: key);
        }
        expect(mutation.body['environmentTargetId'], 42);
        final proceed = DeliveryMeasurementMutationProceedV1.fromCanonicalBytes(
          decodeByteDataWire(
            mutation.body['measurementProceedBytes'],
            malformed: FormatException.new,
          ),
        );
        expect(proceed.operationId, operationId);
        expect(proceed.acknowledgements, hasLength(2));
        expect(proceed.acknowledges(h.review), true);
      },
    );
  }
  test(
    'review-only preserves the full cut and stale or foreign reviews never mutate',
    () async {
      final h = await SurfaceReviewHarness.create();
      addTearDown(h.dispose);
      h.review = mutationReview('surfaceActivate');
      final connection = await h.connect();
      final request = {...surfaceArguments, 'revision': 3};
      final reviewed = await connection.callTool(
        CallToolRequest(
          name: 'restage_publish_surface',
          arguments: {...request, 'reviewOnly': true},
        ),
      );
      expect(reviewed.isError, isNot(true));
      expect(h.mutations, isEmpty);
      expect(
        reviewed.structuredContent!['measurementReview'],
        h.review.toJson(),
      );
      final digest = h.review.digest.hex;
      h.review = mutationReview('surfaceActivate', changed: true);
      final stale = await connection.callTool(
        CallToolRequest(
          name: 'restage_publish_surface',
          arguments: {...request, 'reviewedDigest': digest},
        ),
      );
      expect(stale.isError, true);
      expect(h.mutations, isEmpty);
      expect(stale.structuredContent!['reviewDigest'], h.review.digest.hex);
      h.review = mutationReview('surfaceActivate', appId: 99);
      final foreign = await connection.callTool(
        CallToolRequest(
          name: 'restage_publish_surface',
          arguments: {...request, 'reviewOnly': true},
        ),
      );
      expect(foreign.isError, true);
      expect(h.mutations, isEmpty);
      expect(
        (foreign.content.single as TextContent).text,
        contains('invalid delivery result'),
      );
    },
  );
  test(
    'actual live guard and complete warning approval remain separate',
    () async {
      final h = await SurfaceReviewHarness.create();
      addTearDown(h.dispose);
      h.review = mutationReview('surfaceFreeze', live: true);
      final connection = await h.connect();
      final arguments = {
        ...surfaceArguments,
        'environmentSlug': 'production',
        'runtimePlane': 'live',
      };
      final denied = await connection.callTool(
        CallToolRequest(name: 'restage_freeze_surface', arguments: arguments),
      );
      expect(denied.isError, true);
      expect(h.calls.where((call) => call.endpoint == 'surface'), isEmpty);
      final consentOnly = await connection.callTool(
        CallToolRequest(
          name: 'restage_freeze_surface',
          arguments: {...arguments, 'confirmLive': true},
        ),
      );
      expect(consentOnly.isError, true);
      expect(h.mutations, isEmpty);
      expect(consentOnly.structuredContent!['acknowledgementRequired'], true);
      final accepted = await connection.callTool(
        CallToolRequest(
          name: 'restage_freeze_surface',
          arguments: {
            ...arguments,
            'confirmLive': true,
            'reviewedDigest': h.review.digest.hex,
            'operationId': operationId,
          },
        ),
      );
      expect(
        accepted.isError,
        isNot(true),
        reason: (accepted.content.single as TextContent).text,
      );
      expect(h.mutations.single.body['environmentTargetId'], 44);
    },
  );
  test(
    'authoritative refusal and post-review stale code remain original',
    () async {
      final h = await SurfaceReviewHarness.create();
      addTearDown(h.dispose);
      h.review = mutationReview('surfaceActivate', refused: true);
      final connection = await h.connect();
      final refused = await connection.callTool(
        CallToolRequest(
          name: 'restage_publish_surface',
          arguments: {...surfaceArguments, 'revision': 3, 'reviewOnly': true},
        ),
      );
      expect(refused.isError, true);
      expect(h.mutations, isEmpty);
      expect(
        refused.structuredContent!['measurementReview'],
        h.review.toJson(),
      );
      h.review = mutationReview('surfaceActivate');
      h.refusal = 'review_stale';
      final stale = await connection.callTool(
        CallToolRequest(
          name: 'restage_publish_surface',
          arguments: {
            ...surfaceArguments,
            'revision': 3,
            'reviewedDigest': h.review.digest.hex,
          },
        ),
      );
      expect(stale.isError, true);
      expect(
        (stale.content.single as TextContent).text,
        contains('review_stale'),
      );
    },
  );
}
