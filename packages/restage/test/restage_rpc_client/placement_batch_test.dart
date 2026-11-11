import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage/src/restage_rpc_client/placement_delivery_adapter.dart';
import 'package:restage/src/delivery/surface_artifact_store.dart';
import 'package:restage/src/refresh/delivery_announcement.dart';
import 'package:restage/src/delivery/surface_delivery_receipt.dart';
import 'package:restage/src/flow/flow_resolver.dart';
import 'package:restage/src/flow/flow_descriptors.dart';
import 'package:restage/src/resolver/placement_fallback_log.dart'
    show
        PlacementNoAnswerCause,
        PlacementNoAnswerStale,
        PlacementStaleChange,
        refusedApiKeyClock,
        resetPlacementFallbackLog;
import 'package:restage/src/resolver/placement_mount_resolver.dart';
import 'package:restage/src/resolver/surface_assignment_credential_store.dart';
import 'package:restage/src/resolver/surface_assignment_key_provider.dart';
import 'package:restage/src/runtime/placement_registry.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/placement_delivery_fixture.dart';

void main() {
  test(
    'one authenticated batch assembles unpublished flow descendants by source identity',
    () async {
      final fixture = readPlacementDeliveryFixture(
        fileName: 'retained_flow_dependencies_v1.json',
      );
      final requests = <http.Request>[];
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: MockClient((request) async {
          requests.add(request);
          return placementFixtureArtifact(request) ??
              http.Response.bytes(fixture.response.canonicalBytes, 200);
        }),
      );
      addTearDown(client.close);
      sharedSurfaceArtifactStore = MemorySurfaceArtifactStore();
      addTearDown(() => sharedSurfaceArtifactStore = null);
      final response = await client.fetchPlacements(
        fixture.request,
        publicationGuard: () => true,
      ) as PlacementBatchResolvedV1;
      final artifacts = placementArtifactsFor(response)!;
      expect(artifacts.frames, hasLength(4));
      expect(artifacts.documents, hasLength(6));
      expect(artifacts.publications, hasLength(2));
      final first = response.decisions.first as PlacementBatchAvailableV1;
      final rootDocument =
          artifacts.publications[first.publicDelivery.actualPublication]!;
      expect(rootDocument.version, 29);
      expect(
        (rootDocument.payload as FlowSurfacePayload).flowDocument.version,
        5,
      );
      final declaration = (
        mount: fixture.request.mounts.first,
        host: fixture.request.buildContract
            .contractsByHash[fixture.request.mounts.first.hostContractHash]!,
      );
      final registry = PlacementRegistry(
        scope: 'retained-flow-test',
        configurationFingerprint: 'retained-flow-test',
        client: () => client,
        isCurrent: () => true,
      );
      final context = PlacementRequestContext(
        request: fixture.request,
        lease: SurfaceAssignmentKeyProvider.captureKeylessLease(),
        capturedAt: DateTime.utc(2026, 10, 3),
        isCurrent: () => true,
      );
      final resolver = PlacementFlowResolver(
        registry: registry,
        declaration: declaration,
        flow: SurfaceFlowRef<Map<String, Object?>>(
          id: 'first_root',
          version: 29,
          minClient: 2,
          surface: Surface.general,
          decodeResult: (value) => value,
        ),
        originalResolver: const AssetFlowResolver(),
      );
      final root = resolver.convert(
        PlacementDeliveryAdmission(
          decision: first,
          context: context,
          host: declaration.host,
          registry: registry,
          document: rootDocument,
        ),
        artifacts,
        cacheHit: false,
      )!;
      expect(root.document.flow, 'first_root');
      expect(root.document.version, 5);
      final child = await resolver.resolve(
        SurfaceFlowRef<Map<String, Object?>>(
          id: 'shared_child',
          version: 7,
          minClient: 2,
          surface: Surface.general,
          decodeResult: (value) => value,
        ),
      );
      final leaf = await resolver.resolve(
        SurfaceFlowRef<Map<String, Object?>>(
          id: 'shared_leaf',
          version: 11,
          minClient: 2,
          surface: Surface.general,
          decodeResult: (value) => value,
        ),
      );
      expect(child.document.version, 7);
      expect(leaf.document.version, 11);
      expect(
        first.artifactClosure.where(
          (reference) => reference.publication == null,
        ),
        hasLength(2),
      );
      await expectLater(
        resolver.resolve(
          SurfaceFlowRef<Map<String, Object?>>(
            id: 'second_root',
            version: 8,
            minClient: 2,
            surface: Surface.general,
            decodeResult: (value) => value,
          ),
        ),
        throwsA(isA<FlowUnavailableError>()),
      );
      // One resolve, then each referenced frame once.
      expect(requests.first.method, 'POST');
      expect(requests.first.url.path, '/sdk/v1/placements/resolve');
      expect(
        requests.skip(1).map((request) => (request.method, request.url.path)),
        unorderedEquals([
          ('GET', '/first_root'),
          ('GET', '/second_root'),
          ('GET', '/shared_child'),
          ('GET', '/shared_leaf'),
        ]),
      );
    },
  );

  test(
    'one placement POST admits two decisions and fetches their frame once',
    () async {
      final fixture = readPlacementDeliveryFixture();
      final requests = <http.Request>[];
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: MockClient((request) async {
          requests.add(request);
          final artifact = placementFixtureArtifact(request);
          if (artifact != null) return artifact;
          expect(request.method, 'POST');
          expect(request.url.path, '/sdk/v1/placements/resolve');
          expect(request.headers['Authorization'], 'Bearer rs_pk_test');
          expect(request.bodyBytes, fixture.request.canonicalBytes);
          return http.Response.bytes(fixture.response.canonicalBytes, 200);
        }),
      );
      addTearDown(client.close);

      final response = await client.fetchPlacements(
        fixture.request,
        publicationGuard: () => true,
      );

      expect(requests.map((request) => request.method), ['POST', 'GET']);
      expect(
        requests.last.headers[surfaceArtifactPassHeader],
        isNotEmpty,
      );
      expect(response, isA<PlacementBatchResolvedV1>());
      final resolved = response! as PlacementBatchResolvedV1;
      expect(resolved.decisions, hasLength(2));
      expect(client.heldPlacementArtifacts, hasLength(1));
      expect(client.placementTarget, fixture.target);
      final replacements = resolved.decisions.cast<PlacementBatchAvailableV1>();
      for (final replacement in replacements) {
        expect(
          replacement.publicDelivery.actualPublication.surface.family,
          DeliveryFamilySelectorV1.screenContract(contractVersion: 7),
        );
        expect(
          replacement.publicDelivery.actualPublication.surface.family,
          isNot(replacement.descriptor.defaultSurface!.family),
        );
      }
    },
  );

  test('a batch carries the records a live-refresh push named, once', () async {
    final fixture = readPlacementDeliveryFixture();
    final wanted = <String?>[];
    final client = RestageRpcClient(
      baseUrl: 'https://example.com',
      apiKey: 'rs_pk_test',
      httpClient: MockClient((request) async {
        if (request.method == 'POST') {
          wanted.add(request.headers['restage-want-records']);
        }
        return placementFixtureArtifact(request) ??
            http.Response.bytes(fixture.response.canonicalBytes, 200);
      }),
    );
    addTearDown(client.close);
    final registry = PlacementRegistry(
      scope: 'want-test',
      configurationFingerprint: 'want-test',
      client: () => client,
      isCurrent: () => true,
    );
    PlacementRequestContext context() => PlacementRequestContext(
          request: fixture.request,
          lease: SurfaceAssignmentKeyProvider.captureKeylessLease(),
          capturedAt: DateTime.utc(2026, 10, 3),
          isCurrent: () => true,
        );

    await registry.fetch(context(), wants: [
      AnnouncedWant('d/1/general/a=${'1' * 64}'),
      AnnouncedWant('d/1/general/a=${'1' * 64}'),
      AnnouncedWant('p/1/${'2' * 64}=-'),
    ]);
    await registry.fetch(context());
    await registry.fetch(context(), wants: [
      AnnouncedWant('s/1/general/a=${'3' * 64}'),
      AnnouncedWant('*'),
    ]);

    expect(wanted, [
      'd/1/general/a=${'1' * 64},p/1/${'2' * 64}=-',
      null,
      '*',
    ]);
  });

  test(
      'an answer to a push that does not say it read the named records is '
      'no answer', () async {
    final fixture = readPlacementDeliveryFixture();
    String? met;
    final client = RestageRpcClient(
      baseUrl: 'https://example.com',
      apiKey: 'rs_pk_test',
      httpClient: MockClient((request) async =>
          placementFixtureArtifact(request) ??
          http.Response.bytes(fixture.response.canonicalBytes, 200,
              headers: {if (met != null) 'restage-want-met': met})),
    );
    addTearDown(client.close);
    final refusals = <(SurfaceDeliveryReceiptReason, PlacementNoAnswerCause)>[];
    Future<PlacementBatchResponseV1?> fetch(String? want) =>
        client.fetchPlacements(fixture.request,
            publicationGuard: () => true,
            wantRecords: want,
            onNoAnswer: (reason, cause) => refusals.add((reason, cause)));
    const want = 'd/1/general/a=-';

    expect(await fetch(want), isNull);
    met = '0';
    expect(await fetch(want), isNull);
    expect(refusals.map((r) => r.$1),
        everyElement(SurfaceDeliveryReceiptReason.serverError));
    expect(refusals.first.$2.describe(), contains('live update'));

    refusals.clear();
    met = '1';
    expect(await fetch(want), isA<PlacementBatchResolvedV1>());
    met = null;
    expect(await fetch(null), isA<PlacementBatchResolvedV1>());
    expect(refusals, isEmpty);
  });

  test('only a taken answer meets the wants a request carried', () async {
    final fixture = readPlacementDeliveryFixture();
    String? met;
    String? served;
    final client = RestageRpcClient(
      baseUrl: 'https://example.com',
      apiKey: 'rs_pk_test',
      httpClient: MockClient((request) async =>
          placementFixtureArtifact(request) ??
          http.Response.bytes(fixture.response.canonicalBytes, 200, headers: {
            if (met != null) 'restage-want-met': met,
            if (served != null) 'restage-want-served': served,
          })),
    );
    addTearDown(client.close);
    final registry = PlacementRegistry(
      scope: 'unmet-test',
      configurationFingerprint: 'unmet-test',
      client: () => client,
      isCurrent: () => true,
    );
    var current = true;
    PlacementRequestContext context() => PlacementRequestContext(
          request: fixture.request,
          lease: SurfaceAssignmentKeyProvider.captureKeylessLease(),
          capturedAt: DateTime.utc(2026, 10, 3),
          isCurrent: () => current,
        );
    const want = 'd/1/general/a=-';
    List<AnnouncedWant> wants() => [AnnouncedWant(want), AnnouncedWant(want)];

    // Unmet: neither surface the request answered for is met.
    var sent = wants();
    expect(await registry.fetch(context(), wants: sent), isNull);
    expect(sent.map((w) => w.met), [false, false]);

    // Nothing sent.
    met = '1';
    current = false;
    sent = wants();
    expect(await registry.fetch(context(), wants: sent), isNull);
    expect(sent.map((w) => w.met), [false, false]);

    current = true;
    sent = wants();
    expect(await registry.fetch(context(), wants: sent), isNotNull);
    expect(sent.map((w) => w.met), [true, true]);
    expect(sent.map((w) => w.served), [null, null]);

    // Each met want carries what the answer read in place of what was named.
    served = 'd/1/general/a=${'2' * 64}';
    sent = wants();
    expect(await registry.fetch(context(), wants: sent), isNotNull);
    expect(sent.map((w) => w.served), [served, served]);
  });

  test('held content is assembled without an artifact GET', () async {
    final fixture = readPlacementDeliveryFixture();
    final requests = <http.Request>[];
    final client = RestageRpcClient(
      baseUrl: 'https://example.com',
      apiKey: 'rs_pk_test',
      httpClient: MockClient((request) async {
        requests.add(request);
        return placementFixtureArtifact(request) ??
            http.Response.bytes(fixture.response.canonicalBytes, 200);
      }),
    );
    addTearDown(client.close);
    await client.fetchPlacements(fixture.request, publicationGuard: () => true);
    final response = await client.fetchPlacements(
      fixture.request,
      publicationGuard: () => true,
    );

    expect(response, isA<PlacementBatchResolvedV1>());
    expect(requests.map((request) => request.method), ['POST', 'GET', 'POST']);
  });

  test('an answered build is named by hash and resent once on a miss',
      () async {
    final fixture = readPlacementDeliveryFixture();
    final carried = <bool>[];
    var miss = false;
    final client = RestageRpcClient(
      baseUrl: 'https://example.com',
      apiKey: 'rs_pk_test',
      httpClient: MockClient((request) async {
        final artifact = placementFixtureArtifact(request);
        if (artifact != null) return artifact;
        final body = jsonDecode(request.body) as Map<String, Object?>;
        carried.add(body.containsKey('buildContract'));
        if (miss && !body.containsKey('buildContract')) {
          return http.Response(
              jsonEncode({'error': PlacementBuildContractRequired.errorCode}),
              PlacementBuildContractRequired.status);
        }
        return http.Response.bytes(fixture.response.canonicalBytes, 200);
      }),
    );
    addTearDown(client.close);
    await client.fetchPlacements(fixture.request, publicationGuard: () => true);
    await client.fetchPlacements(fixture.request, publicationGuard: () => true);
    expect(carried, [true, false]);

    miss = true;
    final response = await client.fetchPlacements(
      fixture.request,
      publicationGuard: () => true,
    );
    expect(response, isA<PlacementBatchResolvedV1>());
    expect(carried, [true, false, false, true]);
  });

  test('a service that cannot read a build named by hash gets it in full',
      () async {
    final fixture = readPlacementDeliveryFixture();
    final carried = <bool>[];
    final client = RestageRpcClient(
      baseUrl: 'https://example.com',
      apiKey: 'rs_pk_test',
      httpClient: MockClient((request) async {
        final artifact = placementFixtureArtifact(request);
        if (artifact != null) return artifact;
        final body = jsonDecode(request.body) as Map<String, Object?>;
        carried.add(body.containsKey('buildContract'));
        // An older decoder requires the contract and refuses its absence.
        if (!body.containsKey('buildContract')) {
          return http.Response.bytes(
              PlacementBatchRefusedV1(
                reason: PlacementBatchRefusalReasonV1.invalidRequest,
              ).canonicalBytes,
              400);
        }
        return http.Response.bytes(fixture.response.canonicalBytes, 200);
      }),
    );
    addTearDown(client.close);
    for (var i = 0; i < 3; i++) {
      expect(
        await client.fetchPlacements(fixture.request,
            publicationGuard: () => true),
        isA<PlacementBatchResolvedV1>(),
      );
    }
    // After one refusal of the hash form, every send carries the contract.
    expect(carried, [true, false, true, true]);
  });

  test('a frame that cannot be fetched leaves its rows without content',
      () async {
    final fixture = readPlacementDeliveryFixture();
    final requests = <http.Request>[];
    final client = RestageRpcClient(
      baseUrl: 'https://example.com',
      apiKey: 'rs_pk_test',
      httpClient: MockClient((request) async {
        requests.add(request);
        return request.method == 'GET'
            ? http.Response('', 503)
            : http.Response.bytes(fixture.response.canonicalBytes, 200);
      }),
    );
    addTearDown(client.close);

    final response = await client.fetchPlacements(
      fixture.request,
      publicationGuard: () => true,
    ) as PlacementBatchResolvedV1;

    expect(placementArtifactsFor(response)!.publications, isEmpty);
    expect(requests.map((request) => request.method), ['POST', 'GET']);
    expect(client.heldPlacementArtifacts, isEmpty);
  });

  test('a fetched frame whose hash differs is not content', () async {
    final fixture = readPlacementDeliveryFixture();
    final client = RestageRpcClient(
      baseUrl: 'https://example.com',
      apiKey: 'rs_pk_test',
      httpClient: MockClient((request) async {
        if (request.method == 'GET') {
          final bytes = placementFixtureArtifact(request)!.bodyBytes.toList()
            ..[0] ^= 1;
          return http.Response.bytes(bytes, 200);
        }
        return http.Response.bytes(fixture.response.canonicalBytes, 200);
      }),
    );
    addTearDown(client.close);

    final response = await client.fetchPlacements(
      fixture.request,
      publicationGuard: () => true,
    ) as PlacementBatchResolvedV1;

    expect(placementArtifactsFor(response)!.publications, isEmpty);
    expect(client.heldPlacementArtifacts, isEmpty);
  });

  test('a non-canonical response is malformed and logged in debug builds',
      () async {
    final fixture = readPlacementDeliveryFixture();
    final lines = <String>[];
    final previous = debugPrint;
    debugPrint = (message, {wrapWidth}) => lines.add(message!);
    addTearDown(() => debugPrint = previous);
    final client = RestageRpcClient(
      baseUrl: 'https://example.com',
      apiKey: 'rs_pk_test',
      httpClient: MockClient((_) async =>
          http.Response(jsonEncode(fixture.response.toJson()), 200)),
    );
    addTearDown(client.close);

    final response = await client.fetchPlacements(
      fixture.request,
      publicationGuard: () => true,
    );

    expect(
      (response! as PlacementBatchRefusedV1).reason,
      PlacementBatchRefusalReasonV1.decodeFailed,
    );
    expect(lines.single,
        startsWith('[restage] placement response was malformed: '));
  });

  group('a failed resolve', () {
    late List<String> lines;
    setUp(() {
      lines = [];
      final previous = debugPrint;
      debugPrint = (message, {wrapWidth}) => lines.add(message!);
      addTearDown(() {
        debugPrint = previous;
        resetPlacementFallbackLog();
      });
    });

    Future<(PlacementBatchResponseV1?, PlacementNoAnswerCause?)> fetch(
        http.Response reply) async {
      final fixture = readPlacementDeliveryFixture();
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: MockClient((_) async => reply),
      );
      addTearDown(client.close);
      PlacementNoAnswerCause? cause;
      final response = await client.fetchPlacements(fixture.request,
          publicationGuard: () => true, onNoAnswer: (_, why) => cause = why);
      return (response, cause);
    }

    test('logs nothing when the service first sends a refusal', () async {
      final (response, cause) = await fetch(http.Response.bytes(
          PlacementBatchResponseV1.refused(
                  reason: PlacementBatchRefusalReasonV1.invalidAuthority)
              .canonicalBytes,
          401));
      expect((response! as PlacementBatchRefusedV1).reason,
          PlacementBatchRefusalReasonV1.invalidAuthority);
      expect(cause, isNull);
      expect(lines, isEmpty);
    });

    test('the edge refusing a dead key falls back, named once it persists',
        () async {
      var now = DateTime.utc(2026);
      refusedApiKeyClock = () => now;
      for (var i = 0; i < 3; i++) {
        if (i == 1) expect(lines, isEmpty);
        now = now.add(const Duration(seconds: 40));
        final (response, cause) =
            await fetch(http.Response('{"error":"unauthorized"}', 401));
        expect((response! as PlacementBatchRefusedV1).reason,
            PlacementBatchRefusalReasonV1.invalidAuthority);
        expect(cause, isNull);
      }
      expect(lines, [
        '[restage] the service at example.com refused the API key (HTTP 401). '
            'Set `apiKey` to the public SDK key (rs_pk_...) for this '
            'environment. See https://docs.restage.dev/delivery/'
            'hosted-delivery#configure-delivery',
      ]);
    });

    const configDocs =
        'https://docs.restage.dev/delivery/hosted-delivery#configure-delivery';

    test('names a 404 without a refusal as a base URL to fix', () async {
      final (response, cause) =
          await fetch(http.Response('{"error":"not_found"}', 404));
      expect(response, isNull);
      expect(
          lines.single,
          '[restage] placement resolve failed: the service at example.com has '
          'no placement route at '
          'https://example.com/sdk/v1/placements/resolve (HTTP 404, '
          '`not_found`). Set `baseUrl` to the API URL alone, with no path. '
          'See $configDocs');
      expect(cause!.describe(), lines.single.split('failed: ').last);
    });

    test('names another 4xx without a refusal as a rejected request', () async {
      final (response, cause) = await fetch(http.Response('', 422));
      expect(response, isNull);
      expect(
          cause!.describe(),
          'the service at example.com rejected the request (HTTP 422) '
          'without a placement answer. Check that the restage package '
          '(2.0.0) and the service are current.');
    });

    test('names a redirect as a base URL to fix, not a server error', () async {
      final (response, cause) = await fetch(http.Response('', 301, headers: {
        'location': 'https://www.example.com/sdk/v1/placements/resolve'
      }));
      expect(response, isNull);
      expect(
          lines.single,
          '[restage] placement resolve failed: the service at example.com '
          'redirected the request (HTTP 301 to '
          'https://www.example.com/sdk/v1/placements/resolve), and the SDK '
          "doesn't follow redirects. Set `baseUrl` to "
          'https://www.example.com. See $configDocs');
      expect(cause!.describe(), lines.single.split('failed: ').last);
    });

    test('names the wait the service asked for, uncapped', () async {
      final (_, cause) =
          await fetch(http.Response('', 429, headers: {'retry-after': '3600'}));
      expect(lines.single, endsWith('(HTTP 429). Retry after 3600 s.'));
      expect(cause!.describe(), endsWith('Retry after 3600 s.'));
      final (_, dated) = await fetch(http.Response('', 429,
          headers: {'retry-after': 'Wed, 21 Oct 2026 07:28:00 GMT'}));
      expect(dated!.describe(),
          'the service at example.com is rate limiting this app (HTTP 429).');
    });
  });

  test('an independently known target fences a foreign batch', () async {
    final fixture = readPlacementDeliveryFixture();
    final client = RestageRpcClient(
      baseUrl: 'https://example.com',
      apiKey: 'rs_pk_test',
      httpClient: MockClient(
        (_) async => http.Response.bytes(fixture.response.canonicalBytes, 200),
      ),
    );
    addTearDown(client.close);
    final otherTarget = TargetCoordinate.fromJson({
      ...fixture.target.toJson(),
      'appId': 99,
    });

    final response = await client.fetchPlacements(
      fixture.request,
      expectedTarget: otherTarget,
      publicationGuard: () => true,
    );

    expect(response, isA<PlacementBatchRefusedV1>());
    expect(client.placementTarget, isNull);
    expect(client.heldPlacementArtifacts, isEmpty);
  });

  test(
    'a stale generation cannot publish a completed placement reply',
    () async {
      final fixture = readPlacementDeliveryFixture();
      final reply = Completer<http.Response>();
      final posted = Completer<void>();
      var current = true;
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: MockClient((_) {
          posted.complete();
          return reply.future;
        }),
      );
      addTearDown(client.close);
      final pending = client.fetchPlacements(
        fixture.request,
        publicationGuard: () => current,
      );
      final rejected = expectLater(
        pending,
        throwsA(isA<SurfaceRequestPublicationRejected>()),
      );
      await posted.future;
      current = false;
      reply.complete(http.Response.bytes(fixture.response.canonicalBytes, 200));
      await rejected;

      expect(client.heldPlacementArtifacts, isEmpty);
      expect(client.placementTarget, isNull);
    },
  );

  test('a fence rejected in flight says the registration changed', () async {
    final fixture = readPlacementDeliveryFixture();
    final reply = Completer<http.Response>();
    final posted = Completer<void>();
    var current = true;
    final client = RestageRpcClient(
      baseUrl: 'https://example.com',
      apiKey: 'rs_pk_test',
      httpClient: MockClient((_) {
        posted.complete();
        return reply.future;
      }),
    );
    addTearDown(client.close);
    final registry = PlacementRegistry(
      scope: 'fence-test',
      configurationFingerprint: 'fence-test',
      client: () => client,
      isCurrent: () => true,
    );
    final context = PlacementRequestContext(
      request: fixture.request,
      lease: SurfaceAssignmentKeyProvider.captureKeylessLease(),
      capturedAt: DateTime.utc(2026, 10, 3),
      isCurrent: () => current,
    );
    String? reason;
    PlacementNoAnswerCause? cause;
    final pending = registry.fetchBatch(context,
        onNoAnswer: (why, [detail]) => (reason, cause) = (why, detail));
    await posted.future;
    current = false;
    reply.complete(http.Response.bytes(fixture.response.canonicalBytes, 200));

    expect(await pending, isNull);
    expect(reason, placementStaleReason);
    expect(cause, isA<PlacementNoAnswerStale>());
    expect(
        cause!.describe(),
        "Restage's configuration, user identity or consent changed while the "
        'request was being made. The request was dropped. '
        "It's retried on the next mount.");
  });

  test('a decision whose routed-on fact changed names the fact', () async {
    final fixture = readPlacementDeliveryFixture();
    final response = placementFixtureResponse(fixture.request,
        cacheValidityOverrides: const {
          'consultedBuiltIns': ['daysSinceInstall']
        });
    final client = RestageRpcClient(
      baseUrl: 'https://example.com',
      apiKey: 'rs_pk_test',
      httpClient: MockClient((http.Request wire) async =>
          placementFixtureArtifact(wire) ??
          http.Response.bytes(response.canonicalBytes, 200)),
    );
    addTearDown(client.close);
    final fetched = await client.fetchPlacements(fixture.request,
        publicationGuard: () => true) as PlacementBatchResolvedV1;
    final decision = fetched.decisions.first as PlacementBatchAvailableV1;
    final document = placementArtifactsFor(fetched)!
        .publications[decision.publicDelivery.actualPublication]!;
    final registry = PlacementRegistry(
      scope: 'facts-test',
      configurationFingerprint: 'facts-test',
      client: () => client,
      isCurrent: () => true,
    );
    PlacementLapse? lapse(List<String> changed) => PlacementDeliveryAdmission(
          decision: decision,
          context: PlacementRequestContext(
            request: fixture.request,
            lease: SurfaceAssignmentKeyProvider.captureKeylessLease(),
            capturedAt: DateTime.utc(2026, 10, 3),
            isCurrent: () => true,
            changedFacts: (consulted) => [
              for (final fact in changed)
                if (consulted.contains(fact)) fact,
            ],
          ),
          host: fixture.request.buildContract
              .contractsByHash[decision.descriptor.hostContractHash]!,
          registry: registry,
          document: document,
        ).lapse;
    final changed = lapse(['daysSinceInstall']);
    expect(changed?.$1, placementStaleReason);
    expect(
        changed?.$2?.describe(),
        "the device's install age changed after this decision was made. The "
        "decision wasn't shown. It's retried on the next mount.");
    // A fact the decision was not routed on does not stale it.
    expect(
        lapse(['country'])?.$2,
        isNot(isA<PlacementNoAnswerStale>().having((cause) => cause.change,
            'change', PlacementStaleChange.deviceFacts)));
  });

  test('a credential the service no longer holds is retired for registration',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = SurfaceAssignmentCredentialStore(
      namespace: 'placements',
      actor: () async => 'actor',
      identityGeneration: () => 0,
      onRetentionRollover: () {},
    );
    SurfaceAssignmentKeyProvider.install(
      key: store.resolve,
      identityGeneration: () => store.generation,
      registration: store.capture,
      confirmedKey: () => store.currentHandle,
      refuseRegistration: store.refuse,
    );
    addTearDown(SurfaceAssignmentKeyProvider.clear);
    final handle = 'ic1.${'a' * 64}';
    final attempt = (await store.capture())!;
    final now = DateTime.now().microsecondsSinceEpoch;
    expect(
        await store.confirm(
            attempt: attempt,
            localRequestStartMicros: now,
            credentialHandle: handle,
            expiresAtMicros: now + Duration.microsecondsPerDay,
            serverNowMicros: now),
        isTrue);
    final lease = await SurfaceAssignmentKeyProvider.captureLease();
    expect(lease.registration!.credentialHandle, handle);

    final fixture = readPlacementDeliveryFixture();
    final request = PlacementBatchRequestV1.fromJson({
      ...fixture.request.toJson(),
      'mode': 'mount',
      'assignmentKey': handle,
    });
    final refused = PlacementBatchResolvedV1(
      request: request,
      expectedTarget: fixture.target,
      decisions: placementFixtureResponse(request).decisions,
      registrationRefused: true,
    );
    final client = RestageRpcClient(
      baseUrl: 'https://example.com',
      apiKey: 'rs_pk_test',
      httpClient: MockClient((http.Request wire) async =>
          placementFixtureArtifact(wire) ??
          http.Response.bytes(refused.canonicalBytes, 200)),
    );
    addTearDown(client.close);
    await expectLater(
        client.fetchPlacements(request,
            publicationGuard: () => true, registrationLease: lease),
        throwsA(isA<PlacementRegistrationRetired>()));

    // The next request carries a fresh registration tuple, not the handle.
    final next = await SurfaceAssignmentKeyProvider.captureLease();
    expect(next.registration!.credentialHandle, isNull);
    expect(
        next.registration!.registrationNonce, isNot(attempt.registrationNonce));
  });

  test('a refusal of a handle this device did not present retires nothing',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = SurfaceAssignmentCredentialStore(
      namespace: 'placements',
      actor: () async => 'actor',
      identityGeneration: () => 0,
      onRetentionRollover: () {},
    );
    SurfaceAssignmentKeyProvider.install(
      key: store.resolve,
      identityGeneration: () => store.generation,
      registration: store.capture,
      confirmedKey: () => store.currentHandle,
      refuseRegistration: store.refuse,
    );
    addTearDown(SurfaceAssignmentKeyProvider.clear);
    final handle = 'ic1.${'a' * 64}';
    final attempt = (await store.capture())!;
    final now = DateTime.now().microsecondsSinceEpoch;
    expect(
        await store.confirm(
            attempt: attempt,
            localRequestStartMicros: now,
            credentialHandle: handle,
            expiresAtMicros: now + Duration.microsecondsPerDay,
            serverNowMicros: now),
        isTrue);
    final lease = await SurfaceAssignmentKeyProvider.captureLease();
    expect(lease.registration!.credentialHandle, handle);

    final fixture = readPlacementDeliveryFixture();
    final request = PlacementBatchRequestV1.fromJson({
      ...fixture.request.toJson(),
      'mode': 'mount',
      'assignmentKey': 'ic1.${'c' * 64}',
    });
    final refused = PlacementBatchResolvedV1(
      request: request,
      expectedTarget: fixture.target,
      decisions: placementFixtureResponse(request).decisions,
      registrationRefused: true,
    );
    final client = RestageRpcClient(
      baseUrl: 'https://example.com',
      apiKey: 'rs_pk_test',
      httpClient: MockClient((http.Request wire) async =>
          placementFixtureArtifact(wire) ??
          http.Response.bytes(refused.canonicalBytes, 200)),
    );
    addTearDown(client.close);
    final fetched = await client.fetchPlacements(request,
        publicationGuard: () => true, registrationLease: lease);
    expect(fetched, isA<PlacementBatchResolvedV1>());

    // The device keeps its own confirmed handle.
    final next = await SurfaceAssignmentKeyProvider.captureLease();
    expect(next.registration!.credentialHandle, handle);
  });

  test('a closed publication fence never posts a placement request', () async {
    final fixture = readPlacementDeliveryFixture();
    var requests = 0;
    final client = RestageRpcClient(
      baseUrl: 'https://example.com',
      apiKey: 'rs_pk_test',
      httpClient: MockClient((_) async {
        requests++;
        return http.Response.bytes(fixture.response.canonicalBytes, 200);
      }),
    );
    addTearDown(client.close);

    await expectLater(
      client.fetchPlacements(fixture.request, publicationGuard: () => false),
      throwsA(isA<SurfaceRequestPublicationRejected>()),
    );
    expect(requests, 0);
  });
}
