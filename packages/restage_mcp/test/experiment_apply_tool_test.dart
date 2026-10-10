import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_mcp/client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/api.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:test/test.dart';

import '_support/harness.dart';

const _typedDeliveryArms = <Map<String, Object?>>[
  {
    'contractVersion': 4,
    'kind': 'experimentSurfaceContractArmDelivery',
    'label': 'Contract treatment',
    'publishedRevision': 4,
    'stableArmId': 'arm.contract',
  },
];

void main() {
  late Directory home;
  late FileCredentialStore store;

  setUp(() async {
    home = Directory.systemTemp.createTempSync('restage_mcp_experiment');
    store = FileCredentialStore('${home.path}/credentials');
    await store.write(
      const Credential(
        endpoint: 'http://localhost:8080/',
        kind: CredentialKind.authKey,
        authToken: 'keyId:key',
      ),
    );
  });

  tearDown(() => home.deleteSync(recursive: true));

  /// Connects a server whose semantic route answers with [reply].
  Future<({ServerConnection connection, List<String> methods})> connect({
    Uint8List Function(String method, ExperimentAuthoringRequestV1 request)?
    reply,
    List<Uint8List>? requests,
  }) async {
    final methods = <String>[];
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, Object?>;
      final method = body['method']! as String;
      final directory = _targetDirectory(method);
      if (directory != null) return directory;
      methods.add(method);
      final bytes = _bytes(body['requestBytes']! as String);
      requests?.add(bytes);
      final sent = ExperimentAuthoringRequestV1.fromCanonicalBytes(bytes);
      return http.Response(
        jsonEncode(
          _wire(
            reply?.call(method, sent) ??
                _refusal(
                  method,
                  ExperimentAuthoringRefusalCodeV1.capabilityUnavailable,
                  sent.correlationId,
                ),
          ),
        ),
        200,
      );
    });
    final connection = await connectServer(store: store, httpClient: client);
    return (connection: connection, methods: methods);
  }

  Map<String, Object?> arguments({
    required String operation,
    required Map<String, Object?> payload,
    String? idempotencyKey,
  }) => {
    'operation': operation,
    'payload': payload,
    'idempotencyKey': ?idempotencyKey,
    'organizationId': 11,
    'projectSlug': 'checkout',
    'appSlug': 'app',
    'environmentSlug': 'production',
    'environmentTargetId': 31,
    'runtimePlane': 'live',
  };

  group('the tool schema', () {
    test('offers every operation as a closed choice', () async {
      final server = await connect();
      final tools = await server.connection.listTools(ListToolsRequest());
      final tool = tools.tools.singleWhere(
        (candidate) => candidate.name == 'restage_experiment_apply',
      );

      final properties =
          (tool.inputSchema as Map<String, Object?>)['properties']!
              as Map<String, Object?>;
      final operation = properties['operation']! as Map<String, Object?>;
      expect(operation['enum'], [
        for (final value in ExperimentAuthoringOperationV1.values)
          value.wireName,
      ]);
      expect(
        (operation['enum']! as List<Object?>),
        hasLength(ExperimentAuthoringOperationV1.values.length),
      );
    });

    test(
      'rejects unknown properties and asks for no canonical bytes',
      () async {
        final server = await connect();
        final tools = await server.connection.listTools(ListToolsRequest());
        final tool = tools.tools.singleWhere(
          (candidate) => candidate.name == 'restage_experiment_apply',
        );

        final schema = tool.inputSchema as Map<String, Object?>;
        expect(schema['additionalProperties'], isFalse);
        final properties = schema['properties']! as Map<String, Object?>;
        expect(
          properties.keys.where((key) => key.toLowerCase().contains('base64')),
          isEmpty,
        );
        expect(jsonEncode(schema).toLowerCase(), isNot(contains('base64')));
      },
    );

    test('pins its exact property and required sets', () async {
      final server = await connect();
      final tools = await server.connection.listTools(ListToolsRequest());
      final tool = tools.tools.singleWhere(
        (candidate) => candidate.name == 'restage_experiment_apply',
      );

      final schema = tool.inputSchema as Map<String, Object?>;
      expect(
        (schema['properties']! as Map<String, Object?>).keys.toList()..sort(),
        [
          'appSlug',
          'environmentSlug',
          'environmentTargetId',
          'idempotencyKey',
          'operation',
          'organizationId',
          'payload',
          'projectSlug',
          'runtimePlane',
        ],
      );
      expect(
        (schema['required']! as List<Object?>).cast<String>().toList()..sort(),
        [
          'appSlug',
          'environmentSlug',
          'environmentTargetId',
          'operation',
          'organizationId',
          'payload',
          'projectSlug',
          'runtimePlane',
        ],
      );
    });

    test('is not registered without the host opt-in', () async {
      final connection = await connectServer(
        store: store,
        httpClient: MockClient((request) async => http.Response('{}', 200)),
        environment: const {},
      );
      final tools = await connection.listTools(ListToolsRequest());

      expect(
        tools.tools.map((tool) => tool.name),
        isNot(contains('restage_experiment_apply')),
      );
    });
  });

  group('semantic routing', () {
    test(
      'retains complete canonical write identity across tool retries',
      () async {
        final requests = <Uint8List>[];
        Uint8List? retainedRequest;

        Future<CallToolResult> invoke({
          required String idempotencyKey,
          required int lifecycleOrdinal,
        }) async {
          final server = await connect(
            requests: requests,
            reply: (method, sent) {
              final bytes = sent.canonicalBytes;
              final rebound =
                  retainedRequest != null &&
                  sent.idempotencyKey == 'operator-retry-key' &&
                  base64Encode(retainedRequest!) != base64Encode(bytes);
              retainedRequest ??= bytes;
              return _refusal(
                method,
                rebound
                    ? ExperimentAuthoringRefusalCodeV1.replayRebinding
                    : ExperimentAuthoringRefusalCodeV1.capabilityUnavailable,
                sent.correlationId,
              );
            },
          );
          return server.connection.callTool(
            CallToolRequest(
              name: 'restage_experiment_apply',
              arguments: arguments(
                operation: 'pauseExperiment',
                idempotencyKey: idempotencyKey,
                payload: {
                  'expectedLifecycleOrdinal': lifecycleOrdinal,
                  'experimentId': 'experiment.checkout',
                },
              ),
            ),
          );
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
        expect(changed.isError, isNot(true));
        expect(
          ((changed.structuredContent!['result']!
                  as Map<String, Object?>)['refusal']
              as Map<String, Object?>)['code'],
          'replayRebinding',
        );
      },
    );

    test('reaches the route the declared operation names', () async {
      for (final operation in ExperimentAuthoringOperationV1.values) {
        final server = await connect();
        await server.connection.callTool(
          CallToolRequest(
            name: 'restage_experiment_apply',
            arguments: arguments(
              operation: operation.wireName,
              payload: _payloadFor(operation),
              idempotencyKey: operation.requiresIdempotencyKey
                  ? 'retry-key'
                  : null,
            ),
          ),
        );

        expect(server.methods, [
          operation.wireName,
        ], reason: '${operation.wireName} must reach only its own route');
      }
    });

    test(
      'reports a delivery-options refusal as a refusal, not as an error',
      () async {
        final server = await connect();

        final result = await server.connection.callTool(
          CallToolRequest(
            name: 'restage_experiment_apply',
            arguments: arguments(
              operation: 'readDeliveryOptions',
              payload: const {'experimentId': 'experiment.checkout'},
            ),
          ),
        );

        expect(result.isError, isNot(true));
        final structured = result.structuredContent!;
        expect(structured['outcome'], 'refused');
        expect(structured['operation'], 'readDeliveryOptions');
        final document = structured['result']! as Map<String, Object?>;
        expect(
          (document['refusal']! as Map<String, Object?>)['code'],
          'capabilityUnavailable',
        );
      },
    );

    test(
      'reports an activation audience conflict refusal with its typed locator',
      () async {
        final requests = <Uint8List>[];
        final server = await connect(
          requests: requests,
          reply: (method, sent) => _refusal(
            method,
            ExperimentAuthoringRefusalCodeV1.validationBlocked,
            sent.correlationId,
            locator: _audienceConflictLocator(),
          ),
        );

        final result = await server.connection.callTool(
          CallToolRequest(
            name: 'restage_experiment_apply',
            arguments: arguments(
              operation: 'activateDraft',
              idempotencyKey: 'activation-conflict-key',
              payload: _payloadFor(
                ExperimentAuthoringOperationV1.activateDraft,
              ),
            ),
          ),
        );

        expect(result.isError, isNot(true));
        final sent = ExperimentAuthoringRequestV1.fromCanonicalBytes(
          requests.single,
        );
        expect(sent.issueLocators, isTrue);
        final refusal =
            ((result.structuredContent!['result']!
                    as Map<String, Object?>)['refusal']!
                as Map<String, Object?>);
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
        expect(
          (result.content.single as TextContent).text,
          allOf(
            contains('experiment.sweden'),
            contains('audience.se.v1'),
            contains('audience.se.v2'),
          ),
        );
      },
    );

    test(
      'returns the sealed audience and exact arm publications for handover',
      () async {
        final requests = <Uint8List>[];
        final server = await connect(
          requests: requests,
          reply: (method, sent) => _deliveryOptionsAccepted(sent.correlationId),
        );

        final result = await server.connection.callTool(
          CallToolRequest(
            name: 'restage_experiment_apply',
            arguments: arguments(
              operation: 'readDeliveryOptions',
              payload: const {'experimentId': 'experiment.checkout'},
            ),
          ),
        );

        expect(result.isError, isNot(true));
        expect(server.methods, ['readDeliveryOptions']);
        final sent = ExperimentAuthoringRequestV1.fromCanonicalBytes(
          requests.single,
        );
        expect(sent.idempotencyKey, isNull);
        expect(sent.issueLocators, isTrue);
        expect(sent.payload, {'experimentId': 'experiment.checkout'});
        final resultJson =
            result.structuredContent!['result']! as Map<String, Object?>;
        final response = resultJson['response']! as Map<String, Object?>;
        expect(response['audienceLabel'], 'Sweden');
        expect(response['audienceRevisionId'], 'audience.sweden.v4');
        expect(response['surfaceSlug'], 'checkout');
        expect(
          [
            for (final rawArm in response['arms']! as List<Object?>)
              '${(rawArm! as Map<String, Object?>)['stableArmId']}:'
                  '${(rawArm as Map<String, Object?>)['publishedVersion']}',
          ],
          ['arm.control:4', 'arm.treatment:5'],
        );
        expect(
          (result.content.single as TextContent).text,
          allOf(
            contains('Sweden (audience.sweden.v4)'),
            contains('Control (arm.control) version 4'),
            contains('Treatment (arm.treatment) version 5'),
          ),
        );
      },
    );

    test(
      'renders a typed publication with equal revision and contract',
      () async {
        Uint8List? responseBytes;
        final server = await connect(
          reply: (method, sent) {
            final response = _deliveryOptionsAccepted(
              sent.correlationId,
              arms: _typedDeliveryArms,
            );
            responseBytes = response;
            return response;
          },
        );

        final result = await server.connection.callTool(
          CallToolRequest(
            name: 'restage_experiment_apply',
            arguments: arguments(
              operation: 'readDeliveryOptions',
              payload: const {'experimentId': 'experiment.checkout'},
            ),
          ),
        );

        expect(result.isError, isNot(true));
        expect(server.methods, ['readDeliveryOptions']);
        final resultJson =
            result.structuredContent!['result']! as Map<String, Object?>;
        expect(
          ExperimentAuthoringResultV1.fromJson(resultJson).canonicalBytes,
          orderedEquals(responseBytes!),
        );
        final response = resultJson['response']! as Map<String, Object?>;
        expect(response['arms'], _typedDeliveryArms);
        expect(
          (result.content.single as TextContent).text,
          allOf(
            contains(
              'Contract treatment (arm.contract) revision 4 (contract 4)',
            ),
            isNot(contains('Contract treatment (arm.contract) version 4')),
          ),
        );
      },
    );
  });

  group('payload discipline', () {
    test('delivery-options reads keep their nonmutating identity free of retry '
        'keys', () async {
      final requests = <Uint8List>[];
      for (var invocation = 0; invocation < 2; invocation++) {
        final server = await connect(requests: requests);
        await server.connection.callTool(
          CallToolRequest(
            name: 'restage_experiment_apply',
            arguments: arguments(
              operation: 'readDeliveryOptions',
              payload: const {'experimentId': 'experiment.checkout'},
            ),
          ),
        );
      }

      final decoded = [
        for (final bytes in requests)
          ExperimentAuthoringRequestV1.fromCanonicalBytes(bytes),
      ];
      expect(
        decoded.map((request) => request.idempotencyKey),
        everyElement(isNull),
      );
      expect(
        decoded.map((request) => request.correlationId).toSet(),
        hasLength(2),
      );
    });

    test('refuses a resolved serverDefault before any transport', () async {
      final server = await connect();

      final result = await server.connection.callTool(
        CallToolRequest(
          name: 'restage_experiment_apply',
          arguments: arguments(
            operation: 'replaceDraft',
            idempotencyKey: 'retry-key',
            payload: {
              ..._draftBinding,
              'replacement': {
                ..._emptyDraftChoices,
                'randomizedUnitSelection': const {
                  'kind': 'serverDefault',
                  'resolvedValue': 'installation',
                  'source': {
                    'kind': 'experimentRandomizedUnitDefaults',
                    'randomizedUnitKind': 'installation',
                  },
                },
              },
            },
          ),
        ),
      );

      expect(result.isError, isTrue);
      expect(server.methods, isEmpty);
    });

    test('accepts the bare serverDefault sentinel', () async {
      final server = await connect();

      await server.connection.callTool(
        CallToolRequest(
          name: 'restage_experiment_apply',
          arguments: arguments(
            operation: 'replaceDraft',
            idempotencyKey: 'retry-key',
            payload: {..._draftBinding, 'replacement': _emptyDraftChoices},
          ),
        ),
      );

      expect(server.methods, ['replaceDraft']);
    });

    test('refuses an unknown key inside the payload', () async {
      final server = await connect();

      final result = await server.connection.callTool(
        CallToolRequest(
          name: 'restage_experiment_apply',
          arguments: arguments(
            operation: 'readExperiment',
            payload: const {
              'experimentId': 'experiment.checkout',
              'unknownSelector': 'value',
            },
          ),
        ),
      );

      expect(result.isError, isTrue);
      expect(server.methods, isEmpty);
    });

    test('refuses an idempotency key on delivery-options', () async {
      final server = await connect();

      final result = await server.connection.callTool(
        CallToolRequest(
          name: 'restage_experiment_apply',
          arguments: arguments(
            operation: 'readDeliveryOptions',
            payload: const {'experimentId': 'experiment.checkout'},
            idempotencyKey: 'retry-key',
          ),
        ),
      );

      expect(result.isError, isTrue);
      expect(server.methods, isEmpty);
      expect(_errorText(result), contains('idempotencyKey'));
    });

    test('passes a list continuation cursor through untouched', () async {
      final requests = <Uint8List>[];
      final server = await connect(requests: requests);

      await server.connection.callTool(
        CallToolRequest(
          name: 'restage_experiment_apply',
          arguments: arguments(
            operation: 'listExperiments',
            payload: const {'pageCursor': 'experiment-page-2', 'pageSize': 50},
          ),
        ),
      );

      expect(server.methods, ['listExperiments']);
      final sent = ExperimentAuthoringRequestV1.fromCanonicalBytes(
        requests.single,
      );
      expect(sent.payload, {'pageCursor': 'experiment-page-2', 'pageSize': 50});
    });

    test('passes an exact discovery reference through untouched', () async {
      final requests = <Uint8List>[];
      final server = await connect(requests: requests);
      final reference = ExperimentExactSurfaceReferenceV1.fromJson({
        'kind': 'exactSurfaceReference',
        'surfaceId': '$kMintedSurfaceIdPrefix${List.filled(64, 'a').join()}',
        'surfaceRevisionId':
            '$kMintedSurfaceRevisionIdPrefix${List.filled(64, 'b').join()}',
      });
      final payload = <String, Object?>{
        'exactSurfaceReference': reference.toJson(),
        'pageSize': 1,
      };

      await server.connection.callTool(
        CallToolRequest(
          name: 'restage_experiment_apply',
          arguments: arguments(
            operation: 'discoverTargetsAndCapabilities',
            payload: payload,
          ),
        ),
      );

      expect(server.methods, ['discoverTargetsAndCapabilities']);
      final sent = ExperimentAuthoringRequestV1.fromCanonicalBytes(
        requests.single,
      );
      expect(sent.payload, payload);
    });

    test('refuses an unsupported operation before transport', () async {
      final server = await connect();

      final result = await server.connection.callTool(
        CallToolRequest(
          name: 'restage_experiment_apply',
          arguments: arguments(
            operation: 'inventExperimentOperation',
            payload: const <String, Object?>{},
          ),
        ),
      );

      expect(result.isError, isTrue);
      expect(server.methods, isEmpty);
    });

    test('leaks no credential when the stored endpoint is refused', () async {
      final leakHome = Directory.systemTemp.createTempSync(
        'restage_mcp_experiment_leak',
      );
      addTearDown(() => leakHome.deleteSync(recursive: true));
      final leakStore = FileCredentialStore('${leakHome.path}/credentials');
      await leakStore.write(
        const Credential(
          endpoint: 'http://99:SUPERSECRET@evil.example/',
          kind: CredentialKind.authKey,
          authToken: '99:SUPERSECRET',
        ),
      );
      final connection = await connectServer(
        store: leakStore,
        httpClient: MockClient((_) async => http.Response('[]', 200)),
      );

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_experiment_apply',
          arguments: arguments(
            operation: 'readExperiment',
            payload: const {'experimentId': 'experiment.checkout'},
          ),
        ),
      );

      expect(result.isError, isTrue);
      final text = (result.content.single as TextContent).text;
      expect(text, isNot(contains('SUPERSECRET')));
      expect(text, isNot(contains('evil.example')));
    });

    test('requires an idempotency key on a write', () async {
      final server = await connect();

      final result = await server.connection.callTool(
        CallToolRequest(
          name: 'restage_experiment_apply',
          arguments: arguments(
            operation: 'pauseExperiment',
            payload: const {
              'expectedLifecycleOrdinal': 8,
              'experimentId': 'experiment.checkout',
            },
          ),
        ),
      );

      expect(result.isError, isTrue);
      expect(server.methods, isEmpty);
      expect(_errorText(result), contains('idempotencyKey'));
    });
  });
}

