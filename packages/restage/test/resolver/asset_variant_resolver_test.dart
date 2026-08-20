import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/resolver/resolved_paywall_payload.dart';
import 'package:restage/src/runtime/builtin_catalog_capabilities.dart';
import 'package:restage/restage.dart';
import 'package:restage_shared/restage_shared.dart';

import '../support/packaged_assets.dart';

/// The bundled resolver's capability ceiling — the installed catalog version.
const int _supportedVersion = RestageBuiltInCatalogCapabilities.currentVersion;

void main() {
  test('resolves bundled asset by id', () async {
    final bundle = _PaywallAssetBundle()
      ..writeBlob('test', Uint8List.fromList([1, 2, 3]));
    final resolver = AssetVariantResolver(bundle: bundle);

    final variant = await resolver.resolve('test');

    expect(variant.bytes, [1, 2, 3]);
    expect(variant.paywallId, 'test');
    expect(bundle.loadedKeys, ['assets/paywalls/test.rfw']);
  });

  test('throws RestagePaywallError on missing asset', () async {
    final resolver = AssetVariantResolver(bundle: _PaywallAssetBundle());

    expect(
      () => resolver.resolve('does_not_exist'),
      throwsA(isA<RestagePaywallError>()
          .having((e) => e.code, 'code', 'asset_not_found')),
    );
  });

  group('resolvePayload', () {
    test('returns FlowPaywallPayload for a bundled flow paywall', () async {
      final screenBytes = Uint8List.fromList([7, 8, 9]);
      final bundle = _PaywallAssetBundle()
        ..writeFlow(
          'pro_upgrade',
          _flowDocument(
            flow: 'pro_upgrade',
            screenBytes: screenBytes,
          ),
        )
        ..writeScreen('paywall_pro_upgrade.rfw', screenBytes);
      final resolver = AssetVariantResolver(bundle: bundle);

      final payload = await resolver.resolvePayload('pro_upgrade');

      expect(payload, isA<FlowPaywallPayload>());
      final flowPayload = payload as FlowPaywallPayload;
      expect(flowPayload.paywallId, 'pro_upgrade');
      expect(flowPayload.paywallPublishedVersion, isNull);
      expect(flowPayload.flow.document.flow, 'pro_upgrade');
      expect(flowPayload.flow.screenBlobs.keys, ['welcome']);
      expect(flowPayload.flow.screenBlobs['welcome'], screenBytes);
      expect(bundle.loadedKeys, [
        'assets/paywalls/pro_upgrade.flow.json',
        'assets/paywalls/screens/paywall_pro_upgrade.rfw',
      ]);
    });

    test('returns BlobPaywallPayload for a bundled blob paywall', () async {
      final bundle = _PaywallAssetBundle()
        ..writeBlob('pro_upgrade', Uint8List.fromList([1, 2, 3]));
      final resolver = AssetVariantResolver(bundle: bundle);

      final payload = await resolver.resolvePayload('pro_upgrade');

      expect(payload, isA<BlobPaywallPayload>());
      final blobPayload = payload as BlobPaywallPayload;
      expect(blobPayload.variant.bytes, [1, 2, 3]);
      expect(blobPayload.variant.paywallId, 'pro_upgrade');
      expect(bundle.loadedKeys, [
        'assets/paywalls/pro_upgrade.flow.json',
        'assets/paywalls/pro_upgrade.rfw',
      ]);
    });

    test('fails closed when a bundled flow screen hash mismatches', () async {
      final expectedScreenBytes = Uint8List.fromList([1, 2, 3]);
      final actualScreenBytes = Uint8List.fromList([9, 9, 9]);
      final bundle = _PaywallAssetBundle()
        ..writeFlow(
          'pro_upgrade',
          _flowDocument(
            flow: 'pro_upgrade',
            screenBytes: expectedScreenBytes,
          ),
        )
        ..writeScreen('paywall_pro_upgrade.rfw', actualScreenBytes)
        ..writeBlob('pro_upgrade', Uint8List.fromList([4, 5, 6]));
      final resolver = AssetVariantResolver(bundle: bundle);

      await expectLater(
        resolver.resolvePayload('pro_upgrade'),
        throwsA(
          isA<RestagePaywallError>()
              .having((error) => error.code, 'code', 'delivery_unavailable')
              .having(
                (error) => error.message,
                'message',
                contains('hash_mismatch'),
              ),
        ),
      );
      expect(bundle.loadedKeys, [
        'assets/paywalls/pro_upgrade.flow.json',
        'assets/paywalls/screens/paywall_pro_upgrade.rfw',
      ]);
    });

    test('rejects a bundled flow whose minClient is too high', () async {
      final screenBytes = Uint8List.fromList([1, 2, 3]);
      final bundle = _PaywallAssetBundle()
        ..writeFlow(
          'pro_upgrade',
          _flowDocument(
            flow: 'pro_upgrade',
            screenBytes: screenBytes,
            minClient: _supportedVersion + 1,
          ),
        )
        ..writeScreen('paywall_pro_upgrade.rfw', screenBytes)
        ..writeBlob('pro_upgrade', Uint8List.fromList([4, 5, 6]));
      final resolver = AssetVariantResolver(bundle: bundle);

      await expectLater(
        resolver.resolvePayload('pro_upgrade'),
        throwsA(
          isA<RestagePaywallError>()
              .having((error) => error.code, 'code', 'delivery_unavailable')
              .having(
                (error) => error.message,
                'message',
                contains('unsupported_min_client'),
              ),
        ),
      );
      expect(bundle.loadedKeys, ['assets/paywalls/pro_upgrade.flow.json']);
    });

    test('keeps resolve blob-only when a flow asset also exists', () async {
      final screenBytes = Uint8List.fromList([7, 8, 9]);
      final blobBytes = Uint8List.fromList([1, 2, 3]);
      final bundle = _PaywallAssetBundle()
        ..writeFlow(
          'pro_upgrade',
          _flowDocument(
            flow: 'pro_upgrade',
            screenBytes: screenBytes,
          ),
        )
        ..writeScreen('paywall_pro_upgrade.rfw', screenBytes)
        ..writeBlob('pro_upgrade', blobBytes);
      final resolver = AssetVariantResolver(bundle: bundle);

      final variant = await resolver.resolve('pro_upgrade');

      expect(variant.bytes, blobBytes);
      expect(variant.paywallId, 'pro_upgrade');
      expect(bundle.loadedKeys, ['assets/paywalls/pro_upgrade.rfw']);
    });
  });

  group('packaged in a container', () {
    // The shipped shape: generated artifacts travel inside `.rsbundle`
    // containers and only the containers are declared assets. Resolving is
    // flow-first, so every load of a single-screen paywall used to ask for a
    // flow document that was never packaged — free on a platform that reads
    // assets from disk, one logged network failure per load on one that reads
    // them over the network.
    test('a single-screen paywall probes for no logical path', () async {
      final blobBytes = Uint8List.fromList([1, 2, 3]);
      final bundle = _ContainerAssetBundle({
        'assets/restage/bundles/lib/pro.rsbundle': _container({
          'assets/paywalls/pro_upgrade.rfw': blobBytes,
        }),
      });
      final resolver = AssetVariantResolver(bundle: bundle);

      final payload = await resolver.resolvePayload('pro_upgrade');

      expect(payload, isA<BlobPaywallPayload>());
      expect((payload as BlobPaywallPayload).variant.bytes, blobBytes);
      expect(
        bundle.loadedKeys,
        ['assets/restage/bundles/lib/pro.rsbundle'],
        reason: 'only the declared container is ever fetched',
      );
    });

    test('a flow paywall still resolves flow-first', () async {
      final screenBytes = Uint8List.fromList([7, 8, 9]);
      final bundle = _ContainerAssetBundle({
        'assets/restage/bundles/lib/pro.rsbundle': _container({
          'assets/paywalls/pro_upgrade.flow.json': Uint8List.fromList(
            utf8.encode(
              FlowDocumentCodec.encodePrettyJson(
                _flowDocument(flow: 'pro_upgrade', screenBytes: screenBytes),
              ),
            ),
          ),
          'assets/paywalls/screens/paywall_pro_upgrade.rfw': screenBytes,
          'assets/paywalls/pro_upgrade.rfw': Uint8List.fromList([4, 5, 6]),
        }),
      });
      final resolver = AssetVariantResolver(bundle: bundle);

      final payload = await resolver.resolvePayload('pro_upgrade');

      expect(payload, isA<FlowPaywallPayload>());
      final flowPayload = payload as FlowPaywallPayload;
      expect(flowPayload.flow.document.flow, 'pro_upgrade');
      expect(flowPayload.flow.screenBlobs['welcome'], screenBytes);
      expect(
        bundle.loadedKeys,
        ['assets/restage/bundles/lib/pro.rsbundle'],
        reason: 'only the declared container is ever fetched',
      );
    });
  });
}

