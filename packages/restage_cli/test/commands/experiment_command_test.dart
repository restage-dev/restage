import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/src/cli.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:test/test.dart';

import '../_helpers/experiment_fixtures.dart';
import '../_helpers/test_fixtures.dart';

/// The sixteen subcommands, paired with the operation each one invokes.
const _routes = <String, String>{
  'discover': 'discoverTargetsAndCapabilities',
  'create': 'openDraft',
  'read-draft': 'readDraft',
  'resolve-draft': 'resolveDraft',
  'save': 'replaceDraft',
  'copy': 'copyDraftToTarget',
  'validate': 'validateDraft',
  'review': 'reviewDraft',
  'activate': 'activateDraft',
  'pause': 'pauseExperiment',
  'resume': 'resumeExperiment',
  'conclude': 'concludeExperiment',
  'list': 'listExperiments',
  'read': 'readExperiment',
  'results': 'readExperimentResults',
  'archive': 'setExperimentArchived',
};

/// The selectors each subcommand needs beyond the shared target flags.
const _selectors = <String, List<String>>{
  'discover': [],
  'create': [],
  'read-draft': _draftBinding,
  'resolve-draft': ['--draft-id=draft'],
  'save': _draftBinding,
  'copy': [
    '--source-draft-id=draft',
    '--source-draft-revision-id=draft.v1',
    '--source-expected-cas=cas-1',
    '--source-organization-id=11',
    '--source-app-id=23',
    '--source-environment-target-id=41',
    '--source-named-environment-id=43',
    '--source-plane=sandbox',
  ],
  'validate': _draftBinding,
  'review': _draftBinding,
  'activate': [
    ..._draftBinding,
    '--review-id=review.checkout.v1',
    '--review-digest=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  ],
  'pause': _lifecycleSelectors,
  'resume': _lifecycleSelectors,
  'conclude': _lifecycleSelectors,
  'list': [],
  'read': ['--experiment-id=experiment.checkout'],
  'results': [
    '--experiment-id=experiment.checkout',
    '--activation-ordinal=7',
    '--result-digest=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  ],
  'archive': [
    '--experiment-id=experiment.checkout',
    '--expected-control-plane-ordinal=8',
  ],
};

const _draftBinding = [
  '--draft-id=experiment-draft-checkout',
  '--draft-revision-id=experiment-draft-checkout.v3',
  '--expected-cas=draft-cas-3',
];

const _lifecycleSelectors = [
  '--experiment-id=experiment.checkout',
  '--expected-lifecycle-ordinal=8',
];

void main() {
  late Directory home;
  late Directory project;
  late FileCredentialStore store;

  setUp(() async {
    home = Directory.systemTemp.createTempSync('restage_experiment_home');
    project = Directory.systemTemp.createTempSync('restage_experiment_project');
    store = FileCredentialStore('${home.path}/.config/restage/credentials');
    await seedCredential(store, endpoint: 'http://localhost:8080/');
    await seedRestageConfig(
      project,
      'checkout',
      'app',
      defaultEnvironment: 'production',
      organization: 'restage',
    );
  });

  tearDown(() {
    home.deleteSync(recursive: true);
    project.deleteSync(recursive: true);
  });

  /// Writes the complete draft choices `save` replaces a draft with.
  String replacementPath() {
    final file = File('${project.path}/replacement.json')
      ..writeAsStringSync(jsonEncode(emptyDraftChoices));
    return file.path;
  }

  /// Runs `restage experiment <arguments>` against a fake backend.
  Future<({int code, String out, String err, List<String> methods})> run(
    List<String> arguments, {
    Uint8ListReply? reply,
  }) async {
    final methods = <String>[];
    final stdout = StringBuffer();
    final stderr = StringBuffer();
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, Object?>;
      final method = body['method']! as String;
      final directory = targetDirectoryResponse(method);
      if (directory != null) return directory;
      methods.add(method);
      final sent = ExperimentAuthoringRequestV1.fromCanonicalBytes(
        byteDataBytes(body['requestBytes']! as String),
      );
      return http.Response(
        jsonEncode(
          byteDataWire(
            reply?.call(method, sent) ??
                refusalFor(
                  method,
                  ExperimentAuthoringRefusalCodeV1.capabilityUnavailable,
                  correlationId: sent.correlationId,
                ),
          ),
        ),
        200,
      );
    });
    final code =
        await RestageCli(
          stdout: stdout,
          stderr: stderr,
          credentialStore: store,
          httpClient: client,
          environment: const {'RESTAGE_EXPERIMENTAL': '1'},
        ).run([
          '--non-interactive',
          '--yes',
          'experiment',
          ...arguments,
          '--directory=${project.path}',
        ]);
    return (
      code: code,
      out: stdout.toString(),
      err: stderr.toString(),
      methods: methods,
    );
  }

  group('routing', () {
    test('each subcommand invokes exactly its own operation', () async {
      for (final entry in _routes.entries) {
        final result = await run([
          entry.key,
          ..._selectors[entry.key]!,
          if (entry.key == 'save') '--replacement=${replacementPath()}',
        ]);
        expect(
          result.methods,
          isNotEmpty,
          reason: '${entry.key} reached no route',
        );
        expect(result.methods.toSet(), {
          entry.value,
        }, reason: '${entry.key} must invoke only ${entry.value}');
      }
    });

    test('the sixteen subcommands cover the sixteen operations', () {
      expect(_routes, hasLength(16));
      expect(
        _routes.values.toSet(),
        ExperimentAuthoringOperationV1.values.map((e) => e.wireName).toSet(),
      );
    });

    test('draft, experiment, and results reads stay separate routes', () async {
      final resolved = await run([
        'resolve-draft',
        ..._selectors['resolve-draft']!,
      ]);
      expect(resolved.methods, ['resolveDraft']);
      final draft = await run(['read-draft', ..._selectors['read-draft']!]);
      final experiment = await run(['read', ..._selectors['read']!]);
      final results = await run(['results', ..._selectors['results']!]);

      expect(draft.methods, ['readDraft']);
      expect(experiment.methods, ['readExperiment']);
      expect(results.methods, ['readExperimentResults']);
    });

    test('help lists exactly the sixteen subcommands', () async {
      final stdout = StringBuffer();
      final stderr = StringBuffer();
      await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        environment: const {'RESTAGE_EXPERIMENTAL': '1'},
      ).run(const ['experiment', '--help']);

      expect(
        _subcommandsInHelp(stdout.toString()),
        _routes.keys.toList()..sort(),
      );
    });
  });

  group('results', () {
    test(
      'forwards the capability refusal from the route rather than stubbing it',
      () async {
        final result = await run(['results', ..._selectors['results']!]);

        expect(result.methods, ['readExperimentResults']);
        expect(result.code, 1);
        expect(result.err, contains('capabilityUnavailable'));
      },
    );

    test('prints the exact semantic refusal with --json', () async {
      final result = await run([
        'results',
        ..._selectors['results']!,
        '--json',
      ]);

      final decoded = jsonDecode(result.out.trim()) as Map<String, Object?>;
      expect(decoded['kind'], 'refused');
      expect(decoded['operation'], 'readExperimentResults');
      expect(
        (decoded['refusal']! as Map<String, Object?>)['code'],
        'capabilityUnavailable',
      );
    });
  });

  group('semantic payloads', () {
    test(
      'retains complete canonical write identity across independent retries',
      () async {
        final requests = <List<int>>[];
        List<int>? retainedRequest;
        final client = MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          final method = body['method']! as String;
          final directory = targetDirectoryResponse(method);
          if (directory != null) return directory;
          final bytes = byteDataBytes(body['requestBytes']! as String);
          requests.add(bytes);
          final sent = ExperimentAuthoringRequestV1.fromCanonicalBytes(bytes);
          final rebound =
              retainedRequest != null &&
              sent.idempotencyKey == 'operator-retry-key' &&
              base64Encode(retainedRequest!) != base64Encode(bytes);
          retainedRequest ??= bytes;
          return http.Response(
            jsonEncode(
              byteDataWire(
                refusalFor(
                  method,
                  rebound
                      ? ExperimentAuthoringRefusalCodeV1.replayRebinding
                      : ExperimentAuthoringRefusalCodeV1.capabilityUnavailable,
                  correlationId: sent.correlationId,
                ),
              ),
            ),
            200,
          );
        });

        Future<({int code, String err})> invoke({
          required String idempotencyKey,
          required int lifecycleOrdinal,
        }) async {
          final stderr = StringBuffer();
          final code =
              await RestageCli(
                stdout: StringBuffer(),
                stderr: stderr,
                credentialStore: store,
                httpClient: client,
                environment: const {'RESTAGE_EXPERIMENTAL': '1'},
              ).run([
                '--non-interactive',
                '--yes',
                'experiment',
                'pause',
                '--experiment-id=experiment.checkout',
                '--expected-lifecycle-ordinal=$lifecycleOrdinal',
                '--idempotency-key=$idempotencyKey',
                '--directory=${project.path}',
              ]);
          return (code: code, err: stderr.toString());
        }

        await invoke(idempotencyKey: 'operator-retry-key', lifecycleOrdinal: 8);
        await invoke(idempotencyKey: 'operator-retry-key', lifecycleOrdinal: 8);
        await invoke(
          idempotencyKey: 'different-retry-key',
          lifecycleOrdinal: 8,
        );
        final changed = await invoke(
          idempotencyKey: 'operator-retry-key',
          lifecycleOrdinal: 9,
        );

        expect(requests, hasLength(4));
        expect(requests[1], orderedEquals(requests.first));
        expect(requests[2], isNot(orderedEquals(requests.first)));
        expect(requests[3], isNot(orderedEquals(requests.first)));
        final first = ExperimentAuthoringRequestV1.fromCanonicalBytes(
          requests.first,
        );
        final distinctKey = ExperimentAuthoringRequestV1.fromCanonicalBytes(
          requests[2],
        );
        final changedPayload = ExperimentAuthoringRequestV1.fromCanonicalBytes(
          requests[3],
        );
        expect(first.correlationId, startsWith('correlation-'));
        expect(first.correlationId.length, 'correlation-'.length + 64);
        expect(first.correlationId, isNot(distinctKey.correlationId));
        expect(first.correlationId, isNot(changedPayload.correlationId));
        expect(changed.code, 1);
        expect(changed.err, contains('replayRebinding'));
      },
    );

    test('sends the selectors as the payload for that operation', () async {
      late ExperimentAuthoringRequestV1 sent;
      final stdout = StringBuffer();
      final stderr = StringBuffer();
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, Object?>;
        final directory = targetDirectoryResponse(body['method']! as String);
        if (directory != null) return directory;
        sent = ExperimentAuthoringRequestV1.fromCanonicalBytes(
          byteDataBytes(body['requestBytes']! as String),
        );
        return http.Response(
          jsonEncode(
            byteDataWire(
              refusalFor(
                body['method']! as String,
                ExperimentAuthoringRefusalCodeV1.capabilityUnavailable,
                correlationId: sent.correlationId,
              ),
            ),
          ),
          200,
        );
      });

      await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: client,
        environment: const {'RESTAGE_EXPERIMENTAL': '1'},
      ).run([
        '--non-interactive',
        '--yes',
        'experiment',
        'pause',
        ..._lifecycleSelectors,
        '--directory=${project.path}',
      ]);

      expect(sent.operation, ExperimentAuthoringOperationV1.pauseExperiment);
      expect(sent.payload, {
        'expectedLifecycleOrdinal': 8,
        'experimentId': 'experiment.checkout',
      });
      expect(sent.idempotencyKey, isNotNull);
    });

    test('honours an operator-supplied idempotency key', () async {
      late ExperimentAuthoringRequestV1 sent;
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, Object?>;
        final directory = targetDirectoryResponse(body['method']! as String);
        if (directory != null) return directory;
        sent = ExperimentAuthoringRequestV1.fromCanonicalBytes(
          byteDataBytes(body['requestBytes']! as String),
        );
        return http.Response(
          jsonEncode(
            byteDataWire(
              refusalFor(
                body['method']! as String,
                ExperimentAuthoringRefusalCodeV1.capabilityUnavailable,
                correlationId: sent.correlationId,
              ),
            ),
          ),
          200,
        );
      });

      await RestageCli(
        stdout: StringBuffer(),
        stderr: StringBuffer(),
        credentialStore: store,
        httpClient: client,
        environment: const {'RESTAGE_EXPERIMENTAL': '1'},
      ).run([
        '--non-interactive',
        '--yes',
        'experiment',
        'pause',
        ..._lifecycleSelectors,
        '--idempotency-key=operator-chosen-key',
        '--directory=${project.path}',
      ]);

      expect(sent.idempotencyKey, 'operator-chosen-key');
    });

    test(
      'read operations carry no idempotency key and retain fresh correlation',
      () async {
        final sent = <ExperimentAuthoringRequestV1>[];
        final client = MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          final directory = targetDirectoryResponse(body['method']! as String);
          if (directory != null) return directory;
          final semanticRequest =
              ExperimentAuthoringRequestV1.fromCanonicalBytes(
                byteDataBytes(body['requestBytes']! as String),
              );
          sent.add(semanticRequest);
          return http.Response(
            jsonEncode(
              byteDataWire(
                refusalFor(
                  body['method']! as String,
                  ExperimentAuthoringRefusalCodeV1.capabilityUnavailable,
                  correlationId: semanticRequest.correlationId,
                ),
              ),
            ),
            200,
          );
        });

        for (var invocation = 0; invocation < 2; invocation++) {
          await RestageCli(
            stdout: StringBuffer(),
            stderr: StringBuffer(),
            credentialStore: store,
            httpClient: client,
            environment: const {'RESTAGE_EXPERIMENTAL': '1'},
          ).run([
            '--non-interactive',
            'experiment',
            'read',
            '--experiment-id=experiment.checkout',
            '--directory=${project.path}',
          ]);
        }

        expect(
          sent.map((request) => request.idempotencyKey),
          everyElement(isNull),
        );
        expect(
          sent.map((request) => request.correlationId).toSet(),
          hasLength(2),
        );
      },
    );
  });

  group('non-interactive discipline', () {
    test('names the selector a semantic choice is missing', () async {
      final result = await run(const ['read']);

      expect(result.code, 1);
      expect(result.err, contains('Required: --experiment-id'));
      expect(result.methods, isEmpty);
    });

    test('refuses a non-positive ordinal before any transport', () async {
      final result = await run(const [
        'pause',
        '--experiment-id=experiment.checkout',
        '--expected-lifecycle-ordinal=0',
      ]);

      expect(result.code, 1);
      expect(result.err, contains('must be a positive integer'));
      expect(result.methods, isEmpty);
    });
  });

  group('accepted results', () {
    test('discover renders and exits zero on an accepted drain', () async {
      final result = await run(
        const ['discover'],
        reply: (method, sent) => discoveryPage(
          namedEnvironmentLabels: const ['Production'],
          nextPageCursor: null,
          correlationId: sent.correlationId,
        ),
      );

      expect(result.code, 0);
      expect(result.out, contains('Discovered'));
      expect(result.err, isEmpty);
    });

    test('discover --json carries the action availability', () async {
      final result = await run(
        const ['discover', '--json'],
        reply: (method, sent) => discoveryPage(
          namedEnvironmentLabels: const ['Production'],
          nextPageCursor: null,
          correlationId: sent.correlationId,
        ),
      );

      final decoded = jsonDecode(result.out.trim()) as Map<String, Object?>;
      final availability = decoded['actionAvailability']! as List<Object?>;
      expect(
        availability.map((entry) => (entry! as Map<String, Object?>)['action']),
        ExperimentActionV1.values.map((action) => action.wireName),
      );
    });

    test('list renders each accepted entry and exits zero', () async {
      final result = await run(
        const ['list'],
        reply: (method, sent) => listPage(
          experimentIds: const ['experiment.a', 'experiment.b'],
          correlationId: sent.correlationId,
        ),
      );

      expect(result.code, 0);
      expect(result.out, contains('experiment.a'));
      expect(result.out, contains('experiment.b'));
    });

    test('a service-fault refusal exits two, not one', () async {
      final result = await run(
        const ['read', '--experiment-id=experiment.checkout'],
        reply: (method, sent) => refusalFor(
          method,
          ExperimentAuthoringRefusalCodeV1.backendUnavailable,
          correlationId: sent.correlationId,
        ),
      );

      expect(result.code, 2);
      expect(result.err, contains('retryable'));
    });
  });

  group('a route that will not finish a drain', () {
    test('reports it cleanly instead of crashing the tool', () async {
      final result = await run(
        const ['discover'],
        reply: (method, sent) => discoveryPage(
          namedEnvironmentLabels: const ['Production'],
          nextPageCursor: 'cursor-stuck',
          correlationId: sent.correlationId,
        ),
      );

      expect(result.code, 2, reason: 'a service fault, not operator error');
      expect(result.err, contains('cursor'));
    });
  });

  group('a request the operator wrote wrongly', () {
    test('names the field and never blames the service', () async {
      final bad = File('${project.path}/bad-replacement.json')
        ..writeAsStringSync(
          jsonEncode({
            ...emptyDraftChoices,
            'randomizedUnitSelection': const {
              'kind': 'serverDefault',
              'resolvedValue': 'installation',
              'source': {
                'kind': 'experimentRandomizedUnitDefaults',
                'randomizedUnitKind': 'installation',
              },
            },
          }),
        );

      final result = await run([
        'save',
        ..._draftBinding,
        '--replacement=${bad.path}',
      ]);

      expect(result.code, 1, reason: 'the operator can fix this, not a fault');
      expect(result.err, contains('randomizedUnitSelection'));
      expect(result.err, isNot(contains('The service returned')));
      expect(result.methods, isEmpty, reason: 'nothing may reach the wire');
    });
  });

  group('live-plane consent', () {
    /// Runs a live-plane pause with the given global flags.
    Future<({int code, String err, List<String> methods})> pauseLive(
      List<String> globals,
    ) async {
      final methods = <String>[];
      final stderr = StringBuffer();
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, Object?>;
        final method = body['method']! as String;
        final directory = targetDirectoryResponse(method);
        if (directory != null) return directory;
        methods.add(method);
        final sent = ExperimentAuthoringRequestV1.fromCanonicalBytes(
          byteDataBytes(body['requestBytes']! as String),
        );
        return http.Response(
          jsonEncode(
            byteDataWire(
              refusalFor(
                method,
                ExperimentAuthoringRefusalCodeV1.capabilityUnavailable,
                correlationId: sent.correlationId,
              ),
            ),
          ),
          200,
        );
      });
      final code =
          await RestageCli(
            stdout: StringBuffer(),
            stderr: stderr,
            credentialStore: store,
            httpClient: client,
            environment: const {'RESTAGE_EXPERIMENTAL': '1'},
          ).run([
            ...globals,
            'experiment',
            'pause',
            ..._lifecycleSelectors,
            '--directory=${project.path}',
          ]);
      return (code: code, err: stderr.toString(), methods: methods);
    }

    test('refuses a scripted live write without an explicit --yes', () async {
      final result = await pauseLive(const ['--non-interactive']);

      expect(result.code, 1);
      expect(result.err, contains('changes live experiment state'));
      expect(
        result.methods,
        isEmpty,
        reason: 'no live write may reach the route without consent',
      );
    });

    test('proceeds on an explicit --yes', () async {
      final result = await pauseLive(const ['--yes']);

      expect(result.methods, ['pauseExperiment']);
    });
  });

  group('the experimental gate', () {
    test('hides the command until the host opts in', () async {
      final stdout = StringBuffer();
      await RestageCli(
        stdout: stdout,
        stderr: StringBuffer(),
        credentialStore: store,
        environment: const {},
      ).run(const ['--help']);

      expect(stdout.toString(), isNot(contains('experiment ')));
    });

    test('a subcommand refuses and reaches no route without it', () async {
      final methods = <String>[];
      final stderr = StringBuffer();
      final code =
          await RestageCli(
            stdout: StringBuffer(),
            stderr: stderr,
            credentialStore: store,
            httpClient: MockClient((request) async {
              methods.add(
                (jsonDecode(request.body) as Map<String, Object?>)['method']!
                    as String,
              );
              return http.Response('{}', 200);
            }),
            environment: const {},
          ).run([
            '--non-interactive',
            '--yes',
            'experiment',
            'conclude',
            ..._lifecycleSelectors,
            '--directory=${project.path}',
          ]);

      expect(code, 1);
      expect(stderr.toString(), contains('experimental'));
      expect(
        methods,
        isEmpty,
        reason: 'no request may leave without the opt-in',
      );
    });
  });
}

