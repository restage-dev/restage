/// Funnel counts and rates by surface and served version.
/// Rates include exact fractions and rounded decimals at
/// [kExperimentResultDecimalScale]. Zero denominators omit the rate.
/// Groups below the disclosure floor retain their identity but omit counts,
/// preventing recovery of hidden counts by subtracting visible groups.
library;

import 'canonical.dart';
import 'experiment_authoring.dart';
import 'ordered_capture.dart';
import 'target.dart';

/// Largest published version count one funnel reading returns.
const int kSurfaceFunnelMaximumVersions = 64;

/// Largest typed drop-off band count one published version carries.
const int kSurfaceFunnelMaximumBands = 1024;

/// Largest authored step count one published version carries.
const int kSurfaceFunnelMaximumSteps = 1024;

/// Longest surface identity a funnel selection may name.
const int kSurfaceFunnelIdentityLimit = 200;

/// Why one group of a funnel reading states no numbers.
enum SurfaceFunnelDisclosureV1 {
  /// The group's own population is at or above the reading's floor.
  disclosed('disclosed'),

  /// The group's own population is under the floor.
  belowDisclosureFloor('belowDisclosureFloor'),

  /// The group is derived from one that is itself held back.
  derivedFromSuppressed('derivedFromSuppressed');

  const SurfaceFunnelDisclosureV1(this.wireName);

  /// The published spelling.
  final String wireName;

  static SurfaceFunnelDisclosureV1 _fromWire(String value, String path) {
    for (final candidate in SurfaceFunnelDisclosureV1.values) {
      if (candidate.wireName == value) return candidate;
    }
    throw CanonicalFormatException('$path "$value" is unsupported');
  }
}

/// Whether one published version can state funnel figures, and why not.
enum SurfaceFunnelVersionStatusV1 {
  /// The version states figures.
  available('available'),

  /// The version served before ordered capture was published for it.
  orderedCaptureUnavailable('orderedCaptureUnavailable'),

  /// The version's authored step metadata cannot be read.
  flowMetadataUnavailable('flowMetadataUnavailable'),

  /// The version's authored shape is outside what this reading describes.
  unsupportedFlow('unsupportedFlow');

  const SurfaceFunnelVersionStatusV1(this.wireName);

  /// The published spelling.
  final String wireName;

  static SurfaceFunnelVersionStatusV1 _fromWire(String value, String path) {
    for (final candidate in SurfaceFunnelVersionStatusV1.values) {
      if (candidate.wireName == value) return candidate;
    }
    throw CanonicalFormatException('$path "$value" is unsupported');
  }
}

/// A rate with exact counts, a reduced fraction and a rounded decimal.
/// Decoding verifies both representations using [kExperimentResultDecimalScale].
/// Rates above one are allowed when completions exceed recorded views.
final class SurfaceFunnelRateV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  SurfaceFunnelRateV1._({
    required this.numerator,
    required this.denominator,
    required this.decimal,
    required this.exact,
  });

  /// Writes [numerator] over [denominator] through the shared helpers.
  factory SurfaceFunnelRateV1.of({
    required int numerator,
    required int denominator,
    required String path,
  }) {
    if (numerator < 0 || denominator <= 0) {
      throw CanonicalFormatException('$path is not a rate of its counts');
    }
    final top = BigInt.from(numerator);
    final bottom = BigInt.from(denominator);
    return SurfaceFunnelRateV1._(
      numerator: numerator,
      denominator: denominator,
      decimal: experimentResultDecimal(
        top,
        bottom,
        rounding: ExperimentDecimalRoundingV1.nearest,
      ),
      exact: ExperimentExactRatioV1.fromJson(
        experimentExactRatioJson(top, bottom),
        path: '$path.exact',
      ),
    );
  }

  /// Decodes one rate and checks it against its own counts.
  factory SurfaceFunnelRateV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'decimal', 'denominator', 'exact', 'numerator'},
      requiredKeys: const {'decimal', 'denominator', 'exact', 'numerator'},
      path: path,
    );
    final recomputed = SurfaceFunnelRateV1.of(
      numerator: reader.integer('numerator'),
      denominator: reader.integer('denominator'),
      path: path,
    );
    if (reader.string('decimal') != recomputed.decimal) {
      throw CanonicalFormatException('$path.decimal disagrees with its counts');
    }
    final exact = ExperimentExactRatioV1.fromJson(
      reader.object('exact'),
      path: '$path.exact',
    );
    if (exact.numerator != recomputed.exact.numerator ||
        exact.denominator != recomputed.exact.denominator) {
      throw CanonicalFormatException('$path.exact disagrees with its counts');
    }
    return recomputed;
  }

  /// The count above the line.
  final int numerator;

  /// The count below it, always positive.
  final int denominator;

  /// The rate at [kExperimentResultDecimalScale], to the nearest figure.
  final String decimal;

  /// The same fraction unrounded, in lowest terms.
  final ExperimentExactRatioV1 exact;

  @override
  Map<String, Object?> toJson() => {
        'decimal': decimal,
        'denominator': denominator,
        'exact': exact.toJson(),
        'numerator': numerator,
      };
}

