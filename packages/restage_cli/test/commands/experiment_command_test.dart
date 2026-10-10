import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/src/cli.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:test/test.dart';

import '../_helpers/experiment_fixtures.dart';
import '../_helpers/test_fixtures.dart';

/// The subcommands, paired with the operation each one invokes.
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
  'register-build': 'registerBuildCapabilities',
  'readiness': 'readExperimentReadiness',
  'delivery-options': 'readDeliveryOptions',
};

/// The operator subcommands, paired with the route each one invokes.
const _operatorRoutes = <String, String>{
  'rebuild-serving-records': 'rebuildServingRecords',
};

const _typedDeliveryArms = <Map<String, Object?>>[
  {
    'contractVersion': 4,
    'kind': 'experimentSurfaceContractArmDelivery',
    'label': 'Contract treatment',
    'publishedRevision': 4,
    'stableArmId': 'arm.contract',
  },
];

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
  'register-build': _buildRegistration,
  'readiness': [],
  'delivery-options': ['--experiment-id=experiment.checkout'],
};

const _buildRegistration = [
  '--platform=ios',
  '--app-build-ordinal=412',
  '--sdk-api-level=3',
  '--context-schema-id=assignment.context.checkout',
  '--context-schema-revision-id=assignment.context.checkout.v2',
  '--context-schema-digest=cccccccccccccccccccccccccccccccc'
      'cccccccccccccccccccccccccccccccc',
];

const _draftBinding = [
  '--draft-id=experiment-draft-checkout',
  '--draft-revision-id=experiment-draft-checkout.v3',
  '--expected-cas=draft-cas-3',
];

const _lifecycleSelectors = [
  '--experiment-id=experiment.checkout',
  '--expected-lifecycle-ordinal=8',
];

const _audienceDigest =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

const _schemaDigest =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';

/// One accepted registration, as the route answers it.
Uint8List _registrationAccepted(
  String correlationId, {
  bool storedNow = true,
}) => ExperimentAuthoringResultV1.fromJson({
  'correlationId': correlationId,
  'kind': 'accepted',
  'operation': 'registerBuildCapabilities',
  'response': {
    'appBuildOrdinal': 412,
    'contextSchemaRef': {
      'contextSchemaId': 'assignment.context.checkout',
      'revisionId': 'assignment.context.checkout.v2',
      'semanticDigest': _schemaDigest,
    },
    'kind': 'experimentBuildCapabilityView',
    'platform': 'ios',
    'providedAttributeIds': const ['attr.country', 'attr.platform'],
    'schemaVersion': kMeasurementSchemaVersion,
    'storedNow': storedNow,
    'target': fixtureTarget.toJson(),
  },
  'schemaVersion': kMeasurementSchemaVersion,
}).canonicalBytes;

