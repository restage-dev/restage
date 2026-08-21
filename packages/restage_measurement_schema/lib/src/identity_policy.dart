import 'package:restage_measurement_schema/src/canonical.dart';
import 'package:restage_measurement_schema/src/identifiers.dart';

/// Immutable reference to a governed policy: the exact revision that was
/// accepted, plus the semantic hash of the accepted set at that revision.
///
/// Every governance reference in the vocabulary shares this shape, so it is
/// declared once rather than restated per policy family.
abstract base class GovernancePolicyRefV1<R extends MeasurementIdentifier>
    extends CanonicalValue {
  const GovernancePolicyRefV1({
    required this.revisionId,
    required this.semanticHash,
  });

  /// Exact immutable policy revision authority.
  final R revisionId;

  /// Accepted-set semantic hash of the referenced policy.
  final CanonicalDigest semanticHash;

  @override
  Map<String, Object?> toJson() => {
        'revisionId': revisionId.value,
        'semanticHash': semanticHash.hex,
      };
}

/// Immutable processing-purpose policy reference.
final class PurposePolicyRefV1
    extends GovernancePolicyRefV1<PurposePolicyRevisionId> {
  const PurposePolicyRefV1({
    required super.revisionId,
    required super.semanticHash,
  });

  factory PurposePolicyRefV1.fromCanonicalBytes(List<int> bytes) =>
      verifyCanonicalRoundTrip(
        PurposePolicyRefV1.fromJson(decodeCanonicalObject(bytes)),
        bytes,
        path: 'purposePolicyRef',
      );

  factory PurposePolicyRefV1.fromJson(Map<String, Object?> json) =>
      _decodeGovernanceRef(
        json,
        'purposePolicyRef',
        PurposePolicyRevisionId.new,
        (revisionId, semanticHash) => PurposePolicyRefV1(
          revisionId: revisionId,
          semanticHash: semanticHash,
        ),
      );
}

T _decodeGovernanceRef<T, R extends MeasurementIdentifier>(
  Map<String, Object?> json,
  String path,
  R Function(String) decodeRevisionId,
  T Function(R, CanonicalDigest) create,
) {
  final reader = CanonicalObjectReader(
    json,
    allowedKeys: const {'revisionId', 'semanticHash'},
    requiredKeys: const {'revisionId', 'semanticHash'},
    path: path,
  );
  return _decodeIdentityValue(
    path,
    () => create(
      decodeRevisionId(reader.string('revisionId')),
      CanonicalDigest(reader.string('semanticHash')),
    ),
  );
}

/// Immutable reference to one governed subject-policy revision.
final class SubjectPolicyRefV1 extends CanonicalValue {
  const SubjectPolicyRefV1({
    required this.subjectPolicyId,
    required this.revisionId,
    required this.semanticHash,
  });

  /// Decodes a byte-exact subject-policy reference.
  factory SubjectPolicyRefV1.fromCanonicalBytes(List<int> bytes) =>
      verifyCanonicalRoundTrip(
        SubjectPolicyRefV1.fromJson(decodeCanonicalObject(bytes)),
        bytes,
        path: 'subjectPolicyRef',
      );

  /// Decodes a strict nested subject-policy reference.
  factory SubjectPolicyRefV1.fromJson(Map<String, Object?> json) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'revisionId', 'semanticHash', 'subjectPolicyId'},
      requiredKeys: const {'revisionId', 'semanticHash', 'subjectPolicyId'},
      path: 'subjectPolicyRef',
    );
    return _decodeIdentityValue(
      'subjectPolicyRef',
      () => SubjectPolicyRefV1(
        subjectPolicyId: SubjectPolicyId(reader.string('subjectPolicyId')),
        revisionId: SubjectPolicyRevisionId(reader.string('revisionId')),
        semanticHash: CanonicalDigest(reader.string('semanticHash')),
      ),
    );
  }

  /// Stable subject-policy authority.
  final SubjectPolicyId subjectPolicyId;

  /// Immutable subject-policy revision.
  final SubjectPolicyRevisionId revisionId;

  /// Accepted-set semantic hash.
  final CanonicalDigest semanticHash;

  @override
  Map<String, Object?> toJson() => {
        'revisionId': revisionId.value,
        'semanticHash': semanticHash.hex,
        'subjectPolicyId': subjectPolicyId.value,
      };
}

T _decodeIdentityValue<T>(String path, T Function() create) {
  try {
    return create();
  } on CanonicalFormatException {
    rethrow;
  } on ArgumentError catch (error) {
    throw CanonicalFormatException('$path: ${error.message}');
  }
}