/// Returns the rate of [numerator] over [denominator], or null for no
/// denominator to divide by.
SurfaceFunnelRateV1? _rateOrNone({
  required int numerator,
  required int denominator,
  required String path,
}) =>
    denominator == 0
        ? null
        : SurfaceFunnelRateV1.of(
            numerator: numerator,
            denominator: denominator,
            path: path,
          );

/// Distinct presentation counts for one published version or one of its steps.
///
/// These count presentations, never people and never sessions spanning more
/// than one surface. A presentation still awaiting its terminal report is
/// carried in [pendingRoots], so [views] and [completions] remain lower bounds
/// while any pending presentation exists.
final class SurfaceFunnelCountsV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  SurfaceFunnelCountsV1._({
    required this.eligibleRoots,
    required this.views,
    required this.completions,
    required this.skips,
    required this.dismissals,
    required this.reachedAnotherStep,
    required this.completeRoots,
    required this.pendingRoots,
    required this.unavailableRoots,
    required this.viewRate,
    required this.completionRate,
    required this.conversionRate,
  });

  /// Builds one set of counts and the three rates they imply.
  factory SurfaceFunnelCountsV1.of({
    required int eligibleRoots,
    required int views,
    required int completions,
    required int skips,
    required int dismissals,
    required int reachedAnotherStep,
    required int completeRoots,
    required int pendingRoots,
    required int unavailableRoots,
    required String path,
  }) {
    final counts = [
      views,
      completions,
      skips,
      dismissals,
      reachedAnotherStep,
      completeRoots,
      pendingRoots,
      unavailableRoots,
    ];
    if (eligibleRoots < 0 ||
        counts.any((value) => value < 0 || value > eligibleRoots) ||
        completeRoots + pendingRoots + unavailableRoots != eligibleRoots) {
      throw CanonicalFormatException('$path are inconsistent');
    }
    return SurfaceFunnelCountsV1._(
      eligibleRoots: eligibleRoots,
      views: views,
      completions: completions,
      skips: skips,
      dismissals: dismissals,
      reachedAnotherStep: reachedAnotherStep,
      completeRoots: completeRoots,
      pendingRoots: pendingRoots,
      unavailableRoots: unavailableRoots,
      viewRate: _rateOrNone(
        numerator: views,
        denominator: eligibleRoots,
        path: '$path.viewRate',
      ),
      completionRate: _rateOrNone(
        numerator: completions,
        denominator: views,
        path: '$path.completionRate',
      ),
      conversionRate: _rateOrNone(
        numerator: completions,
        denominator: eligibleRoots,
        path: '$path.conversionRate',
      ),
    );
  }

  /// Decodes one set of counts, checking every stated rate against them.
  factory SurfaceFunnelCountsV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'completeRoots',
        'completionRate',
        'completions',
        'conversionRate',
        'dismissals',
        'eligibleRoots',
        'pendingRoots',
        'reachedAnotherStep',
        'skips',
        'unavailableRoots',
        'views',
        'viewRate',
      },
      requiredKeys: const {
        'completeRoots',
        'completions',
        'dismissals',
        'eligibleRoots',
        'pendingRoots',
        'reachedAnotherStep',
        'skips',
        'unavailableRoots',
        'views',
      },
      path: path,
    );
    final recomputed = SurfaceFunnelCountsV1.of(
      eligibleRoots: reader.integer('eligibleRoots'),
      views: reader.integer('views'),
      completions: reader.integer('completions'),
      skips: reader.integer('skips'),
      dismissals: reader.integer('dismissals'),
      reachedAnotherStep: reader.integer('reachedAnotherStep'),
      completeRoots: reader.integer('completeRoots'),
      pendingRoots: reader.integer('pendingRoots'),
      unavailableRoots: reader.integer('unavailableRoots'),
      path: path,
    );
    _requireStatedRate(reader, 'viewRate', recomputed.viewRate, path);
    _requireStatedRate(
      reader,
      'completionRate',
      recomputed.completionRate,
      path,
    );
    _requireStatedRate(
      reader,
      'conversionRate',
      recomputed.conversionRate,
      path,
    );
    return recomputed;
  }

  /// Presentations this version or step was eligible for in the window.
  final int eligibleRoots;

  /// Eligible presentations that were painted.
  final int views;

  /// Presentations that reached the authored end.
  final int completions;

  /// Presentations the viewer skipped past.
  final int skips;

  /// Presentations the viewer dismissed.
  final int dismissals;

  /// Presentations that went on to another authored step.
  final int reachedAnotherStep;

  /// Eligible presentations whose terminal report has arrived.
  final int completeRoots;

  /// Eligible presentations still awaiting a terminal report.
  final int pendingRoots;

  /// Eligible presentations whose terminal report will not arrive.
  final int unavailableRoots;

  /// [views] over [eligibleRoots], absent when nothing was eligible.
  final SurfaceFunnelRateV1? viewRate;

  /// [completions] over [views], absent when nothing was viewed.
  final SurfaceFunnelRateV1? completionRate;

  /// [completions] over [eligibleRoots], absent when nothing was eligible.
  final SurfaceFunnelRateV1? conversionRate;

  @override
  Map<String, Object?> toJson() => {
        'completeRoots': completeRoots,
        if (completionRate != null) 'completionRate': completionRate!.toJson(),
        'completions': completions,
        if (conversionRate != null) 'conversionRate': conversionRate!.toJson(),
        'dismissals': dismissals,
        'eligibleRoots': eligibleRoots,
        'pendingRoots': pendingRoots,
        'reachedAnotherStep': reachedAnotherStep,
        'skips': skips,
        'unavailableRoots': unavailableRoots,
        if (viewRate != null) 'viewRate': viewRate!.toJson(),
        'views': views,
      };
}

