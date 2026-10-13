import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/src/api/render_bundle_api.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/credentials/credential.dart';
import 'package:test/test.dart';

void main() {
  const credential = Credential(
    endpoint: 'http://api.restage.localhost:8080',
    kind: CredentialKind.authKey,
    authToken: 'key-id:private-key',
  );
  final endpoint = Uri.parse('http://api.restage.localhost:8080');
  final localBundleOrigin = Uri.parse('http://bundles.restage.localhost:8081');

  test('lists the heads an app holds, environment heads first', () async {
    final rpc = _FakeRestageApi()
      ..headsResponse = <String, Object?>{
        'appId': 4,
        'environmentHeads': <Object?>[
          <String, Object?>{
            'head': 'staging',
            'version': versionView(3, libraries: {'acme.widgets': 2}),
            'updatedAt': DateTime.utc(2030).toIso8601String(),
          },
        ],
        'personalHeads': <Object?>[
          <String, Object?>{
            'head': 'user/alice',
            'version': versionView(2),
            'ownerDisplayName': 'Alice',
            'updatedAt': DateTime.utc(2029).toIso8601String(),
          },
        ],
      };
    final api = RenderBundleApi(
      rpc: rpc,
      apiEndpoint: endpoint,
      credential: credential,
      trustedBundleOrigin: localBundleOrigin,
    );

    final heads = await api.listHeads(
      project: 'demo',
      app: 'mobile',
      organizationId: 7,
    );

    expect(rpc.calls, <String>['listHeads']);
    expect(rpc.lastArgs, <String, dynamic>{
      'projectSlug': 'demo',
      'appSlug': 'mobile',
      'organizationId': 7,
    });
    expect(heads.map((head) => head.head), <String>['staging', 'user/alice']);
    expect(heads.map((head) => head.version), <int>[3, 2]);
    expect(heads.first.libraries, {'acme.widgets': 2});
    expect(heads.last.libraries, isEmpty);
    expect(heads.first.ownerDisplayName, isNull);
    expect(heads.last.ownerDisplayName, 'Alice');
    expect(heads.first.updatedAt, DateTime.utc(2030));
  });

  test('refuses a head listing that is not status-safe', () async {
    final valid = <String, Object?>{
      'head': 'staging',
      'version': versionView(3),
      'updatedAt': DateTime.utc(2030).toIso8601String(),
    };
    final broken = <List<Object?>>[
      <Object?>[
        <String, Object?>{...valid, 'head': 'Staging'},
      ],
      <Object?>[
        <String, Object?>{...valid, 'version': versionView(0)},
      ],
      <Object?>[
        <String, Object?>{...valid, 'version': 3},
      ],
      <Object?>[
        <String, Object?>{
          ...valid,
          'version': versionView(3, manifestJson: '{"formatVersion":1}'),
        },
      ],
      <Object?>[
        <String, Object?>{...valid, 'updatedAt': '2030-01-01T00:00:00'},
      ],
      <Object?>[valid, valid],
      <Object?>['staging'],
    ];
    for (final environmentHeads in broken) {
      final rpc = _FakeRestageApi()
        ..headsResponse = <String, Object?>{
          'appId': 4,
          'environmentHeads': environmentHeads,
          'personalHeads': <Object?>[],
        };
      final api = RenderBundleApi(
        rpc: rpc,
        apiEndpoint: endpoint,
        credential: credential,
        trustedBundleOrigin: localBundleOrigin,
      );
      await expectLater(
        api.listHeads(project: 'demo', app: 'mobile', organizationId: 7),
        throwsA(isA<RenderBundleUploadException>()),
        reason: environmentHeads.toString(),
      );
    }
  });

  test('an empty app or project scope fails before RPC', () async {
    final rpc = _FakeRestageApi();
    final api = RenderBundleApi(
      rpc: rpc,
      apiEndpoint: endpoint,
      credential: credential,
      trustedBundleOrigin: localBundleOrigin,
    );
    for (final scope in <(String, String)>[('', 'mobile'), ('demo', '')]) {
      await expectLater(
        api.listHeads(project: scope.$1, app: scope.$2, organizationId: 7),
        throwsA(isA<RenderBundleUploadException>()),
        reason: scope.toString(),
      );
    }
    expect(rpc.calls, isEmpty);
  });

  test('prepares one typed redacted browser bootstrap', () async {
    final rpc = _FakeRestageApi()
      ..bootstrapResponse = <String, Object?>{
        'renderBundleId': 17,
        'bootstrapUrl':
            'http://b-17.restage.localhost:8081/render-bundles/v1/b/17/bootstrap',
        'bootstrapGrant': 'a' * 64,
        'expiresAt': '2030-01-01T00:00:00.000Z',
      };
    final api = RenderBundleApi(
      rpc: rpc,
      apiEndpoint: endpoint,
      credential: credential,
      trustedBundleOrigin: localBundleOrigin,
    );

    final bootstrap = await api.prepareBrowserBootstrap(
      project: 'demo',
      app: 'mobile',
      head: 'staging',
      organizationId: 7,
      trustedBundleOrigin: localBundleOrigin,
    );

    expect(bootstrap.renderBundleId, 17);
    expect(bootstrap.bootstrapGrant, 'a' * 64);
    expect('$bootstrap', isNot(contains('aaaa')));
    expect(rpc.calls, ['prepareBrowserBootstrap']);
  });

  test(
    'rejects a bootstrap served from another bundle execution origin',
    () async {
      final rpc = _FakeRestageApi()
        ..bootstrapResponse = <String, Object?>{
          'renderBundleId': 17,
          'bootstrapUrl':
              'http://b-18.restage.localhost:8081/render-bundles/v1/b/17/bootstrap',
          'bootstrapGrant': 'a' * 64,
          'expiresAt': '2030-01-01T00:00:00.000Z',
        };
      final api = RenderBundleApi(
        rpc: rpc,
        apiEndpoint: endpoint,
        credential: credential,
        trustedBundleOrigin: localBundleOrigin,
      );

      await expectLater(
        api.prepareBrowserBootstrap(
          project: 'demo',
          app: 'mobile',
          head: 'staging',
          trustedBundleOrigin: localBundleOrigin,
        ),
        throwsA(isA<RenderBundleUploadException>()),
      );
    },
  );

  test('rejects invalid local bootstrap authorities before RPC', () async {
    for (final origin in <String>[
      'http://localhost:8081',
      'http://127.0.0.1:8081',
      'http://control.restage.localhost:8081',
      'http://bundles.restage.localhost:8080',
    ]) {
      final rpc = _FakeRestageApi();
      final api = RenderBundleApi(
        rpc: rpc,
        apiEndpoint: endpoint,
        credential: credential,
        trustedBundleOrigin: Uri.parse(origin),
      );

      await expectLater(
        api.prepareBrowserBootstrap(
          project: 'demo',
          app: 'mobile',
          head: 'staging',
          trustedBundleOrigin: Uri.parse(origin),
        ),
        throwsA(isA<RenderBundleUploadException>()),
      );
      expect(rpc.calls, isEmpty, reason: origin);
    }
  });

  test('an invalid browser-bootstrap head fails before RPC', () async {
    final rpc = _FakeRestageApi();
    final api = RenderBundleApi(
      rpc: rpc,
      apiEndpoint: endpoint,
      credential: credential,
      trustedBundleOrigin: localBundleOrigin,
    );

    await expectLater(
      api.prepareBrowserBootstrap(
        project: 'demo',
        app: 'mobile',
        head: 'Staging',
        trustedBundleOrigin: localBundleOrigin,
      ),
      throwsA(isA<RenderBundleUploadException>()),
    );
    expect(rpc.calls, isEmpty);
  });
}

