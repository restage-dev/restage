import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:restage_cli/api.dart';
import 'package:restage_cli/restage_cli.dart';
import 'package:restage_cli/src/tui/console_command_executor.dart';
import 'package:restage_cli/src/tui/console_models.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    hide RuntimePlane;
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    as m
    show RuntimePlane;
import 'package:test/test.dart';

import '../_helpers/test_fixtures.dart';
import '../_helpers/publication_fixtures.dart';
import 'delivery_command_test.dart' show warningImpact;
import 'delivery_sample_command_test.dart' show operationId;

TargetCoordinate surfaceReviewTarget({bool live = false, int appId = 5}) =>
    TargetCoordinate(
      organizationId: OrganizationId(7),
      appId: ApplicationId(appId),
      environmentTargetId: EnvironmentTargetId(live ? 13 : 12),
      namedEnvironmentId: NamedEnvironmentId(live ? 23 : 22),
      runtimePlane: live ? m.RuntimePlane.live : m.RuntimePlane.sandbox,
    );

DeliveryMeasurementMutationReviewV1 surfaceMutationReview(
  String operation, {
  bool live = false,
  bool warned = true,
  bool changed = false,
  bool refused = false,
  int appId = 5,
}) {
  final reviews = <DeliveryMeasurementImpactReviewV1>[];
  if (warned) {
    for (final slug in ['welcome', 'returning']) {
      final scope = DeliveryPolicyScopeV1(
        root: DeliveryRootIdentityV1.placement(
          PlacementIdentityV1(
            target: surfaceReviewTarget(live: live, appId: appId),
            key: PlacementKeyV1.named(slug: slug),
          ),
        ),
        family: const DeliveryFamilySelectorV1.none(),
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

DeliveryMeasurementMutationReviewV1 exactVersionKillReview({
  bool live = false,
  int activationOrdinal = 2,
  bool refused = false,
}) {
  final scope = DeliveryPolicyScopeV1(
    root: DeliveryRootIdentityV1.surface(
      PublishedSurfaceIdentityV1(
        target: surfaceReviewTarget(live: live),
        surfaceId: SurfaceId('pro'),
      ),
    ),
    family: const DeliveryFamilySelectorV1.general(),
  );
  final publications = [
    for (final revision in [1, 3])
      DeliveryPublicationReferenceV1(
        surface: DeliverySurfaceReferenceV1(
          surfaceIdentity: scope.root.surface!,
          family: scope.family,
        ),
        publishedVersion: revision,
        payloadFormatVersion: 2,
        contentHash: CanonicalDigest('$revision' * 64),
      ),
  ];
  final source = warningImpact(scope).affectedSources.single;
  return DeliveryMeasurementMutationReviewV1(
    operation: 'surfaceKill',
    reviews: [
      DeliveryMeasurementImpactReviewV1(
        scope: scope,
        operation: 'surfaceKill',
        dependencyDigest: CanonicalDigest('a' * 64),
        expectedLivePublications: [publications.last],
        affectedSources: [
          DeliveryMeasurementSourceImpactV1.fromJson({
            ...source.toJson(),
            'experimentReference': {
              ...source.experimentReference.toJson(),
              'activationOrdinal': activationOrdinal,
            },
            'affectedPublications': [
              for (final publication in publications) publication.toJson(),
            ],
            'warningCode': 'scheduledOutputLost',
          }),
        ],
      ),
    ],
    dependencyDigest: CanonicalDigest('b' * 64),
    refusalCodes: refused ? ['impactAuthorityUnavailable'] : const [],
  );
}

Map<String, Object?> surfaceMutationResponse(int revision) => {
  'family': {
    'surfaceType': 'paywall',
    'surfaceSlug': 'pro',
    'sourceKind': 'paywall',
  },
  'publishedRevision': revision,
  'activePublishedRevisionBefore': 3,
  'activePublishedRevisionAfter': revision,
  'identityFrozenAfter': false,
};

class SurfaceReviewHarness {
  SurfaceReviewHarness._(this.directory, this.store);
  static Future<SurfaceReviewHarness> create() async {
    final directory = await Directory.systemTemp.createTemp('surface-review-');
    final store = FileCredentialStore('${directory.path}/credentials');
    await seedCredential(store);
    return SurfaceReviewHarness._(directory, store);
  }

  final Directory directory;
  final FileCredentialStore store;
  final stdout = StringBuffer();
  final stderr = StringBuffer();
  final calls = <Map<String, dynamic>>[];
  late DeliveryMeasurementMutationReviewV1 review;
  String? refusal;
  Interactive interactive = const NonInteractive();

  http.Client client() => mockHttpClient((request) {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    calls.add(body);
    switch (body['method']) {
      case 'reviewDeliveryImpact':
        return http.Response(
          jsonEncode(encodeByteDataWire(review.canonicalBytes)),
          200,
        );
      case 'surfaceStatus':
        return http.Response(
          jsonEncode({
            'surfaceType': 'paywall',
            'surfaceSlug': 'pro',
            'environmentSlug': 'staging',
            'liveVersion': 3,
            'locked': false,
            'deliveryShape': 'blob',
            'draftOrigin': 'code',
            'sourceKind': 'paywall',
            'versions': [
              for (final version in [1, 3])
                {
                  'version': version,
                  'publishedAt': '2026-06-01T10:00:00.000Z',
                  'contentHash': 'hash-$version',
                  'isActive': version == 3,
                  'deliveryMode': 'blob',
                },
            ],
          }),
          200,
        );
      case 'rollbackPreflight':
        return http.Response(
          jsonEncode({
            'surfaceType': 'paywall',
            'surfaceSlug': 'pro',
            'environmentSlug': 'staging',
            'toVersion': 1,
            'classification': 'compatible',
            'blockingChanges': <Object>[],
          }),
          200,
        );
      case 'activateSurface':
      case 'rollbackSurface':
        if (refusal != null) {
          return typedErrorResponse('SurfaceRoutingRejectedException', {
            'reason': refusal,
          });
        }
        return http.Response(
          jsonEncode(
            surfaceMutationResponse(
              body['publishedRevision'] as int? ??
                  body['toVersion'] as int? ??
                  3,
            ),
          ),
          200,
        );
      case 'killSurface':
      case 'setSurfaceLock':
        if (refusal != null) {
          return typedErrorResponse('SurfaceRoutingRejectedException', {
            'reason': refusal,
          });
        }
        return http.Response(
          jsonEncode({
            'surfaceType': 'paywall',
            'surfaceSlug': 'pro',
            'frozen': false,
            'affectedFamilies': <Object>[],
          }),
          200,
        );
      default:
        fail('Unexpected surface call ${body['method']}');
    }
  }, withDefaultSurfaceReview: false);

  Future<int> run(String command, List<String> flags, {bool live = false}) {
    stdout.clear();
    stderr.clear();
    calls.clear();
    return RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
      httpClient: client(),
      interactiveFactory: (_) => interactive,
    ).run([
      '--yes',
      'surface',
      command,
      'pro',
      '--type',
      'paywall',
      '--project',
      'demo',
      '--app',
      'mobile',
      '--env',
      live ? 'production' : 'staging',
      '--plane',
      live ? 'live' : 'sandbox',
      '--directory',
      directory.path,
      '--reason',
      'Reviewed surface change',
      ...flags,
    ]);
  }

  List<Map<String, dynamic>> get mutations => calls
      .where(
        (body) => const {
          'activateSurface',
          'rollbackSurface',
          'killSurface',
          'setSurfaceLock',
        }.contains(body['method']),
      )
      .toList();
  Future<void> dispose() => directory.delete(recursive: true);
}

void main() {
  test(
    'kill exposes exact-version impact and requires its current acknowledgement',
    () async {
      final h = await SurfaceReviewHarness.create();
      addTearDown(h.dispose);
      h.review = exactVersionKillReview();
      expect(await h.run('kill', ['--yes']), 1);
      expect(h.mutations, isEmpty);
      for (final detail in [
        'Welcome experiment',
        'welcome-experiment',
        'Completed welcome',
        'scheduledOutputLost',
        '"publishedVersion": 1',
        '"publishedVersion": 3',
        'stops fresh experimental delivery',
        'saved results are unchanged',
      ]) {
        expect(h.stdout.toString(), contains(detail));
      }
      expect(h.stdout.toString(), isNot(contains('expectedLivePolicy')));
      final previous = h.review.digest.hex;
      h.review = exactVersionKillReview(activationOrdinal: 3);
      expect(await h.run('kill', ['--yes', '--reviewed-digest', previous]), 1);
      expect(h.mutations, isEmpty);
      expect(
        await h.run('kill', [
          '--yes',
          '--reviewed-digest',
          h.review.digest.hex,
          '--operation-id',
          operationId,
        ]),
        0,
        reason: h.stderr.toString(),
      );
      final proceed = DeliveryMeasurementMutationProceedV1.fromCanonicalBytes(
        decodeByteDataWire(
          h.mutations.single['measurementProceedBytes'],
          malformed: FormatException.new,
        ),
      );
      expect(proceed.acknowledges(h.review), true);
      expect(proceed.operationId, operationId);
      expect(proceed.acknowledgements.single.warningCodes, [
        'scheduledOutputLost',
      ]);
    },
  );
  test(
    'kill acknowledgement cannot override review or mutation refusals',
    () async {
      final h = await SurfaceReviewHarness.create();
      addTearDown(h.dispose);
      h.review = exactVersionKillReview(refused: true);
      expect(
        await h.run('kill', [
          '--yes',
          '--reviewed-digest',
          h.review.digest.hex,
        ]),
        1,
      );
      expect(h.mutations, isEmpty);
      expect(h.stderr.toString(), contains('impactAuthorityUnavailable'));
      h.review = exactVersionKillReview();
      h.refusal = 'review_stale';
      expect(
        await h.run('kill', [
          '--yes',
          '--reviewed-digest',
          h.review.digest.hex,
        ]),
        1,
      );
      expect(h.mutations, hasLength(1));
      expect(h.stderr.toString(), contains('review_stale'));
    },
  );
  test(
    'identity-wide review omits a family selected by the actual manifest',
    () async {
      final h = await SurfaceReviewHarness.create();
      addTearDown(h.dispose);
      await seedRestageConfig(h.directory, 'demo', 'mobile');
      await seedGeneratedPaywall(h.directory, slug: 'pro');
      h.review = surfaceMutationReview('surfaceKill');
      expect(
        await h.run('kill', [
          '--yes',
          '--reviewed-digest',
          h.review.digest.hex,
        ]),
        0,
        reason: h.stderr.toString(),
      );
      final reviewed = h.calls.singleWhere(
        (call) => call['method'] == 'reviewDeliveryImpact',
      );
      expect(reviewed.containsKey('sourceKind'), false);
      expect(reviewed.containsKey('contractVersion'), false);
      expect(h.mutations.single.containsKey('sourceKind'), false);
      expect(h.mutations.single.containsKey('contractVersion'), false);
    },
  );
  for (final (command, operation, method, flags, revision, frozen) in [
    (
      'publish',
      'surfaceActivate',
      'activateSurface',
      ['--revision', '3', '--source-kind', 'paywall'],
      3,
      null,
    ),
    (
      'rollback',
      'surfaceRollback',
      'rollbackSurface',
      ['--to-version', '1', '--freeze', '--source-kind', 'paywall', '--yes'],
      1,
      true,
    ),
    ('kill', 'surfaceKill', 'killSurface', ['--frozen', '--yes'], null, true),
    ('freeze', 'surfaceFreeze', 'setSurfaceLock', <String>[], null, true),
    ('unfreeze', 'surfaceFreeze', 'setSurfaceLock', <String>[], null, false),
  ]) {
    test(
      '$command registered CLI preserves every reviewed coordinate and warning acknowledgement',
      () async {
        final h = await SurfaceReviewHarness.create();
        addTearDown(h.dispose);
        h.review = surfaceMutationReview(operation);
        expect(await h.run(command, flags), 1);
        expect(h.mutations, isEmpty);
        expect(h.stdout.toString(), contains('Welcome experiment'));
        expect(
          h.stderr.toString(),
          contains('--reviewed-digest ${h.review.digest.hex}'),
        );
        expect(
          await h.run(command, [
            ...flags,
            '--reviewed-digest',
            h.review.digest.hex,
            '--operation-id',
            operationId,
          ]),
          0,
          reason: h.stderr.toString(),
        );
        final reviewCall = h.calls.singleWhere(
          (call) => call['method'] == 'reviewDeliveryImpact',
        );
        final mutation = h.mutations.single;
        expect(mutation['method'], method);
        expect(reviewCall['operation'], operation);
        expect(reviewCall['publishedRevision'], revision);
        expect(reviewCall['frozen'], frozen);
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
          expect(reviewCall[key], mutation[key], reason: key);
        }
        final proceed = DeliveryMeasurementMutationProceedV1.fromCanonicalBytes(
          decodeByteDataWire(
            mutation['measurementProceedBytes'],
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
    'review-only and stale or cross-app reviews cannot change the surface',
    () async {
      final h = await SurfaceReviewHarness.create();
      addTearDown(h.dispose);
      h.review = surfaceMutationReview('surfaceActivate');
      expect(
        await h.run('publish', ['--revision', '3', '--review-measurement']),
        0,
      );
      expect(h.mutations, isEmpty);
      final digest = h.review.digest.hex;
      h.review = surfaceMutationReview('surfaceActivate', changed: true);
      expect(
        await h.run('publish', [
          '--revision',
          '3',
          '--reviewed-digest',
          digest,
        ]),
        1,
      );
      expect(h.mutations, isEmpty);
      h.review = surfaceMutationReview('surfaceActivate', appId: 55);
      expect(
        await h.run('publish', ['--revision', '3', '--review-measurement']),
        2,
      );
      expect(h.mutations, isEmpty);
      expect(h.stderr.toString(), contains('invalid delivery result'));
    },
  );
  test(
    'original server stale refusal remains explicit after acknowledged submit',
    () async {
      final h = await SurfaceReviewHarness.create();
      addTearDown(h.dispose);
      h.review = surfaceMutationReview('surfaceActivate');
      h.refusal = 'review_stale';
      expect(
        await h.run('publish', [
          '--revision',
          '3',
          '--reviewed-digest',
          h.review.digest.hex,
        ]),
        1,
      );
      expect(h.stderr.toString(), contains('review_stale'));
    },
  );
  test(
    'confirmed production in console never acknowledges measurement warnings',
    () async {
      final h = await SurfaceReviewHarness.create();
      addTearDown(h.dispose);
      h.review = exactVersionKillReview(live: true);
      final executor = ConsoleCommandExecutor(
        credentialStore: h.store,
        httpClient: h.client(),
        directory: h.directory,
      );
      final result = await executor.kill(
        context: const ConsoleContext(
          organizationSlug: 'restage',
          project: 'demo',
          app: 'mobile',
          appId: 5,
          environment: 'production',
          namedEnvironmentId: 23,
          environmentTargetId: 13,
          runtimePlane: RuntimePlane.live,
        ),
        surface: const ConsoleSurface(
          surfaceType: 'paywall',
          slug: 'pro',
          name: 'Pro',
        ),
        reason: 'Reviewed surface change',
        frozen: false,
        confirmedProduction: true,
      );
      expect(result.exitCode, 1);
      expect(h.mutations, isEmpty);
      expect(result.stdout, contains('Welcome experiment'));
      expect(result.stdout, contains('scheduledOutputLost'));
      expect(result.stdout, contains('"publishedVersion": 3'));
      expect(result.stdout, contains('stops fresh experimental delivery'));
      expect(result.stdout, contains('saved results are unchanged'));
      final accepted = await executor.runCommand([
        '--yes',
        'surface',
        'freeze',
        'pro',
        '--type',
        'paywall',
        '--project',
        'demo',
        '--app',
        'mobile',
        '--env',
        'production',
        '--plane',
        'live',
        '--reason',
        'Reviewed surface change',
        '--reviewed-digest',
        (h.review = surfaceMutationReview(
          'surfaceFreeze',
          live: true,
        )).digest.hex,
        '--operation-id',
        operationId,
      ]);
      expect(accepted.exitCode, 0, reason: accepted.stderr);
      expect(h.mutations.single['method'], 'setSurfaceLock');
    },
  );
}
