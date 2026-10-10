import 'dart:convert';

import 'package:restage_measurement_schema/restage_measurement_schema.dart';

/// UTC width of an observed placement-history bucket.
enum PlacementHistoryBucketV1 {
  /// One UTC hour.
  hour(Duration.microsecondsPerHour),

  /// One UTC day.
  day(Duration.microsecondsPerDay);

  const PlacementHistoryBucketV1(this.widthMicros);

  /// Exact fixed UTC width.
  final int widthMicros;
}

/// Evidence counted by the history source.
enum PlacementHistoryBasisV1 {
  /// An authenticated successful first paint creates each counted root once.
  authenticatedFirstPaint,
}

/// Coverage of the qualified retained attribution source at the stated cut.
enum PlacementHistoryCoverageV1 {
  /// The qualified retained source covers the requested interval.
  complete,

  /// Only part of the requested source interval remains qualified or retained.
  partialRetention,

  /// The source has no exact historical coverage witness for this interval.
  unavailableHistoric,
}

/// A bounded half-open interval for one immutable placement key.
final class PlacementObservedHistoryQueryV1 extends CanonicalValue {
  /// Selects successful paints in an explicit UTC interval.
  PlacementObservedHistoryQueryV1({
    required this.placement,
    required this.fromMicros,
    required this.untilMicros,
    required this.bucket,
  }) {
    _portable(fromMicros, 'fromMicros');
    _portable(untilMicros, 'untilMicros');
    if (untilMicros <= fromMicros ||
        untilMicros - fromMicros > 366 * Duration.microsecondsPerDay) {
      throw const CanonicalFormatException('Invalid placement history window');
    }
  }

  /// Decodes the closed query document.
  factory PlacementObservedHistoryQueryV1.fromJson(Map<String, Object?> json) {
    final reader = _reader(json, 'placementObservedHistoryQueryV1', const {
      'placement',
      'fromMicros',
      'untilMicros',
      'bucket',
    });
    return PlacementObservedHistoryQueryV1(
      placement: PlacementKeyV1.fromJson(reader.object('placement')),
      fromMicros: reader.integer('fromMicros'),
      untilMicros: reader.integer('untilMicros'),
      bucket: _enum(PlacementHistoryBucketV1.values, reader.string('bucket')),
    );
  }

  /// Decodes only the exact canonical representation.
  factory PlacementObservedHistoryQueryV1.fromCanonicalBytes(List<int> bytes) =>
      verifyCanonicalRoundTrip(
        PlacementObservedHistoryQueryV1.fromJson(decodeCanonicalObject(bytes)),
        bytes,
        path: 'placementObservedHistoryQueryV1',
      );

  /// The original placement namespace and name.
  final PlacementKeyV1 placement;

  /// Inclusive UTC lower bound.
  final int fromMicros;

  /// Exclusive UTC upper bound.
  final int untilMicros;

  /// The returned UTC bucket width.
  final PlacementHistoryBucketV1 bucket;

  @override
  Map<String, Object?> toJson() => {
        'kind': 'placementObservedHistoryQueryV1',
        'placement': placement.toJson(),
        'fromMicros': fromMicros,
        'untilMicros': untilMicros,
        'bucket': bucket.name,
      };
}

/// Successful paints of one original surface/publication/policy coordinate.
final class PlacementObservedHistoryRowV1 extends CanonicalValue {
  /// Creates one disclosed UTC bucket without any private root identity.
  PlacementObservedHistoryRowV1({
    required this.utcBucketStartMicros,
    required this.actualSurface,
    this.actualPublication,
    required this.surfaceRevisionId,
    required this.publicationBindingDigest,
    required this.opaquePlacementPolicyRef,
    required this.evidenceStrength,
    required this.authenticatedPaints,
  }) {
    _portable(utcBucketStartMicros, 'utcBucketStartMicros');
    if (utcBucketStartMicros % Duration.microsecondsPerHour != 0) {
      throw const CanonicalFormatException(
        'Unaligned placement history bucket',
      );
    }
    SurfaceRevisionId(surfaceRevisionId);
    if (actualPublication != null &&
        (actualPublication!.surface != actualSurface ||
            (actualPublication!.publicationBindingRef != null &&
                actualPublication!.publicationBindingRef!.bindingDigest !=
                    publicationBindingDigest))) {
      throw const CanonicalFormatException('Invalid original publication');
    }
    if (opaquePlacementPolicyRef != null &&
        (opaquePlacementPolicyRef!.isEmpty ||
            opaquePlacementPolicyRef!.length > 256)) {
      throw const CanonicalFormatException(
        'Invalid placement policy reference',
      );
    }
    if (authenticatedPaints != null) {
      _portable(authenticatedPaints!, 'authenticatedPaints');
      if (authenticatedPaints! < measurementDisclosureFloor) {
        throw const CanonicalFormatException(
          'Undisclosed placement paint count',
        );
      }
    }
  }

