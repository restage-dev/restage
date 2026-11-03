import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography_plus/dart.dart';
import 'package:cryptography_plus/cryptography_plus.dart' as c;
import 'package:restage_shared/src/surface_delivery/ed25519_verify.dart';
import 'package:test/test.dart';

Uint8List _hex(String hex) => Uint8List.fromList([
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);

void main() {
  test('RFC 8032 vectors verify', () {
    expect(
      ed25519Verify(
        _hex(
            'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a'),
        const [],
        _hex('e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555'
            'fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b'),
      ),
      isTrue,
    );
    expect(
      ed25519Verify(
        _hex(
            '3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c'),
        const [0x72],
        _hex('92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da'
            '085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00'),
      ),
      isTrue,
    );
  });

  test('agrees with an independent implementation', () async {
    final random = Random(984);
    final algorithm = DartEd25519();
    for (var round = 0; round < 40; round++) {
      final pair = await algorithm.newKeyPairFromSeed(
          List<int>.generate(32, (_) => random.nextInt(256)));
      final publicKey = (await pair.extractPublicKey()).bytes;
      final message =
          List<int>.generate(random.nextInt(400), (_) => random.nextInt(256));
      final signature = (await algorithm.sign(message, keyPair: pair)).bytes;
      expect(ed25519Verify(publicKey, message, signature), isTrue);
      if (round < 5) {
        expect(ed25519VerifyReference(publicKey, message, signature), isTrue);
        expect(ed25519VerifyReference(publicKey, [...message, 1], signature),
            isFalse);
      }

      // One flipped bit anywhere fails.
      final badMessage = [...message, 1];
      expect(ed25519Verify(publicKey, badMessage, signature), isFalse);
      final badSignature = [...signature];
      badSignature[random.nextInt(64)] ^= 1 << random.nextInt(8);
      expect(ed25519Verify(publicKey, message, badSignature), isFalse);
      final otherKey =
          (await (await algorithm.newKeyPair()).extractPublicKey()).bytes;
      expect(ed25519Verify(otherKey, message, signature), isFalse);
      final oracle = await algorithm.verify(badSignature,
          signature: c.Signature(signature,
              publicKey:
                  c.SimplePublicKey(publicKey, type: c.KeyPairType.ed25519)));
      expect(oracle, isFalse);
    }
  });

  test('the test signer matches RFC 8032', () {
    final (publicKey, signature) = ed25519SignForTesting(
      _hex('9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60'),
      const [],
    );
    expect(
      publicKey,
      _hex('d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a'),
    );
    expect(
      signature,
      _hex('e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555'
          'fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b'),
    );
  });

  test('refuses elements that are not bytes on both paths', () {
    final message = [0x41, 0x42];
    final (publicKey, signature) =
        ed25519SignForTesting(List<int>.filled(32, 9), message);
    final l = (BigInt.one << 252) +
        BigInt.parse('27742317777372353535851937790883648493');
    var s = BigInt.zero;
    for (var i = 63; i >= 32; i--) {
      s = (s << 8) | BigInt.from(signature[i]);
    }
    final sPlusL = [
      for (var i = 0; i < 32; i++)
        (((s + l) >> (8 * i)) & BigInt.from(255)).toInt(),
    ];
    final malleable = [...signature.sublist(0, 32), ...sPlusL]..[63] =
        sPlusL[31] - 256;
    final widePublicKey = [...publicKey]..[0] = publicKey[0] + 256;
    for (final (pk, msg, sig) in [
      (publicKey, message, malleable),
      (publicKey, [0x141, 0x42], signature),
      (widePublicKey, message, signature),
    ]) {
      expect(ed25519Verify(pk, msg, sig), isFalse);
      expect(ed25519VerifyReference(pk, msg, sig), isFalse);
    }
    expect(ed25519Verify(publicKey, message, signature), isTrue);
  });

  test('refuses a scalar at or above the group order', () {
    final signature = Uint8List(64)..fillRange(32, 64, 0xff);
    expect(
      ed25519Verify(
        _hex(
            'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a'),
        const [],
        signature,
      ),
      isFalse,
    );
  });

  test('timing', () async {
    final algorithm = DartEd25519();
    final pair = await algorithm.newKeyPairFromSeed(List<int>.filled(32, 7));
    final publicKey = (await pair.extractPublicKey()).bytes;
    final message = List<int>.filled(300, 3);
    final signature = (await algorithm.sign(message, keyPair: pair)).bytes;
    for (var i = 0; i < 50; i++) {
      ed25519Verify(publicKey, message, signature);
    }
    final sw = Stopwatch()..start();
    for (var i = 0; i < 200; i++) {
      ed25519Verify(publicKey, message, signature);
    }
    // ignore: avoid_print
    print('fast verify ${sw.elapsedMicroseconds / 200} us');
  });
}
