import 'dart:convert';

import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

final _target = _coordinate();
final _named = PlacementKeyV1.named(slug: 'welcome');
final _generated = PlacementKeyV1.generatedDefault(
  surfaceType: DeliverySurfaceTypeId('screen'),
  slug: 'welcome',
);
final _cut = PlacementManagementCutV1(
  asOfMicros: 100,
  publicationGeneration: 2,
  publishedAsOfMicros: 90,
  validUntilMicros: 200,
  sourceDigest: 'a' * 64,
);
final _refusal = isA<CanonicalFormatException>();

void main() {
  test('all four closed request envelopes preserve canonical owner values', () {
    final history = PlacementObservedHistoryQueryV1(
      placement: _named,
      fromMicros: 0,
      untilMicros: 80,
      bucket: PlacementHistoryBucketV1.hour,
    );
    final page = PlacementDirectoryRequestV1(target: _target, limit: 200);
    final detail = PlacementReadRequestV1(
      target: _target,
      key: _named,
      observedHistory: history,
    );
    final observed = PlacementObservedHistoryReadRequestV1(
      target: _target,
      query: history,
    );
    final simulation = PlacementSimulationPageRequestV1(
      target: _target,
      keys: [_named, _generated],
      inputs: DeliverySimulationInputsV1(localNow: null),
    );
    expect(
      PlacementDirectoryRequestV1.fromCanonicalBytes(page.canonicalBytes),
      page,
    );
    expect(
      PlacementReadRequestV1.fromCanonicalBytes(detail.canonicalBytes),
      detail,
    );
    expect(
      PlacementObservedHistoryReadRequestV1.fromCanonicalBytes(
        observed.canonicalBytes,
      ),
      observed,
    );
    expect(
      PlacementSimulationPageRequestV1.fromCanonicalBytes(
        simulation.canonicalBytes,
      ),
      simulation,
    );
    expect(simulation.inputs.localNow, isNull);
    expect(
      () => PlacementDirectoryRequestV1.fromJson(
        {...page.toJson(), 'private': true},
      ),
      throwsA(_refusal),
    );
    expect(
      () => PlacementDirectoryRequestV1.fromCanonicalBytes(
        utf8.encode(' ${utf8.decode(page.canonicalBytes)}'),
      ),
      throwsA(_refusal),
    );
  });

  test('management bounds and namespace identity are enforced before IO', () {
    for (final limit in [0, 201]) {
      expect(
        () => PlacementDirectoryRequestV1(target: _target, limit: limit),
        throwsA(_refusal),
      );
    }
    for (final cursor in ['', 'padded=', 'x' * 4097]) {
      expect(
        () => PlacementDirectoryRequestV1(target: _target, cursor: cursor),
        throwsA(_refusal),
      );
    }
    expect(
      () => PlacementSimulationPageRequestV1(
        target: _target,
        keys: [_named, _named],
        inputs: DeliverySimulationInputsV1(localNow: null),
      ),
      throwsA(_refusal),
    );
    final page = _page([_item(_named), _item(_generated)]);
    expect(page.items.map((item) => item.label), ['welcome', 'welcome']);
    expect(
      page.items.map((item) => item.namespace),
      ['named', 'generatedDefault'],
    );
    expect(
      PlacementDirectoryPageV1.fromCanonicalBytes(page.canonicalBytes),
      page,
    );
  });

  test('directory absence, refusal and removed sample remain distinct', () {
    for (final status in PlacementDirectoryStatusV1.values) {
      final page = PlacementDirectoryPageV1(
        target: _target,
        cut: _cut,
        reportingCutoffMicros: 0,
        status: status,
        items: const [],
      );
      expect(
        PlacementDirectoryPageV1.fromCanonicalBytes(page.canonicalBytes).status,
        status,
      );
    }
    final removed =
        _item(_named, sampleStatus: PlacementDirectorySampleStatusV1.removed);
    expect(removed.sample, isNull);
    expect(removed.policy.revision, isNull);
    expect(removed.policy.rootPresent, isTrue);
    expect(
      removed.builds.single.freshness,
      PlacementBuildFreshnessV1.unreported,
    );
    expect(
      utf8.decode(_page([removed]).canonicalBytes),
      isNot(contains('pngBytes')),
    );
    expect(
      () => _page(
        [removed],
        status: PlacementDirectoryStatusV1.authorityUnavailable,
      ),
      throwsA(_refusal),
    );
  });

  test('target and sample authority must match all five coordinates', () {
    for (final target in [
      _coordinate(organizationId: 2),
      _coordinate(appId: 2),
      _coordinate(environmentTargetId: 2),
      _coordinate(namedEnvironmentId: 2),
      _coordinate(runtimePlane: RuntimePlane.sandbox),
    ]) {
      expect(() => _page([_item(_named, target: target)]), throwsA(_refusal));
      expect(
        () => _item(
          _named,
          sampleStatus: PlacementDirectorySampleStatusV1.bound,
          sample: _sample(target),
        ),
        throwsA(_refusal),
      );
    }
    expect(
      _item(
        _named,
        sampleStatus: PlacementDirectorySampleStatusV1.bound,
        sample: _sample(_target),
      ).sample,
      isNotNull,
    );
  });

  test('unreported builds cannot invent SDK observations or another host', () {
    final build = _build(_named);
    expect(PlacementDirectoryBuildV1.fromJson(build.toJson()), build);
    expect(
      () => PlacementDirectoryBuildV1.fromJson(
        {...build.toJson(), 'lastObservedAtMicros': 1},
      ),
      throwsA(_refusal),
    );
    final wrongMount = PlacementMountRequestV1(
      key: _named,
      hostContractHash: 'sha256:${'b' * 64}',
    );
    expect(
      () => PlacementDirectoryBuildV1.fromJson(
        {...build.toJson(), 'mount': wrongMount.toJson()},
      ),
      throwsA(_refusal),
    );
  });

  test(
      'detail observed history retains exact target, placement and cut even empty',
      () {
    PlacementReadV1 detail(PlacementObservedHistoryV1 observed) =>
        PlacementReadV1(
          target: _target,
          key: _named,
          cut: _cut,
          reportingCutoffMicros: 0,
          status: PlacementReadStatusV1.available,
          authorityStatus: PlacementAuthorityStatusV1.available,
          surfaces: const [],
          placementExperimentRequirement:
              PlacementExperimentRequirementV1.absent,
          placementExperiments: const [],
          item: _item(_named),
          observedHistory: observed,
        );
    final observed = _history();
    expect(
      PlacementReadV1.fromCanonicalBytes(detail(observed).canonicalBytes),
      detail(observed),
    );
    for (final wrong in [
      _history(target: _coordinate(appId: 2)),
      _history(key: _generated),
      _history(generation: 3),
    ]) {
      expect(() => detail(wrong), throwsA(_refusal));
    }
  });

  test(
      'simulation preserves explicit keys and refuses mixed authority or scope order',
      () {
    final decision =
        DeliveryPolicySimulationV1(scope: _scope(_named), reason: 'no_default');
    final probe = PlacementSimulationProbeV1(
      key: _named,
      reason: 'no_default',
      decisions: [decision],
    );
    final result = PlacementSimulationPageV1(
      target: _target,
      cut: _cut,
      status: PlacementDirectoryStatusV1.available,
      evaluatedKeys: [_named],
      probes: [probe],
    );
    expect(
      PlacementSimulationPageV1.fromCanonicalBytes(result.canonicalBytes),
      result,
    );
    expect(
      () => PlacementSimulationProbeV1(
        key: _generated,
        reason: 'no_default',
        decisions: [decision],
      ),
      throwsA(_refusal),
    );
    expect(
      () => PlacementSimulationPageV1(
        target: _coordinate(appId: 2),
        cut: _cut,
        status: PlacementDirectoryStatusV1.available,
        evaluatedKeys: [_named],
        probes: [probe],
      ),
      throwsA(_refusal),
    );
  });
}

