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

/// Minimal fake that records the most-recent [call] invocation and returns a
/// constructor-supplied [response]. Used for lifecycle methods where testing
/// the HTTP wire format adds no value over testing the arg-map shape.
class FakeRestageApi implements RestageApi {
  FakeRestageApi({required this.response});

  final dynamic response;
  String? lastEndpoint;
  String? lastMethod;
  Map<String, dynamic>? lastArgs;

  @override
  Future<dynamic> call(
    String endpointName,
    String methodName,
    Map<String, dynamic> args,
  ) async {
    lastEndpoint = endpointName;
    lastMethod = methodName;
    lastArgs = args;
    return response;
  }

  @override
  void close() {}
}

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

  group('SurfaceApi.kill', () {
    test('encodes frozen mode + reason and targets killSurface', () async {
      final fake = FakeRestageApi(response: null);
      await SurfaceApi(fake).kill(
        project: 'p',
        app: 'a',
        surfaceType: SurfaceType.paywall,
        surfaceSlug: 'pro',
        environment: 'production',
        frozen: true,
        reason: 'bad price',
      );
      expect(fake.lastEndpoint, 'surface');
      expect(fake.lastMethod, 'killSurface');
      expect(fake.lastArgs!['mode'], 'frozen');
      expect(fake.lastArgs!['reason'], 'bad price');
      expect(fake.lastArgs!['surfaceType'], 'paywall');
    });

    test('encodes transient mode when frozen is false', () async {
      final fake = FakeRestageApi(response: null);
      await SurfaceApi(fake).kill(
        project: 'p',
        app: 'a',
        surfaceType: SurfaceType.onboarding,
        surfaceSlug: 'welcome',
        environment: 'staging',
        frozen: false,
        reason: 'test',
      );
      expect(fake.lastArgs!['mode'], 'transient');
    });

    test('threads organizationId when provided, omits it when null', () async {
      final fake = FakeRestageApi(response: null);
      await SurfaceApi(fake).kill(
        project: 'p',
        app: 'a',
        surfaceType: SurfaceType.paywall,
        surfaceSlug: 's',
        environment: 'e',
        frozen: true,
        reason: 'r',
        organizationId: 42,
      );
      expect(fake.lastArgs!['organizationId'], 42);

      await SurfaceApi(fake).kill(
        project: 'p',
        app: 'a',
        surfaceType: SurfaceType.paywall,
        surfaceSlug: 's',
        environment: 'e',
        frozen: true,
        reason: 'r',
      );
      expect(fake.lastArgs!.containsKey('organizationId'), isFalse);
    });
  });

  group('SurfaceApi.setLock', () {
    test('encodes locked + reason and targets setSurfaceLock', () async {
      final fake = FakeRestageApi(response: null);
      await SurfaceApi(fake).setLock(
        project: 'p',
        app: 'a',
        surfaceType: SurfaceType.paywall,
        surfaceSlug: 'pro',
        environment: 'production',
        locked: true,
        reason: 'freeze for release',
      );
      expect(fake.lastMethod, 'setSurfaceLock');
      expect(fake.lastArgs!['locked'], true);
      expect(fake.lastArgs!['reason'], 'freeze for release');
      expect(fake.lastArgs!['surfaceType'], 'paywall');
    });
  });

  group('SurfaceApi.rollback', () {
    test('encodes toVersion + lockAfter and targets rollbackSurface', () async {
      final fake = FakeRestageApi(response: null);
      await SurfaceApi(fake).rollback(
        project: 'p',
        app: 'a',
        surfaceType: SurfaceType.paywall,
        surfaceSlug: 'pro',
        environment: 'production',
        toVersion: 3,
        lockAfter: true,
        reason: 'revert',
      );
      expect(fake.lastEndpoint, 'surface');
      expect(fake.lastMethod, 'rollbackSurface');
      expect(fake.lastArgs!['toVersion'], 3);
      expect(fake.lastArgs!['lockAfter'], true);
      expect(fake.lastArgs!['reason'], 'revert');
    });

    test('threads organizationId when provided, omits it when null', () async {
      final fake = FakeRestageApi(response: null);
      await SurfaceApi(fake).rollback(
        project: 'p',
        app: 'a',
        surfaceType: SurfaceType.paywall,
        surfaceSlug: 's',
        environment: 'e',
        toVersion: 1,
        lockAfter: false,
        reason: 'r',
        organizationId: 7,
      );
      expect(fake.lastArgs!['organizationId'], 7);

      await SurfaceApi(fake).rollback(
        project: 'p',
        app: 'a',
        surfaceType: SurfaceType.paywall,
        surfaceSlug: 's',
        environment: 'e',
        toVersion: 1,
        lockAfter: false,
        reason: 'r',
      );
      expect(fake.lastArgs!.containsKey('organizationId'), isFalse);
    });
  });

  group('SurfaceApi.surfaceStatus', () {
    test('decodes response + targets surfaceStatus method', () async {
      final fake = FakeRestageApi(
        response: {
          'surfaceType': 'paywall',
          'surfaceSlug': 'pro',
          'environmentSlug': 'production',
          'liveVersion': 2,
          'locked': false,
          'deliveryShape': 'blob',
          'versions': <dynamic>[
            {
              'version': 2,
              'publishedAt': '2026-06-25T00:00:00.000Z',
              'contentHash': 'abc',
              'isActive': true,
            },
          ],
        },
      );
      final result = await SurfaceApi(fake).surfaceStatus(
        project: 'p',
        app: 'a',
        surfaceType: SurfaceType.paywall,
        surfaceSlug: 'pro',
        environment: 'production',
      );
      expect(fake.lastMethod, 'surfaceStatus');
      expect(fake.lastArgs!['surfaceType'], 'paywall');
      expect(fake.lastArgs!['surfaceSlug'], 'pro');
      expect(fake.lastArgs!['environmentSlug'], 'production');
      expect(result.liveVersion, 2);
      expect(result.deliveryShape, 'blob');
      expect(result.supportsRollback, isTrue);
      expect(result.versions, hasLength(1));
    });
  });

  group('SurfaceApi audit reads', () {
    test(
      'listSurfaceHistory targets the history RPC and decodes rows',
      () async {
        final fake = FakeRestageApi(
          response: [
            {
              'action': 'surfacePublished',
              'actorType': 'human',
              'outcome': 'success',
              'severity': 'notice',
              'occurredAt': '2026-06-29T18:17:51.000Z',
              'context': {'surfaceSlug': 'pro'},
              'chainState': 'chained',
              'chainVerified': true,
            },
          ],
        );

        final rows = await SurfaceApi(fake).listSurfaceHistory(
          project: 'p',
          app: 'a',
          surfaceType: SurfaceType.paywall,
          surfaceSlug: 'pro',
          environment: 'staging',
          organizationId: 7,
        );

        expect(fake.lastEndpoint, 'surface');
        expect(fake.lastMethod, 'listSurfaceHistory');
        expect(fake.lastArgs!['projectSlug'], 'p');
        expect(fake.lastArgs!['appSlug'], 'a');
        expect(fake.lastArgs!['surfaceType'], 'paywall');
        expect(fake.lastArgs!['surfaceSlug'], 'pro');
        expect(fake.lastArgs!['environmentSlug'], 'staging');
        expect(fake.lastArgs!['organizationId'], 7);
        expect(rows.single.action, 'surfacePublished');
      },
    );

    test('listAuditLog targets org-wide audit log', () async {
      final fake = FakeRestageApi(response: <Map<String, dynamic>>[]);

      final rows = await SurfaceApi(fake).listAuditLog(organizationId: 7);

      expect(rows, isEmpty);
      expect(fake.lastEndpoint, 'surface');
      expect(fake.lastMethod, 'listAuditLog');
      expect(fake.lastArgs, {'organizationId': 7});
    });

    test('exportComplianceAudit decodes export rows', () async {
      final fake = FakeRestageApi(
        response: [
          {
            'occurredAt': '2026-06-29T18:17:51.000Z',
            'action': 'surfaceKilled',
            'surfaceSlug': 'pro',
            'surfaceType': 'paywall',
            'environmentSlug': 'production',
            'chainState': 'pendingChain',
            'chainVerified': false,
          },
        ],
      );

      final rows = await SurfaceApi(
        fake,
      ).exportComplianceAudit(organizationId: 7);

      expect(fake.lastMethod, 'exportComplianceAudit');
      expect(fake.lastArgs, {'organizationId': 7});
      expect(rows.single.action, 'surfaceKilled');
      expect(rows.single.chainVerified, isFalse);
    });

    test('surfaceChainVerdict decodes verdict projection', () async {
      final fake = FakeRestageApi(
        response: {
          'status': 'verified',
          'verifiedThroughEntryId': 99,
          'lastRunAt': '2026-06-29T18:30:00.000Z',
        },
      );

      final verdict = await SurfaceApi(
        fake,
      ).surfaceChainVerdict(organizationId: 7);

      expect(fake.lastMethod, 'surfaceChainVerdict');
      expect(fake.lastArgs, {'organizationId': 7});
      expect(verdict.status, 'verified');
      expect(verdict.verifiedThroughEntryId, 99);
    });
  });

  group('SurfaceApi.rollbackPreflight', () {
    test('threads the args + targets rollbackPreflight + decodes', () async {
      final fake = FakeRestageApi(
        response: {
          'surfaceType': 'onboarding',
          'surfaceSlug': 'welcome',
          'environmentSlug': 'production',
          'toVersion': 1,
          'classification': 'contractChange',
          'blockingChanges': <dynamic>['minClientRaised'],
        },
      );
      final result = await SurfaceApi(fake).rollbackPreflight(
        project: 'p',
        app: 'a',
        surfaceType: SurfaceType.onboarding,
        surfaceSlug: 'welcome',
        environment: 'production',
        toVersion: 1,
      );
      expect(fake.lastMethod, 'rollbackPreflight');
      expect(fake.lastArgs!['surfaceType'], 'onboarding');
      expect(fake.lastArgs!['surfaceSlug'], 'welcome');
      expect(fake.lastArgs!['environmentSlug'], 'production');
      expect(fake.lastArgs!['toVersion'], 1);
      expect(
        result.classification,
        RollbackPreflightClassification.contractChange,
      );
      expect(result.blockingChanges, ['minClientRaised']);
    });
  });
}
