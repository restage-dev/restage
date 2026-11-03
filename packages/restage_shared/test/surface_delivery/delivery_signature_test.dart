import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/src/surface_delivery/delivery_signing_testing.dart';
import 'package:test/test.dart';

const _hash =
    'sha256:1111111111111111111111111111111111111111111111111111111111111111';

Map<String, Object?> _json() => {
      'artifactPass': 'pass',
      'artifactUrl': 'https://artifacts.example/a',
      'contentHash': _hash,
      'payloadFormatVersion': 1,
      'publishedAtMicros': 1000,
      'surfaceSlug': 'welcome',
      'surfaceType': 'onboarding',
      'version': 3,
    };

void main() {
  final signer = TestDeliverySigner(organizationId: 42);
  SurfaceArtifactDescriptor signed([Map<String, Object?> extra = const {}]) =>
      SurfaceArtifactDescriptorV1Codec.decode({
        ...signer.signJson(_json()),
        ...extra,
      });

  test('a signed descriptor verifies under its key', () {
    expect(DeliveryKeyring([signer.publicKey]).check(signed()), isNull);
  });

  test('the per-request URL and pass are outside the signature', () {
    final descriptor = signed({
      'artifactUrl': 'https://elsewhere.example/b',
      'artifactPass': 'other',
    });
    expect(DeliveryKeyring([signer.publicKey]).check(descriptor), isNull);
  });

  test('every signed field is covered', () {
    final keyring = DeliveryKeyring([signer.publicKey]);
    for (final change in <String, Object?>{
      'contentHash': _hash.replaceAll('1', '2'),
      'payloadFormatVersion': 2,
      'publishedAtMicros': 1001,
      'authorizedAtMicros': 5000,
      'surfaceSlug': 'other',
      'surfaceType': 'paywall',
      'version': 4,
    }.entries) {
      expect(
        keyring.check(signed({change.key: change.value})),
        DeliveryRefusal.invalidSignature,
        reason: change.key,
      );
    }
  });

  test('the organization is bound through the configured key', () {
    final foreign = DeliveryPublicKey(
      organizationId: 43,
      bytes: signer.publicKey.bytes,
    );
    expect(
      DeliveryKeyring([foreign]).check(signed()),
      DeliveryRefusal.invalidSignature,
    );
  });

  test('another key is refused, and a rotation accepts both', () {
    final other = TestDeliverySigner(organizationId: 42, seedByte: 9);
    expect(
      DeliveryKeyring([other.publicKey]).check(signed()),
      DeliveryRefusal.unknownKey,
    );
    expect(
      DeliveryKeyring([other.publicKey, signer.publicKey]).check(signed()),
      isNull,
    );
  });

  test('an unsigned or version 1 descriptor does not decode', () {
    final json = signer.signJson(_json());
    expect(
      () => SurfaceArtifactDescriptorV1Codec.decode(
          {...json}..remove('signature')),
      throwsFormatException,
    );
    expect(
      () => SurfaceArtifactDescriptorV1Codec.decode({
        ...json,
        'descriptorVersion': 1,
      }),
      throwsFormatException,
    );
    expect(
      () => SurfaceArtifactDescriptorV1Codec.decode({
        ...json,
        'signature': 'ed25519:abc:def',
      }),
      throwsFormatException,
    );
  });

  test('values with no canonical form are refused, never thrown', () {
    for (final change in <String, Object?>{
      'version': 9007199254740992,
      'surfaceSlug': 'a\ud800',
    }.entries) {
      expect(
        () => SurfaceArtifactDescriptorV1Codec.decode({
          ...signer.signJson(_json()),
          change.key: change.value,
        }),
        throwsFormatException,
        reason: change.key,
      );
    }
    final unportable = SurfaceArtifactDescriptor(
      payloadFormatVersion: 1,
      surfaceType: Surface.onboarding,
      surfaceSlug: 'welcome',
      version: 9007199254740992,
      publishedAtMicros: 1000,
      contentHash: _hash,
      artifactUrl: 'https://artifacts.example/a',
      artifactPass: 'pass',
      signature: signed().signature,
      authorizedAtMicros: 1000,
    );
    expect(
      DeliveryKeyring([signer.publicKey]).check(unportable),
      DeliveryRefusal.invalidSignature,
    );
  });

  test('a public key round-trips its printed form', () {
    final printed = signer.publicKey.toString();
    expect(DeliveryPublicKey.parse(printed), signer.publicKey);
    expect(() => DeliveryPublicKey.parse('x:abc'), throwsFormatException);
  });
}
