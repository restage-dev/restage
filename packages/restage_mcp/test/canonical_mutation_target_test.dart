import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/api.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    as measurement;
import 'package:test/test.dart';

import '_support/harness.dart';

/// The target block the canonical mutation tool reports back to its caller.
///
/// Both experiment and mutation tools resolve a target through one shared
/// helper, so this pins the shape the mutation tool publishes.
void main() {
  late Directory home;
  late FileCredentialStore store;

  setUp(() async {
    home = Directory.systemTemp.createTempSync('restage_mcp_mutation_target');
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

  test('reports the resolved target it addressed', () async {
    late Map<String, Object?> sentArguments;
    final connection = await connectServer(
      store: store,
      httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, Object?>;
        final directory = _targetDirectory(body['method']! as String);
        if (directory != null) return directory;
        sentArguments = body;
        return http.Response(jsonEncode(_wire(_acceptedResponse)), 200);
      }),
    );

    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_apply_canonical_mutation',
        arguments: {
          'canonicalRequestBase64': base64Encode(_request),
          'organizationId': 11,
          'projectSlug': 'checkout',
          'appSlug': 'app',
          'environmentSlug': 'production',
          'environmentTargetId': 31,
          'runtimePlane': 'live',
        },
      ),
    );

    expect(result.isError, isNot(true));
    expect(result.structuredContent!['target'], {
      'organizationId': 11,
      'appId': 23,
      'namedEnvironmentId': 37,
      'environmentTargetId': 31,
      'runtimePlane': 'live',
    });
    expect(sentArguments['method'], 'mutate');
    expect(sentArguments['appId'], 23);
    expect(sentArguments['environmentTargetId'], 31);
  });

  test('refuses when the declared target resolves to no exact row', () async {
    var reachedRoute = false;
    final connection = await connectServer(
      store: store,
      httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, Object?>;
        final method = body['method']! as String;
        if (method == 'listEnvironmentTargets') {
          return http.Response(jsonEncode(<Object?>[]), 200);
        }
        final directory = _targetDirectory(method);
        if (directory != null) return directory;
        reachedRoute = true;
        return http.Response(jsonEncode(_wire(_acceptedResponse)), 200);
      }),
    );

    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_apply_canonical_mutation',
        arguments: {
          'canonicalRequestBase64': base64Encode(_request),
          'organizationId': 11,
          'projectSlug': 'checkout',
          'appSlug': 'app',
          'environmentSlug': 'production',
          'environmentTargetId': 31,
          'runtimePlane': 'live',
        },
      ),
    );

    expect(result.isError, isTrue);
    expect(reachedRoute, isFalse);
  });
}

final _target = measurement.TargetCoordinate(
  organizationId: measurement.OrganizationId(11),
  appId: measurement.ApplicationId(23),
  environmentTargetId: measurement.EnvironmentTargetId(31),
  namedEnvironmentId: measurement.NamedEnvironmentId(37),
  runtimePlane: measurement.RuntimePlane.live,
);

final _request = measurement.CanonicalJsonCodec.encode({
  'coordinate': {'target': _target.toJson()},
  'kind': 'programmaticReadDraftRequest',
});

final _acceptedResponse = measurement.CanonicalJsonCodec.encode(const {
  'kind': 'programmaticDraftReadResponse',
});

String _wire(List<int> bytes) => "decode('${base64Encode(bytes)}', 'base64')";

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