/// The message an error result carries.
String _errorText(CallToolResult result) =>
    (result.content.single as TextContent).text;

const _draftBinding = <String, Object?>{
  'draftId': 'experiment-draft-checkout',
  'draftRevisionId': 'experiment-draft-checkout.v3',
  'expectedCas': 'draft-cas-3',
};

const _emptyDraftChoices = <String, Object?>{
  'analysisSelection': {'kind': 'unselected'},
  'arms': <Object?>[],
  'assignmentAudienceSelection': {'kind': 'unselected'},
  'assignmentEligibilitySelection': {'kind': 'unselected'},
  'description': '',
  'diagnosticBindingIds': <Object?>[],
  'guardrails': <Object?>[],
  'kind': 'experimentDraftChoices',
  'label': '',
  'layerHoldoutIds': <Object?>[],
  'memberHoldouts': <Object?>[],
  'memberNoTreatment': {'kind': 'unselected'},
  'metricBindings': <Object?>[],
  'primaryBindingSelection': {'kind': 'unselected'},
  'randomizedUnitSelection': {'kind': 'serverDefault'},
  'rootSurfaceSelection': {'kind': 'unselected'},
  'subjectSelection': {'kind': 'subjectless'},
};

Map<String, Object?> _payloadFor(ExperimentAuthoringOperationV1 operation) =>
    switch (operation) {
      ExperimentAuthoringOperationV1.discoverTargetsAndCapabilities => const {
        'pageSize': 100,
      },
      ExperimentAuthoringOperationV1.openDraft => const {},
      ExperimentAuthoringOperationV1.readDraft ||
      ExperimentAuthoringOperationV1.validateDraft ||
      ExperimentAuthoringOperationV1.reviewDraft => _draftBinding,
      ExperimentAuthoringOperationV1.readDeliveryOptions => const {
        'experimentId': 'experiment.checkout',
      },
      ExperimentAuthoringOperationV1.resolveDraft => {
        'draftId': _draftBinding['draftId'],
      },
      ExperimentAuthoringOperationV1.replaceDraft => {
        ..._draftBinding,
        'replacement': _emptyDraftChoices,
      },
      ExperimentAuthoringOperationV1.copyDraftToTarget => {
        'sourceDraft': _draftBinding,
        'sourceTarget': const {
          'appId': 23,
          'environmentTargetId': 41,
          'kind': 'targetCoordinate',
          'namedEnvironmentId': 43,
          'organizationId': 11,
          'runtimePlane': 'sandbox',
          'schemaVersion': kMeasurementSchemaVersion,
        },
      },
      ExperimentAuthoringOperationV1.activateDraft => {
        ..._draftBinding,
        'reviewReference': {
          'kind': 'experimentReviewReference',
          'recordDigest': 'a' * 64,
          'reviewId': 'review.checkout.v1',
          'schemaVersion': kMeasurementSchemaVersion,
        },
      },
      ExperimentAuthoringOperationV1.pauseExperiment ||
      ExperimentAuthoringOperationV1.resumeExperiment ||
      ExperimentAuthoringOperationV1.concludeExperiment => const {
        'expectedLifecycleOrdinal': 8,
        'experimentId': 'experiment.checkout',
      },
      ExperimentAuthoringOperationV1.listExperiments => const {'pageSize': 50},
      ExperimentAuthoringOperationV1.readExperiment => const {
        'experimentId': 'experiment.checkout',
      },
      ExperimentAuthoringOperationV1.readExperimentResults => {
        'activationOrdinal': 7,
        'experimentId': 'experiment.checkout',
        'resultDigest': 'b' * 64,
      },
      ExperimentAuthoringOperationV1.setExperimentArchived => const {
        'archived': true,
        'expectedControlPlaneOrdinal': 8,
        'experimentId': 'experiment.checkout',
      },
      ExperimentAuthoringOperationV1.registerBuildCapabilities => {
        'appBuildOrdinal': 412,
        'contextSchemaRef': {
          'contextSchemaId': 'assignment.context.checkout',
          'revisionId': 'assignment.context.checkout.v2',
          'semanticDigest': 'c' * 64,
        },
        'platform': 'ios',
        'sdkApiLevel': 3,
      },
      ExperimentAuthoringOperationV1.readExperimentReadiness => const {
        'pageSize': 100,
      },
    };

