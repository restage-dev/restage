// Compares the verifier with libsodium, OpenSSL and cryptography_plus on cases
// from generate.py:
//   python3 -I generate.py /tmp/cases.jsonl 9000
//   ED25519_CASES=/tmp/cases.jsonl dart test <this file>
import 'dart:convert';
import 'dart:io';

import 'package:cryptography_plus/cryptography_plus.dart' as c;
import 'package:cryptography_plus/dart.dart';
import 'package:restage_shared/src/surface_delivery/ed25519_verify.dart';
import 'package:test/test.dart';

final _path = Platform.environment['ED25519_CASES'];

List<int> _hex(String hex) => [
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ];

void main() {
  test('agrees with libsodium on every case', () async {
    final oracle = DartEd25519();
    final divergence = <String, int>{};
    void note(String what) => divergence[what] = (divergence[what] ?? 0) + 1;
    var count = 0;
    for (final line in File(_path!).readAsLinesSync()) {
      final row = jsonDecode(line) as Map<String, Object?>;
      final kind = row['kind']! as String;
      final pk = _hex(row['pk']! as String);
      final msg = _hex(row['msg']! as String);
      final sig = _hex(row['sig']! as String);
      final ours = ed25519Verify(pk, msg, sig);
      if (ours != row['sodium']) note('libsodium $kind');
      if (ours != row['openssl']) note('openssl $kind ours=$ours');
      bool plus;
      try {
        plus = await oracle.verify(msg,
            signature: c.Signature(sig,
                publicKey: c.SimplePublicKey(pk, type: c.KeyPairType.ed25519)));
      } on Object {
        plus = false;
      }
      if (ours != plus) note('cryptography_plus $kind ours=$ours');
      count++;
    }
    // ignore: avoid_print
    print('cases=$count divergence=$divergence');
    expect(divergence.keys.where((k) => k.startsWith('libsodium')), isEmpty);
  }, skip: _path == null ? 'set ED25519_CASES' : false, timeout: Timeout.none);
}