TargetCoordinate _coordinate({
  int organizationId = 1,
  int appId = 1,
  int environmentTargetId = 1,
  int namedEnvironmentId = 1,
  RuntimePlane runtimePlane = RuntimePlane.live,
}) =>
    TargetCoordinate(
      organizationId: OrganizationId(organizationId),
      appId: ApplicationId(appId),
      environmentTargetId: EnvironmentTargetId(environmentTargetId),
      namedEnvironmentId: NamedEnvironmentId(namedEnvironmentId),
      runtimePlane: runtimePlane,
    );

DeliveryPolicyScopeV1 _scope(PlacementKeyV1 key, {TargetCoordinate? target}) =>
    DeliveryPolicyScopeV1(
      root: DeliveryRootIdentityV1.placement(
        PlacementIdentityV1(target: target ?? _target, key: key),
      ),
      family: const DeliveryFamilySelectorV1.none(),
    );

PlacementDirectoryBuildV1 _build(PlacementKeyV1 key) {
  final host = SurfaceHostContractV1(
    hosting: SurfaceHostingV1(
      contentKind: SurfaceContentKindV1.single,
      presentation: SurfacePresentationV1.inline,
    ),
    providedContext: const SurfaceScreenHostDataSchema.empty(),
    handledEvents: SurfaceScreenEventSchema(events: const []),
  );
  return PlacementDirectoryBuildV1(
    appBuildContractHash: 'sha256:${'a' * 64}',
    platform: 'ios',
    mount: PlacementMountRequestV1(
      key: key,
      hostContractHash: host.contentHash,
      defaultSurface: key.isGeneratedDefault
          ? DeliverySurfaceLocatorV1(
              surfaceType: key.surfaceType!,
              slug: key.slug,
              family: const DeliveryFamilySelectorV1.general(),
            )
          : null,
    ),
    hostContract: host,
    freshness: PlacementBuildFreshnessV1.unreported,
  );
}

