import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/src/api/render_bundle_api.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/credentials/credential.dart';
import 'package:restage_cli/src/render_bundles/bundle_source.dart';
import 'package:restage_cli/src/render_bundles/flutter_render_bundle_builder.dart';
import 'package:restage_cli/src/render_bundles/push_target.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  final bundleOrigin = Uri.parse('http://bundles.restage.localhost:8081');
  const blobUrl =
      'http://bundles.restage.localhost:8081/render-bundles/v1/blob';

  Uint8List bytes(String text) => Uint8List.fromList(utf8.encode(text));
  String hashOf(Uint8List value) => 'sha256:${crypto.sha256.convert(value)}';

  final index = bytes('<!doctype html>');
  final wasm = bytes('app payload');
  final skwasm = bytes('engine payload');
  final engineSet = RenderBundleEngineSet.fromFiles(
    flutterVersion: '3.99.0-0.1.pre',
    engineRevision: 'af7e796e161ae0bb1ff0758c71a7105418bd9ded',
    files: {'skwasm.wasm': skwasm},
  );
  final artifact = RenderBundleArtifact(
    appFiles: <String, Uint8List>{'index.html': index, 'main.dart.wasm': wasm},
    engineSet: engineSet,
  );
  const source = BundleSource(
    inRepository: true,
    commit: 'a91f2c3d4e5f60718293a4b5c6d7e8f901234567',
    dirty: true,
  );

  Map<String, Object?> ticket({
    List<String> missingContentHashes = const <String>[],
    int uploadConcurrency = 3,
    int maxFileTransferBytes = 24 * 1024 * 1024,
    String blob = blobUrl,
  }) => <String, Object?>{
    'uploadToken': 'token-1',
    'headReference': 'staging',
    'expiresAt': DateTime.utc(2030).toIso8601String(),
    'blobUploadUrl': blob,
    'missingContentHashes': missingContentHashes,
    'uploadConcurrency': uploadConcurrency,
    'maxFileTransferBytes': maxFileTransferBytes,
  };

  Map<String, Object?> pushResult({int version = 4}) => <String, Object?>{
    'version': <String, Object?>{
      'version': version,
      'contentHash': 'sha256:${'a' * 64}',
    },
    'organizationId': 7,
    'organizationSlug': 'acme',
    'headReference': 'staging',
    'reactivated': false,
  };

  RenderBundleApi apiWith(_FakeUploadRpc rpc, http.Client uploadClient) =>
      RenderBundleApi(
        rpc: rpc,
        trustedBundleOrigin: bundleOrigin,
        uploadClient: uploadClient,
      );

  test('sends the manifest, the missing files, then commits', () async {
    final rpc = _FakeUploadRpc(
      prepared: <Object?>[
        ticket(missingContentHashes: <String>[hashOf(wasm)]),
      ],
      committed: pushResult(),
    );
    final sent = <Uri, List<int>>{};
    final api = apiWith(
      rpc,
      MockClient((request) async {
        sent[request.url] = gzip.decode(request.bodyBytes);
        expect(request.headers['content-encoding'], 'gzip');
        // The token is a capability, so it travels in the header.
        expect(request.headers[renderBundleUploadTokenHeader], 'token-1');
        expect(
          request.url.queryParameters.keys,
          isNot(contains('uploadToken')),
        );
        return http.Response('', 204);
      }),
    );

    final outcome = await api.push(
      project: 'demo',
      app: 'mobile',
      target: const BundlePushTarget.environment('staging'),
      artifact: artifact,
      source: source,
      organizationId: 7,
    );

    expect(rpc.calls, <String>['prepare', 'commit']);
    // commit carries the same manifest prepare validated.
    expect(rpc.commitArgs!['manifest'], rpc.prepareArgs!['manifest']);
    expect(rpc.commitArgs!['uploadToken'], 'token-1');
    expect(rpc.prepareArgs!['appSlug'], 'mobile');
    expect(rpc.prepareArgs!['environment'], 'staging');
    expect(rpc.prepareArgs!['personal'], isFalse);
    expect(rpc.prepareArgs!['engineSet'], engineSet.canonicalForm);
    expect(rpc.prepareArgs!.containsKey('engineSetId'), isFalse);
    expect(rpc.prepareArgs!['provenance'], <String, Object?>{
      'sourceCommit': 'a91f2c3d4e5f60718293a4b5c6d7e8f901234567',
      'sourceDirty': true,
    });
    // The manifest holds the app's own files, sorted; the engine never
    // travels with a push.
    expect(rpc.prepareArgs!['manifest'], <Map<String, Object?>>[
      <String, Object?>{
        'path': 'index.html',
        'contentHash': hashOf(index),
        'byteLength': index.length,
      },
      <String, Object?>{
        'path': 'main.dart.wasm',
        'contentHash': hashOf(wasm),
        'byteLength': wasm.length,
      },
    ]);
    expect(sent.keys.map((uri) => uri.path).toSet(), <String>{
      '/render-bundles/v1/blob',
    });
    expect(
      sent.entries.firstWhere((entry) => entry.key.path.endsWith('blob')).value,
      wasm,
    );
    expect(
      sent.keys.firstWhere((uri) => uri.path.endsWith('blob')).queryParameters,
      <String, String>{'contentHash': hashOf(wasm)},
    );
    expect(outcome.version, 4);
    expect(outcome.headReference, 'staging');
    expect(outcome.appFilesSent, 1);
    expect(outcome.appFilesHeld, 1);
  });

  test('a push whose files are all stored sends no bytes', () async {
    final rpc = _FakeUploadRpc(
      prepared: <Object?>[ticket()],
      committed: pushResult(version: 9),
    );
    var uploads = 0;
    final api = apiWith(
      rpc,
      MockClient((_) async {
        uploads++;
        return http.Response('', 204);
      }),
    );

    final outcome = await api.push(
      project: 'demo',
      app: 'mobile',
      target: const BundlePushTarget.personal(),
      artifact: artifact,
      source: source,
    );

    expect(uploads, 0);
    expect(outcome.appFilesSent, 0);
    expect(outcome.appFilesHeld, 2);
    expect(outcome.version, 9);
    expect(rpc.prepareArgs!['personal'], isTrue);
    expect(rpc.prepareArgs!.containsKey('environment'), isFalse);
  });

  test('no more than the advertised number of uploads run at once', () async {
    final hashes = <String>[hashOf(index), hashOf(wasm)];
    final rpc = _FakeUploadRpc(
      prepared: <Object?>[
        ticket(missingContentHashes: hashes, uploadConcurrency: 1),
      ],
      committed: pushResult(),
    );
    var inFlight = 0;
    var peak = 0;
    final api = apiWith(
      rpc,
      MockClient((_) async {
        inFlight++;
        peak = inFlight > peak ? inFlight : peak;
        await Future<void>.delayed(Duration.zero);
        inFlight--;
        return http.Response('', 204);
      }),
    );

    await api.push(
      project: 'demo',
      app: 'mobile',
      target: const BundlePushTarget.environment('staging'),
      artifact: artifact,
      source: source,
    );

    expect(peak, 1);
  });

  test('a file over the advertised ceiling refuses before the wire', () async {
    final rpc = _FakeUploadRpc(
      prepared: <Object?>[
        ticket(
          missingContentHashes: <String>[hashOf(wasm)],
          maxFileTransferBytes: 4,
        ),
      ],
      committed: pushResult(),
    );
    var uploads = 0;
    final api = apiWith(
      rpc,
      MockClient((_) async {
        uploads++;
        return http.Response('', 204);
      }),
    );

    await expectLater(
      api.push(
        project: 'demo',
        app: 'mobile',
        target: const BundlePushTarget.environment('staging'),
        artifact: artifact,
        source: source,
      ),
      throwsA(
        isA<RenderBundleUploadException>().having(
          (error) => error.oversize?.limitBytes,
          'limitBytes',
          4,
        ),
      ),
    );
    expect(uploads, 0);
    expect(rpc.calls, <String>['prepare']);
  });

  test('a prepared address off the pinned origin is refused', () async {
    for (final unsafe in <String>[
      'http://bundles.restage.localhost:8082/render-bundles/v1/blob',
      'http://api.restage.localhost:8080/render-bundles/v1/blob',
      'https://bundles.restage.dev/render-bundles/v1/blob',
      'http://user@bundles.restage.localhost:8081/render-bundles/v1/blob',
      'http://bundles.restage.localhost:8081/render-bundles/v1/upload',
      'http://bundles.restage.localhost:8081/render-bundles/v1/blob?extra=1',
      'http://bundles.restage.localhost:8081/render-bundles/v1/blob#x',
    ]) {
      final rpc = _FakeUploadRpc(
        prepared: <Object?>[
          ticket(missingContentHashes: <String>[hashOf(wasm)], blob: unsafe),
        ],
        committed: pushResult(),
      );
      var uploads = 0;
      final api = apiWith(
        rpc,
        MockClient((_) async {
          uploads++;
          return http.Response('', 204);
        }),
      );

      await expectLater(
        api.push(
          project: 'demo',
          app: 'mobile',
          target: const BundlePushTarget.environment('staging'),
          artifact: artifact,
          source: source,
        ),
        throwsA(isA<RenderBundleUploadException>()),
        reason: unsafe,
      );
      expect(uploads, 0, reason: unsafe);
    }
  });

  test('files that go missing are prepared and sent again', () async {
    final rpc = _FakeUploadRpc(
      prepared: <Object?>[
        ticket(missingContentHashes: <String>[hashOf(wasm)]),
        ticket(missingContentHashes: <String>[hashOf(wasm)]),
      ],
      committed: pushResult(version: 5),
      missingRounds: 1,
    );
    var uploads = 0;
    final api = apiWith(
      rpc,
      MockClient((_) async {
        uploads++;
        return http.Response('', 204);
      }),
    );

    final outcome = await api.push(
      project: 'demo',
      app: 'mobile',
      target: const BundlePushTarget.environment('staging'),
      artifact: artifact,
      source: source,
    );

    expect(rpc.calls, <String>['prepare', 'commit', 'prepare', 'commit']);
    expect(uploads, 2);
    expect(outcome.version, 5);
    // The same file went twice; the bundle still holds two files, one of them
    // moved, so the figures stay inside the manifest.
    expect(outcome.appFilesSent, 1);
    expect(outcome.appFilesHeld, 1);
  });

  test('two files with the same bytes move once and neither is held', () async {
    final shared = bytes('one payload under two names');
    final twins = RenderBundleArtifact(
      appFiles: <String, Uint8List>{'a.bin': shared, 'b.bin': shared},
      engineSet: engineSet,
    );
    final rpc = _FakeUploadRpc(
      prepared: <Object?>[
        ticket(missingContentHashes: <String>[hashOf(shared)]),
      ],
      committed: pushResult(),
    );
    var uploads = 0;
    final api = apiWith(
      rpc,
      MockClient((_) async {
        uploads++;
        return http.Response('', 204);
      }),
    );

    final outcome = await api.push(
      project: 'demo',
      app: 'mobile',
      target: const BundlePushTarget.environment('staging'),
      artifact: twins,
      source: source,
    );

    expect(uploads, 1);
    expect(outcome.appFilesSent, 1);
    expect(outcome.appFilesHeld, 0);
  });

  test('the retry waits before asking the service again', () async {
    final rpc = _FakeUploadRpc(
      prepared: <Object?>[
        ticket(missingContentHashes: <String>[hashOf(wasm)]),
      ],
      committed: pushResult(),
    );
    final waits = <Duration>[];
    var attempts = 0;
    final api = RenderBundleApi(
      rpc: rpc,
      trustedBundleOrigin: bundleOrigin,
      uploadClient: MockClient((_) async {
        attempts++;
        return http.Response('', attempts == 1 ? 503 : 204);
      }),
      delay: (duration) async => waits.add(duration),
    );

    final outcome = await api.push(
      project: 'demo',
      app: 'mobile',
      target: const BundlePushTarget.environment('staging'),
      artifact: artifact,
      source: source,
    );

    expect(attempts, 2);
    expect(waits, <Duration>[const Duration(milliseconds: 750)]);
    expect(outcome.appFilesSent, 1);
  });

  test('files that keep going missing end as an incomplete push', () async {
    final rpc = _FakeUploadRpc(
      prepared: <Object?>[
        for (var round = 0; round < 3; round++)
          ticket(missingContentHashes: <String>[hashOf(wasm)]),
      ],
      committed: pushResult(),
      missingRounds: 3,
    );
    final api = apiWith(rpc, MockClient((_) async => http.Response('', 204)));

    await expectLater(
      api.push(
        project: 'demo',
        app: 'mobile',
        target: const BundlePushTarget.environment('staging'),
        artifact: artifact,
        source: source,
      ),
      throwsA(
        isA<RenderBundleUploadException>().having(
          (error) => error.incomplete,
          'incomplete',
          isTrue,
        ),
      ),
    );
    expect(rpc.calls.where((call) => call == 'prepare'), hasLength(3));
  });

  test('a storage refusal carries its figures and what holds them', () async {
    final rpc = _FakeUploadRpc(
      prepared: <Object?>[],
      committed: null,
      prepareFailure: RestageApiException(
        400,
        jsonEncode(<String, Object?>{
          'className': 'RenderBundleStorageLimitException',
          'data': <String, Object?>{
            'usedBytes': 900,
            'limitBytes': 1000,
            'neededBytes': 300,
            'protectedHolders': <String, Object?>{
              'items': [
                <String, Object?>{
                  'kind': 'environmentHead',
                  'label': 'prod',
                  'version': 2,
                  'byteLength': 400,
                },
              ],
            },
            'evictedVersionIds': <Object?>[3, 4],
          },
        }),
      ),
    );
    final api = apiWith(rpc, MockClient((_) async => http.Response('', 204)));

    await expectLater(
      api.push(
        project: 'demo',
        app: 'mobile',
        target: const BundlePushTarget.environment('staging'),
        artifact: artifact,
        source: source,
      ),
      throwsA(
        isA<RenderBundleUploadException>()
            .having((error) => error.storage?.neededBytes, 'neededBytes', 300)
            .having(
              (error) => error.storage?.holders.single.label,
              'holder',
              'prod',
            )
            .having(
              (error) => error.storage?.evictedVersionIds,
              'evictedVersionIds',
              [3, 4],
            ),
      ),
    );
  });

  test('a refusal carries its reason and no server prose', () async {
    final rpc = _FakeUploadRpc(
      prepared: <Object?>[],
      committed: null,
      prepareFailure: RestageApiException(
        403,
        jsonEncode(<String, Object?>{
          'className': 'RenderBundleRejectedException',
          'data': <String, Object?>{'reason': 'missing_scope'},
        }),
      ),
    );
    final api = apiWith(rpc, MockClient((_) async => http.Response('', 204)));

    await expectLater(
      api.push(
        project: 'demo',
        app: 'mobile',
        target: const BundlePushTarget.environment('staging'),
        artifact: artifact,
        source: source,
      ),
      throwsA(
        isA<RenderBundleUploadException>()
            .having((error) => error.reason, 'reason', 'missing_scope')
            .having(
              (error) => error.toString(),
              'toString',
              isNot(contains('{')),
            ),
      ),
    );
  });

  test('a reason that is not a short name is dropped', () async {
    for (final prose in <String>[
      'PostgresException: relation "render_bundle_version" does not exist',
      'MISSING_SCOPE',
      'missing scope',
      '',
      'a' * 65,
    ]) {
      final rpc = _FakeUploadRpc(
        prepared: <Object?>[],
        committed: null,
        prepareFailure: RestageApiException(
          403,
          jsonEncode(<String, Object?>{
            'className': 'RenderBundleRejectedException',
            'data': <String, Object?>{'reason': prose},
          }),
        ),
      );
      final api = apiWith(rpc, MockClient((_) async => http.Response('', 204)));

      await expectLater(
        api.push(
          project: 'demo',
          app: 'mobile',
          target: const BundlePushTarget.environment('staging'),
          artifact: artifact,
          source: source,
        ),
        throwsA(
          isA<RenderBundleUploadException>()
              .having((error) => error.reason, 'reason', isNull)
              .having((error) => error.statusCode, 'statusCode', 403),
        ),
        reason: prose,
      );
    }
  });
}

