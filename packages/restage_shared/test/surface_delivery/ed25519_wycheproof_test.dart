import 'dart:convert';
import 'dart:io';

import 'package:restage_shared/src/surface_delivery/ed25519_verify.dart';
import 'package:test/test.dart';

List<int> _hex(String hex) => [
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ];

void main() {
  final vectors = jsonDecode(
    File('test/fixtures/wycheproof/ed25519_test.json').readAsStringSync(),
  ) as Map<String, Object?>;

  // Wycheproof leaves these to the verifier. libsodium, whose rules the
  // verifier follows, refuses small-order keys and accepts mixed-order ones.
  bool expected(Map<String, Object?> test) => switch (test['result']) {
        'valid' => true,
        'invalid' => false,
        _ => !(test['flags']! as List).contains('SmallOrderPublicKey'),
      };

  test('every Wycheproof Ed25519 vector', () {
    var count = 0;
    for (final group in vectors['testGroups']! as List) {
      final key = _hex(
        ((group as Map)['publicKey'] as Map)['pk'] as String,
      );
      for (final test in group['tests'] as List) {
        final t = (test as Map).cast<String, Object?>();
        final message = _hex(t['msg']! as String);
        final signature = _hex(t['sig']! as String);
        final reason = 'tcId ${t['tcId']} ${t['flags']} ${t['comment']}';
        expect(ed25519Verify(key, message, signature), expected(t),
            reason: reason);
        expect(ed25519VerifyReference(key, message, signature), expected(t),
            reason: '$reason (reference)');
        count++;
      }
    }
    expect(count, vectors['numberOfTests']);
  });
}
