import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/restage.dart';
// The installed built-in catalog content version (the resolver's capability
// ceiling) is internal; this proof reaches it via the src path.
import 'package:restage/src/runtime/builtin_catalog_capabilities.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart';

/// The renderable built-in catalog floor: a baseline proof flow (Text / Center /
/// ElevatedButton) installs at the SDK's current built-in catalog version.
const int _renderableMinClient =
    RestageBuiltInCatalogCapabilities.currentVersion;

/// The host's compiled flow-ref floor for this proof. Pinned above the
/// installed catalog version (with headroom) so a valid document at the
/// installed version renders, while a delivered document above the ref floor
/// ([_aboveRefFloorMinClient]) fails closed. Derived from the installed
/// version so the relationship survives catalog version bumps.
const int _refFloorMinClient = _renderableMinClient + 2;

/// A floor strictly above the host's compiled ref floor.
const int _aboveRefFloorMinClient = _refFloorMinClient + 1;

/// Proof slice for the server delivery path: `RestageOnboarding` with a
/// `ServerFlowResolver` injected fetches a published onboarding flow from a fake
/// server and renders + traverses it end to end, and fails closed to the
/// unavailable policy on every server-side failure.
void main() {
  const baseUrl = 'https://surfaces.example.com';
  const apiKey = 'rs_pk_test_proof';

  setUp(Restage.debugReset);

  testWidgets('a server-fetched flow renders and traverses to typed completion',
      (tester) async {
    ProofResult? completed;
    final envelope = _proofEnvelope();

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RestageOnboarding<ProofResult>(
          flow: _proofRef,
          resolver: ServerFlowResolver(
            baseUrl: baseUrl,
            apiKey: apiKey,
            httpClient: _server(envelope),
          ),
          unavailable: FlowUnavailablePolicy.fallback(builder: _fallback),
          onComplete: (result) => completed = result,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // First screen renders from the server-delivered blob.
    expect(find.text('WelcomeScreen'), findsOneWidget);

    await tester.tap(find.text('WelcomeScreen'));
    await tester.pumpAndSettle();

    // Multi-screen traversal works over the server-delivered flow.
    expect(find.text('ReadyScreen'), findsOneWidget);

    await tester.tap(find.text('ReadyScreen'));
    await tester.pumpAndSettle();

    expect(completed, const ProofResult(completed: true));
  });

  testWidgets('server unavailable (404) fails closed to the policy fallback',
      (tester) async {
    await _pumpUnavailable(
      tester,
      MockClient((_) async => http.Response('', 404)),
    );
    expect(find.text('fallback:unavailable'), findsOneWidget);
  });

  testWidgets('a below-floor flow fails closed to the policy fallback',
      (tester) async {
    // A delivered flow requiring more than the host's compiled ref floor must
    // fail closed.
    final envelope = _proofEnvelope(minClient: _aboveRefFloorMinClient);
    await _pumpUnavailable(tester, _server(envelope));
    expect(find.text('fallback:unsupported_min_client'), findsOneWidget);
  });

  testWidgets('a wrong-version surface fails closed to the policy fallback',
      (tester) async {
    // The serve route is asked for version 1; a server returning a version-2
    // envelope fails the envelope-identity gate (surface_mismatch) — the wrong
    // surface must not render as this flow.
    final envelope = _proofEnvelope(version: 2);
    await _pumpUnavailable(tester, _server(envelope));
    expect(find.text('fallback:surface_mismatch'), findsOneWidget);
  });
}

Future<void> _pumpUnavailable(WidgetTester tester, http.Client client) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: RestageOnboarding<ProofResult>(
        flow: _proofRef,
        resolver: ServerFlowResolver(
          baseUrl: 'https://surfaces.example.com',
          apiKey: 'rs_pk_test_proof',
          httpClient: client,
        ),
        unavailable: FlowUnavailablePolicy.fallback(builder: _fallback),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Widget _fallback(BuildContext context, FlowUnavailableError error) {
  return Text('fallback:${error.reason}', textDirection: TextDirection.ltr);
}

const _proofRef = OnboardingFlowRef<ProofResult>(
  id: 'proof',
  version: 1,
  minClient: _refFloorMinClient,
  decodeResult: _decodeProofResult,
);

ProofResult _decodeProofResult(Map<String, Object?> result) {
  final completed = result['completed'];
  if (completed is! bool) {
    throw const FormatException('Expected completed to be a bool.');
  }
  return ProofResult(completed: completed);
}

@immutable
class ProofResult {
  const ProofResult({required this.completed});

  final bool completed;

  @override
  bool operator ==(Object other) =>
      other is ProofResult && other.completed == completed;

  @override
  int get hashCode => completed.hashCode;
}

/// Encodes a renderable two-screen onboarding flow into a surface envelope.
Uint8List _proofEnvelope(
    {int version = 1, int minClient = _renderableMinClient}) {
  final welcome = _blob('WelcomeScreen', 'next');
  final ready = _blob('ReadyScreen', 'start');
  final document = FlowDocument(
    flow: 'proof',
    version: version,
    schemaVersion: 1,
    minClient: minClient,
    initial: 'welcome',
    actions: const {},
    // Minimal proof flow: pass the terminal result straight through rather than
    // declaring an outbound terminalResult filter (data-minimization filtering
    // is exercised by the flow-runtime suite, not this delivery proof).
    legacyTerminalResultPassthrough: true,
    screenArtifacts: {
      'welcome': ScreenArtifact(
        path: 'welcome.rfw',
        version: 1,
        schemaVersion: 1,
        minClient: minClient,
        contentHash: FlowContentHash.compute(welcome),
      ),
      'ready': ScreenArtifact(
        path: 'ready.rfw',
        version: 1,
        schemaVersion: 1,
        minClient: minClient,
        contentHash: FlowContentHash.compute(ready),
      ),
    },
    states: const {
      'welcome': ScreenFlowState(
        screen: 'welcome',
        on: {'next': FlowTransition.goto('ready')},
      ),
      'ready': ScreenFlowState(
        screen: 'ready',
        on: {'start': FlowTransition.goto('done')},
      ),
      'done': EndFlowState(result: {'completed': true}),
    },
  );
  final payload = FlowSurfacePayload(
    flowDocument: document,
    screenBlobs: {'welcome': welcome, 'ready': ready},
  );
  return SurfaceDocumentCodec.encode(
    SurfaceDocument(
      surfaceType: SurfaceType.onboarding,
      surfaceSlug: document.flow,
      version: document.version,
      minClient: document.minClient,
      payload: payload,
      publishedAt: DateTime.utc(2026),
    ),
  );
}

Uint8List _blob(String label, String event) {
  final source = '''
import restage.core;
import restage.material;
import restage.cupertino;

widget OnboardingScreen = Center(
  child: ElevatedButton(
    onPressed: event "$event" {},
    child: Text(text: "$label"),
  ),
);
''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

MockClient _server(Uint8List envelope) {
  return MockClient(
    (_) async => http.Response(
      jsonEncode({'envelope': base64Encode(envelope)}),
      200,
    ),
  );
}