final class _FakeUploadRpc extends RestageApi {
  _FakeUploadRpc({
    required this.prepared,
    required this.committed,
    this.missingRounds = 0,
    this.prepareFailure,
  }) : super(
         endpoint: Uri.parse('http://api.restage.localhost:8080'),
         credential: const Credential(
           endpoint: 'http://api.restage.localhost:8080',
           kind: CredentialKind.authKey,
           authToken: 'key-id:private-key',
         ),
         httpClient: MockClient((_) async => http.Response('', 500)),
       );

  final List<Object?> prepared;
  final Object? committed;

  /// How many commits answer that the files went missing.
  final int missingRounds;
  final RestageApiException? prepareFailure;

  final List<String> calls = <String>[];
  Map<String, dynamic>? prepareArgs;
  Map<String, dynamic>? commitArgs;
  var _prepares = 0;
  var _commits = 0;

  @override
  Future<dynamic> call(
    String endpointName,
    String methodName,
    Map<String, dynamic> args,
  ) async {
    expect(endpointName, 'renderBundleUpload');
    calls.add(methodName);
    if (methodName == 'prepare') {
      final failure = prepareFailure;
      if (failure != null) throw failure;
      prepareArgs = args;
      return prepared[_prepares++];
    }
    if (methodName == 'commit') {
      commitArgs = args;
      if (_commits++ < missingRounds) {
        throw RestageApiException(
          409,
          jsonEncode(<String, Object?>{
            'className': 'RenderBundleRejectedException',
            'data': <String, Object?>{'reason': 'files_missing'},
          }),
        );
      }
      return committed;
    }
    throw StateError('unexpected method');
  }
}
