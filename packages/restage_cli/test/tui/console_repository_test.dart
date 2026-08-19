import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/tui/console_models.dart';
import 'package:restage_cli/src/tui/console_repository.dart';
import 'package:test/test.dart';

import '../_helpers/test_fixtures.dart';

void main() {
  late Directory tempDir;
  late FileCredentialStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('console_repository_');
    store = FileCredentialStore(p.join(tempDir.path, 'credentials'));
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('loads configured context, surfaces, and selected status', () async {
    await seedCredential(store);
    await seedRestageConfig(
      tempDir,
      'alpha',
      'mobile',
      defaultEnvironment: 'staging',
      organization: 'restage',
      endpoint: 'http://localhost:8080/',
    );

    Map<String, dynamic>? statusBody;
    final repo = DefaultConsoleRepository(
      credentialStore: store,
      directory: tempDir,
      httpClient: scriptedHttpClient([
        _listOrganizations,
        _listProjects,
        _listApps,
        _listEnvironments,
        _listEnvironmentTargets,
        _listPaywalls,
        _emptySurfaceList,
        _emptySurfaceList,
        _emptySurfaceList,
        _emptySurfaceList,
        (request) {
          statusBody = jsonDecode(request.body) as Map<String, dynamic>;
          expect(statusBody!['method'], 'surfaceStatus');
          expect(statusBody!['organizationId'], 7);
          expect(statusBody!['environmentTargetId'], 12);
          expect(statusBody!['runtimePlane'], 'live');
          return http.Response(
            jsonEncode({
              '__className__': 'SurfaceStatusResult',
              'surfaceType': 'paywall',
              'surfaceSlug': 'pro',
              'environmentSlug': 'staging',
              'liveVersion': 2,
              'locked': false,
              'deliveryShape': 'blob',
              'versions': <Map<String, dynamic>>[],
            }),
            200,
          );
        },
      ], withDefaultTargetDiscovery: false),
    );

    final snapshot = await repo.load();
    final status = await repo.status(
      snapshot.surfaces.single,
      context: snapshot.context,
    );

    expect(snapshot.context.organizationSlug, 'restage');
    expect(snapshot.context.project, 'alpha');
    expect(snapshot.context.appId, 5);
    expect(snapshot.context.app, 'mobile');
    expect(snapshot.context.environment, 'staging');
    expect(snapshot.context.environmentTargetId, 12);
    expect(snapshot.context.namedEnvironmentId, 22);
    expect(snapshot.context.runtimePlane, RuntimePlane.live);
    expect(
      snapshot.environments.map(
        (target) =>
            (target.environmentTargetId, target.slug, target.runtimePlane),
      ),
      [
        (11, 'dev', RuntimePlane.live),
        (12, 'staging', RuntimePlane.live),
        (31, 'prod', RuntimePlane.sandbox),
        (32, 'prod', RuntimePlane.live),
      ],
    );
    expect(snapshot.surfaces.single.slug, 'pro');
    expect(status.liveVersion, 2);
    expect(statusBody, isNotNull);
  });

  test(
    'loads server audit log and chain verdict for the selected org',
    () async {
      await seedCredential(store);
      await seedRestageConfig(
        tempDir,
        'alpha',
        'mobile',
        defaultEnvironment: 'staging',
        organization: 'restage',
        endpoint: 'http://localhost:8080/',
      );

      final repo = DefaultConsoleRepository(
        credentialStore: store,
        directory: tempDir,
        httpClient: scriptedHttpClient([
          _listOrganizations,
          _listProjects,
          _listApps,
          _listEnvironments,
          _listEnvironmentTargets,
          _listPaywalls,
          _emptySurfaceList,
          _emptySurfaceList,
          _emptySurfaceList,
          _emptySurfaceList,
          (request) {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['method'], 'surfaceChainVerdict');
            expect(body['organizationId'], 7);
            return http.Response(
              jsonEncode({
                '__className__': 'SurfaceChainVerdict',
                'status': 'verified',
                'verifiedThroughEntryId': 99,
                'lastRunAt': '2026-06-29T18:30:00.000Z',
              }),
              200,
            );
          },
          (request) {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['method'], 'listAuditLog');
            expect(body['organizationId'], 7);
            return http.Response(
              jsonEncode([
                {
                  '__className__': 'SurfaceAuditLogEntryView',
                  'action': 'surfacePublished',
                  'actorType': 'human',
                  'actorEmail': 'owner@example.com',
                  'outcome': 'success',
                  'severity': 'notice',
                  'occurredAt': '2026-06-29T18:17:51.000Z',
                  'context': {'surfaceSlug': 'pro'},
                  'chainState': 'chained',
                  'chainVerified': true,
                  'entryId': 99,
                },
              ]),
              200,
            );
          },
        ], withDefaultTargetDiscovery: false),
      );

      final snapshot = await repo.load();
      final verdict = await repo.surfaceChainVerdict(context: snapshot.context);
      final auditLog = await repo.auditLog(context: snapshot.context);

      expect(verdict.status, 'verified');
      expect(verdict.verifiedThroughEntryId, 99);
      expect(auditLog.single.action, 'surfacePublished');
      expect(auditLog.single.actorEmail, 'owner@example.com');
    },
  );

  test('rejects a config endpoint mismatch before any HTTP call', () async {
    await seedCredential(store, endpoint: 'http://localhost:8080/');
    await seedRestageConfig(
      tempDir,
      'alpha',
      'mobile',
      defaultEnvironment: 'staging',
      organization: 'restage',
      endpoint: 'https://example.invalid/',
    );

    final repo = DefaultConsoleRepository(
      credentialStore: store,
      directory: tempDir,
      httpClient: mockHttpClient(
        (_) => fail('HTTP should not be called'),
        withDefaultTargetDiscovery: false,
      ),
    );

    await expectLater(
      repo.load(),
      throwsA(
        isA<ConsoleLoadException>().having(
          (e) => e.message,
          'message',
          contains('stored credential belongs'),
        ),
      ),
    );
  });

  test('joins the old config default to the exact legacy target', () async {
    await seedCredential(store);
    await seedRestageConfig(
      tempDir,
      'alpha',
      'mobile',
      defaultEnvironment: 'prod',
      organization: 'restage',
      endpoint: 'http://localhost:8080/',
    );

    final repo = DefaultConsoleRepository(
      credentialStore: store,
      directory: tempDir,
      httpClient: scriptedHttpClient([
        _listOrganizations,
        _listProjects,
        _listApps,
        _listSameSlugLegacyEnvironments,
        _listSameSlugTargets,
        _listPaywalls,
        _emptySurfaceList,
        _emptySurfaceList,
        _emptySurfaceList,
        _emptySurfaceList,
      ], withDefaultTargetDiscovery: false),
    );

    final snapshot = await repo.load();

    expect(snapshot.context.environment, 'prod');
    expect(snapshot.context.environmentTargetId, 31);
    expect(snapshot.context.runtimePlane, RuntimePlane.sandbox);
    expect(snapshot.environments.map((target) => target.environmentTargetId), [
      31,
      32,
    ]);
    expect(snapshot.environments.map((target) => target.runtimePlane), [
      RuntimePlane.sandbox,
      RuntimePlane.live,
    ]);
  });
}

