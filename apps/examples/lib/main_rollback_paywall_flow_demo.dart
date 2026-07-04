import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:restage/restage.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart';

import 'main_hosted_paywall_demo.dart' show FakeSurfaceServer;

/// Dev-only entrypoint for the FLOW-PAYWALL operator-rollback smoke. It shows
/// what a hosted paywall client does AFTER an operator rolls the active-version
/// pointer back to an earlier FLOW-shaped paywall version (a paywall lowered to
/// a navigation flow) — the capability this chapter adds on top of flow-surface
/// rollback: re-pointing a paywall to a flow version now reaches the SDK paywall
/// flow active arm, which re-resolves + renders it, gated by the same render
/// gate as a forward OTA.
///
/// Two buttons exercise the two outcomes against an in-app fake server (no real
/// backend, no seed):
///
///  - **Rollback to a compatible flow version** serves an earlier version whose
///    client-observable contract is unchanged (only the entry copy differs) →
///    the active arm accepts it → the rolled-back version renders (the re-point
///    reached the client, distinguishable by its "· rolled back" entry copy).
///  - **Rollback to a contract-changed flow version** serves an earlier version
///    the installed client cannot honor (a raised capability floor) → the SDK
///    fails closed to the app's own bundled flow paywall (the render gate +
///    retained floor backstop). A rolled-back-but-incompatible version never
///    renders; the client renders its bundled copy.
///
/// Frictionless: the fake server stands in for the backend. For the FULL
/// operator→client device smoke, publish a lowered flow paywall and drive a real
/// `restage surface rollback <slug> --type paywall --to-version <N>` against a
/// live backend, then re-open this paywall — the active arm serves whatever the
/// (now re-pointed) pointer names.
///
/// Run it with `flutter run -t lib/main_rollback_paywall_flow_demo.dart`.
const _paywallId = 'pro_upgrade';
const _fakeBaseUrl = 'https://fake-surfaces.local';

// A modest, always-renderable capability floor for the synthetic flow paywall
// (its screens use only foundational built-ins). The incompatible rollback
// raises this above the client's bundled floor so the render gate rejects it.
const _baseMinClient = 3;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _RollbackFlowPaywallApp());
}

class _RollbackFlowPaywallApp extends StatelessWidget {
  const _RollbackFlowPaywallApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rollback active-arm flow paywall',
      theme: ThemeData.dark(useMaterial3: true),
      home: const _Launcher(),
    );
  }
}

class _Launcher extends StatelessWidget {
  const _Launcher();

