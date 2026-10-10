import 'package:restage_measurement_schema/src/canonical.dart';
import 'package:restage_measurement_schema/src/delivery_identity.dart';
import 'package:restage_measurement_schema/src/delivery_management.dart';

/// Gregorian local civil time with second precision and no time-zone identity.
final class LocalCivilDateTimeV1 extends CanonicalValue
    implements ImmutableCanonicalDocument, Comparable<LocalCivilDateTimeV1> {
  /// Creates a validated date and time without overflow normalization.
  LocalCivilDateTimeV1({
    required this.year,
    required this.month,
    required this.day,
    this.hour = 0,
    this.minute = 0,
    this.second = 0,
  }) {
    _requireRange(year, 1, 9999, 'year');
    _requireRange(month, 1, 12, 'month');
    _requireRange(day, 1, _daysInMonth(year, month), 'day');
    _requireRange(hour, 0, 23, 'hour');
    _requireRange(minute, 0, 59, 'minute');
    _requireRange(second, 0, 59, 'second');
  }

  /// Parses exactly `YYYY-MM-DDTHH:mm:ss` with no zone or fractional seconds.
  factory LocalCivilDateTimeV1.parse(String value) {
    if (value.length != 19 || !_civilTimePattern.hasMatch(value)) {
      throw const CanonicalFormatException(
        'Expected local civil time YYYY-MM-DDTHH:mm:ss',
      );
    }
    return _constructCalendar(
      'localCivilDateTime',
      () => LocalCivilDateTimeV1(
        year: int.parse(value.substring(0, 4)),
        month: int.parse(value.substring(5, 7)),
        day: int.parse(value.substring(8, 10)),
        hour: int.parse(value.substring(11, 13)),
        minute: int.parse(value.substring(14, 16)),
        second: int.parse(value.substring(17, 19)),
      ),
    );
  }

  /// Decodes byte-exact canonical civil-time bytes.
  factory LocalCivilDateTimeV1.fromCanonicalBytes(List<int> bytes) =>
      verifyCanonicalRoundTrip(
        LocalCivilDateTimeV1.fromJson(decodeCanonicalObject(bytes)),
        bytes,
        path: 'localCivilDateTime',
      );

  /// Decodes one closed local civil time.
  factory LocalCivilDateTimeV1.fromJson(Map<String, Object?> json) {
    final reader = _calendarReader(json, 'localCivilDateTime', const {'value'});
    return LocalCivilDateTimeV1.parse(reader.string('value'));
  }

  /// Gregorian year, 1 through 9999.
  final int year;

  /// Month, 1 through 12.
  final int month;

  /// Day within the validated Gregorian month.
  final int day;

  /// Hour, 0 through 23.
  final int hour;

  /// Minute, 0 through 59.
  final int minute;

  /// Second, 0 through 59.
  final int second;

  /// Fixed canonical local spelling with no zone suffix.
  String get value => '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}T'
      '${hour.toString().padLeft(2, '0')}:'
      '${minute.toString().padLeft(2, '0')}:'
      '${second.toString().padLeft(2, '0')}';

  @override
  int compareTo(LocalCivilDateTimeV1 other) => value.compareTo(other.value);

  @override
  Map<String, Object?> toJson() =>
      {'kind': 'localCivilDateTime', 'value': value};

  @override
  String toString() => value;
}

