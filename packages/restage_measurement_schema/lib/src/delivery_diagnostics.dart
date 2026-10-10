/// Canonical operator diagnostics for one surface's delivery decisions.
///
/// The two sections deliberately describe different observed populations:
/// admitted served defaults come from retained root-selection rows, while
/// recorded server refusals come from the serving boundary's daily aggregate.
/// Neither population counts people, devices, or every network request.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:restage_measurement_schema/restage_measurement_schema.dart';

/// Microseconds in one UTC day.
const int measurementDeliveryDiagnosticsDayMicros = 86400000000;

/// Measurement retention window in integer microseconds.
/// Must match the server's raw Measurement retention window.
const int measurementDeliveryDiagnosticsRetentionWindowMicros = 7776000000000;

/// The floor below which a reason keeps its name but states no count.
///
/// The backend obtains this from the shared Measurement disclosure owner. It
/// travels here so a consumer can distinguish a held reading from zero.
const int measurementDeliveryDiagnosticsDisclosureFloor = 5;

/// Maximum reason groups carried by either diagnostic population.
///
/// This bounds a strict operator response. A wider stored vocabulary is
/// refused by the server rather than silently truncated or folded.
const int measurementDeliveryDiagnosticsMaximumReasonEntries = 1000;

/// Maximum UTF-8 bytes in one stored delivery reason.
///
/// The corresponding Measurement relation admits at most 256 Unicode
/// characters, which can occupy at most four UTF-8 bytes each.
const int measurementDeliveryDiagnosticsMaximumReasonUtf8Bytes = 1024;

/// Maximum canonical bytes in one complete diagnostics response.
///
/// This bounds the public `ByteData` decode and result allocation. It covers
/// two independently bounded reason populations and matches the existing
/// public operator-result ceiling.
const int measurementDeliveryDiagnosticsMaximumCanonicalBytes =
    16 * 1024 * 1024;

/// The two non-interchangeable populations this read can describe.
enum MeasurementDeliveryDiagnosticsPopulationV1 {
  /// Retained selections joined to server-admitted root presentations.
  servedDefaultPresentations('servedDefaultPresentations'),

  /// Refusal decisions recorded once at the authenticated serving boundary.
  recordedServerRefusals('recordedServerRefusals');

  const MeasurementDeliveryDiagnosticsPopulationV1(this.wireName);

  /// Stable canonical spelling.
  final String wireName;

  /// Decodes an exact known population.
  static MeasurementDeliveryDiagnosticsPopulationV1 fromWire(String wireName) {
    for (final value in values) {
      if (value.wireName == wireName) return value;
    }
    throw CanonicalFormatException(
      'Unknown delivery diagnostics population "$wireName"',
    );
  }
}

/// What a section's observations do and do not cover.
enum MeasurementDeliveryDiagnosticsCoverageV1 {
  /// Retained, server-admitted selections only; not requests that refused.
  observedAdmittedPresentations('observedAdmittedPresentations'),

  /// Server decisions whose post-decision aggregate recording succeeded.
  observedRecordedServerRefusals('observedRecordedServerRefusals');

  const MeasurementDeliveryDiagnosticsCoverageV1(this.wireName);

  /// Stable canonical spelling.
  final String wireName;

  /// Decodes an exact known coverage description.
  static MeasurementDeliveryDiagnosticsCoverageV1 fromWire(String wireName) {
    for (final value in values) {
      if (value.wireName == wireName) return value;
    }
    throw CanonicalFormatException(
      'Unknown delivery diagnostics coverage "$wireName"',
    );
  }
}

/// Whether a section can state reason counts.
enum MeasurementDeliveryDiagnosticsAvailabilityV1 {
  /// No retained observation exists for this population and scope.
  unavailable('unavailable'),

  /// Observations exist, but every reason count is held at the floor.
  held('held'),

  /// Some reason counts are held and some are disclosed.
  partiallyHeld('partiallyHeld'),

