import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:test/test.dart';

final _target = TargetCoordinate(
  organizationId: OrganizationId(7),
  appId: ApplicationId(11),
  environmentTargetId: EnvironmentTargetId(13),
  namedEnvironmentId: NamedEnvironmentId(17),
  runtimePlane: RuntimePlane.live,
);

SurfaceFunnelCountsV1 _counts({
  int eligibleRoots = 400,
  int views = 400,
  int completions = 125,
  int skips = 30,
  int dismissals = 45,
  int reachedAnotherStep = 300,
  int completeRoots = 380,
  int pendingRoots = 15,
  int unavailableRoots = 5,
}) =>
    SurfaceFunnelCountsV1.of(
      eligibleRoots: eligibleRoots,
      views: views,
      completions: completions,
      skips: skips,
      dismissals: dismissals,
      reachedAnotherStep: reachedAnotherStep,
      completeRoots: completeRoots,
      pendingRoots: pendingRoots,
      unavailableRoots: unavailableRoots,
      path: 'counts',
    );

SurfaceFunnelViewV1 _view({
  List<SurfaceFunnelVersionV1>? versions,
  String? surfaceType = 'onboarding',
}) =>
    SurfaceFunnelViewV1.of(
      target: _target,
      surfaceId: 'welcome',
      surfaceType: surfaceType,
      windowStartMicros: 1000,
      windowEndExclusiveMicros: 2000,
      asOfMicros: 2500,
      disclosureFloor: 5,
      versions: versions ??
          [
            SurfaceFunnelVersionV1.of(
              surfaceRevisionId: 'revision-1',
              revisionOrdinal: 1,
              publishedAtMicros: 900,
              status: SurfaceFunnelVersionStatusV1.available,
              disclosure: SurfaceFunnelDisclosureV1.disclosed,
              counts: _counts(),
              unattributedDismissals: 4,
              flowId: 'welcome-flow',
              flowVersion: 3,
              flowContentHash: 'abc123',
              initialStateId: 'intro',
              stateTransitions: {
                'intro': ['plan'],
                'plan': [],
              },
              steps: [
                SurfaceFunnelStepV1.of(
                  stateId: 'intro',
                  screenArtifactId: 'intro-screen',
                  screenContentHash: 'hash-intro',
                  screenVersion: 2,
                  disclosure: SurfaceFunnelDisclosureV1.disclosed,
                  counts: _counts(views: 390, completions: 0),
                  transitionTargets: const ['plan'],
                  path: 'step',
                ),
                SurfaceFunnelStepV1.of(
                  stateId: 'plan',
                  screenArtifactId: 'plan-screen',
                  screenContentHash: 'hash-plan',
                  screenVersion: 2,
                  disclosure: SurfaceFunnelDisclosureV1.belowDisclosureFloor,
                  path: 'step',
                ),
              ],
              bands: [
                SurfaceFunnelBandV1.of(
                  point: MeasurementBreakdownPointV1(
                    kindV1: MeasurementBreakdownPointKindV1.pageIndex,
                    reference: '0',
                    label: 'Intro',
                    authoredOrder: 0,
                  ),
                  disclosure: SurfaceFunnelDisclosureV1.disclosed,
                  counts: SurfaceFunnelBandCountsV1.of(
                    eligibleRoots: 400,
                    reach: 390,
                    occurrences: 410,
                    continued: 300,
                    completeRoots: 380,
                    pendingRoots: 15,
                    unavailableRoots: 5,
                    path: 'band',
                  ),
                  path: 'band',
                ),
              ],
              path: 'version',
            ),
          ],
    );

