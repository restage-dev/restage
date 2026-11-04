import 'dart:convert';

import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_measurement_schema/src/canonical.dart'
    show canonicalDecodeTrusted, decodeTrustedCanonical;
import 'package:test/test.dart';

void main() {
  final target = TargetCoordinate(
    organizationId: OrganizationId(11),
    appId: ApplicationId(23),
    environmentTargetId: EnvironmentTargetId(31),
    namedEnvironmentId: NamedEnvironmentId(37),
    runtimePlane: RuntimePlane.sandbox,
  );
  final reference = GeneratedPointReferenceV1(
    referenceId: GeneratedReferenceId('reference.checkout-button'),
    target: target,
    surfaceRevisionId: SurfaceRevisionId('surface.checkout.v1'),
    artifactGraphHash: CanonicalDigest('a' * 64),
    occurrenceId: CanonicalDigest('b' * 64),
    lineageId: PointLineageId('lineage.checkout-button'),
    sourceEventIdentity: SourceEventIdentity('onPressed'),
    dartSymbol: GeneratedDartSymbol('checkoutButtonOnPressed'),
  );
  final bytes = reference.canonicalBytes;

  test('decodes canonical input to the value, bytes and digest strict does',
      () {
    final strict = GeneratedPointReferenceV1.fromCanonicalBytes(bytes);
    final trusted = decodeTrustedCanonical(
      () => GeneratedPointReferenceV1.fromCanonicalBytes(bytes),
    );

    expect(trusted, strict);
    expect(trusted.canonicalBytes, bytes);
    expect(trusted.hashCode, strict.hashCode);
    expect(trusted.canonicalDigest, strict.canonicalDigest);
    expect(
      trusted.canonicalDigest,
      canonicalSha256(trusted.hashDomain, bytes),
    );
  });

  test("holds a copy of the input, not the caller's list", () {
    final input = List<int>.of(bytes);
    final trusted = decodeTrustedCanonical(
      () => GeneratedPointReferenceV1.fromCanonicalBytes(input),
    );
    input[0] = 0x20;

    expect(trusted.canonicalBytes, bytes);
  });

  test('still refuses an unknown or missing key', () {
    final extra = CanonicalJsonCodec.encode({
      ...reference.toJson(),
      'addedLater': true,
    });
    final missing = CanonicalJsonCodec.encode(
      reference.toJson()..remove('dartSymbol'),
    );

    for (final input in [extra, missing]) {
      expect(
        () => decodeTrustedCanonical(
          () => GeneratedPointReferenceV1.fromCanonicalBytes(input),
        ),
        throwsA(isA<CanonicalFormatException>()),
      );
    }
  });

  test('runs only for the decode it wraps, even when that decode throws', () {
    final spaced = utf8.encode(' ${utf8.decode(bytes)}');

    expect(canonicalDecodeTrusted, isFalse);
    expect(
      () => decodeTrustedCanonical<void>(() {
        expect(canonicalDecodeTrusted, isTrue);
        decodeTrustedCanonical(() => null);
        expect(canonicalDecodeTrusted, isTrue);
        throw StateError('refused');
      }),
      throwsStateError,
    );
    expect(canonicalDecodeTrusted, isFalse);
    expect(
      () => GeneratedPointReferenceV1.fromCanonicalBytes(spaced),
      throwsA(isA<CanonicalFormatException>()),
    );
  });
}
