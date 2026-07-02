import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/tui/console_command_executor.dart';
import 'package:restage_cli/src/tui/console_models.dart';
import 'package:test/test.dart';

import '../_helpers/test_fixtures.dart';

void main() {
  test(
    'kill routes through surface kill with reason and confirmation',
    () async {
      final dir = await Directory.systemTemp.createTemp('restage-console-');
      addTearDown(() => dir.delete(recursive: true));
      final store = FileCredentialStore(p.join(dir.path, 'credential.json'));
      await seedCredential(store);
      await seedRestageConfig(
        dir,
        'default',
        'default',
        defaultEnvironment: 'staging',
        organization: 'restage',
        endpoint: 'http://localhost:8080/',
      );

      final calls = <Map<String, dynamic>>[];
      final client = scriptedHttpClient([
        _okListOrgs,
        _okStatus,
        (request) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          calls.add(body);
          expect(body['method'], 'killSurface');
          expect(body['reason'], 'cleanup');
          return http.Response('{}', 200);
        },
      ]);

      final executor = ConsoleCommandExecutor(
        credentialStore: store,
        httpClient: client,
        directory: dir,
      );

      final result = await executor.kill(
        context: const ConsoleContext(
          organizationSlug: 'restage',
          project: 'default',
          app: 'default',
          environment: 'staging',
        ),
        surface: const ConsoleSurface(
          surfaceType: 'paywall',
          slug: 'pro',
          name: 'Pro',
        ),
        reason: 'cleanup',
        frozen: true,
      );

      expect(result.exitCode, 0);
      expect(calls.single['mode'], 'frozen');
    },
  );

  test(
    'production kill uses interactive confirmation instead of --yes',
    () async {
      final dir = await Directory.systemTemp.createTemp('restage-console-');
      addTearDown(() => dir.delete(recursive: true));
      final store = FileCredentialStore(p.join(dir.path, 'credential.json'));
      await seedCredential(store);
      await seedRestageConfig(
        dir,
        'default',
        'default',
        defaultEnvironment: 'production',
        organization: 'restage',
        endpoint: 'http://localhost:8080/',
      );

      final calls = <Map<String, dynamic>>[];
      final client = scriptedHttpClient([
        _okListOrgs,
        _okStatus,
        (request) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          calls.add(body);
          expect(body['method'], 'killSurface');
          return http.Response('{}', 200);
        },
      ]);

      final executor = ConsoleCommandExecutor(
        credentialStore: store,
        httpClient: client,
        directory: dir,
      );

      final result = await executor.kill(
        context: const ConsoleContext(
          organizationSlug: 'restage',
          project: 'default',
          app: 'default',
          environment: 'production',
        ),
        surface: const ConsoleSurface(
          surfaceType: 'paywall',
          slug: 'pro',
          name: 'Pro',
        ),
        reason: 'cleanup',
        frozen: false,
        confirmedProduction: true,
      );

      expect(result.exitCode, 0);
      expect(calls.single['mode'], 'transient');
    },
  );

  test(
    'production kill without UI confirmation fails before mutation',
    () async {
      final dir = await Directory.systemTemp.createTemp('restage-console-');
      addTearDown(() => dir.delete(recursive: true));
      final store = FileCredentialStore(p.join(dir.path, 'credential.json'));
      await seedCredential(store);
      await seedRestageConfig(
        dir,
        'default',
        'default',
        defaultEnvironment: 'production',
        organization: 'restage',
        endpoint: 'http://localhost:8080/',
      );

      final executor = ConsoleCommandExecutor(
        credentialStore: store,
        httpClient: scriptedHttpClient([_okListOrgs, _okStatus]),
        directory: dir,
      );

      final result = await executor.kill(
        context: const ConsoleContext(
          organizationSlug: 'restage',
          project: 'default',
          app: 'default',
          environment: 'production',
        ),
        surface: const ConsoleSurface(
          surfaceType: 'paywall',
          slug: 'pro',
          name: 'Pro',
        ),
        reason: 'cleanup',
        frozen: false,
      );

      expect(result.exitCode, 1);
      expect(result.stderr, contains('needs confirmation'));
    },
  );

  test(
    'rollback routes through surface rollback with reason and freeze flag',
    () async {
      final fixture = await _seedExecutorFixture(environment: 'staging');

      final calls = <Map<String, dynamic>>[];
      final client = scriptedHttpClient([
        _okListOrgs,
        _okStatus,
        (request) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['method'], 'rollbackPreflight');
          expect(body['toVersion'], 2);
          return _okRollbackPreflight();
        },
        (request) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          calls.add(body);
          expect(body['method'], 'rollbackSurface');
          expect(body['reason'], 'restore');
          expect(body['toVersion'], 2);
          expect(body['lockAfter'], true);
          return http.Response('{}', 200);
        },
      ]);

      final executor = ConsoleCommandExecutor(
        credentialStore: fixture.store,
        httpClient: client,
        directory: fixture.dir,
      );

      final result = await executor.rollback(
        context: _context('staging'),
        surface: _surface,
        reason: 'restore',
        toVersion: 2,
        freeze: true,
      );

      expect(result.exitCode, 0);
      expect(calls.single['surfaceType'], 'paywall');
    },
  );

  test('freeze and unfreeze route through surface lock commands', () async {
    final fixture = await _seedExecutorFixture(environment: 'staging');

    final lockCalls = <Map<String, dynamic>>[];
    final client = scriptedHttpClient([
      _okListOrgs,
      (request) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        lockCalls.add(body);
        expect(body['method'], 'setSurfaceLock');
        expect(body['locked'], true);
        expect(body['reason'], 'pause publishes');
        return http.Response('', 200);
      },
      _okListOrgs,
      (request) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        lockCalls.add(body);
        expect(body['method'], 'setSurfaceLock');
        expect(body['locked'], false);
        expect(body['reason'], 'resume publishes');
        return http.Response('', 200);
      },
    ]);

    final executor = ConsoleCommandExecutor(
      credentialStore: fixture.store,
      httpClient: client,
      directory: fixture.dir,
    );

    final freeze = await executor.freeze(
      context: _context('staging'),
      surface: _surface,
      reason: 'pause publishes',
    );
    final unfreeze = await executor.unfreeze(
      context: _context('staging'),
      surface: _surface,
      reason: 'resume publishes',
    );

    expect(freeze.exitCode, 0);
    expect(unfreeze.exitCode, 0);
    expect(lockCalls, hasLength(2));
  });

  test('publish routes through surface publish command core', () async {
    final fixture = await _seedExecutorFixture(environment: 'staging');
    await seedRfw(fixture.dir, 'pro', List<int>.generate(48, (index) => index));

    var saveCalls = 0;
    var publishCalls = 0;
    final client = scriptedHttpClient([
      _okListOrgs,
      (request) {
        saveCalls++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['method'], 'save');
        expect(body['surfaceType'], 'paywall');
        expect(body['surfaceSlug'], 'pro');
        return http.Response('null', 200);
      },
      (request) {
        publishCalls++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['method'], 'publish');
        expect(body['surfaceType'], 'paywall');
        expect(body['surfaceSlug'], 'pro');
        expect(body['environmentSlug'], 'staging');
        return http.Response('3', 200);
      },
    ]);

    final executor = ConsoleCommandExecutor(
      credentialStore: fixture.store,
      httpClient: client,
      directory: fixture.dir,
    );

    final result = await executor.publish(
      context: _context('staging'),
      surface: _surface,
    );

    expect(result.exitCode, 0);
    expect(saveCalls, 1);
    expect(publishCalls, 1);
  });
}

