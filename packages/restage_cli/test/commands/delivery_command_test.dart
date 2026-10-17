import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/api.dart';
import 'package:restage_cli/src/commands/delivery_command.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    hide RuntimePlane;
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../_helpers/test_fixtures.dart';
import 'delivery_sample_command_test.dart' show operationId, sampleTarget;

DeliveryPolicyScopeV1 placementScope({
  PlacementKeyV1? key,
  bool live = false,
}) => DeliveryPolicyScopeV1(
  root: DeliveryRootIdentityV1.placement(
    PlacementIdentityV1(
      target: sampleTarget(live: live),
      key: key ?? PlacementKeyV1.named(slug: 'welcome'),
    ),
  ),
  family: const DeliveryFamilySelectorV1.none(),
);

DeliveryPolicyScopeV1 surfaceScope({bool live = false}) =>
    DeliveryPolicyScopeV1(
      root: DeliveryRootIdentityV1.surface(
        PublishedSurfaceIdentityV1(
          target: sampleTarget(live: live),
          surfaceId: SurfaceId('welcome'),
        ),
      ),
      family: DeliveryFamilySelectorV1.screenContract(contractVersion: 2),
    );

DeliveryPolicyPlanV1 policyPlan(
  DeliveryPolicyScopeV1 scope,
) => DeliveryPolicyPlanV1(
  scope: scope,
  snapshots: [
    DeliveryPolicySnapshotInputV1(
      effectiveFromLocal: null,
      documentCanonicalBytes: CanonicalJsonCodec.encode({'rules': <Object>[]}),
    ),
    DeliveryPolicySnapshotInputV1(
      effectiveFromLocal: LocalCivilDateTimeV1.parse('2027-01-04T09:30:00'),
      documentCanonicalBytes: CanonicalJsonCodec.encode({'rules': <Object>[]}),
    ),
  ],
);

DeliveryPolicyRevisionRefV1 policyRevision(
  DeliveryPolicyScopeV1 scope,
  int ordinal,
) => DeliveryPolicyRevisionRefV1(
  scope: scope,
  ordinal: ordinal,
  revisionId: 'revision-$ordinal',
  canonicalPolicyDigest: CanonicalDigest('a' * 64),
);

DeliveryPolicyReadV1 policyRead(DeliveryPolicyScopeV1 scope, int ordinal) =>
    DeliveryPolicyReadV1(
      scope: scope,
      headId: 9,
      revision: policyRevision(scope, ordinal),
      policyCanonicalBytes: CanonicalJsonCodec.encode({'rules': <Object>[]}),
      publishedAtMicros: 100,
    );

DeliveryPolicyReviewV1 policyReview(
  DeliveryPolicyScopeV1 scope, {
  int? expectedHeadOrdinal,
  String reason = 'Restore complete plan',
  DeliveryMeasurementImpactReviewV1? impact,
}) => DeliveryPolicyReviewV1(
  scope: scope,
  expectedHeadOrdinal: expectedHeadOrdinal,
  candidatePlan: policyPlan(scope),
  candidateRevision: policyRevision(scope, (expectedHeadOrdinal ?? 0) + 1),
  reviewedAuthorityDigest: CanonicalDigest('b' * 64),
  measurementImpact:
      impact ??
      DeliveryMeasurementImpactReviewV1(
        scope: scope,
        operation: 'policyPublish',
        dependencyDigest: CanonicalDigest('c' * 64),
      ),
  reason: reason,
  reviewedAtMicros: 120,
);

DeliveryMeasurementImpactReviewV1 warningImpact(DeliveryPolicyScopeV1 scope) =>
    DeliveryMeasurementImpactReviewV1(
      scope: scope,
      operation: 'policyPublish',
      dependencyDigest: CanonicalDigest('d' * 64),
      affectedSources: [
        DeliveryMeasurementSourceImpactV1(
          experimentReference: ExperimentLiveReadReferenceV1.fromJson({
            'kind': 'experimentLiveReadReference',
            'target': scope.target.toJson(),
            'experimentId': 'welcome-experiment',
            'activationOrdinal': 2,
            'receiptDigest': 'e' * 64,
          }),
          experimentName: 'Welcome experiment',
          metricName: 'Completed welcome',
          metricBindingReference:
              ExperimentExactMetricBindingReferenceV1.fromJson({
                'canonicalDigest': 'f' * 64,
                'metricBindingId': 'completed-welcome',
                'metricBindingRevisionId': 'completed-welcome-2',
                'semanticDigest': 'a' * 64,
              }, path: 'metricBindingReference'),
          affectedPublications: const [],
          warningCode: 'metricSourceUnavailable',
        ),
      ],
    );

