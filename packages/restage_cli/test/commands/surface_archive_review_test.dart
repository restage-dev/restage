import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/api.dart';
import 'package:restage_cli/restage_cli.dart';
import 'package:restage_cli/src/io/interactive.dart' show RealInteractive;
import 'package:restage_cli/src/tui/console_command_executor.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    hide RuntimePlane;
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    as m
    show RuntimePlane;
import 'package:test/test.dart';

import '../_helpers/test_fixtures.dart';
import 'delivery_command_test.dart' show warningImpact;
import 'delivery_sample_command_test.dart' show operationId;

DeliveryMeasurementMutationReviewV1 archiveReview({
  bool warned = true,
  bool changed = false,
  bool refused = false,
  int appId = 5,
  int organizationId = 7,
  String operation = 'surfaceArchive',
}) {
  final reviews = <DeliveryMeasurementImpactReviewV1>[];
  if (warned) {
    for (final live in [false, true]) {
      final target = TargetCoordinate(
        organizationId: OrganizationId(organizationId),
        appId: ApplicationId(appId),
        environmentTargetId: EnvironmentTargetId(live ? 13 : 12),
        namedEnvironmentId: NamedEnvironmentId(live ? 23 : 22),
        runtimePlane: live ? m.RuntimePlane.live : m.RuntimePlane.sandbox,
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
    await seedCredential(store);
    return ArchiveHarness._(directory, store);
  }

  final Directory directory;
  final FileCredentialStore store;
  final stdout = StringBuffer();
  final stderr = StringBuffer();
  final calls = <({String endpoint, Map<String, dynamic> body})>[];
  DeliveryMeasurementMutationReviewV1 review = archiveReview();
  Object? malformed;
  String? refusal;
  bool hasLive = true;
  Interactive interactive = const NonInteractive();

  http.Client client() => MockClient((request) async {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final endpoint = request.url.pathSegments.last;
    calls.add((endpoint: endpoint, body: body));
    if (endpoint == 'scope') {
      return http.Response(
        jsonEncode({
          'organizationId': 7,
          'session': {
            'memberships': [
              {
                'organizationId': 7,
                'slug': 'restage',
                'name': 'Restage',
                'role': 'admin',
              },
            ],
            'workspaceExperiences': <Object>[],
          },
          'projects': [
            {'id': 1, 'slug': 'demo', 'name': 'Demo'},
          ],
          'apps': [
            {'id': 5, 'projectId': 1, 'slug': 'mobile', 'name': 'Mobile'},
          ],
          'environments': [
            {'id': 12, 'appId': 5, 'namedEnvironmentId': 22, 'slug': 'staging'},
            if (hasLive)
              {
                'id': 13,
                'appId': 5,
                'namedEnvironmentId': 23,
                'slug': 'production',
              },
          ],
          'environmentTargets': [
            {
              'environmentTargetId': 12,
              'namedEnvironmentId': 22,
              'environmentSlug': 'staging',
              'runtimePlane': 'sandbox',
            },
            if (hasLive)
              {
                'environmentTargetId': 13,
                'namedEnvironmentId': 23,
                'environmentSlug': 'production',
                'runtimePlane': 'live',
              },
          ],
          'surfaces': <Object>[],
          'apiKeys': <Object>[],
        }),
        200,
      );
    }
    expect(endpoint, 'surfaceArchive');
    if (body['method'] == 'reviewDeliveryImpact') {
      return http.Response(
        jsonEncode(malformed ?? encodeByteDataWire(review.canonicalBytes)),
        200,
      );
    }
    if (refusal != null) {
      return typedErrorResponse('SurfaceRoutingRejectedException', {
        'reason': refusal,
      });
    }
    return http.Response('null', 200);
  });

  Future<int> run(
    List<String> flags, {
    bool yes = true,
    String command = 'archive',
  }) {
    calls.clear();
    stdout.clear();
    stderr.clear();
    return RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
      httpClient: client(),
      interactiveFactory: (_) => interactive,
    ).run([
      if (yes) '--yes',
      'surface',
      command,
      'pro',
      '--type',
      'paywall',
      '--project',
      'demo',
      '--app',
      'mobile',
      '--directory',
      directory.path,
      ...flags,
    ]);
  }

  List<Map<String, dynamic>> get archiveCalls => [
    for (final call in calls)
      if (call.endpoint == 'surfaceArchive' && call.body['method'] == 'archive')
        call.body,
  ];

  Future<void> dispose() => directory.delete(recursive: true);
}

void main() {
  test(
    'registered archive retains every target review and requires exact separate acknowledgement',
    () async {
      final h = await ArchiveHarness.create();
      addTearDown(h.dispose);
      expect(await h.run([]), 1);
      expect(h.archiveCalls, isEmpty);
      expect(h.stdout.toString(), contains('Welcome experiment'));
      expect(h.stdout.toString(), contains('"runtimePlane": "live"'));
      expect(h.stdout.toString(), contains('"contractVersion": 2'));
      expect(h.stderr.toString(), contains(h.review.digest.hex));
      expect(
        await h.run([
          '--reviewed-digest',
          h.review.digest.hex,
          '--operation-id',
          operationId,
        ]),
        0,
        reason: h.stderr.toString(),
      );
      final reviewed = h.calls.singleWhere(
        (call) => call.body['method'] == 'reviewDeliveryImpact',
      );
      expect(reviewed.body.keys.toSet(), {
        'method',
        'projectSlug',
        'appSlug',
        'surfaceType',
        'surfaceSlug',
        'organizationId',
      });
      expect(reviewed.body['organizationId'], 7);
      final archived = h.archiveCalls.single;
      expect(archived.keys.toSet(), {
        ...reviewed.body.keys,
        'measurementProceedBytes',
      });
      final proceed = DeliveryMeasurementMutationProceedV1.fromCanonicalBytes(
        decodeByteDataWire(
          archived['measurementProceedBytes'],
          malformed: (detail) => FormatException(detail),
        ),
      );
      expect(proceed.operationId, operationId);
      expect(proceed.reviewDigest, h.review.digest);
      expect(proceed.acknowledgements, hasLength(2));
      expect(proceed.acknowledges(h.review), true);
      expect(h.stdout.toString(), contains('Surface archived.'));
      expect(
        await h.run([
          '--reviewed-digest',
          h.review.digest.hex,
          '--operation-id',
          'invalid',
        ]),
        1,
      );
      expect(h.archiveCalls, isEmpty);
    },
  );

  test(
    'archive review-only and stale aggregate digest never archive',
    () async {
      final h = await ArchiveHarness.create();
      addTearDown(h.dispose);
      expect(await h.run(['--review-measurement']), 0);
      expect(h.archiveCalls, isEmpty);
      expect(h.stdout.toString(), contains(h.review.digest.hex));
      final old = h.review.digest.hex;
      h.review = archiveReview(changed: true);
      expect(await h.run(['--reviewed-digest', old]), 1);
      expect(h.archiveCalls, isEmpty);
      h.review = archiveReview(refused: true);
      expect(await h.run(['--review-measurement']), 1);
      expect(h.stdout.toString(), contains('impactAuthorityUnavailable'));
      expect(h.archiveCalls, isEmpty);
    },
  );

  test(
    'archive live guard considers every app target and permits a sandbox-only app',
    () async {
      final h = await ArchiveHarness.create();
      addTearDown(h.dispose);
      h.review = archiveReview(warned: false);
      expect(await h.run([], yes: false), 1);
      expect(
        h.calls.where((call) => call.endpoint == 'surfaceArchive'),
        isEmpty,
      );
      h.hasLive = false;
      expect(await h.run([], yes: false), 0, reason: h.stderr.toString());
      expect(h.archiveCalls, hasLength(1));
    },
  );

  test(
    'archive rejects foreign app organization operation and malformed review without detail leakage',
    () async {
      final h = await ArchiveHarness.create();
      addTearDown(h.dispose);
      for (final review in [
        archiveReview(appId: 99),
        archiveReview(organizationId: 9),
        archiveReview(operation: 'surfaceKill'),
      ]) {
        h.review = review;
        expect(await h.run(['--reviewed-digest', review.digest.hex]), 2);
        expect(h.archiveCalls, isEmpty);
      }
      h.malformed = {'private': 'secret detail'};
      expect(await h.run([]), 2);
      expect(h.stderr.toString(), isNot(contains('secret detail')));
      expect(h.archiveCalls, isEmpty);
    },
  );

  test(
    'archive preserves typed stale and source-loss refusals from the existing mutation',
    () async {
      final h = await ArchiveHarness.create();
      addTearDown(h.dispose);
      for (final reason in ['review_stale', 'source_loss_blocked']) {
        h.refusal = reason;
        expect(await h.run(['--reviewed-digest', h.review.digest.hex]), 1);
        expect(h.stderr.toString(), contains(reason));
        expect(h.archiveCalls, hasLength(1));
      }
    },
  );

  test(
    'archive interactive live consent cannot acknowledge measurement warnings',
    () async {
      final h = await ArchiveHarness.create();
      addTearDown(h.dispose);
      final answers = ['yes', 'no'];
      h.interactive = RealInteractive(
        readLine: () async => answers.removeAt(0),
        stdout: h.stdout,
        isInteractiveOverride: true,
      );
      expect(await h.run([], yes: false), 1);
      expect(answers, isEmpty);
      expect(
        h.stdout.toString(),
        contains('Acknowledge every measurement warning'),
      );
      expect(h.archiveCalls, isEmpty);
    },
  );

  test(
    'restore and delete use their original operation with no archive review or proceed',
    () async {
      final h = await ArchiveHarness.create();
      addTearDown(h.dispose);
      for (final command in ['restore', 'delete']) {
        expect(
          await h.run(
            command == 'delete' ? ['--confirm', 'pro'] : [],
            command: command,
            yes: false,
          ),
          0,
        );
        expect(
          h.calls.where(
            (call) => call.body['method'] == 'reviewDeliveryImpact',
          ),
          isEmpty,
        );
        final mutation = h.calls.singleWhere(
          (call) => call.endpoint == 'surfaceArchive',
        );
        expect(mutation.body.containsKey('measurementProceedBytes'), false);
      }
    },
  );

  test(
    'console command line uses the registered archive review and exact consent path',
    () async {
      final h = await ArchiveHarness.create();
      addTearDown(h.dispose);
      final executor = ConsoleCommandExecutor(
        credentialStore: h.store,
        httpClient: h.client(),
        directory: h.directory,
      );
      final arguments = [
        '--yes',
        'surface',
        'archive',
        'pro',
        '--type',
        'paywall',
        '--project',
        'demo',
        '--app',
        'mobile',
      ];
      final denied = await executor.runCommand(arguments);
      expect(denied.exitCode, 1);
      expect(h.archiveCalls, isEmpty);
      expect(denied.stdout, contains('Welcome experiment'));
      final approved = await executor.runCommand([
        ...arguments,
        '--reviewed-digest',
        h.review.digest.hex,
        '--operation-id',
        operationId,
      ]);
      expect(approved.exitCode, 0, reason: approved.stderr);
      expect(h.archiveCalls, hasLength(1));
    },
  );
}
