import 'package:restage_measurement_schema/src/canonical.dart';
import 'package:restage_measurement_schema/src/identifiers.dart';

/// Execution plane of one exact resolved environment target.
enum RuntimePlane {
  /// Hosted evaluation plane isolated from customer live traffic.
  sandbox('sandbox'),

  /// Customer live traffic plane.
  live('live');

  const RuntimePlane(this.wireName);

  /// Stable canonical-wire spelling.
  final String wireName;

  static RuntimePlane _fromWire(String value) {
    for (final plane in values) {
      if (plane.wireName == value) return plane;
    }
    throw CanonicalFormatException('Unknown runtime plane "$value"');
  }
}

/// Exact post-resolution control-plane coordinate.
final class TargetCoordinate extends CanonicalDocument {
  /// Creates a complete target coordinate from existing integer authorities.
  const TargetCoordinate({
    required this.organizationId,
    required this.appId,
    required this.environmentTargetId,
    required this.namedEnvironmentId,
    required this.runtimePlane,
  });

  /// Decodes byte-exact canonical target-coordinate JSON.
  factory TargetCoordinate.fromCanonicalBytes(List<int> bytes) =>
      verifyCanonicalRoundTrip(
        TargetCoordinate.fromJson(decodeCanonicalObject(bytes)),
        bytes,
        path: 'targetCoordinate',
      );

  /// Decodes a strict nested target-coordinate object.
  factory TargetCoordinate.fromJson(Map<String, Object?> values) {
    final reader = CanonicalObjectReader(
      values,
      allowedKeys: const {
        'appId',
        'environmentTargetId',
        'kind',
        'namedEnvironmentId',
        'organizationId',
        'runtimePlane',
        'schemaVersion',
      },
      requiredKeys: const {
        'appId',
        'environmentTargetId',
        'kind',
        'namedEnvironmentId',
        'organizationId',
        'runtimePlane',
        'schemaVersion',
      },
      path: 'targetCoordinate',
    );
    validateCanonicalDocument(reader, expectedKind: 'targetCoordinate');
    final organizationId = reader.integer('organizationId');
    final appId = reader.integer('appId');
    final environmentTargetId = reader.integer('environmentTargetId');
    final namedEnvironmentId = reader.integer('namedEnvironmentId');
    for (final authority in {
      'organizationId': organizationId,
      'appId': appId,
      'environmentTargetId': environmentTargetId,
      'namedEnvironmentId': namedEnvironmentId,
    }.entries) {
      if (authority.value <= 0) {
        throw CanonicalFormatException(
          'targetCoordinate.${authority.key} must be positive',
        );
      }
    }
    try {
      return TargetCoordinate(
        organizationId: OrganizationId(organizationId),
        appId: ApplicationId(appId),
        environmentTargetId: EnvironmentTargetId(environmentTargetId),
        namedEnvironmentId: NamedEnvironmentId(namedEnvironmentId),
        runtimePlane: RuntimePlane._fromWire(reader.string('runtimePlane')),
      );
    } catch (error) {
      if (error is! ArgumentError) rethrow;
      throw CanonicalFormatException(
        'targetCoordinate is invalid: ${error.message}',
      );
    }
  }

  /// Tenant authority.
  final OrganizationId organizationId;

  /// Application authority.
  final ApplicationId appId;

  /// Resolved environment-target authority.
  final EnvironmentTargetId environmentTargetId;

  /// Resolved named-environment authority.
  final NamedEnvironmentId namedEnvironmentId;

  /// Exact runtime execution plane.
  final RuntimePlane runtimePlane;

  @override
  CanonicalHashDomain get hashDomain => CanonicalHashDomain.targetCoordinate;

  @override
  Map<String, Object?> toJson() => {
        'appId': appId.value,
        'environmentTargetId': environmentTargetId.value,
        'kind': 'targetCoordinate',
        'namedEnvironmentId': namedEnvironmentId.value,
        'organizationId': organizationId.value,
        'runtimePlane': runtimePlane.wireName,
        'schemaVersion': kMeasurementSchemaVersion,
      };
}
