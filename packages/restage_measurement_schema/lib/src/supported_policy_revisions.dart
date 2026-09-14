import 'package:restage_measurement_schema/src/canonical.dart';
import 'package:restage_measurement_schema/src/policy_revision.dart' as policy;

/// Maximum characters of the base64url report carrier on a request.
const int sdkSupportedPolicyRevisionsMaximumCarrierCharacters = 2048;

/// The policy revisions supported by one SDK build.
final class SdkSupportedPolicyRevisionsV1 extends CanonicalValue {
  /// Creates a bounded report of the SDK's supported policy revisions.
  SdkSupportedPolicyRevisionsV1({
    required this.sdkVersion,
    required this.assignmentApiLevel,
    required this.platform,
    required this.privacyPolicyFloor,
    required this.collectionBudgetFloor,
  }) {
    if (sdkVersion.isEmpty || sdkVersion.length > 64) {
      throw ArgumentError.value(
          sdkVersion, 'sdkVersion', 'Expected 1..64 characters');
    }
    if (platform.isEmpty || platform.length > 32) {
      throw ArgumentError.value(
          platform, 'platform', 'Expected 1..32 characters');
    }
    for (final entry in {
      'privacyPolicyFloor': privacyPolicyFloor,
      'collectionBudgetFloor': collectionBudgetFloor,
    }.entries) {
      if (entry.value < 0 || entry.value > kMaximumPortableJsonInteger) {
        throw ArgumentError.value(
          entry.value,
          entry.key,
          'Expected a non-negative portable JSON integer',
        );
      }
    }
  }

  /// Decodes the closed supported policy report object.
  factory SdkSupportedPolicyRevisionsV1.fromJson(Map<String, Object?> json) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: _keys,
      requiredKeys: _keys,
      path: 'sdkSupportedPolicyRevisions',
    );
    validateCanonicalDocument(reader,
        expectedKind: 'sdkSupportedPolicyRevisions');
    if (reader.string('privacyPolicyFamily') !=
            policy.manifestPrivacyPolicyFamily ||
        reader.string('collectionBudgetFamily') !=
            policy.collectionBudgetFamily ||
        reader.string('privacyClassificationRevisionId') !=
            policy.privacyClassificationRevisionId) {
      throw const CanonicalFormatException(
          'Unsupported policy family or privacy classification');
    }
    return SdkSupportedPolicyRevisionsV1(
      sdkVersion: reader.string('sdkVersion'),
      assignmentApiLevel: reader.integer('assignmentApiLevel'),
      platform: reader.string('platform'),
      privacyPolicyFloor: reader.integer('privacyPolicyFloor'),
      collectionBudgetFloor: reader.integer('collectionBudgetFloor'),
    );
  }

  /// Decodes exact canonical bytes for a supported policy report.
  factory SdkSupportedPolicyRevisionsV1.fromCanonicalBytes(List<int> bytes) =>
      verifyCanonicalRoundTrip(
        SdkSupportedPolicyRevisionsV1.fromJson(decodeCanonicalObject(bytes)),
        bytes,
        path: 'sdkSupportedPolicyRevisions',
      );

  static const _keys = {
    'assignmentApiLevel',
    'collectionBudgetFamily',
    'collectionBudgetFloor',
    'kind',
    'platform',
    'privacyClassificationRevisionId',
    'privacyPolicyFamily',
    'privacyPolicyFloor',
    'schemaVersion',
    'sdkVersion',
  };

  /// Reported SDK version.
  final String sdkVersion;

  /// Supported assignment API level.
  final int assignmentApiLevel;

  /// Platform running the SDK.
  final String platform;

  /// Lowest supported manifest privacy policy revision.
  final int privacyPolicyFloor;

  /// Lowest supported collection budget revision.
  final int collectionBudgetFloor;

  @override
  Map<String, Object?> toJson() => {
        'assignmentApiLevel': assignmentApiLevel,
        'collectionBudgetFamily': policy.collectionBudgetFamily,
        'collectionBudgetFloor': collectionBudgetFloor,
        'kind': 'sdkSupportedPolicyRevisions',
        'platform': platform,
        'privacyClassificationRevisionId':
            policy.privacyClassificationRevisionId,
        'privacyPolicyFamily': policy.manifestPrivacyPolicyFamily,
        'privacyPolicyFloor': privacyPolicyFloor,
        'schemaVersion': kMeasurementSchemaVersion,
        'sdkVersion': sdkVersion,
      };
}