  /// Every observed reason count is disclosed; this may be an observed empty.
  disclosed('disclosed');

  const MeasurementDeliveryDiagnosticsAvailabilityV1(this.wireName);

  /// Stable canonical spelling.
  final String wireName;

  /// Decodes an exact known availability state.
  static MeasurementDeliveryDiagnosticsAvailabilityV1 fromWire(
    String wireName,
  ) {
    for (final value in values) {
      if (value.wireName == wireName) return value;
    }
    throw CanonicalFormatException(
      'Unknown delivery diagnostics availability "$wireName"',
    );
  }
}

/// Delivery surface types accepted by operator diagnostics.
/// The server maps its enum exhaustively to this vocabulary.
enum MeasurementDeliveryDiagnosticsSurfaceTypeV1 {
  /// The onboarding surface.
  onboarding('onboarding'),

  /// The in-app message surface.
  message('message'),

  /// The survey surface.
  survey('survey'),

  /// The paywall surface.
  paywall('paywall'),

  /// A general, non-typed surface.
  general('general');

  const MeasurementDeliveryDiagnosticsSurfaceTypeV1(this.wireName);

  /// Stable canonical spelling.
  final String wireName;

  /// Decodes an exact closed surface type.
  static MeasurementDeliveryDiagnosticsSurfaceTypeV1 fromWire(
    String wireName,
  ) {
    for (final value in values) {
      if (value.wireName == wireName) return value;
    }
    throw CanonicalFormatException(
      'Unknown delivery diagnostics surface type "$wireName"',
    );
  }
}

/// One server-owned reason and its count when disclosure permits it.
///
/// [reason] remains a string because served-default rows preserve their
/// stored vocabulary. That includes `frozen` and a future producer's unknown
/// reason rather than silently classifying either as an ordinary default.
final class MeasurementDeliveryDiagnosticsReasonCountV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  /// Creates one disclosed or held reason entry.
  MeasurementDeliveryDiagnosticsReasonCountV1({
    required this.reason,
    this.observedCount,
  }) {
    final bytes = utf8.encode(reason);
    if (reason.runes.isEmpty ||
        reason.runes.length > 256 ||
        bytes.length > measurementDeliveryDiagnosticsMaximumReasonUtf8Bytes) {
      throw ArgumentError.value(
        reason,
        'reason',
        'must contain 1 through 256 characters and '
            '$measurementDeliveryDiagnosticsMaximumReasonUtf8Bytes UTF-8 bytes',
      );
    }
    if (observedCount != null &&
        (observedCount! < measurementDeliveryDiagnosticsDisclosureFloor ||
            observedCount! > kMaximumPortableJsonInteger)) {
      throw ArgumentError.value(
        observedCount,
        'observedCount',
        'must clear the disclosure floor and be JSON-portable when stated',
      );
    }
  }

  /// Decodes one exact reason entry.
  factory MeasurementDeliveryDiagnosticsReasonCountV1.fromJson(
    Map<String, Object?> json,
  ) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'observedCount', 'reason'},
      requiredKeys: const {'reason'},
      path: 'measurementDeliveryDiagnosticsReasonCount',
    );
    return MeasurementDeliveryDiagnosticsReasonCountV1(
      reason: reader.string('reason'),
      observedCount: reader.optionalInteger('observedCount'),
    );
  }

  /// Exact stored reason vocabulary.
  final String reason;

  /// Observed member count, when disclosure permits it.
  ///
  /// Its population is named by the enclosing section, so a consumer never
  /// mistakes an admitted presentation count for a refusal-request count.
  final int? observedCount;

  @override
  Map<String, Object?> toJson() => {
        'reason': reason,
        if (observedCount != null) 'observedCount': observedCount,
      };
}

