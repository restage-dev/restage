import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/tui/console_command_executor.dart';
import 'package:restage_cli/src/tui/console_models.dart';
import 'package:test/test.dart';

import '../_helpers/test_fixtures.dart';

void main() {
  late Directory dir;
  late FileCredentialStore store;
  late List<Map<String, dynamic>> calls;
  late ConsoleCommandExecutor executor;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('restage-console-line-');
    store = FileCredentialStore(p.join(dir.path, 'credential.json'));
    await seedCredential(store);
    await seedRestageConfig(
      dir,
      'default',
      'mobile',
      defaultEnvironment: 'staging',
      organization: 'restage',
    );
    calls = [];
    executor = ConsoleCommandExecutor(
      credentialStore: store,
      httpClient: mockHttpClient((request) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        calls.add(body);
        return http.Response('[]', 200);
      }),
      directory: dir,
    );
  });

  tearDown(() => dir.delete(recursive: true));

  test(
    'a command that reads the project runs in the console project',
    () async {
      final result = await executor.runCommand(['orgs']);

      expect(result.exitCode, 0, reason: result.stderr);
      expect(result.stdout, contains('restage'));
    },
  );

  test('a command without a project option runs without one', () async {
    final result = await executor.runCommand(['help']);

    expect(result.exitCode, 0, reason: result.stderr);
    expect(result.stdout, contains('Available commands'));
  });

  test('publish asks the server for the newest pushed revision', () async {
    final family = {
      '__className__': 'SurfaceContractFamilyReference',
      'surfaceType': 'paywall',
      'surfaceSlug': 'pro',
      'sourceKind': 'paywall',
    };
    final publishing = ConsoleCommandExecutor(
      credentialStore: store,
      httpClient: mockHttpClient((request) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        calls.add(body);
        return switch (body['method']) {
          _ => http.Response(
            jsonEncode({
              '__className__': 'SurfaceContractFamilyOperationResult',
              'family': family,
              'publishedRevision': 3,
              'activePublishedRevisionAfter': 3,
              'identityFrozenAfter': false,
            }),
            200,
          ),
        };
      }),
      directory: dir,
    );

    final result = await publishing.publish(
      context: const ConsoleContext(
        organizationSlug: 'restage',
        project: 'default',
        appId: 5,
        app: 'mobile',
        environmentTargetId: 12,
        namedEnvironmentId: 22,
        environment: 'staging',
        runtimePlane: RuntimePlane.sandbox,
      ),
      surface: const ConsoleSurface(
        surfaceType: 'paywall',
        slug: 'pro',
        name: 'Pro',
      ),
      reason: 'ship new copy',
    );

    expect(result.exitCode, 0, reason: result.stderr);
    final activate = calls.singleWhere(
      (call) => call['method'] == 'activateSurface',
    );
    expect(activate['publishedRevision'], isNull);
    expect(activate['reason'], 'ship new copy');
    expect(activate['environmentTargetId'], 12);
    expect(
      calls.map((call) => call['method']),
      isNot(contains('surfaceStatus')),
    );
    expect(result.stdout, contains('Published "pro" at r3 in staging'));
  });
}