typedef Uint8ListReply =
    List<int> Function(String method, ExperimentAuthoringRequestV1 sent);

/// The subcommand names the `Available subcommands` block of [help] lists.
List<String> _subcommandsInHelp(String help) {
  final lines = help.split('\n');
  final start = lines.indexWhere(
    (line) => line.trim() == 'Available subcommands:',
  );
  if (start < 0) return const [];
  final names = <String>[];
  for (final line in lines.skip(start + 1)) {
    if (line.trim().isEmpty) break;
    final match = RegExp(r'^\s{2}([a-z][a-z-]*)\s').firstMatch(line);
    if (match != null) names.add(match.group(1)!);
  }
  return names..sort();
}

/// Answers the directory reads the shared target resolution performs.
///
/// Returns null for anything else, so the caller handles the semantic route.
http.Response? targetDirectoryResponse(String method) => switch (method) {
  'listMine' => http.Response(
    jsonEncode([
      {'organizationId': 11, 'slug': 'restage', 'name': 'Restage'},
    ]),
    200,
  ),
  'listApps' => http.Response(
    jsonEncode([
      {'id': 23, 'slug': 'app', 'name': 'App'},
    ]),
    200,
  ),
  'listEnvironmentTargets' => http.Response(
    jsonEncode([
      {
        'environmentTargetId': 31,
        'namedEnvironmentId': 37,
        'environmentSlug': 'production',
        'runtimePlane': 'live',
      },
    ]),
    200,
  ),
  _ => null,
};
