import 'dart:convert';
import 'dart:io';

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

  test('target fixture decodes and re-encodes through the production type', () {
    final bytes = File(
      'test/fixtures/canonical/target_coordinate_v1.json',
    ).readAsBytesSync();

    final decoded = TargetCoordinate.fromCanonicalBytes(bytes);

    expect(decoded, target);
    expect(decoded.canonicalBytes, bytes);
  });

  test('target rejects unknown versions, planes, and keys', () {
    for (final source in <String>[
      '{"appId":23,"environmentTargetId":31,'
          '"kind":"targetCoordinate","namedEnvironmentId":37,'
          '"organizationId":11,"runtimePlane":"sandbox",'
          '"schemaVersion":2}',
      '{"appId":23,"environmentTargetId":31,'
          '"kind":"targetCoordinate","namedEnvironmentId":37,'
          '"organizationId":11,"runtimePlane":"preview",'
          '"schemaVersion":1}',
      '{"appId":23,"environmentTargetId":31,'
          '"extra":true,"kind":"targetCoordinate",'
          '"namedEnvironmentId":37,"organizationId":11,'
          '"runtimePlane":"sandbox","schemaVersion":1}',
      '{"appId":0,"environmentTargetId":31,'
          '"kind":"targetCoordinate","namedEnvironmentId":37,'
          '"organizationId":11,"runtimePlane":"sandbox",'
          '"schemaVersion":1}',
    ]) {
      expect(
        () => TargetCoordinate.fromCanonicalBytes(utf8.encode(source)),
        throwsA(isA<CanonicalFormatException>()),
        reason: source,
      );
    }
  });

  test('occurrence ID changes for every frozen identity input', () {
    final changedIdentity = <MeasurementPointOccurrenceV1>[
      _copyOccurrence(
        occurrence,
        surfaceRevisionId: SurfaceRevisionId('surface.checkout.v2'),
      ),
      _copyOccurrence(occurrence, artifactGraphHash: CanonicalDigest('c' * 64)),
      _copyOccurrence(
        occurrence,
        artifactId: ArtifactId('artifact.checkout-child'),
      ),
      _copyOccurrence(
        occurrence,
        artifactOccurrenceEdgeToken: ArtifactOccurrenceEdgeToken('nested.edge'),
      ),
      _copyOccurrence(
        occurrence,
        artifactContentHash: CanonicalDigest('d' * 64),
      ),
      _copyOccurrence(
        occurrence,
        canonicalNodeToken: NodeTokenId('node.other-button'),
      ),
      _copyOccurrence(
        occurrence,
        sourceEventIdentity: SourceEventIdentity('onTap'),
      ),
      _copyOccurrence(
        occurrence,
        capabilityKind: MeasurementCapabilityKind.presented,
        clearSourceEventIdentity: true,
        clearNormalizedInteractionKind: true,
        semanticValueClass: SemanticValueClass.none,
      ),
    ];

    for (final changed in changedIdentity) {
      expect(changed.occurrenceId, isNot(occurrence.occurrenceId));
    }
  });

  test('occurrence ID excludes target, lineage, and record metadata', () {
    final metadataOnly = _copyOccurrence(
      occurrence,
      target: TargetCoordinate(
        organizationId: OrganizationId(101),
        appId: ApplicationId(103),
        environmentTargetId: EnvironmentTargetId(107),
        namedEnvironmentId: NamedEnvironmentId(109),
        runtimePlane: RuntimePlane.live,
      ),
      normalizedInteractionKind: NormalizedInteractionKind.submit,
      privacyClass: MeasurementPrivacyClass.sensitive,
      semanticValueClass: SemanticValueClass.explicitReviewedValue,
      collectionClass: MeasurementCollectionClass.tier1KeepAll,
      lineageId: PointLineageId('lineage.metadata-change'),
      displayMetadataRef: DisplayMetadataRef('display.metadata-change'),
    );

    expect(metadataOnly.occurrenceId, occurrence.occurrenceId);
    expect(metadataOnly, isNot(occurrence));
  });

  test('presentation capability cannot declare a source event', () {
    expect(
      () => MeasurementPointOccurrenceV1(
        target: target,
        surfaceRevisionId: occurrence.surfaceRevisionId,
        artifactGraphHash: occurrence.artifactGraphHash,
        artifactId: occurrence.artifactId,
        artifactOccurrenceEdgeToken: ArtifactOccurrenceEdgeToken('root'),
        artifactContentHash: occurrence.artifactContentHash,
        canonicalNodeToken: NodeTokenId('node.root'),
        capabilityKind: MeasurementCapabilityKind.presented,
        sourceEventIdentity: SourceEventIdentity('onPressed'),
        privacyClass: MeasurementPrivacyClass.nonSensitive,
        semanticValueClass: SemanticValueClass.none,
        collectionClass: MeasurementCollectionClass.tier1KeepAll,
        lineageId: PointLineageId('lineage.root'),
        displayMetadataRef: DisplayMetadataRef('display.root'),
      ),
      throwsArgumentError,
    );
  });

  test('local and complete manifests freeze exact closure', () {
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
    final local = LocalMeasurementManifestV1(
      manifestId: MeasurementManifestId('manifest.checkout-root'),
      target: target,
      surfaceRevisionId: occurrence.surfaceRevisionId,
      artifactGraphHash: occurrence.artifactGraphHash,
      artifactId: occurrence.artifactId,
      artifactContentHash: occurrence.artifactContentHash,
      childArtifactIds: const [],
      points: [occurrence],
      generatedReferences: [reference],
      privacyPolicyRevisionId: AuthorityRevisionId('privacy.v1'),
      collectionBudgetRevisionId: AuthorityRevisionId('collection.v1'),
    );
    final complete = CompleteMeasurementManifestV1(
      manifestId: MeasurementManifestId('manifest.checkout-complete'),
      target: target,
      surfaceId: SurfaceId('surface.checkout'),
      surfaceRevisionId: occurrence.surfaceRevisionId,
      rootArtifactId: occurrence.artifactId,
      artifactGraphHash: occurrence.artifactGraphHash,
      localManifests: [local],
      nodeAncestryIndex: _ancestryIndex(occurrence, [local]),
      privacyPolicyRevisionId: AuthorityRevisionId('privacy.v1'),
      collectionBudgetRevisionId: AuthorityRevisionId('collection.v1'),
    );

    expect(local.hashDomain, CanonicalHashDomain.localManifest);
    expect(complete.hashDomain, CanonicalHashDomain.completeManifest);
    expect(complete.points.single, occurrence);
    expect(complete.generatedReferences.single, reference);
  });

  test('manifest admits presentation and interaction slots on one node', () {
    final presentation = _copyOccurrence(
      occurrence,
      capabilityKind: MeasurementCapabilityKind.presented,
      clearSourceEventIdentity: true,
      clearNormalizedInteractionKind: true,
      semanticValueClass: SemanticValueClass.none,
      lineageId: PointLineageId('lineage.checkout-presentation'),
      displayMetadataRef: DisplayMetadataRef('display.checkout-presentation'),
    );
    final local = _localManifest(
      occurrence,
      points: [occurrence, presentation],
    );
    final complete = _completeManifest(occurrence, [local]);

    expect(presentation.occurrenceId, isNot(occurrence.occurrenceId));
    expect(local.points, hasLength(2));
    expect(complete.nodeAncestryIndex.directParentEdges, hasLength(1));
    expect(
      CompleteMeasurementManifestV1.fromCanonicalBytes(
        complete.canonicalBytes,
      ).canonicalBytes,
      complete.canonicalBytes,
    );
  });

  test('manifest admits repeated artifact occurrences with one node token', () {
    final repeated = _copyOccurrence(
      occurrence,
      artifactOccurrenceEdgeToken: ArtifactOccurrenceEdgeToken('repeat.edge'),
      lineageId: PointLineageId('lineage.checkout-button-repeat'),
      displayMetadataRef: DisplayMetadataRef('display.checkout-button-repeat'),
    );
    final local = _localManifest(
      occurrence,
      points: [occurrence, repeated],
    );
    final complete = _completeManifest(occurrence, [local]);

    expect(repeated.occurrenceId, isNot(occurrence.occurrenceId));
    expect(local.points, hasLength(2));
    expect(complete.nodeAncestryIndex.directParentEdges, hasLength(2));
    expect(
      CompleteMeasurementManifestV1.fromCanonicalBytes(
        complete.canonicalBytes,
      ).canonicalBytes,
      complete.canonicalBytes,
    );
  });

  test('complete manifest rejects multiple current occurrences per lineage',
      () {
    final duplicateLineage = _copyOccurrence(
      occurrence,
      canonicalNodeToken: NodeTokenId('node.checkout-duplicate-lineage'),
      lineageId: occurrence.lineageId,
      displayMetadataRef: DisplayMetadataRef('display.checkout-duplicate'),
    );
    expect(
      () => _completeManifest(
        occurrence,
        [
          _localManifest(
            occurrence,
            points: [occurrence, duplicateLineage],
          ),
        ],
      ),
      throwsArgumentError,
    );

    final distinctLineage = _copyOccurrence(
      occurrence,
      canonicalNodeToken: NodeTokenId('node.checkout-distinct-lineage'),
      lineageId: PointLineageId('lineage.checkout-distinct'),
      displayMetadataRef: DisplayMetadataRef('display.checkout-distinct'),
    );
    final valid = _completeManifest(
      occurrence,
      [
        _localManifest(
          occurrence,
          points: [occurrence, distinctLineage],
        ),
      ],
    );
    final invalid = valid.toJson();
    final localManifests = invalid['localManifests']! as List<Object?>;
    final local = localManifests.single! as Map<String, Object?>;
    final points = local['points']! as List<Object?>;
    final distinctPoint =
        points.map((value) => value! as Map<String, Object?>).singleWhere(
              (point) => point['lineageId'] == distinctLineage.lineageId.value,
            );
    distinctPoint['lineageId'] = occurrence.lineageId.value;

    expect(
      () => CompleteMeasurementManifestV1.fromCanonicalBytes(
        CanonicalJsonCodec.encode(invalid),
      ),
      throwsA(isA<CanonicalFormatException>()),
    );
  });

  test('local manifest rejects duplicate point identity and duplicate children',
      () {
    final duplicateIdentity = _copyOccurrence(
      occurrence,
      lineageId: PointLineageId('lineage.other'),
      displayMetadataRef: DisplayMetadataRef('display.other'),
    );
    expect(duplicateIdentity.occurrenceId, occurrence.occurrenceId);

    expect(
      () => LocalMeasurementManifestV1(
        manifestId: MeasurementManifestId('manifest.duplicate'),
        target: target,
        surfaceRevisionId: occurrence.surfaceRevisionId,
        artifactGraphHash: occurrence.artifactGraphHash,
        artifactId: occurrence.artifactId,
        artifactContentHash: occurrence.artifactContentHash,
        childArtifactIds: const [],
        points: [occurrence, duplicateIdentity],
        generatedReferences: const [],
        privacyPolicyRevisionId: AuthorityRevisionId('privacy.v1'),
        collectionBudgetRevisionId: AuthorityRevisionId('collection.v1'),
      ),
      throwsArgumentError,
    );

    expect(
      () => LocalMeasurementManifestV1(
        manifestId: MeasurementManifestId('manifest.duplicate-child'),
        target: target,
        surfaceRevisionId: occurrence.surfaceRevisionId,
        artifactGraphHash: occurrence.artifactGraphHash,
        artifactId: occurrence.artifactId,
        artifactContentHash: occurrence.artifactContentHash,
        childArtifactIds: [
          ArtifactId('artifact.child'),
          ArtifactId('artifact.child'),
        ],
        points: [occurrence],
        generatedReferences: const [],
        privacyPolicyRevisionId: AuthorityRevisionId('privacy.v1'),
        collectionBudgetRevisionId: AuthorityRevisionId('collection.v1'),
      ),
      throwsArgumentError,
    );
  });

  test('complete manifest requires exact root-reachable artifact closure', () {
    final childId = ArtifactId('artifact.child');
    final rootWithChild = _localManifest(
      occurrence,
      childArtifactIds: [childId],
    );
    final childOccurrence = _copyOccurrence(
      occurrence,
      artifactId: childId,
      artifactOccurrenceEdgeToken: ArtifactOccurrenceEdgeToken('root.child'),
      artifactContentHash: CanonicalDigest('c' * 64),
      canonicalNodeToken: NodeTokenId('node.child'),
      lineageId: PointLineageId('lineage.child'),
      displayMetadataRef: DisplayMetadataRef('display.child'),
    );
    final child = _localManifest(
      childOccurrence,
      manifestId: MeasurementManifestId('manifest.child'),
    );

    expect(
      () => _completeManifest(occurrence, [rootWithChild]),
      throwsArgumentError,
      reason: 'a referenced child local manifest is missing',
    );
    expect(
      () => _completeManifest(occurrence, [_localManifest(occurrence), child]),
      throwsArgumentError,
      reason: 'an unreferenced local manifest is an orphan',
    );
    expect(
      _completeManifest(occurrence, [rootWithChild, child]).localManifests,
      hasLength(2),
    );
  });

  test('complete manifest admits one node token in distinct occurrences', () {
    final childId = ArtifactId('artifact.child');
    final root = _localManifest(
      occurrence,
      childArtifactIds: [childId],
    );
    final repeatedNode = _copyOccurrence(
      occurrence,
      artifactId: childId,
      artifactOccurrenceEdgeToken: ArtifactOccurrenceEdgeToken('root.child'),
      artifactContentHash: CanonicalDigest('c' * 64),
      lineageId: PointLineageId('lineage.child'),
      displayMetadataRef: DisplayMetadataRef('display.child'),
    );
    final child = _localManifest(
      repeatedNode,
      manifestId: MeasurementManifestId('manifest.child'),
    );
    final complete = _completeManifest(occurrence, [root, child]);

    expect(
      CompleteMeasurementManifestV1.fromCanonicalBytes(
        complete.canonicalBytes,
      ).canonicalBytes,
      complete.canonicalBytes,
    );
  });

  group('lineage transitions', () {
    final prior = LineageEndpointV1(
      occurrenceId: CanonicalDigest('1' * 64),
      lineageId: PointLineageId('lineage.prior'),
    );
    final continued = LineageEndpointV1(
      occurrenceId: CanonicalDigest('2' * 64),
      lineageId: prior.lineageId,
    );

    test('admits exactly the five closed operations', () {
      expect(LineageOperation.values, hasLength(5));
      expect(
        LineageOperation.values.map((value) => value.wireName),
        ['continue', 'create', 'retire', 'split', 'merge'],
      );
    });

    test('continue is one-to-one and preserves lineage', () {
      final transition = LineageTransitionV1(
        transitionId: LineageTransitionId('transition.continue'),
        publishedSurfaceRevisionId: SurfaceRevisionId('surface.checkout.v2'),
        operation: LineageOperation.continueLineage,
        authority: LineageTransitionAuthority.exactToken,
        prior: [prior],
        next: [continued],
      );

      expect(transition.canonicalDigest.hex, hasLength(64));

      for (final invalid in <LineageTransitionV1 Function()>[
        () => LineageTransitionV1(
              transitionId: LineageTransitionId('transition.continue-arity'),
              publishedSurfaceRevisionId:
                  SurfaceRevisionId('surface.checkout.v2'),
              operation: LineageOperation.continueLineage,
              authority: LineageTransitionAuthority.exactToken,
              prior: const [],
              next: [continued],
            ),
        () => LineageTransitionV1(
              transitionId: LineageTransitionId('transition.continue-lineage'),
              publishedSurfaceRevisionId:
                  SurfaceRevisionId('surface.checkout.v2'),
              operation: LineageOperation.continueLineage,
              authority: LineageTransitionAuthority.explicit,
              prior: [prior],
              next: [
                LineageEndpointV1(
                  occurrenceId: CanonicalDigest('3' * 64),
                  lineageId: PointLineageId('lineage.changed'),
                ),
              ],
            ),
        () => LineageTransitionV1(
              transitionId:
                  LineageTransitionId('transition.continue-next-arity'),
              publishedSurfaceRevisionId:
                  SurfaceRevisionId('surface.checkout.v2'),
              operation: LineageOperation.continueLineage,
              authority: LineageTransitionAuthority.exactToken,
              prior: [prior],
              next: [
                continued,
                LineageEndpointV1(
                  occurrenceId: CanonicalDigest('6' * 64),
                  lineageId: PointLineageId('lineage.extra'),
                ),
              ],
            ),
      ]) {
        expect(invalid, throwsArgumentError);
      }
    });

    test('create is exactly zero-to-one', () {
      expect(
        LineageTransitionV1(
          transitionId: LineageTransitionId('transition.create'),
          publishedSurfaceRevisionId: SurfaceRevisionId('surface.checkout.v2'),
          operation: LineageOperation.create,
          authority: LineageTransitionAuthority.exactToken,
          prior: const [],
          next: [continued],
        ).next,
        [continued],
      );

      expect(
        () => LineageTransitionV1(
          transitionId: LineageTransitionId('transition.create-with-prior'),
          publishedSurfaceRevisionId: SurfaceRevisionId('surface.checkout.v2'),
          operation: LineageOperation.create,
          authority: LineageTransitionAuthority.exactToken,
          prior: [prior],
          next: [continued],
        ),
        throwsArgumentError,
      );
      expect(
        () => LineageTransitionV1(
          transitionId: LineageTransitionId('transition.create-no-next'),
          publishedSurfaceRevisionId: SurfaceRevisionId('surface.checkout.v2'),
          operation: LineageOperation.create,
          authority: LineageTransitionAuthority.explicit,
          prior: const [],
          next: const [],
        ),
        throwsArgumentError,
      );
    });

    test('retire is exactly one-to-zero', () {
      expect(
        LineageTransitionV1(
          transitionId: LineageTransitionId('transition.retire'),
          publishedSurfaceRevisionId: SurfaceRevisionId('surface.checkout.v2'),
          operation: LineageOperation.retire,
          authority: LineageTransitionAuthority.explicit,
          prior: [prior],
          next: const [],
        ).prior,
        [prior],
      );

      expect(
        () => LineageTransitionV1(
          transitionId: LineageTransitionId('transition.retire-with-next'),
          publishedSurfaceRevisionId: SurfaceRevisionId('surface.checkout.v2'),
          operation: LineageOperation.retire,
          authority: LineageTransitionAuthority.exactToken,
          prior: [prior],
          next: [continued],
        ),
        throwsArgumentError,
      );
      expect(
        () => LineageTransitionV1(
          transitionId: LineageTransitionId('transition.retire-no-prior'),
          publishedSurfaceRevisionId: SurfaceRevisionId('surface.checkout.v2'),
          operation: LineageOperation.retire,
          authority: LineageTransitionAuthority.explicit,
          prior: const [],
          next: const [],
        ),
        throwsArgumentError,
      );
    });

    test('split is one-to-many with at most one inherited lineage', () {
      final newSuccessor = LineageEndpointV1(
        occurrenceId: CanonicalDigest('3' * 64),
        lineageId: PointLineageId('lineage.new'),
      );
      expect(
        LineageTransitionV1(
          transitionId: LineageTransitionId('transition.split'),
          publishedSurfaceRevisionId: SurfaceRevisionId('surface.checkout.v2'),
          operation: LineageOperation.split,
          authority: LineageTransitionAuthority.explicit,
          prior: [prior],
          next: [continued, newSuccessor],
        ).next,
        hasLength(2),
      );

      for (final invalidNext in <List<LineageEndpointV1>>[
        [continued],
        [
          continued,
          LineageEndpointV1(
            occurrenceId: CanonicalDigest('4' * 64),
            lineageId: prior.lineageId,
          ),
        ],
        [
          newSuccessor,
          LineageEndpointV1(
            occurrenceId: CanonicalDigest('5' * 64),
            lineageId: newSuccessor.lineageId,
          ),
        ],
      ]) {
        expect(
          () => LineageTransitionV1(
            transitionId: LineageTransitionId('transition.invalid-split'),
            publishedSurfaceRevisionId:
                SurfaceRevisionId('surface.checkout.v2'),
            operation: LineageOperation.split,
            authority: LineageTransitionAuthority.explicit,
            prior: [prior],
            next: invalidNext,
          ),
          throwsArgumentError,
        );
      }
      expect(
        () => LineageTransitionV1(
          transitionId: LineageTransitionId('transition.split-prior-arity'),
          publishedSurfaceRevisionId: SurfaceRevisionId('surface.checkout.v2'),
          operation: LineageOperation.split,
          authority: LineageTransitionAuthority.explicit,
          prior: const [],
          next: [continued, newSuccessor],
        ),
        throwsArgumentError,
      );
    });

    test('merge is many-to-one and protects converging histories', () {
      final other = LineageEndpointV1(
        occurrenceId: CanonicalDigest('4' * 64),
        lineageId: PointLineageId('lineage.other'),
      );
      final newLineage = LineageEndpointV1(
        occurrenceId: CanonicalDigest('5' * 64),
        lineageId: PointLineageId('lineage.merged'),
      );

      expect(
        LineageTransitionV1(
          transitionId: LineageTransitionId('transition.merge-explicit'),
          publishedSurfaceRevisionId: SurfaceRevisionId('surface.checkout.v2'),
          operation: LineageOperation.merge,
          authority: LineageTransitionAuthority.explicit,
          prior: [prior, other],
          next: [newLineage],
        ).next,
        [newLineage],
      );

      for (final invalid in <LineageTransitionV1 Function()>[
        () => LineageTransitionV1(
              transitionId: LineageTransitionId('transition.merge-arity'),
              publishedSurfaceRevisionId:
                  SurfaceRevisionId('surface.checkout.v2'),
              operation: LineageOperation.merge,
              authority: LineageTransitionAuthority.explicit,
              prior: [prior],
              next: [newLineage],
            ),
        () => LineageTransitionV1(
              transitionId: LineageTransitionId('transition.merge-authority'),
              publishedSurfaceRevisionId:
                  SurfaceRevisionId('surface.checkout.v2'),
              operation: LineageOperation.merge,
              authority: LineageTransitionAuthority.exactToken,
              prior: [prior, other],
              next: [continued],
            ),
        () => LineageTransitionV1(
              transitionId: LineageTransitionId('transition.merge-next-arity'),
              publishedSurfaceRevisionId:
                  SurfaceRevisionId('surface.checkout.v2'),
              operation: LineageOperation.merge,
              authority: LineageTransitionAuthority.explicit,
              prior: [prior, other],
              next: [continued, newLineage],
            ),
      ]) {
        expect(invalid, throwsArgumentError);
      }
    });

    test('transition graph rejects cycles', () {
      final reverse = LineageTransitionV1(
        transitionId: LineageTransitionId('transition.reverse'),
        publishedSurfaceRevisionId: SurfaceRevisionId('surface.checkout.v3'),
        operation: LineageOperation.continueLineage,
        authority: LineageTransitionAuthority.explicit,
        prior: [continued],
        next: [prior],
      );

      expect(
        () => validateLineageTransitionGraph([
          LineageTransitionV1(
            transitionId: LineageTransitionId('transition.forward'),
            publishedSurfaceRevisionId: SurfaceRevisionId(
              'surface.checkout.v2',
            ),
            operation: LineageOperation.continueLineage,
            authority: LineageTransitionAuthority.exactToken,
            prior: [prior],
            next: [continued],
          ),
          reverse,
        ]),
        throwsArgumentError,
      );
    });
  });
}