PlacementManagementCutV1 directoryCut() => PlacementManagementCutV1(
  asOfMicros: 200,
  publicationGeneration: 7,
  publishedAsOfMicros: 190,
  validUntilMicros: 300,
  sourceDigest: 'd' * 64,
);

void main() {
  test(
    'review retains named metric warnings and publish sends only the explicit exact acknowledgement',
    () async {
      final h = await DeliveryCommandHarness.create();
      addTearDown(h.dispose);
      final scope = placementScope();
      final impact = warningImpact(scope);
      final review = policyReview(scope, impact: impact);
      h.respond(review);
      final plan = await h.file(
        'plan.json',
        review.candidatePlan.canonicalBytes,
      );
      final path = '${h.directory.path}/review.json';
      expect(
        await h.run([
          'plan',
          'review',
          '--plan',
          plan,
          '--expect-no-head',
          '--reason',
          review.reason,
          '--out',
          path,
        ]),
        0,
      );
      expect(h.lastJson['measurementImpact'], impact.toJson());
      expect(h.stdout.toString(), contains('Welcome experiment'));
      expect(h.stdout.toString(), contains('Completed welcome'));
      h.respond(
        const DeliveryPolicyPublishResultV1.refused(
          'measurementAcknowledgementRequired',
        ),
      );
      final args = [
        'plan',
        'publish',
        '--review',
        path,
        '--operation-id',
        operationId,
      ];
      expect(await h.run(args, yes: true), 1);
      expect(
        DeliveryPolicyPublishRequestV1.fromCanonicalBytes(
          h.lastRequestBytes,
        ).measurementAcknowledgement,
        isNull,
      );
      final acknowledgement = DeliveryMeasurementImpactAcknowledgementV1(
        reviewDigest: impact.digest,
        warningCodes: impact.warningCodes,
      );
      final ackPath = await h.file(
        'acknowledgement.json',
        acknowledgement.canonicalBytes,
      );
      h.respond(
        DeliveryPolicyPublishResultV1.applied(review.candidateRevision),
      );
      expect(await h.run([...args, '--acknowledgement', ackPath]), 0);
      final sent = DeliveryPolicyPublishRequestV1.fromCanonicalBytes(
        h.lastRequestBytes,
      );
      expect(sent.measurementAcknowledgement, acknowledgement);
      expect(sent.reviewRef, review.reviewRef);
    },
  );

  test(
    'registered fit preserves exact publication and opaque page continuation',
    () async {
      final h = await DeliveryCommandHarness.create();
      addTearDown(h.dispose);
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
      final request = DeliveryPolicyFitReadRequestV1.forPublication(
        publication: publication,
        pageSize: 2,
        cursor: 'opaque-fit-start',
      );
      final result = DeliveryPolicyFitReadV1(
        request: request,
        authorityDigest: CanonicalDigest('f' * 64),
        entries: [
          DeliveryPolicyFitEntryV1(
            scope: placementScope(),
            publication: publication,
            verdictCanonicalBytes: CanonicalJsonCodec.encode({
              'accepted': true,
            }),
          ),
        ],
        nextCursor: 'opaque-fit-next',
      );
      h.respond(result);
      final path = await h.file('publication.json', publication.canonicalBytes);
      expect(
        await h.run([
          'plan',
          'fit',
          '--publication',
          path,
          '--page-size',
          '2',
          '--cursor',
          'opaque-fit-start',
        ]),
        0,
      );
      expect(
        DeliveryPolicyFitReadRequestV1.fromCanonicalBytes(h.lastRequestBytes),
        request,
      );
      expect(h.lastJson, result.toJson());
    },
  );

  test(
    'registered reads preserve equal-slug namespaces and exact surface family',
    () async {
      final h = await DeliveryCommandHarness.create();
      addTearDown(h.dispose);
      final named = placementScope();
      final defaultKey = PlacementKeyV1.parse('default:paywall:welcome');
      final fallback = placementScope(key: defaultKey);
      final screen = surfaceScope();
      final page = PlacementDirectoryPageV1(
        target: sampleTarget(),
        cut: directoryCut(),
        reportingCutoffMicros: 80,
        status: PlacementDirectoryStatusV1.available,
        items: const [],
        nextCursor: 'opaque-directory-continuation',
      );
      h.respond(page);
      expect(
        await h.run([
          'placements',
          'list',
          '--page-size',
          '2',
          '--cursor',
          'opaque-directory-start',
        ]),
        0,
      );
      final directory = PlacementDirectoryRequestV1.fromCanonicalBytes(
        h.lastRequestBytes,
      );
      expect(directory.limit, 2);
      expect(directory.cursor, 'opaque-directory-start');
      expect(h.lastJson, page.toJson());
      for (final scope in [named, fallback, screen]) {
        h.respond(DeliveryPolicyReadV1(scope: scope));
        final path = await h.file('scope.json', scope.canonicalBytes);
        expect(await h.run(['plan', 'read', '--scope', path]), 0);
        expect(
          DeliveryPolicyReadRequestV1.fromCanonicalBytes(
            h.lastRequestBytes,
          ).scope,
          scope,
        );
        expect(h.lastJson['scope'], scope.toJson());
      }
      expect(named.root.placement!.key, isNot(fallback.root.placement!.key));
      final timeline = DeliveryPolicyTimelineV1(
        policy: policyRead(screen, 3),
        plan: policyPlan(screen),
      );
      h.respond(timeline);
      final path = await h.file('screen.json', screen.canonicalBytes);
      expect(await h.run(['plan', 'timeline', '--scope', path]), 0);
      expect(h.lastJson, timeline.toJson());
      expect(h.calls.map((c) => c['method']), [
        'readPage',
        'readPolicy',
        'readPolicy',
        'readPolicy',
        'readTimeline',
      ]);
    },
  );

  test(
    'history keeps complete revisions and observed-history UTC coverage',
    () async {
      final h = await DeliveryCommandHarness.create();
      addTearDown(h.dispose);
      final scope = placementScope();
      final history = DeliveryPolicyHistoryV1(
        scope: scope,
        revisions: [policyRead(scope, 5), policyRead(scope, 4)],
        nextBeforeOrdinal: 4,
      );
      h.respond(history);
      expect(
        await h.run([
          'plan',
          'history',
          '--placement',
          'named:welcome',
          '--before-ordinal',
          '6',
          '--page-size',
          '2',
        ]),
        0,
      );
      final request = DeliveryPolicyHistoryRequestV1.fromCanonicalBytes(
        h.lastRequestBytes,
      );
      expect(request.beforeOrdinal, 6);
      expect(request.pageSize, 2);
      expect(h.lastJson, history.toJson());
      final query = PlacementObservedHistoryQueryV1(
        placement: scope.root.placement!.key,
        fromMicros: 10,
        untilMicros: 100,
        bucket: PlacementHistoryBucketV1.hour,
      );
      final observed = PlacementObservedHistoryV1(
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
      );
      h.respond(observed);
      final queryPath = await h.file('query.json', query.canonicalBytes);
      expect(await h.run(['observed-history', '--query', queryPath]), 0);
      expect(
        PlacementObservedHistoryReadRequestV1.fromCanonicalBytes(
          h.lastRequestBytes,
        ).query,
        query,
      );
      expect(h.lastJson, observed.toJson());
      expect(h.lastJson['basis'], 'authenticatedFirstPaint');
      h.respond(
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
          observedHistory: observed,
        ),
      );
      expect(
        await h.run([
          'placements',
          'show',
          '--key',
          'named:welcome',
          '--query',
          queryPath,
        ]),
        0,
      );
      expect(h.lastJson['status'], 'notFound');
      expect(h.lastJson['observedHistory'], observed.toJson());
    },
  );

  test(
    'simulation sends original built-ins and preserves both stages without identity enrollment',
    () async {
      final h = await DeliveryCommandHarness.create();
      addTearDown(h.dispose);
      final placement = placementScope();
      final surface = surfaceScope();
      final inputs = DeliverySimulationInputsV1(
        localNow: LocalCivilDateTimeV1.parse('2027-01-04T09:30:00'),
        sdkBuiltInsCanonicalBytes: CanonicalJsonCodec.encode({
          'channel': 'organic',
          'daysSinceInstall': 8,
        }),
        assignmentContextCanonicalBytes: CanonicalJsonCodec.encode({
          'platform': 'ios',
        }),
      );
      final path = await h.file('inputs.json', inputs.canonicalBytes);
      final decisions = [
        DeliveryPolicySimulationV1(scope: placement, reason: 'selected'),
        DeliveryPolicySimulationV1(scope: surface, reason: 'cohortUnavailable'),
      ];
      final result = PlacementSimulationPageV1(
        target: sampleTarget(),
        cut: directoryCut(),
        status: PlacementDirectoryStatusV1.available,
        evaluatedKeys: [placement.root.placement!.key],
        probes: [
          PlacementSimulationProbeV1(
            key: placement.root.placement!.key,
            reason: 'cohortUnavailable',
            decisions: decisions,
          ),
        ],
        nextCursor: 'opaque-probe-continuation',
      );
      h.respond(result);
      expect(
        await h.run([
          'simulate',
          '--key',
          'named:welcome',
          '--inputs',
          path,
          '--cursor',
          'opaque-probe-start',
        ]),
        0,
      );
      final request = PlacementSimulationPageRequestV1.fromCanonicalBytes(
        h.lastRequestBytes,
      );
      expect(request.inputs, inputs);
      expect(request.inputs.analyticsAnonymousId, isNull);
      expect(request.cursor, 'opaque-probe-start');
      expect(h.lastJson, result.toJson());
      expect(h.lastJson.toString(), isNot(contains('assignmentReceipt')));
      h.respond(decisions.last);
      final scope = await h.file('scope.json', surface.canonicalBytes);
      expect(
        await h.run(['plan', 'simulate', '--scope', scope, '--inputs', path]),
        0,
      );
      expect(
        DeliveryPolicySimulationRequestV1.fromCanonicalBytes(
          h.lastRequestBytes,
        ).inputs,
        inputs,
      );
      expect(h.lastJson['reason'], 'cohortUnavailable');
      expect(h.lastJson.containsKey('allocationId'), isFalse);
    },
  );

  test(
    'publish sends only the immutable reviewed ref and replay identity after the plan file changes',
    () async {
      final h = await DeliveryCommandHarness.create();
      addTearDown(h.dispose);
      final review = policyReview(
        placementScope(),
        reason: 'First complete policy',
      );
      final planPath = await h.file(
        'plan.json',
        review.candidatePlan.canonicalBytes,
      );
      final reviewPath = '${h.directory.path}/review.json';
      h.respond(review);
      expect(
        await h.run([
          'plan',
          'review',
          '--plan',
          planPath,
          '--expect-no-head',
          '--reason',
          review.reason,
          '--out',
          reviewPath,
        ]),
        0,
      );
      expect(await File(reviewPath).readAsBytes(), review.canonicalBytes);
      await File(planPath).writeAsString('{"edited":"after review"}');
      h.respond(
        DeliveryPolicyPublishResultV1.applied(review.candidateRevision),
      );
      expect(
        await h.run([
          'plan',
          'publish',
          '--review',
          reviewPath,
          '--operation-id',
          operationId,
        ]),
        0,
      );
      final request = DeliveryPolicyPublishRequestV1.fromCanonicalBytes(
        h.lastRequestBytes,
      );
      expect(request.reviewRef, review.reviewRef);
      expect(request.operationId, operationId);
      expect(request.toJson().containsKey('candidatePlan'), isFalse);
      expect(h.calls.where((c) => c['method'] == 'publish'), hasLength(1));
      h.respond(
        DeliveryPolicyPublishResultV1.conflict(policyRevision(review.scope, 2)),
      );
      expect(
        await h.run([
          'plan',
          'publish',
          '--review',
          reviewPath,
          '--operation-id',
          operationId,
        ]),
        1,
      );
      expect(h.lastJson['outcome'], 'conflict');
      final undo = policyReview(review.scope, expectedHeadOrdinal: 2);
      h.respond(undo);
      expect(
        await h.run([
          'plan',
          'undo',
          '--placement',
          'named:welcome',
          '--expected-head-ordinal',
          '2',
          '--restore-ordinal',
          '1',
          '--reason',
          undo.reason,
          '--out',
          reviewPath,
        ]),
        0,
      );
      expect(
        DeliveryPolicyUndoReviewRequestV1.fromCanonicalBytes(
          h.lastRequestBytes,
        ).restoreOrdinal,
        1,
      );
      expect(await File(reviewPath).readAsBytes(), undo.canonicalBytes);
    },
  );

  test(
    'publish live guard refuses before mutation and accepts the same valid reviewed request',
    () async {
      final h = await DeliveryCommandHarness.create();
      addTearDown(h.dispose);
      final review = policyReview(placementScope(live: true));
      final path = await h.file('review.json', review.canonicalBytes);
      final args = [
        'plan',
        'publish',
        '--review',
        path,
        '--operation-id',
        operationId,
      ];
      expect(await h.run(args, live: true), 1);
      expect(h.calls, isEmpty);
      h.respond(
        DeliveryPolicyPublishResultV1.applied(review.candidateRevision),
      );
      expect(await h.run(args, live: true, yes: true), 0);
      expect(h.calls.single['method'], 'publish');
      expect(h.calls.single['runtimePlane'], 'live');
    },
  );

  test('a publish held for a fit is sent again confirmed with --yes', () async {
    final h = await DeliveryCommandHarness.create();
    addTearDown(h.dispose);
    final review = policyReview(placementScope(live: true));
    final path = await h.file('review.json', review.canonicalBytes);
    h
      ..holdForFit = true
      ..respond(
        DeliveryPolicyPublishResultV1.applied(review.candidateRevision),
      );

    final code = await h.run(
      ['plan', 'publish', '--review', path, '--operation-id', operationId],
      live: true,
      yes: true,
    );

    expect(code, 0, reason: h.stderr.toString());
    expect(h.calls.map((c) => c['acceptFit']), [null, true]);
    expect(h.calls.last['requestBytes'], h.calls.first['requestBytes']);
  });

  test(
    'wrong target response is refused and unauthorized response stays an error',
    () async {
      final h = await DeliveryCommandHarness.create();
      addTearDown(h.dispose);
      h.respond(DeliveryPolicyReadV1(scope: placementScope(live: true)));
      expect(await h.run(['plan', 'read', '--placement', 'named:welcome']), 2);
      h.refusal = http.Response(
        '{"className":"SurfaceRoutingRejectedException","data":{"reason":"notAuthorized"}}',
        400,
      );
      expect(await h.run(['plan', 'read', '--placement', 'named:welcome']), 1);
      expect(h.stderr.toString(), contains('notAuthorized'));
    },
  );
}

