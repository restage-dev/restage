import 'package:restage_cli/api.dart';
import 'package:test/test.dart';

void main() {
  test('api.dart re-exports the reusable wire/auth/credential layer', () {
    // Referencing each symbol proves the export is reachable from the public
    // `api.dart` library (compile-time check), with a couple of behavioural
    // touches so the test exercises rather than merely names the surface.
    expect(isAcceptableTransport(Uri.parse('https://example/')), isTrue);
    expect(isAcceptableTransport(Uri.parse('http://example/')), isFalse);
    expect(CredentialKind.authKey, 'authKey');
    expect(
      defaultCredentialPath(
        environment: const {'HOME': '/home/user'},
        isWindows: false,
      ),
      '/home/user/.config/restage/credentials',
    );
    expect(
      const Credential(
        endpoint: 'https://example/',
        kind: CredentialKind.authKey,
        authToken: 'keyId:key',
      ),
      isA<Credential>(),
    );

    // Types referenced to prove the export (no instances required).
    expect(RestageApi, isNotNull);
    expect(RestageApiException, isNotNull);
    expect(InsecureEndpointException, isNotNull);
    expect(AuthApi, isNotNull);
    expect(PaywallApi, isNotNull);
    expect(PaywallSummary, isNotNull);
    expect(SurfaceApi, isNotNull);
    expect(SurfaceNotFound, isNotNull);
    expect(FileCredentialStore, isNotNull);
  });

  test(
    'api.dart re-exports the restage_shared types used in its signatures',
    () {
      // SurfaceApi/PaywallApi signatures name these; re-exporting them lets a
      // consumer name them without a second `package:restage_shared` import.
      expect(SurfaceType.paywall.wireName, 'paywall');
      expect(
        const LibraryRequirement(namespace: 'restage.material', minVersion: 1),
        isA<LibraryRequirement>(),
      );
    },
  );
}
