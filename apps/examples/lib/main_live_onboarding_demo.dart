import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'onboarding/flows/first_run.dart';

/// Dev-only entrypoint that renders the first-run onboarding flow via
/// **Restage-hosted active-arm delivery** against a real backend — the client
/// half of the operator→client rollback smoke.
///
/// It configures a [ServerFlowResolver] with `active: true`, so the SDK serves
/// whatever the surface's active-version pointer names (gated by the render gate,
/// fail-closed to the app's bundled first-run flow). Point it at staging:
///
///     flutter run -t lib/main_live_onboarding_demo.dart \
///       --dart-define=RESTAGE_BASE_URL=https://restage-backend-staging-7annhvjkja-uc.a.run.app \
///       --dart-define=RESTAGE_API_KEY=rs_pk_...
///
/// The rollback smoke, end to end:
///  1. `restage surface publish first_run --type onboarding` (v1), then a
///     compatible content edit + republish (v2) — v2 becomes active.
///  2. Launch this on a device → it serves the ACTIVE version (v2).
///  3. `restage surface rollback first_run --type onboarding --to-version 1`.
///  4. Relaunch (or re-resolve) → it now serves the rolled-back v1 (the re-point
///     reached the active-arm client).
///  5. A contract-narrowing target instead fails closed to the bundled flow.
// Accept either flag name — `RESTAGE_BASE_URL` or `RESTAGE_BACKEND_URL` (the
// dashboard/runbook convention) — and strip any trailing slash so the SDK's
// `<baseUrl>/sdk/v1/...` path never doubles up.
const _baseUrlPrimary = String.fromEnvironment('RESTAGE_BASE_URL');
const _baseUrlBackend = String.fromEnvironment('RESTAGE_BACKEND_URL');
final _baseUrl =
    (_baseUrlPrimary.isNotEmpty ? _baseUrlPrimary : _baseUrlBackend)
        .replaceFirst(RegExp(r'/+$'), '');
const _apiKey =
    String.fromEnvironment('RESTAGE_API_KEY', defaultValue: 'rs_pk_demo');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (_baseUrl.isEmpty) {
    runApp(const _MisconfiguredApp());
    return;
  }

  Restage.configure(
    apiKey: _apiKey,
    baseUrl: _baseUrl,
    environment: RestageEnvironment.production,
    flowResolver: ServerFlowResolver(
      baseUrl: _baseUrl,
      apiKey: _apiKey,
      active: true,
    ),
  );
  runApp(const _LiveOnboardingApp());
}

class _LiveOnboardingApp extends StatelessWidget {
  const _LiveOnboardingApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Live onboarding (active-arm delivery)',
      home: const _FirstRunOnboardingHost(),
    );
  }
}

class _FirstRunOnboardingHost extends StatelessWidget {
  const _FirstRunOnboardingHost();

  @override
  Widget build(BuildContext context) {
    return RestageOnboarding<FirstRunResult>(
      flow: FirstRunFlowDescriptor.ref,
      actions: FirstRunActions(
        requestNotifications: (_, __) async =>
            const NotificationDecision(granted: true),
      ),
      loadingBuilder: (context) => const ColoredBox(color: Color(0xFF0E1B33)),
      // Fail-closed: if the active version is incompatible (or delivery fails),
      // the SDK falls back to the app's own bundled first-run flow, shown here.
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

class _MisconfiguredApp extends StatelessWidget {
  const _MisconfiguredApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'Set --dart-define=RESTAGE_BASE_URL (and RESTAGE_API_KEY) to the '
              'staging backend to run the live onboarding delivery smoke.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