MeasurementPointOccurrenceV1 _copyOccurrence(
  MeasurementPointOccurrenceV1 source, {
  TargetCoordinate? target,
  SurfaceRevisionId? surfaceRevisionId,
  CanonicalDigest? artifactGraphHash,
  ArtifactId? artifactId,
  ArtifactOccurrenceEdgeToken? artifactOccurrenceEdgeToken,
  CanonicalDigest? artifactContentHash,
  NodeTokenId? canonicalNodeToken,
  MeasurementCapabilityKind? capabilityKind,
  SourceEventIdentity? sourceEventIdentity,
  bool clearSourceEventIdentity = false,
  NormalizedInteractionKind? normalizedInteractionKind,
  bool clearNormalizedInteractionKind = false,
  MeasurementPrivacyClass? privacyClass,
  SemanticValueClass? semanticValueClass,
  MeasurementCollectionClass? collectionClass,
  PointLineageId? lineageId,
  DisplayMetadataRef? displayMetadataRef,
}) =>
    MeasurementPointOccurrenceV1(
      target: target ?? source.target,
      surfaceRevisionId: surfaceRevisionId ?? source.surfaceRevisionId,
      artifactGraphHash: artifactGraphHash ?? source.artifactGraphHash,
      artifactId: artifactId ?? source.artifactId,
      artifactOccurrenceEdgeToken:
          artifactOccurrenceEdgeToken ?? source.artifactOccurrenceEdgeToken,
      artifactContentHash: artifactContentHash ?? source.artifactContentHash,
      canonicalNodeToken: canonicalNodeToken ?? source.canonicalNodeToken,
      capabilityKind: capabilityKind ?? source.capabilityKind,
      sourceEventIdentity: clearSourceEventIdentity
          ? null
          : sourceEventIdentity ?? source.sourceEventIdentity,
      normalizedInteractionKind: clearNormalizedInteractionKind
          ? null
          : normalizedInteractionKind ?? source.normalizedInteractionKind,
      privacyClass: privacyClass ?? source.privacyClass,
      semanticValueClass: semanticValueClass ?? source.semanticValueClass,
      collectionClass: collectionClass ?? source.collectionClass,
      lineageId: lineageId ?? source.lineageId,
      displayMetadataRef: displayMetadataRef ?? source.displayMetadataRef,
    );

