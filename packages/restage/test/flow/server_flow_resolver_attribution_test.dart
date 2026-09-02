import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle, CachingAssetBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/runtime/builtin_catalog_capabilities.dart';
import 'package:restage_shared/restage_shared.dart';

import '../support/hosted_artifact_delivery.dart';

/// The server-flow ladder always returns the content that passed its retained
/// checks: fresh active content, hold-last-good content, or the bundled flow.
const int _installed = RestageBuiltInCatalogCapabilities.currentVersion;
const int _refFloor = _installed + 2;

/// The stub delivery for this file: it describes surfaces AND answers for
/// their content, so no test here can stub half a wire.
final HostedArtifactFixture _delivery = HostedArtifactFixture();

void main() {
  const baseUrl = 'https://surfaces.example.com';
  const apiKey = 'rs_pk_test_abc123';

  const flowRef = OnboardingFlowRef<Map<String, Object?>>(
    id: 'first_run',
    version: 1,
    minClient: _refFloor,
    surface: Surface.onboarding,
    decodeResult: _decodeMapResult,
  );

  test('fresh accept: the active content is served', () async {
    final bundledBytes = Uint8List.fromList([1, 2, 3]);
    final activeBytes = Uint8List.fromList([4, 5, 6, 7]);
    final resolver = ServerFlowResolver(
      baseUrl: baseUrl,
      apiKey: apiKey,
      active: true,
      bundle: _bundleFor(_doc(screenBytes: bundledBytes), bundledBytes),
      httpClient: _server(
        _envelope(_doc(version: 2, screenBytes: activeBytes), activeBytes),
      ),
    );

    final resolved = await resolver.resolveActiveRoot(flowRef);

    expect(resolved.document.version, 2);
    expect(resolved.screenBlobs['welcome'], orderedEquals(activeBytes));
  });

  test('fresh rejected → bundled content is served', () async {
    final bundledBytes = Uint8List.fromList([1, 2, 3]);
    final activeBytes = Uint8List.fromList([4, 5, 6]);
    // Contract expansion → the render gate REJECTS the fresh active.
    final breakingActive = _doc(
      version: 2,
      screenBytes: activeBytes,
      terminalResult: const {'completed': true, 'extra': 1},
    );
    final resolver = ServerFlowResolver(
      baseUrl: baseUrl,
      apiKey: apiKey,
      active: true,
      bundle: _bundleFor(_doc(screenBytes: bundledBytes), bundledBytes),
      httpClient: _server(_envelope(breakingActive, activeBytes)),
    );

    final resolved = await resolver.resolveActiveRoot(flowRef);

    expect(resolved.document.version, 1); // bundled rendered
    expect(resolved.screenBlobs['welcome'], orderedEquals(bundledBytes));
  });

  test(
      'fresh active accepted then rejected → hold-last-good serves the active '
      'content', () async {
    final bundledBytes = Uint8List.fromList([1, 2, 3]);
    final armABytes = Uint8List.fromList([4, 5, 6, 7]);
    final armBBytes = Uint8List.fromList([8, 9, 10]);
    final acceptedActive = _doc(version: 2, screenBytes: armABytes);
    // Contract expansion makes this otherwise fresh response incompatible.
    final rejectedActive = _doc(
      version: 3,
      screenBytes: armBBytes,
      terminalResult: const {'completed': true, 'extra': 1},
    );
    final resolver = ServerFlowResolver(
      baseUrl: baseUrl,
      apiKey: apiKey,
      active: true,
      bundle: _bundleFor(_doc(screenBytes: bundledBytes), bundledBytes),
      httpClient: _sequenceServer([
        _envelope(acceptedActive, armABytes),
        _envelope(rejectedActive, armBBytes),
      ]),
    );

    final first = await resolver.resolveActiveRoot(flowRef);
    final second = await resolver.resolveActiveRoot(flowRef);

    expect(first.document.version, 2);
    expect(first.screenBlobs['welcome'], orderedEquals(armABytes));
    // The second active document is rejected by the contract gate. The first
    // accepted active artifact is served from hold-last-good with its bytes
    // intact.
    expect(second.cacheHit, isTrue);
    expect(second.document.version, 2);
    expect(second.screenBlobs['welcome'], orderedEquals(armABytes));
  });

  test('exact resolve() serves content; a cache hit preserves it', () async {
    final screenBytes = Uint8List.fromList([1, 2, 3]);
    final resolver = ServerFlowResolver(
      baseUrl: baseUrl,
      apiKey: apiKey,
      httpClient: _server(
        _envelope(_doc(screenBytes: screenBytes), screenBytes),
      ),
    );

    final first = await resolver.resolve(flowRef);
    final second = await resolver.resolve(flowRef);

    expect(second.cacheHit, isTrue);
    expect(first.screenBlobs['welcome'], orderedEquals(screenBytes));
    expect(second.screenBlobs['welcome'], orderedEquals(screenBytes));
  });
}

Map<String, Object?> _decodeMapResult(Map<String, Object?> result) => result;

FlowDocument _doc({
  required Uint8List screenBytes,
  int version = 1,
  Map<String, Object?> terminalResult = const {'completed': true},
}) {
  return FlowDocument(
    flow: 'first_run',
    version: version,
    schemaVersion: 1,
    minClient: _installed,
    initial: 'welcome',
    actions: const {},
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
  );
}

Uint8List _envelope(FlowDocument document, Uint8List screenBytes) {
  final surface = SurfaceDocument(
    surfaceType: Surface.onboarding,
    surfaceSlug: document.flow,
    version: document.version,
    minClient: document.minClient,
    payload: FlowSurfacePayload(
      flowDocument: document,
      screenBlobs: {'welcome': screenBytes},
    ),
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
  return _delivery.client((request) async {
    return http.Response(_body(envelope), 200);
  });
}

MockClient _sequenceServer(
  List<Uint8List> responses,
) {
  var index = 0;
  return _delivery.client((request) async {
    final response = responses[index++];
    return http.Response(_body(response), 200);
  });
}

String _body(Uint8List envelope) =>
    jsonEncode(_delivery.describeEnvelope(envelope));

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