/// Distinct presentation reach at one typed drop-off band.
///
/// [reach] counts presentations, so a revisit raises [occurrences] alone.
/// [continued] is stated only where one authored successor makes the next band
/// adjacent; a branch, an unordered band, a final page, or a neighbour held
/// back under the floor all leave it absent rather than manufacturing a loss.
final class SurfaceFunnelBandCountsV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  SurfaceFunnelBandCountsV1._({
    required this.eligibleRoots,
    required this.reach,
    required this.occurrences,
    required this.continued,
    required this.completeRoots,
    required this.pendingRoots,
    required this.unavailableRoots,
    required this.reachRate,
    required this.continuationRate,
    required this.dropOffRate,
  });

  /// Builds one band's counts and the rates they imply.
  factory SurfaceFunnelBandCountsV1.of({
    required int eligibleRoots,
    required int reach,
    required int occurrences,
    required int completeRoots,
    required int pendingRoots,
    required int unavailableRoots,
    required String path,
    int? continued,
  }) {
    if (eligibleRoots < 0 ||
        reach < 0 ||
        reach > eligibleRoots ||
        occurrences < reach ||
        (continued != null && (continued < 0 || continued > reach)) ||
        completeRoots < 0 ||
        pendingRoots < 0 ||
        unavailableRoots < 0 ||
        completeRoots + pendingRoots + unavailableRoots != eligibleRoots) {
      throw CanonicalFormatException('$path are inconsistent');
    }
    return SurfaceFunnelBandCountsV1._(
      eligibleRoots: eligibleRoots,
      reach: reach,
      occurrences: occurrences,
      continued: continued,
      completeRoots: completeRoots,
      pendingRoots: pendingRoots,
      unavailableRoots: unavailableRoots,
      reachRate: _rateOrNone(
        numerator: reach,
        denominator: eligibleRoots,
        path: '$path.reachRate',
      ),
      continuationRate: continued == null
          ? null
          : _rateOrNone(
              numerator: continued,
              denominator: reach,
              path: '$path.continuationRate',
            ),
      dropOffRate: continued == null
          ? null
          : _rateOrNone(
              numerator: reach - continued,
              denominator: reach,
              path: '$path.dropOffRate',
            ),
    );
  }

  /// Decodes one band's counts, checking every stated rate against them.
  factory SurfaceFunnelBandCountsV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'completeRoots',
        'continuationRate',
        'continued',
        'dropOffRate',
        'eligibleRoots',
        'occurrences',
        'pendingRoots',
        'reach',
        'reachRate',
        'unavailableRoots',
      },
      requiredKeys: const {
        'completeRoots',
        'eligibleRoots',
        'occurrences',
        'pendingRoots',
        'reach',
        'unavailableRoots',
      },
      path: path,
    );
    final recomputed = SurfaceFunnelBandCountsV1.of(
      eligibleRoots: reader.integer('eligibleRoots'),
      reach: reader.integer('reach'),
      occurrences: reader.integer('occurrences'),
      continued: reader.optionalInteger('continued'),
      completeRoots: reader.integer('completeRoots'),
      pendingRoots: reader.integer('pendingRoots'),
      unavailableRoots: reader.integer('unavailableRoots'),
      path: path,
    );
    _requireStatedRate(reader, 'reachRate', recomputed.reachRate, path);
    _requireStatedRate(
      reader,
      'continuationRate',
      recomputed.continuationRate,
      path,
    );
    _requireStatedRate(reader, 'dropOffRate', recomputed.dropOffRate, path);
    return recomputed;
  }

  /// Presentations eligible for the version this band belongs to.
  final int eligibleRoots;

  /// Eligible presentations that reached this band.
  final int reach;

  /// Times this band was reached, revisits included.
  final int occurrences;

  /// Reaching presentations that went on to the one authored successor.
  final int? continued;

  /// Eligible presentations whose terminal report has arrived.
  final int completeRoots;

  /// Eligible presentations still awaiting a terminal report.
  final int pendingRoots;

  /// Eligible presentations whose terminal report will not arrive.
  final int unavailableRoots;

  /// [reach] over [eligibleRoots], absent when nothing was eligible.
  final SurfaceFunnelRateV1? reachRate;

  /// [continued] over [reach], absent when either is unavailable.
  final SurfaceFunnelRateV1? continuationRate;

  /// The reaching presentations that did not continue, over [reach].
  final SurfaceFunnelRateV1? dropOffRate;

  @override
  Map<String, Object?> toJson() => {
        'completeRoots': completeRoots,
        if (continuationRate != null)
          'continuationRate': continuationRate!.toJson(),
        if (continued != null) 'continued': continued,
        if (dropOffRate != null) 'dropOffRate': dropOffRate!.toJson(),
        'eligibleRoots': eligibleRoots,
        'occurrences': occurrences,
        'pendingRoots': pendingRoots,
        'reach': reach,
        if (reachRate != null) 'reachRate': reachRate!.toJson(),
        'unavailableRoots': unavailableRoots,
      };
}

