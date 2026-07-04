import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/src/api/paywall_api.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/surface_models.dart';
import 'package:restage_cli/src/credentials/credential.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

Credential _stubCredential() => const Credential(
  endpoint: 'http://localhost:8080/',
  kind: CredentialKind.authKey,
  authToken: 'kid:secret',
);

RestageApi _apiWithClient(http.Client client) => RestageApi(
  endpoint: Uri.parse('http://localhost:8080/'),
  httpClient: client,
  credential: _stubCredential(),
);

/// The backend ByteData wire form: `decode('<base64>', 'base64')`.
String _byteDataWire(List<int> bytes) =>
    "decode('${base64Encode(bytes)}', 'base64')";

/// The derived capability floor a caller stamps at save time (codegen-supplied
/// in production; a fixed test value here).
const _testMinClient = 2;

/// A stored paywall frame: the canonical [BlobSurfacePayload] bytes the
/// surface store holds, in the ByteData wire form the backend returns.
String _blobFrameWire(List<int> blob) {
  final canonical = BlobSurfacePayload(
    minClient: _testMinClient,
    blob: Uint8List.fromList(blob),
  ).canonicalBytes;
  return _byteDataWire(canonical);
}

/// A stored flow-shaped paywall frame (a navigation-lowered paywall): the
/// canonical [FlowSurfacePayload] bytes for a minimal one-screen flow, in the
/// ByteData wire form. Used to prove `load` degrades on a flow paywall instead
/// of crashing on a blob cast.
String _flowFrameWire() {
  final blob = Uint8List.fromList(utf8.encode('rfw-screen-blob'));
  final json = <String, Object?>{
    'flow': 'demo_flow',
    'initial': 'a',
    'minClient': 1,
    'schemaVersion': 1,
    'screenArtifacts': {
      'a': {
        'contentHash': CapabilitySidecar.hashBlob(blob),
        'minClient': 1,
        'path': 'a.rfw',
        'schemaVersion': 1,
        'version': 1,
      },
    },
    'states': {
      'a': {
        'kind': 'screen',
        'screen': 'a',
        'on': {
          'go': {'target': 'done', 'type': 'goto'},
        },
      },
      'done': {'kind': 'end', 'result': <String, Object?>{}},
    },
    'version': 1,
  };
  final canonical = FlowSurfacePayload(
    flowDocument: FlowDocumentCodec.decodeJson(jsonEncode(json)),
    screenBlobs: {'a': blob},
  ).canonicalBytes;
  return _byteDataWire(canonical);
}

