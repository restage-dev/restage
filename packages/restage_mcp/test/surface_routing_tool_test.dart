import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/api.dart';
import 'package:restage_mcp/src/surface_routing_tool.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    hide RuntimePlane;
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    as measurement
    show RuntimePlane;
import 'package:test/test.dart';

import '_support/harness.dart';

/// The wire form the service reads byte columns as.
String wire(List<int> bytes) => "decode('${base64Encode(bytes)}', 'base64')";

final _diagnosticsTarget = TargetCoordinate(
  organizationId: OrganizationId(11),
  appId: ApplicationId(12),
  environmentTargetId: EnvironmentTargetId(31),
  namedEnvironmentId: NamedEnvironmentId(32),
  runtimePlane: measurement.RuntimePlane.sandbox,
);

MeasurementDeliveryDiagnosticsV1 diagnosticsRead({
  MeasurementDeliveryDiagnosticsSectionV1? servedDefaults,
  MeasurementDeliveryDiagnosticsSectionV1? recordedRefusals,
}) => MeasurementDeliveryDiagnosticsV1(
  target: _diagnosticsTarget,
  surfaceType: MeasurementDeliveryDiagnosticsSurfaceTypeV1.onboarding,
  surfaceSlug: 'welcome',
  contractVersion: 3,
  windowStartDayUtc: DateTime.utc(2026, 9, 1).microsecondsSinceEpoch,
  windowEndDayExclusiveUtc: DateTime.utc(2026, 9, 3).microsecondsSinceEpoch,
  disclosureFloor: measurementDeliveryDiagnosticsDisclosureFloor,
  servedDefaults:
      servedDefaults ??
      MeasurementDeliveryDiagnosticsSectionV1(
        population: MeasurementDeliveryDiagnosticsPopulationV1
            .servedDefaultPresentations,
        coverage: MeasurementDeliveryDiagnosticsCoverageV1
            .observedAdmittedPresentations,
        availability:
            MeasurementDeliveryDiagnosticsAvailabilityV1.partiallyHeld,
        reasons: [
          MeasurementDeliveryDiagnosticsReasonCountV1(
            reason: 'frozen',
            observedCount: 5,
          ),
          MeasurementDeliveryDiagnosticsReasonCountV1(reason: 'futureDefault'),
        ],
      ),
  recordedRefusals:
      recordedRefusals ??
      MeasurementDeliveryDiagnosticsSectionV1(
        population:
            MeasurementDeliveryDiagnosticsPopulationV1.recordedServerRefusals,
        coverage: MeasurementDeliveryDiagnosticsCoverageV1
            .observedRecordedServerRefusals,
        availability: MeasurementDeliveryDiagnosticsAvailabilityV1.held,
        reasons: [
          MeasurementDeliveryDiagnosticsReasonCountV1(
            reason: 'audienceUndecided',
          ),
        ],
      ),
);