/// A local decision window with an inclusive start and exclusive end.
final class LocalDeliveryWindowV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  /// Requires at least one endpoint and increasing endpoints when both exist.
  LocalDeliveryWindowV1({this.startsInclusive, this.endsExclusive}) {
    if (startsInclusive == null && endsExclusive == null) {
      throw ArgumentError(
        'A local delivery window requires at least one endpoint',
      );
    }
    if (startsInclusive != null &&
        endsExclusive != null &&
        startsInclusive!.compareTo(endsExclusive!) >= 0) {
      throw ArgumentError('A local delivery window must have start before end');
    }
  }

  /// Decodes byte-exact canonical local-window bytes.
  factory LocalDeliveryWindowV1.fromCanonicalBytes(List<int> bytes) =>
      verifyCanonicalRoundTrip(
        LocalDeliveryWindowV1.fromJson(decodeCanonicalObject(bytes)),
        bytes,
        path: 'localDeliveryWindow',
      );

  /// Decodes a closed local window with omitted unbounded endpoints.
  factory LocalDeliveryWindowV1.fromJson(Map<String, Object?> json) {
    final reader = _calendarReader(
      json,
      'localDeliveryWindow',
      const {},
      optional: const {'startsInclusive', 'endsExclusive'},
    );
    final start = reader.optionalObject('startsInclusive');
    final end = reader.optionalObject('endsExclusive');
    return _constructCalendar(
      'localDeliveryWindow',
      () => LocalDeliveryWindowV1(
        startsInclusive:
            start == null ? null : LocalCivilDateTimeV1.fromJson(start),
        endsExclusive: end == null ? null : LocalCivilDateTimeV1.fromJson(end),
      ),
    );
  }

  /// Inclusive civil lower bound, absent for an unbounded start.
  final LocalCivilDateTimeV1? startsInclusive;

  /// Exclusive civil upper bound, absent for an unbounded end.
  final LocalCivilDateTimeV1? endsExclusive;

  /// Whether [now] is inside this local civil interval.
  bool contains(LocalCivilDateTimeV1 now) =>
      (startsInclusive == null || now.compareTo(startsInclusive!) >= 0) &&
      (endsExclusive == null || now.compareTo(endsExclusive!) < 0);

  @override
  Map<String, Object?> toJson() => {
        if (endsExclusive != null) 'endsExclusive': endsExclusive!.toJson(),
        'kind': 'localDeliveryWindow',
        if (startsInclusive != null)
          'startsInclusive': startsInclusive!.toJson(),
      };
}

/// Request-only evidence of the device's current UTC offset in minutes.
final class DeliveryLocalClockV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  /// Accepts integer offsets from -1080 through 1080 minutes.
  DeliveryLocalClockV1(this.utcOffsetMinutes) {
    _requireRange(utcOffsetMinutes, -1080, 1080, 'utcOffsetMinutes');
  }

  /// Decodes byte-exact canonical local-clock bytes.
  factory DeliveryLocalClockV1.fromCanonicalBytes(List<int> bytes) =>
      verifyCanonicalRoundTrip(
        DeliveryLocalClockV1.fromJson(decodeCanonicalObject(bytes)),
        bytes,
        path: 'deliveryLocalClock',
      );

  /// Decodes explicit local-clock evidence; an absent offset is invalid.
  factory DeliveryLocalClockV1.fromJson(Map<String, Object?> json) {
    final reader =
        _calendarReader(json, 'deliveryLocalClock', const {'utcOffsetMinutes'});
    return _constructCalendar(
      'deliveryLocalClock',
      () => DeliveryLocalClockV1(
        reader.integer('utcOffsetMinutes'),
      ),
    );
  }

  /// Current offset supplied for this request.
  final int utcOffsetMinutes;

  /// Computes current civil time from portable UTC micros and this offset.
  LocalCivilDateTimeV1 localNow({required int nowMicros}) {
    _requireRange(
      nowMicros,
      kMinimumPortableJsonInteger,
      kMaximumPortableJsonInteger,
      'nowMicros',
    );
    const microsPerMinute = 60 * 1000000;
    final offsetMicros = utcOffsetMinutes * microsPerMinute;
    if ((offsetMicros > 0 &&
            nowMicros > kMaximumPortableJsonInteger - offsetMicros) ||
        (offsetMicros < 0 &&
            nowMicros < kMinimumPortableJsonInteger - offsetMicros)) {
      throw ArgumentError(
        'Local clock offset exceeds the portable integer range',
      );
    }
    final local = DateTime.fromMicrosecondsSinceEpoch(
      nowMicros + offsetMicros,
      isUtc: true,
    );
    return LocalCivilDateTimeV1(
      year: local.year,
      month: local.month,
      day: local.day,
      hour: local.hour,
      minute: local.minute,
      second: local.second,
    );
  }

  @override
  Map<String, Object?> toJson() => {
        'kind': 'deliveryLocalClock',
        'utcOffsetMinutes': utcOffsetMinutes,
      };
}

