import 'dart:io';

import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  final surface = PublishedSurfaceIdentityV1.fromCanonicalBytes(
    File('../restage_measurement_schema/test/fixtures/published_identity/published_surface_identity_v1.json')
        .readAsBytesSync(),
  );
  final actual = DeliverySurfaceReferenceV1(
    surfaceIdentity: surface,
    family: DeliveryFamilySelectorV1.general(),
  );
  PlacementObservedHistoryRowV1 row({int? count, int bucket = 0}) =>
      PlacementObservedHistoryRowV1(
        utcBucketStartMicros: bucket,
        actualSurface: actual,
        surfaceRevisionId: 'surface.checkout.v3',
        publicationBindingDigest: CanonicalDigest('a' * 64),
        opaquePlacementPolicyRef: 'policy:p:1',
        evidenceStrength: MountEvidenceStrengthV1.reportedLocal,
        authenticatedPaints: count,
      );

  test('suppression round-trips without private source coordinates', () {
    final observed = row();
    final wire = observed.toJson();
    expect(observed.authenticatedPaints, isNull);
    expect(wire, isNot(contains('privateAtomDigest')));
    expect(wire, isNot(contains('rootPresentationId')));
    expect(
        PlacementObservedHistoryRowV1.fromCanonicalBytes(
            observed.canonicalBytes),
        observed);
    for (final private in [
      'privateAtomDigest',
      'rootPresentationId',
      'sessionKey'
    ]) {
      expect(
          () => PlacementObservedHistoryRowV1.fromJson({...wire, private: 'x'}),
          throwsA(isA<CanonicalFormatException>()));
    }
  });

  test('missing source coverage keeps observed counts and no invented bound',
      () {
    final history = PlacementObservedHistoryV1(
      target: surface.target,
      placement: PlacementKeyV1.named(slug: 'p'),
      coverage: PlacementHistoryCoverageV1.unavailableHistoric,
      requestedFromMicros: 0,
      requestedUntilMicros: 2,
      retainedFromMicros: null,
      publicationGeneration: 0,
      publishedAsOfMicros: 1,
      validUntilMicros: kMaximumPortableJsonInteger,
      rows: [row(count: 7)],
    );
    expect(
        PlacementObservedHistoryV1.fromCanonicalBytes(history.canonicalBytes),
        history);
    expect(history.retainedFromMicros, isNull);
    expect(history.rows.single.authenticatedPaints, 7);
    expect(
        () => PlacementObservedHistoryV1.fromJson({
              ...history.toJson(),
              'coverage': 'complete',
            }),
        throwsA(isA<CanonicalFormatException>()));
  });

  test('query rejects invalid UTC windows and unknown widths', () {
    final query = PlacementObservedHistoryQueryV1(
      placement: PlacementKeyV1.named(slug: 'p'),
      fromMicros: 0,
      untilMicros: 1,
      bucket: PlacementHistoryBucketV1.hour,
    );
    expect(
        PlacementObservedHistoryQueryV1.fromCanonicalBytes(
            query.canonicalBytes),
        query);
    for (final mutation in [
      {'fromMicros': -1},
      {'untilMicros': 0},
      {'bucket': 'week'},
      {'untilMicros': 367 * Duration.microsecondsPerDay},
    ]) {
      expect(
          () => PlacementObservedHistoryQueryV1.fromJson(
              {...query.toJson(), ...mutation}),
          throwsA(isA<CanonicalFormatException>()));
    }
  });

  test('rows reject unaligned buckets and non-positive counts', () {
    expect(() => row(bucket: 1), throwsA(isA<CanonicalFormatException>()));
    for (final count in [-1, 0]) {
      expect(() => row(count: count), throwsA(isA<CanonicalFormatException>()));
    }
    expect(
        () => PlacementObservedHistoryRowV1.fromJson({
              ...row().toJson(),
              'evidenceStrength': 'inferred',
            }),
        throwsA(isA<CanonicalFormatException>()));
  });

  test('a coordinate cannot be repeated with a different disclosed count', () {
    expect(
      () => PlacementObservedHistoryV1(
        target: surface.target,
        placement: PlacementKeyV1.named(slug: 'p'),
        coverage: PlacementHistoryCoverageV1.unavailableHistoric,
        requestedFromMicros: 0,
        requestedUntilMicros: 2,
        retainedFromMicros: null,
        publicationGeneration: 0,
        publishedAsOfMicros: 1,
        validUntilMicros: kMaximumPortableJsonInteger,
        rows: [row(count: 5), row(count: 6)],
      ),
      throwsA(isA<CanonicalFormatException>()),
    );
  });
}
