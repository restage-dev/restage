import 'package:restage_cli/src/credentials/credential.dart';
import 'package:test/test.dart';

void main() {
  group('Credential', () {
    test('toJson round-trips through fromJson', () {
      const c = Credential(
        endpoint: 'https://api.example.com/',
        kind: 'authKey',
        authToken: '42:abc',
      );
      expect(Credential.fromJson(c.toJson()), c);
    });

    test('fromJson defaults kind to "authKey" when absent', () {
      final c = Credential.fromJson(<String, dynamic>{
        'endpoint': 'https://api.example.com/',
        'authToken': '42:abc',
      });
      expect(c.kind, 'authKey');
      expect(c.endpoint, 'https://api.example.com/');
      expect(c.authToken, '42:abc');
    });

    test('fromJson preserves an unknown kind for forward-compat', () {
      // Older readers must not crash on a kind they do not recognise — the
      // file format is forward-compatible and unrecognised kinds surface
      // as a domain error at the auth-header builder, not at parse time.
      final c = Credential.fromJson(<String, dynamic>{
        'endpoint': 'https://api.example.com/',
        'kind': 'apiKey',
        'authToken': 'rs_pk_test_xyz',
      });
      expect(c.kind, 'apiKey');
    });
  });
}
