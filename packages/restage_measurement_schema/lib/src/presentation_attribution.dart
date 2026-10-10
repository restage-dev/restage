import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:restage_measurement_schema/src/canonical.dart';
import 'package:restage_measurement_schema/src/delivery_identity.dart';
import 'package:restage_measurement_schema/src/measurement_ingest.dart';
import 'package:restage_measurement_schema/src/publication_binding.dart';
import 'package:restage_measurement_schema/src/target.dart';

/// How the mounted output was resolved.
enum MountResolutionKindV1 {
  /// Output obtained from hosted delivery.
  hosted,

  /// Output obtained from a cached delivery.
  cached,

  /// Output rendered by the app's compiled fallback.
  compiledFallback,
}

/// The evidence established for a mounted selection.
enum MountEvidenceStrengthV1 {
  /// A complete public selection whose authority is verified externally.
  verifiedSelection,

  /// Evidence reported by the local mount without verified selection authority.
  reportedLocal,
}

/// The authority domain resolved by an opaque assignment handle.
enum PresentationAssignmentOwnerV2 {
  /// One original independent assignment.
  independent,

  /// One complete original joint assignment.
  joint,

  /// A retained ordered path of original assignment authorities.
  path,
}

/// One bounded opaque assignment handle whose authority resolves externally.
final class PresentationAssignmentCarrierV2 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  /// Validates canonical handle bytes; path handles contain exactly 32 bytes.
  PresentationAssignmentCarrierV2({
    required this.owner,
    required this.outcomeLinkCarrier,
  }) {
    try {
      MeasurementExperimentAssignmentV1.fromJson({
        'kind': 'measurementExperimentAssignment',
        'schemaVersion': kMeasurementSchemaVersion,
        'outcomeLinkCarrier': outcomeLinkCarrier,
      });
    } on MeasurementIngestCodecException {
      throw ArgumentError('Expected a canonical bounded opaque outcome link');
    }
    if (owner == PresentationAssignmentOwnerV2.path &&
        base64Url.decode(base64Url.normalize(outcomeLinkCarrier)).length !=
            32) {
      throw ArgumentError('A path assignment handle must contain 32 bytes');
    }
  }

  /// Decodes byte-exact canonical assignment-carrier bytes.
  factory PresentationAssignmentCarrierV2.fromCanonicalBytes(List<int> bytes) =>
      verifyCanonicalRoundTrip(
        PresentationAssignmentCarrierV2.fromJson(decodeCanonicalObject(bytes)),
        bytes,
        path: 'presentationAssignmentCarrier',
      );

  /// Decodes one closed carrier without establishing assignment authority.
  factory PresentationAssignmentCarrierV2.fromJson(Map<String, Object?> json) {
    const path = 'presentationAssignmentCarrier';
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'kind',
        'schemaVersion',
        'owner',
        'outcomeLinkCarrier',
      },
      requiredKeys: const {
        'kind',
        'schemaVersion',
        'owner',
        'outcomeLinkCarrier',
      },
      path: path,
    );
    if (reader.string('kind') != path || reader.integer('schemaVersion') != 2) {
      throw const CanonicalFormatException(
        'Expected presentationAssignmentCarrier version 2',
      );
    }
    try {
      return PresentationAssignmentCarrierV2(
        owner:
            PresentationAssignmentOwnerV2.values.byName(reader.string('owner')),
        outcomeLinkCarrier: reader.string('outcomeLinkCarrier'),
      );
      // Constructor refusals become canonical-format refusals when decoding.
      // ignore: avoid_catching_errors
    } on ArgumentError catch (error) {
      throw CanonicalFormatException('$path is invalid: ${error.message}');
    }
  }

  /// Authority domain identified by the issuer.
  final PresentationAssignmentOwnerV2 owner;

  /// Opaque canonical unpadded base64url outcome-link handle.
  final String outcomeLinkCarrier;

  /// SHA-256 of the terminated assignment-carrier domain and canonical bytes.
  late final CanonicalDigest canonicalDigest = CanonicalDigest(
    sha256.convert([
      ...utf8.encode('restage.presentation-assignment-carrier.v2\u0000'),
      ...canonicalBytes,
    ]).toString(),
  );

  @override
  Map<String, Object?> toJson() => {
        'kind': 'presentationAssignmentCarrier',
        'schemaVersion': 2,
        'owner': owner.name,
        'outcomeLinkCarrier': outcomeLinkCarrier,
      };
}