/// One typed drop-off band: an authored page, question, or named interaction.
final class SurfaceFunnelBandV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  SurfaceFunnelBandV1._({
    required this.point,
    required this.disclosure,
    required this.counts,
  });

  /// Builds one band, whose counts are absent exactly when it is held back.
  factory SurfaceFunnelBandV1.of({
    required MeasurementBreakdownPointV1 point,
    required SurfaceFunnelDisclosureV1 disclosure,
    required String path,
    SurfaceFunnelBandCountsV1? counts,
  }) {
    if ((counts == null) !=
        (disclosure != SurfaceFunnelDisclosureV1.disclosed)) {
      throw CanonicalFormatException('$path disagrees with its disclosure');
    }
    return SurfaceFunnelBandV1._(
      point: point,
      disclosure: disclosure,
      counts: counts,
    );
  }

  /// Decodes one band.
  factory SurfaceFunnelBandV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'counts', 'disclosure', 'point'},
      requiredKeys: const {'disclosure', 'point'},
      path: path,
    );
    return SurfaceFunnelBandV1.of(
      point: MeasurementBreakdownPointV1.fromJson(reader.object('point')),
      disclosure: SurfaceFunnelDisclosureV1._fromWire(
        reader.string('disclosure'),
        '$path.disclosure',
      ),
      counts: switch (reader.optionalObject('counts')) {
        final Map<String, Object?> value => SurfaceFunnelBandCountsV1.fromJson(
            value,
            path: '$path.counts',
          ),
        null => null,
      },
      path: path,
    );
  }

  /// What this band names.
  final MeasurementBreakdownPointV1 point;

  /// Why this band states no numbers, when it states none.
  final SurfaceFunnelDisclosureV1 disclosure;

  /// Absent when this band's own reach is under the floor.
  final SurfaceFunnelBandCountsV1? counts;

  /// Identity of this band within one published version.
  String get identity => point.identity;

  @override
  Map<String, Object?> toJson() => {
        if (counts != null) 'counts': counts!.toJson(),
        'disclosure': disclosure.wireName,
        'point': point.toJson(),
      };
}