final class _FakeRestageApi extends RestageApi {
  _FakeRestageApi()
    : super(
        endpoint: Uri.parse('http://api.restage.localhost:8080'),
        httpClient: MockClient((_) async => http.Response('', 500)),
      );

  Object? discoverResponse;
  Object? bootstrapResponse;
  Object? headsResponse;
  final List<String> calls = <String>[];
  Map<String, dynamic>? lastArgs;

  @override
  Future<dynamic> call(
    String endpointName,
    String methodName,
    Map<String, dynamic> args,
  ) async {
    expect(endpointName, 'renderBundle');
    calls.add(methodName);
    lastArgs = args;
    if (methodName == 'discover') return discoverResponse;
    if (methodName == 'listHeads') return headsResponse;
    if (methodName == 'prepareBrowserBootstrap') return bootstrapResponse;
    throw StateError('unexpected method');
  }
}

/// One stored version as the server lists it under a head.
Map<String, Object?> versionView(
  int version, {
  Map<String, int> libraries = const {},
  String? manifestJson,
}) => <String, Object?>{
  'renderBundleId': 40 + version,
  'appId': 4,
  'version': version,
  'contentHash': 'sha256:${'0' * 64}',
  'engineSetId': '1' * 64,
  'capabilityManifestJson':
      manifestJson ??
      jsonEncode(<String, Object?>{
        'formatVersion': 1,
        'catalog': <String, Object?>{
          'libraries': <String, Object?>{
            for (final entry in libraries.entries)
              entry.key: <String, Object?>{'capabilityVersion': entry.value},
          },
          'widgets': <Object?>[],
        },
      }),
  'byteLength': 1024,
  'sourceDirty': false,
  'uploadedAt': DateTime.utc(2030).toIso8601String(),
};
