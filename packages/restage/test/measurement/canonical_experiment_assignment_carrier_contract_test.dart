import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage_shared/restage_shared.dart';

import '../support/hosted_artifact_delivery.dart';

const _outcomeLinkCarrier = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

const _canonicalJson = '{"schemaVersion":1,'
    '"experimentId":"experiment.checkout",'
    '"experimentRevisionId":"revision.checkout.1",'
    '"experimentEpochId":"epoch.checkout.1",'
    '"armId":"arm.treatment",'
    '"outcomeLinkCarrier":"$_outcomeLinkCarrier"}';

Map<String, Object?> _canonicalMap() => <String, Object?>{
      'schemaVersion': 1,
      'experimentId': 'experiment.checkout',
      'experimentRevisionId': 'revision.checkout.1',
      'experimentEpochId': 'epoch.checkout.1',
      'armId': 'arm.treatment',
      'outcomeLinkCarrier': _outcomeLinkCarrier,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('raw delivery preserves the canonical carrier across cache copies',
      () async {
    final delivery = HostedArtifactFixture();
    final client = RestageRpcClient(
      baseUrl: 'https://example.com',
      apiKey: 'rs_pk_test',
      httpClient: delivery.serving(
        delivery.deliveryBody(
          testBlobDocument(const <int>[1, 2, 3]),
          extra: <String, Object?>{
            'assignment': _canonicalMap(),
          },
        ),
      ),
    );

    final first = await client.fetchSurface(
      surfaceType: 'paywall',
      surfaceSlug: 'pro_upgrade',
    );
    final cached = await client.fetchSurface(
      surfaceType: 'paywall',
      surfaceSlug: 'pro_upgrade',
    );

    expect(first, isNotNull);
    expect(cached, isNotNull);
    expect(delivery.artifactRequests, hasLength(1));
    for (final result in <SurfaceFetchResult>[first!, cached!]) {
      final assignment = result.canonicalExperimentAssignment;
      expect(assignment, isNotNull);
      expect(
        CanonicalSurfaceExperimentAssignmentV1Codec.encodeCanonicalJson(
          assignment!,
        ),
        _canonicalJson,
      );
    }
  });

  test('ordinary unassigned delivery keeps the carrier absent', () async {
    final delivery = HostedArtifactFixture();
    final client = RestageRpcClient(
      baseUrl: 'https://example.com',
      apiKey: 'rs_pk_test',
      httpClient: delivery.serving(
        delivery.describe(testBlobDocument(const <int>[1, 2, 3])),
      ),
    );

    final result = await client.fetchSurface(
      surfaceType: 'paywall',
      surfaceSlug: 'pro_upgrade',
    );

    expect(result, isNotNull);
    expect(result!.canonicalExperimentAssignment, isNull);
  });

  test('raw decoder refuses a noncanonical assignment before fetching bytes',
      () async {
    for (final rawKey in const <String>[
      'revisionId',
      'epochId',
      'experimentEpoch',
      'variantId',
      'outcomeLinkToken',
    ]) {
      final delivery = HostedArtifactFixture();
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: delivery.serving(
          delivery.deliveryBody(
            testBlobDocument(const <int>[1, 2, 3]),
            extra: <String, Object?>{
              'assignment': <String, Object?>{
                ..._canonicalMap(),
                rawKey: 'not-canonical',
              },
            },
          ),
        ),
      );

      expect(
        await client.fetchSurface(
          surfaceType: 'paywall',
          surfaceSlug: 'pro_upgrade',
        ),
        isNull,
        reason: rawKey,
      );
      expect(
        delivery.artifactRequests,
        isEmpty,
        reason: '$rawKey must be refused before the artifact request',
      );
    }
  });

  test('raw decoder refuses an assignment that breaks the identifier law',
      () async {
    for (final armId in const <String>['ARM', 'arm/treatment', '']) {
      final delivery = HostedArtifactFixture();
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: delivery.serving(
          delivery.deliveryBody(
            testBlobDocument(const <int>[1, 2, 3]),
            extra: <String, Object?>{
              'assignment': <String, Object?>{
                ..._canonicalMap(),
                'armId': armId,
              },
            },
          ),
        ),
      );

      expect(
        await client.fetchSurface(
          surfaceType: 'paywall',
          surfaceSlug: 'pro_upgrade',
        ),
        isNull,
        reason: armId,
      );
      expect(delivery.artifactRequests, isEmpty, reason: armId);
    }
  });

  test('the fetch result declares no deleted assignment or epoch member', () {
    final source = File(
      'lib/src/restage_rpc_client/restage_rpc_client.dart',
    ).readAsStringSync();
    final start = source.indexOf('final class SurfaceFetchResult');
    expect(start, isNonNegative);
    final end = source.indexOf('\n}\n', start);
    expect(end, greaterThan(start));
    final resultSource = source.substring(start, end);

    for (final retired in const <String>[
      'SurfaceExperimentAssignment',
      'FlowAssignment',
      'experimentEpoch',
      'variantId',
    ]) {
      expect(
        RegExp('\\b${RegExp.escape(retired)}\\b').hasMatch(resultSource),
        isFalse,
        reason: 'SurfaceFetchResult still names $retired',
      );
    }
  });
}