/// One authored step of a published version.
///
/// The list position is not an authored order; [transitionTargets] names the
/// steps this one can lead to.
final class SurfaceFunnelStepV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  SurfaceFunnelStepV1._({
    required this.stateId,
    required this.screenArtifactId,
    required this.screenContentHash,
    required this.screenVersion,
    required this.disclosure,
    required this.counts,
    required List<String> transitionTargets,
  }) : transitionTargets = List.unmodifiable(transitionTargets);

  /// Builds one step, whose counts are absent exactly when it is held back.
  factory SurfaceFunnelStepV1.of({
    required String stateId,
    required String screenArtifactId,
    required String screenContentHash,
    required int screenVersion,
    required SurfaceFunnelDisclosureV1 disclosure,
    required String path,
    SurfaceFunnelCountsV1? counts,
    List<String> transitionTargets = const [],
  }) {
    if (stateId.isEmpty || screenArtifactId.isEmpty || screenVersion < 1) {
      throw CanonicalFormatException('$path names no authored step');
    }
    if (transitionTargets.toSet().length != transitionTargets.length) {
      throw CanonicalFormatException('$path repeats a transition target');
    }
    if ((counts == null) !=
        (disclosure != SurfaceFunnelDisclosureV1.disclosed)) {
      throw CanonicalFormatException('$path disagrees with its disclosure');
    }
    if (counts == null && transitionTargets.isNotEmpty) {
      throw CanonicalFormatException('$path states transitions it holds back');
    }
    return SurfaceFunnelStepV1._(
      stateId: stateId,
      screenArtifactId: screenArtifactId,
      screenContentHash: screenContentHash,
      screenVersion: screenVersion,
      disclosure: disclosure,
      counts: counts,
      transitionTargets: List.unmodifiable(transitionTargets),
    );
  }

  /// Decodes one step.
  factory SurfaceFunnelStepV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'counts',
        'disclosure',
        'screenArtifactId',
        'screenContentHash',
        'screenVersion',
        'stateId',
        'transitionTargets',
      },
      requiredKeys: const {
        'disclosure',
        'screenArtifactId',
        'screenContentHash',
        'screenVersion',
        'stateId',
      },
      path: path,
    );
    return SurfaceFunnelStepV1.of(
      stateId: reader.string('stateId'),
      screenArtifactId: reader.string('screenArtifactId'),
      screenContentHash: reader.string('screenContentHash'),
      screenVersion: reader.integer('screenVersion'),
      disclosure: SurfaceFunnelDisclosureV1._fromWire(
        reader.string('disclosure'),
        '$path.disclosure',
      ),
      counts: switch (reader.optionalObject('counts')) {
        final Map<String, Object?> value => SurfaceFunnelCountsV1.fromJson(
            value,
            path: '$path.counts',
          ),
        null => null,
      },
      transitionTargets: [
        for (final value
            in reader.optionalList('transitionTargets') ?? const [])
          requireCanonicalString(value, '$path.transitionTargets'),
      ],
      path: path,
    );
  }

  /// The authored state this step names.
  final String stateId;

  /// The screen artifact the step paints.
  final String screenArtifactId;

  /// Content hash of that artifact.
  final String screenContentHash;

  /// Published version of that artifact.
  final int screenVersion;

  /// Why this step states no numbers, when it states none.
  final SurfaceFunnelDisclosureV1 disclosure;

  /// Absent when this step's own population is under the floor.
  final SurfaceFunnelCountsV1? counts;

  /// The steps this one can lead to.
  final List<String> transitionTargets;

  @override
  Map<String, Object?> toJson() => {
        if (counts != null) 'counts': counts!.toJson(),
        'disclosure': disclosure.wireName,
        'screenArtifactId': screenArtifactId,
        'screenContentHash': screenContentHash,
        'screenVersion': screenVersion,
        'stateId': stateId,
        if (transitionTargets.isNotEmpty)
          'transitionTargets': transitionTargets,
      };
}