/// One population's reason distribution and its truthfully narrow coverage.
final class MeasurementDeliveryDiagnosticsSectionV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  /// Creates one section, requiring canonical reason order and availability.
  MeasurementDeliveryDiagnosticsSectionV1({
    required this.population,
    required this.coverage,
    required this.availability,
    required List<MeasurementDeliveryDiagnosticsReasonCountV1> reasons,
  }) : reasons = List.unmodifiable(reasons) {
    if (reasons.length > measurementDeliveryDiagnosticsMaximumReasonEntries) {
      throw ArgumentError.value(
        reasons.length,
        'reasons',
        'must contain at most $measurementDeliveryDiagnosticsMaximumReasonEntries entries',
      );
    }
    if (!_coverageMatchesPopulation(population, coverage)) {
      throw ArgumentError(
          'The population and coverage must name the same read');
    }
    final names = [for (final entry in reasons) entry.reason];
    if (names.toSet().length != names.length || !_isStrictlySorted(names)) {
      throw ArgumentError(
          'Reasons must be unique and sorted by their spelling');
    }
    final stated = reasons.where((entry) => entry.observedCount != null).length;
    switch (availability) {
      case MeasurementDeliveryDiagnosticsAvailabilityV1.unavailable:
        if (reasons.isNotEmpty) {
          throw ArgumentError('An unavailable section names no reasons');
        }
      case MeasurementDeliveryDiagnosticsAvailabilityV1.held:
        if (reasons.isEmpty || stated != 0) {
          throw ArgumentError(
              'A held section has observed, wholly held reasons');
        }
      case MeasurementDeliveryDiagnosticsAvailabilityV1.partiallyHeld:
        if (stated == 0 || stated == reasons.length) {
          throw ArgumentError(
              'A partly held section states and holds a reason');
        }
      case MeasurementDeliveryDiagnosticsAvailabilityV1.disclosed:
        if (stated != reasons.length) {
          throw ArgumentError('A disclosed section states every named reason');
        }
    }
  }

  /// Decodes one exact diagnostics section.
  factory MeasurementDeliveryDiagnosticsSectionV1.fromJson(
    Map<String, Object?> json,
  ) {
    const keys = {'availability', 'coverage', 'population', 'reasons'};
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: keys,
      requiredKeys: keys,
      path: 'measurementDeliveryDiagnosticsSection',
    );
    return MeasurementDeliveryDiagnosticsSectionV1(
      population: MeasurementDeliveryDiagnosticsPopulationV1.fromWire(
        reader.string('population'),
      ),
      coverage: MeasurementDeliveryDiagnosticsCoverageV1.fromWire(
        reader.string('coverage'),
      ),
      availability: MeasurementDeliveryDiagnosticsAvailabilityV1.fromWire(
        reader.string('availability'),
      ),
      reasons: [
        for (final value in reader.list('reasons'))
          MeasurementDeliveryDiagnosticsReasonCountV1.fromJson(
            requireCanonicalObject(
                value, 'measurementDeliveryDiagnostics.reasons[]'),
          ),
      ],
    );
  }

  /// Population the reason entries describe.
  final MeasurementDeliveryDiagnosticsPopulationV1 population;

  /// Coverage statement inseparable from [population].
  final MeasurementDeliveryDiagnosticsCoverageV1 coverage;

  /// Disclosure and observation state for the whole section.
  final MeasurementDeliveryDiagnosticsAvailabilityV1 availability;

  /// Reasons in deterministic lexical order; held counts are null.
  final List<MeasurementDeliveryDiagnosticsReasonCountV1> reasons;

  @override
  Map<String, Object?> toJson() => {
        'availability': availability.wireName,
        'coverage': coverage.wireName,
        'population': population.wireName,
        'reasons': [for (final reason in reasons) reason.toJson()],
      };
}