class DeliveryCommandHarness {
  DeliveryCommandHarness(this.directory, this.store);
  final Directory directory;
  final FileCredentialStore store;
  final stdout = StringBuffer();
  final stderr = StringBuffer();
  final calls = <Map<String, dynamic>>[];
  final responses = <List<int>>[];
  http.Response? refusal;

  /// Whether a call without `acceptFit` is held for a fit confirmation.
  bool holdForFit = false;
  Map<String, Object?> get lastJson =>
      jsonDecode(stdout.toString().trim().split('\n').last)
          as Map<String, Object?>;
  Uint8List get lastRequestBytes => decodeByteDataWire(
    calls.last['requestBytes'],
    malformed: FormatException.new,
    maximumBytes: kMaximumRoutingDocumentBytes,
  );

  static Future<DeliveryCommandHarness> create() async {
    final directory = await Directory.systemTemp.createTemp(
      'delivery-command-',
    );
    final store = FileCredentialStore('${directory.path}/credentials');
    await seedCredential(store);
    return DeliveryCommandHarness(directory, store);
  }

  void respond(CanonicalValue value) => responses.add(value.canonicalBytes);
  Future<String> file(String name, List<int> bytes) async {
    final file = File('${directory.path}/$name');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  Future<int?> run(List<String> args, {bool live = false, bool yes = false}) {
    final client = mockHttpClient((request) {
      expect(request.url.path, anyOf('/deliveryPolicy', '/placementDirectory'));
      calls.add(jsonDecode(request.body) as Map<String, dynamic>);
      if (refusal != null) return refusal!;
      if (holdForFit && calls.last['acceptFit'] != true) {
        return http.Response(
          jsonEncode({
            'className': 'SurfaceFitNeedsConfirmationException',
            'data': {
              '__className__': 'SurfaceFitNeedsConfirmationException',
              'verdict': 'noneFit',
              'environment': 'production',
              'builds': {'items': <Object>[]},
            },
          }),
          400,
        );
      }
      expect(responses, isNotEmpty, reason: 'Unexpected extra delivery RPC');
      return http.Response(
        jsonEncode(encodeByteDataWire(responses.removeAt(0))),
        200,
      );
    });
    final runner = CommandRunner<int>('restage', '')
      ..argParser.addFlag('yes', negatable: false);
    runner.addCommand(
      DeliveryCommand(
        stdout: stdout,
        stderr: stderr,
        interactive: const NonInteractive(),
        credentialStore: store,
        httpClient: client,
      ),
    );
    return runner.run([
      if (yes) '--yes',
      'delivery',
      ...args,
      '-C',
      directory.path,
      '--project',
      'p',
      '--app',
      'a',
      '--env',
      live ? 'production' : 'staging',
      '--plane',
      live ? 'live' : 'sandbox',
      '--json',
    ]);
  }

  Future<void> dispose() => directory.delete(recursive: true);
}