/// One exact published version of the surface, and what it did in the window.
final class SurfaceFunnelVersionV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  SurfaceFunnelVersionV1._({
    required this.surfaceRevisionId,
    required this.revisionOrdinal,
    required this.publishedAtMicros,
    required this.status,
    required this.disclosure,
    required this.counts,
    required this.unattributedDismissals,
    required List<SurfaceFunnelStepV1> steps,
    required List<SurfaceFunnelBandV1> bands,
    required Map<String, List<String>> stateTransitions,
    required this.flowId,
    required this.flowVersion,
    required this.flowContentHash,
    required this.initialStateId,
  })  : steps = List.unmodifiable(steps),
        bands = List.unmodifiable(bands),
        stateTransitions = Map.unmodifiable({
          for (final entry in stateTransitions.entries)
            entry.key: List<String>.unmodifiable(entry.value),
        });

  /// Builds one published version's figures.
  factory SurfaceFunnelVersionV1.of({
    required String surfaceRevisionId,
    required int revisionOrdinal,
    required int publishedAtMicros,
    required SurfaceFunnelVersionStatusV1 status,
    required SurfaceFunnelDisclosureV1 disclosure,
    required Map<String, List<String>> stateTransitions,
    required String path,
    SurfaceFunnelCountsV1? counts,
    int? unattributedDismissals,
    List<SurfaceFunnelStepV1> steps = const [],
    List<SurfaceFunnelBandV1> bands = const [],
    String? flowId,
    int? flowVersion,
    String? flowContentHash,
    String? initialStateId,
  }) {
    if (surfaceRevisionId.isEmpty || revisionOrdinal < 1) {
      throw CanonicalFormatException('$path names no published version');
    }
    if ((counts == null) !=
        (disclosure != SurfaceFunnelDisclosureV1.disclosed)) {
      throw CanonicalFormatException('$path disagrees with its disclosure');
    }
    if ((counts == null) != (unattributedDismissals == null)) {
      throw CanonicalFormatException('$path holds back part of its counts');
    }
    if (counts != null &&
        (unattributedDismissals! < 0 ||
            unattributedDismissals > counts.dismissals)) {
      throw CanonicalFormatException('$path attributes more than it dismissed');
    }
    if (steps.length > kSurfaceFunnelMaximumSteps ||
        steps.map((step) => step.stateId).toSet().length != steps.length) {
      throw CanonicalFormatException('$path repeats or overruns its steps');
    }
    if (bands.length > kSurfaceFunnelMaximumBands ||
        bands.map((band) => band.identity).toSet().length != bands.length) {
      throw CanonicalFormatException('$path repeats or overruns its bands');
    }
    return SurfaceFunnelVersionV1._(
      surfaceRevisionId: surfaceRevisionId,
      revisionOrdinal: revisionOrdinal,
      publishedAtMicros: publishedAtMicros,
      status: status,
      disclosure: disclosure,
      counts: counts,
      unattributedDismissals: unattributedDismissals,
      steps: List.unmodifiable(steps),
      bands: List.unmodifiable(bands),
      stateTransitions: Map.unmodifiable({
        for (final entry in stateTransitions.entries)
          entry.key: List<String>.unmodifiable(entry.value),
      }),
      flowId: flowId,
      flowVersion: flowVersion,
      flowContentHash: flowContentHash,
      initialStateId: initialStateId,
    );
  }

  /// Decodes one published version's figures.
  factory SurfaceFunnelVersionV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'bands',
        'counts',
        'disclosure',
        'flowContentHash',
        'flowId',
        'flowVersion',
        'initialStateId',
        'publishedAtMicros',
        'revisionOrdinal',
        'stateTransitions',
        'status',
        'steps',
        'surfaceRevisionId',
        'unattributedDismissals',
      },
      requiredKeys: const {
        'disclosure',
        'publishedAtMicros',
        'revisionOrdinal',
        'stateTransitions',
        'status',
        'steps',
        'surfaceRevisionId',
      },
      path: path,
    );
    return SurfaceFunnelVersionV1.of(
      surfaceRevisionId: reader.string('surfaceRevisionId'),
      revisionOrdinal: reader.integer('revisionOrdinal'),
      publishedAtMicros: reader.integer('publishedAtMicros'),
      status: SurfaceFunnelVersionStatusV1._fromWire(
        reader.string('status'),
        '$path.status',
      ),
      disclosure: SurfaceFunnelDisclosureV1._fromWire(
        reader.string('disclosure'),
        '$path.disclosure',
      ),
      counts: switch (reader.optionalObject('counts')) {
        final Map<String, Object?> value => SurfaceFunnelCountsV1.fromJson(
            value,
            path: '$path.counts',
          ),
        null => null,
      },
      unattributedDismissals: reader.optionalInteger('unattributedDismissals'),
      steps: [
        for (final (index, value) in reader.list('steps').indexed)
          SurfaceFunnelStepV1.fromJson(
            requireCanonicalObject(value, '$path.steps[$index]'),
            path: '$path.steps[$index]',
          ),
      ],
      bands: [
        for (final (index, value)
            in (reader.optionalList('bands') ?? const []).indexed)
          SurfaceFunnelBandV1.fromJson(
            requireCanonicalObject(value, '$path.bands[$index]'),
            path: '$path.bands[$index]',
          ),
      ],
      stateTransitions: _transitions(
        reader.object('stateTransitions'),
        '$path.stateTransitions',
      ),
      flowId: reader.optionalString('flowId'),
      flowVersion: reader.optionalInteger('flowVersion'),
      flowContentHash: reader.optionalString('flowContentHash'),
      initialStateId: reader.optionalString('initialStateId'),
      path: path,
    );
  }

  /// The exact published revision this version names.
  final String surfaceRevisionId;

  /// Its position in the surface's publication order.
  final int revisionOrdinal;

  /// When it was published.
  final int publishedAtMicros;

  /// Whether it can state figures, and why not.
  final SurfaceFunnelVersionStatusV1 status;

  /// Why this version states no numbers, when it states none.
  final SurfaceFunnelDisclosureV1 disclosure;

  /// Absent when this version's own population is under the floor.
  final SurfaceFunnelCountsV1? counts;

  /// Dismissals this reading could not attribute to one step.
  final int? unattributedDismissals;

  /// The version's authored steps.
  final List<SurfaceFunnelStepV1> steps;

  /// Its typed drop-off bands, empty where it declares no point.
  final List<SurfaceFunnelBandV1> bands;

  /// The authored transitions between its steps.
  final Map<String, List<String>> stateTransitions;

  /// The flow this version serves, when it serves one.
  final String? flowId;

  /// That flow's published version.
  final int? flowVersion;

  /// That flow's content hash.
  final String? flowContentHash;

  /// The step the flow starts at.
  final String? initialStateId;

  @override
  Map<String, Object?> toJson() => {
        if (bands.isNotEmpty)
          'bands': [for (final band in bands) band.toJson()],
        if (counts != null) 'counts': counts!.toJson(),
        'disclosure': disclosure.wireName,
        if (flowContentHash != null) 'flowContentHash': flowContentHash,
        if (flowId != null) 'flowId': flowId,
        if (flowVersion != null) 'flowVersion': flowVersion,
        if (initialStateId != null) 'initialStateId': initialStateId,
        'publishedAtMicros': publishedAtMicros,
        'revisionOrdinal': revisionOrdinal,
        'stateTransitions': stateTransitions,
        'status': status.wireName,
        'steps': [for (final step in steps) step.toJson()],
        'surfaceRevisionId': surfaceRevisionId,
        if (unattributedDismissals != null)
          'unattributedDismissals': unattributedDismissals,
      };
}

