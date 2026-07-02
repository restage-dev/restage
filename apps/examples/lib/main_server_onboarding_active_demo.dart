import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:restage/restage.dart';
import 'package:restage_shared/restage_shared.dart';

import 'onboarding/flows/first_run.dart';

/// Dev-only entrypoint that runs the first-run onboarding flow through the
/// **opt-in active arm** of [ServerFlowResolver] — the OTA path. Unlike the
/// exact-version server demo, the resolver here omits the version and asks the
/// server for the *currently-active* version, then renders it only if it is
/// contract-compatible with the app's own bundled flow (the render gate);
/// otherwise it fails closed to the bundled flow.
///
/// Two buttons exercise the two outcomes against an in-app fake server (no real
/// backend, no seed):
///
///  - **Compatible active** serves a *newer version* of the same flow with an
///    unchanged client-observable contract → the gate accepts it → the active
///    version renders (watch `[onboarding analytics]` for `resolvedVersion`).
///  - **Breaking active** serves a version the installed client cannot honor
///    (here, a raised capability floor) → the SDK rejects it (the gate plus the
///    retained capability-floor checks) → the app's own bundled flow renders
///    instead, never the incompatible server version.
///
/// Run it with `flutter run -t lib/main_server_onboarding_active_demo.dart`.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _ActiveArmLauncherApp());
}

class _ActiveArmLauncherApp extends StatelessWidget {
  const _ActiveArmLauncherApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Active-arm onboarding',
      home: const _Launcher(),
    );
  }
}

class _Launcher extends StatelessWidget {
  const _Launcher();

  Future<void> _open(BuildContext context, {required bool compatible}) async {
    final envelope = await buildActiveSurfaceEnvelope(compatible: compatible);
    Restage.configure(
      apiKey: 'rs_pk_demo',
      baseUrl: 'https://fake-surfaces.local',
      flowResolver: ServerFlowResolver(
        baseUrl: 'https://fake-surfaces.local',
        apiKey: 'rs_pk_demo',
        active: true,
        httpClient: FakeSurfaceServer(envelope),
      ),
    );
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const _FirstRunOnboardingHost()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E1B33),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () => _open(context, compatible: true),
              child: const Text('Compatible active → renders'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _open(context, compatible: false),
              child: const Text('Breaking active → falls back to bundled'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Minimal host for the first-run onboarding flow — renders it through
/// [RestageOnboarding] and fails closed to a plain surface if the flow can't be
/// made available.
class _FirstRunOnboardingHost extends StatelessWidget {
  const _FirstRunOnboardingHost();

  @override
  Widget build(BuildContext context) {
    return RestageOnboarding<FirstRunResult>(
      flow: FirstRunFlowDescriptor.ref,
      actions: FirstRunActions(
        // A real app shows the OS notification dialog here; this dev harness
        // returns a fixed granted decision so the flow renders its happy path.
        requestNotifications: (_, __) async =>
            const NotificationDecision(granted: true),
      ),
      loadingBuilder: (context) => const ColoredBox(color: Color(0xFF0E1B33)),
      unavailable: FlowUnavailablePolicy.fallback(
        builder: (context, error) => const ColoredBox(
          color: Color(0xFF0E1B33),
          child: Center(
            child: Text(
              'Let’s get you started',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: Color(0xFFF5F7FB),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Re-packages the app's own bundled first-run flow as the surface document a
/// backend would serve for the *active* version.
///
/// [compatible] true bumps only the version (the content-OTA shape the gate
/// accepts); false additionally raises the capability floor — which the SDK
/// rejects (the retained floor backstop), so it falls back to the bundled flow.
Future<Uint8List> buildActiveSurfaceEnvelope({required bool compatible}) async {
  final resolved =
      await const AssetFlowResolver().resolve(FirstRunFlowDescriptor.ref);
  final bundled = resolved.document;
  final activeDocument = _rebuildFlowDocument(
    bundled,
    version: bundled.version + 1,
    minClient: compatible ? bundled.minClient : bundled.minClient + 1,
  );
  return SurfaceDocumentCodec.encode(
    SurfaceDocument(
      surfaceType: SurfaceType.onboarding,
      surfaceSlug: activeDocument.flow,
      version: activeDocument.version,
      minClient: activeDocument.minClient,
      payload: FlowSurfacePayload(
        flowDocument: activeDocument,
        screenBlobs: resolved.screenBlobs,
      ),
      publishedAt: DateTime.now().toUtc(),
    ),
  );
}

/// Rebuilds [document] with an overridden [version] / [minClient], copying every
/// other field unchanged (FlowDocument is immutable, with no copyWith).
FlowDocument _rebuildFlowDocument(
  FlowDocument document, {
  required int version,
  required int minClient,
}) {
  return FlowDocument(
    flow: document.flow,
    version: version,
    schemaVersion: document.schemaVersion,
    minClient: minClient,
    initial: document.initial,
    screenArtifacts: document.screenArtifacts,
    states: document.states,
    actions: document.actions,
    flowState: document.flowState,
    outbound: document.outbound,
    legacyTerminalResultPassthrough: document.legacyTerminalResultPassthrough,
    unsupportedFeatures: document.unsupportedFeatures,
  );
}

/// An [http.Client] that answers every request with [envelope] wrapped in the
/// SDK serve-route response shape — the in-app stand-in for the backend.
class FakeSurfaceServer extends http.BaseClient {
  /// Creates a fake server that always serves [envelope].
  FakeSurfaceServer(this._envelope);

  final Uint8List _envelope;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = jsonEncode({'envelope': base64Encode(_envelope)});
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(body)),
      200,
      request: request,
    );
  }
}
