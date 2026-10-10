import 'dart:io';

import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/cli.dart';
import 'package:restage_cli/src/credentials/credential.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../_helpers/test_fixtures.dart';

void main() {
  late Directory root;
  late FileCredentialStore store;
  late StringBuffer stdout;
  late StringBuffer stderr;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('surface_push_id_test_');
    store = FileCredentialStore(p.join(root.path, 'credentials'));
    stdout = StringBuffer();
    stderr = StringBuffer();
    await store.write(
      const Credential(
        endpoint: 'http://api.restage.localhost:8080/',
        kind: CredentialKind.authKey,
        authToken: 'key:private',
      ),
    );
    await seedRestageConfig(root, 'demo', 'mobile');
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  // Nothing may reach the network: the id is refused before the first request.
  final refusesEveryRequest = MockClient(
    (request) async => fail('sent a request for ${request.url}'),
  );

  for (final command in const ['surface', 'paywall']) {
    test('$command push refuses an id outside the grammar', () async {
      for (final refused in const ['\u{1F600}', 'WelcomeFlow', 'wel come']) {
        stderr.clear();
        final exit = await RestageCli(
          stdout: stdout,
          stderr: stderr,
          credentialStore: store,
          httpClient: refusesEveryRequest,
        ).run(<String>[command, 'push', refused, '-C', root.path]);

        expect(exit, 1, reason: 'expected `$refused` to be refused');
        expect(stderr.toString(), contains(surfaceSlugRefusalMessage));
      }
    });
  }
}