  /// Decodes the closed safe observation document.
  factory PlacementObservedHistoryRowV1.fromJson(Map<String, Object?> json) {
    final reader = _reader(json, 'placementObservedHistoryRowV1', const {
      'utcBucketStartMicros',
      'actualSurface',
      'actualPublication',
      'surfaceRevisionId',
      'publicationBindingDigest',
      'opaquePlacementPolicyRef',
      'evidenceStrength',
      'authenticatedPaints',
    });
    return PlacementObservedHistoryRowV1(
      utcBucketStartMicros: reader.integer('utcBucketStartMicros'),
      actualSurface: DeliverySurfaceReferenceV1.fromJson(
        reader.object('actualSurface'),
      ),
      actualPublication: json['actualPublication'] == null
          ? null
          : DeliveryPublicationReferenceV1.fromJson(
              reader.object('actualPublication')),
      surfaceRevisionId: reader.string('surfaceRevisionId'),
      publicationBindingDigest: CanonicalDigest(
        reader.string('publicationBindingDigest'),
      ),
      opaquePlacementPolicyRef: json['opaquePlacementPolicyRef'] == null
          ? null
          : reader.string('opaquePlacementPolicyRef'),
      evidenceStrength: _enum(
        MountEvidenceStrengthV1.values,
        reader.string('evidenceStrength'),
      ),
      authenticatedPaints: json['authenticatedPaints'] == null
          ? null
          : reader.integer('authenticatedPaints'),
    );
  }

  /// Decodes only the exact canonical representation.
  factory PlacementObservedHistoryRowV1.fromCanonicalBytes(List<int> bytes) =>
      verifyCanonicalRoundTrip(
        PlacementObservedHistoryRowV1.fromJson(decodeCanonicalObject(bytes)),
        bytes,
        path: 'placementObservedHistoryRowV1',
      );

  /// Aligned UTC bucket start, including buckets with partial query edges.
  final int utcBucketStartMicros;

  /// The exact original surface and family retained by the mounted tuple.
  final DeliverySurfaceReferenceV1 actualSurface;

  /// Exact remote publication when one was present in the original tuple.
  final DeliveryPublicationReferenceV1? actualPublication;

  /// The original measured publication revision.
  final String surfaceRevisionId;

  /// Exact original publication binding.
  final CanonicalDigest publicationBindingDigest;

  /// Safe opaque reference to the original placement policy, if proven.
  final String? opaquePlacementPolicyRef;

  /// Selection evidence; successful-paint authentication is the series basis.
  final MountEvidenceStrengthV1 evidenceStrength;

  /// Null means the shared disclosure plan withholds the count.
  final int? authenticatedPaints;

  @override
  Map<String, Object?> toJson() => {
        'kind': 'placementObservedHistoryRowV1',
        'utcBucketStartMicros': utcBucketStartMicros,
        'actualSurface': actualSurface.toJson(),
        'actualPublication': actualPublication?.toJson(),
        'surfaceRevisionId': surfaceRevisionId,
        'publicationBindingDigest': publicationBindingDigest.hex,
        'opaquePlacementPolicyRef': opaquePlacementPolicyRef,
        'evidenceStrength': evidenceStrength.name,
        'authenticatedPaints': authenticatedPaints,
      };
}

/// Observed first paints plus the original source's explicit coverage witness.
final class PlacementObservedHistoryV1 extends CanonicalValue {
  /// Creates a source-qualified reading at one safe page cut.
  PlacementObservedHistoryV1({
    required this.target,
    required this.placement,
    required this.coverage,
    required this.requestedFromMicros,
    required this.requestedUntilMicros,
    required this.retainedFromMicros,
    required this.publicationGeneration,
    required this.publishedAsOfMicros,
    required this.validUntilMicros,
    required List<PlacementObservedHistoryRowV1> rows,
  }) : rows = List.unmodifiable(rows) {
    for (final value in [
      requestedFromMicros,
      requestedUntilMicros,
      publicationGeneration,
      publishedAsOfMicros,
      validUntilMicros,
    ]) {
      _portable(value, 'history cut');
    }
    if (retainedFromMicros != null)
      _portable(retainedFromMicros!, 'retainedFromMicros');
    if (requestedUntilMicros <= requestedFromMicros ||
        validUntilMicros < publishedAsOfMicros ||
        (coverage == PlacementHistoryCoverageV1.complete &&
            (retainedFromMicros == null ||
                retainedFromMicros! > requestedFromMicros ||
                requestedUntilMicros > publishedAsOfMicros + 1)) ||
        (coverage == PlacementHistoryCoverageV1.partialRetention &&
            retainedFromMicros == null) ||
        this.rows.length > 65536) {
      throw const CanonicalFormatException(
        'Invalid placement history coverage',
      );
    }
    final identities = <String>{};
    for (final row in this.rows) {
      final coordinate = row.toJson()..remove('authenticatedPaints');
      if (row.actualSurface.target != target ||
          !identities.add(utf8.decode(CanonicalJsonCodec.encode(coordinate))) ||
          row.utcBucketStartMicros >= requestedUntilMicros ||
          row.utcBucketStartMicros + Duration.microsecondsPerDay <=
              requestedFromMicros ||
          row.utcBucketStartMicros > publishedAsOfMicros) {
        throw const CanonicalFormatException(
          'Invalid placement history row extent',
        );
      }
    }
  }