http.Response _listOrganizations(http.Request request) {
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
      {'organizationId': 8, 'slug': 'other', 'name': 'Other', 'role': 'owner'},
    ]),
    200,
  );
}

http.Response _listProjects(http.Request request) {
  final body = jsonDecode(request.body) as Map<String, dynamic>;
  expect(body['method'], 'listProjects');
  expect(body['organizationId'], 7);
  return http.Response(
    jsonEncode([
      {'slug': 'alpha', 'name': 'Alpha'},
    ]),
    200,
  );
}

http.Response _listApps(http.Request request) {
  final body = jsonDecode(request.body) as Map<String, dynamic>;
  expect(body['method'], 'listApps');
  expect(body['organizationId'], 7);
  expect(body['projectSlug'], 'alpha');
  return http.Response(
    jsonEncode([
      {'id': 5, 'slug': 'mobile', 'name': 'Mobile'},
    ]),
    200,
  );
}

http.Response _listEnvironments(http.Request request) {
  final body = jsonDecode(request.body) as Map<String, dynamic>;
  expect(body['method'], 'listEnvironments');
  expect(body['organizationId'], 7);
  expect(body['projectSlug'], 'alpha');
  return http.Response(
    jsonEncode([
      {'id': 12, 'appId': 5, 'slug': 'staging'},
    ]),
    200,
  );
}