void main() {
  group('funnel rates', () {
    test('write nine places beside the exact pair they came from', () {
      final counts = _counts();
      expect(counts.conversionRate!.decimal, '0.312500000');
      expect(counts.conversionRate!.numerator, 125);
      expect(counts.conversionRate!.denominator, 400);
      expect(counts.conversionRate!.exact.numerator, BigInt.from(5));
      expect(counts.conversionRate!.exact.denominator, BigInt.from(16));
      expect(
        counts.conversionRate!.decimal.split('.').last.length,
        kExperimentResultDecimalScale,
      );
    });

    test('place a repeating figure at the nearest ninth', () {
      final rate = SurfaceFunnelRateV1.of(
        numerator: 1,
        denominator: 3,
        path: 'rate',
      );
      expect(rate.decimal, '0.333333333');
      expect(rate.exact.numerator, BigInt.one);
      expect(rate.exact.denominator, BigInt.from(3));
    });

    test('are absent rather than zero when nothing was eligible', () {
      final counts = _counts(
        eligibleRoots: 0,
        views: 0,
        completions: 0,
        skips: 0,
        dismissals: 0,
        reachedAnotherStep: 0,
        completeRoots: 0,
        pendingRoots: 0,
        unavailableRoots: 0,
      );
      expect(counts.viewRate, isNull);
      expect(counts.completionRate, isNull);
      expect(counts.conversionRate, isNull);
      expect(counts.toJson().containsKey('conversionRate'), isFalse);
    });

    test('state a band drop-off beside its continuation', () {
      final band = SurfaceFunnelBandCountsV1.of(
        eligibleRoots: 400,
        reach: 390,
        occurrences: 410,
        continued: 300,
        completeRoots: 380,
        pendingRoots: 15,
        unavailableRoots: 5,
        path: 'band',
      );
      expect(band.continuationRate!.numerator, 300);
      expect(band.dropOffRate!.numerator, 90);
      expect(band.dropOffRate!.denominator, 390);
      expect(band.dropOffRate!.decimal, '0.230769231');
    });

    test('leave a band with no authored successor stating no loss', () {
      final band = SurfaceFunnelBandCountsV1.of(
        eligibleRoots: 400,
        reach: 390,
        occurrences: 410,
        completeRoots: 400,
        pendingRoots: 0,
        unavailableRoots: 0,
        path: 'band',
      );
      expect(band.continuationRate, isNull);
      expect(band.dropOffRate, isNull);
      expect(band.reachRate!.decimal, '0.975000000');
    });
  });

  group('funnel view', () {
    test('round-trips byte for byte through the canonical codec', () {
      final view = _view();
      final decoded = SurfaceFunnelViewV1.fromCanonicalBytes(
        view.canonicalBytes,
      );
      expect(decoded, view);
      expect(decoded.canonicalBytes, view.canonicalBytes);
      expect(decoded.surfaceType, 'onboarding');
      expect(decoded.versions.single.steps.length, 2);
      expect(decoded.versions.single.bands.single.identity, contains('0'));
    });

    test('omits an unresolved surface type rather than naming one', () {
      final view = _view(surfaceType: null);
      final decoded = SurfaceFunnelViewV1.fromCanonicalBytes(
        view.canonicalBytes,
      );
      expect(decoded.surfaceType, isNull);
      expect(view.toJson().containsKey('surfaceType'), isFalse);
    });

    test('refuses a decimal that disagrees with its counts', () {
      final json = _view().toJson();
      final version =
          (json['versions']! as List).single as Map<String, Object?>;
      final counts = version['counts']! as Map<String, Object?>;
      final rate = counts['conversionRate']! as Map<String, Object?>;
      counts['conversionRate'] = {...rate, 'decimal': '0.999999999'};
      expect(
        () => SurfaceFunnelViewV1.fromJson(json),
        throwsA(isA<CanonicalFormatException>()),
      );
    });

    test('refuses an exact pair that disagrees with its counts', () {
      final json = _view().toJson();
      final version =
          (json['versions']! as List).single as Map<String, Object?>;
      final counts = version['counts']! as Map<String, Object?>;
      final rate = counts['conversionRate']! as Map<String, Object?>;
      counts['conversionRate'] = {
        ...rate,
        'exact': {'denominator': '3', 'numerator': '1'},
      };
      expect(
        () => SurfaceFunnelViewV1.fromJson(json),
        throwsA(isA<CanonicalFormatException>()),
      );
    });

    test('refuses a rate stated where the counts imply none', () {
      final json = _view().toJson();
      final version =
          (json['versions']! as List).single as Map<String, Object?>;
      (version['counts']! as Map<String, Object?>)
        ..['eligibleRoots'] = 0
        ..['views'] = 0
        ..['completions'] = 0
        ..['skips'] = 0
        ..['dismissals'] = 0
        ..['reachedAnotherStep'] = 0
        ..['completeRoots'] = 0
        ..['pendingRoots'] = 0
        ..['unavailableRoots'] = 0;
      expect(
        () => SurfaceFunnelViewV1.fromJson(json),
        throwsA(isA<CanonicalFormatException>()),
      );
    });

    test('refuses counts whose coverage does not add up', () {
      expect(
        () => _counts(pendingRoots: 16),
        throwsA(isA<CanonicalFormatException>()),
      );
    });

    test('refuses a step that holds back its counts and states targets', () {
      expect(
        () => SurfaceFunnelStepV1.of(
          stateId: 'intro',
          screenArtifactId: 'intro-screen',
          screenContentHash: 'hash',
          screenVersion: 1,
          disclosure: SurfaceFunnelDisclosureV1.belowDisclosureFloor,
          transitionTargets: const ['plan'],
          path: 'step',
        ),
        throwsA(isA<CanonicalFormatException>()),
      );
    });

    test('refuses a version stating counts it says are held back', () {
      expect(
        () => SurfaceFunnelVersionV1.of(
          surfaceRevisionId: 'revision-1',
          revisionOrdinal: 1,
          publishedAtMicros: 900,
          status: SurfaceFunnelVersionStatusV1.available,
          disclosure: SurfaceFunnelDisclosureV1.belowDisclosureFloor,
          counts: _counts(),
          unattributedDismissals: 0,
          stateTransitions: const {},
          path: 'version',
        ),
        throwsA(isA<CanonicalFormatException>()),
      );
    });

    test('refuses the same published version twice', () {
      final version = _view().versions.single;
      expect(
        () => _view(versions: [version, version]),
        throwsA(isA<CanonicalFormatException>()),
      );
    });
  });

  group('funnel selection', () {
    test('accepts a bounded window and version list', () {
      final selection = SurfaceFunnelSelectionV1(
        surfaceId: 'welcome',
        windowStartMicros: 0,
        windowEndExclusiveMicros: 10,
        surfaceRevisionIds: const ['revision-1'],
      );
      expect(selection.surfaceRevisionIds, ['revision-1']);
    });

    test('names the field a caller got wrong', () {
      expect(
        () => SurfaceFunnelSelectionV1(
          surfaceId: 'welcome',
          windowStartMicros: 10,
          windowEndExclusiveMicros: 10,
        ),
        throwsA(
          isA<CanonicalFormatException>().having(
            (error) => error.message,
            'message',
            contains('windowEndExclusiveMicros'),
          ),
        ),
      );
      expect(
        () => SurfaceFunnelSelectionV1(
          surfaceId: '',
          windowStartMicros: 0,
          windowEndExclusiveMicros: 10,
        ),
        throwsA(
          isA<CanonicalFormatException>().having(
            (error) => error.message,
            'message',
            contains('surfaceId'),
          ),
        ),
      );
      expect(
        () => SurfaceFunnelSelectionV1(
          surfaceId: 'welcome',
          windowStartMicros: 0,
          windowEndExclusiveMicros: 10,
          surfaceRevisionIds: const ['one', 'one'],
        ),
        throwsA(
          isA<CanonicalFormatException>().having(
            (error) => error.message,
            'message',
            contains('surfaceRevisionIds'),
          ),
        ),
      );
    });
  });
}
