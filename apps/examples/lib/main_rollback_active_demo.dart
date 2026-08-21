import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
import 'package:restage_shared/restage_shared.dart';

import 'main_server_onboarding_active_demo.dart' show FakeSurfaceServer;
import 'onboarding/flows/first_run.dart';

/// Dev-only entrypoint for the operator-rollback smoke. It shows what an
/// active-arm flow client does AFTER an operator rolls the active-version
/// pointer back to an EARLIER version — the new capability for flow surfaces
/// (onboarding / message / survey): re-pointing the pointer reaches the
/// active-arm clients, which re-resolve and render the rolled-back version,
/// gated by the same render gate as a forward OTA.
///
/// Two buttons exercise the two outcomes against an in-app fake server (no real
/// backend, no seed):
///
///  - **Rollback to a compatible version** serves an earlier version whose
///    client-observable contract is unchanged → the gate accepts it → the
///    rolled-back version renders (the re-point reached the client).
///  - **Rollback to a contract-changed version** serves an earlier version the
///    installed client cannot honor (here, a raised capability floor) → the SDK
///    rejects it (the gate plus the retained capability-floor checks) → the
///    app's own bundled flow renders instead. The render gate still applies to
///    a rolled-back target: a rolled-back-but-incompatible version never
///    renders; the client fails closed to bundled.
///
/// Frictionless: the fake server stands in for the backend. For the FULL
/// operator→client smoke, drive a real
/// `restage surface rollback <slug> --type onboarding --to-version <N>` against
/// a live backend and re-open this surface — the active arm serves whatever the
/// (now re-pointed) pointer names.
///
/// Run it with `flutter run -t lib/main_rollback_active_demo.dart`.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _RollbackLauncherApp());
}

class _RollbackLauncherApp extends StatelessWidget {
  const _RollbackLauncherApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rollback active-arm onboarding',
      home: const _Launcher(),
    );
  }
}

class _Launcher extends StatelessWidget {
  const _Launcher();

  Future<void> _open(BuildContext context, {required bool compatible}) async {
    final envelope = await buildRolledBackSurfaceEnvelope(
      compatible: compatible,
    );
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
              child: const Text('Rollback to a compatible version → renders'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _open(context, compatible: false),
              child: const Text(
                'Rollback to a contract-changed version → bundled',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Minimal host for the first-run onboarding flow — renders it through
/// [RestageFlowGraph] and fails closed to a plain surface if the flow can't be
/// made available.
class _FirstRunOnboardingHost extends StatelessWidget {
  const _FirstRunOnboardingHost();

  @override
  Widget build(BuildContext context) {
    return RestageFlowGraph<FirstRunResult>(
      flow: firstRunFlowRef,
      actions: FirstRunActions(
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
/// backend would serve for the active version AFTER a rollback re-points the
/// pointer to an earlier version.
///
/// [compatible] true serves an earlier version number with an unchanged
/// client-observable contract (the gate accepts it → the rolled-back version
/// renders); false additionally raises the capability floor — which the SDK
/// rejects (the retained floor backstop), so it falls back to the bundled flow.
Future<Uint8List> buildRolledBackSurfaceEnvelope({
  required bool compatible,
}) async {
  final resolved = await const AssetFlowResolver().resolve(
    firstRunFlowRef,
  );
  final bundled = resolved.document;
  // A rollback re-points the active pointer to an earlier-published immutable
  // version. The client serves whatever the pointer names, gated — the
  // re-pointed version here carries a distinct version number so the smoke can
  // tell "served the re-pointed active version" apart from "fell back to the
  // bundled version". The render gate is version-agnostic (it gates the
  // contract, not the number), which is exactly why re-pointing reaches the
  // client.
  final rolledBack = _rebuildFlowDocument(
    bundled,
    version: bundled.version + 1,
    minClient: compatible ? bundled.minClient : bundled.minClient + 1,
  );
  return SurfaceDocumentCodec.encode(
    SurfaceDocument(
      surfaceType: Surface.onboarding,
      surfaceSlug: rolledBack.flow,
      version: rolledBack.version,
      minClient: rolledBack.minClient,
      payload: FlowSurfacePayload(
        flowDocument: rolledBack,
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
