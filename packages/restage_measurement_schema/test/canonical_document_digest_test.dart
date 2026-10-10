import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:test/test.dart';

void main() {
  final target = TargetCoordinate(
    organizationId: OrganizationId(11),
    appId: ApplicationId(23),
    environmentTargetId: EnvironmentTargetId(31),
    namedEnvironmentId: NamedEnvironmentId(37),
    runtimePlane: RuntimePlane.sandbox,
  );
  final occurrence = MeasurementPointOccurrenceV1(
    target: target,
    surfaceRevisionId: SurfaceRevisionId('surface.checkout.v1'),
    artifactGraphHash: CanonicalDigest('a' * 64),
    artifactId: ArtifactId('artifact.checkout-root'),
    artifactOccurrenceEdgeToken: ArtifactOccurrenceEdgeToken('root'),
    artifactContentHash: CanonicalDigest('b' * 64),
    canonicalNodeToken: NodeTokenId('node.checkout-button'),
    capabilityKind: MeasurementCapabilityKind.sourceInteraction,
    sourceEventIdentity: SourceEventIdentity('onPressed'),
    normalizedInteractionKind: NormalizedInteractionKind.activate,
    privacyClass: MeasurementPrivacyClass.nonSensitive,
    semanticValueClass: SemanticValueClass.activityOnly,
    collectionClass: MeasurementCollectionClass.tier2Coalesced,
    lineageId: PointLineageId('lineage.checkout-button'),
    displayMetadataRef: DisplayMetadataRef('display.checkout-button'),
  );
  final reference = GeneratedPointReferenceV1(
    referenceId: GeneratedReferenceId('reference.checkout-button'),
    target: target,
    surfaceRevisionId: occurrence.surfaceRevisionId,
    artifactGraphHash: occurrence.artifactGraphHash,
    occurrenceId: occurrence.occurrenceId,
    lineageId: occurrence.lineageId,
    sourceEventIdentity: occurrence.sourceEventIdentity!,
    dartSymbol: GeneratedDartSymbol('checkoutButtonOnPressed'),
  );

  group('canonical document digest', () {
    test('is the digest a fresh computation produces', () {
      for (final document in <CanonicalDocument>[reference]) {
        expect(
          document.canonicalDigest,
          canonicalSha256(document.hashDomain, document.canonicalBytes),
          reason: '${document.runtimeType}',
        );
      }
    });

    test('is recomputed unless the document declares it owns its content', () {
      final probe = _ProbeDocument('first');
      final first = probe.canonicalDigest;
      probe.value = 'second';

      expect(
        probe.canonicalDigest,
        isNot(first),
        reason: 'an undeclared document must not hold a digest',
      );
      expect(
        probe.canonicalDigest,
        canonicalSha256(probe.hashDomain, probe.canonicalBytes),
      );
    });

    test('is held only when the document declares it owns its content', () {
      final probe = _DeclaredProbeDocument('first');
      final first = probe.canonicalDigest;
      probe.value = 'second';

      // The declaration is a promise about the document, which is why it is
      // opt in: a document that cannot keep it must not make it.
      expect(probe.canonicalDigest, first);
    });

    test('is stable across reads and survives a round trip', () {
      final first = reference.canonicalDigest;
      expect(reference.canonicalDigest, first);
      expect(reference.canonicalDigest, first);

      final decoded = GeneratedPointReferenceV1.fromCanonicalBytes(
        reference.canonicalBytes,
      );
      expect(decoded.canonicalDigest, first);
      expect(decoded.canonicalBytes, reference.canonicalBytes);
    });

    test('differs whenever the content differs', () {
      final other = GeneratedPointReferenceV1(
        referenceId: GeneratedReferenceId('reference.other-button'),
        target: target,
        surfaceRevisionId: occurrence.surfaceRevisionId,
        artifactGraphHash: occurrence.artifactGraphHash,
        occurrenceId: occurrence.occurrenceId,
        lineageId: occurrence.lineageId,
        sourceEventIdentity: occurrence.sourceEventIdentity!,
        dartSymbol: GeneratedDartSymbol('checkoutButtonOnPressed'),
      );

      expect(other.canonicalDigest, isNot(reference.canonicalDigest));
      expect(
        other.canonicalDigest,
        canonicalSha256(other.hashDomain, other.canonicalBytes),
      );
      expect(reference == other, isFalse);
      expect(reference == reference, isTrue);
    });
  });
}

/// Stands in for a document that has not declared that it owns its content.
final class _ProbeDocument extends CanonicalDocument {
  _ProbeDocument(this.value);

  String value;

  @override
  CanonicalHashDomain get hashDomain => CanonicalHashDomain.nodeToken;

  @override
  Map<String, Object?> toJson() => {'value': value};
}

/// Stands in for a document that has declared it.
final class _DeclaredProbeDocument extends CanonicalDocument
    implements ImmutableCanonicalDocument {
  _DeclaredProbeDocument(this.value);

  String value;

  @override
  CanonicalHashDomain get hashDomain => CanonicalHashDomain.nodeToken;

  @override
  Map<String, Object?> toJson() => {'value': value};
}