http.Response _listEnvironmentTargets(http.Request request) {
  final body = jsonDecode(request.body) as Map<String, dynamic>;
  expect(body['method'], 'listEnvironmentTargets');
  expect(body['organizationId'], 7);
  expect(body['projectSlug'], 'alpha');
  expect(body['appSlug'], 'mobile');
  expect(body['appId'], 5);
  return http.Response(
    jsonEncode([
      {
        'environmentTargetId': 11,
        'namedEnvironmentId': 21,
        'environmentSlug': 'dev',
        'runtimePlane': 'live',
      },
      {
        'environmentTargetId': 12,
        'namedEnvironmentId': 22,
        'environmentSlug': 'staging',
        'runtimePlane': 'live',
      },
      {
        'environmentTargetId': 31,
        'namedEnvironmentId': 41,
        'environmentSlug': 'prod',
        'runtimePlane': 'sandbox',
      },
      {
        'environmentTargetId': 32,
        'namedEnvironmentId': 41,
        'environmentSlug': 'prod',
        'runtimePlane': 'live',
      },
    ]),
    200,
  );
}

http.Response _listSameSlugLegacyEnvironments(http.Request request) {
  final body = jsonDecode(request.body) as Map<String, dynamic>;
  expect(body['method'], 'listEnvironments');
  return http.Response(
    jsonEncode([
      {'id': 31, 'appId': 5, 'slug': 'prod'},
    ]),
    200,
  );
}

http.Response _listSameSlugTargets(http.Request request) {
  final body = jsonDecode(request.body) as Map<String, dynamic>;
  expect(body['method'], 'listEnvironmentTargets');
  expect(body['appId'], 5);
  return http.Response(
    jsonEncode([
      {
        'environmentTargetId': 31,
        'namedEnvironmentId': 41,
        'environmentSlug': 'prod',
        'runtimePlane': 'sandbox',
      },
      {
        'environmentTargetId': 32,
        'namedEnvironmentId': 41,
        'environmentSlug': 'prod',
        'runtimePlane': 'live',
      },
    ]),
    200,
  );
}

http.Response _listPaywalls(http.Request request) {
  final body = jsonDecode(request.body) as Map<String, dynamic>;
  expect(body['method'], 'list');
  expect(body['surfaceType'], 'paywall');
  expect(body['organizationId'], 7);
  expect(body['appId'], 5);
  return http.Response(
    jsonEncode([
      {
        '__className__': 'SurfaceSummary',
        'surfaceType': 'paywall',
        'slug': 'pro',
        'name': 'Pro',
        'draftUpdatedAt': '2026-06-01T00:00:00.000Z',
        'publishedVersionByEnvironment': {'staging': 2},
      },
    ]),
    200,
  );
}

http.Response _emptySurfaceList(http.Request request) {
  final body = jsonDecode(request.body) as Map<String, dynamic>;
  expect(body['method'], 'list');
  expect(
    body['surfaceType'],
    isIn(['onboarding', 'message', 'survey', 'general']),
  );
  expect(body['organizationId'], 7);
  expect(body['appId'], 5);
  return http.Response(jsonEncode(<Map<String, dynamic>>[]), 200);
}
