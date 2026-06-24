import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/surface_api.dart';
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

void main() {
  group('SurfaceApi.save', () {
    test('posts to the surface endpoint, threads surfaceType.wireName, and '
        'encodes the bytes as the `decode(...)` wire fragment', () async {
      late http.Request seen;
      late Map<String, dynamic> seenBody;
      final client = MockClient((request) async {
        seen = request;
        seenBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('null', 200);
      });

      final bytes = Uint8List.fromList(<int>[9, 8, 7, 6, 5]);
      await SurfaceApi(_apiWithClient(client)).save(
        project: 'demo',
        app: 'mobile',
        surfaceType: SurfaceType.onboarding,
        surfaceSlug: 'first_run',
        bytes: bytes,
      );

      expect(seen.url.toString(), endsWith('surface'));
      expect(seenBody['method'], 'save');
      expect(seenBody['projectSlug'], 'demo');
      expect(seenBody['appSlug'], 'mobile');
      expect(seenBody['surfaceType'], 'onboarding');
      expect(seenBody['surfaceSlug'], 'first_run');

      final wireBytes = seenBody['bytes'] as String;
      expect(wireBytes, startsWith("decode('"));
      expect(wireBytes, endsWith("', 'base64')"));
      final base64Slice = wireBytes.substring(8, wireBytes.length - 12);
      expect(base64Decode(base64Slice), equals(bytes));
    });

    test('threads message / survey wire names', () async {
      final seen = <String, dynamic>{};
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        seen[body['surfaceType'] as String] = body['surfaceType'];
        return http.Response('null', 200);
      });
      final api = SurfaceApi(_apiWithClient(client));
      final bytes = Uint8List.fromList(<int>[1]);

      await api.save(
        project: 'd',
        app: 'm',
        surfaceType: SurfaceType.message,
        surfaceSlug: 's',
        bytes: bytes,
      );
      await api.save(
        project: 'd',
        app: 'm',
        surfaceType: SurfaceType.survey,
        surfaceSlug: 's',
        bytes: bytes,
      );

      expect(seen.containsKey('message'), isTrue);
      expect(seen.containsKey('survey'), isTrue);
    });

    test('threads organizationId when provided, omits it when null', () async {
      Map<String, dynamic>? seen;
      final client = MockClient((request) async {
        seen = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('null', 200);
      });
      final api = SurfaceApi(_apiWithClient(client));
      final bytes = Uint8List.fromList(<int>[1]);

      await api.save(
        project: 'd',
        app: 'm',
        surfaceType: SurfaceType.onboarding,
        surfaceSlug: 's',
        bytes: bytes,
        organizationId: 13,
      );
      expect(seen!['organizationId'], 13);

      await api.save(
        project: 'd',
        app: 'm',
        surfaceType: SurfaceType.onboarding,
        surfaceSlug: 's',
        bytes: bytes,
      );
      expect(seen!.containsKey('organizationId'), isFalse);
    });
  });

  group('SurfaceApi.publish', () {
    test('returns the new version number on success', () async {
      late Map<String, dynamic> seenBody;
      final client = MockClient((request) async {
        seenBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('3', 200);
      });

      final version = await SurfaceApi(_apiWithClient(client)).publish(
        project: 'demo',
        app: 'mobile',
        surfaceType: SurfaceType.onboarding,
        surfaceSlug: 'first_run',
        environment: 'dev',
      );

      expect(version, 3);
      expect(seenBody['method'], 'publish');
      expect(seenBody['surfaceType'], 'onboarding');
      expect(seenBody['surfaceSlug'], 'first_run');
      expect(seenBody['environmentSlug'], 'dev');
    });

    test('threads organizationId when provided, omits it when null', () async {
      Map<String, dynamic>? seen;
      final client = MockClient((request) async {
        seen = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('1', 200);
      });
      final api = SurfaceApi(_apiWithClient(client));

      await api.publish(
        project: 'd',
        app: 'm',
        surfaceType: SurfaceType.onboarding,
        surfaceSlug: 's',
        environment: 'e',
        organizationId: 11,
      );
      expect(seen!['organizationId'], 11);

      await api.publish(
        project: 'd',
        app: 'm',
        surfaceType: SurfaceType.onboarding,
        surfaceSlug: 's',
        environment: 'e',
      );
      expect(seen!.containsKey('organizationId'), isFalse);
    });

    test('throws RestageApiException whose body decodes to '
        'SurfacePublishConflict', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'className': 'SurfacePublishConflictException',
            'data': {
              '__className__': 'SurfacePublishConflictException',
              'surfaceSlug': 'first_run',
              'environmentSlug': 'dev',
            },
          }),
          400,
        );
      });

      Object? thrown;
      try {
        await SurfaceApi(_apiWithClient(client)).publish(
          project: 'demo',
          app: 'mobile',
          surfaceType: SurfaceType.onboarding,
          surfaceSlug: 'first_run',
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
    });
  });
}
