import 'dart:convert';
import 'dart:io' show SocketException, gzip;
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/src/api/render_bundle_api.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/credentials/credential.dart';
import 'package:restage_cli/src/render_bundles/render_bundle_archive.dart';
import 'package:test/test.dart';

void main() {
  const credential = Credential(
    endpoint: 'http://api.restage.localhost:8080',
    kind: CredentialKind.authKey,
    authToken: 'key-id:private-key',
  );
  final endpoint = Uri.parse('http://api.restage.localhost:8080');
  final localBundleOrigin = Uri.parse('http://bundles.restage.localhost:8081');
  const prepared =
      'http://bundles.restage.localhost:8081/render-bundles/v1/upload?projectSlug=demo&organizationId=7&channel=main';

  test('prepares then sends one exact raw authenticated POST', () async {
    final rpc = _FakeRestageApi(prepared);
    late http.Request request;
    final uploadClient = MockClient((incoming) async {
      request = incoming;
      return http.Response('', 204);
    });
    final api = RenderBundleApi(
      rpc: rpc,
      apiEndpoint: endpoint,
      credential: credential,
      trustedBundleOrigin: localBundleOrigin,
      uploadClient: uploadClient,
    );
    final archive = Uint8List.fromList(<int>[1, 2, 3]);

    await api.uploadMain(project: 'demo', organizationId: 7, archive: archive);

    expect(rpc.calls, <String>['prepareUpload']);
    expect(request.method, 'POST');
    expect(request.url.toString(), prepared);
    expect(request.followRedirects, isFalse);
    expect(request.maxRedirects, 0);
    expect(
      request.headers,
      containsPair('content-type', 'application/vnd.restage.render-bundle.v1'),
    );
    expect(
      request.headers,
      containsPair(
        'authorization',
        'Basic ${base64Encode(utf8.encode(credential.authToken))}',
      ),
    );
    // The container travels gzipped: the serving platform refuses a single
    // request body over 32 MiB and a real bundle exceeds that raw. The
    // compression is transport-only, so the body must inflate back to exactly
    // the archive that was handed in.
    expect(request.headers, containsPair('content-encoding', 'gzip'));
    expect(request.headers, isNot(contains('transfer-encoding')));
    expect(request.contentLength, request.bodyBytes.length);
    expect(request.bodyBytes, isNot(archive));
    expect(gzip.decode(request.bodyBytes), archive);
  });

  test(
    'refuses a body that stays over the transfer cap once compressed',
    () async {
      final rpc = _FakeRestageApi(prepared);
      var uploadCalls = 0;
      final api = RenderBundleApi(
        rpc: rpc,
        apiEndpoint: endpoint,
        credential: credential,
        trustedBundleOrigin: localBundleOrigin,
        uploadClient: MockClient((_) async {
          uploadCalls++;
          return http.Response('', 204);
        }),
      );
      // Incompressible random bytes just over the transfer cap: under the raw
      // archive ceiling, so only the wire-size guard can reject it.
      final random = Random(7);
      final incompressible = Uint8List.fromList(
        List<int>.generate(
          renderBundleMaxUploadTransferBytes + 1024,
          (_) => random.nextInt(256),
        ),
      );

      await expectLater(
        api.uploadMain(
          project: 'demo',
          organizationId: 7,
          archive: incompressible,
        ),
        throwsA(isA<RenderBundleUploadException>()),
      );
      expect(uploadCalls, 0, reason: 'never put an oversize body on the wire');
    },
  );

  test('honours the part limit the service advertises', () async {
    // Splitting removes the single-request ceiling, so the only local refusal
    // left is a body that needs more parts than the service will take.
    final rpc = _FakeRestageApi(prepared, chunked: true, maxParts: 1);
    var partUploads = 0;
    final api = RenderBundleApi(
      rpc: rpc,
      apiEndpoint: endpoint,
      credential: credential,
      trustedBundleOrigin: localBundleOrigin,
      uploadClient: MockClient((_) async {
        partUploads++;
        return http.Response('', 204);
      }),
    );
    final random = Random(11);
    final incompressible = Uint8List.fromList(
      List<int>.generate(
        renderBundleMaxUploadTransferBytes + 1024,
        (_) => random.nextInt(256),
      ),
    );

    await expectLater(
      api.uploadMain(
        project: 'demo',
        organizationId: 7,
        archive: incompressible,
      ),
      throwsA(
        isA<RenderBundleUploadException>()
            .having(
              (e) => e.oversize?.measuredBytes,
              'measuredBytes',
              greaterThan(_FakeRestageApi.partByteLimit),
            )
            .having(
              (e) => e.oversize?.limitBytes,
              'limitBytes',
              _FakeRestageApi.partByteLimit,
            )
            .having((e) => e.oversize?.compressed, 'compressed', isTrue),
      ),
    );
    expect(partUploads, 0, reason: 'nothing goes on the wire past the limit');
  });

  test('splits an oversize body into parts and commits it by hash', () async {
    final random = Random(3);
    final archive = Uint8List.fromList(
      List<int>.generate(
        renderBundleMaxUploadTransferBytes + (4 * 1024 * 1024),
        (_) => random.nextInt(256),
      ),
    );
    final rpc = _FakeRestageApi(prepared, chunked: true);
    final partBodies = <int, List<int>>{};
    final partCounts = <int>{};
    final api = RenderBundleApi(
      rpc: rpc,
      apiEndpoint: endpoint,
      credential: credential,
      trustedBundleOrigin: localBundleOrigin,
      uploadClient: MockClient((request) async {
        final query = request.url.queryParameters;
        expect(query['uploadId'], _FakeRestageApi.uploadId);
        expect(request.headers, isNot(contains('content-encoding')));
        expect(
          request.bodyBytes.length,
          lessThanOrEqualTo(_FakeRestageApi.partByteLimit),
        );
        partCounts.add(int.parse(query['partCount']!));
        partBodies[int.parse(query['partIndex']!)] = request.bodyBytes;
        return http.Response('', 204);
      }),
    );

    await api.uploadMain(project: 'demo', organizationId: 7, archive: archive);

    expect(rpc.calls, <String>[
      'prepareUpload',
      'prepareChunkedUpload',
      'commitChunkedUpload',
    ]);
    expect(partCounts, hasLength(1), reason: 'one declared part count');
    expect(partBodies, hasLength(partCounts.single));
    // The parts are byte ranges of one compressed stream: concatenating them
    // in index order must reproduce exactly what a single request would send.
    final reassembled = <int>[
      for (var index = 0; index < partBodies.length; index++)
        ...partBodies[index]!,
    ];
    expect(reassembled, gzip.encode(archive));
    expect(gzip.decode(reassembled), archive);
    // The commit names the hash of the raw container. The compressed
    // transfer has its own, and the two differ.
    expect(
      rpc.lastCommit?['contentHash'],
      'sha256:${crypto.sha256.convert(archive)}',
    );
  });

  test(
    'a busy lane on one part is retried once before the refusal stands',
    () async {
      final random = Random(29);
      final archive = Uint8List.fromList(
        List<int>.generate(
          renderBundleMaxUploadTransferBytes + (4 * 1024 * 1024),
          (_) => random.nextInt(256),
        ),
      );
      final rpc = _FakeRestageApi(prepared, chunked: true);
      var busyAnswers = 0;
      final api = RenderBundleApi(
        rpc: rpc,
        apiEndpoint: endpoint,
        credential: credential,
        trustedBundleOrigin: localBundleOrigin,
        uploadClient: MockClient((request) async {
          // The first part is told the lane is busy, exactly once.
          if (request.url.queryParameters['partIndex'] == '0' &&
              busyAnswers == 0) {
            busyAnswers++;
            return http.Response('', 503);
          }
          return http.Response('', 204);
        }),
      );

      await api.uploadMain(
        project: 'demo',
        organizationId: 7,
        archive: archive,
      );

      expect(busyAnswers, 1);
      expect(rpc.calls, contains('commitChunkedUpload'));
      expect(
        rpc.calls,
        isNot(contains('discardChunkedUpload')),
        reason: 'a busy lane leaves the upload intact',
      );
    },
  );

  test('carries the refusal status without any server detail', () async {
    for (final status in <int>[413, 415, 429, 503]) {
      final rpc = _FakeRestageApi(prepared);
      final api = RenderBundleApi(
        rpc: rpc,
        apiEndpoint: endpoint,
        credential: credential,
        trustedBundleOrigin: localBundleOrigin,
        uploadClient: MockClient(
          (_) async =>
              http.Response('request entity too large: secret', status),
        ),
      );

      await expectLater(
        api.uploadMain(
          project: 'demo',
          organizationId: 7,
          archive: Uint8List.fromList(<int>[1, 2, 3]),
        ),
        throwsA(
          isA<RenderBundleUploadException>()
              .having((e) => e.statusCode, 'statusCode', status)
              .having((e) => e.oversize, 'oversize', isNull)
              .having(
                (e) => e.transferBytes,
                'transferBytes',
                isA<int>().having((bytes) => bytes, 'sent', greaterThan(0)),
              )
              .having(
                (e) => e.toString(),
                'toString',
                isNot(contains('secret')),
              ),
        ),
      );
    }
  });

  test('a part that fails in transit is retried once', () async {
    final random = Random(9);
    final archive = Uint8List.fromList(
      List<int>.generate(
        renderBundleMaxUploadTransferBytes + (1024 * 1024),
        (_) => random.nextInt(256),
      ),
    );
    final rpc = _FakeRestageApi(prepared, chunked: true);
    var attempts = 0;
    final api = RenderBundleApi(
      rpc: rpc,
      apiEndpoint: endpoint,
      credential: credential,
      trustedBundleOrigin: localBundleOrigin,
      uploadClient: MockClient((request) async {
        attempts++;
        // The first part's first attempt dies in transit, as a socket would.
        if (attempts == 1) throw const SocketException('reset');
        return http.Response('', 204);
      }),
    );

    await api.uploadMain(project: 'demo', organizationId: 7, archive: archive);

    expect(rpc.calls, contains('commitChunkedUpload'));
    expect(rpc.calls, isNot(contains('discardChunkedUpload')));
    expect(attempts, greaterThan(1), reason: 'the failed part was retried');
  });

  test('a part that keeps failing discards the staged parts', () async {
    final random = Random(13);
    final archive = Uint8List.fromList(
      List<int>.generate(
        renderBundleMaxUploadTransferBytes + (1024 * 1024),
        (_) => random.nextInt(256),
      ),
    );
    final rpc = _FakeRestageApi(prepared, chunked: true);
    final api = RenderBundleApi(
      rpc: rpc,
      apiEndpoint: endpoint,
      credential: credential,
      trustedBundleOrigin: localBundleOrigin,
      uploadClient: MockClient((_) async => throw const SocketException('x')),
    );

    await expectLater(
      api.uploadMain(project: 'demo', organizationId: 7, archive: archive),
      throwsA(isA<RenderBundleUploadException>()),
    );

    // A transport failure must not leave the staged parts behind.
    expect(rpc.calls, contains('discardChunkedUpload'));
    expect(rpc.calls, isNot(contains('commitChunkedUpload')));
  });

  test('rejects oversize before RPC or upload network', () async {
    final rpc = _FakeRestageApi(prepared);
    var uploadCalls = 0;
    final api = RenderBundleApi(
      rpc: rpc,
      apiEndpoint: endpoint,
      credential: credential,
      trustedBundleOrigin: localBundleOrigin,
      uploadClient: MockClient((_) async {
        uploadCalls++;
        return http.Response('', 204);
      }),
    );

    await expectLater(
      api.uploadMain(
        project: 'demo',
        organizationId: 7,
        archive: Uint8List(renderBundleMaxArchiveBytes + 1),
      ),
      throwsA(isA<RenderBundleUploadException>()),
    );
    expect(rpc.calls, isEmpty);
    expect(uploadCalls, 0);
  });

  test('fails closed on any prepared URL authority or shape change', () async {
    for (final unsafe in <String>[
      'https://127.0.0.1:8081/render-bundles/v1/upload?projectSlug=demo&organizationId=7&channel=main',
      'http://127.0.0.1:8081/render-bundles/v1/upload?projectSlug=demo&organizationId=7&channel=main',
      'http://localhost:8081/render-bundles/v1/upload?projectSlug=demo&organizationId=7&channel=main',
      'http://127.0.0.1:8080/render-bundles/v1/upload?projectSlug=demo&organizationId=7&channel=main',
      'http://127.0.0.1:8081/render-bundles/v1/upload/?projectSlug=demo&organizationId=7&channel=main',
      'http://127.0.0.1:8081/render-bundles/v1/upload?organizationId=7&channel=main&projectSlug=demo',
      'http://127.0.0.1:8081/render-bundles/v1/upload?projectSlug=other&organizationId=7&channel=main',
      'http://127.0.0.1:8081/render-bundles/v1/upload?projectSlug=demo&organizationId=8&channel=main',
      'http://127.0.0.1:8081/render-bundles/v1/upload?projectSlug=demo&organizationId=7&channel=main&extra=1',
      'http://user@127.0.0.1:8081/render-bundles/v1/upload?projectSlug=demo&organizationId=7&channel=main',
      'http://127.0.0.1:8081/render-bundles/v1/upload?projectSlug=demo&organizationId=7&channel=main#x',
    ]) {
      var uploadCalls = 0;
      final api = RenderBundleApi(
        rpc: _FakeRestageApi(unsafe),
        apiEndpoint: endpoint,
        credential: credential,
        trustedBundleOrigin: localBundleOrigin,
        uploadClient: MockClient((_) async {
          uploadCalls++;
          return http.Response('', 204);
        }),
      );
      await expectLater(
        api.uploadMain(
          project: 'demo',
          organizationId: 7,
          archive: Uint8List.fromList(<int>[1]),
        ),
        throwsA(isA<RenderBundleUploadException>()),
        reason: unsafe,
      );
      expect(uploadCalls, 0, reason: unsafe);
    }
  });

  test(
    'revalidates the returned channel authority before upload network',
    () async {
      final rpc = _FakeRestageApi(prepared);
      var uploadCalls = 0;
      final api = RenderBundleApi(
        rpc: rpc,
        apiEndpoint: endpoint,
        credential: credential,
        trustedBundleOrigin: localBundleOrigin,
        uploadClient: MockClient((_) async {
          uploadCalls++;
          return http.Response('', 204);
        }),
      );

      await expectLater(
        api.upload(
          project: 'demo',
          channel: 'user/alice',
          organizationId: 7,
          archive: Uint8List.fromList(<int>[1]),
        ),
        throwsA(isA<RenderBundleUploadException>()),
      );

      expect(rpc.calls, <String>['prepareUpload']);
      expect(rpc.lastArgs, <String, dynamic>{
        'projectSlug': 'demo',
        'channel': 'user/alice',
        'organizationId': 7,
      });
      expect(uploadCalls, 0);
    },
  );

  test(
    'local upload requires the exact pinned finite control origin',
    () async {
      for (final trustedOrigin in <Uri?>[
        null,
        Uri.parse('http://127.0.0.1:8082'),
        Uri.parse('http://127.0.0.1:8081'),
        Uri.parse('http://localhost:8081'),
        Uri.parse('http://control.restage.localhost:8081'),
      ]) {
        var uploadCalls = 0;
        final api = RenderBundleApi(
          rpc: _FakeRestageApi(prepared),
          apiEndpoint: endpoint,
          credential: credential,
          trustedBundleOrigin: trustedOrigin,
          uploadClient: MockClient((_) async {
            uploadCalls++;
            return http.Response('', 204);
          }),
        );

        await expectLater(
          api.uploadMain(
            project: 'demo',
            organizationId: 7,
            archive: Uint8List.fromList(<int>[1]),
          ),
          throwsA(isA<RenderBundleUploadException>()),
          reason: '$trustedOrigin',
        );
        expect(uploadCalls, 0, reason: '$trustedOrigin');
      }
    },
  );

  test('deployed upload accepts the exact code-owned sibling origin', () async {
    const deployedPrepared =
        'https://bundles.restage.dev/render-bundles/v1/upload?projectSlug=demo&organizationId=7&channel=main';
    var uploadCalls = 0;
    final api = RenderBundleApi(
      rpc: _FakeRestageApi(deployedPrepared),
      apiEndpoint: Uri.parse('https://api.restage.dev'),
      credential: credential,
      trustedBundleOrigin: Uri.parse('https://bundles.restage.dev'),
      uploadClient: MockClient((_) async {
        uploadCalls++;
        return http.Response('', 204);
      }),
    );

    await api.uploadMain(
      project: 'demo',
      organizationId: 7,
      archive: Uint8List.fromList(<int>[1]),
    );
    expect(uploadCalls, 1);
  });

  test(
    'deployed upload rejects unapproved or changed authority before upload',
    () async {
      const uploadPath =
          '/render-bundles/v1/upload?projectSlug=demo&organizationId=7&channel=main';
      for (final unsafe in <(String, String, String, String)>[
        (
          'arbitrary cross-site',
          'https://api.example.com',
          'https://upload.example.com',
          'https://upload.example.com$uploadPath',
        ),
        (
          'public suffix siblings',
          'https://api.github.io',
          'https://upload.github.io',
          'https://upload.github.io$uploadPath',
        ),
        (
          'cross-site bundle pin',
          'https://api.restage.dev',
          'https://upload.example.com',
          'https://upload.example.com$uploadPath',
        ),
        (
          'nested bundle host',
          'https://api.restage.dev',
          'https://nested.upload.restage.dev',
          'https://nested.upload.restage.dev$uploadPath',
        ),
        (
          'deceptive suffix',
          'https://api.restage.dev.evil.test',
          'https://upload.restage.dev.evil.test',
          'https://upload.restage.dev.evil.test$uploadPath',
        ),
        (
          'prepared URL changes authority',
          'https://api.restage.dev',
          'https://upload.restage.dev',
          'https://other.restage.dev$uploadPath',
        ),
      ]) {
        var uploadCalls = 0;
        final api = RenderBundleApi(
          rpc: _FakeRestageApi(unsafe.$4),
          apiEndpoint: Uri.parse(unsafe.$2),
          credential: credential,
          trustedBundleOrigin: Uri.parse(unsafe.$3),
          uploadClient: MockClient((_) async {
            uploadCalls++;
            return http.Response('', 204);
          }),
        );
        await expectLater(
          api.uploadMain(
            project: 'demo',
            organizationId: 7,
            archive: Uint8List.fromList(<int>[1]),
          ),
          throwsA(isA<RenderBundleUploadException>()),
          reason: unsafe.$1,
        );
        expect(uploadCalls, 0, reason: unsafe.$1);
      }
    },
  );

  test(
    'deployed upload rejects a same-origin pin before upload network',
    () async {
      const sameOriginPrepared =
          'https://api.restage.dev/render-bundles/v1/upload?projectSlug=demo&organizationId=7&channel=main';
      var uploadCalls = 0;
      final api = RenderBundleApi(
        rpc: _FakeRestageApi(sameOriginPrepared),
        apiEndpoint: Uri.parse('https://api.restage.dev'),
        credential: credential,
        trustedBundleOrigin: Uri.parse('https://api.restage.dev'),
        uploadClient: MockClient((_) async {
          uploadCalls++;
          return http.Response('', 204);
        }),
      );

      await expectLater(
        api.uploadMain(
          project: 'demo',
          organizationId: 7,
          archive: Uint8List.fromList(<int>[1]),
        ),
        throwsA(isA<RenderBundleUploadException>()),
      );
      expect(uploadCalls, 0);
    },
  );

  test('does not follow, retry, or expose failed response details', () async {
    final rpc = _FakeRestageApi(prepared);
    var uploadCalls = 0;
    final api = RenderBundleApi(
      rpc: rpc,
      apiEndpoint: endpoint,
      credential: credential,
      trustedBundleOrigin: localBundleOrigin,
      uploadClient: MockClient((_) async {
        uploadCalls++;
        return http.Response(
          'secret response body',
          307,
          headers: <String, String>{
            'location': 'http://attacker.example/collect',
          },
        );
      }),
    );

    Object? failure;
    try {
      await api.uploadMain(
        project: 'demo',
        organizationId: 7,
        archive: Uint8List.fromList(<int>[1]),
      );
    } catch (error) {
      failure = error;
    }
    expect(uploadCalls, 1);
    expect(failure, isA<RenderBundleUploadException>());
    expect('$failure', isNot(contains('secret')));
    expect('$failure', isNot(contains('attacker')));
    expect('$failure', isNot(contains(prepared)));
  });

  test('accepts only an empty 204 and discovers version/hash', () async {
    for (final response in <http.Response>[
      http.Response('', 200),
      http.Response('x', 204),
    ]) {
      final api = RenderBundleApi(
        rpc: _FakeRestageApi(prepared),
        apiEndpoint: endpoint,
        credential: credential,
        trustedBundleOrigin: localBundleOrigin,
        uploadClient: MockClient((_) async => response),
      );
      await expectLater(
        api.uploadMain(
          project: 'demo',
          organizationId: 7,
          archive: Uint8List.fromList(<int>[1]),
        ),
        throwsA(isA<RenderBundleUploadException>()),
      );
    }

    final rpc = _FakeRestageApi(prepared)
      ..discoverResponse = <String, Object?>{
        'version': 3,
        'contentHash': 'sha256:${List<String>.filled(64, 'a').join()}',
      };
    final api = RenderBundleApi(
      rpc: rpc,
      apiEndpoint: endpoint,
      credential: credential,
      trustedBundleOrigin: localBundleOrigin,
      uploadClient: MockClient((_) async => http.Response('', 204)),
    );
    final snapshot = await api.discoverMain(project: 'demo', organizationId: 7);
    expect(snapshot?.version, 3);
    expect(
      snapshot?.contentHash,
      'sha256:${List<String>.filled(64, 'a').join()}',
    );
  });

  test('lists only typed status-safe channel fields', () async {
    final rpc = _FakeRestageApi(prepared)
      ..channelsResponse = <Object?>[
        <String, Object?>{
          'channel': 'main',
          'activeRenderBundleId': 17,
          'activeVersion': 3,
          'updatedByUserInfoId': 29,
          'updatedAt': '2030-01-01T00:00:00.000Z',
          'futureField': <String, Object?>{
            'bootstrapGrant': 'secret-not-projected',
          },
        },
        <String, Object?>{
          'channel': 'user/alice',
          'activeRenderBundleId': 19,
          'activeVersion': 2,
          'updatedByUserInfoId': 31,
          'updatedAt': '2030-01-02T00:00:00.000Z',
        },
      ];
    final api = RenderBundleApi(
      rpc: rpc,
      apiEndpoint: endpoint,
      credential: credential,
      trustedBundleOrigin: localBundleOrigin,
    );

    final channels = await api.listChannels(project: 'demo', organizationId: 7);

    expect(channels.map((item) => item.channel), ['main', 'user/alice']);
    expect(channels.map((item) => item.activeVersion), [3, 2]);
    expect(channels.first.updatedAt, DateTime.utc(2030));
    expect(rpc.calls, ['listChannels']);
    expect(rpc.lastArgs, <String, dynamic>{
      'projectSlug': 'demo',
      'organizationId': 7,
    });
  });

  test(
    'channel listing rejects malformed, duplicate, or noncanonical rows',
    () async {
      final valid = <String, Object?>{
        'channel': 'main',
        'activeRenderBundleId': 17,
        'activeVersion': 3,
        'updatedByUserInfoId': 29,
        'updatedAt': '2030-01-01T00:00:00.000Z',
      };
      for (final response in <Object?>[
        null,
        <Object?>['main'],
        <Object?>[
          <String, Object?>{...valid}..remove('activeVersion'),
        ],
        <Object?>[
          <String, Object?>{...valid, 'channel': 'Main'},
        ],
        <Object?>[
          <String, Object?>{...valid, 'activeRenderBundleId': 0},
        ],
        <Object?>[
          <String, Object?>{...valid, 'activeVersion': 0},
        ],
        <Object?>[
          <String, Object?>{...valid, 'updatedByUserInfoId': 0},
        ],
        <Object?>[
          <String, Object?>{...valid, 'updatedAt': '2030-01-01'},
        ],
        <Object?>[valid, valid],
      ]) {
        final rpc = _FakeRestageApi(prepared)..channelsResponse = response;
        final api = RenderBundleApi(
          rpc: rpc,
          apiEndpoint: endpoint,
          credential: credential,
          trustedBundleOrigin: localBundleOrigin,
        );

        await expectLater(
          api.listChannels(project: 'demo', organizationId: 7),
          throwsA(isA<RenderBundleUploadException>()),
          reason: '$response',
        );
      }
    },
  );

  test('invalid channel-list project scope fails before RPC', () async {
    final rpc = _FakeRestageApi(prepared);
    final api = RenderBundleApi(
      rpc: rpc,
      apiEndpoint: endpoint,
      credential: credential,
      trustedBundleOrigin: localBundleOrigin,
    );

    await expectLater(
      api.listChannels(project: '', organizationId: 0),
      throwsA(isA<RenderBundleUploadException>()),
    );
    expect(rpc.calls, isEmpty);
  });

  test('prepares one typed redacted browser bootstrap', () async {
    final rpc = _FakeRestageApi(prepared)
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
      channel: 'main',
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
      final rpc = _FakeRestageApi(prepared)
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
          channel: 'main',
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
      final rpc = _FakeRestageApi(prepared);
      final api = RenderBundleApi(
        rpc: rpc,
        apiEndpoint: endpoint,
        credential: credential,
        trustedBundleOrigin: Uri.parse(origin),
      );

      await expectLater(
        api.prepareBrowserBootstrap(
          project: 'demo',
          channel: 'main',
          trustedBundleOrigin: Uri.parse(origin),
        ),
        throwsA(isA<RenderBundleUploadException>()),
      );
      expect(rpc.calls, isEmpty, reason: origin);
    }
  });

  test('invalid browser-bootstrap channel fails before RPC', () async {
    final rpc = _FakeRestageApi(prepared);
    final api = RenderBundleApi(
      rpc: rpc,
      apiEndpoint: endpoint,
      credential: credential,
      trustedBundleOrigin: localBundleOrigin,
    );

    await expectLater(
      api.prepareBrowserBootstrap(
        project: 'demo',
        channel: 'Main',
        trustedBundleOrigin: localBundleOrigin,
      ),
      throwsA(isA<RenderBundleUploadException>()),
    );
    expect(rpc.calls, isEmpty);
  });
}

