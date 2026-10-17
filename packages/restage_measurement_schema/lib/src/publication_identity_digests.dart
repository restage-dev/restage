import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:restage_measurement_schema/src/canonical.dart';

/// Domain of the publication-line digest behind a minted surface identity.
const String _publicationLineDigestDomainV1 =
    'restage-surface-publication-line-v1';

/// Domain of the digest behind a publication artifact's identity.
const String _artifactDefinitionDigestDomainV1 =
    'restage-measurement-artifact-definition-v1';

/// Domain of the digest over a publication's declared artifact bytes.
const String _declaredArtifactBytesDigestDomainV1 =
    'restage-surface-publication-declared-artifact-bytes-v1';

/// The prefix on every artifact identity the platform mints.
const String kMintedArtifactIdPrefix = 'artifact.v1.';

/// Lowercase hex SHA-256 of [domain], a NUL, and the canonical JSON of [value].
String measurementDomainDigest(String domain, Object? value) => sha256.convert(
      <int>[
        ...utf8.encode('$domain\u0000'),
        ...CanonicalJsonCodec.encode(value),
      ],
    ).toString();

/// Digest of one publication line. Pass [contractVersion] only for a screen.
String publicationLineDigestV1({
  required String surface,
  required String slug,
  required String sourceKind,
  int? contractVersion,
}) =>
    measurementDomainDigest(_publicationLineDigestDomainV1, <String, Object?>{
      if (contractVersion != null) 'contractVersion': contractVersion,
      'kind': 'publicationLine',
      'schemaVersion': 1,
      'slug': slug,
      'sourceKind': sourceKind,
      'surface': surface,
    });

/// Digest of one artifact slot of a publication line. Pass [contractVersion]
/// only for a screen; [artifactId] is null for a flow document.
String artifactDefinitionDigestV1({
  required String surface,
  required String slug,
  required String sourceKind,
  required String artifactRole,
  int? contractVersion,
  String? artifactId,
}) =>
    measurementDomainDigest(
        _artifactDefinitionDigestDomainV1, <String, Object?>{
      'artifactSlot': '$artifactRole:${artifactId ?? ''}',
      'publication': <String, Object?>{
        if (contractVersion != null) 'contractVersion': contractVersion,
        'slug': slug,
        'sourceKind': sourceKind,
        'surface': surface,
      },
    });

/// Digest over a publication's declared artifact tuples, in declared order.
String declaredArtifactBytesDigestV1(List<Object?> tuples) =>
    measurementDomainDigest(
      _declaredArtifactBytesDigestDomainV1,
      <String, Object?>{
        'kind': 'restageSurfacePublicationDeclaredArtifactBytes',
        'schemaVersion': 1,
        'tuples': tuples,
      },
    );
