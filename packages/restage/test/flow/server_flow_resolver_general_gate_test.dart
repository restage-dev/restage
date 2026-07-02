import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart'
    show AssetBundle, ByteData, CachingAssetBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/runtime/builtin_catalog_capabilities.dart';
import 'package:restage_shared/restage_shared.dart';

const int _installed = RestageBuiltInCatalogCapabilities.currentVersion;
const int _refFloor = _installed + 2;

const flowRef = OnboardingFlowRef<Map<String, Object?>>(
  id: 'first_run',
  version: 1,
  minClient: _refFloor,
  decodeResult: _decodeMapResult,
);

void main() {
  const baseUrl = 'https://surfaces.example.com';
  const apiKey = 'rs_pk_test_abc123';

  setUp(Restage.debugReset);

  test('general bundled + general active structural change serves active',
      () async {
    final bundledBytes = Uint8List.fromList([1, 2, 3]);
    final activeBytes = Uint8List.fromList([4, 5, 6]);
    final resolver = ServerFlowResolver(
      baseUrl: baseUrl,
      apiKey: apiKey,
      active: true,
      bundle: _bundleFor(
        _doc(
          screenBytes: bundledBytes,
          deliveryMode: FlowDeliveryMode.general,
        ),
        bundledBytes,
      ),
      httpClient: _server(
        _envelope(
          _doc(
            version: 2,
            screenBytes: activeBytes,
            deliveryMode: FlowDeliveryMode.general,
            terminalResult: const {'completed': true, 'extra': 1},
          ),
          activeBytes,
        ),
      ),
    );

    final resolved = await resolver.resolveActiveRoot(flowRef);

    expect(resolved.document.version, 2);
    expect(resolved.screenBlobs['welcome'], activeBytes);
  });

  test('general bundled + typed active rejects to bundled', () async {
    final bundledBytes = Uint8List.fromList([1, 2, 3]);
    final activeBytes = Uint8List.fromList([4, 5, 6, 7]);
    final resolver = ServerFlowResolver(
      baseUrl: baseUrl,
      apiKey: apiKey,
      active: true,
      bundle: _bundleFor(
        _doc(
          screenBytes: bundledBytes,
          deliveryMode: FlowDeliveryMode.general,
        ),
        bundledBytes,
      ),
      httpClient: _server(
        _envelope(
          _doc(
            version: 2,
            screenBytes: activeBytes,
            deliveryMode: FlowDeliveryMode.typed,
          ),
          activeBytes,
        ),
      ),
    );

    final resolved = await resolver.resolveActiveRoot(flowRef);

    expect(resolved.document.version, 1);
    expect(resolved.screenBlobs['welcome'], bundledBytes);
  });

  test(
      'typed bundled + general active (content-only) fails closed to bundled '
      '(mode agreement is symmetric)', () async {
    // Without the delivery-mode agreement precheck the content-only gate would
    // accept this general active under the typed client (it does not compare the
    // delivery-mode marker); the precheck fails it closed to the bundled doc.
    final bundledBytes = Uint8List.fromList([1, 2, 3]);
    final activeBytes = Uint8List.fromList([4, 5, 6]);
    final resolver = ServerFlowResolver(
      baseUrl: baseUrl,
      apiKey: apiKey,
      active: true,
      bundle: _bundleFor(
        _doc(screenBytes: bundledBytes, deliveryMode: FlowDeliveryMode.typed),
        bundledBytes,
      ),
      httpClient: _server(
        _envelope(
          _doc(
            version: 2,
            screenBytes: activeBytes,
            deliveryMode: FlowDeliveryMode.general,
          ),
          activeBytes,
        ),
      ),
    );

    final resolved = await resolver.resolveActiveRoot(flowRef);

    expect(resolved.document.version, 1);
    expect(resolved.screenBlobs['welcome'], bundledBytes);
  });

  test('typed bundled + typed active structural change keeps bundled',
      () async {
    final bundledBytes = Uint8List.fromList([1, 2, 3]);
    final activeBytes = Uint8List.fromList([4, 5, 6]);
    final resolver = ServerFlowResolver(
      baseUrl: baseUrl,
      apiKey: apiKey,
      active: true,
      bundle: _bundleFor(
        _doc(
          screenBytes: bundledBytes,
          deliveryMode: FlowDeliveryMode.typed,
        ),
        bundledBytes,
      ),
      httpClient: _server(
        _envelope(
          _doc(
            version: 2,
            screenBytes: activeBytes,
            deliveryMode: FlowDeliveryMode.typed,
            terminalResult: const {'completed': true, 'extra': 1},
          ),
          activeBytes,
        ),
      ),
    );

    final resolved = await resolver.resolveActiveRoot(flowRef);

    expect(resolved.document.version, 1);
    expect(resolved.screenBlobs['welcome'], bundledBytes);
  });
}

Map<String, Object?> _decodeMapResult(Map<String, Object?> result) => result;

FlowDocument _doc({
  required Uint8List screenBytes,
  int version = 1,
  FlowDeliveryMode deliveryMode = FlowDeliveryMode.typed,
  Map<String, Object?> terminalResult = const {'completed': true},
}) {
  return FlowDocument(
    flow: 'first_run',
    version: version,
    schemaVersion: 1,
    minClient: _installed,
    initial: 'welcome',
    screenArtifacts: {
      'welcome': ScreenArtifact(
        path: 'welcome.rfw',
        version: 1,
        schemaVersion: 1,
        minClient: _installed,
        contentHash: FlowContentHash.compute(screenBytes),
      ),
    },
    states: {
      'welcome': const ScreenFlowState(
        screen: 'welcome',
        on: {'next': FlowTransition.goto('done')},
      ),
      'done': EndFlowState(result: terminalResult),
    },
    deliveryMode: deliveryMode,
  );
}

Uint8List _envelope(FlowDocument document, Uint8List screenBytes) {
  final payload = FlowSurfacePayload(
    flowDocument: document,
    screenBlobs: {'welcome': screenBytes},
  );
  final surface = SurfaceDocument(
    surfaceType: SurfaceType.onboarding,
    surfaceSlug: document.flow,
    version: document.version,
    minClient: document.minClient,
    payload: payload,
    publishedAt: DateTime.utc(2026),
  );
  return SurfaceDocumentCodec.encode(surface);
}

AssetBundle _bundleFor(FlowDocument document, Uint8List screenBytes) {
  return _TestBundle({
    'assets/onboarding/flows/first_run.flow.json':
        Uint8List.fromList(FlowDocumentCodec.encodeCanonicalJson(document)),
    'assets/onboarding/screens/welcome.rfw': screenBytes,
  });
}

MockClient _server(Uint8List envelope) {
  return MockClient((request) async {
    return http.Response(jsonEncode({'envelope': base64Encode(envelope)}), 200);
  });
}

final class _TestBundle extends CachingAssetBundle {
  _TestBundle(this._assets);

  final Map<String, Uint8List> _assets;

  @override
  Future<ByteData> load(String key) async {
    final bytes = _assets[key];
    if (bytes == null) {
      throw FlutterError('Unable to load asset: $key');
    }
    return ByteData.view(Uint8List.fromList(bytes).buffer);
  }
}
