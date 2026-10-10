import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:restage/restage.dart';
import 'package:restage/src/delivery/surface_sections_carrier.dart';
import 'package:restage_shared/restage_shared.dart';

import '../support/hosted_artifact_delivery.dart';

void main() {
  test('the sidecar sits beside the artifact under its stem', () {
    expect(
      localSeedSidecarPath('assets/paywalls/pro_upgrade.rfw'),
      'assets/paywalls/pro_upgrade.local.json',
    );
    expect(
      localSeedSidecarPath('assets/onboarding/flows/first_run.flow.json'),
      'assets/onboarding/flows/first_run.local.json',
    );
  });

  test('a malformed sidecar reads as none', () {
    expect(decodeLocalSeedSidecar(utf8.encode('[1]')), isNull);
    expect(decodeLocalSeedSidecar(utf8.encode('{"root": 3}')), isNull);
    expect(decodeLocalSeedSidecar(null), isNull);
    expect(
      decodeLocalSeedSidecar(utf8.encode('{"root": {"name": "Ada"}}'))!
          .localSeeds,
      {
        'root': {'name': 'Ada'},
      },
    );
  });

  test('a bundled blob carries the seeds of its sidecar', () async {
    final bundle = _Bundle({
      'assets/paywalls/pro_upgrade.rfw': Uint8List.fromList([1, 2, 3]),
      'assets/paywalls/pro_upgrade.local.json':
          Uint8List.fromList(utf8.encode('{"root": {"plan": "annual"}}')),
    });

    final variant =
        await AssetVariantResolver(bundle: bundle).resolve('pro_upgrade');

    expect(surfaceSectionsFor(variant).localSeeds, {
      'root': {'plan': 'annual'},
    });
  });

  test('a hosted blob carries its seeds, fresh and replayed', () async {
    final delivery = HostedArtifactFixture();
    final payload = BlobSurfacePayload(
      minClient: kSurfaceFeatureClientFloor,
      blob: Uint8List.fromList(const [4, 5, 6]),
      localSeeds: const <String, Map<String, Object>>{
        'root': <String, Object>{'plan': 'monthly'},
      },
    );
    final body = delivery.describeRaw(
      surfaceType: Surface.paywall,
      surfaceSlug: 'pro_upgrade',
      version: 3,
      publishedAt: DateTime.utc(2026),
      content: payload.canonicalBytes,
      payloadFormatVersion: kMaxSupportedSurfaceArtifactPayloadFormatVersion,
    );
    var online = true;
    final resolver = RestageVariantResolver(
      apiKey: 'rs_pk_test',
      environment: RestageEnvironment.production,
      baseUrl: 'https://surfaces.example.com',
      httpClient: delivery.client((_) async => online
          ? http.Response(jsonEncode(body), 200)
          : http.Response('unavailable', 503)),
    );

    final fresh = await resolver.resolve('pro_upgrade');
    online = false;
    final held = await resolver.resolve('pro_upgrade');

    expect(held.cacheHit, isTrue);
    for (final variant in [fresh, held]) {
      expect(surfaceSectionsFor(variant).localSeeds, {
        'root': {'plan': 'monthly'},
      });
    }
  });
}

final class _Bundle extends CachingAssetBundle {
  _Bundle(this._assets);

  final Map<String, Uint8List> _assets;

  @override
  Future<ByteData> load(String key) async {
    final bytes = _assets[key];
    if (bytes == null) throw FlutterError('Unable to load asset: $key');
    return ByteData.view(Uint8List.fromList(bytes).buffer);
  }
}