Uint8List _refusal(
  String operationWireName,
  ExperimentAuthoringRefusalCodeV1 code,
  String correlationId, {
  Map<String, Object?>? locator,
}) => ExperimentAuthoringResultV1.fromJson({
  'correlationId': correlationId,
  'kind': 'refused',
  'operation': operationWireName,
  'refusal': {
    'code': code.wireName,
    'kind': 'experimentAuthoringRefusal',
    if (locator != null) 'locator': locator,
    'messageKey': 'experiment.authoring.${code.wireName}',
    'retryable':
        code == ExperimentAuthoringRefusalCodeV1.backendUnavailable ||
        code == ExperimentAuthoringRefusalCodeV1.transportUnknownOutcome,
    'schemaVersion': kMeasurementSchemaVersion,
  },
  'schemaVersion': kMeasurementSchemaVersion,
}).canonicalBytes;

Map<String, Object?> _audienceConflictLocator() => {
  'conflictingAudienceRef': _audienceRef('audience.se.v1'),
  'conflictingExperimentId': 'experiment.sweden',
  'kind': 'audienceConflict',
  'proposedAudienceRef': _audienceRef('audience.se.v2'),
};

Map<String, Object?> _audienceRef(String revisionId) => {
  'assignmentAudiencePolicyId': 'audience.se',
  'revisionId': revisionId,
  'semanticHash': 'b' * 64,
};

