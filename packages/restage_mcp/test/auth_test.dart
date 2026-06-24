import 'dart:io';

import 'package:restage_cli/api.dart';
import 'package:restage_mcp/src/auth.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late FileCredentialStore store;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('restage_mcp_auth_test');
    store = FileCredentialStore('${tempDir.path}/credentials');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('resolveAuthenticatedApi', () {
    test('throws NotSignedInException when no credential exists', () {
      expect(
        () => resolveAuthenticatedApi(store: store),
        throwsA(isA<NotSignedInException>()),
      );
    });

    test('NotSignedInException message points at `restage login`', () {
      expect(
        const NotSignedInException().toString(),
        contains('restage login'),
      );
    });

    test('returns a RestageApi for an https credential', () async {
      await store.write(
        const Credential(
          endpoint: 'https://example.test/',
          kind: CredentialKind.authKey,
          authToken: 'keyId:key',
        ),
      );
      final api = await resolveAuthenticatedApi(store: store);
      expect(api, isA<RestageApi>());
      api.close();
    });

    test('returns a RestageApi for an http loopback credential', () async {
      await store.write(
        const Credential(
          endpoint: 'http://127.0.0.1:8080/',
          kind: CredentialKind.authKey,
          authToken: 'keyId:key',
        ),
      );
      final api = await resolveAuthenticatedApi(store: store);
      expect(api, isA<RestageApi>());
      api.close();
    });

    test('propagates InsecureEndpointException for a non-loopback http '
        'credential', () async {
      await store.write(
        const Credential(
          endpoint: 'http://evil.example/',
          kind: CredentialKind.authKey,
          authToken: 'keyId:key',
        ),
      );
      expect(
        () => resolveAuthenticatedApi(store: store),
        throwsA(isA<InsecureEndpointException>()),
      );
    });
  });
}