void main() {
  group('PaywallApi.list', () {
    test('sends a surface/list POST (surfaceType: paywall) and adapts the '
        'summaries to PaywallSummary', () async {
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        return http.Response(
          jsonEncode([
            {
              '__className__': 'SurfaceSummary',
              'surfaceType': 'paywall',
              'slug': 'a',
              'name': 'A',
              'draftUpdatedAt': '2026-05-01T12:34:56.000Z',
              'publishedVersionByEnvironment': {'dev': 1},
            },
            {
              '__className__': 'SurfaceSummary',
              'surfaceType': 'paywall',
              'slug': 'b',
              'name': 'B',
              'draftUpdatedAt': '2026-05-02T01:02:03.000Z',
              'publishedVersionByEnvironment': <String, int?>{},
            },
          ]),
          200,
        );
      });

      final summaries = await PaywallApi(
        _apiWithClient(client),
      ).list(project: 'demo', app: 'mobile');

      expect(seen.url.toString(), endsWith('surface'));
      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      expect(body['method'], 'list');
      expect(body['surfaceType'], 'paywall');
      expect(body['projectSlug'], 'demo');
      expect(body['appSlug'], 'mobile');

      expect(summaries.length, 2);
      expect(summaries[0].slug, 'a');
      expect(summaries[0].publishedVersionByEnvironment, {'dev': 1});
      expect(summaries[1].slug, 'b');
    });
  });

  group('PaywallApi.save', () {
    test('uploads the caller-framed canonical bytes verbatim to surface/save '
        '(surfaceType: paywall) — byte-transparent, no re-framing', () async {
      late Map<String, dynamic> seenBody;
      final client = MockClient((request) async {
        seenBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('null', 200);
      });

      final blob = Uint8List.fromList(<int>[1, 2, 3, 4, 5]);
      final canonical = BlobSurfacePayload(
        minClient: _testMinClient,
        blob: blob,
      ).canonicalBytes;
      await PaywallApi(_apiWithClient(client)).save(
        project: 'demo',
        app: 'mobile',
        paywall: 'hello',
        canonicalBytes: canonical,
      );

      expect(seenBody['method'], 'save');
      expect(seenBody['surfaceType'], 'paywall');
      expect(seenBody['projectSlug'], 'demo');
      expect(seenBody['appSlug'], 'mobile');
      expect(seenBody['surfaceSlug'], 'hello');

      // Byte-transparent: the wire `bytes` are exactly the canonical frame the
      // caller supplied (a flow frame would pass through identically), so the
      // paywall save layer can never re-wrap a flow paywall inside a blob.
      final wireBytes = seenBody['bytes'] as String;
      expect(wireBytes, startsWith("decode('"));
      expect(wireBytes, endsWith("', 'base64')"));
      final base64Slice = wireBytes.substring(8, wireBytes.length - 12);
      final decoded = base64Decode(base64Slice);
      expect(decoded, orderedEquals(canonical));
      final payload = SurfacePayload.decode(decoded);
      expect(payload, isA<BlobSurfacePayload>());
      expect((payload as BlobSurfacePayload).blob, equals(blob));
      expect(payload.minClient, _testMinClient);
    });
  });

  group('PaywallApi.publish', () {
    test('returns the new version number on success', () async {
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['method'], 'publish');
        expect(body['surfaceType'], 'paywall');
        expect(body['surfaceSlug'], 'hello');
        return http.Response('7', 200);
      });

      final version = await PaywallApi(_apiWithClient(client)).publish(
        project: 'demo',
        app: 'mobile',
        paywall: 'hello',
        environment: 'dev',
      );

      expect(version, 7);
    });

    test(
      'throws RestageApiException whose body decodes to SurfacePublishConflict',
      () async {
        final client = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'className': 'SurfacePublishConflictException',
              'data': {
                '__className__': 'SurfacePublishConflictException',
                'surfaceSlug': 'hello',
                'environmentSlug': 'dev',
              },
            }),
            400,
          );
        });

        Object? thrown;
        try {
          await PaywallApi(_apiWithClient(client)).publish(
            project: 'demo',
            app: 'mobile',
            paywall: 'hello',
            environment: 'dev',
          );
        } on RestageApiException catch (e) {
          thrown = e;
        }

        expect(thrown, isA<RestageApiException>());
        final decoded = decodeSurfaceTypedException(
          (thrown! as RestageApiException).body,
        );
        expect(decoded, isA<SurfacePublishConflict>());
      },
    );
  });

  group('PaywallApi.load', () {
    test(
      'reads surface/load (surfaceType: paywall) and unwraps the inner blob',
      () async {
        final blob = <int>[10, 20, 30, 40];
        late Map<String, dynamic> seenBody;
        final client = MockClient((request) async {
          seenBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode(_blobFrameWire(blob)), 200);
        });

        final result = await PaywallApi(
          _apiWithClient(client),
        ).load(project: 'demo', app: 'mobile', paywall: 'hello');

        expect(seenBody['method'], 'load');
        expect(seenBody['surfaceType'], 'paywall');
        expect(seenBody['projectSlug'], 'demo');
        expect(seenBody['appSlug'], 'mobile');
        expect(seenBody['surfaceSlug'], 'hello');
        expect(result, equals(blob));
      },
    );

    test('passes the single-zero-byte skeleton through unchanged', () async {
      final wire = _byteDataWire(<int>[0]);
      final client = MockClient(
        (_) async => http.Response(jsonEncode(wire), 200),
      );

      final result = await PaywallApi(
        _apiWithClient(client),
      ).load(project: 'd', app: 'm', paywall: 'h');

      expect(result, equals(Uint8List.fromList(<int>[0])));
    });

    test('fails loud with a clear Exception on a flow paywall '
        '(no blob-cast crash)', () async {
      // A navigation-lowered paywall is stored as a FlowSurfacePayload; it has
      // no single inner blob to download. `load` must fail loud with a
      // catchable Exception, not crash on a raw `as BlobSurfacePayload` cast.
      final client = MockClient(
        (_) async => http.Response(jsonEncode(_flowFrameWire()), 200),
      );

      await expectLater(
        () => PaywallApi(
          _apiWithClient(client),
        ).load(project: 'd', app: 'm', paywall: 'flow-pw'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString().toLowerCase(),
            'message',
            contains('flow'),
          ),
        ),
      );
    });
  });

  group('PaywallApi.getPublishedVersion', () {
    test('returns the version number', () async {
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['method'], 'getPublishedVersion');
        expect(body['surfaceType'], 'paywall');
        expect(body['surfaceSlug'], 'h');
        expect(body['environmentSlug'], 'production');
        return http.Response('5', 200);
      });

      final version = await PaywallApi(_apiWithClient(client))
          .getPublishedVersion(
            project: 'd',
            app: 'm',
            paywall: 'h',
            environment: 'production',
          );

      expect(version, 5);
    });

    test('returns null when nothing has been published', () async {
      final client = MockClient((_) async => http.Response('null', 200));

      final version = await PaywallApi(_apiWithClient(client))
          .getPublishedVersion(
            project: 'd',
            app: 'm',
            paywall: 'h',
            environment: 'production',
          );

      expect(version, isNull);
    });
  });

  group('organizationId passthrough', () {
    test(
      'list includes organizationId when provided, omits it when null',
      () async {
        Map<String, dynamic>? seen;
        final client = MockClient((request) async {
          seen = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('[]', 200);
        });
        final api = PaywallApi(_apiWithClient(client));

        await api.list(project: 'd', app: 'm', organizationId: 42);
        expect(seen!['organizationId'], 42);

        await api.list(project: 'd', app: 'm');
        expect(seen!.containsKey('organizationId'), isFalse);
      },
    );

    test(
      'publish / load / getPublishedVersion thread organizationId',
      () async {
        final seen = <String, Map<String, dynamic>>{};
        final client = MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          seen[body['method'] as String] = body;
          switch (body['method']) {
            case 'load':
              return http.Response(jsonEncode(_byteDataWire(<int>[0])), 200);
            default:
              return http.Response('1', 200);
          }
        });
        final api = PaywallApi(_apiWithClient(client));

        await api.publish(
          project: 'd',
          app: 'm',
          paywall: 'h',
          environment: 'e',
          organizationId: 7,
        );
        await api.load(project: 'd', app: 'm', paywall: 'h', organizationId: 7);
        await api.getPublishedVersion(
          project: 'd',
          app: 'm',
          paywall: 'h',
          environment: 'e',
          organizationId: 7,
        );

        expect(seen['publish']!['organizationId'], 7);
        expect(seen['load']!['organizationId'], 7);
        expect(seen['getPublishedVersion']!['organizationId'], 7);
      },
    );
  });
}