/// Funnel figures for one surface over one window, per published version.
final class SurfaceFunnelViewV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  SurfaceFunnelViewV1._({
    required this.target,
    required this.surfaceId,
    required this.surfaceType,
    required this.windowStartMicros,
    required this.windowEndExclusiveMicros,
    required this.asOfMicros,
    required this.disclosureFloor,
    required List<SurfaceFunnelVersionV1> versions,
  }) : versions = List.unmodifiable(versions);

  /// Builds one funnel reading.
  factory SurfaceFunnelViewV1.of({
    required TargetCoordinate target,
    required String surfaceId,
    required int windowStartMicros,
    required int windowEndExclusiveMicros,
    required int asOfMicros,
    required int disclosureFloor,
    required List<SurfaceFunnelVersionV1> versions,
    String? surfaceType,
  }) {
    const path = 'surfaceFunnelView';
    if (surfaceId.isEmpty || surfaceId.length > kSurfaceFunnelIdentityLimit) {
      throw const CanonicalFormatException('$path.surfaceId is out of bounds');
    }
    if (windowStartMicros < 0 ||
        windowEndExclusiveMicros <= windowStartMicros ||
        asOfMicros <= 0) {
      throw const CanonicalFormatException('$path.window is not a window');
    }
    if (disclosureFloor < 0) {
      throw const CanonicalFormatException(
        '$path.disclosureFloor must not be negative',
      );
    }
    if (versions.length > kSurfaceFunnelMaximumVersions ||
        versions.map((version) => version.surfaceRevisionId).toSet().length !=
            versions.length) {
      throw const CanonicalFormatException(
        '$path repeats or overruns its versions',
      );
    }
    return SurfaceFunnelViewV1._(
      target: target,
      surfaceId: surfaceId,
      surfaceType: surfaceType,
      windowStartMicros: windowStartMicros,
      windowEndExclusiveMicros: windowEndExclusiveMicros,
      asOfMicros: asOfMicros,
      disclosureFloor: disclosureFloor,
      versions: List.unmodifiable(versions),
    );
  }

  /// Decodes one strict funnel reading.
  factory SurfaceFunnelViewV1.fromJson(Map<String, Object?> json) {
    const path = 'surfaceFunnelView';
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'asOfMicros',
        'disclosureFloor',
        'kind',
        'schemaVersion',
        'surfaceId',
        'surfaceType',
        'target',
        'versions',
        'windowEndExclusiveMicros',
        'windowStartMicros',
      },
      requiredKeys: const {
        'asOfMicros',
        'disclosureFloor',
        'kind',
        'schemaVersion',
        'surfaceId',
        'target',
        'versions',
        'windowEndExclusiveMicros',
        'windowStartMicros',
      },
      path: path,
    );
    validateCanonicalDocument(reader, expectedKind: 'surfaceFunnelView');
    return SurfaceFunnelViewV1.of(
      target: TargetCoordinate.fromJson(reader.object('target')),
      surfaceId: reader.string('surfaceId'),
      surfaceType: reader.optionalString('surfaceType'),
      windowStartMicros: reader.integer('windowStartMicros'),
      windowEndExclusiveMicros: reader.integer('windowEndExclusiveMicros'),
      asOfMicros: reader.integer('asOfMicros'),
      disclosureFloor: reader.integer('disclosureFloor'),
      versions: [
        for (final (index, value) in reader.list('versions').indexed)
          SurfaceFunnelVersionV1.fromJson(
            requireCanonicalObject(value, '$path.versions[$index]'),
            path: '$path.versions[$index]',
          ),
      ],
    );
  }

  /// Decodes byte-exact canonical funnel JSON.
  factory SurfaceFunnelViewV1.fromCanonicalBytes(List<int> bytes) =>
      verifyCanonicalRoundTrip(
        SurfaceFunnelViewV1.fromJson(decodeCanonicalObject(bytes)),
        bytes,
        path: 'surfaceFunnelView',
      );

  /// The target these figures were read from.
  final TargetCoordinate target;

  /// The surface they describe.
  final String surfaceId;

  /// The surface's authored type, joined by the service; absent when the
  /// service could not resolve one.
  final String? surfaceType;

  /// Start of the half-open window, inclusive.
  final int windowStartMicros;

  /// End of the half-open window, exclusive.
  final int windowEndExclusiveMicros;

  /// The snapshot the figures were read at.
  final int asOfMicros;

  /// Smallest population this reading states numbers for.
  final int disclosureFloor;

  /// One entry per served published version, in publication order.
  final List<SurfaceFunnelVersionV1> versions;

  @override
  Map<String, Object?> toJson() => {
        'asOfMicros': asOfMicros,
        'disclosureFloor': disclosureFloor,
        'kind': 'surfaceFunnelView',
        'schemaVersion': kMeasurementSchemaVersion,
        'surfaceId': surfaceId,
        if (surfaceType != null) 'surfaceType': surfaceType,
        'target': target.toJson(),
        'versions': [for (final version in versions) version.toJson()],
        'windowEndExclusiveMicros': windowEndExclusiveMicros,
        'windowStartMicros': windowStartMicros,
      };
}

