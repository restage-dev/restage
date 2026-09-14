import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/src/api/experiment_api.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/credentials/credential.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:test/test.dart';

import '../_helpers/experiment_fixtures.dart';

void main() {
  group('ExperimentApi.execute', () {
    test('gives every operation its own method on the one endpoint', () async {
      final methods = <String>[];
      final urls = <String>{};
      final api = _apiOver((request) async {
        final body = jsonDecode(request.body) as Map<String, Object?>;
        final method = body['method']! as String;
        methods.add(method);
        urls.add(request.url.toString());
        return http.Response(jsonEncode(byteDataWire(_reply(method))), 200);
      });

      for (final operation in ExperimentAuthoringOperationV1.values) {
        await api.execute(
          request: canonicalRequest(operation),
          target: fixtureTarget,
        );
      }

      expect(methods, [
        for (final operation in ExperimentAuthoringOperationV1.values)
          operation.wireName,
      ]);
      expect(methods.toSet(), hasLength(16));
      expect(urls, {'https://api.example.com/api/experimentAuthoring'});
    });

    test('sends the canonical request bytes and the exact target', () async {
      late Map<String, Object?> body;
      final request = canonicalRequest(
        ExperimentAuthoringOperationV1.listExperiments,
      );
      final api = _apiOver((httpRequest) async {
        body = jsonDecode(httpRequest.body) as Map<String, Object?>;
        return http.Response(
          jsonEncode(byteDataWire(acceptedFor('listExperiments'))),
          200,
        );
      });

      await api.execute(request: request, target: fixtureTarget);

      expect(body.keys.toSet(), {
        'method',
        'organizationId',
        'appId',
        'environmentTargetId',
        'namedEnvironmentId',
        'runtimePlane',
        'requestBytes',
      });
      expect(body['organizationId'], fixtureTarget.organizationId.value);
      expect(body['appId'], fixtureTarget.appId.value);
      expect(
        body['environmentTargetId'],
        fixtureTarget.environmentTargetId.value,
      );
      expect(
        body['namedEnvironmentId'],
        fixtureTarget.namedEnvironmentId.value,
      );
      expect(body['runtimePlane'], fixtureTarget.runtimePlane.wireName);
      expect(body['requestBytes'], byteDataWire(request.canonicalBytes));
    });

    test('carries the credential authorization header', () async {
      late http.Request seen;
      final api = _apiOver(
        (request) async {
          seen = request;
          return http.Response(
            jsonEncode(byteDataWire(acceptedFor('listExperiments'))),
            200,
          );
        },
        credential: const Credential(
          endpoint: 'https://api.example.com/api/',
          kind: CredentialKind.authKey,
          authToken: '42:abc',
        ),
      );

      await api.execute(
        request: canonicalRequest(
          ExperimentAuthoringOperationV1.listExperiments,
        ),
        target: fixtureTarget,
      );

      expect(seen.headers['authorization'], 'Basic NDI6YWJj');
    });

    test('returns the typed refusal a route answers with', () async {
      final api = _apiOver(
        (request) async => http.Response(
          jsonEncode(
            byteDataWire(
              refusalFor(
                'readExperimentResults',
                ExperimentAuthoringRefusalCodeV1.capabilityUnavailable,
              ),
            ),
          ),
          200,
        ),
      );

      final result = await api.execute(
        request: canonicalRequest(
          ExperimentAuthoringOperationV1.readExperimentResults,
        ),
        target: fixtureTarget,
      );

      final refused = result as ExperimentAuthoringRefusedV1;
      expect(
        refused.refusal.code,
        ExperimentAuthoringRefusalCodeV1.capabilityUnavailable,
      );
      expect(refused.refusal.retryable, isFalse);
    });

    test('surfaces a denied action without widening it', () async {
      final api = _apiOver(
        (request) async => http.Response(
          jsonEncode(
            byteDataWire(
              refusalFor(
                'activateDraft',
                ExperimentAuthoringRefusalCodeV1.deniedAction,
              ),
            ),
          ),
          200,
        ),
      );

      final result = await api.execute(
        request: canonicalRequest(ExperimentAuthoringOperationV1.activateDraft),
        target: fixtureTarget,
      );

      expect(
        (result as ExperimentAuthoringRefusedV1).refusal.code,
        ExperimentAuthoringRefusalCodeV1.deniedAction,
      );
    });

    test('refuses a result carrying another operation', () async {
      final api = _apiOver(
        (request) async => http.Response(
          jsonEncode(byteDataWire(acceptedFor('listExperiments'))),
          200,
        ),
      );

      await expectLater(
        api.execute(
          request: canonicalRequest(
            ExperimentAuthoringOperationV1.discoverTargetsAndCapabilities,
          ),
          target: fixtureTarget,
        ),
        throwsA(isA<ExperimentResponseMismatchException>()),
      );
    });

    test('refuses a result carrying another correlation', () async {
      final api = _apiOver(
        (request) async => http.Response(
          jsonEncode(
            byteDataWire(
              acceptedFor('listExperiments', correlationId: 'other'),
            ),
          ),
          200,
        ),
      );

      await expectLater(
        api.execute(
          request: canonicalRequest(
            ExperimentAuthoringOperationV1.listExperiments,
          ),
          target: fixtureTarget,
        ),
        throwsA(isA<ExperimentResponseMismatchException>()),
      );
    });

    test('refuses a view addressed to another target', () async {
      final api = _apiOver(
        (request) async => http.Response(
          jsonEncode(
            byteDataWire(
              acceptedFor('listExperiments', target: fixtureOtherTarget),
            ),
          ),
          200,
        ),
      );

      await expectLater(
        api.execute(
          request: canonicalRequest(
            ExperimentAuthoringOperationV1.listExperiments,
          ),
          target: fixtureTarget,
        ),
        throwsA(isA<ExperimentResponseMismatchException>()),
      );
    });

    test(
      'refuses response bytes that are not the canonical spelling',
      () async {
        final padded = utf8.encode(
          ' ${utf8.decode(acceptedFor("listExperiments"))}',
        );
        final api = _apiOver(
          (request) async =>
              http.Response(jsonEncode(byteDataWire(padded)), 200),
        );

        await expectLater(
          api.execute(
            request: canonicalRequest(
              ExperimentAuthoringOperationV1.listExperiments,
            ),
            target: fixtureTarget,
          ),
          throwsA(isA<CanonicalFormatException>()),
        );
      },
    );
  });

  group('ExperimentApi safe retry', () {
    test(
      'resends byte-identical content and the same idempotency key',
      () async {
        final bodies = <String>[];
        final api = _apiOver((request) async {
          bodies.add(request.body);
          if (bodies.length == 1) return http.Response('unavailable', 503);
          return http.Response(
            jsonEncode(
              byteDataWire(
                refusalFor(
                  'activateDraft',
                  ExperimentAuthoringRefusalCodeV1.deniedAction,
                ),
              ),
            ),
            200,
          );
        });
        final request = canonicalRequest(
          ExperimentAuthoringOperationV1.activateDraft,
        );

        await api.execute(request: request, target: fixtureTarget);

        expect(bodies, hasLength(2));
        expect(bodies[1], bodies[0]);
        expect(request.idempotencyKey, 'idempotency-activateDraft');
        expect(
          (jsonDecode(bodies[1]) as Map<String, Object?>)['requestBytes'],
          byteDataWire(request.canonicalBytes),
        );
      },
    );

    test(
      'retries a retryable refusal and returns the settled result',
      () async {
        var attempts = 0;
        final api = _apiOver((request) async {
          attempts++;
          return http.Response(
            jsonEncode(
              byteDataWire(
                attempts == 1
                    ? refusalFor(
                        'listExperiments',
                        ExperimentAuthoringRefusalCodeV1.backendUnavailable,
                      )
                    : acceptedFor('listExperiments'),
              ),
            ),
            200,
          );
        });

        final result = await api.execute(
          request: canonicalRequest(
            ExperimentAuthoringOperationV1.listExperiments,
          ),
          target: fixtureTarget,
        );

        expect(attempts, 2);
        expect(result, isA<ExperimentAuthoringAcceptedV1>());
      },
    );

    test('does not retry a refusal the route calls final', () async {
      var attempts = 0;
      final api = _apiOver((request) async {
        attempts++;
        return http.Response(
          jsonEncode(
            byteDataWire(
              refusalFor(
                'listExperiments',
                ExperimentAuthoringRefusalCodeV1.deniedAction,
              ),
            ),
          ),
          200,
        );
      });

      await api.execute(
        request: canonicalRequest(
          ExperimentAuthoringOperationV1.listExperiments,
        ),
        target: fixtureTarget,
      );

      expect(attempts, 1);
    });

    test('does not retry a rejected request', () async {
      var attempts = 0;
      final api = _apiOver((request) async {
        attempts++;
        return http.Response('denied', 403);
      });

      await expectLater(
        api.execute(
          request: canonicalRequest(
            ExperimentAuthoringOperationV1.listExperiments,
          ),
          target: fixtureTarget,
        ),
        throwsA(isA<RestageApiException>()),
      );
      expect(attempts, 1);
    });

    test(
      'stops at the attempt ceiling and surfaces the last outcome',
      () async {
        var attempts = 0;
        final api = _apiOver((request) async {
          attempts++;
          return http.Response('unavailable', 503);
        });

        await expectLater(
          api.execute(
            request: canonicalRequest(
              ExperimentAuthoringOperationV1.listExperiments,
            ),
            target: fixtureTarget,
          ),
          throwsA(isA<RestageApiException>()),
        );
        expect(attempts, 3);
      },
    );
  });

  group('ExperimentApi.discoverEveryPage', () {
    test('threads each cursor and completes on a null cursor', () async {
      final cursors = <Object?>[];
      final api = _apiOver((request) async {
        final body = jsonDecode(request.body) as Map<String, Object?>;
        final sent = ExperimentAuthoringRequestV1.fromCanonicalBytes(
          byteDataBytes(body['requestBytes']! as String),
        );
        cursors.add(sent.payload['pageCursor']);
        return http.Response(
          jsonEncode(
            byteDataWire(
              discoveryPage(
                namedEnvironmentLabels: switch (cursors.length) {
                  1 => const ['alpha'],
                  2 => const <String>[],
                  _ => const ['beta'],
                },
                nextPageCursor: switch (cursors.length) {
                  1 => 'cursor-2',
                  2 => 'cursor-3',
                  _ => null,
                },
              ),
            ),
          ),
          200,
        );
      });

      final drain = await api.discoverEveryPage(
        target: fixtureTarget,
        correlationId: fixtureCorrelationId('discoverTargetsAndCapabilities'),
      );

      expect(cursors, [null, 'cursor-2', 'cursor-3']);
      final discovery =
          (drain as ExperimentPagesAccepted<ExperimentDiscovery>).value;
      expect(discovery.namedEnvironments.map((option) => option.label), [
        'alpha',
        'beta',
      ]);
    });

    test('keeps source order across more than 256 entries', () async {
      var page = 0;
      final api = _apiOver((request) async {
        page++;
        final start = (page - 1) * 100;
        return http.Response(
          jsonEncode(
            byteDataWire(
              discoveryPage(
                namedEnvironmentLabels: [
                  for (var index = start; index < start + 100; index++)
                    'environment-$index',
                ],
                nextPageCursor: page < 3 ? 'cursor-${page + 1}' : null,
              ),
            ),
          ),
          200,
        );
      });

      final drain = await api.discoverEveryPage(
        target: fixtureTarget,
        correlationId: fixtureCorrelationId('discoverTargetsAndCapabilities'),
      );

      final discovery =
          (drain as ExperimentPagesAccepted<ExperimentDiscovery>).value;
      expect(discovery.namedEnvironments, hasLength(300));
      expect(discovery.namedEnvironments.map((option) => option.label), [
        for (var index = 0; index < 300; index++) 'environment-$index',
      ]);
    });

    test('keys surfaces by identity and revision together', () async {
      var page = 0;
      final api = _apiOver((request) async {
        page++;
        return http.Response(
          jsonEncode(
            byteDataWire(
              discoveryPage(
                surfaces: page == 1
                    ? const [
                        ('checkout', 'checkout.r1'),
                        ('paywall', 'paywall.r1'),
                      ]
                    : const [
                        ('checkout', 'checkout.r1'),
                        ('checkout', 'checkout.r2'),
                      ],
                nextPageCursor: page == 1 ? 'cursor-2' : null,
              ),
            ),
          ),
          200,
        );
      });

      final drain = await api.discoverEveryPage(
        target: fixtureTarget,
        correlationId: fixtureCorrelationId('discoverTargetsAndCapabilities'),
      );

      final discovery =
          (drain as ExperimentPagesAccepted<ExperimentDiscovery>).value;
      expect(
        discovery.surfaceCapabilities.map(
          (capability) => (
            capability.surfaceReference.surfaceId.value,
            capability.surfaceReference.surfaceRevisionId.value,
          ),
        ),
        [
          (
            fixtureMintedSurfaceId('checkout'),
            fixtureMintedSurfaceRevisionId('checkout.r1'),
          ),
          (
            fixtureMintedSurfaceId('paywall'),
            fixtureMintedSurfaceRevisionId('paywall.r1'),
          ),
          (
            fixtureMintedSurfaceId('checkout'),
            fixtureMintedSurfaceRevisionId('checkout.r2'),
          ),
        ],
      );
    });

    test('stops rather than follow a cursor it already followed', () async {
      var pages = 0;
      final api = _apiOver((request) async {
        pages++;
        return http.Response(
          jsonEncode(
            byteDataWire(
              discoveryPage(
                namedEnvironmentLabels: const ['alpha'],
                nextPageCursor: 'cursor-stuck',
              ),
            ),
          ),
          200,
        );
      });

      await expectLater(
        api.discoverEveryPage(
          target: fixtureTarget,
          correlationId: fixtureCorrelationId('discoverTargetsAndCapabilities'),
        ),
        throwsA(isA<ExperimentPageCursorRepeatedException>()),
      );
      expect(pages, 2, reason: 'the repeat must end the drain immediately');
    });

    test('stops at the refusal that interrupts the drain', () async {
      var page = 0;
      final api = _apiOver((request) async {
        page++;
        return http.Response(
          jsonEncode(
            byteDataWire(
              page == 1
                  ? discoveryPage(
                      namedEnvironmentLabels: const ['alpha'],
                      nextPageCursor: 'cursor-2',
                    )
                  : refusalFor(
                      'discoverTargetsAndCapabilities',
                      ExperimentAuthoringRefusalCodeV1.deniedAction,
                    ),
            ),
          ),
          200,
        );
      });

      final drain = await api.discoverEveryPage(
        target: fixtureTarget,
        correlationId: fixtureCorrelationId('discoverTargetsAndCapabilities'),
      );

      expect(page, 2);
      expect(
        (drain as ExperimentPagesRefused<ExperimentDiscovery>)
            .refusal
            .refusal
            .code,
        ExperimentAuthoringRefusalCodeV1.deniedAction,
      );
    });
  });

  group('ExperimentApi.listEveryPage', () {
    test('concatenates pages and completes on a null cursor', () async {
      var page = 0;
      final api = _apiOver((request) async {
        page++;
        return http.Response(
          jsonEncode(
            byteDataWire(
              listPage(
                experimentIds: switch (page) {
                  1 => const ['experiment.a'],
                  2 => const <String>[],
                  _ => const ['experiment.b'],
                },
                nextPageCursor: page < 3 ? 'cursor-${page + 1}' : null,
              ),
            ),
          ),
          200,
        );
      });

      final drain = await api.listEveryPage(
        target: fixtureTarget,
        correlationId: fixtureCorrelationId('listExperiments'),
      );

      expect(page, 3);
      final entries =
          (drain as ExperimentPagesAccepted<List<ExperimentListEntryV1>>).value;
      expect(entries.map((entry) => entry.experimentId.value), [
        'experiment.a',
        'experiment.b',
      ]);
    });
  });

  group('experiment mutation payload discipline', () {
    test('a resolved serverDefault never reaches the transport', () async {
      var calls = 0;
      final api = _apiOver((request) async {
        calls++;
        return http.Response('unreachable', 500);
      });

      Future<void> send() => api.execute(
        request: ExperimentAuthoringRequestV1.fromJson(
          replaceDraftRequestJson(
            randomizedUnitSelection: const {
              'kind': 'serverDefault',
              'resolvedValue': 'installation',
              'source': <String, Object?>{
                'kind': 'experimentRandomizedUnitDefaults',
                'randomizedUnitKind': 'installation',
              },
            },
          ),
        ),
        target: fixtureTarget,
      );

      expect(send, throwsA(isA<CanonicalFormatException>()));
      expect(calls, 0, reason: 'the request must be refused before transport');
    });

    test('accepts the bare serverDefault sentinel', () {
      final request = ExperimentAuthoringRequestV1.fromJson(
        replaceDraftRequestJson(
          randomizedUnitSelection: const {'kind': 'serverDefault'},
        ),
      );

      expect(request.operation, ExperimentAuthoringOperationV1.replaceDraft);
    });
  });
}

ExperimentApi _apiOver(
  Future<http.Response> Function(http.Request request) handler, {
  Credential? credential,
}) => ExperimentApi(
  RestageApi(
    endpoint: Uri.parse('https://api.example.com/api/'),
    httpClient: MockClient(handler),
    credential: credential,
  ),
);

/// The accepted reply the route-coverage case answers each method with.
List<int> _reply(String method) => switch (method) {
  'discoverTargetsAndCapabilities' || 'listExperiments' => acceptedFor(method),
  _ => refusalFor(
    method,
    ExperimentAuthoringRefusalCodeV1.capabilityUnavailable,
  ),
};