PlacementDirectoryItemV1 _item(
  PlacementKeyV1 key, {
  TargetCoordinate? target,
  PlacementDirectorySampleStatusV1 sampleStatus =
      PlacementDirectorySampleStatusV1.absent,
  PlacementScreenSampleRefV1? sample,
}) =>
    PlacementDirectoryItemV1(
      key: key,
      policy: DeliveryPolicyReadV1(scope: _scope(key, target: target)),
      builds: [_build(key)],
      sampleStatus: sampleStatus,
      sample: sample,
      canEdit: false,
      canManageSamples: false,
    );

PlacementDirectoryPageV1 _page(
  List<PlacementDirectoryItemV1> items, {
  PlacementDirectoryStatusV1 status = PlacementDirectoryStatusV1.available,
}) =>
    PlacementDirectoryPageV1(
      target: _target,
      cut: _cut,
      reportingCutoffMicros: 0,
      status: status,
      items: items,
    );

PlacementScreenSampleRefV1 _sample(TargetCoordinate target) =>
    PlacementScreenSampleRefV1(
      target: target,
      sampleId: '12345678-1234-4234-8234-123456789012',
      appBuildContractHash: 'sha256:${'a' * 64}',
      manifestDigest: 'sha256:${'b' * 64}',
      imageSha256: 'sha256:${'c' * 64}',
      screenLabel: 'Welcome',
      bindingRevision: 1,
    );

PlacementObservedHistoryV1 _history({
  TargetCoordinate? target,
  PlacementKeyV1? key,
  int generation = 2,
}) =>
    PlacementObservedHistoryV1(
      target: target ?? _target,
      placement: key ?? _named,
      coverage: PlacementHistoryCoverageV1.unavailableHistoric,
      requestedFromMicros: 0,
      requestedUntilMicros: 80,
      retainedFromMicros: null,
      publicationGeneration: generation,
      publishedAsOfMicros: 90,
      validUntilMicros: 200,
      rows: const [],
    );