/// One accepted readiness read, with or without an assessment.
Uint8List _readinessAccepted(String correlationId, {bool assessed = true}) =>
    ExperimentAuthoringResultV1.fromJson({
      'correlationId': correlationId,
      'kind': 'accepted',
      'operation': 'readExperimentReadiness',
      'response': {
        'audiences': [
          {
            'description': null,
            'kind': 'experimentAudienceOption',
            'label': 'Sweden',
            'reference': {
              'policyId': 'audience.sweden',
              'revisionId': 'audience.sweden.v4',
              'semanticDigest': _audienceDigest,
            },
            'revisionOrdinal': 4,
          },
        ],
        'kind': 'experimentReadinessView',
        'nextPageCursor': null,
        'readiness': assessed
            ? {
                'activationBlocked': true,
                'attributes': [
                  {
                    'assignmentAttributeId': 'attr.country',
                    'kind': 'experimentAttributeReadiness',
                    'providingBuildCount': 1,
                    'supply': 'missingRegistration',
                  },
                ],
                'contextSchemaRef': {
                  'contextSchemaId': 'assignment.context.checkout',
                  'revisionId': 'assignment.context.checkout.v2',
                  'semanticDigest': _schemaDigest,
                },
                'kind': 'experimentAudienceReadiness',
                'reference': {
                  'policyId': 'audience.sweden',
                  'revisionId': 'audience.sweden.v4',
                  'semanticDigest': _audienceDigest,
                },
                'registeredBuilds': [
                  {
                    'appBuildOrdinal': 412,
                    'kind': 'experimentRegisteredBuild',
                    'platform': 'ios',
                    'providedAttributeIds': const ['attr.country'],
                  },
                  {
                    'appBuildOrdinal': 96,
                    'kind': 'experimentRegisteredBuild',
                    'platform': 'android',
                    'providedAttributeIds': const <String>[],
                  },
                ],
              }
            : null,
        'schemaVersion': kMeasurementSchemaVersion,
        'target': fixtureTarget.toJson(),
      },
      'schemaVersion': kMeasurementSchemaVersion,
    }).canonicalBytes;

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
    String Function(String method)? operatorReply,
    bool withYes = true,
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
      // An operator route carries no semantic request envelope.
      final requestBytes = body['requestBytes'];
      if (requestBytes == null) {
        return http.Response(
          jsonEncode(operatorReply?.call(method) ?? '{}'),
          200,
        );
      }
      final sent = ExperimentAuthoringRequestV1.fromCanonicalBytes(
        byteDataBytes(requestBytes as String),
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
          if (withYes) '--yes',
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

    test('the nineteen semantic subcommands cover the nineteen operations', () {
      expect(_routes, hasLength(19));
      expect(
        _routes.values.toSet(),
        ExperimentAuthoringOperationV1.values.map((e) => e.wireName).toSet(),
      );
    });

    test('the operator subcommand names no semantic operation', () {
      expect(
        _operatorRoutes.values.toSet().intersection(
          ExperimentAuthoringOperationV1.values.map((e) => e.wireName).toSet(),
        ),
        isEmpty,
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

    test('help lists the semantic and operator subcommands', () async {
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
        [..._routes.keys, ..._operatorRoutes.keys]..sort(),
      );
    });

    test(
      'the rebuild command reports readiness and exits on what is left',
      () async {
        const missing =
            '{"ready":false,"missing":2,"produced":1,"superseded":1,'
            '"sourcesReproven":true,'
            '"unrecoverable":[{"experimentId":"experiment.x",'
            '"reason":"sourcesNotProven"}],'
            '"surfaces":[{"surfaceId":3,"surfaceType":"paywall",'
            '"surfaceSlug":"checkout","surfaceContractFamilyId":null,'
            '"nominated":3,"missing":2,"produced":1,"superseded":1,'
            '"unrecoverable":[{"experimentId":"experiment.x",'
            '"reason":"sourcesNotProven"}]}]}';
        const ready =
            '{"ready":true,"missing":0,"produced":0,"superseded":0,'
            '"sourcesReproven":false,"unrecoverable":[],'
            '"surfaces":[{"surfaceId":3,"surfaceType":"paywall",'
            '"surfaceSlug":"checkout","surfaceContractFamilyId":null,'
            '"nominated":3,"missing":0,"produced":0,"superseded":0,'
            '"unrecoverable":[]}]}';

        final unready = await run(const [
          'rebuild-serving-records',
        ], operatorReply: (_) => missing);
        expect(unready.methods, [_operatorRoutes['rebuild-serving-records']]);
        expect(unready.code, 1);
        expect(unready.out, contains('Produced 1, superseded 1.'));
        expect(unready.out, contains('1 superseded'));
        expect(
          unready.out,
          contains('Unprovable: experiment.x (sourcesNotProven).'),
        );
        expect(unready.out, contains('paywall/checkout'));

        // A readiness read changes nothing, so it needs no live consent, and
        // its verdict must never read as the re-proven one.
        final settled = await run(
          const ['rebuild-serving-records', '--readiness-only'],
          operatorReply: (_) => ready,
          withYes: false,
        );
        expect(settled.methods, [_operatorRoutes['rebuild-serving-records']]);
        expect(settled.code, 0);
        expect(settled.out, isNot(contains('Ready:')));
        expect(settled.out, contains('sources not re-proven'));
      },
    );

    test('discover help explains the exact published revision read', () async {
      final stdout = StringBuffer();
      await RestageCli(
        stdout: stdout,
        stderr: StringBuffer(),
        credentialStore: store,
        environment: const {'RESTAGE_EXPERIMENTAL': '1'},
      ).run(const ['experiment', 'discover', '--help']);

      expect(stdout.toString(), contains('--surface-id'));
      expect(stdout.toString(), contains('--surface-revision-id'));
      expect(stdout.toString(), contains('inactive'));
      expect(stdout.toString(), contains('live delivery'));
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

  group('delivery options', () {
    test(
      'renders the sealed audience and exact arm publications as a read',
      () async {
        ExperimentAuthoringRequestV1? sentRequest;
        final result = await run(
          const ['delivery-options', '--experiment-id=experiment.checkout'],
          withYes: false,
          reply: (method, sent) {
            sentRequest = sent;
            return deliveryOptionsAccepted(sent.correlationId);
          },
        );

        expect(result.code, 0);
        expect(result.err, isEmpty);
        expect(result.methods, ['readDeliveryOptions']);
        expect(sentRequest!.idempotencyKey, isNull);
        expect(sentRequest!.payload, {'experimentId': 'experiment.checkout'});
        expect(result.out, contains('checkout (paywall)'));
        expect(result.out, contains('Sweden, revision audience.sweden.v4'));
        expect(result.out, contains('arm.control  Control  version 4'));
        expect(result.out, contains('arm.treatment  Treatment  version 5'));
      },
    );

    test(
      'renders a typed publication when its fields have equal numbers',
      () async {
        final result = await run(
          const ['delivery-options', '--experiment-id=experiment.checkout'],
          reply: (method, sent) => deliveryOptionsAccepted(
            sent.correlationId,
            arms: _typedDeliveryArms,
          ),
        );

        expect(result.code, 0);
        expect(
          result.out,
          contains('arm.contract  Contract treatment  revision 4 (contract 4)'),
        );
        expect(result.out, isNot(contains('Contract treatment  version 4')));
      },
    );

    test('preserves typed handover inputs in JSON output', () async {
      Uint8List? responseBytes;
      final result = await run(
        const [
          'delivery-options',
          '--experiment-id=experiment.checkout',
          '--json',
        ],
        reply: (method, sent) {
          responseBytes = deliveryOptionsAccepted(
            sent.correlationId,
            arms: _typedDeliveryArms,
          );
          return responseBytes!;
        },
      );

      expect(result.code, 0);
      final resultJson = jsonDecode(result.out) as Map<String, Object?>;
      expect(
        ExperimentAuthoringResultV1.fromJson(resultJson).canonicalBytes,
        orderedEquals(responseBytes!),
      );
      final response = resultJson['response']! as Map<String, Object?>;
      expect(response['audienceLabel'], 'Sweden');
      expect(response['audienceRevisionId'], 'audience.sweden.v4');
      expect(response['surfaceSlug'], 'checkout');
      expect(response['arms'], _typedDeliveryArms);
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

    test(
      'requires an experiment identity for delivery options before transport',
      () async {
        final result = await run(const ['delivery-options']);

        expect(result.code, 1);
        expect(result.err, contains('Required: --experiment-id'));
        expect(result.methods, isEmpty);
      },
    );

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

    test(
      'requires both exact discovery surface selectors before transport',
      () async {
        final surfaceId = fixtureMintedSurfaceId('checkout');
        final revisionId = fixtureMintedSurfaceRevisionId('checkout.r5');
        for (final arguments in [
          ['discover', '--surface-id=$surfaceId'],
          ['discover', '--surface-revision-id=$revisionId'],
        ]) {
          final result = await run(arguments);

          expect(result.code, 1);
          expect(result.methods, isEmpty);
          expect(
            result.err,
            contains('--surface-id and --surface-revision-id together'),
          );
        }
      },
    );

    test(
      'validates an exact discovery surface as platform-minted locally',
      () async {
        final result = await run(const [
          'discover',
          '--surface-id=checkout',
          '--surface-revision-id=checkout.r5',
        ]);

        expect(result.code, 1);
        expect(result.methods, isEmpty);
        expect(result.err, contains('exactSurfaceReference.surfaceId'));
      },
    );

    test('rejects paging options with an exact discovery selector', () async {
      final surfaceId = fixtureMintedSurfaceId('checkout');
      final revisionId = fixtureMintedSurfaceRevisionId('checkout.r5');
      for (final pagingOption in ['--page-size=1', '--page-cursor=next']) {
        final result = await run([
          'discover',
          '--surface-id=$surfaceId',
          '--surface-revision-id=$revisionId',
          pagingOption,
        ]);

        expect(result.code, isNot(0));
        expect(result.methods, isEmpty);
        expect(
          result.err,
          contains(pagingOption.substring(2).split('=').first),
        );
      }
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

    test(
      'discover reads one exact published surface without a continuation',
      () async {
        ExperimentAuthoringRequestV1? sentRequest;
        final surfaceId = fixtureMintedSurfaceId('checkout');
        final revisionId = fixtureMintedSurfaceRevisionId('checkout.r5');
        final result = await run(
          [
            'discover',
            '--surface-id=$surfaceId',
            '--surface-revision-id=$revisionId',
          ],
          reply: (method, sent) {
            sentRequest = sent;
            return discoveryPage(
              surfaces: const [('checkout', 'checkout.r5')],
              nextPageCursor: 'must-not-follow',
              correlationId: sent.correlationId,
            );
          },
        );

        expect(result.code, 0);
        expect(result.methods, ['discoverTargetsAndCapabilities']);
        expect(sentRequest!.payload, {
          'exactSurfaceReference': {
            'kind': 'exactSurfaceReference',
            'surfaceId': surfaceId,
            'surfaceRevisionId': revisionId,
          },
          'pageSize': 1,
        });
        expect(result.out, contains('Discovered 1 surfaces'));
      },
    );

    test('results print the digits the result carries, unchanged', () async {
      final result = await run(
        ['results', ..._selectors['results']!],
        reply: (method, sent) => resultsView(correlationId: sent.correlationId),
      );

      expect(result.code, 0);
      expect(result.err, isEmpty);
      expect(
        result.out,
        contains(
          '  arm.variant: rate 0.105000000 (525/5000 of 5000) '
          'effect 0.005000000, '
          'interval -0.000976563 to 0.008789063',
        ),
      );
      expect(
        result.out,
        contains('  guardrail guardrail.checkout-errors: withinBound'),
      );
    });

    test(
      'results --json keep the exact fraction behind every figure',
      () async {
        final result = await run(
          ['results', ..._selectors['results']!, '--json'],
          reply: (method, sent) =>
              resultsView(correlationId: sent.correlationId),
        );

        final decoded = jsonDecode(result.out.trim()) as Map<String, Object?>;
        final response = decoded['response']! as Map<String, Object?>;
        final arms = (response['armResults']! as List<Object?>)
            .cast<Map<String, Object?>>();
        final variant = arms.last;
        final interval = variant['interval']! as Map<String, Object?>;

        expect(variant['rateExact'], {'denominator': '200', 'numerator': '21'});
        expect(variant['effectExact'], {
          'denominator': '200',
          'numerator': '1',
        });
        expect(interval['lowerExact'], {
          'denominator': '1024',
          'numerator': '-1',
        });
        expect(interval['upperExact'], {
          'denominator': '1024',
          'numerator': '9',
        });
      },
    );

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

    test('list --results prints each entry beside its figures', () async {
      final result = await run(
        const ['list', '--results'],
        reply: (method, sent) => switch (method) {
          'listExperiments' => _activatedListPage(sent.correlationId),
          _ => resultsView(correlationId: sent.correlationId),
        },
      );

      expect(result.code, 0, reason: result.err);
      expect(result.methods, ['listExperiments', 'readExperimentResults']);
      expect(result.out, contains('experiment.checkout (active):'));
      expect(
        result.out,
        contains(
          '  arm.variant: rate 0.105000000 (525/5000 of 5000) '
          'effect 0.005000000, '
          'interval -0.000976563 to 0.008789063',
        ),
      );
    });

    test('list --results reads no result for an entry naming none', () async {
      final result = await run(
        const ['list', '--results'],
        reply: (method, sent) => listPage(
          experimentIds: const ['experiment.a'],
          correlationId: sent.correlationId,
        ),
      );

      expect(result.code, 0, reason: result.err);
      expect(result.methods, ['listExperiments']);
      expect(result.out, contains('experiment.a: no result'));
    });

    test('list --results keeps the rows around a refused entry', () async {
      var reads = 0;
      final result = await run(
        const ['list', '--results'],
        reply: (method, sent) => switch (method) {
          'listExperiments' => _activatedListPage(
            sent.correlationId,
            experimentIds: const ['experiment.a', 'experiment.b'],
          ),
          _ =>
            ++reads == 1
                ? refusalFor(
                    method,
                    ExperimentAuthoringRefusalCodeV1.capabilityUnavailable,
                    correlationId: sent.correlationId,
                  )
                : resultsView(correlationId: sent.correlationId),
        },
      );

      expect(result.code, 0, reason: result.err);
      expect(result.methods, [
        'listExperiments',
        'readExperimentResults',
        'readExperimentResults',
      ]);
      expect(
        result.out,
        contains('experiment.a: no result (capabilityUnavailable)'),
      );
      expect(result.out, contains('experiment.b (active):'));
      expect(result.out, contains('  arm.variant: rate 0.105000000'));
    });

    test('list --results --json keeps each entry beside its result', () async {
      final result = await run(
        const ['list', '--results', '--json'],
        reply: (method, sent) => switch (method) {
          'listExperiments' => _activatedListPage(sent.correlationId),
          _ => resultsView(correlationId: sent.correlationId),
        },
      );

      final rows = (jsonDecode(result.out.trim())! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(rows, hasLength(1));
      final entry = rows.single['entry']! as Map<String, Object?>;
      expect(entry['kind'], 'experimentSummary');
      final results = rows.single['results']! as Map<String, Object?>;
      final arms = (results['armResults']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(arms.last['rate'], '0.105000000');
      expect(arms.last['rateExact'], {'denominator': '200', 'numerator': '21'});
    });

    test('the drain follows every cursor and keeps every entry', () async {
      final cursors = <String?>[];
      final result = await run(
        const ['list'],
        reply: (method, sent) {
          cursors.add(sent.payload['pageCursor'] as String?);
          return switch (cursors.length) {
            1 => listPage(
              experimentIds: const ['experiment.a'],
              nextPageCursor: 'cursor-2',
              correlationId: sent.correlationId,
            ),
            2 => listPage(
              experimentIds: const ['experiment.b'],
              nextPageCursor: 'cursor-3',
              correlationId: sent.correlationId,
            ),
            _ => listPage(
              experimentIds: const ['experiment.c'],
              correlationId: sent.correlationId,
            ),
          };
        },
      );

      expect(result.code, 0);
      expect(cursors, [null, 'cursor-2', 'cursor-3']);
      for (final id in const ['experiment.a', 'experiment.b', 'experiment.c']) {
        expect(result.out, contains(id));
      }
    });

    // Nothing bounds how many entries a drain returns. A page size is bounded;
    // a total is not, so this asserts an absence the route must keep.
    test('the drain keeps every entry past any one page size', () async {
      final expected = [for (var index = 0; index < 250; index++) 'e.$index'];
      var page = 0;
      final result = await run(
        const ['list'],
        reply: (method, sent) {
          final start = page * 100;
          final end = start + 100 > expected.length
              ? expected.length
              : start + 100;
          page += 1;
          return listPage(
            experimentIds: expected.sublist(start, end),
            nextPageCursor: end < expected.length ? 'cursor-$page' : null,
            correlationId: sent.correlationId,
          );
        },
      );

      expect(result.code, 0);
      expect(page, 3);
      expect(result.out.trim().split('\n'), expected);
    });

    test('every request says this build reads an issue locator', () async {
      final declared = <bool>[];
      await run(
        const ['list'],
        reply: (method, sent) {
          declared.add(sent.issueLocators);
          return listPage(correlationId: sent.correlationId);
        },
      );

      expect(declared, isNotEmpty);
      expect(declared, everyElement(isTrue));
    });

    test(
      'validate names the experiment already holding the audience',
      () async {
        ExperimentAuthoringRequestV1? sentRequest;
        final result = await run(
          const ['validate', ..._draftBinding],
          reply: (method, sent) {
            sentRequest = sent;
            return _conflictValidation(sent.correlationId);
          },
        );

        expect(result.code, 0);
        expect(sentRequest!.issueLocators, isTrue);
        expect(result.out, contains('experiment.sweden'));
        expect(result.out, contains('audience.se.v1'));
        expect(result.out, contains('audience.se.v2'));
        expect(result.out, contains('concurrentAudienceOverlap'));
      },
    );

    test('validate preserves a conflict locator in JSON output', () async {
      final result = await run(const [
        'validate',
        ..._draftBinding,
        '--json',
      ], reply: (method, sent) => _conflictValidation(sent.correlationId));

      final resultJson = jsonDecode(result.out) as Map<String, Object?>;
      final response = resultJson['response']! as Map<String, Object?>;
      final issue =
          (response['issues']! as List<Object?>).single!
              as Map<String, Object?>;
      final locator = issue['locator']! as Map<String, Object?>;
      expect(locator['conflictingExperimentId'], 'experiment.sweden');
      expect(
        (locator['conflictingAudienceRef']!
            as Map<String, Object?>)['revisionId'],
        'audience.se.v1',
      );
      expect(
        (locator['proposedAudienceRef']! as Map<String, Object?>)['revisionId'],
        'audience.se.v2',
      );
    });

    test(
      'renders an activation audience conflict refusal from its locator',
      () async {
        ExperimentAuthoringRequestV1? sentRequest;
        final result = await run(
          ['activate', ..._selectors['activate']!],
          reply: (method, sent) {
            sentRequest = sent;
            return _conflictActivationRefusal(sent.correlationId);
          },
        );

        expect(result.code, 1);
        expect(result.methods, ['activateDraft']);
        expect(sentRequest!.issueLocators, isTrue);
        expect(result.out, isEmpty);
        expect(result.err, contains('validationBlocked'));
        expect(result.err, contains('experiment.sweden'));
        expect(result.err, contains('audience.se.v1'));
        expect(result.err, contains('audience.se.v2'));
      },
    );

    test(
      'preserves an activation audience conflict refusal in JSON output',
      () async {
        final result = await run(
          ['activate', ..._selectors['activate']!, '--json'],
          reply: (method, sent) =>
              _conflictActivationRefusal(sent.correlationId),
        );

        expect(result.code, 1);
        final refusal =
            (jsonDecode(result.out) as Map<String, Object?>)['refusal']!
                as Map<String, Object?>;
        final locator = refusal['locator']! as Map<String, Object?>;
        expect(refusal['code'], 'validationBlocked');
        expect(locator['conflictingExperimentId'], 'experiment.sweden');
        expect(
          (locator['conflictingAudienceRef']!
              as Map<String, Object?>)['revisionId'],
          'audience.se.v1',
        );
        expect(
          (locator['proposedAudienceRef']!
              as Map<String, Object?>)['revisionId'],
          'audience.se.v2',
        );
      },
    );

    test('a service-fault refusal exits with code two', () async {
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

  group('build capability and readiness', () {
    test(
      'register-build sends the build and schema the operator named',
      () async {
        ExperimentAuthoringRequestV1? sentRequest;
        final result = await run(
          const ['register-build', ..._buildRegistration],
          reply: (method, sent) {
            sentRequest = sent;
            return _registrationAccepted(sent.correlationId);
          },
        );

        expect(result.code, 0);
        expect(result.methods, ['registerBuildCapabilities']);
        final payload = sentRequest!.payload;
        expect(payload['platform'], 'ios');
        expect(payload['appBuildOrdinal'], 412);
        expect(payload['sdkApiLevel'], 3);
        expect(payload['contextSchemaRef'], {
          'contextSchemaId': 'assignment.context.checkout',
          'revisionId': 'assignment.context.checkout.v2',
          'semanticDigest': 'c' * 64,
        });
        // A write carries retry identity; a read is refused one.
        expect(sentRequest!.idempotencyKey, isNotNull);
        expect(result.out, contains('Registered ios 412'));
        expect(result.out, contains('attr.country'));
      },
    );

    test('a repeat registration reports that nothing was stored', () async {
      final result = await run(
        const ['register-build', ..._buildRegistration],
        reply: (method, sent) =>
            _registrationAccepted(sent.correlationId, storedNow: false),
      );

      expect(result.code, 0);
      expect(result.out, contains('Already registered ios 412'));
    });

    test('readiness lists the audiences and names what blocks one', () async {
      ExperimentAuthoringRequestV1? sentRequest;
      final result = await run(
        <String>[
          'readiness',
          '--audience-id=audience.sweden',
          '--audience-revision-id=audience.sweden.v4',
          '--audience-digest=$_audienceDigest',
        ],
        reply: (method, sent) {
          sentRequest = sent;
          return _readinessAccepted(sent.correlationId);
        },
      );

      expect(result.code, 0);
      expect(result.methods, ['readExperimentReadiness']);
      expect(sentRequest!.payload['audienceRef'], {
        'policyId': 'audience.sweden',
        'revisionId': 'audience.sweden.v4',
        'semanticDigest': _audienceDigest,
      });
      // A read carries no retry identity.
      expect(sentRequest!.idempotencyKey, isNull);
      expect(result.out, contains('Sweden'));
      expect(result.out, contains('revision 4'));
      expect(result.out, contains('Cannot be activated yet.'));
      expect(result.out, contains('not reported by android 96'));
    });

    test(
      'readiness reads the roster alone when no audience is named',
      () async {
        ExperimentAuthoringRequestV1? sentRequest;
        final result = await run(
          const ['readiness'],
          reply: (method, sent) {
            sentRequest = sent;
            return _readinessAccepted(sent.correlationId, assessed: false);
          },
        );

        expect(result.code, 0);
        expect(sentRequest!.payload.containsKey('audienceRef'), isFalse);
        expect(sentRequest!.payload['pageSize'], 100);
        expect(result.out, contains('Sweden'));
        expect(result.out, isNot(contains('Cannot be activated')));
      },
    );

    test(
      'readiness sends the continuation cursor the operator named',
      () async {
        ExperimentAuthoringRequestV1? sentRequest;
        final result = await run(
          const [
            'readiness',
            '--page-size=37',
            '--page-cursor=audience-page-2',
          ],
          reply: (method, sent) {
            sentRequest = sent;
            return _readinessAccepted(sent.correlationId, assessed: false);
          },
        );

        expect(result.code, 0);
        expect(sentRequest!.payload, {
          'pageCursor': 'audience-page-2',
          'pageSize': 37,
        });
      },
    );

    test('half an audience reference never reaches the route', () async {
      final result = await run(const [
        'readiness',
        '--audience-id=audience.sweden',
      ]);

      expect(result.code, 1);
      expect(result.methods, isEmpty);
      expect(result.err, contains('--audience-revision-id'));
    });

    test(
      'a key the route will not accept is reported, never widened',
      () async {
        final result = await run(
          const ['register-build', ..._buildRegistration],
          reply: (method, sent) => refusalFor(
            method,
            ExperimentAuthoringRefusalCodeV1.deniedAction,
            correlationId: sent.correlationId,
          ),
        );

        expect(result.code, isNot(0));
        expect(result.err, contains('deniedAction'));
      },
    );
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

      expect(result.code, 2, reason: 'code two marks a service fault');
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

      expect(
        result.code,
        1,
        reason: 'code one marks an operator-fixable error',
      );
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

/// One accepted list page carrying an activated, evaluated entry per id.
Uint8List _activatedListPage(
  String correlationId, {
  List<String> experimentIds = const ['experiment.checkout'],
}) => ExperimentAuthoringResultV1.fromJson({
  'correlationId': correlationId,
  'kind': 'accepted',
  'operation': 'listExperiments',
  'response': {
    'experiments': [
      for (final experimentId in experimentIds)
        {
          'acceptedAtMicros': 1788091300000000,
          'activationOrdinal': 7,
          'archivedAtMicros': null,
          'controlPlaneOrdinal': 9,
          'experimentId': experimentId,
          'inferenceReference': {
            'inferenceRevisionId': 'inference.checkout.v2',
            'kind': 'exact',
            'resultDigest': _audienceDigest,
          },
          'integrityState': 'verified',
          'kind': 'experimentSummary',
          'label': experimentId,
          'lifecycleOrdinal': 8,
          'lifecycleState': 'active',
          'liveReadReference': {
            'activationOrdinal': 7,
            'experimentId': experimentId,
            'kind': 'experimentLiveReadReference',
            'receiptDigest': _schemaDigest,
            'target': fixtureTarget.toJson(),
          },
          'pendingDraft': const {'kind': 'none'},
          'schemaVersion': kMeasurementSchemaVersion,
          'target': fixtureTarget.toJson(),
        },
    ],
    'kind': 'experimentListView',
    'nextPageCursor': null,
    'schemaVersion': kMeasurementSchemaVersion,
    'target': fixtureTarget.toJson(),
  },
  'schemaVersion': kMeasurementSchemaVersion,
}).canonicalBytes;

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

/// An accepted validation carrying one audience conflict.
Uint8List _conflictValidation(String correlationId) =>
    ExperimentAuthoringResultV1.fromJson({
      'correlationId': correlationId,
      'kind': 'accepted',
      'operation': 'validateDraft',
      'response': {
        'capabilityReasons': const <Object?>[],
        'draftBinding': fixtureDraftBinding,
        'issues': [
          {
            'code': 'staleDependency',
            'fieldPath': 'assignmentAudienceSelection',
            'kind': 'experimentValidationIssue',
            'locator': {
              'conflictingAudienceRef': _audienceRef('audience.se.v1'),
              'conflictingExperimentId': 'experiment.sweden',
              'kind': 'audienceConflict',
              'proposedAudienceRef': _audienceRef('audience.se.v2'),
            },
            'messageKey': 'experiment.activation.concurrentAudienceOverlap',
          },
        ],
        'kind': 'experimentValidationView',
        'planningPreview': null,
        'schemaVersion': kMeasurementSchemaVersion,
      },
      'schemaVersion': kMeasurementSchemaVersion,
    }).canonicalBytes;

/// A refused activation carrying the same typed conflict as the production
/// application boundary.
Uint8List _conflictActivationRefusal(String correlationId) =>
    ExperimentAuthoringResultV1.fromJson({
      'correlationId': correlationId,
      'kind': 'refused',
      'operation': 'activateDraft',
      'refusal': {
        'code': 'validationBlocked',
        'kind': 'experimentAuthoringRefusal',
        'locator': {
          'conflictingAudienceRef': _audienceRef('audience.se.v1'),
          'conflictingExperimentId': 'experiment.sweden',
          'kind': 'audienceConflict',
          'proposedAudienceRef': _audienceRef('audience.se.v2'),
        },
        'messageKey': 'experiment.authoring.validationBlocked',
        'retryable': false,
        'schemaVersion': kMeasurementSchemaVersion,
      },
      'schemaVersion': kMeasurementSchemaVersion,
    }).canonicalBytes;

Map<String, Object?> _audienceRef(String revisionId) => {
  'assignmentAudiencePolicyId': 'audience.se',
  'revisionId': revisionId,
  'semanticHash': 'b' * 64,
};
