import 'package:restage_measurement_schema/restage_measurement_schema.dart';

/// Builds a syntactically exact context for schema fixtures that do not
/// exercise a binding resolver.
ExactMeasurementPublicationContextRefV1 exactPublicationContextRefV1({
  required TargetCoordinate target,
  required SurfaceId surfaceId,
  required SurfaceRevisionId surfaceRevisionId,
  required CanonicalDigest artifactGraphHash,
  required CanonicalDigest measurementManifestHash,
  MeasurementPublicationBindingReferenceV1? bindingReference,
}) =>
    ExactMeasurementPublicationContextRefV1(
      bindingReference: bindingReference ?? _fixtureBindingReference,
      surfaceIdentity: PublishedSurfaceIdentityV1(
        target: target,
        surfaceId: surfaceId,
      ),
      surfaceRevisionId: surfaceRevisionId,
      artifactGraphHash: artifactGraphHash,
      measurementManifestHash: measurementManifestHash,
    );

final MeasurementPublicationBindingReferenceV1 _fixtureBindingReference =
    MeasurementPublicationBindingReferenceV1(
  publicationAuthorityReference: RegisteredPublicationAuthorityReferenceV1(
    authorityId: MeasurementPublicationAuthorityId(
      'registered.publication.schema-fixture.v1',
    ),
    externalPublicationAuthorityRef: 'mpa1.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    candidateReference: MeasurementPublicationCandidateReferenceV1(
      candidateDigest: CanonicalDigest(
        'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
      ),
      selectedPublicationManifestDigest: CanonicalDigest(
        'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
      ),
      declaredArtifactBytesDigest: CanonicalDigest(
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      ),
      assembledPublicationUploadDigest: CanonicalDigest(
        'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
      ),
      measurementPublicationDraftDigest: CanonicalDigest(
        'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
      ),
    ),
    immutablePublicationDigest: CanonicalDigest(
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    ),
    declaredArtifactBytesDigest: CanonicalDigest(
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    ),
  ),
  bindingDigest: CanonicalDigest(
    '9999999999999999999999999999999999999999999999999999999999999999',
  ),
);
