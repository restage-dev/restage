import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/credentials/credential.dart';
import 'package:test/test.dart';

void main() {
  group('RestageApi.call', () {
    test('POSTs to <endpoint>/<endpointName> with JSON body containing the '
        'method name and args', () async {
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        return http.Response('null', 200);
      });
      final api = RestageApi(
        endpoint: Uri.parse('https://api.example.com/'),
        httpClient: client,
      );
      await api.call('auth', 'requestMagicLink', <String, dynamic>{
        'email': 'jane@example.com',
      });
      expect(seen.method, 'POST');
      expect(seen.url.toString(), 'https://api.example.com/auth');
      expect(seen.headers['content-type'], contains('application/json'));
      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      expect(body['method'], 'requestMagicLink');
      expect(body['email'], 'jane@example.com');
    });

    test('sends the Authorization header when a credential is supplied; '
        'authKey credentials wrap as basic <base64(authToken)>', () async {
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        return http.Response('null', 200);
      });
      final api = RestageApi(
        endpoint: Uri.parse('https://api.example.com/'),
        httpClient: client,
        credential: const Credential(
          endpoint: 'https://api.example.com/',
          kind: CredentialKind.authKey,
          authToken: '42:abc',
        ),
      );
      await api.call('paywall', 'list', const <String, dynamic>{});
      // "Basic " + base64("42:abc") = "Basic NDI6YWJj". The capital `B`
      // is required — see _buildAuthHeader's doc comment.
      expect(seen.headers['authorization'], 'Basic NDI6YWJj');
    });

    test(
      'omits the Authorization header when no credential is supplied',
      () async {
        late http.Request seen;
        final client = MockClient((request) async {
          seen = request;
          return http.Response('null', 200);
        });
        final api = RestageApi(
          endpoint: Uri.parse('https://api.example.com/'),
          httpClient: client,
        );
        await api.call('auth', 'whoami', const <String, dynamic>{});
        expect(seen.headers.containsKey('authorization'), isFalse);
      },
    );

    test('throws RestageApiException on non-200 responses', () async {
      final client = MockClient((_) async => http.Response('oh no', 500));
      final api = RestageApi(
        endpoint: Uri.parse('https://api.example.com/'),
        httpClient: client,
      );
      await expectLater(
        api.call('auth', 'whoami', const <String, dynamic>{}),
        throwsA(
          isA<RestageApiException>().having((e) => e.statusCode, 'status', 500),
        ),
      );
    });

    test('returns the decoded JSON body for 200 responses', () async {
      final client = MockClient(
        (_) async => http.Response('{"a":1,"b":"x"}', 200),
      );
      final api = RestageApi(
        endpoint: Uri.parse('https://api.example.com/'),
        httpClient: client,
      );
      final result = await api.call(
        'auth',
        'whoami',
        const <String, dynamic>{},
      );
      expect(result, <String, dynamic>{'a': 1, 'b': 'x'});
    });

    test('returns null for an empty 200 body', () async {
      final client = MockClient((_) async => http.Response('', 200));
      final api = RestageApi(
        endpoint: Uri.parse('https://api.example.com/'),
        httpClient: client,
      );
      expect(
        await api.call('auth', 'logout', const <String, dynamic>{}),
        isNull,
      );
    });

    test(
      'throws StateError when the credential carries an unsupported kind',
      () async {
        final client = MockClient((_) async => http.Response('null', 200));
        final api = RestageApi(
          endpoint: Uri.parse('https://api.example.com/'),
          httpClient: client,
          credential: const Credential(
            endpoint: 'https://api.example.com/',
            kind: 'futureKind',
            authToken: 'opaque',
          ),
        );
        await expectLater(
          api.call('auth', 'whoami', const <String, dynamic>{}),
          throwsStateError,
        );
      },
    );
  });

  group('RestageApi.call endpoint resolution', () {
    test('preserves a base path that lacks a trailing slash when resolving the '
        'RPC class name', () async {
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        return http.Response('null', 200);
      });
      // A base URL without a trailing slash must not drop its path segment:
      // `https://host/api` + `auth` resolves under `/api/`, not `/auth`.
      final api = RestageApi(
        endpoint: Uri.parse('https://api.example.com/api'),
        httpClient: client,
      );
      await api.call('auth', 'whoami', const <String, dynamic>{});
      expect(seen.url.toString(), 'https://api.example.com/api/auth');
    });

    test(
      'resolves a multi-segment relative path under a no-slash base',
      () async {
        late http.Request seen;
        final client = MockClient((request) async {
          seen = request;
          return http.Response('null', 200);
        });
        final api = RestageApi(
          endpoint: Uri.parse('https://api.example.com/api'),
          httpClient: client,
        );
        await api.call('v1/foo', 'doThing', const <String, dynamic>{});
        expect(seen.url.toString(), 'https://api.example.com/api/v1/foo');
      },
    );

    test('leaves a base that already ends in a slash unchanged', () async {
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        return http.Response('null', 200);
      });
      final api = RestageApi(
        endpoint: Uri.parse('https://api.example.com/api/'),
        httpClient: client,
      );
      await api.call('auth', 'whoami', const <String, dynamic>{});
      expect(seen.url.toString(), 'https://api.example.com/api/auth');
    });
  });

  group('isAcceptableTransport', () {
    test('accepts any https:// origin', () {
      expect(
        isAcceptableTransport(Uri.parse('https://api.example.com/')),
        isTrue,
      );
      expect(
        isAcceptableTransport(Uri.parse('https://10.0.0.5:9443/')),
        isTrue,
      );
    });

    test('accepts http:// only for loopback hosts', () {
      for (final endpoint in const [
        'http://localhost:8080/',
        'http://localhost.:8080/',
        'http://127.0.0.1:8080/',
        'http://127.0.0.2:8080/',
        'http://127.255.255.254:8080/',
        'http://[::1]:8080/',
        'http://[0:0:0:0:0:0:0:1]:8080/',
        'http://[::ffff:127.0.0.1]:8080/',
      ]) {
        expect(
          isAcceptableTransport(Uri.parse(endpoint)),
          isTrue,
          reason: endpoint,
        );
      }
    });

    test('rejects http:// on non-loopback hosts', () {
      for (final endpoint in const [
        'http://api.example.com/',
        'http://ip6-localhost:8080/',
        'http://10.0.0.5:8080/',
        'http://[::ffff:10.0.0.5]:8080/',
      ]) {
        expect(
          isAcceptableTransport(Uri.parse(endpoint)),
          isFalse,
          reason: endpoint,
        );
      }
    });

    test('rejects schemes other than http/https', () {
      expect(isAcceptableTransport(Uri.parse('ftp://example.com/')), isFalse);
      expect(isAcceptableTransport(Uri.parse('file:///tmp/x')), isFalse);
    });
  });

  group('RestageApi constructor', () {
    test(
      'rejects insecure endpoints before allocating the default HTTP client',
      () {
        final overrides = _CountingHttpOverrides();

        HttpOverrides.runWithHttpOverrides(() {
          expect(
            () => RestageApi(endpoint: Uri.parse('http://api.example.com/')),
            throwsA(isA<InsecureEndpointException>()),
          );
        }, overrides);

        expect(overrides.createdClients, 0);
      },
    );

    test(
      'throws InsecureEndpointException for http:// on a non-loopback host',
      () {
        expect(
          () => RestageApi(
            endpoint: Uri.parse('http://api.example.com/'),
            httpClient: MockClient((_) async => http.Response('null', 200)),
          ),
          throwsA(isA<InsecureEndpointException>()),
        );
      },
    );

    test('allows http:// localhost for local development', () {
      expect(
        () => RestageApi(
          endpoint: Uri.parse('http://localhost:8080/'),
          httpClient: MockClient((_) async => http.Response('null', 200)),
        ),
        returnsNormally,
      );
    });
  });
}

final class _CountingHttpOverrides extends HttpOverrides {
  int createdClients = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    createdClients += 1;
    return super.createHttpClient(context);
  }
}
