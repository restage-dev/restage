import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/api/surface_publication_api.dart';
import 'package:restage_cli/src/cli.dart';
import 'package:restage_cli/src/commands/lifecycle_support.dart'
    show kCohortImpactNotePrefix;
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/tui/console_command_executor.dart';
import 'package:restage_cli/src/tui/console_models.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../_helpers/publication_fixtures.dart';
import '../_helpers/test_fixtures.dart';

void main() {
  for (final selection in [
    (flags: <String>[], environment: 'dev', targetId: 11, plane: 'sandbox'),
    (
      flags: ['--env', 'staging'],
      environment: 'staging',
      targetId: 12,
      plane: 'sandbox',
    ),
    (
      flags: ['--env=production', '--plane=live'],
      environment: 'production',
      targetId: 13,
      plane: 'live',
    ),
  ]) {
    test('command inherits target with overrides ${selection.flags}', () async {
      final fixture = await _seedExecutorFixture(environment: 'production');
      Map<String, dynamic>? request;
      final executor = ConsoleCommandExecutor(
        credentialStore: fixture.store,
        directory: fixture.dir,
        httpClient: scriptedHttpClient([
          (incoming) {
            request = jsonDecode(incoming.body) as Map<String, dynamic>;
            return _okStatus(incoming);
          },
        ]),
      );
      final arguments = ['paywall', 'status', 'pro', ...selection.flags];
      final result = await executor.runCommand(
        arguments,
        context: _context('dev').copyWith(project: 'alpha', app: 'mobile'),
      );

      expect(result.exitCode, 0, reason: result.stderr);
      expect(request?['projectSlug'], 'alpha');
      expect(request?['appSlug'], 'mobile');
      expect(request?['environmentTargetId'], selection.targetId);
      expect(request?['runtimePlane'], selection.plane);
      expect(result.targetDescription, contains('--project=alpha'));
      expect(result.targetDescription, contains('--app=mobile'));
      expect(
        result.targetDescription,
        contains('--env=${selection.environment}'),
      );
      expect(result.targetDescription, contains('--plane=${selection.plane}'));
      expect(
        ConsoleCommandOutput(arguments: arguments, result: result).lines.first,
        'Target: ${result.targetDescription}',
      );
    });
  }

  test('command inherits the selected plane for a same-named target', () async {
    final fixture = await _seedExecutorFixture(environment: 'staging');
    Map<String, dynamic>? request;
    final executor = ConsoleCommandExecutor(
      credentialStore: fixture.store,
      directory: fixture.dir,
      httpClient: scriptedHttpClient([
        _target('staging', 42, RuntimePlane.live),
        (incoming) {
          request = jsonDecode(incoming.body) as Map<String, dynamic>;
          return _okStatus(incoming);
        },
      ], withDefaultTargetDiscovery: false),
    );

    final result = await executor.runCommand(
      ['paywall', 'status', 'pro'],
      context: _context(
        'staging',
        environmentTargetId: 42,
        namedEnvironmentId: 142,
        runtimePlane: RuntimePlane.live,
      ),
    );

    expect(result.exitCode, 0, reason: result.stderr);
    expect(request?['environmentTargetId'], 42);
    expect(request?['runtimePlane'], 'live');
  });

  test('explicit project and app replace only those selectors', () async {
    final fixture = await _seedExecutorFixture(environment: 'production');
    Map<String, dynamic>? request;
    final executor = ConsoleCommandExecutor(
      credentialStore: fixture.store,
      directory: fixture.dir,
      httpClient: scriptedHttpClient([
        (incoming) {
          request = jsonDecode(incoming.body) as Map<String, dynamic>;
          return _okStatus(incoming);
        },
      ]),
    );

    final result = await executor.runCommand([
      'paywall',
      'status',
      '--project=other',
      '--app=a',
      '--',
      'pro',
    ], context: _context('staging'));

    expect(result.exitCode, 0, reason: result.stderr);
    expect(request?['projectSlug'], 'other');
    expect(request?['appSlug'], 'a');
    expect(request?['environmentTargetId'], 12);
    expect(request?['runtimePlane'], 'sandbox');
    expect(result.targetDescription, contains('--project=other'));
    expect(result.targetDescription, contains('--app=a'));
  });

  test(
    'an environment override keeps the selected plane and refuses mismatch',
    () async {
      final fixture = await _seedExecutorFixture(environment: 'production');
      final executor = ConsoleCommandExecutor(
        credentialStore: fixture.store,
        directory: fixture.dir,
        httpClient: scriptedHttpClient([]),
      );

      final result = await executor.runCommand([
        'paywall',
        'status',
        'pro',
        '--env=production',
      ], context: _context('staging'));

      expect(result.exitCode, 1);
      expect(result.stderr, contains('No environment target matches'));
      expect(result.targetDescription, contains('--env=production'));
      expect(result.targetDescription, contains('--plane=sandbox'));
    },
  );

  test('app-scoped commands inherit only their supported selectors', () async {
    final fixture = await _seedExecutorFixture(environment: 'production');
    final executor = ConsoleCommandExecutor(
      credentialStore: fixture.store,
      directory: fixture.dir,
      httpClient: scriptedHttpClient([
        scopeTargetStep({
          'environmentTargetId': 42,
          'namedEnvironmentId': 142,
          'environmentSlug': 'staging',
          'runtimePlane': 'sandbox',
        }, organizationSlug: 'selected-org'),
      ], withDefaultTargetDiscovery: false),
    );

    final result = await executor.runCommand(
      ['targets', '--json'],
      context: _context('staging').copyWith(
        organizationSlug: 'selected-org',
        project: 'alpha',
        app: 'mobile',
      ),
    );

    expect(result.exitCode, 0, reason: result.stderr);
    expect(result.stdout, contains('42'));
    expect(result.targetDescription, contains('--organization=selected-org'));
    expect(result.targetDescription, contains('--project=alpha'));
    expect(result.targetDescription, contains('--app=mobile'));
    expect(result.targetDescription, isNot(contains('--env=')));
  });

  test(
    'an explicit organization overrides the selected organization',
    () async {
      final fixture = await _seedExecutorFixture(environment: 'production');
      final executor = ConsoleCommandExecutor(
        credentialStore: fixture.store,
        directory: fixture.dir,
        httpClient: scriptedHttpClient([
          scopeTargetStep({
            'environmentTargetId': 12,
            'namedEnvironmentId': 22,
            'environmentSlug': 'staging',
            'runtimePlane': 'sandbox',
          }, organizationSlug: 'other-org'),
          _okStatus,
        ], withDefaultTargetDiscovery: false),
      );

      final result = await executor.runCommand([
        'paywall',
        'status',
        'pro',
        '--organization=other-org',
      ], context: _context('staging'));

      expect(result.exitCode, 0, reason: result.stderr);
      expect(result.targetDescription, contains('--organization=other-org'));
      expect(
        result.targetDescription,
        isNot(contains('--organization=restage')),
      );
    },
  );

  test(
    'an explicit personal build head suppresses the inherited environment',
    () async {
      final fixture = await _seedExecutorFixture(environment: 'production');
      final executor = ConsoleCommandExecutor(
        credentialStore: FileCredentialStore(
          p.join(fixture.dir.path, 'unsigned-credential.json'),
        ),
        directory: fixture.dir,
        httpClient: scriptedHttpClient([]),
      );

      final result = await executor.runCommand([
        'build',
        'push',
        '--personal',
      ], context: _context('staging'));

      expect(result.exitCode, 1);
      expect(result.stderr, contains('Not signed in'));
      expect(result.stderr, isNot(contains('Name one target')));
      expect(result.targetDescription, contains('--app=default'));
      expect(result.targetDescription, isNot(contains('--env=')));
      expect(result.targetDescription, isNot(contains('--plane=')));
    },
  );

  for (final explicitSlug in [false, true]) {
    test('organization ID overrides defaults and checks explicit slug: '
        '$explicitSlug', () async {
      final fixture = await _seedExecutorFixture(environment: 'staging');
      File(p.join(fixture.dir.path, 'restage_config.yaml')).writeAsStringSync(
        'organizationId: 99\nappId: 98\nenvironmentTargetId: 97\n'
        'namedEnvironmentId: 96\n',
        mode: FileMode.append,
      );
      final arguments = [
        'paywall',
        'status',
        'pro',
        '--organization-id=7',
        if (explicitSlug) '--organization=restage',
      ];
      http.Client client() => scriptedHttpClient([
        scopeTargetStep(
          {
            'environmentTargetId': 12,
            'namedEnvironmentId': 22,
            'environmentSlug': 'staging',
            'runtimePlane': 'sandbox',
          },
          organizationSlug: 'other-org',
          inspect: (request) => expect(request['organizationId'], 7),
        ),
        if (!explicitSlug) _okStatus,
      ], withDefaultTargetDiscovery: false);
      final executor = ConsoleCommandExecutor(
        credentialStore: fixture.store,
        directory: fixture.dir,
        httpClient: client(),
      );

      final result = await executor.runCommand(
        arguments,
        context: _context('staging'),
      );
      final stderr = StringBuffer();
      final cliCode =
          await RestageCli(
            credentialStore: fixture.store,
            httpClient: client(),
            stderr: stderr,
          ).run([
            '--non-interactive',
            ...arguments,
            '--directory=${fixture.dir.path}',
            '--env=staging',
          ]);

      expect(result.exitCode, explicitSlug ? 1 : 0, reason: result.stderr);
      expect(cliCode, result.exitCode, reason: stderr.toString());
      expect(result.stderr, stderr.toString());
      expect(result.targetDescription, contains('--organization-id=7'));
      if (explicitSlug) {
        expect(result.stderr, contains('No organization matches'));
      } else {
        expect(result.targetDescription, isNot(contains('--organization=')));
      }
    });
  }

  for (final command in [
    ['analytics', 'overview'],
    ['surface', 'push', 'pro'],
    ['build', 'push'],
    ['catalog', 'push'],
  ]) {
    test(
      'malformed organization ID refuses before requests: $command',
      () async {
        final fixture = await _seedExecutorFixture(environment: 'staging');
        for (final value in ['abc', '0', '-7']) {
          final client = scriptedHttpClient(
            [],
            withDefaultTargetDiscovery: false,
          );
          final executor = ConsoleCommandExecutor(
            credentialStore: fixture.store,
            directory: fixture.dir,
            httpClient: client,
          );
          final arguments = [...command, '--organization-id=$value'];
          final result = await executor.runCommand(
            arguments,
            context: _context('staging'),
          );
          final stderr = StringBuffer();
          final code = await RestageCli(
            credentialStore: fixture.store,
            httpClient: client,
            stderr: stderr,
          ).run(['--directory=${fixture.dir.path}', ...arguments]);

          expect(result.exitCode, 1);
          expect(code, 1);
          expect(
            result.stderr,
            contains('--organization-id must be a positive integer'),
          );
          expect(result.stderr, stderr.toString());
          expect(result.targetDescription, isNull);
          expect(result.stdout, isEmpty);
        }
      },
    );
  }

  for (final arguments in [
    ['help'],
    ['orgs'],
    ['analytics', 'overview', '--help'],
  ]) {
    test('non-target command or help works with context: $arguments', () async {
      final fixture = await _seedExecutorFixture(environment: 'production');
      final executor = ConsoleCommandExecutor(
        credentialStore: fixture.store,
        directory: fixture.dir,
        httpClient: scriptedHttpClient([]),
      );

      final result = await executor.runCommand(
        arguments,
        context: _context('staging'),
      );

      expect(result.exitCode, 0, reason: result.stderr);
      expect(result.stdout, isNotEmpty);
      if (!arguments.contains('analytics')) {
        expect(result.targetDescription, isNull);
      }
    });
  }

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
        _okStatus,
        (request) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          calls.add(body);
          expect(body['method'], 'killSurface');
          expect(body['environmentTargetId'], 12);
          expect(body['runtimePlane'], 'sandbox');
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
          appId: 5,
          app: 'default',
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
          appId: 5,
          app: 'default',
          environmentTargetId: 13,
          namedEnvironmentId: 23,
          environment: 'production',
          runtimePlane: RuntimePlane.live,
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
        httpClient: scriptedHttpClient([_okStatus]),
        directory: dir,
      );

      final result = await executor.kill(
        context: const ConsoleContext(
          organizationSlug: 'restage',
          project: 'default',
          appId: 5,
          app: 'default',
          environmentTargetId: 13,
          namedEnvironmentId: 23,
          environment: 'production',
          runtimePlane: RuntimePlane.live,
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

  test('rollbackPreview drives the real rollback --preview: no reason needed, '
      'no mutation, and the cohort-impact line survives extraction', () async {
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

    var mutated = false;
    final client = scriptedHttpClient([
      _okStatus,
      (request) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['method'] == 'rollbackSurface') mutated = true;
        expect(body['method'], 'rollbackPreflight');
        return _okRollbackPreflight();
      },
    ]);

    final executor = ConsoleCommandExecutor(
      credentialStore: store,
      httpClient: client,
      directory: dir,
    );

    final result = await executor.rollbackPreview(
      context: const ConsoleContext(
        organizationSlug: 'restage',
        project: 'default',
        appId: 5,
        app: 'default',
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
      toVersion: 2,
    );

    expect(result.exitCode, 0);
    expect(mutated, isFalse);
    // Pins the REAL command's output shape against the console's
    // extraction: the note line must start with the shared prefix.
    final noteLines = result.stdout
        .trim()
        .split('\n')
        .where((line) => line.startsWith(kCohortImpactNotePrefix));
    expect(noteLines, isNotEmpty);
  });

  test('freeze and unfreeze route through surface lock commands', () async {
    final fixture = await _seedExecutorFixture(environment: 'staging');

    final lockCalls = <Map<String, dynamic>>[];
    final client = scriptedHttpClient([
      (request) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        lockCalls.add(body);
        expect(body['method'], 'setSurfaceLock');
        expect(body['environmentTargetId'], 12);
        expect(body['runtimePlane'], 'sandbox');
        expect(body['locked'], true);
        expect(body['reason'], 'pause publishes');
        return http.Response('', 200);
      },
      (request) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        lockCalls.add(body);
        expect(body['method'], 'setSurfaceLock');
        expect(body['environmentTargetId'], 12);
        expect(body['runtimePlane'], 'sandbox');
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

  test('push routes through surface push command core', () async {
    final fixture = await _seedExecutorFixture(environment: 'staging');
    final entry = await seedGeneratedPaywall(fixture.dir, slug: 'pro');

    var pushCalls = 0;
    final client = scriptedHttpClient([
      (request) {
        pushCalls++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['method'], surfacePublicationUploadMethod);
        expect(body['environmentSlug'], 'staging');
        expect(body['environmentTargetId'], 12);
        expect(body['runtimePlane'], 'sandbox');
        final wireUpload = body['upload'] as Map<String, dynamic>;
        final upload = SurfacePublicationUploadRequestV1Codec.decodeJson(
          wireUpload['canonicalJson'] as String,
        );
        expect(upload.publication.surface, entry.publication.surface);
        expect(upload.publication.slug, entry.publication.slug);
        expect(upload.publication.sourceKind, entry.publication.sourceKind);
        expect(upload.publication.payloadKind, entry.publication.payloadKind);
        return http.Response(
          jsonEncode({
            'family': {
              '__className__': 'SurfaceContractFamilyReference',
              'surfaceType': entry.publication.surface.wireName,
              'surfaceSlug': entry.publication.slug,
              'sourceKind': entry.publication.sourceKind.wireName,
            },
            'storedPublishedRevision': 3,
            'activePublishedRevision': 3,
            'identityFrozen': false,
          }),
          200,
        );
      },
    ]);

    final executor = ConsoleCommandExecutor(
      credentialStore: fixture.store,
      httpClient: client,
      directory: fixture.dir,
    );

    final result = await executor.push(
      context: _context('staging'),
      surface: _surface,
    );

    expect(result.exitCode, 0);
    expect(pushCalls, 1);
  });

  for (final environment in const ['dev', 'staging']) {
    test('live $environment kill forwards the exact live target', () async {
      final fixture = await _seedExecutorFixture(environment: environment);
      final targetId = environment == 'dev' ? 41 : 42;
      Map<String, dynamic>? mutation;
      final client = scriptedHttpClient([
        _target(environment, targetId, RuntimePlane.live),
        _okStatus,
        (request) {
          mutation = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{}', 200);
        },
      ], withDefaultTargetDiscovery: false);
      final executor = ConsoleCommandExecutor(
        credentialStore: fixture.store,
        httpClient: client,
        directory: fixture.dir,
      );

      final result = await executor.kill(
        context: _context(
          environment,
          environmentTargetId: targetId,
          namedEnvironmentId: targetId + 100,
          runtimePlane: RuntimePlane.live,
        ),
        surface: _surface,
        reason: 'cleanup',
        frozen: false,
        confirmedProduction: true,
      );

      expect(result.exitCode, 0);
      expect(mutation?['method'], 'killSurface');
      expect(mutation?['environmentTargetId'], targetId);
      expect(mutation?['runtimePlane'], 'live');
    });
  }

  test('a live freeze runs only once the operator confirmed', () async {
    final fixture = await _seedExecutorFixture(environment: 'staging');
    final mutations = <Map<String, dynamic>>[];
    final client = scriptedHttpClient([
      _target('staging', 42, RuntimePlane.live),
      _target('staging', 42, RuntimePlane.live),
      (request) {
        mutations.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response('', 200);
      },
    ], withDefaultTargetDiscovery: false);
    final executor = ConsoleCommandExecutor(
      credentialStore: fixture.store,
      httpClient: client,
      directory: fixture.dir,
    );
    final context = _context(
      'staging',
      environmentTargetId: 42,
      namedEnvironmentId: 142,
      runtimePlane: RuntimePlane.live,
    );

    final refused = await executor.freeze(
      context: context,
      surface: _surface,
      reason: 'hold releases',
    );
    expect(refused.exitCode, 1);
    expect(refused.stderr, contains('changes what the live plane serves'));
    expect(mutations, isEmpty);

    final confirmed = await executor.freeze(
      context: context,
      surface: _surface,
      reason: 'hold releases',
      confirmedProduction: true,
    );
    expect(confirmed.exitCode, 0, reason: confirmed.stderr);
    expect(mutations.single['method'], 'setSurfaceLock');
    expect(mutations.single['runtimePlane'], 'live');
  });

  test('sandbox prod kill bypasses only on the sandbox plane', () async {
    final fixture = await _seedExecutorFixture(environment: 'prod');
    Map<String, dynamic>? mutation;
    final client = scriptedHttpClient([
      _target('prod', 31, RuntimePlane.sandbox),
      _okStatus,
      (request) {
        mutation = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{}', 200);
      },
    ], withDefaultTargetDiscovery: false);
    final executor = ConsoleCommandExecutor(
      credentialStore: fixture.store,
      httpClient: client,
      directory: fixture.dir,
    );

    final result = await executor.kill(
      context: _context(
        'prod',
        environmentTargetId: 31,
        namedEnvironmentId: 131,
        runtimePlane: RuntimePlane.sandbox,
      ),
      surface: _surface,
      reason: 'cleanup',
      frozen: false,
    );

    expect(result.exitCode, 0);
    expect(mutation?['method'], 'killSurface');
    expect(mutation?['environmentTargetId'], 31);
    expect(mutation?['runtimePlane'], 'sandbox');
  });
}

const _surface = ConsoleSurface(
  surfaceType: 'paywall',
  slug: 'pro',
  name: 'Pro',
);

ConsoleContext _context(
  String environment, {
  int environmentTargetId = 12,
  int namedEnvironmentId = 22,
  RuntimePlane runtimePlane = RuntimePlane.sandbox,
}) => ConsoleContext(
  organizationSlug: 'restage',
  project: 'default',
  appId: 5,
  app: 'default',
  environmentTargetId: environmentTargetId,
  namedEnvironmentId: namedEnvironmentId,
  environment: environment,
  runtimePlane: runtimePlane,
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

ScriptStep _target(
  String environment,
  int environmentTargetId,
  RuntimePlane runtimePlane,
) => scopeTargetStep(
  {
    'environmentTargetId': environmentTargetId,
    'namedEnvironmentId': environmentTargetId + 100,
    'environmentSlug': environment,
    'runtimePlane': runtimePlane.wireName,
  },
  appId: 5,
  inspect: (body) => expect(body['method'], 'read'),
);

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
