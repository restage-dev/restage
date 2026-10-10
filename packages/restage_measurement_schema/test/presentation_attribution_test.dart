import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:test/test.dart';

void main() {
  final identity = PublishedSurfaceIdentityV1.fromCanonicalBytes(
    File('test/fixtures/published_identity/published_surface_identity_v1.json')
        .readAsBytesSync(),
  );
  final surface = DeliverySurfaceReferenceV1(
    surfaceIdentity: identity,
    family: const DeliveryFamilySelectorV1.general(),
  );
  final frame = decodeCanonicalObject(
    File('test/fixtures/runtime/measurement_fact_frame_v1.json')
        .readAsBytesSync(),
  );
  final bundledContext = ExactMeasurementPublicationContextRefV1.fromJson(
    frame['publishedContext']! as Map<String, Object?>,
  );
  final binding = bundledContext.bindingReference;
  final bundledSurface = DeliverySurfaceReferenceV1(
    surfaceIdentity: bundledContext.surfaceIdentity,
    family: const DeliveryFamilySelectorV1.general(),
  );
  final publication = _publication(surface, binding: binding);
  final verified = _verified(surface, publication, binding: binding);
  final fallback = MountSelectionAttributionV1(
    resolvedTarget: identity.target,
    actualSurface: surface,
    resolutionKind: MountResolutionKindV1.compiledFallback,
    evidenceStrength: MountEvidenceStrengthV1.reportedLocal,
    mountNonceDigest: CanonicalDigest('a' * 64),
  );
  final widgetOnly = MountSelectionAttributionV1(
    placementKey: PlacementKeyV1.named(slug: 'home'),
    resolutionKind: MountResolutionKindV1.compiledFallback,
    evidenceStrength: MountEvidenceStrengthV1.reportedLocal,
    mountNonceDigest: CanonicalDigest('b' * 64),
  );

  group('opaque presentation assignment', () {
    final handle =
        base64Url.encode(List<int>.generate(32, (i) => i)).replaceAll('=', '');

    test('all owners round-trip under the exact versioned hash domain', () {
      for (final owner in PresentationAssignmentOwnerV2.values) {
        final carrier = PresentationAssignmentCarrierV2(
          owner: owner,
          outcomeLinkCarrier: handle,
        );
        final decoded = PresentationAssignmentCarrierV2.fromCanonicalBytes(
          carrier.canonicalBytes,
        );
        expect(decoded, carrier);
        expect(decoded.hashCode, carrier.hashCode);
        expect(decoded.owner, owner);
        expect(decoded.outcomeLinkCarrier, handle);
        expect(carrier.toJson(), {
          'kind': 'presentationAssignmentCarrier',
          'schemaVersion': 2,
          'owner': owner.name,
          'outcomeLinkCarrier': handle,
        });
        expect(
          carrier.canonicalDigest.hex,
          sha256.convert([
            ...utf8.encode('restage.presentation-assignment-carrier.v2\u0000'),
            ...carrier.canonicalBytes,
          ]).toString(),
        );
        expect(decoded.canonicalDigest, carrier.canonicalDigest);
        expect(carrier.toJson(), isNot(contains('canonicalDigest')));
        final bytes = carrier.canonicalBytes;
        bytes[0] = 0;
        carrier.toJson().clear();
        expect(
          PresentationAssignmentCarrierV2.fromCanonicalBytes(
            carrier.canonicalBytes,
          ),
          carrier,
        );
      }
      final independent = PresentationAssignmentCarrierV2(
        owner: PresentationAssignmentOwnerV2.independent,
        outcomeLinkCarrier: handle,
      );
      final joint = PresentationAssignmentCarrierV2(
        owner: PresentationAssignmentOwnerV2.joint,
        outcomeLinkCarrier: handle,
      );
      expect(independent, isNot(joint));
      expect(independent.canonicalDigest, isNot(joint.canonicalDigest));
    });

    test('independent and joint preserve the existing maximum handle size', () {
      final maximum = base64Url
          .encode(
            List<int>.filled(
              (measurementOutcomeLinkCarrierMaximumLength * 3) ~/ 4,
              255,
            ),
          )
          .replaceAll('=', '');
      expect(maximum.length, 4096);
      for (final owner in [
        PresentationAssignmentOwnerV2.independent,
        PresentationAssignmentOwnerV2.joint,
      ]) {
        for (final value in ['AA', maximum]) {
          final carrier = PresentationAssignmentCarrierV2(
            owner: owner,
            outcomeLinkCarrier: value,
          );
          if (value == maximum) {
            expect(
              carrier.canonicalBytes.length,
              owner == PresentationAssignmentOwnerV2.independent ? 4200 : 4194,
            );
          }
          expect(
            PresentationAssignmentCarrierV2.fromCanonicalBytes(
              carrier.canonicalBytes,
            ),
            carrier,
          );
          expect(
            MeasurementExperimentAssignmentV1.fromJson({
              'kind': 'measurementExperimentAssignment',
              'schemaVersion': 1,
              'outcomeLinkCarrier': value,
            }).outcomeLinkCarrier,
            value,
          );
        }
        expect(
          () => PresentationAssignmentCarrierV2(
            owner: owner,
            outcomeLinkCarrier: '${maximum}AA',
          ),
          throwsArgumentError,
        );
      }
    });

    test('path handles require exactly 32 decoded bytes', () {
      for (final length in [1, 31, 33, 3072]) {
        final value =
            base64Url.encode(List<int>.filled(length, 0)).replaceAll('=', '');
        expect(
          () => PresentationAssignmentCarrierV2(
            owner: PresentationAssignmentOwnerV2.path,
            outcomeLinkCarrier: value,
          ),
          throwsArgumentError,
          reason: '$length bytes',
        );
        expect(
          () => PresentationAssignmentCarrierV2.fromJson({
            'kind': 'presentationAssignmentCarrier',
            'schemaVersion': 2,
            'owner': 'path',
            'outcomeLinkCarrier': value,
          }),
          throwsA(isA<CanonicalFormatException>()),
        );
      }
      expect(handle.length, 43);
      expect(
        PresentationAssignmentCarrierV2(
          owner: PresentationAssignmentOwnerV2.path,
          outcomeLinkCarrier: handle,
        ).canonicalBytes.length,
        140,
      );
      expect(
        PresentationAssignmentCarrierV2(
          owner: PresentationAssignmentOwnerV2.path,
          outcomeLinkCarrier: handle,
        ).outcomeLinkCarrier,
        handle,
      );
    });

    test('opaque handle grammar rejects aliases padding and malformed input',
        () {
      for (final value in ['', 'A', 'AB', 'AA=', 'AA==', 'a+b/', 'AA\n', 'é']) {
        for (final owner in PresentationAssignmentOwnerV2.values) {
          expect(
            () => PresentationAssignmentCarrierV2(
              owner: owner,
              outcomeLinkCarrier: value,
            ),
            throwsArgumentError,
            reason: '$owner: $value',
          );
          expect(
            () => PresentationAssignmentCarrierV2.fromJson({
              'kind': 'presentationAssignmentCarrier',
              'schemaVersion': 2,
              'owner': owner.name,
              'outcomeLinkCarrier': value,
            }),
            throwsA(isA<CanonicalFormatException>()),
          );
        }
      }
    });

    test('assignment codec is closed and refuses noncanonical bytes', () {
      final carrier = PresentationAssignmentCarrierV2(
        owner: PresentationAssignmentOwnerV2.path,
        outcomeLinkCarrier: handle,
      );
      for (final field in [
        'members',
        'unit',
        'arm',
        'epoch',
        'canonicalDigest',
      ]) {
        expect(
          () => PresentationAssignmentCarrierV2.fromJson({
            ...carrier.toJson(),
            field: [],
          }),
          throwsA(isA<CanonicalFormatException>()),
        );
      }
      for (final (field, value) in <(String, Object?)>[
        ('kind', 'unknown'),
        ('schemaVersion', 1),
        ('schemaVersion', 2.0),
        ('owner', 'unknown'),
        ('owner', null),
        ('outcomeLinkCarrier', null),
      ]) {
        expect(
          () => PresentationAssignmentCarrierV2.fromJson({
            ...carrier.toJson(),
            field: value,
          }),
          throwsA(isA<CanonicalFormatException>()),
        );
      }
      for (final field in carrier.toJson().keys) {
        expect(
          () => PresentationAssignmentCarrierV2.fromJson(
            carrier.toJson()..remove(field),
          ),
          throwsA(isA<CanonicalFormatException>()),
        );
      }
      final text = utf8.decode(carrier.canonicalBytes);
      for (final invalid in [
        '$text\n',
        text.replaceFirst('"owner":"path"', '"owner":"path","owner":"path"'),
        text.replaceFirst('"schemaVersion":2', '"schemaVersion":2.0'),
        text.replaceFirst('"path"', r'"p\u0061th"'),
      ]) {
        expect(invalid, isNot(text));
        expect(
          () => PresentationAssignmentCarrierV2.fromCanonicalBytes(
            utf8.encode(invalid),
          ),
          throwsA(isA<CanonicalFormatException>()),
        );
      }
    });

    test('existing measurement assignment constructor and wire stay unchanged',
        () {
      const original = MeasurementExperimentAssignmentV1(
        outcomeLinkCarrier: 'already-validated',
      );
      expect(original.toJson(), {
        'kind': 'measurementExperimentAssignment',
        'schemaVersion': 1,
        'outcomeLinkCarrier': 'already-validated',
      });
    });
  });

  test('local surface and key-only fallback round-trip without remote evidence',
      () {
    for (final value in [fallback, widgetOnly]) {
      final decoded = MountSelectionAttributionV1.fromCanonicalBytes(
        value.canonicalBytes,
      );
      expect(decoded, value);
      expect(decoded.hashCode, value.hashCode);
      expect(decoded.canonicalDigest, value.canonicalDigest);
      expect(decoded.canonicalBytes, orderedEquals(value.canonicalBytes));
      expect(decoded.actualPublication, isNull);
      expect(decoded.measurementBinding, isNull);
      expect(decoded.resolvedSelectionDigest, isNull);
    }
    expect(widgetOnly.resolvedTarget, isNull);
    expect(widgetOnly.actualSurface, isNull);
    expect(
      widgetOnly.toJson().keys,
      unorderedEquals([
        'kind',
        'schemaVersion',
        'placementKey',
        'resolutionKind',
        'evidenceStrength',
        'mountNonceDigest',
      ]),
    );
  });

  test('bundled fallback retains its real binding without a remote publication',
      () {
    final bundled = MountSelectionAttributionV1(
      placementKey: PlacementKeyV1.generatedDefault(
        surfaceType: DeliverySurfaceTypeId('message'),
        slug: 'home',
      ),
      resolvedTarget: bundledSurface.target,
      actualSurface: bundledSurface,
      measurementBinding: binding,
      resolutionKind: MountResolutionKindV1.compiledFallback,
      evidenceStrength: MountEvidenceStrengthV1.reportedLocal,
      mountNonceDigest: CanonicalDigest('c' * 64),
    );
    final decoded = MountSelectionAttributionV1.fromCanonicalBytes(
      bundled.canonicalBytes,
    );
    expect(decoded.measurementBinding, binding);
    expect(decoded.resolvedTarget, bundledContext.surfaceIdentity.target);
    expect(decoded.actualSurface, bundledSurface);
    expect(decoded.actualPublication, isNull);
    expect(decoded.resolvedSelectionDigest, isNull);
    expect(decoded.toJson(), isNot(contains('actualPublication')));
  });

  test('hosted and cached verified selections retain complete known evidence',
      () {
    for (final kind in [
      MountResolutionKindV1.hosted,
      MountResolutionKindV1.cached,
    ]) {
      final value =
          _verified(surface, publication, binding: binding, kind: kind);
      final decoded = MountSelectionAttributionV1.fromJson(value.toJson());
      expect(decoded, value);
      expect(decoded.placementKey, PlacementKeyV1.named(slug: 'home'));
      expect(decoded.resolvedTarget, surface.target);
      expect(decoded.actualSurface, surface);
      expect(decoded.actualPublication, publication);
      expect(decoded.measurementBinding, binding);
      expect(decoded.resolvedSelectionDigest, CanonicalDigest('d' * 64));
    }
    final unbound = _verified(surface, _publication(surface));
    expect(unbound.measurementBinding, isNull);
    expect(unbound.actualPublication!.publicationBindingRef, isNull);
  });

  test(
      'reported local hosted and cached tuples preserve only supplied evidence',
      () {
    for (final kind in [
      MountResolutionKindV1.hosted,
      MountResolutionKindV1.cached,
    ]) {
      final value = MountSelectionAttributionV1(
        placementKey: widgetOnly.placementKey,
        actualPublication: publication,
        resolutionKind: kind,
        evidenceStrength: MountEvidenceStrengthV1.reportedLocal,
        mountNonceDigest: CanonicalDigest('a' * 64),
      );
      final decoded = MountSelectionAttributionV1.fromJson(value.toJson());
      expect(decoded.actualPublication, publication);
      expect(decoded.resolvedTarget, isNull);
      expect(decoded.actualSurface, isNull);
      expect(decoded.measurementBinding, isNull);
      expect(decoded.resolvedSelectionDigest, isNull);
    }
  });

  test(
      'the versioned mount digest covers the safe tuple without self-reference',
      () {
    final expected = sha256.convert([
      ...utf8.encode('restage.mount-selection-attribution.v1\u0000'),
      ...verified.canonicalBytes,
    ]);
    expect(verified.canonicalDigest.hex, expected.toString());
    expect(verified.toJson(), isNot(contains('canonicalDigest')));
    expect(verified.toJson(), isNot(contains('mountAttributionDigest')));
    expect(
      verified.canonicalDigest.hex,
      isNot(sha256.convert(verified.canonicalBytes).toString()),
    );
    final unterminated = sha256.convert([
      ...utf8.encode('restage.mount-selection-attribution.v1'),
      ...verified.canonicalBytes,
    ]);
    expect(verified.canonicalDigest.hex, isNot(unterminated.toString()));
    expect(
      MountSelectionAttributionV1.fromCanonicalBytes(verified.canonicalBytes)
          .canonicalDigest,
      verified.canonicalDigest,
    );
  });

  test(
      'the same public selection with a different nonce has a new mount digest',
      () {
    final second =
        _verified(surface, publication, binding: binding, nonce: 'b');
    expect(second.resolvedSelectionDigest, verified.resolvedSelectionDigest);
    expect(second.placementKey, verified.placementKey);
    expect(second.actualPublication, verified.actualPublication);
    expect(second.canonicalDigest, isNot(verified.canonicalDigest));
    expect(second, isNot(verified));
    final otherSelection = MountSelectionAttributionV1.fromJson({
      ...verified.toJson(),
      'resolvedSelectionDigest': 'e' * 64,
    });
    expect(otherSelection.canonicalDigest, isNot(verified.canonicalDigest));
  });

  test('all supplied target coordinates must agree', () {
    final targets = [
      for (final field in [
        'organizationId',
        'appId',
        'environmentTargetId',
        'namedEnvironmentId',
      ])
        TargetCoordinate.fromJson({
          ...surface.target.toJson(),
          field: (surface.target.toJson()[field]! as int) + 1,
        }),
      TargetCoordinate.fromJson({
        ...surface.target.toJson(),
        'runtimePlane': 'live',
      }),
    ];
    for (final otherTarget in targets) {
      final otherSurface = DeliverySurfaceReferenceV1(
        surfaceIdentity: PublishedSurfaceIdentityV1(
          target: otherTarget,
          surfaceId: identity.surfaceId,
        ),
        family: surface.family,
      );
      for (final (target, actualSurface, actualPublication) in [
        (otherTarget, surface, publication),
        (otherTarget, surface, null),
        (otherTarget, null, publication),
        (null, otherSurface, publication),
      ]) {
        expect(
          () => MountSelectionAttributionV1(
            resolvedTarget: target,
            actualSurface: actualSurface,
            actualPublication: actualPublication,
            resolutionKind: MountResolutionKindV1.hosted,
            evidenceStrength: MountEvidenceStrengthV1.reportedLocal,
            mountNonceDigest: CanonicalDigest('a' * 64),
          ),
          throwsArgumentError,
          reason: otherTarget.toJson().toString(),
        );
        expect(
          () => MountSelectionAttributionV1.fromJson({
            ...widgetOnly.toJson(),
            'resolutionKind': 'hosted',
            if (target != null) 'resolvedTarget': target.toJson(),
            if (actualSurface != null) 'actualSurface': actualSurface.toJson(),
            if (actualPublication != null)
              'actualPublication': actualPublication.toJson(),
          }),
          throwsA(isA<CanonicalFormatException>()),
        );
      }
    }
  });

  test('publication must match the supplied surface identity and family', () {
    final otherIdentity = PublishedSurfaceIdentityV1(
      target: surface.target,
      surfaceId: SurfaceId('surface.other'),
    );
    for (final otherSurface in [
      DeliverySurfaceReferenceV1(
        surfaceIdentity: otherIdentity,
        family: surface.family,
      ),
      DeliverySurfaceReferenceV1(
        surfaceIdentity: identity,
        family: DeliveryFamilySelectorV1.screenContract(contractVersion: 3),
      ),
    ]) {
      expect(
        () => _verified(otherSurface, publication, binding: binding),
        throwsArgumentError,
      );
      expect(
        () => MountSelectionAttributionV1.fromJson({
          ...verified.toJson(),
          'actualSurface': otherSurface.toJson(),
        }),
        throwsA(isA<CanonicalFormatException>()),
      );
    }
  });

  test('duplicate binding agrees without inferring absent coordinates', () {
    final otherBinding = MeasurementPublicationBindingReferenceV1.fromJson({
      ...binding.toJson(),
      'bindingDigest': 'f' * 64,
    });
    expect(
      () => _verified(surface, publication, binding: otherBinding),
      throwsArgumentError,
    );
    expect(
      () => MountSelectionAttributionV1.fromJson({
        ...verified.toJson(),
        'measurementBinding': otherBinding.toJson(),
      }),
      throwsA(isA<CanonicalFormatException>()),
    );
    final notDuplicated = _verified(surface, publication);
    expect(notDuplicated.measurementBinding, isNull);
    expect(notDuplicated.actualPublication!.publicationBindingRef, binding);
    final noPublicationBinding = _verified(
      surface,
      _publication(surface),
      binding: binding,
    );
    expect(noPublicationBinding.measurementBinding, binding);
    expect(
      noPublicationBinding.actualPublication!.publicationBindingRef,
      isNull,
    );
  });

  test('verified selection requires every public selection coordinate', () {
    for (final field in [
      'placementKey',
      'resolvedTarget',
      'actualSurface',
      'actualPublication',
      'resolvedSelectionDigest',
    ]) {
      expect(
        () => MountSelectionAttributionV1.fromJson(
          verified.toJson()..remove(field),
        ),
        throwsA(isA<CanonicalFormatException>()),
        reason: field,
      );
    }
    expect(
      () => MountSelectionAttributionV1(
        resolutionKind: MountResolutionKindV1.hosted,
        evidenceStrength: MountEvidenceStrengthV1.verifiedSelection,
        mountNonceDigest: CanonicalDigest('a' * 64),
      ),
      throwsArgumentError,
    );
  });

  test('compiled fallback refuses remote publication and verified evidence',
      () {
    for (final value in <Map<String, Object?>>[
      {...fallback.toJson(), 'actualPublication': publication.toJson()},
      {...fallback.toJson(), 'resolvedSelectionDigest': 'd' * 64},
      {...verified.toJson(), 'resolutionKind': 'compiledFallback'},
    ]) {
      expect(
        () => MountSelectionAttributionV1.fromJson(value),
        throwsA(isA<CanonicalFormatException>()),
      );
    }
    expect(
      () => MountSelectionAttributionV1(
        resolutionKind: MountResolutionKindV1.compiledFallback,
        evidenceStrength: MountEvidenceStrengthV1.verifiedSelection,
        mountNonceDigest: CanonicalDigest('a' * 64),
      ),
      throwsArgumentError,
    );
  });

  test('reported local evidence cannot claim a public selection digest', () {
    for (final kind in MountResolutionKindV1.values) {
      expect(
        () => MountSelectionAttributionV1(
          resolutionKind: kind,
          evidenceStrength: MountEvidenceStrengthV1.reportedLocal,
          mountNonceDigest: CanonicalDigest('a' * 64),
          resolvedSelectionDigest: CanonicalDigest('d' * 64),
        ),
        throwsArgumentError,
      );
      expect(
        () => MountSelectionAttributionV1.fromJson({
          ...widgetOnly.toJson(),
          'resolutionKind': kind.name,
          'resolvedSelectionDigest': 'd' * 64,
        }),
        throwsA(isA<CanonicalFormatException>()),
      );
    }
  });

  test('closed tuple refuses unknown private and digest fields', () {
    for (final field in [
      'unknown',
      'memberAliases',
      'routingSelectionReceipt',
      'assignment',
      'outcomeLinkCarrier',
      'privateEvidenceDigest',
      'canonicalDigest',
      'mountAttributionDigest',
    ]) {
      final json = {...fallback.toJson(), field: <Object?>[]};
      expect(
        () => MountSelectionAttributionV1.fromJson(json),
        throwsA(isA<CanonicalFormatException>()),
        reason: field,
      );
      expect(
        () => MountSelectionAttributionV1.fromCanonicalBytes(
          CanonicalJsonCodec.encode(json),
        ),
        throwsA(isA<CanonicalFormatException>()),
        reason: field,
      );
    }
    expect(
      () => MountSelectionAttributionV1.fromJson({
        ...verified.toJson(),
        'actualSurface': {...surface.toJson(), 'memberAliases': <Object?>[]},
      }),
      throwsA(isA<CanonicalFormatException>()),
    );
  });

  test('codec refuses duplicate byte keys and noncanonical spellings', () {
    final text = utf8.decode(widgetOnly.canonicalBytes);
    for (final invalid in [
      text.replaceFirst(
        '"schemaVersion":1',
        '"schemaVersion":1,"schemaVersion":1',
      ),
      text.replaceFirst('"slug":"home"', '"slug":"home","slug":"home"'),
      '$text\n',
      text.replaceFirst('"schemaVersion":1', '"schemaVersion":1.0'),
      text.replaceFirst('"home"', r'"h\u006fme"'),
    ]) {
      expect(invalid, isNot(text));
      expect(
        () => MountSelectionAttributionV1.fromCanonicalBytes(
          utf8.encode(invalid),
        ),
        throwsA(isA<CanonicalFormatException>()),
      );
    }
  });

  test('codec refuses unsupported kinds versions enums and malformed digests',
      () {
    for (final (field, value) in <(String, Object?)>[
      ('kind', 'unknown'),
      ('schemaVersion', 2),
      ('schemaVersion', 1.0),
      ('resolutionKind', 'unknown'),
      ('evidenceStrength', 'unknown'),
      ('mountNonceDigest', 'A' * 64),
      ('mountNonceDigest', 'a' * 63),
      ('mountNonceDigest', null),
      ('resolvedSelectionDigest', 'D' * 64),
    ]) {
      expect(
        () => MountSelectionAttributionV1.fromJson({
          ...verified.toJson(),
          field: value,
        }),
        throwsA(isA<CanonicalFormatException>()),
        reason: field,
      );
    }
    for (final field in [
      'kind',
      'schemaVersion',
      'resolutionKind',
      'evidenceStrength',
      'mountNonceDigest',
    ]) {
      expect(
        () => MountSelectionAttributionV1.fromJson(
          widgetOnly.toJson()..remove(field),
        ),
        throwsA(isA<CanonicalFormatException>()),
        reason: field,
      );
    }
  });

  test(
      'optional null is rejected where the canonical tuple omits absent fields',
      () {
    for (final field in [
      'placementKey',
      'resolvedTarget',
      'actualSurface',
      'actualPublication',
      'measurementBinding',
      'resolvedSelectionDigest',
    ]) {
      final json = {...widgetOnly.toJson(), field: null};
      expect(
        () => MountSelectionAttributionV1.fromJson(json),
        throwsA(isA<CanonicalFormatException>()),
        reason: field,
      );
      expect(
        () => MountSelectionAttributionV1.fromCanonicalBytes(
          CanonicalJsonCodec.encode(json),
        ),
        throwsA(isA<CanonicalFormatException>()),
        reason: field,
      );
    }
  });

  test('incoming and returned bytes and JSON cannot change a frozen tuple', () {
    final input = verified.canonicalBytes;
    final decoded = MountSelectionAttributionV1.fromCanonicalBytes(input);
    final digest = decoded.canonicalDigest;
    final hashCode = decoded.hashCode;
    input[0] = 0;
    decoded.canonicalBytes[0] = 0;
    final json = decoded.toJson();
    final nested = json['actualSurface']! as Map<String, Object?>;
    final nestedIdentity = nested['surfaceIdentity']! as Map<String, Object?>;
    (nestedIdentity['target']! as Map<String, Object?>)['appId'] = 999;
    json.clear();
    expect(decoded, verified);
    expect(decoded.hashCode, hashCode);
    expect(decoded.canonicalDigest, digest);
    expect(decoded.canonicalBytes, orderedEquals(verified.canonicalBytes));
    expect(decoded.resolvedTarget, surface.target);
  });
}

DeliveryPublicationReferenceV1 _publication(
  DeliverySurfaceReferenceV1 surface, {
  MeasurementPublicationBindingReferenceV1? binding,
}) =>
    DeliveryPublicationReferenceV1(
      surface: surface,
      publishedVersion: 7,
      payloadFormatVersion: 2,
      contentHash: CanonicalDigest('a' * 64),
      publicationBindingRef: binding,
    );

MountSelectionAttributionV1 _verified(
  DeliverySurfaceReferenceV1 surface,
  DeliveryPublicationReferenceV1 publication, {
  MeasurementPublicationBindingReferenceV1? binding,
  MountResolutionKindV1 kind = MountResolutionKindV1.hosted,
  String nonce = 'a',
}) =>
    MountSelectionAttributionV1(
      placementKey: PlacementKeyV1.named(slug: 'home'),
      resolvedTarget: surface.target,
      actualSurface: surface,
      actualPublication: publication,
      measurementBinding: binding,
      resolutionKind: kind,
      evidenceStrength: MountEvidenceStrengthV1.verifiedSelection,
      mountNonceDigest: CanonicalDigest(nonce * 64),
      resolvedSelectionDigest: CanonicalDigest('d' * 64),
    );
