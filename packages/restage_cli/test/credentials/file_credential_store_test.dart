import 'dart:io';

import 'package:restage_cli/src/credentials/credential.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('defaultCredentialPath', () {
    test('respects XDG_CONFIG_HOME on POSIX', () {
      final result = defaultCredentialPath(
        environment: const {'XDG_CONFIG_HOME': '/custom/xdg'},
        isWindows: false,
      );
      expect(result, p.join('/custom/xdg', 'restage', 'credentials'));
    });

    test('falls back to \$HOME/.config on POSIX without XDG', () {
      final result = defaultCredentialPath(
        environment: const {'HOME': '/home/jane'},
        isWindows: false,
      );
      expect(result, p.join('/home/jane', '.config', 'restage', 'credentials'));
    });

    test('uses APPDATA on Windows', () {
      final result = defaultCredentialPath(
        environment: const {'APPDATA': r'C:\Users\Jane\AppData\Roaming'},
        isWindows: true,
      );
      expect(result, contains('restage'));
      expect(result, endsWith('credentials'));
      expect(result, contains('AppData'));
    });

    test('throws StateError when no home / appdata is set', () {
      expect(
        () => defaultCredentialPath(
          environment: const <String, String>{},
          isWindows: false,
        ),
        throwsStateError,
      );
      expect(
        () => defaultCredentialPath(
          environment: const <String, String>{},
          isWindows: true,
        ),
        throwsStateError,
      );
    });
  });

  group('FileCredentialStore', () {
    late Directory tempDir;
    late String storePath;
    late FileCredentialStore store;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('restage_cli_test_');
      storePath = p.join(tempDir.path, 'restage', 'credentials');
      store = FileCredentialStore(storePath);
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('read returns null when no file exists', () async {
      expect(await store.read(), isNull);
    });

    test('write then read round-trips the credential', () async {
      const c = Credential(
        endpoint: 'https://api.example.com/',
        kind: CredentialKind.authKey,
        authToken: '42:abc',
      );
      await store.write(c);
      expect(await store.read(), c);
    });

    test(
      'read sanitizes malformed JSON without echoing credential contents',
      () async {
        await File(storePath).parent.create(recursive: true);
        await File(storePath).writeAsString(
          '{"endpoint":"https://api.example.com/",'
          '"kind":"authKey",'
          '"authToken":"secret-token",',
        );

        await expectLater(
          store.read(),
          throwsA(
            isA<MalformedCredentialFileException>()
                .having((e) => e.path, 'path', storePath)
                .having(
                  (e) => e.toString(),
                  'message',
                  allOf(
                    contains(storePath),
                    isNot(contains('secret-token')),
                    isNot(contains('authToken')),
                  ),
                ),
          ),
        );
      },
    );

    test('write creates parent directories as needed', () async {
      await store.write(
        const Credential(
          endpoint: 'https://api.example.com/',
          kind: CredentialKind.authKey,
          authToken: 'k',
        ),
      );
      expect(File(storePath).existsSync(), isTrue);
    });

    test('write overwrites an existing credential', () async {
      const first = Credential(
        endpoint: 'https://a/',
        kind: CredentialKind.authKey,
        authToken: '1:a',
      );
      const second = Credential(
        endpoint: 'https://b/',
        kind: CredentialKind.authKey,
        authToken: '2:b',
      );
      await store.write(first);
      await store.write(second);
      expect(await store.read(), second);
    });

    test('delete removes the file and read returns null afterwards', () async {
      await store.write(
        const Credential(
          endpoint: 'https://api.example.com/',
          kind: CredentialKind.authKey,
          authToken: 'k',
        ),
      );
      await store.delete();
      expect(await store.read(), isNull);
    });

    test('delete is a no-op when no file exists', () async {
      await store.delete();
      expect(await store.read(), isNull);
    });

    test(
      'on POSIX, the written file is permissioned 600 (owner read/write)',
      onPlatform: const {
        'windows': Skip('chmod 600 only applies on POSIX systems'),
      },
      () async {
        await store.write(
          const Credential(
            endpoint: 'https://api.example.com/',
            kind: CredentialKind.authKey,
            authToken: 'k',
          ),
        );
        final stat = await File(storePath).stat();
        // Mask the lower 9 bits (owner / group / other read-write-exec).
        final perms = stat.mode & 0x1FF;
        expect(perms, 0x180); // 0600 (owner rw, group nothing, other nothing).
      },
    );
  });
}