/// Exact policy selections and bounds that qualify one cached delivery.
final class DeliveryCacheValidityV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  /// Copies at most two ordered policy selections and validates cache bounds.
  DeliveryCacheValidityV1({
    required List<DeliveryPolicyDocumentSelectionV1> policySelections,
    required this.hostContractHash,
    required this.installedCapabilityHash,
    required this.selectionIdentityDigest,
    this.notBeforeLocal,
    this.expiresBeforeLocal,
    this.receiptExpiresAtMicros,
    this.assignmentExpiresAtMicros,
    this.contentExpiresAtMicros,
  }) : policySelections = _freezePolicySelections(policySelections) {
    if (notBeforeLocal != null &&
        expiresBeforeLocal != null &&
        notBeforeLocal!.compareTo(expiresBeforeLocal!) >= 0) {
      throw ArgumentError('Cache local interval must have start before end');
    }
    for (final (field, value) in [
      ('receiptExpiresAtMicros', receiptExpiresAtMicros),
      ('assignmentExpiresAtMicros', assignmentExpiresAtMicros),
      ('contentExpiresAtMicros', contentExpiresAtMicros),
    ]) {
      if (value != null) {
        _requireRange(value, 0, kMaximumPortableJsonInteger, field);
      }
    }
    _requireSha256Hash(hostContractHash, 'hostContractHash');
    _requireSha256Hash(installedCapabilityHash, 'installedCapabilityHash');
  }

  /// Decodes byte-exact canonical cache-validity bytes.
  factory DeliveryCacheValidityV1.fromCanonicalBytes(List<int> bytes) =>
      verifyCanonicalRoundTrip(
        DeliveryCacheValidityV1.fromJson(decodeCanonicalObject(bytes)),
        bytes,
        path: 'deliveryCacheValidity',
      );

  /// Decodes closed cache evidence without evaluating clock or lease authority.
  factory DeliveryCacheValidityV1.fromJson(Map<String, Object?> json) {
    const path = 'deliveryCacheValidity';
    final reader = _calendarReader(
      json,
      path,
      const {
        'policySelections',
        'hostContractHash',
        'installedCapabilityHash',
        'selectionIdentityDigest',
      },
      optional: const {
        'notBeforeLocal',
        'expiresBeforeLocal',
        'receiptExpiresAtMicros',
        'assignmentExpiresAtMicros',
        'contentExpiresAtMicros',
      },
    );
    final selections = reader.list('policySelections');
    if (selections.length > 2) {
      throw const CanonicalFormatException(
        'Cache validity accepts at most two policy selections',
      );
    }
    final start = reader.optionalObject('notBeforeLocal');
    final end = reader.optionalObject('expiresBeforeLocal');
    return _constructCalendar(
      path,
      () => DeliveryCacheValidityV1(
        policySelections: [
          for (final selection in selections)
            DeliveryPolicyDocumentSelectionV1.fromJson(
              requireCanonicalObject(selection, '$path.policySelections[]'),
            ),
        ],
        notBeforeLocal:
            start == null ? null : LocalCivilDateTimeV1.fromJson(start),
        expiresBeforeLocal:
            end == null ? null : LocalCivilDateTimeV1.fromJson(end),
        receiptExpiresAtMicros:
            reader.optionalInteger('receiptExpiresAtMicros'),
        assignmentExpiresAtMicros:
            reader.optionalInteger('assignmentExpiresAtMicros'),
        contentExpiresAtMicros:
            reader.optionalInteger('contentExpiresAtMicros'),
        hostContractHash: reader.string('hostContractHash'),
        installedCapabilityHash: reader.string('installedCapabilityHash'),
        selectionIdentityDigest:
            CanonicalDigest(reader.string('selectionIdentityDigest')),
      ),
    );
  }

  /// Optional placement selection followed by optional surface selection.
  final List<DeliveryPolicyDocumentSelectionV1> policySelections;

  /// Inclusive local lower bound; absent for an unbounded start.
  final LocalCivilDateTimeV1? notBeforeLocal;

  /// Exclusive local upper bound; absent for an unbounded end.
  final LocalCivilDateTimeV1? expiresBeforeLocal;

  /// Absolute receipt expiry in nonnegative portable UTC micros, when present.
  final int? receiptExpiresAtMicros;

  /// Absolute assignment expiry in nonnegative portable UTC micros.
  final int? assignmentExpiresAtMicros;

  /// Absolute content expiry in nonnegative portable UTC micros, when present.
  final int? contentExpiresAtMicros;

  /// Exact host-contract hash in canonical `sha256:` form.
  final String hostContractHash;

  /// Exact installed-capability hash in canonical `sha256:` form.
  final String installedCapabilityHash;

  /// Digest of safe selected identity/path bytes excluding cache and credentials.
  final CanonicalDigest selectionIdentityDigest;

  @override
  Map<String, Object?> toJson() => {
        'kind': 'deliveryCacheValidity',
        'policySelections':
            policySelections.map((value) => value.toJson()).toList(
                  growable: false,
                ),
        if (notBeforeLocal != null) 'notBeforeLocal': notBeforeLocal!.toJson(),
        if (expiresBeforeLocal != null)
          'expiresBeforeLocal': expiresBeforeLocal!.toJson(),
        if (receiptExpiresAtMicros != null)
          'receiptExpiresAtMicros': receiptExpiresAtMicros,
        if (assignmentExpiresAtMicros != null)
          'assignmentExpiresAtMicros': assignmentExpiresAtMicros,
        if (contentExpiresAtMicros != null)
          'contentExpiresAtMicros': contentExpiresAtMicros,
        'hostContractHash': hostContractHash,
        'installedCapabilityHash': installedCapabilityHash,
        'selectionIdentityDigest': selectionIdentityDigest.hex,
      };
}