void main() {
  late Directory home;
  late FileCredentialStore store;

  setUp(() async {
    home = Directory.systemTemp.createTempSync('restage_mcp_routing');
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

  /// A client that answers one routing call with [response] and records the
  /// request body and path it saw.
  http.Client routingClient(
    Map<String, Object?> response, {
    void Function(Map<String, Object?> body, Uri url)? onCall,
    int status = 200,
    String? rawBody,
  }) => _withTargets((request) async {
    final body = jsonDecode(request.body) as Map<String, Object?>;
    onCall?.call(body, request.url);
    return http.Response(rawBody ?? jsonEncode(response), status);
  });

  Map<String, Object?> surfaceTarget() => {
    'organizationId': 11,
    'projectSlug': 'checkout',
    'appSlug': 'app',
    'surfaceType': 'onboarding',
    'surfaceSlug': 'welcome',
    'environmentTargetId': 31,
  };

  Map<String, Object?> listTarget() => {
    'organizationId': 11,
    'projectSlug': 'checkout',
    'appSlug': 'app',
    'environmentTargetId': 31,
  };

  group('the tools are advertised', () {
    test('a default server lists every routing tool', () async {
      final connection = await connectServer(
        store: store,
        httpClient: _withTargets((_) async => http.Response('{}', 200)),
        environment: const {},
      );

      final tools = await connection.listTools(ListToolsRequest());
      expect(
        tools.tools.map((t) => t.name),
        containsAll([
          'restage_list_routing_audiences',
          'restage_routing_audience_usage',
          'restage_read_routing',
          'restage_read_delivery_diagnostics',
          'restage_read_routing_revision',
          'restage_preview_routing',
          'restage_publish_routing',
          'restage_rollback_route',
        ]),
      );
    });

    test('no tool offers to author a document or an audience', () async {
      final connection = await connectServer(
        store: store,
        httpClient: _withTargets((_) async => http.Response('{}', 200)),
        environment: const {},
      );

      final tools = await connection.listTools(ListToolsRequest());
      final names = tools.tools.map((t) => t.name).toList();
      expect(names, isNot(contains('restage_save_routing_audience')));
      expect(names, isNot(contains('restage_author_routing_document')));
    });
  });

  group('target propagation', () {
    test(
      'a read carries the complete target to the routing endpoint',
      () async {
        Map<String, Object?>? sent;
        Uri? seenUrl;
        final connection = await connectServer(
          store: store,
          httpClient: routingClient(
            {
              'empty': false,
              'documentBytes': wire(const [1, 2]),
              'revisionOrdinal': 4,
            },
            onCall: (body, url) {
              sent = body;
              seenUrl = url;
            },
          ),
        );

        final result = await connection.callTool(
          CallToolRequest(
            name: 'restage_read_routing',
            arguments: {...surfaceTarget(), 'contractVersion': 3},
          ),
        );

        expect(result.isError, isNot(true));
        expect(seenUrl!.path, endsWith('/surfaceRouting'));
        expect(sent!['method'], 'readRouting');
        expect(sent!['projectSlug'], 'checkout');
        expect(sent!['appSlug'], 'app');
        expect(sent!['surfaceType'], 'onboarding');
        expect(sent!['surfaceSlug'], 'welcome');
        expect(sent!['environmentId'], 31);
        expect(sent!['organizationId'], 11);
        expect(sent!['contractVersion'], 3);
      },
    );

    test('a publish carries the same complete target', () async {
      Map<String, Object?>? sent;
      final connection = await connectServer(
        store: store,
        httpClient: routingClient({
          'outcome': 'applied',
          'revisionOrdinal': 5,
        }, onCall: (body, _) => sent = body),
      );

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_publish_routing',
          arguments: {
            ...surfaceTarget(),
            'documentBase64': base64Encode(const [9, 9, 9]),
            'expectedRevisionOrdinal': 4,
          },
        ),
      );

      expect(result.isError, isNot(true));
      expect(sent!['method'], 'publishRouting');
      expect(sent!['surfaceType'], 'onboarding');
      expect(sent!['surfaceSlug'], 'welcome');
      expect(sent!['environmentId'], 31);
      expect(sent!['organizationId'], 11);
    });
  });

  group('delivery diagnostics', () {
    test('carries the exact target and whole UTC window to the authorized '
        'routing read', () async {
      Map<String, Object?>? sent;
      Uri? seenUrl;
      final read = diagnosticsRead();
      final connection = await connectServer(
        store: store,
        httpClient: routingClient(
          const <String, Object?>{},
          rawBody: jsonEncode(wire(read.canonicalBytes)),
          onCall: (body, url) {
            sent = body;
            seenUrl = url;
          },
        ),
      );

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_read_delivery_diagnostics',
          arguments: {
            ...surfaceTarget(),
            'contractVersion': 3,
            'windowStartDateUtc': '2026-09-01',
            'windowEndDateExclusiveUtc': '2026-09-03',
          },
        ),
      );

      expect(result.isError, isNot(true));
      expect(seenUrl!.path, endsWith('/surfaceRouting'));
      expect(sent!['method'], 'readDeliveryDiagnostics');
      expect(sent!['projectSlug'], 'checkout');
      expect(sent!['appSlug'], 'app');
      expect(sent!['surfaceType'], 'onboarding');
      expect(sent!['surfaceSlug'], 'welcome');
      expect(sent!['environmentId'], 31);
      expect(sent!['organizationId'], 11);
      expect(sent!['contractVersion'], 3);
      expect(
        sent!['windowStartDayUtc'],
        DateTime.utc(2026, 9, 1).microsecondsSinceEpoch,
      );
      expect(
        sent!['windowEndDayExclusiveUtc'],
        DateTime.utc(2026, 9, 3).microsecondsSinceEpoch,
      );
      final served =
          result.structuredContent!['servedDefaults']! as Map<String, Object?>;
      final refusals =
          result.structuredContent!['recordedRefusals']!
              as Map<String, Object?>;
      expect(served['population'], 'servedDefaultPresentations');
      expect(served['coverage'], 'observedAdmittedPresentations');
      expect(served['availability'], 'partiallyHeld');
      expect(served['reasons'], [
        {'reason': 'frozen', 'observedCount': 5},
        {'reason': 'futureDefault'},
      ]);
      expect(refusals['population'], 'recordedServerRefusals');
      expect(refusals['coverage'], 'observedRecordedServerRefusals');
      expect(refusals['availability'], 'held');
      expect(refusals['reasons'], [
        {'reason': 'audienceUndecided'},
      ]);
    });

    test('keeps unavailable and observed-empty disclosed sections distinct '
        'without a zero', () async {
      final read = diagnosticsRead(
        servedDefaults: MeasurementDeliveryDiagnosticsSectionV1(
          population: MeasurementDeliveryDiagnosticsPopulationV1
              .servedDefaultPresentations,
          coverage: MeasurementDeliveryDiagnosticsCoverageV1
              .observedAdmittedPresentations,
          availability:
              MeasurementDeliveryDiagnosticsAvailabilityV1.unavailable,
          reasons: const [],
        ),
        recordedRefusals: MeasurementDeliveryDiagnosticsSectionV1(
          population:
              MeasurementDeliveryDiagnosticsPopulationV1.recordedServerRefusals,
          coverage: MeasurementDeliveryDiagnosticsCoverageV1
              .observedRecordedServerRefusals,
          availability: MeasurementDeliveryDiagnosticsAvailabilityV1.disclosed,
          reasons: const [],
        ),
      );
      final connection = await connectServer(
        store: store,
        httpClient: routingClient(
          const <String, Object?>{},
          rawBody: jsonEncode(wire(read.canonicalBytes)),
        ),
      );

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_read_delivery_diagnostics',
          arguments: {
            ...surfaceTarget(),
            'windowStartDateUtc': '2026-09-01',
            'windowEndDateExclusiveUtc': '2026-09-03',
          },
        ),
      );

      expect(result.isError, isNot(true));
      final served =
          result.structuredContent!['servedDefaults']! as Map<String, Object?>;
      final refusals =
          result.structuredContent!['recordedRefusals']!
              as Map<String, Object?>;
      expect(served['availability'], 'unavailable');
      expect(served['reasons'], isEmpty);
      expect(refusals['availability'], 'disclosed');
      expect(refusals['reasons'], isEmpty);
      expect(
        (result.content.single as TextContent).text,
        isNot(contains(': 0')),
      );
    });

    test(
      'refuses an invalid or over-retention date window before a read',
      () async {
        var calls = 0;
        final connection = await connectServer(
          store: store,
          httpClient: _withTargets((_) async {
            calls++;
            return http.Response('{}', 200);
          }),
        );

        final invalidDate = await connection.callTool(
          CallToolRequest(
            name: 'restage_read_delivery_diagnostics',
            arguments: {
              ...surfaceTarget(),
              'windowStartDateUtc': '2026-02-30',
              'windowEndDateExclusiveUtc': '2026-03-02',
            },
          ),
        );
        final nonExactDate = await connection.callTool(
          CallToolRequest(
            name: 'restage_read_delivery_diagnostics',
            arguments: {
              ...surfaceTarget(),
              'windowStartDateUtc': '2026-09-01\n',
              'windowEndDateExclusiveUtc': '2026-09-03',
            },
          ),
        );
        final tooLong = await connection.callTool(
          CallToolRequest(
            name: 'restage_read_delivery_diagnostics',
            arguments: {
              ...surfaceTarget(),
              'windowStartDateUtc': '2026-01-01',
              'windowEndDateExclusiveUtc': '2026-04-02',
            },
          ),
        );

        expect(invalidDate.isError, isTrue);
        expect(nonExactDate.isError, isTrue);
        expect(tooLong.isError, isTrue);
        expect(calls, 0);
        expect(
          (tooLong.content.single as TextContent).text,
          contains('no more than 90 days'),
        );
      },
    );

    test(
      'propagates authorization failure from the diagnostics read',
      () async {
        var calls = 0;
        final connection = await connectServer(
          store: store,
          httpClient: _withTargets((_) async {
            calls++;
            return http.Response(
              jsonEncode({
                'className': 'UnauthorizedException',
                'data': {
                  '__className__': 'UnauthorizedException',
                  'resource': 'surfaceRouting',
                },
              }),
              403,
            );
          }),
        );

        final result = await connection.callTool(
          CallToolRequest(
            name: 'restage_read_delivery_diagnostics',
            arguments: {
              ...surfaceTarget(),
              'windowStartDateUtc': '2026-09-01',
              'windowEndDateExclusiveUtc': '2026-09-03',
            },
          ),
        );

        expect(result.isError, isTrue);
        expect(calls, 1);
        expect(
          (result.content.single as TextContent).text,
          contains('Your role in this organization does not allow this'),
        );
      },
    );
  });

  group('the document travels whole and unread', () {
    test(
      'every byte of a document naming both branches reaches the service',
      () async {
        final document = utf8.encode(
          '{"routes":[{"primary":11,"remainder":12}]}',
        );
        Map<String, Object?>? sent;
        final connection = await connectServer(
          store: store,
          httpClient: routingClient({
            'outcome': 'applied',
            'revisionOrdinal': 1,
          }, onCall: (body, _) => sent = body),
        );

        final result = await connection.callTool(
          CallToolRequest(
            name: 'restage_publish_routing',
            arguments: {
              ...surfaceTarget(),
              'documentBase64': base64Encode(document),
              'expectNoRevision': true,
            },
          ),
        );

        expect(result.isError, isNot(true));
        expect(sent!['documentBytes'], wire(document));
      },
    );

    test('a read returns the stored bytes as base64 unchanged', () async {
      final stored = List<int>.generate(64, (i) => i);
      final connection = await connectServer(
        store: store,
        httpClient: routingClient({
          'empty': false,
          'documentBytes': wire(stored),
          'revisionOrdinal': 7,
        }),
      );

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_read_routing',
          arguments: surfaceTarget(),
        ),
      );

      expect(result.isError, isNot(true));
      expect(result.structuredContent!['documentBase64'], base64Encode(stored));
      expect(result.structuredContent!['revisionOrdinal'], 7);
    });

    test('a preview reports the service classification and evaluates no rule '
        'locally', () async {
      // The document is not a routing document and the context carries nothing
      // a rule could read. A tool that evaluated locally could not report a
      // match; this one reports what the service said.
      Map<String, Object?>? sent;
      final connection = await connectServer(
        store: store,
        httpClient: routingClient({
          'rules': [
            {'routeId': 'r1', 'matches': true, 'reason': 'matched'},
            {'routeId': 'r2', 'matches': false, 'reason': 'notMatched'},
          ],
          'deliveryBytes': wire(const [7, 7]),
          'usesActivePointer': true,
        }, onCall: (body, _) => sent = body),
      );

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_preview_routing',
          arguments: {
            ...surfaceTarget(),
            'documentBase64': base64Encode(utf8.encode('not-a-doc')),
            'schemaBase64': base64Encode(const [1]),
            'requestContextBase64': base64Encode(const [2]),
            'audiencesBase64': [
              base64Encode(const [3]),
              base64Encode(const [4]),
            ],
          },
        ),
      );

      expect(result.isError, isNot(true));
      expect(sent!['method'], 'previewRouting');
      expect(sent!['audienceBytes'], [
        wire(const [3]),
        wire(const [4]),
      ]);
      expect(sent!['requestContextBytes'], wire(const [2]));
      final rules = result.structuredContent!['rules']! as List<Object?>;
      expect((rules.first! as Map)['matches'], isTrue);
      expect((rules.last! as Map)['reason'], 'notMatched');
      expect(result.structuredContent!['usesActivePointer'], isTrue);
    });
  });

  group('the compare-and-set precondition', () {
    test('the expected ordinal reaches the service exactly', () async {
      Map<String, Object?>? sent;
      final connection = await connectServer(
        store: store,
        httpClient: routingClient({
          'outcome': 'applied',
          'revisionOrdinal': 31,
        }, onCall: (body, _) => sent = body),
      );

      await connection.callTool(
        CallToolRequest(
          name: 'restage_publish_routing',
          arguments: {
            ...surfaceTarget(),
            'documentBase64': base64Encode(const [1]),
            'expectedRevisionOrdinal': 30,
          },
        ),
      );

      expect(sent!['expectedRevisionOrdinal'], 30);
    });

    test('expectNoRevision sends a null precondition', () async {
      Map<String, Object?>? sent;
      final connection = await connectServer(
        store: store,
        httpClient: routingClient({
          'outcome': 'applied',
          'revisionOrdinal': 1,
        }, onCall: (body, _) => sent = body),
      );

      await connection.callTool(
        CallToolRequest(
          name: 'restage_publish_routing',
          arguments: {
            ...surfaceTarget(),
            'documentBase64': base64Encode(const [1]),
            'expectNoRevision': true,
          },
        ),
      );

      expect(sent!.containsKey('expectedRevisionOrdinal'), isTrue);
      expect(sent!['expectedRevisionOrdinal'], isNull);
    });

    test('neither precondition is refused before any call', () async {
      var reached = false;
      final connection = await connectServer(
        store: store,
        httpClient: _withTargets((_) async {
          reached = true;
          return http.Response('{}', 200);
        }),
      );

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_publish_routing',
          arguments: {
            ...surfaceTarget(),
            'documentBase64': base64Encode(const [1]),
          },
        ),
      );

      expect(result.isError, isTrue);
      expect(reached, isFalse);
      expect(
        (result.content.single as TextContent).text,
        contains('exactly one'),
      );
    });

    test('both preconditions together are refused before any call', () async {
      var reached = false;
      final connection = await connectServer(
        store: store,
        httpClient: _withTargets((_) async {
          reached = true;
          return http.Response('{}', 200);
        }),
      );

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_publish_routing',
          arguments: {
            ...surfaceTarget(),
            'documentBase64': base64Encode(const [1]),
            'expectedRevisionOrdinal': 4,
            'expectNoRevision': true,
          },
        ),
      );

      expect(result.isError, isTrue);
      expect(reached, isFalse);
    });

    test('a rollback carries the route, the prior revision and the '
        'precondition', () async {
      Map<String, Object?>? sent;
      final connection = await connectServer(
        store: store,
        httpClient: routingClient({
          'outcome': 'applied',
          'revisionOrdinal': 9,
        }, onCall: (body, _) => sent = body),
      );

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_rollback_route',
          arguments: {
            ...surfaceTarget(),
            'routeId': 'welcome-route',
            'priorRevisionOrdinal': 6,
            'expectedRevisionOrdinal': 8,
          },
        ),
      );

      expect(result.isError, isNot(true));
      expect(sent!['method'], 'rollbackRoute');
      expect(sent!['routeId'], 'welcome-route');
      expect(sent!['priorRevisionOrdinal'], 6);
      expect(sent!['expectedRevisionOrdinal'], 8);
    });
  });

  group('the retry identity', () {
    test('a generated operation id is a canonical version 4 UUID', () async {
      Map<String, Object?>? sent;
      final connection = await connectServer(
        store: store,
        httpClient: routingClient({
          'outcome': 'applied',
          'revisionOrdinal': 1,
        }, onCall: (body, _) => sent = body),
      );

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_publish_routing',
          arguments: {
            ...surfaceTarget(),
            'documentBase64': base64Encode(const [1]),
            'expectNoRevision': true,
          },
        ),
      );

      expect(
        sent!['operationId']! as String,
        matches(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}'
          r'-[0-9a-f]{12}$',
        ),
      );
      expect(result.structuredContent!['operationId'], sent!['operationId']);
    });

    test('a supplied operation id is sent unchanged', () async {
      const supplied = '3f2504e0-4f89-41d3-9a0c-0305e82c3301';
      Map<String, Object?>? sent;
      final connection = await connectServer(
        store: store,
        httpClient: routingClient({
          'outcome': 'replayed',
          'revisionOrdinal': 3,
        }, onCall: (body, _) => sent = body),
      );

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_publish_routing',
          arguments: {
            ...surfaceTarget(),
            'documentBase64': base64Encode(const [1]),
            'expectNoRevision': true,
            'operationId': supplied,
          },
        ),
      );

      expect(sent!['operationId'], supplied);
      expect(result.structuredContent!['outcome'], 'replayed');
    });

    test('an operation id that is not a version 4 UUID is refused before any '
        'call', () async {
      var reached = false;
      final connection = await connectServer(
        store: store,
        httpClient: _withTargets((_) async {
          reached = true;
          return http.Response('{}', 200);
        }),
      );

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_publish_routing',
          arguments: {
            ...surfaceTarget(),
            'documentBase64': base64Encode(const [1]),
            'expectNoRevision': true,
            'operationId': 'publish-1',
          },
        ),
      );

      expect(result.isError, isTrue);
      expect(reached, isFalse);
      expect(
        (result.content.single as TextContent).text,
        contains('version 4 UUID'),
      );
    });

    test('the generator does not repeat itself', () {
      final minted = {for (var i = 0; i < 200; i++) newRoutingOperationId()};
      expect(minted, hasLength(200));
    });
  });

  group('page cursors', () {
    test('a cursor and page size reach the service and the next cursor is '
        'returned', () async {
      Map<String, Object?>? sent;
      final connection = await connectServer(
        store: store,
        httpClient: routingClient({
          'audiences': [
            {
              'authorityId': 'a1',
              'revisionId': 'r1',
              'revisionOrdinal': 1,
              'label': 'Trial users in Sweden',
              'description': 'Started a trial, has not converted.',
            },
          ],
          'lastPage': false,
          'nextCursor': 'page-2',
        }, onCall: (body, _) => sent = body),
      );

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_list_routing_audiences',
          arguments: {...listTarget(), 'pageSize': 25, 'cursor': 'page-1'},
        ),
      );

      expect(result.isError, isNot(true));
      expect(sent!['method'], 'listAudiences');
      expect(sent!['pageSize'], 25);
      expect(sent!['cursor'], 'page-1');
      expect(result.structuredContent!['nextCursor'], 'page-2');
      final first =
          (result.structuredContent!['audiences']! as List<Object?>).single!
              as Map<String, Object?>;
      expect(first['label'], 'Trial users in Sweden');
      expect(first['description'], 'Started a trial, has not converted.');
    });

    test(
      'a page size outside the accepted range is refused before any call',
      () async {
        var reached = false;
        final connection = await connectServer(
          store: store,
          httpClient: _withTargets((_) async {
            reached = true;
            return http.Response('{}', 200);
          }),
        );

        final result = await connection.callTool(
          CallToolRequest(
            name: 'restage_list_routing_audiences',
            arguments: {...listTarget(), 'pageSize': 500},
          ),
        );

        expect(result.isError, isTrue);
        expect(reached, isFalse);
      },
    );

    test('audience usage returns both arms with their lifecycle', () async {
      Map<String, Object?>? sent;
      final connection = await connectServer(
        store: store,
        httpClient: routingClient({
          'experiments': [
            {
              'ownerAuthorityKind': 'experimentDesign',
              'ownerAuthorityId': 'x1',
              'ownerRevisionId': 'xr1',
              'lifecycle': 'concluded',
            },
          ],
          'routing': [
            {
              'surfaceType': 'onboarding',
              'surfaceSlug': 'welcome',
              'contractVersion': null,
              'revisionOrdinal': 3,
              'routeIds': ['r1', 'r2'],
              'lifecycle': 'active',
            },
          ],
          'lastPage': true,
          'nextCursor': null,
        }, onCall: (body, _) => sent = body),
      );

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_routing_audience_usage',
          arguments: {...listTarget(), 'audienceRevisionId': 'aud-rev-1'},
        ),
      );

      expect(result.isError, isNot(true));
      expect(sent!['audienceRevisionId'], 'aud-rev-1');
      final experiments =
          result.structuredContent!['experiments']! as List<Object?>;
      expect((experiments.single! as Map)['lifecycle'], 'concluded');
      final routing = result.structuredContent!['routing']! as List<Object?>;
      expect((routing.single! as Map)['routeIds'], ['r1', 'r2']);
      expect((routing.single! as Map)['lifecycle'], 'active');
    });
  });

  group('refusals', () {
    test(
      'a conflict is reported with both ordinals and makes one call',
      () async {
        var calls = 0;
        final connection = await connectServer(
          store: store,
          httpClient: _withTargets((_) async {
            calls++;
            return http.Response(
              jsonEncode({
                'className': 'SurfaceRoutingConflictException',
                'data': {
                  '__className__': 'SurfaceRoutingConflictException',
                  'expectedRevisionOrdinal': 4,
                  'actualRevisionOrdinal': 6,
                },
              }),
              400,
            );
          }),
        );

        final result = await connection.callTool(
          CallToolRequest(
            name: 'restage_publish_routing',
            arguments: {
              ...surfaceTarget(),
              'documentBase64': base64Encode(const [1]),
              'expectedRevisionOrdinal': 4,
            },
          ),
        );

        expect(result.isError, isTrue);
        expect(calls, 1);
        final text = (result.content.single as TextContent).text;
        expect(text, contains('expected 4'));
        expect(text, contains('stored revision is 6'));
      },
    );

    test('a service refusal is surfaced in the service term', () async {
      final connection = await connectServer(
        store: store,
        httpClient: _withTargets(
          (_) async => http.Response(
            jsonEncode({
              'className': 'SurfaceRoutingRejectedException',
              'data': {
                '__className__': 'SurfaceRoutingRejectedException',
                'reason': 'invalid_destination',
              },
            }),
            400,
          ),
        ),
      );

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_publish_routing',
          arguments: {
            ...surfaceTarget(),
            'documentBase64': base64Encode(const [1]),
            'expectNoRevision': true,
          },
        ),
      );

      expect(result.isError, isTrue);
      expect(
        (result.content.single as TextContent).text,
        contains('invalid_destination'),
      );
    });

    test('an identity the service will not admit to operator configuration '
        'is refused, and the refusal is final', () async {
      // Operator authorization is the service's decision. The tool makes one
      // call, reports what it is told, and neither falls back nor retries.
      var calls = 0;
      final connection = await connectServer(
        store: store,
        httpClient: _withTargets((_) async {
          calls++;
          return http.Response(
            jsonEncode({
              'className': 'UnauthorizedException',
              'data': {
                '__className__': 'UnauthorizedException',
                'resource': 'surfaceRouting',
              },
            }),
            403,
          );
        }),
      );

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_read_routing',
          arguments: surfaceTarget(),
        ),
      );

      expect(result.isError, isTrue);
      expect(calls, 1);
      expect(
        (result.content.single as TextContent).text,
        contains('Your role in this organization does not allow this'),
      );
      expect(result.structuredContent, isNull);
    });

    test(
      'a mutation refused for the same reason also makes one call',
      () async {
        var calls = 0;
        final connection = await connectServer(
          store: store,
          httpClient: _withTargets((_) async {
            calls++;
            return http.Response(
              jsonEncode({
                'className': 'UnauthorizedException',
                'data': {
                  '__className__': 'UnauthorizedException',
                  'resource': 'surfaceRouting',
                },
              }),
              403,
            );
          }),
        );

        final result = await connection.callTool(
          CallToolRequest(
            name: 'restage_publish_routing',
            arguments: {
              ...surfaceTarget(),
              'documentBase64': base64Encode(const [1]),
              'expectNoRevision': true,
            },
          ),
        );

        expect(result.isError, isTrue);
        expect(calls, 1);
      },
    );

    test(
      'a document that is not canonical base64 is refused before any call',
      () async {
        var reached = false;
        final connection = await connectServer(
          store: store,
          httpClient: _withTargets((_) async {
            reached = true;
            return http.Response('{}', 200);
          }),
        );

        for (final bad in <String>['', 'not base64!', 'AA==AA']) {
          final result = await connection.callTool(
            CallToolRequest(
              name: 'restage_publish_routing',
              arguments: {
                ...surfaceTarget(),
                'documentBase64': bad,
                'expectNoRevision': true,
              },
            ),
          );
          expect(result.isError, isTrue, reason: 'rejects "$bad"');
        }
        expect(reached, isFalse);
      },
    );

    test('a malformed service response does not reach the client as a stack '
        'trace', () async {
      final connection = await connectServer(
        store: store,
        httpClient: routingClient(const {}, rawBody: '["not","an","object"]'),
      );

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_read_routing',
          arguments: surfaceTarget(),
        ),
      );

      expect(result.isError, isTrue);
      final text = (result.content.single as TextContent).text;
      expect(text, contains('unexpected error'));
      expect(text, isNot(contains('#0')));
    });
  });

  group('reading one earlier revision', () {
    test('the read carries the complete target and the ordinal', () async {
      Map<String, Object?>? sent;
      Uri? seenUrl;
      final connection = await connectServer(
        store: store,
        httpClient: routingClient(
          {
            'revisionOrdinal': 4,
            'documentBytes': wire(const [1, 2, 3]),
            'publishedAtMicros': 1757505600000000,
          },
          onCall: (body, url) {
            sent = body;
            seenUrl = url;
          },
        ),
      );

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_read_routing_revision',
          arguments: {
            ...surfaceTarget(),
            'revisionOrdinal': 4,
            'contractVersion': 3,
          },
        ),
      );

      expect(result.isError, isNot(true));
      expect(seenUrl!.path, endsWith('/surfaceRouting'));
      expect(sent!['method'], 'readRoutingRevision');
      expect(sent!['projectSlug'], 'checkout');
      expect(sent!['appSlug'], 'app');
      expect(sent!['surfaceType'], 'onboarding');
      expect(sent!['surfaceSlug'], 'welcome');
      expect(sent!['environmentId'], 31);
      expect(sent!['organizationId'], 11);
      expect(sent!['revisionOrdinal'], 4);
      expect(sent!['contractVersion'], 3);
    });

    test('the stored document reaches the caller unchanged, with the '
        'publication time', () async {
      final stored = List<int>.generate(48, (i) => i * 2);
      final connection = await connectServer(
        store: store,
        httpClient: routingClient({
          'revisionOrdinal': 6,
          'documentBytes': wire(stored),
          'publishedAtMicros': 1757505600000000,
        }),
      );

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_read_routing_revision',
          arguments: {...surfaceTarget(), 'revisionOrdinal': 6},
        ),
      );

      expect(result.isError, isNot(true));
      expect(result.structuredContent!['revisionOrdinal'], 6);
      expect(result.structuredContent!['documentBase64'], base64Encode(stored));
      expect(result.structuredContent!['publishedAtMicros'], 1757505600000000);
    });

    test('an ordinal below one is refused before any call', () async {
      var reached = false;
      final connection = await connectServer(
        store: store,
        httpClient: _withTargets((_) async {
          reached = true;
          return http.Response('{}', 200);
        }),
      );

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_read_routing_revision',
          arguments: {...surfaceTarget(), 'revisionOrdinal': 0},
        ),
      );

      expect(result.isError, isTrue);
      expect(reached, isFalse);
      expect(
        (result.content.single as TextContent).text,
        contains('revisionOrdinal'),
      );
    });

    test('an ordinal the target never published is surfaced in the '
        "service's own term", () async {
      final connection = await connectServer(
        store: store,
        httpClient: routingClient(
          const {},
          status: 400,
          rawBody: jsonEncode({
            'className': 'SurfaceRoutingRejectedException',
            'data': {
              '__className__': 'SurfaceRoutingRejectedException',
              'reason': 'revision_not_found',
            },
          }),
        ),
      );

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_read_routing_revision',
          arguments: {...surfaceTarget(), 'revisionOrdinal': 99},
        ),
      );

      expect(result.isError, isTrue);
      expect(
        (result.content.single as TextContent).text,
        contains('revision_not_found'),
      );
    });
  });

  test('an empty target reports itself rather than an error', () async {
    final connection = await connectServer(
      store: store,
      httpClient: routingClient({
        'empty': true,
        'documentBytes': null,
        'revisionOrdinal': null,
      }),
    );

    final result = await connection.callTool(
      CallToolRequest(name: 'restage_read_routing', arguments: surfaceTarget()),
    );

    expect(result.isError, isNot(true));
    expect(result.structuredContent!['empty'], isTrue);
    expect(result.structuredContent!['documentBase64'], isNull);
  });
}

/// A client that answers the live guard's target listing, target 31 on the
/// sandbox plane and 32 on the live plane, and hands every other call to
/// [handler].
MockClient _withTargets(Future<http.Response> Function(http.Request) handler) =>
    MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, Object?>;
      if (body['method'] != 'listEnvironmentTargets') return handler(request);
      return http.Response(
        jsonEncode([
          {
            'environmentTargetId': 31,
            'namedEnvironmentId': 41,
            'environmentSlug': 'staging',
            'runtimePlane': 'sandbox',
          },
          {
            'environmentTargetId': 32,
            'namedEnvironmentId': 42,
            'environmentSlug': 'production',
            'runtimePlane': 'live',
          },
        ]),
        200,
      );
    });