Uint8List _deliveryOptionsAccepted(
  String correlationId, {
  List<Map<String, Object?>>? arms,
}) => ExperimentAuthoringResultV1.fromJson({
  'correlationId': correlationId,
  'kind': 'accepted',
  'operation': 'readDeliveryOptions',
  'response': {
    'arms':
        arms ??
        [
          {
            'kind': 'experimentArmDelivery',
            'label': 'Control',
            'publishedVersion': 4,
            'stableArmId': 'arm.control',
          },
          {
            'kind': 'experimentArmDelivery',
            'label': 'Treatment',
            'publishedVersion': 5,
            'stableArmId': 'arm.treatment',
          },
        ],
    'audienceLabel': 'Sweden',
    'audienceRevisionId': 'audience.sweden.v4',
    'experimentId': 'experiment.checkout',
    'kind': 'experimentDeliveryOptionsView',
    'schemaVersion': kMeasurementSchemaVersion,
    'surfaceSlug': 'checkout',
    'surfaceType': 'paywall',
    'target': const {
      'appId': 23,
      'environmentTargetId': 31,
      'kind': 'targetCoordinate',
      'namedEnvironmentId': 37,
      'organizationId': 11,
      'runtimePlane': 'live',
      'schemaVersion': kMeasurementSchemaVersion,
    },
  },
  'schemaVersion': kMeasurementSchemaVersion,
}).canonicalBytes;

String _wire(List<int> bytes) => "decode('${base64Encode(bytes)}', 'base64')";

Uint8List _bytes(String wire) => Uint8List.fromList(
  base64Decode(
    wire.substring("decode('".length, wire.length - "', 'base64')".length),
  ),
);

http.Response? _targetDirectory(String method) => switch (method) {
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
