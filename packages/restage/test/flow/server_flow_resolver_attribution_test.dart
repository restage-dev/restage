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

/// Artifact-owned attribution across the server-flow ladder: the assignment
/// stamped onto the served [ResolvedFlow] is ALWAYS the assignment of the
/// artifact that actually rendered (fresh / hold-last-good / bundled), NEVER the
/// arm of an attempt that was rejected. Test responses carry assignments to pin
/// this invariant without a request-side assignment key.
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

  const armA = FlowAssignment(
    experimentId: 'exp_copy',
    variantId: 'variant_a',
    experimentEpoch: 3,
  );
  const armB = FlowAssignment(
    experimentId: 'exp_copy',
    variantId: 'variant_b',
    experimentEpoch: 3,
  );

  test('fresh accept: the served artifact carries the FRESH arm', () async {
    final bundledBytes = Uint8List.fromList([1, 2, 3]);
    final activeBytes = Uint8List.fromList([4, 5, 6, 7]);
    final resolver = ServerFlowResolver(
      baseUrl: baseUrl,
      apiKey: apiKey,
      active: true,
      bundle: _bundleFor(_doc(screenBytes: bundledBytes), bundledBytes),
      httpClient: _server(
        _envelope(_doc(version: 2, screenBytes: activeBytes), activeBytes),
        assignment: armA,
      ),
    );

    final resolved = await resolver.resolveActiveRoot(flowRef);

    expect(resolved.document.version, 2);
    expect(resolved.assignment, equals(armA));
  });

  test(
      'fresh REJECTED → bundled served: carries the BUNDLED artifact (null), '
      'NEVER the rejected fresh arm', () async {
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
      // The rejected fresh attempt WAS assigned arm B — it must never be stamped.
      httpClient:
          _server(_envelope(breakingActive, activeBytes), assignment: armB),
    );

    final resolved = await resolver.resolveActiveRoot(flowRef);

    expect(resolved.document.version, 1); // bundled rendered
    expect(resolved.assignment, isNull); // the bundled artifact owns no arm
  });

  test(
      'fresh arm A accepted then fresh arm B rejected → hold-last-good '
      'serves and stamps arm A', () async {
    final bundledBytes = Uint8List.fromList([1, 2, 3]);
    final armABytes = Uint8List.fromList([4, 5, 6, 7]);
    final armBBytes = Uint8List.fromList([8, 9, 10]);
    final acceptedArmA = _doc(version: 2, screenBytes: armABytes);
    // Contract expansion makes this otherwise fresh response incompatible.
    final rejectedArmB = _doc(
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
        (envelope: _envelope(acceptedArmA, armABytes), assignment: armA),
        (envelope: _envelope(rejectedArmB, armBBytes), assignment: armB),
      ]),
    );

    final first = await resolver.resolveActiveRoot(flowRef);
    final second = await resolver.resolveActiveRoot(flowRef);

    expect(first.document.version, 2);
    expect(first.assignment, equals(armA));
    // Arm B is rejected by the contract gate. The accepted arm-A artifact is
    // served from hold-last-good with its own assignment and bytes intact.
    expect(second.cacheHit, isTrue);
    expect(second.document.version, 2);
    expect(second.screenBlobs['welcome'], orderedEquals(armABytes));
    expect(second.assignment, equals(armA));
    expect(second.assignment, isNot(equals(armB)));
  });

  test('exact resolve() carries the assignment; a cache hit preserves it',
      () async {
    final screenBytes = Uint8List.fromList([1, 2, 3]);
    final resolver = ServerFlowResolver(
      baseUrl: baseUrl,
      apiKey: apiKey,
      httpClient: _server(
        _envelope(_doc(screenBytes: screenBytes), screenBytes),
        assignment: armA,
      ),
    );

    final first = await resolver.resolve(flowRef);
    final second = await resolver.resolve(flowRef);

    expect(first.assignment, equals(armA));
    expect(second.cacheHit, isTrue);
    expect(second.assignment, equals(armA));
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

MockClient _server(Uint8List envelope, {FlowAssignment? assignment}) {
  return _delivery.client((request) async {
    return http.Response(_body(envelope, assignment), 200);
  });
}

MockClient _sequenceServer(
  List<({Uint8List envelope, FlowAssignment? assignment})> responses,
) {
  var index = 0;
  return _delivery.client((request) async {
    final response = responses[index++];
    return http.Response(_body(response.envelope, response.assignment), 200);
  });
}

String _body(Uint8List envelope, FlowAssignment? assignment) => jsonEncode({
      ..._delivery.describeEnvelope(envelope),
      if (assignment != null) ...{
        'experimentId': assignment.experimentId,
        'variantId': assignment.variantId,
        'experimentEpoch': assignment.experimentEpoch,
      },
    });

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