List<DeliveryPolicyDocumentSelectionV1> _freezePolicySelections(
  List<DeliveryPolicyDocumentSelectionV1> selections,
) {
  if (selections.length > 2) {
    throw ArgumentError('Cache validity accepts at most two policy selections');
  }
  final scopes = <DeliveryPolicyScopeV1>{};
  for (var index = 0; index < selections.length; index++) {
    final scope = selections[index].policyRevision.scope;
    if (!scopes.add(scope)) {
      throw ArgumentError('Cache validity requires unique policy scopes');
    }
    if (index > 0) {
      final previousScope = selections[index - 1].policyRevision.scope;
      if (scope.target != previousScope.target) {
        throw ArgumentError('Cache policy targets must agree');
      }
      if (!previousScope.root.isPlacement || scope.root.isPlacement) {
        throw ArgumentError('Cache selections must be placement then surface');
      }
    }
  }
  return List.unmodifiable(selections);
}

final _sha256HashPattern = RegExp(r'^sha256:[0-9a-f]{64}$');

void _requireSha256Hash(String value, String field) {
  if (value.length != 71 || !_sha256HashPattern.hasMatch(value)) {
    throw ArgumentError.value(
      value,
      field,
      'Expected sha256:<64 lowercase hex>',
    );
  }
}

final _civilTimePattern =
    RegExp(r'^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}$');

int _daysInMonth(int year, int month) => switch (month) {
      2 => year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) ? 29 : 28,
      4 || 6 || 9 || 11 => 30,
      _ => 31,
    };

CanonicalObjectReader _calendarReader(
  Map<String, Object?> json,
  String kind,
  Set<String> required, {
  Set<String> optional = const {},
}) {
  final reader = CanonicalObjectReader(
    json,
    allowedKeys: {'kind', ...required, ...optional},
    requiredKeys: {'kind', ...required},
    path: kind,
  );
  if (reader.string('kind') != kind) {
    throw CanonicalFormatException('Expected $kind');
  }
  return reader;
}

T _constructCalendar<T>(String path, T Function() build) {
  try {
    return build();
    // Constructor refusals become canonical-format refusals when decoding.
    // ignore: avoid_catching_errors
  } on ArgumentError catch (error) {
    throw CanonicalFormatException('$path is invalid: ${error.message}');
  }
}

void _requireRange(int value, int minimum, int maximum, String field) {
  if (value < minimum || value > maximum) {
    throw ArgumentError.value(value, field, 'Expected $minimum..$maximum');
  }
}
