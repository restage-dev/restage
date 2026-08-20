import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart' show ByteData, CachingAssetBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
// ignore: implementation_imports
import 'package:restage/src/resolver/asset_paywall_flow_preflight.dart';
// ignore: implementation_imports
import 'package:restage/src/resolver/resolved_paywall_payload.dart';
import 'package:restage_shared/restage_shared.dart';

import '../support/packaged_assets.dart';

/// Every reader of the bundle-aware asset source tells "this artifact was
/// never packaged" apart from every other failure by catching [FlutterError].
/// Answering a manifest-proven-absent key without asking the delegate means
/// this package, not Flutter, raises that error — so each reader is exercised
/// here against a packaged application to prove it still takes the branch it
/// took when the delegate raised it.
void main() {
  setUp(Restage.debugReset);

  const flowRef = OnboardingFlowRef<Map<String, Object?>>(
    id: 'first_run',
    version: 1,
    minClient: 1,
    surface: Surface.onboarding,
    decodeResult: _decodeMapResult,
  );

  test('a paywall blob that was never packaged is asset_not_found', () async {
    final bundle = _packaged({});
    final resolver = AssetVariantResolver(bundle: bundle);

    await expectLater(
      resolver.resolve('pro_upgrade'),
      throwsA(
        isA<RestagePaywallError>()
            .having((error) => error.code, 'code', 'asset_not_found'),
      ),
    );
    expect(
      bundle.loadedKeys,
      isNot(contains('assets/paywalls/pro_upgrade.rfw')),
      reason: 'these cases must run on the skip path, not the delegate path',
    );
  });

  test('a paywall flow that was never packaged falls back to the blob',
      () async {
    final blobBytes = Uint8List.fromList([1, 2, 3]);
    final resolver = AssetVariantResolver(
      bundle: _packaged({'assets/paywalls/pro_upgrade.rfw': blobBytes}),
    );

    final payload = await resolver.resolvePayload('pro_upgrade');

    expect(payload, isA<BlobPaywallPayload>());
    expect((payload as BlobPaywallPayload).variant.bytes, blobBytes);
  });

  test('a paywall flow screen that was never packaged fails closed', () async {
    final screenBytes = Uint8List.fromList([7, 8, 9]);
    final resolver = AssetVariantResolver(
      bundle: _packaged({
        'assets/paywalls/pro_upgrade.flow.json': _encodeFlow(
          _paywallDocument(flow: 'pro_upgrade', screenBytes: screenBytes),
        ),
      }),
    );

    await expectLater(
      resolver.resolvePayload('pro_upgrade'),
      throwsA(
        isA<RestagePaywallError>()
            .having((error) => error.code, 'code', 'delivery_unavailable')
            .having(
              (error) => error.message,
              'message',
              contains('missing_screen_blob'),
            ),
      ),
    );
  });

  test('a paywall flow that was never packaged preflights as absent', () async {
    final resolver = AssetVariantResolver(
      bundle: _packaged({
        'assets/paywalls/pro_upgrade.rfw': Uint8List.fromList([1, 2, 3]),
      }),
    );

    expect(
      await resolver.preflightFlowBaseline('pro_upgrade'),
      isA<AssetPaywallFlowBaselineAbsent>(),
    );
  });

  test('a flow document that was never packaged is missing_flow_json',
      () async {
    final resolver = AssetFlowResolver(bundle: _packaged({}));

    await expectLater(
      resolver.resolve(flowRef),
      throwsA(
        isA<FlowUnavailableError>()
            .having((error) => error.reason, 'reason', 'missing_flow_json'),
      ),
    );
  });
}

Map<String, Object?> _decodeMapResult(Map<String, Object?> value) => value;

Uint8List _encodeFlow(FlowDocument document) => Uint8List.fromList(
      utf8.encode(FlowDocumentCodec.encodePrettyJson(document)),
    );

FlowDocument _paywallDocument({
  required String flow,
  required Uint8List screenBytes,
}) {
  return FlowDocument(
    flow: flow,
    version: 1,
    schemaVersion: 1,
    minClient: 1,
    initial: 'welcome',
    actions: const {},
    screenArtifacts: {
      'welcome': ScreenArtifact(
        path: 'paywall_$flow.rfw',
        version: 1,
        schemaVersion: 1,
        minClient: 1,
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

/// An application that packages [entries] in one container and declares only
/// that container, so every other logical path is manifest-proven absent.
_PackagedApp _packaged(Map<String, Uint8List> entries) => _PackagedApp(entries);

final class _PackagedApp extends CachingAssetBundle {
  _PackagedApp(Map<String, Uint8List> entries)
      : _assets = <String, Uint8List>{
          'AssetManifest.bin': encodeAssetManifest(const [_containerKey]),
          _containerKey: encodeRestageContainer(entries),
        };

  static const String _containerKey =
      'assets/restage/bundles/lib/surfaces.rsbundle';

  final Map<String, Uint8List> _assets;

  /// Every key the delegate was asked for, bar the manifest itself.
  final List<String> loadedKeys = <String>[];

  @override
  Future<ByteData> load(String key) async {
    if (key != 'AssetManifest.bin') loadedKeys.add(key);
    final bytes = _assets[key];
    if (bytes == null) throw FlutterError('Unable to load asset: $key');
    return ByteData.view(Uint8List.fromList(bytes).buffer);
  }
}