FlowDocument _flowDocument({
  required String flow,
  required Uint8List screenBytes,
  int minClient = _supportedVersion,
  int artifactMinClient = _supportedVersion,
}) {
  return FlowDocument(
    flow: flow,
    version: 1,
    schemaVersion: 1,
    minClient: minClient,
    initial: 'welcome',
    actions: const {},
    screenArtifacts: {
      'welcome': ScreenArtifact(
        path: 'paywall_$flow.rfw',
        version: 1,
        schemaVersion: 1,
        minClient: artifactMinClient,
        contentHash: FlowContentHash.compute(screenBytes),
      ),
    },
    states: const {
      'welcome': ScreenFlowState(
        screen: 'welcome',
        on: {'next': FlowTransition.goto('done')},
      ),
      'done': EndFlowState(result: {'completed': true}),
    },
  );
}

Uint8List _container(Map<String, Uint8List> entries) => encodeRestageContainer(
      entries,
      authoredLibraryPath: 'lib/paywalls/pro_upgrade.dart',
    );

/// A fake application bundle that records which artifacts a resolve reads.
abstract base class _RecordingAssetBundle extends CachingAssetBundle {
  _RecordingAssetBundle(this._assets);

  final Map<String, Uint8List> _assets;

  /// Every key the delegate was asked for, bar the asset manifest.
  ///
  /// The manifest is how the SDK finds packaged containers, and how it knows a
  /// logical path was never packaged loose. It is not a delivery artifact, and
  /// these tests are about which delivery artifacts a resolve reads.
  final List<String> loadedKeys = [];

  @override
  Future<ByteData> load(String key) async {
    if (key != 'AssetManifest.bin') loadedKeys.add(key);
    final bytes = _assets[key];
    if (bytes == null) {
      throw FlutterError('Unable to load asset: $key');
    }
    return ByteData.view(Uint8List.fromList(bytes).buffer);
  }
}

/// An application that declares only its packaged containers, the way the
/// generated `pubspec.yaml` asset entry does.
final class _ContainerAssetBundle extends _RecordingAssetBundle {
  _ContainerAssetBundle(Map<String, Uint8List> assets)
      : super(<String, Uint8List>{
          'AssetManifest.bin': encodeAssetManifest(assets.keys),
          ...assets,
        });
}

/// An application with no asset manifest at all, so nothing about a logical
/// path can be proven before it is read.
final class _PaywallAssetBundle extends _RecordingAssetBundle {
  _PaywallAssetBundle() : super(<String, Uint8List>{});

  void writeBlob(String id, Uint8List bytes) {
    _assets['assets/paywalls/$id.rfw'] = Uint8List.fromList(bytes);
  }

  void writeFlow(String id, FlowDocument document) {
    _assets['assets/paywalls/$id.flow.json'] = Uint8List.fromList(
      utf8.encode(FlowDocumentCodec.encodePrettyJson(document)),
    );
  }

  void writeScreen(String path, Uint8List bytes) {
    _assets['assets/paywalls/screens/$path'] = Uint8List.fromList(bytes);
  }
}