/// The arguments one funnel read sends, checked before the read opens.
///
/// Constructing this refuses a value the caller supplied with a message naming
/// the field, so a caller's own mistake is never reported as a service fault.
final class SurfaceFunnelSelectionV1 {
  /// Checks one selection's bounds.
  factory SurfaceFunnelSelectionV1({
    required String surfaceId,
    required int windowStartMicros,
    required int windowEndExclusiveMicros,
    List<String>? surfaceRevisionIds,
  }) {
    if (surfaceId.isEmpty || surfaceId.length > kSurfaceFunnelIdentityLimit) {
      throw const CanonicalFormatException(
        'surfaceId must name one surface, at most '
        '$kSurfaceFunnelIdentityLimit characters',
      );
    }
    if (windowStartMicros < 0) {
      throw const CanonicalFormatException(
        'windowStartMicros must not be negative',
      );
    }
    if (windowEndExclusiveMicros <= windowStartMicros) {
      throw const CanonicalFormatException(
        'windowEndExclusiveMicros must be after windowStartMicros',
      );
    }
    if (surfaceRevisionIds != null) {
      if (surfaceRevisionIds.isEmpty ||
          surfaceRevisionIds.length > kSurfaceFunnelMaximumVersions) {
        throw const CanonicalFormatException(
          'surfaceRevisionIds must name 1 to $kSurfaceFunnelMaximumVersions '
          'versions when present',
        );
      }
      if (surfaceRevisionIds.toSet().length != surfaceRevisionIds.length) {
        throw const CanonicalFormatException(
          'surfaceRevisionIds names the same version twice',
        );
      }
      if (surfaceRevisionIds.any((value) => value.isEmpty)) {
        throw const CanonicalFormatException(
          'surfaceRevisionIds names an empty version',
        );
      }
    }
    return SurfaceFunnelSelectionV1._(
      surfaceId: surfaceId,
      windowStartMicros: windowStartMicros,
      windowEndExclusiveMicros: windowEndExclusiveMicros,
      surfaceRevisionIds: surfaceRevisionIds == null
          ? null
          : List.unmodifiable(surfaceRevisionIds),
    );
  }

  const SurfaceFunnelSelectionV1._({
    required this.surfaceId,
    required this.windowStartMicros,
    required this.windowEndExclusiveMicros,
    required this.surfaceRevisionIds,
  });

  /// The surface to read.
  final String surfaceId;

  /// Start of the half-open window, inclusive.
  final int windowStartMicros;

  /// End of the half-open window, exclusive.
  final int windowEndExclusiveMicros;

  /// The exact published versions to read, or null for every version.
  final List<String>? surfaceRevisionIds;
}

/// Reads the authored transitions out of one closed transition object.
Map<String, List<String>> _transitions(
  Map<String, Object?> json,
  String path,
) {
  final transitions = <String, List<String>>{};
  for (final entry in json.entries) {
    final targets = entry.value;
    if (targets is! List<Object?>) {
      throw CanonicalFormatException('$path.${entry.key} must be a list');
    }
    transitions[entry.key] = [
      for (final value in targets)
        requireCanonicalString(value, '$path.${entry.key}'),
    ];
  }
  return transitions;
}

/// Requires a stated rate to be present exactly when [expected] is, and equal.
void _requireStatedRate(
  CanonicalObjectReader reader,
  String key,
  SurfaceFunnelRateV1? expected,
  String path,
) {
  final stated = reader.optionalObject(key);
  if ((stated == null) != (expected == null)) {
    throw CanonicalFormatException('$path.$key disagrees with its counts');
  }
  if (stated == null) return;
  final decoded = SurfaceFunnelRateV1.fromJson(stated, path: '$path.$key');
  if (decoded != expected) {
    throw CanonicalFormatException('$path.$key disagrees with its counts');
  }
}
