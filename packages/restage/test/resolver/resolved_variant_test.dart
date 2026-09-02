import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/measurement/measurement_resolved_publication_provenance.dart';

void main() {
  test('ResolvedVariant stores bytes + metadata', () {
    final v = ResolvedVariant(
      bytes: Uint8List.fromList([1, 2, 3]),
      surfaceVersion: 'sha256:example',
      paywallId: 'pro_upgrade',
      paywallVersion: '0.0.1',
      paywallPublishedVersion: 7,
      cacheHit: false,
    );
    expect(v.bytes.length, 3);
    expect(v.paywallId, 'pro_upgrade');
    expect(v.surfaceVersion, 'sha256:example');
    expect(v.paywallPublishedVersion, 7);
    expect(v.cacheHit, isFalse);
  });

  test('ResolvedVariant remains subclassable', () {
    final variant = _ExtendedResolvedVariant(
      bytes: Uint8List.fromList([1, 2, 3]),
      paywallId: 'pro_upgrade',
      surfaceVersion: 'sha256:extended',
    );

    expect(variant, isA<ResolvedVariant>());
    expect(variant.label, 'extended');
  });

  group('ResolvedVariant value equality (identity tuple)', () {
    ResolvedVariant make({
      List<int> bytes = const [1, 2, 3],
      String paywallId = 'pro_upgrade',
      String surfaceVersion = 'sha256:example',
      String? paywallVersion = '0.0.1',
      int? paywallPublishedVersion = 7,
      MeasurementPublicationBindingReferenceV1? publicationBindingReference,
      bool cacheHit = false,
    }) =>
        attachMeasurementPublicationBindingReference(
          ResolvedVariant(
            bytes: Uint8List.fromList(bytes),
            surfaceVersion: surfaceVersion,
            paywallId: paywallId,
            paywallVersion: paywallVersion,
            paywallPublishedVersion: paywallPublishedVersion,
            cacheHit: cacheHit,
          ),
          publicationBindingReference,
        );

    test('equal over the identity tuple, ignoring bytes and cacheHit', () {
      expect(
        make(bytes: const [1, 2, 3], cacheHit: false),
        equals(make(bytes: const [9, 9, 9], cacheHit: true)),
      );
      expect(
        make(bytes: const [1, 2, 3], cacheHit: false).hashCode,
        make(bytes: const [9, 9, 9], cacheHit: true).hashCode,
      );
    });

    test('differs when any identity field differs', () {
      expect(make(paywallId: 'a'), isNot(equals(make(paywallId: 'b'))));
      expect(
        make(surfaceVersion: 'sha256:a'),
        isNot(equals(make(surfaceVersion: 'sha256:b'))),
      );
      expect(
        make(paywallVersion: '1'),
        isNot(equals(make(paywallVersion: '2'))),
      );
      final first = make(publicationBindingReference: _bindingReference('a'));
      final second = make(publicationBindingReference: _bindingReference('b'));
      // Measurement provenance stays in an SDK-private carrier. It must not
      // widen the public value identity of a resolved paywall.
      expect(first, equals(second));
      expect(
        measurementPublicationBindingReferenceFor(first),
        isNot(equals(measurementPublicationBindingReferenceFor(second))),
      );
    });

    test('differs when the published version differs (hosted republish)', () {
      // A hosted republish (v1 -> v2) changes the bytes, so the same id at a
      // different published version must NOT compare equal — otherwise a host's
      // "same variant, skip re-render" cache would show stale content. Null
      // (asset-resolved) vs an int (hosted) also differ.
      expect(
        make(paywallPublishedVersion: 1),
        isNot(equals(make(paywallPublishedVersion: 2))),
      );
      expect(
        make(paywallPublishedVersion: 1).hashCode,
        isNot(make(paywallPublishedVersion: 2).hashCode),
      );
      expect(
        make(paywallPublishedVersion: null),
        isNot(equals(make(paywallPublishedVersion: 3))),
      );
    });
  });

  group('ResolvedVariant.copyWith (all-fields-preserved drop-class guard)', () {
    // Every field is a DISTINCT non-default value so a dropped/reset field is
    // caught field-by-field (the identity `==` deliberately ignores bytes +
    // cacheHit, so preservation is asserted per-field, NOT via equals).
    final full = attachMeasurementPublicationBindingReference(
      ResolvedVariant(
        bytes: Uint8List.fromList([7, 8, 9]),
        surfaceVersion: 'sha256:full',
        paywallId: 'pro_upgrade',
        paywallVersion: '0.0.1',
        paywallPublishedVersion: 7,
        cacheHit: false,
      ),
      _bindingReference('c'),
    );

    test('copyWith() with no overrides preserves every field', () {
      final copy = full.copyWith();
      expect(copy.bytes, full.bytes);
      expect(copy.paywallId, 'pro_upgrade');
      expect(copy.surfaceVersion, 'sha256:full');
      expect(copy.paywallVersion, '0.0.1');
      expect(copy.paywallPublishedVersion, 7);
      // A public copy can alter the payload identity, so it must never carry
      // an exact delivery binding by implication.
      expect(measurementPublicationBindingReferenceFor(copy), isNull);
      expect(copy.cacheHit, isFalse);
    });

    test('copyWith(cacheHit: true) flips only cacheHit, preserves the rest',
        () {
      final hit = full.copyWith(cacheHit: true);
      expect(hit.cacheHit, isTrue);
      expect(hit.bytes, full.bytes);
      expect(hit.paywallId, 'pro_upgrade');
      expect(hit.surfaceVersion, 'sha256:full');
      expect(hit.paywallVersion, '0.0.1');
      expect(hit.paywallPublishedVersion, 7);
      expect(measurementPublicationBindingReferenceFor(hit), isNull);
    });

    test('each override lands independently', () {
      expect(full.copyWith(paywallId: 'other').paywallId, 'other');
      expect(
        full.copyWith(surfaceVersion: 'sha256:next').surfaceVersion,
        'sha256:next',
      );
      expect(full.copyWith(paywallVersion: '9').paywallVersion, '9');
      expect(
        full.copyWith(paywallPublishedVersion: 42).paywallPublishedVersion,
        42,
      );
      final replaced = full.copyWith(
        bytes: Uint8List.fromList([1]),
        surfaceVersion: 'sha256:replacement',
      );
      expect(replaced.bytes, Uint8List.fromList([1]));
      expect(replaced.surfaceVersion, 'sha256:replacement');
    });

    test('copyWith() rejects replacement bytes without a new identity', () {
      expect(
        () => full.copyWith(bytes: Uint8List.fromList([1])),
        throwsArgumentError,
      );
      expect(
        () => full.copyWith(
          bytes: Uint8List.fromList([1]),
          surfaceVersion: full.surfaceVersion,
        ),
        throwsArgumentError,
      );
    });
  });

  test('RestagePaywallError exposes code + message', () {
    const e = RestagePaywallError(
      code: 'decode_failed',
      message: 'corrupt blob',
      retryable: false,
    );
    expect(e.code, 'decode_failed');
    expect(e.toString(), contains('corrupt blob'));
  });

  test('the private provenance carrier cannot rebind a resolved payload', () {
    final variant = ResolvedVariant(
      bytes: Uint8List.fromList([1, 2, 3]),
      surfaceVersion: 'test',
      paywallId: 'pro_upgrade',
    );
    final original = _bindingReference('d');
    attachMeasurementPublicationBindingReference(variant, original);

    expect(
      () => attachMeasurementPublicationBindingReference(
        variant,
        _bindingReference('e'),
      ),
      throwsStateError,
    );
    expect(measurementPublicationBindingReferenceFor(variant), original);
  });

  test('ResolvedVariant rejects an empty surfaceVersion', () {
    expect(
      () => ResolvedVariant(
        bytes: Uint8List.fromList([1]),
        paywallId: 'pro_upgrade',
        surfaceVersion: '',
      ),
      throwsArgumentError,
    );
  });
}

