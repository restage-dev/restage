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
  'delete-draft': 'deleteDraft',
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
  'read': 'readExperiment',
  'archive': 'setExperimentArchived',
  'register-build': 'registerBuildCapabilities',
  'readiness': 'readExperimentReadiness',
  'delivery-options': 'readDeliveryOptions',
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
  'delete-draft': _draftBinding,
  'read-draft': _draftBinding,
  'resolve-draft': ['--draft-id=draft'],
  'save': [],
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
  'read': ['--experiment-id=experiment.checkout'],
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

  /// Writes the accepted draft result that save edits.
  String replacementPath() {
    final file = File('${project.path}/replacement.json')
      ..writeAsBytesSync(acceptedFor('readDraft'));
    return file.path;
  }

  /// Runs `restage experiment <arguments>` against a fake backend.
  Future<({int code, String out, String err, List<String> methods})> run(
    List<String> arguments, {
    Uint8ListReply? reply,
    bool withYes = true,
    Map<String, String> environment = const {},
    http.Response? Function(Map<String, Object?> body)? raw,
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
      if (raw?.call(body) case final response?) return response;
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
          environment: environment,
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

    test('the eighteen semantic subcommands cover the operations they own', () {
      expect(_routes, hasLength(18));
      expect({
        ..._routes.values,
        'listExperiments',
        'readExperimentResults',
      }, ExperimentAuthoringOperationV1.values.map((e) => e.wireName).toSet());
    });

    test('draft and experiment reads stay separate routes', () async {
      final resolved = await run([
        'resolve-draft',
        ..._selectors['resolve-draft']!,
      ]);
      expect(resolved.methods, ['resolveDraft']);
      final draft = await run(['read-draft', ..._selectors['read-draft']!]);
      final experiment = await run(['read', ..._selectors['read']!]);

      expect(draft.methods, ['readDraft']);
      expect(experiment.methods, ['readExperiment']);
    });

    test('help lists every subcommand', () async {
      final stdout = StringBuffer();
      final stderr = StringBuffer();
      await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
      ).run(const ['experiment', '--help']);

      expect(
        _subcommandsInHelp(stdout.toString()),
        [..._routes.keys, 'list', 'results']..sort(),
      );
    });

    test('discover help explains the exact published revision read', () async {
      final stdout = StringBuffer();
      await RestageCli(
        stdout: stdout,
        stderr: StringBuffer(),
        credentialStore: store,
      ).run(const ['experiment', 'discover', '--help']);

      expect(stdout.toString(), contains('--surface-id'));
      expect(stdout.toString(), contains('--surface-revision-id'));
      expect(stdout.toString(), contains('inactive'));
      expect(stdout.toString(), contains('live delivery'));
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

    test('create sends the surface root with its initial candidate', () async {
      ExperimentAuthoringRequestV1? sent;
      final surfaceId = fixtureMintedSurfaceId('checkout');
      final surfaceRevisionId = fixtureMintedSurfaceRevisionId('checkout.r3');
      final result = await run(
        [
          'create',
          '--surface-id=$surfaceId',
          '--surface-revision-id=$surfaceRevisionId',
        ],
        reply: (method, request) {
          sent = request;
          return refusalFor(
            method,
            ExperimentAuthoringRefusalCodeV1.capabilityUnavailable,
            correlationId: request.correlationId,
          );
        },
      );

      expect(result.err, isNot(contains('explicit root')), reason: result.err);
      expect(sent, isNotNull, reason: result.err);
      expect(sent!.operation, ExperimentAuthoringOperationV1.openDraft);
      expect(sent!.payload, {
        'initialCandidate': {
          'kind': 'exactSurfaceReference',
          'surfaceId': surfaceId,
          'surfaceRevisionId': surfaceRevisionId,
        },
        'root': DeliveryRootIdentityV1.surface(
          PublishedSurfaceIdentityV1(
            target: fixtureTarget,
            surfaceId: SurfaceId(surfaceId),
          ),
        ).toJson(),
      });
    });

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

    test('every request says this build reads an issue locator', () async {
      final declared = <bool>[];
      await run(
        const ['discover'],
        reply: (method, sent) {
          declared.add(sent.issueLocators);
          return discoveryPage(
            nextPageCursor: null,
            correlationId: sent.correlationId,
          );
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
      'an activation held for a fit is sent again confirmed with --yes',
      () async {
        final bodies = <Map<String, Object?>>[];
        final result = await run(
          ['activate', ..._selectors['activate']!],
          raw: (body) {
            bodies.add(body);
            if (body['acceptFit'] == true) return null;
            return http.Response(
              jsonEncode({
                'className': 'SurfaceFitNeedsConfirmationException',
                'data': {
                  '__className__': 'SurfaceFitNeedsConfirmationException',
                  'verdict': 'noneFit',
                  'environment': 'staging',
                  'builds': {'items': <Object>[]},
                },
              }),
              400,
            );
          },
        );

        expect(result.methods, ['activateDraft', 'activateDraft']);
        expect(bodies.map((b) => b['acceptFit']), [null, true]);
        expect(result.err, contains('No app version in use can show this yet'));
      },
    );

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
      final result = await run(const ['resolve-draft', '--draft-id=Draft']);

      expect(result.code, 1);
      expect(result.err, contains('draftId'));
      expect(result.err, isNot(contains('The service returned')));
      expect(result.methods, isEmpty);
    });
  });

  group('saving draft results', () {
    String writeReplacement(Object? document) {
      final file = File('${project.path}/replacement.json')
        ..writeAsStringSync(jsonEncode(document));
      return file.path;
    }

    for (final complete in [true, false]) {
      test(
        'saves edited ${complete ? 'complete' : 'partial'} CLI read output',
        () async {
          final read = await run(
            const ['read-draft', ..._draftBinding, '--json'],
            reply: (method, sent) => acceptedFor(
              method,
              correlationId: sent.correlationId,
              completeDraft: complete,
            ),
          );
          expect(read.code, 0, reason: read.err);
          final edited = jsonDecode(read.out) as Map<String, Object?>;
          final draft = edited['response']! as Map<String, Object?>;
          (draft['choices']! as Map<String, Object?>)['label'] =
              'Updated checkout';
          Map<String, Object?>? payload;
          final saved = await run(
            ['save', '--replacement=${writeReplacement(edited)}'],
            reply: (method, sent) {
              payload = sent.payload;
              return acceptedFor(
                method,
                correlationId: sent.correlationId,
                completeDraft: complete,
              );
            },
          );
          expect(saved.code, 0, reason: saved.err);
          expect(saved.methods, ['replaceDraft']);
          expect(payload, containsPair('draftId', draft['draftId']));
          expect(
            payload,
            containsPair('draftRevisionId', draft['draftRevisionId']),
          );
          expect(payload, containsPair('expectedCas', draft['expectedCas']));
          expect(
            payload!['replacement'],
            containsPair('label', 'Updated checkout'),
          );
        },
      );
    }

    test('accepts the result of every draft command', () async {
      for (final operation in [
        'openDraft',
        'readDraft',
        'resolveDraft',
        'replaceDraft',
        'copyDraftToTarget',
      ]) {
        final document = jsonDecode(utf8.decode(acceptedFor(operation)));
        final result = await run(
          ['save', '--replacement=${writeReplacement(document)}'],
          reply: (method, sent) =>
              acceptedFor(method, correlationId: sent.correlationId),
        );
        expect(result.code, 0, reason: '$operation: ${result.err}');
        expect(result.methods, ['replaceDraft']);
      }
      final help = await run(const ['save', '--help']);
      expect(help.out, isNot(contains('--draft-id')));
      expect(
        help.out,
        contains('Path to the --json output of a draft command'),
      );
    });

    test('wrong inputs get one actionable message before send', () async {
      final read =
          jsonDecode(utf8.decode(acceptedFor('readDraft')))
              as Map<String, Object?>;
      final draft = read['response']! as Map<String, Object?>;
      for (final input in [
        emptyDraftChoices,
        draft,
        draft['choices'],
        jsonDecode(
          utf8.decode(
            refusalFor(
              'readDraft',
              ExperimentAuthoringRefusalCodeV1.staleDraft,
            ),
          ),
        ),
        jsonDecode(utf8.decode(acceptedFor('listExperiments'))),
      ]) {
        final result = await run([
          'save',
          '--replacement=${writeReplacement(input)}',
        ]);
        expect(result.code, 1);
        expect(
          result.err,
          'The replacement file must be the --json output of a draft command.\n',
        );
        expect(result.methods, isEmpty);
      }
    });

    test('names a misspelled choice in an edited draft before send', () async {
      final document =
          jsonDecode(utf8.decode(acceptedFor('readDraft')))
              as Map<String, Object?>;
      final draft = document['response']! as Map<String, Object?>;
      (draft['choices']! as Map<String, Object?>)['lable'] = 'Updated checkout';

      final result = await run([
        'save',
        '--replacement=${writeReplacement(document)}',
      ]);

      expect(result.code, 1);
      expect(
        result.err,
        'experimentDraftChoices contains unknown keys: lable\n',
      );
      expect(result.methods, isEmpty);
    });

    test('reports invalid JSON before send', () async {
      final file = File('${project.path}/replacement.json')
        ..writeAsStringSync('{');

      final result = await run(['save', '--replacement=${file.path}']);

      expect(result.code, 1);
      expect(result.err, 'The replacement file is not valid JSON.\n');
      expect(result.methods, isEmpty);
    });

    test('refuses a draft from another target before send', () async {
      final document = jsonDecode(
        utf8.decode(acceptedFor('readDraft', target: fixtureOtherTarget)),
      );
      final result = await run([
        'save',
        '--replacement=${writeReplacement(document)}',
      ]);
      expect(result.code, 1);
      expect(result.err, contains('does not match the selected target'));
      expect(result.methods, isEmpty);
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
      expect(result.err, contains('changes what the live plane serves'));
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

  group('available without experimental opt-in', () {
    for (final entry in <String, Map<String, String>>{
      'unset': const {},
      'false': const {'RESTAGE_EXPERIMENTAL': 'false'},
      'zero': const {'RESTAGE_EXPERIMENTAL': '0'},
    }.entries) {
      test('lists every subcommand with opt-in ${entry.key}', () async {
        final stdout = StringBuffer();
        final code = await RestageCli(
          stdout: stdout,
          stderr: StringBuffer(),
          credentialStore: store,
          environment: entry.value,
        ).run(const ['experiment', '--help']);

        expect(code, 0);
        expect(
          _subcommandsInHelp(stdout.toString()),
          [..._routes.keys, 'list', 'results']..sort(),
        );
      });

      test('executes authoring with opt-in ${entry.key}', () async {
        for (final command in ['discover', 'create', 'read-draft']) {
          final result = await run(
            [command, ..._selectors[command]!],
            environment: entry.value,
            reply: (method, sent) =>
                acceptedFor(method, correlationId: sent.correlationId),
          );

          expect(result.code, 0, reason: '$command: ${result.err}');
          expect(result.methods, [_routes[command]]);
          expect(result.out, isNotEmpty);
        }
      });

      test('still requires authentication with opt-in ${entry.key}', () async {
        await store.delete();
        var requests = 0;
        final stderr = StringBuffer();
        final code =
            await RestageCli(
              stdout: StringBuffer(),
              stderr: stderr,
              credentialStore: store,
              environment: entry.value,
              httpClient: MockClient((request) async {
                requests += 1;
                return http.Response('{}', 200);
              }),
            ).run([
              '--non-interactive',
              'experiment',
              'create',
              '--directory=${project.path}',
            ]);

        expect(code, 1);
        expect(stderr.toString(), contains('Not signed in.'));
        expect(requests, 0);
      });

      test('still requires live consent with opt-in ${entry.key}', () async {
        final result = await run(
          const ['pause', ..._lifecycleSelectors],
          environment: entry.value,
          withYes: false,
        );

        expect(result.code, 1);
        expect(result.err, contains('changes what the live plane serves'));
        expect(result.methods, isEmpty);
      });
    }
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
const _experimentTarget = {
  'environmentTargetId': 31,
  'namedEnvironmentId': 37,
  'environmentSlug': 'production',
  'runtimePlane': 'live',
};

http.Response? targetDirectoryResponse(String method) => switch (method) {
  'read' => http.Response(
    jsonEncode({
      'organizationId': 11,
      'session': {
        'memberships': [
          {
            'organizationId': 11,
            'slug': 'restage',
            'name': 'Restage',
            'role': 'owner',
          },
        ],
        'workspaceExperiences': <Object>[],
      },
      'projects': [
        {'id': 1, 'slug': 'checkout', 'name': 'Checkout'},
      ],
      'apps': [
        {'id': 23, 'projectId': 1, 'slug': 'app', 'name': 'App'},
      ],
      'environments': [
        {'id': 31, 'appId': 23, 'namedEnvironmentId': 37, 'slug': 'production'},
      ],
      'environmentTargets': [_experimentTarget],
      'surfaces': <Object>[],
    }),
    200,
  ),
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
    jsonEncode([_experimentTarget]),
    200,
  ),
  'resolveTarget' => http.Response(
    jsonEncode({
      'organizationId': 11,
      'organizationSlug': 'restage',
      'projectSlug': 'project',
      'appId': 23,
      'appSlug': 'app',
      'target': _experimentTarget,
    }),
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