/// The canonical bounded diagnostic read for one resolved delivery scope.
final class MeasurementDeliveryDiagnosticsV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  /// Creates a complete strict delivery diagnostic read.
  MeasurementDeliveryDiagnosticsV1({
    required this.target,
    required this.surfaceType,
    required this.surfaceSlug,
    required this.contractVersion,
    required this.windowStartDayUtc,
    required this.windowEndDayExclusiveUtc,
    required this.disclosureFloor,
    required this.servedDefaults,
    required this.recordedRefusals,
  }) {
    if (surfaceSlug.isEmpty || utf8.encode(surfaceSlug).length > 256) {
      throw ArgumentError.value(surfaceSlug, 'surfaceSlug', 'must be bounded');
    }
    if (contractVersion != null && contractVersion! < 1) {
      throw ArgumentError.value(
        contractVersion,
        'contractVersion',
        'must be positive when a typed family is named',
      );
    }
    if (disclosureFloor != measurementDeliveryDiagnosticsDisclosureFloor ||
        !_isWholeBoundedUtcDayWindow(
          start: windowStartDayUtc,
          end: windowEndDayExclusiveUtc,
        )) {
      throw ArgumentError('The diagnostics scope is not a retained UTC window');
    }
    if (servedDefaults.population !=
            MeasurementDeliveryDiagnosticsPopulationV1
                .servedDefaultPresentations ||
        recordedRefusals.population !=
            MeasurementDeliveryDiagnosticsPopulationV1.recordedServerRefusals) {
      throw ArgumentError('The two diagnostic sections have fixed populations');
    }
    _validateCanonicalByteBound();
  }

  /// Decodes byte-exact canonical JSON.
  factory MeasurementDeliveryDiagnosticsV1.fromCanonicalBytes(List<int> bytes) {
    if (bytes.length > measurementDeliveryDiagnosticsMaximumCanonicalBytes) {
      throw CanonicalFormatException(
        'measurementDeliveryDiagnostics exceeds '
        '$measurementDeliveryDiagnosticsMaximumCanonicalBytes canonical bytes',
      );
    }
    return verifyCanonicalRoundTrip(
      MeasurementDeliveryDiagnosticsV1.fromJson(decodeCanonicalObject(bytes)),
      bytes,
      path: 'measurementDeliveryDiagnostics',
    );
  }

  /// Decodes the closed diagnostic transport object.
  factory MeasurementDeliveryDiagnosticsV1.fromJson(Map<String, Object?> json) {
    const keys = {
      'contractVersion',
      'disclosureFloor',
      'kind',
      'recordedRefusals',
      'schemaVersion',
      'servedDefaults',
      'surfaceSlug',
      'surfaceTypeWireName',
      'target',
      'windowEndDayExclusiveUtc',
      'windowStartDayUtc',
    };
    const requiredKeys = {
      'disclosureFloor',
      'kind',
      'recordedRefusals',
      'schemaVersion',
      'servedDefaults',
      'surfaceSlug',
      'surfaceTypeWireName',
      'target',
      'windowEndDayExclusiveUtc',
      'windowStartDayUtc',
    };
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: keys,
      requiredKeys: requiredKeys,
      path: 'measurementDeliveryDiagnostics',
    );
    if (reader.string('kind') != 'measurementDeliveryDiagnostics' ||
        reader.integer('schemaVersion') != 1) {
      throw const CanonicalFormatException(
        'Expected measurementDeliveryDiagnostics schema version 1',
      );
    }
    return MeasurementDeliveryDiagnosticsV1(
      target: TargetCoordinate.fromJson(reader.object('target')),
      surfaceType: MeasurementDeliveryDiagnosticsSurfaceTypeV1.fromWire(
        reader.string('surfaceTypeWireName'),
      ),
      surfaceSlug: reader.string('surfaceSlug'),
      contractVersion: reader.optionalInteger('contractVersion'),
      windowStartDayUtc: reader.integer('windowStartDayUtc'),
      windowEndDayExclusiveUtc: reader.integer('windowEndDayExclusiveUtc'),
      disclosureFloor: reader.integer('disclosureFloor'),
      servedDefaults: MeasurementDeliveryDiagnosticsSectionV1.fromJson(
        reader.object('servedDefaults'),
      ),
      recordedRefusals: MeasurementDeliveryDiagnosticsSectionV1.fromJson(
        reader.object('recordedRefusals'),
      ),
    );
  }

  /// Exact resolved target; runtime plane is never inferred by a consumer.
  final TargetCoordinate target;

  /// Closed server-resolved delivery surface type.
  final MeasurementDeliveryDiagnosticsSurfaceTypeV1 surfaceType;

  /// Server-resolved surface slug.
  final String surfaceSlug;

  /// Typed contract family, or null for the general surface scope.
  final int? contractVersion;

  /// First UTC day included, in microseconds.
  final int windowStartDayUtc;

  /// UTC-day-exclusive end, in microseconds.
  final int windowEndDayExclusiveUtc;

  /// Shared Measurement disclosure floor used for every stated count.
  final int disclosureFloor;

  /// Retained admitted default presentations, never refusal requests.
  final MeasurementDeliveryDiagnosticsSectionV1 servedDefaults;

  /// Recorded server refusal decisions, never a request census.
  final MeasurementDeliveryDiagnosticsSectionV1 recordedRefusals;

  /// Canonical wire spelling of [surfaceType].
  String get surfaceTypeWireName => surfaceType.wireName;

  @override
  Uint8List get canonicalBytes {
    final bytes = super.canonicalBytes;
    if (bytes.length > measurementDeliveryDiagnosticsMaximumCanonicalBytes) {
      throw ArgumentError(
        'Delivery diagnostics exceed '
        '$measurementDeliveryDiagnosticsMaximumCanonicalBytes canonical bytes',
      );
    }
    return bytes;
  }

  @override
  Map<String, Object?> toJson() => {
        if (contractVersion != null) 'contractVersion': contractVersion,
        'disclosureFloor': disclosureFloor,
        'kind': 'measurementDeliveryDiagnostics',
        'recordedRefusals': recordedRefusals.toJson(),
        'schemaVersion': 1,
        'servedDefaults': servedDefaults.toJson(),
        'surfaceSlug': surfaceSlug,
        'surfaceTypeWireName': surfaceTypeWireName,
        'target': target.toJson(),
        'windowEndDayExclusiveUtc': windowEndDayExclusiveUtc,
        'windowStartDayUtc': windowStartDayUtc,
      };
}

