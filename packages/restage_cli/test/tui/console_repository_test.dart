import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
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
        _listPaywalls,
        _emptySurfaceList,
        _emptySurfaceList,
        _emptySurfaceList,
        (request) {
          statusBody = jsonDecode(request.body) as Map<String, dynamic>;
          expect(statusBody!['method'], 'surfaceStatus');
          expect(statusBody!['organizationId'], 7);
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
      ]),
    );

    final snapshot = await repo.load();
    final status = await repo.status(
      snapshot.surfaces.single,
      context: snapshot.context,
    );

    expect(snapshot.context.organizationSlug, 'restage');
    expect(snapshot.context.project, 'alpha');
    expect(snapshot.context.app, 'mobile');
    expect(snapshot.context.environment, 'staging');
    expect(snapshot.environments.map((e) => e.slug), ['production', 'staging']);
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
          _listPaywalls,
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
        ]),
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
      httpClient: mockHttpClient((_) => fail('HTTP should not be called')),
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
      {'slug': 'mobile', 'name': 'Mobile'},
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
      {'slug': 'production'},
      {'slug': 'staging'},
    ]),
    200,
  );
}

http.Response _listPaywalls(http.Request request) {
  final body = jsonDecode(request.body) as Map<String, dynamic>;
  expect(body['method'], 'list');
  expect(body['surfaceType'], 'paywall');
  expect(body['organizationId'], 7);
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
  expect(body['surfaceType'], isIn(['onboarding', 'message', 'survey']));
  expect(body['organizationId'], 7);
  return http.Response(jsonEncode(<Map<String, dynamic>>[]), 200);
}
