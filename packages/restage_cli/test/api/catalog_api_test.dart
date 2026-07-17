import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/src/api/catalog_api.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/credentials/credential.dart';
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
  group('CatalogApi.push', () {
    test('posts a plain catalogJson string to catalog.push and returns the '
        'stored version', () async {
      late Map<String, dynamic> seenBody;
      final client = MockClient((request) async {
        seenBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('7', 200);
      });

      final version = await CatalogApi(_apiWithClient(client)).push(
        project: 'demo',
        app: 'mobile',
        catalogJson: '{"schemaVersion":1,"widgets":[]}',
      );

      expect(version, 7);
      expect(seenBody['method'], 'push');
      expect(seenBody['projectSlug'], 'demo');
      expect(seenBody['appSlug'], 'mobile');
      expect(seenBody['catalogJson'], '{"schemaVersion":1,"widgets":[]}');
      expect(seenBody['catalogJson'], isNot(startsWith("decode('")));
      expect(seenBody.containsKey('organizationId'), isFalse);
    });

    test('threads organizationId when provided', () async {
      late Map<String, dynamic> seenBody;
      final client = MockClient((request) async {
        seenBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('3', 200);
      });

      final version = await CatalogApi(_apiWithClient(client)).push(
        project: 'demo',
        app: 'mobile',
        catalogJson: '{}',
        organizationId: 42,
      );

      expect(version, 3);
      expect(seenBody['organizationId'], 42);
    });

    test(
      'throws RestageApiException whose body decodes to CatalogTooLarge',
      () async {
        final client = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'className': 'CatalogTooLargeException',
              'data': {
                '__className__': 'CatalogTooLargeException',
                'maxBytes': 524288,
                'actualBytes': 524289,
              },
            }),
            400,
          );
        });

        Object? thrown;
        try {
          await CatalogApi(
            _apiWithClient(client),
          ).push(project: 'demo', app: 'mobile', catalogJson: '{}');
        } on RestageApiException catch (e) {
          thrown = e;
        }

        expect(thrown, isA<RestageApiException>());
        final decoded = decodeCatalogTypedException(
          (thrown! as RestageApiException).body,
        );
        expect(decoded, isA<CatalogTooLarge>());
      },
    );
  });
}