final class _FakeRestageApi extends RestageApi {
  _FakeRestageApi(this.prepared, {this.chunked = false, this.maxParts = 8})
    : super(
        endpoint: Uri.parse('http://api.restage.localhost:8080'),
        httpClient: MockClient((_) async => http.Response('', 500)),
      );

  static const uploadId = '0123456789abcdef0123456789abcdef';
  static const nonce = 'fedcba9876543210fedcba9876543210';
  static const partByteLimit = 8 * 1024 * 1024;

  final String prepared;
  final bool chunked;
  final int maxParts;
  Map<String, dynamic>? lastCommit;
  Object? discoverResponse;
  Object? bootstrapResponse;
  Object? channelsResponse;
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
    if (methodName == 'prepareUpload') return prepared;
    if (methodName == 'discover') return discoverResponse;
    if (methodName == 'listChannels') return channelsResponse;
    if (methodName == 'prepareBrowserBootstrap') return bootstrapResponse;
    if (chunked && methodName == 'prepareChunkedUpload') {
      return <String, dynamic>{
        'uploadId': uploadId,
        'nonce': nonce,
        'expiresAt': DateTime.utc(2030).toIso8601String(),
        'uploadUrl': prepared,
        'partByteLimit': partByteLimit,
        'maxParts': maxParts,
      };
    }
    if (chunked && methodName == 'discardChunkedUpload') return null;
    if (chunked && methodName == 'commitChunkedUpload') {
      lastCommit = args;
      return null;
    }
    throw StateError('unexpected method');
  }
}