LocalMeasurementManifestV1 _localManifest(
  MeasurementPointOccurrenceV1 occurrence, {
  MeasurementManifestId? manifestId,
  List<ArtifactId> childArtifactIds = const [],
  List<MeasurementPointOccurrenceV1>? points,
}) =>
    LocalMeasurementManifestV1(
      manifestId: manifestId ?? MeasurementManifestId('manifest.checkout-root'),
      target: occurrence.target,
      surfaceRevisionId: occurrence.surfaceRevisionId,
      artifactGraphHash: occurrence.artifactGraphHash,
      artifactId: occurrence.artifactId,
      artifactContentHash: occurrence.artifactContentHash,
      childArtifactIds: childArtifactIds,
      points: points ?? [occurrence],
      generatedReferences: const [],
      privacyPolicyRevisionId: AuthorityRevisionId('privacy.v1'),
      collectionBudgetRevisionId: AuthorityRevisionId('collection.v1'),
    );

CompleteMeasurementManifestV1 _completeManifest(
  MeasurementPointOccurrenceV1 root,
  List<LocalMeasurementManifestV1> localManifests,
) =>
    CompleteMeasurementManifestV1(
      manifestId: MeasurementManifestId('manifest.checkout-complete'),
      target: root.target,
      surfaceId: SurfaceId('surface.checkout'),
      surfaceRevisionId: root.surfaceRevisionId,
      rootArtifactId: root.artifactId,
      artifactGraphHash: root.artifactGraphHash,
      localManifests: localManifests,
      nodeAncestryIndex: _ancestryIndex(root, localManifests),
      privacyPolicyRevisionId: AuthorityRevisionId('privacy.v1'),
      collectionBudgetRevisionId: AuthorityRevisionId('collection.v1'),
    );