bool _coverageMatchesPopulation(
  MeasurementDeliveryDiagnosticsPopulationV1 population,
  MeasurementDeliveryDiagnosticsCoverageV1 coverage,
) =>
    switch (population) {
      MeasurementDeliveryDiagnosticsPopulationV1.servedDefaultPresentations =>
        coverage ==
            MeasurementDeliveryDiagnosticsCoverageV1
                .observedAdmittedPresentations,
      MeasurementDeliveryDiagnosticsPopulationV1.recordedServerRefusals =>
        coverage ==
            MeasurementDeliveryDiagnosticsCoverageV1
                .observedRecordedServerRefusals,
    };

bool _isStrictlySorted(List<String> values) {
  for (var index = 1; index < values.length; index++) {
    if (values[index - 1].compareTo(values[index]) >= 0) return false;
  }
  return true;
}

bool _isWholeBoundedUtcDayWindow({required int start, required int end}) =>
    start > 0 &&
    end > start &&
    start.remainder(measurementDeliveryDiagnosticsDayMicros) == 0 &&
    end.remainder(measurementDeliveryDiagnosticsDayMicros) == 0 &&
    end <= kMaximumPortableJsonInteger &&
    (end - start) <= measurementDeliveryDiagnosticsRetentionWindowMicros;

extension on MeasurementDeliveryDiagnosticsV1 {
  void _validateCanonicalByteBound() {
    if (canonicalBytes.length >
        measurementDeliveryDiagnosticsMaximumCanonicalBytes) {
      throw ArgumentError(
        'Delivery diagnostics exceed '
        '$measurementDeliveryDiagnosticsMaximumCanonicalBytes canonical bytes',
      );
    }
  }
}
