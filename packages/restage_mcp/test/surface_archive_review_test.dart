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

const archiveArguments = {
  'projectSlug': 'demo',
  'appSlug': 'mobile',
  'surfaceType': 'paywall',
  'surfaceSlug': 'pro',
  'organizationId': 7,
};

DeliveryMeasurementMutationReviewV1 archiveReview({
  bool warned = true,
  bool changed = false,
  bool refused = false,
  int appId = 11,
  int organizationId = 7,
  String operation = 'surfaceArchive',
}) {
  final reviews = <DeliveryMeasurementImpactReviewV1>[];
  if (warned) {
    for (final live in [false, true]) {
      final target = TargetCoordinate.fromJson(
        sampleTarget(live: live, appId: appId).toJson()
          ..['organizationId'] = organizationId,
      );
      final scope = DeliveryPolicyScopeV1(
        root: live
            ? DeliveryRootIdentityV1.placement(
                PlacementIdentityV1(
                  target: target,
                  key: PlacementKeyV1.named(slug: 'welcome'),
                ),
              )
            : DeliveryRootIdentityV1.surface(
                PublishedSurfaceIdentityV1(
                  target: target,
                  surfaceId: SurfaceId('pro'),
                ),
              ),
        family: live
            ? const DeliveryFamilySelectorV1.none()
            : DeliveryFamilySelectorV1.screenContract(contractVersion: 2),
      );
      reviews.add(
        DeliveryMeasurementImpactReviewV1.fromJson(
          warningImpact(scope).toJson()..['operation'] = operation,
        ),
      );
    }
    reviews.sort(
      (a, b) => base64Encode(
        a.scope.canonicalBytes,
      ).compareTo(base64Encode(b.scope.canonicalBytes)),
    );
  }
  return DeliveryMeasurementMutationReviewV1(
    operation: operation,
    reviews: reviews,
    dependencyDigest: CanonicalDigest((changed ? 'b' : 'a') * 64),
    refusalCodes: refused ? ['impactAuthorityUnavailable'] : const [],
  );
}

class ArchiveHarness {
  ArchiveHarness._(this.directory, this.store);

  static Future<ArchiveHarness> create() async {
    final directory = await Directory.systemTemp.createTemp('archive-review-');
    final store = FileCredentialStore('${directory.path}/credentials');
    await store.write(
      Credential(
        endpoint: 'http://localhost:8080/',
        kind: CredentialKind.authKey,
        authToken: 'test:secret',
      ),
    );
    return ArchiveHarness._(directory, store);
  }

  final Directory directory;
  final FileCredentialStore store;
  final calls = <BackendCall>[];
  DeliveryMeasurementMutationReviewV1 review = archiveReview();
  Object? malformed;
  String? refusal;
  bool hasLive = true;

  Future<ServerConnection> connect() => connectServer(
    store: store,
    httpClient: fakeBackend(
      (call) async {
        expect(call.endpoint, 'surfaceArchive');
        if (call.method == 'reviewDeliveryImpact') {
          return http.Response(
            jsonEncode(malformed ?? encodeByteDataWire(review.canonicalBytes)),
            200,
          );
        }
        if (refusal != null) {
          return typedError('SurfaceRoutingRejectedException', {
            'reason': refusal,
          });
        }
        return http.Response('null', 200);
      },
      calls: calls,
      targets: [
        for (final target in defaultTargets)
          if (hasLive || target.plane != 'live') target,
      ],
    ),
  );

  List<BackendCall> get archives => calls
      .where(
        (call) => call.endpoint == 'surfaceArchive' && call.method == 'archive',
      )
      .toList();
  Future<void> dispose() => directory.delete(recursive: true);
}