CanonicalNodeAncestryIndexV1 _ancestryIndex(
  MeasurementPointOccurrenceV1 root,
  List<LocalMeasurementManifestV1> localManifests,
) {
  final rootNode = AncestryNodeRefV1(
    artifactOccurrenceEdgeToken: root.artifactOccurrenceEdgeToken,
    canonicalNodeToken: root.canonicalNodeToken,
  );
  final nodesByIdentity = <String, AncestryNodeRefV1>{
    _ancestryIdentity(rootNode): rootNode,
  };
  for (final manifest in localManifests) {
    for (final point in manifest.points) {
      final node = AncestryNodeRefV1(
        artifactOccurrenceEdgeToken: point.artifactOccurrenceEdgeToken,
        canonicalNodeToken: point.canonicalNodeToken,
      );
      nodesByIdentity.putIfAbsent(_ancestryIdentity(node), () => node);
    }
  }
  final nodes = nodesByIdentity.values.toList();
  return CanonicalNodeAncestryIndexV1(
    rootNode: rootNode,
    directParentEdges: [
      CanonicalNodeParentEdgeV1(node: rootNode),
      for (final node in nodes.skip(1))
        CanonicalNodeParentEdgeV1(node: node, parent: rootNode),
    ],
  );
}

String _ancestryIdentity(AncestryNodeRefV1 node) =>
    '${node.artifactOccurrenceEdgeToken.value}\u0000'
    '${node.canonicalNodeToken.value}';