const _surface = ConsoleSurface(
  surfaceType: 'paywall',
  slug: 'pro',
  name: 'Pro',
);

ConsoleContext _context(String environment) => ConsoleContext(
  organizationSlug: 'restage',
  project: 'default',
  app: 'default',
  environment: environment,
);

Future<({Directory dir, FileCredentialStore store})> _seedExecutorFixture({
  required String environment,
}) async {
  final dir = await Directory.systemTemp.createTemp('restage-console-');
  addTearDown(() => dir.delete(recursive: true));
  final store = FileCredentialStore(p.join(dir.path, 'credential.json'));
  await seedCredential(store);
  await seedRestageConfig(
    dir,
    'default',
    'default',
    defaultEnvironment: environment,
    organization: 'restage',
    endpoint: 'http://localhost:8080/',
  );
  return (dir: dir, store: store);
}

http.Response _okListOrgs(http.Request request) {
  final body = jsonDecode(request.body) as Map<String, dynamic>;
  expect(body['method'], 'listMine');
  return http.Response(
    jsonEncode([
      {
        'organizationId': 7,
        'slug': 'restage',
        'name': 'Restage',
        'role': 'owner',
      },
    ]),
    200,
  );
}

http.Response _okStatus(http.Request request) {
  final body = jsonDecode(request.body) as Map<String, dynamic>;
  expect(body['method'], 'surfaceStatus');
  expect(body['organizationId'], 7);
  return http.Response(
    jsonEncode({
      '__className__': 'SurfaceStatusResult',
      'surfaceType': 'paywall',
      'surfaceSlug': 'pro',
      'environmentSlug': 'staging',
      'liveVersion': 2,
      'locked': false,
      'deliveryShape': 'blob',
      'versions': [
        {
          'version': 2,
          'publishedAt': '2026-06-01T00:00:00.000Z',
          'contentHash': 'sha-2',
          'isActive': true,
        },
        {
          'version': 1,
          'publishedAt': '2026-05-31T00:00:00.000Z',
          'contentHash': 'sha-1',
          'isActive': false,
        },
      ],
    }),
    200,
  );
}

http.Response _okRollbackPreflight() => http.Response(
  jsonEncode({
    '__className__': 'RollbackPreflightView',
    'surfaceType': 'paywall',
    'surfaceSlug': 'pro',
    'environmentSlug': 'staging',
    'toVersion': 2,
    'classification': 'compatible',
    'blockingChanges': <String>[],
  }),
  200,
);