  Future<void> _open(BuildContext context, {required bool compatible}) async {
    final resolver = RestageVariantResolver(
      apiKey: 'rs_pk_demo',
      environment: RestageEnvironment.sandbox,
      baseUrl: _fakeBaseUrl,
      httpClient: FakeSurfaceServer(
        buildRolledBackFlowPaywallEnvelope(compatible: compatible),
      ),
      // The client's bundled copy — the active arm gates the served version
      // against it, and fails closed to it when the served version is
      // incompatible.
      assetFallback: AssetVariantResolver(bundle: buildBundledFlowPaywall()),
    );
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Flow paywall')),
          body: RestagePaywall(
            id: _paywallId,
            resolver: resolver,
            onEvent: (event) => debugPrint('paywall event: ${event.name}'),
            loadingBuilder: (context) =>
                const Center(child: CircularProgressIndicator()),
            errorBuilder: (context, error) => const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'This paywall is unavailable right now.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101012),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () => _open(context, compatible: true),
              child: const Text(
                'Rollback to a compatible flow version → renders',
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _open(context, compatible: false),
              child: const Text(
                'Rollback to a contract-changed flow version → bundled',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A flow screen blob whose root is `OnboardingScreen` (what the flow view
/// renders), with one tappable label per (label -> event).
Uint8List _screenBlob(Map<String, String> labelToEvent) {
  final buttons = labelToEvent.entries
      .map(
        (e) => 'SizedBox(height: 96.0, child: GestureDetector('
            "onTap: event '${e.value}' { slot: \"primary\" }, "
            'child: Center(child: Text(text: "${e.key}"))))',
      )
      .join(',\n');
  final source = '''
    import restage.core;
    widget OnboardingScreen = Column(children: [
      SizedBox(height: 96.0),
      $buttons
    ]);
  ''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

/// Builds the lowered 2-screen nav flow paywall document: entry (pushes "plans"
/// via restageNav0, dismisses via skip) -> plans (a pushed paywall).
FlowDocument _navFlowDocument({
  required Uint8List entryBytes,
  required Uint8List plansBytes,
  int version = 1,
  int minClient = _baseMinClient,
}) {
  return FlowDocument(
    flow: _paywallId,
    version: version,
    schemaVersion: 1,
    minClient: minClient,
    initial: 'entry',
    actions: const {},
    screenArtifacts: {
      'entry': ScreenArtifact(
        path: 'paywall_$_paywallId.rfw',
        version: version,
        schemaVersion: 1,
        minClient: minClient,
        contentHash: FlowContentHash.compute(entryBytes),
      ),
      'plans': ScreenArtifact(
        path: 'paywall_${_paywallId}_plans.rfw',
        version: version,
        schemaVersion: 1,
        minClient: minClient,
        contentHash: FlowContentHash.compute(plansBytes),
      ),
    },
    states: const {
      'entry': ScreenFlowState(
        screen: 'entry',
        on: {
          'restageNav0': FlowTransition.goto('plans'),
          'skip': FlowTransition.goto('done'),
        },
      ),
      'plans': ScreenFlowState(screen: 'plans', on: {}),
      'done': EndFlowState(result: {}),
    },
  );
}

/// The client's bundled flow paywall (the newer version the app shipped with,
/// and the fallback the active arm gates against). Its entry copy is plain
/// "See plans".
CachingAssetBundle buildBundledFlowPaywall() {
  final entry = _screenBlob({'See plans': 'restageNav0', 'No thanks': 'skip'});
  final plans = _screenBlob({'Buy': 'restage.purchase'});
  return _FlowAssetBundle()
    ..writeFlow(
      _paywallId,
      _navFlowDocument(entryBytes: entry, plansBytes: plans, version: 2),
    )
    ..writeScreen('paywall_$_paywallId.rfw', entry)
    ..writeScreen('paywall_${_paywallId}_plans.rfw', plans);
}

/// Re-packages an earlier flow-paywall version as the surface document a backend
/// would serve for the active version AFTER a rollback re-points the pointer.
///
/// [compatible] true keeps the client-observable contract unchanged (only the
/// entry copy differs, so the smoke can tell the served version apart from the
/// bundled one) → the active arm accepts it → the rolled-back version renders.
/// false additionally raises the capability floor above the bundled contract →
/// the SDK rejects it → it falls back to the bundled flow paywall.
Uint8List buildRolledBackFlowPaywallEnvelope({required bool compatible}) {
  final entry = _screenBlob({
    'See plans · rolled back': 'restageNav0',
    'No thanks': 'skip',
  });
  final plans = _screenBlob({'Buy': 'restage.purchase'});
  final document = _navFlowDocument(
    entryBytes: entry,
    plansBytes: plans,
    // An earlier immutable version number the pointer is rolled back to.
    version: 1,
    minClient: compatible ? _baseMinClient : _baseMinClient + 1,
  );
  return SurfaceDocumentCodec.encode(
    SurfaceDocument(
      surfaceType: SurfaceType.paywall,
      surfaceSlug: _paywallId,
      version: document.version,
      minClient: document.minClient,
      payload: FlowSurfacePayload(
        flowDocument: document,
        screenBlobs: {'entry': entry, 'plans': plans},
      ),
      publishedAt: DateTime.now().toUtc(),
    ),
  );
}

/// An in-memory bundle serving the flow JSON + its screen blobs.
final class _FlowAssetBundle extends CachingAssetBundle {
  final Map<String, Uint8List> _assets = {};

  void writeFlow(String id, FlowDocument document) {
    _assets['assets/paywalls/$id.flow.json'] = Uint8List.fromList(
      utf8.encode(FlowDocumentCodec.encodePrettyJson(document)),
    );
  }

  void writeScreen(String path, Uint8List bytes) {
    _assets['assets/onboarding/screens/$path'] = bytes;
  }

  @override
  Future<ByteData> load(String key) async {
    final bytes = _assets[key];
    if (bytes == null) throw FlutterError('Unable to load asset: $key');
    return ByteData.view(bytes.buffer);
  }
}
