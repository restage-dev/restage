import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/commands/surface_activate_command.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../_helpers/test_fixtures.dart';

void main() {
  late Directory tempDir;
  late FileCredentialStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('surface_activate_');
    store = FileCredentialStore(p.join(tempDir.path, 'credentials'));
    await seedCredential(store);
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  test('activates one exact non-versioned family revision', () async {
    Map<String, dynamic>? activationBody;
    final client = mockHttpClient((request) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      activationBody = body;
      return http.Response(
        jsonEncode({
          '__className__': 'SurfaceContractFamilyOperationResult',
          'family': {
            '__className__': 'SurfaceContractFamilyReference',
            'surfaceType': 'paywall',
            'surfaceSlug': 'pro',
            'sourceKind': 'paywall',
          },
          'publishedRevision': 3,
          'activePublishedRevisionAfter': 3,
          'identityFrozenAfter': false,
        }),
        200,
      );
    });
    final out = StringBuffer();
    final err = StringBuffer();
    final runner = CommandRunner<int>('restage', '')
      ..addCommand(
        SurfaceActivateCommand(
          stdout: out,
          stderr: err,
          interactive: const NonInteractive(),
          fixedSurfaceType: SurfaceType.paywall,
          credentialStore: store,
          httpClient: client,
        ),
      );

    final code = await runner.run([
      'activate',
      'pro',
      '--revision',
      '3',
      '--reason',
      'restore known good revision',
      '--project',
      'demo',
      '--app',
      'mobile',
      '--env',
      'staging',
    ]);

    expect(code, 0);
    expect(activationBody, isNotNull);
    expect(activationBody!['method'], 'activateSurface');
    expect(activationBody!['publishedRevision'], 3);
    expect(activationBody!['contractVersion'], isNull);
    expect(out.toString(), contains('Activated "pro" at r3'));
    expect(err.toString(), isEmpty);
  });
}