  /// Decodes the closed safe history document.
  factory PlacementObservedHistoryV1.fromJson(Map<String, Object?> json) {
    final reader = _reader(json, 'placementObservedHistoryV1', const {
      'target',
      'placement',
      'basis',
      'coverage',
      'requestedFromMicros',
      'requestedUntilMicros',
      'retainedFromMicros',
      'publicationGeneration',
      'publishedAsOfMicros',
      'validUntilMicros',
      'rows',
    });
    _enum(PlacementHistoryBasisV1.values, reader.string('basis'));
    return PlacementObservedHistoryV1(
      target: TargetCoordinate.fromJson(reader.object('target')),
      placement: PlacementKeyV1.fromJson(reader.object('placement')),
      coverage: _enum(
        PlacementHistoryCoverageV1.values,
        reader.string('coverage'),
      ),
      requestedFromMicros: reader.integer('requestedFromMicros'),
      requestedUntilMicros: reader.integer('requestedUntilMicros'),
      retainedFromMicros: json['retainedFromMicros'] == null
          ? null
          : reader.integer('retainedFromMicros'),
      publicationGeneration: reader.integer('publicationGeneration'),
      publishedAsOfMicros: reader.integer('publishedAsOfMicros'),
      validUntilMicros: reader.integer('validUntilMicros'),
      rows: [
        for (final value in reader.list('rows'))
          PlacementObservedHistoryRowV1.fromJson(
            requireCanonicalObject(value, 'rows'),
          ),
      ],
    );
  }

  /// Decodes only the exact canonical representation.
  factory PlacementObservedHistoryV1.fromCanonicalBytes(List<int> bytes) =>
      verifyCanonicalRoundTrip(
        PlacementObservedHistoryV1.fromJson(decodeCanonicalObject(bytes)),
        bytes,
        path: 'placementObservedHistoryV1',
      );

  /// Every row counts authenticated successful first paints.
  PlacementHistoryBasisV1 get basis =>
      PlacementHistoryBasisV1.authenticatedFirstPaint;

  /// Exact authorized target of this source reading.
  final TargetCoordinate target;

  /// Original placement key selected by this reading.
  final PlacementKeyV1 placement;

  /// Source coverage independent of the number of paints returned.
  final PlacementHistoryCoverageV1 coverage;

  /// Inclusive requested UTC lower bound.
  final int requestedFromMicros;

  /// Exclusive requested UTC upper bound.
  final int requestedUntilMicros;

  /// Earliest qualified retained source bound, or null if no witness exists.
  final int? retainedFromMicros;

  /// Published projection generation, or zero for the unadopted raw cut.
  final int publicationGeneration;

  /// The shared page's exact source cut.
  final int publishedAsOfMicros;

  /// Exclusive validity bound of the shared page cut.
  final int validUntilMicros;

  /// Immutable observed surface/publication coordinates at the cut.
  final List<PlacementObservedHistoryRowV1> rows;

  @override
  Map<String, Object?> toJson() => {
        'kind': 'placementObservedHistoryV1',
        'target': target.toJson(),
        'placement': placement.toJson(),
        'basis': basis.name,
        'coverage': coverage.name,
        'requestedFromMicros': requestedFromMicros,
        'requestedUntilMicros': requestedUntilMicros,
        'retainedFromMicros': retainedFromMicros,
        'publicationGeneration': publicationGeneration,
        'publishedAsOfMicros': publishedAsOfMicros,
        'validUntilMicros': validUntilMicros,
        'rows': [for (final row in rows) row.toJson()],
      };
}

CanonicalObjectReader _reader(
  Map<String, Object?> json,
  String kind,
  Set<String> keys,
) {
  final reader = CanonicalObjectReader(
    json,
    allowedKeys: {'kind', ...keys},
    requiredKeys: {'kind', ...keys},
    path: kind,
  );
  if (reader.string('kind') != kind) {
    throw CanonicalFormatException('Invalid $kind kind');
  }
  return reader;
}

T _enum<T extends Enum>(List<T> values, String name) => values.firstWhere(
      (value) => value.name == name,
      orElse: () =>
          throw CanonicalFormatException('Unknown history value "$name"'),
    );

void _portable(int value, String field) {
  if (value < 0 || value > kMaximumPortableJsonInteger) {
    throw CanonicalFormatException('Invalid $field');
  }
}