void main() {
  test(
    'registered archive retains every original scope and carries exact complete proceed',
    () async {
      final h = await ArchiveHarness.create();
      addTearDown(h.dispose);
      final connection = await h.connect();
      final denied = await connection.callTool(
        CallToolRequest(
          name: 'restage_archive_surface',
          arguments: {...archiveArguments, 'confirmLive': true},
        ),
      );
      expect(denied.isError, true);
      expect(h.archives, isEmpty);
      expect(denied.structuredContent!['measurementReview'], h.review.toJson());
      expect(denied.structuredContent!['reviewDigest'], h.review.digest.hex);
      h.calls.clear();
      final approved = await connection.callTool(
        CallToolRequest(
          name: 'restage_archive_surface',
          arguments: {
            ...archiveArguments,
            'confirmLive': true,
            'reviewedDigest': h.review.digest.hex,
            'operationId': operationId,
          },
        ),
      );
      expect(
        approved.isError,
        isNot(true),
        reason: (approved.content.single as TextContent).text,
      );
      final reviewed = h.calls.singleWhere(
        (call) => call.method == 'reviewDeliveryImpact',
      );
      expect(reviewed.body.keys.toSet(), {
        'method',
        'projectSlug',
        'appSlug',
        'surfaceType',
        'surfaceSlug',
        'organizationId',
      });
      final proceed = DeliveryMeasurementMutationProceedV1.fromCanonicalBytes(
        decodeByteDataWire(
          h.archives.single.body['measurementProceedBytes'],
          malformed: (detail) => FormatException(detail),
        ),
      );
      expect(proceed.operationId, operationId);
      expect(proceed.reviewDigest, h.review.digest);
      expect(proceed.acknowledgements, hasLength(2));
      expect(proceed.acknowledges(h.review), true);
      expect(approved.structuredContent!['operationId'], operationId);
    },
  );

  test(
    'archive schema and review-only expose complete all-target review without environment or family selector',
    () async {
      final h = await ArchiveHarness.create();
      addTearDown(h.dispose);
      final connection = await h.connect();
      final tool = (await connection.listTools(
        ListToolsRequest(),
      )).tools.singleWhere((tool) => tool.name == 'restage_archive_surface');
      expect(
        tool.inputSchema.properties!.keys,
        containsAll([
          'reviewOnly',
          'reviewedDigest',
          'operationId',
          'confirmLive',
        ]),
      );
      expect(
        tool.inputSchema.properties!.keys,
        isNot(contains('environmentSlug')),
      );
      expect(tool.inputSchema.properties!.keys, isNot(contains('sourceKind')));
      expect(
        tool.inputSchema.properties!.keys,
        isNot(contains('contractVersion')),
      );
      final result = await connection.callTool(
        CallToolRequest(
          name: tool.name,
          arguments: {
            ...archiveArguments,
            'confirmLive': true,
            'reviewOnly': true,
          },
        ),
      );
      expect(result.isError, isNot(true));
      expect(result.structuredContent!['measurementReview'], h.review.toJson());
      expect(result.structuredContent!['reviewDigest'], h.review.digest.hex);
      expect(h.archives, isEmpty);
      for (final selectors in [
        {'environmentSlug': 'staging'},
        {'runtimePlane': 'sandbox'},
        {'environmentTargetId': 42},
        {'contractVersion': 2},
        {'sourceKind': 'screen'},
      ]) {
        h.calls.clear();
        final partial = await connection.callTool(
          CallToolRequest(
            name: tool.name,
            arguments: {
              ...archiveArguments,
              ...selectors,
              'confirmLive': true,
              'reviewOnly': true,
            },
          ),
        );
        expect(partial.isError, true);
        expect(
          h.calls.where((call) => call.endpoint == 'surfaceArchive'),
          isEmpty,
        );
      }
    },
  );

  test(
    'archive live consent covers every actual app target and permits sandbox-only apps',
    () async {
      final h = await ArchiveHarness.create();
      addTearDown(h.dispose);
      h.review = archiveReview(warned: false);
      final connection = await h.connect();
      final denied = await connection.callTool(
        CallToolRequest(
          name: 'restage_archive_surface',
          arguments: archiveArguments,
        ),
      );
      expect(denied.isError, true);
      expect(
        h.calls.where((call) => call.endpoint == 'surfaceArchive'),
        isEmpty,
      );
      final listed = h.calls.singleWhere(
        (call) => call.method == 'listEnvironmentTargets',
      );
      expect(listed.body['appId'], 11);
      expect(listed.body.containsKey('runtimePlane'), false);
      h.hasLive = false;
      h.calls.clear();
      final sandboxConnection = await h.connect();
      final approved = await sandboxConnection.callTool(
        CallToolRequest(
          name: 'restage_archive_surface',
          arguments: archiveArguments,
        ),
      );
      expect(
        approved.isError,
        isNot(true),
        reason: (approved.content.single as TextContent).text,
      );
      expect(h.archives, hasLength(1));
    },
  );

  test(
    'archive stale digest invalid UUID and refused review cannot mutate',
    () async {
      final h = await ArchiveHarness.create();
      addTearDown(h.dispose);
      final old = h.review.digest.hex;
      h.review = archiveReview(changed: true);
      final connection = await h.connect();
      final stale = await connection.callTool(
        CallToolRequest(
          name: 'restage_archive_surface',
          arguments: {
            ...archiveArguments,
            'confirmLive': true,
            'reviewedDigest': old,
          },
        ),
      );
      expect(stale.isError, true);
      expect(stale.structuredContent!['measurementReview'], h.review.toJson());
      final invalid = await connection.callTool(
        CallToolRequest(
          name: 'restage_archive_surface',
          arguments: {
            ...archiveArguments,
            'confirmLive': true,
            'reviewedDigest': h.review.digest.hex,
            'operationId': 'invalid',
          },
        ),
      );
      expect(invalid.isError, true);
      expect((invalid.content.single as TextContent).text, contains('UUIDv4'));
      h.review = archiveReview(refused: true);
      final refused = await connection.callTool(
        CallToolRequest(
          name: 'restage_archive_surface',
          arguments: {
            ...archiveArguments,
            'confirmLive': true,
            'reviewedDigest': h.review.digest.hex,
          },
        ),
      );
      expect(refused.isError, true);
      expect(
        refused.structuredContent!['measurementReview'],
        h.review.toJson(),
      );
      expect(h.archives, isEmpty);
    },
  );

  test(
    'archive validates the admitted app organization operation and canonical response without leaking details',
    () async {
      final h = await ArchiveHarness.create();
      addTearDown(h.dispose);
      final connection = await h.connect();
      for (final review in [
        archiveReview(appId: 99),
        archiveReview(organizationId: 9),
        archiveReview(operation: 'surfaceKill'),
      ]) {
        h.review = review;
        final result = await connection.callTool(
          CallToolRequest(
            name: 'restage_archive_surface',
            arguments: {
              ...archiveArguments,
              'confirmLive': true,
              'reviewedDigest': review.digest.hex,
            },
          ),
        );
        expect(result.isError, true);
        expect(result.structuredContent, isNull);
      }
      h.malformed = {'private': 'secret detail'};
      final malformed = await connection.callTool(
        CallToolRequest(
          name: 'restage_archive_surface',
          arguments: {...archiveArguments, 'confirmLive': true},
        ),
      );
      expect(malformed.isError, true);
      expect(
        (malformed.content.single as TextContent).text,
        isNot(contains('secret detail')),
      );
      expect(h.archives, isEmpty);
    },
  );

  test(
    'archive preserves typed stale and source-loss mutation refusals',
    () async {
      final h = await ArchiveHarness.create();
      addTearDown(h.dispose);
      final connection = await h.connect();
      for (final reason in ['review_stale', 'source_loss_blocked']) {
        h.calls.clear();
        h.refusal = reason;
        final result = await connection.callTool(
          CallToolRequest(
            name: 'restage_archive_surface',
            arguments: {
              ...archiveArguments,
              'confirmLive': true,
              'reviewedDigest': h.review.digest.hex,
            },
          ),
        );
        expect(result.isError, true);
        expect((result.content.single as TextContent).text, contains(reason));
        expect(h.archives, hasLength(1));
      }
    },
  );

  test(
    'restore and delete retain their original mutation with no archive review or proceed',
    () async {
      final h = await ArchiveHarness.create();
      addTearDown(h.dispose);
      final connection = await h.connect();
      for (final tool in [
        'restage_restore_surface',
        'restage_delete_surface',
      ]) {
        h.calls.clear();
        final result = await connection.callTool(
          CallToolRequest(
            name: tool,
            arguments: {
              ...archiveArguments,
              if (tool == 'restage_delete_surface') 'confirm': 'pro',
            },
          ),
        );
        expect(result.isError, isNot(true));
        expect(
          h.calls.where((call) => call.method == 'reviewDeliveryImpact'),
          isEmpty,
        );
        final mutation = h.calls.singleWhere(
          (call) => call.endpoint == 'surfaceArchive',
        );
        expect(mutation.body.containsKey('measurementProceedBytes'), false);
      }
    },
  );
}
