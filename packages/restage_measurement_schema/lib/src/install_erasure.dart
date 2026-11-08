import 'package:restage_measurement_schema/src/canonical.dart';
import 'package:restage_measurement_schema/src/target.dart';

/// Possession authority for erasing the current installation's keyed records.
final class MeasurementInstallErasureRequestV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  /// Creates a bounded request without exposing its authority in errors.
  MeasurementInstallErasureRequestV1({
    required this.operationId,
    required this.assignmentKey,
  }) {
    _requireOperationId(operationId);
    if (RegExp(r'^ic1\.[0-9a-f]{64}$').stringMatch(assignmentKey) !=
        assignmentKey) {
      throw const CanonicalFormatException('Invalid install erasure authority');
    }
  }

  /// Decodes a strict request object.
  factory MeasurementInstallErasureRequestV1.fromJson(
    Map<String, Object?> json,
  ) =>
      _safeDecode(() {
        final reader = _reader(json, 'measurementInstallErasureRequest', const {
          'operationId',
          'assignmentKey',
        });
        return MeasurementInstallErasureRequestV1(
          operationId: reader.string('operationId'),
          assignmentKey: reader.string('assignmentKey'),
        );
      });

  /// Decodes only the canonical byte representation.
  factory MeasurementInstallErasureRequestV1.fromCanonicalBytes(
    List<int> bytes,
  ) =>
      _safeDecode(
        () => verifyCanonicalRoundTrip(
          MeasurementInstallErasureRequestV1.fromJson(
            decodeCanonicalObject(bytes),
          ),
          bytes,
          path: 'measurementInstallErasureRequest',
        ),
      );

  /// Opaque idempotency identifier for this operation.
  final String operationId;

  /// Service-issued installation credential, never suitable for diagnostics.
  final String assignmentKey;

  @override
  Map<String, Object?> toJson() => {
        'kind': 'measurementInstallErasureRequest',
        'schemaVersion': kMeasurementSchemaVersion,
        'operationId': operationId,
        'assignmentKey': assignmentKey,
      };
}

/// Minimal confirmation of completed current-install erasure.
final class MeasurementInstallErasureReceiptV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  /// Creates a completion receipt containing no subject identity or counts.
  MeasurementInstallErasureReceiptV1({
    required this.operationId,
    required this.target,
    required this.completedAtServerTimeMicros,
  }) {
    _requireOperationId(operationId);
    if (completedAtServerTimeMicros <= 0 ||
        completedAtServerTimeMicros > kMaximumPortableJsonInteger) {
      throw const CanonicalFormatException('Invalid erasure completion time');
    }
  }

  /// Decodes a strict receipt object with fixed scope and categories.
  factory MeasurementInstallErasureReceiptV1.fromJson(
    Map<String, Object?> json,
  ) =>
      _safeDecode(() {
        final reader = _reader(json, 'measurementInstallErasureReceipt', const {
          'operationId',
          'target',
          'scope',
          'categories',
          'completedAtServerTimeMicros',
        });
        final categories = reader.list('categories');
        if (reader.string('scope') != 'currentInstall' ||
            categories.length != _categories.length ||
            Iterable<int>.generate(_categories.length).any(
              (index) => categories[index] != _categories[index],
            )) {
          throw const CanonicalFormatException(
            'Invalid install erasure receipt',
          );
        }
        return MeasurementInstallErasureReceiptV1(
          operationId: reader.string('operationId'),
          target: TargetCoordinate.fromJson(reader.object('target')),
          completedAtServerTimeMicros:
              reader.integer('completedAtServerTimeMicros'),
        );
      });

  /// Decodes only the canonical byte representation.
  factory MeasurementInstallErasureReceiptV1.fromCanonicalBytes(
    List<int> bytes,
  ) =>
      _safeDecode(
        () => verifyCanonicalRoundTrip(
          MeasurementInstallErasureReceiptV1.fromJson(
            decodeCanonicalObject(bytes),
          ),
          bytes,
          path: 'measurementInstallErasureReceipt',
        ),
      );

  /// Identifier of the completed request.
  final String operationId;

  /// Scope resolved by authenticated service authority.
  final TargetCoordinate target;

  /// Server completion timestamp in portable microseconds.
  final int completedAtServerTimeMicros;

  /// Fixed erasure scope.
  String get scope => 'currentInstall';

  /// Fixed ordered categories covered by the operation.
  List<String> get categories => _categories;

  static const _categories = ['assignmentLinks', 'assignments', 'pseudonyms'];

  @override
  Map<String, Object?> toJson() => {
        'kind': 'measurementInstallErasureReceipt',
        'schemaVersion': kMeasurementSchemaVersion,
        'operationId': operationId,
        'target': target.toJson(),
        'scope': scope,
        'categories': categories,
        'completedAtServerTimeMicros': completedAtServerTimeMicros,
      };
}

void _requireOperationId(String value) {
  if (RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$').stringMatch(value) !=
      value) {
    throw const CanonicalFormatException(
      'Invalid install erasure operation ID',
    );
  }
}

CanonicalObjectReader _reader(
  Map<String, Object?> json,
  String kind,
  Set<String> fields,
) {
  final keys = {'kind', 'schemaVersion', ...fields};
  final reader = CanonicalObjectReader(
    json,
    allowedKeys: keys,
    requiredKeys: keys,
    path: kind,
  );
  validateCanonicalDocument(reader, expectedKind: kind);
  return reader;
}

T _safeDecode<T>(T Function() decode) {
  try {
    return decode();
  } on Object {
    throw const CanonicalFormatException('Invalid install erasure document');
  }
}