/// Frozen safe selection evidence shared by consumers of one mount.
/// SDK/backend construction and signed receipt/root verification establish
/// authority; this tuple validates only its public shape and agreement.
final class MountSelectionAttributionV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  /// Creates a tuple of the evidence actually available for one mount.
  MountSelectionAttributionV1({
    required this.resolutionKind,
    required this.evidenceStrength,
    required this.mountNonceDigest,
    this.placementKey,
    this.resolvedTarget,
    this.actualSurface,
    this.actualPublication,
    this.measurementBinding,
    this.resolvedSelectionDigest,
  }) {
    final targets = [
      if (resolvedTarget != null) resolvedTarget!,
      if (actualSurface != null) actualSurface!.target,
      if (actualPublication != null) actualPublication!.surface.target,
    ];
    if (targets.any((target) => target != targets.first)) {
      throw ArgumentError('Mount selection target coordinates must agree');
    }
    if (actualSurface != null &&
        actualPublication != null &&
        actualSurface != actualPublication!.surface) {
      throw ArgumentError(
        'Mount publication must match the actual surface and family',
      );
    }
    final publicationBinding = actualPublication?.publicationBindingRef;
    if (measurementBinding != null &&
        publicationBinding != null &&
        measurementBinding != publicationBinding) {
      throw ArgumentError('Mount and publication bindings must agree');
    }
    if (resolutionKind == MountResolutionKindV1.compiledFallback &&
        (evidenceStrength != MountEvidenceStrengthV1.reportedLocal ||
            actualPublication != null ||
            resolvedSelectionDigest != null)) {
      throw ArgumentError(
        'Compiled fallback requires reported local evidence '
        'without a remote publication or selection digest',
      );
    }
    if (evidenceStrength == MountEvidenceStrengthV1.verifiedSelection &&
        (placementKey == null ||
            resolvedTarget == null ||
            actualSurface == null ||
            actualPublication == null ||
            resolvedSelectionDigest == null)) {
      throw ArgumentError(
        'Verified selection requires placement, target, surface, '
        'publication and public selection digest',
      );
    }
    if (evidenceStrength == MountEvidenceStrengthV1.reportedLocal &&
        resolvedSelectionDigest != null) {
      throw ArgumentError(
        'Reported local evidence cannot claim a selection digest',
      );
    }
  }

  /// Decodes byte-exact canonical mount-attribution bytes.
  factory MountSelectionAttributionV1.fromCanonicalBytes(List<int> bytes) =>
      verifyCanonicalRoundTrip(
        MountSelectionAttributionV1.fromJson(decodeCanonicalObject(bytes)),
        bytes,
        path: 'mountSelectionAttribution',
      );

  /// Decodes one closed public mount-attribution tuple.
  factory MountSelectionAttributionV1.fromJson(Map<String, Object?> json) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'kind',
        'schemaVersion',
        'placementKey',
        'resolvedTarget',
        'actualSurface',
        'actualPublication',
        'measurementBinding',
        'resolutionKind',
        'evidenceStrength',
        'mountNonceDigest',
        'resolvedSelectionDigest',
      },
      requiredKeys: const {
        'kind',
        'schemaVersion',
        'resolutionKind',
        'evidenceStrength',
        'mountNonceDigest',
      },
      path: 'mountSelectionAttribution',
    );
    validateCanonicalDocument(
      reader,
      expectedKind: 'mountSelectionAttribution',
    );
    final key = reader.optionalObject('placementKey');
    final target = reader.optionalObject('resolvedTarget');
    final surface = reader.optionalObject('actualSurface');
    final publication = reader.optionalObject('actualPublication');
    final binding = reader.optionalObject('measurementBinding');
    final selectionDigest = reader.optionalString('resolvedSelectionDigest');
    try {
      return MountSelectionAttributionV1(
        placementKey: key == null ? null : PlacementKeyV1.fromJson(key),
        resolvedTarget:
            target == null ? null : TargetCoordinate.fromJson(target),
        actualSurface: surface == null
            ? null
            : DeliverySurfaceReferenceV1.fromJson(surface),
        actualPublication: publication == null
            ? null
            : DeliveryPublicationReferenceV1.fromJson(publication),
        measurementBinding: binding == null
            ? null
            : MeasurementPublicationBindingReferenceV1.fromJson(binding),
        resolutionKind: MountResolutionKindV1.values
            .byName(reader.string('resolutionKind')),
        evidenceStrength: MountEvidenceStrengthV1.values
            .byName(reader.string('evidenceStrength')),
        mountNonceDigest: CanonicalDigest(reader.string('mountNonceDigest')),
        resolvedSelectionDigest:
            selectionDigest == null ? null : CanonicalDigest(selectionDigest),
      );
      // Constructor refusals must decode as canonical format refusals.
      // ignore: avoid_catching_errors
    } on ArgumentError catch (error) {
      throw CanonicalFormatException(
        'mountSelectionAttribution is invalid: ${error.message}',
      );
    }
  }

  /// Placement at this mount, when known.
  final PlacementKeyV1? placementKey;

  /// Exact resolved target, when known.
  final TargetCoordinate? resolvedTarget;

  /// Actual surface and family, when known.
  final DeliverySurfaceReferenceV1? actualSurface;

  /// Exact remote publication, when known; absent for compiled fallbacks.
  final DeliveryPublicationReferenceV1? actualPublication;

  /// Opaque generated or delivered binding whose authority resolves separately.
  final MeasurementPublicationBindingReferenceV1? measurementBinding;

  /// How this output was resolved.
  final MountResolutionKindV1 resolutionKind;

  /// Selection evidence established by the constructing authority.
  final MountEvidenceStrengthV1 evidenceStrength;

  /// Digest of the nonce identifying this particular mount.
  final CanonicalDigest mountNonceDigest;

  /// Pre-mount safe public projection digest copied from the selected delivery.
  final CanonicalDigest? resolvedSelectionDigest;

  /// SHA-256 of the versioned domain prefix and the canonical safe tuple bytes.
  late final CanonicalDigest canonicalDigest = CanonicalDigest(
    sha256.convert([
      ...utf8.encode('restage.mount-selection-attribution.v1\u0000'),
      ...canonicalBytes,
    ]).toString(),
  );

  @override
  Map<String, Object?> toJson() => {
        'kind': 'mountSelectionAttribution',
        'schemaVersion': kMeasurementSchemaVersion,
        if (placementKey != null) 'placementKey': placementKey!.toJson(),
        if (resolvedTarget != null) 'resolvedTarget': resolvedTarget!.toJson(),
        if (actualSurface != null) 'actualSurface': actualSurface!.toJson(),
        if (actualPublication != null)
          'actualPublication': actualPublication!.toJson(),
        if (measurementBinding != null)
          'measurementBinding': measurementBinding!.toJson(),
        'resolutionKind': resolutionKind.name,
        'evidenceStrength': evidenceStrength.name,
        'mountNonceDigest': mountNonceDigest.hex,
        if (resolvedSelectionDigest != null)
          'resolvedSelectionDigest': resolvedSelectionDigest!.hex,
      };
}