MeasurementPublicationBindingReferenceV1 _bindingReference(String seed) {
  final candidate = MeasurementPublicationCandidateReferenceV1(
    candidateDigest: CanonicalDigest(seed * 64),
    selectedPublicationManifestDigest: CanonicalDigest('b' * 64),
    declaredArtifactBytesDigest: CanonicalDigest('c' * 64),
    assembledPublicationUploadDigest: CanonicalDigest('d' * 64),
    measurementPublicationDraftDigest: CanonicalDigest('e' * 64),
  );
  return MeasurementPublicationBindingReferenceV1(
    publicationAuthorityReference: RegisteredPublicationAuthorityReferenceV1(
      authorityId: MeasurementPublicationAuthorityId(
        'authority.resolved-variant.$seed',
      ),
      externalPublicationAuthorityRef: 'mpa1.${seed.toUpperCase() * 32}',
      candidateReference: candidate,
      immutablePublicationDigest: CanonicalDigest('f' * 64),
      declaredArtifactBytesDigest: candidate.declaredArtifactBytesDigest,
    ),
    bindingDigest: CanonicalDigest('0' * 64),
  );
}

final class _ExtendedResolvedVariant extends ResolvedVariant {
  _ExtendedResolvedVariant({
    required Uint8List bytes,
    required String paywallId,
    required String surfaceVersion,
  }) : super(
          bytes: bytes,
          paywallId: paywallId,
          surfaceVersion: surfaceVersion,
        );

  String get label => 'extended';
}
