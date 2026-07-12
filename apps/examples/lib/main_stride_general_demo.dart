import 'dart:async';

import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'onboarding/flows/stride_first_run.dart';

/// Dev-only entrypoint that renders Stride's **general-delivery** first-run
/// onboarding via Restage-hosted active-arm delivery against a real backend —
/// the client half of the general-surface rollback smoke.
///
/// A general flow is delivered through the same active-arm path as a typed one,
/// but its render gate is *structurally permissive*: the server can serve (and
/// roll back) a recomposed graph — an added screen, a reordered path — without
/// an app release, bounded to the vocabulary this app installs. Point it at
/// staging:
///
///     flutter run -t lib/main_stride_general_demo.dart \
///       --dart-define=RESTAGE_BASE_URL=https://restage-backend-staging-7annhvjkja-uc.a.run.app \
///       --dart-define=RESTAGE_API_KEY=rs_pk_...
///
/// Both defines are required: delivery fails SILENTLY closed to the bundled
/// flow by design (fail-safe delivery), so a smoke tool that launched with a
/// bad key would render the bundled copy pixel-identically to a served one.
/// This entrypoint therefore refuses to start without a real key, and it
/// overlays a version banner driven by [FlowStarted] — `resolvedVersion` is
/// set when the rendered content version differs from the bundled contract,
/// which is what makes the post-rollback step unambiguous.
///
/// The rollback smoke, end to end:
///  1. `restage surface publish stride_first_run --type onboarding` (v1), then
///     a structurally-changed republish (v2, an added screen) — v2 becomes
///     active.
///  2. Launch this on a device → v2 renders (the extra "Set your pace"
///     screen). NOTE: at this step served-v2 and bundled-v2 are the same
///     document, so the banner reads "same version as bundled" — that is a
///     design property of fail-safe delivery, not a fault. Step 4 is the
///     discriminating observation.
///  3. `restage surface rollback stride_first_run --type onboarding
///     --to-version 1` → the preflight classifies the structural revert
///     compatible (the general gate; a typed contract would classify it a
///     contract change).
///  4. Relaunch (or re-resolve) → v1 renders WITHOUT the goals screen and the
///     banner shows `server-delivered v1` (`resolvedVersion: 1` against the
///     bundled v2 contract) — provably the server's rollback, not a local
///     fallback.
// Accept either flag name — `RESTAGE_BASE_URL` or `RESTAGE_BACKEND_URL` (the
// dashboard/runbook convention) — and strip any trailing slash so the SDK's
// `<baseUrl>/sdk/v1/...` path never doubles up.
const _baseUrlPrimary = String.fromEnvironment('RESTAGE_BASE_URL');
const _baseUrlBackend = String.fromEnvironment('RESTAGE_BACKEND_URL');
final _baseUrl =
    (_baseUrlPrimary.isNotEmpty ? _baseUrlPrimary : _baseUrlBackend)
        .replaceFirst(RegExp(r'/+$'), '');
// No usable default on purpose: a placeholder key would authenticate nothing
// and silently exercise the bundled fallback (see the doc comment above). The
// URL and the key fail loudly the same way.
const _apiKey = String.fromEnvironment('RESTAGE_API_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (_baseUrl.isEmpty || _apiKey.isEmpty) {
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
  runApp(const _StrideGeneralApp());
}

class _StrideGeneralApp extends StatelessWidget {
  const _StrideGeneralApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Stride (general active-arm delivery)',
      home: _StrideOnboardingHost(),
    );
  }
}

class _StrideOnboardingHost extends StatefulWidget {
  const _StrideOnboardingHost();

  @override
  State<_StrideOnboardingHost> createState() => _StrideOnboardingHostState();
}

class _StrideOnboardingHostState extends State<_StrideOnboardingHost> {
  StreamSubscription<RestageEvent>? _events;
  String? _banner;
  String? _outcome;

  @override
  void initState() {
    super.initState();
    _events = Restage.events.listen((event) {
      if (event is FlowStarted && event.flowId == 'stride_first_run') {
        final resolved = event.resolvedVersion;
        final banner = resolved != null
            ? 'server-delivered v$resolved (bundled contract v${event.flowVersion})'
            : 'v${event.flowVersion} — same version as bundled '
                '(served-vs-fallback indistinguishable by design)';
        debugPrint('stride smoke: $banner');
        if (mounted) setState(() => _banner = banner);
      }
      if (event is FlowCustomEvent &&
          event.flowId == 'stride_first_run' &&
          event.eventName == 'skip') {
        debugPrint('stride smoke: skip fired — entering the app unfinished');
        if (mounted) setState(() => _outcome = 'Skipped past onboarding');
      }
    });
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final outcome = _outcome;
    final body = outcome != null
        ? _SmokeOutcomeScreen(outcome: outcome)
        : RestageOnboarding<Map<String, Object?>>(
            flow: StrideFirstRunFlowDescriptor.ref,
            actions: StrideFirstRunActions(
              requestNotifications: (_, __) async =>
                  const ReminderDecision(granted: true),
            ),
            // The untyped result, read defensively (an outbound field is a
            // contract, not a compiler guarantee under general delivery).
            onComplete: (result) {
              final completed = result['completed'] == true;
              debugPrint('stride smoke: completed (completed=$completed)');
              setState(
                () => _outcome = 'Completed (completed=$completed)',
              );
            },
            loadingBuilder: (context) =>
                const ColoredBox(color: Color(0xFF241024)),
            // Fail-closed: on an unrenderable active version (or a delivery
            // failure) the active arm walks the automatic ladder —
            // hold-last-good → bundled → typed-error — so the app's own
            // bundled Stride flow renders long before this builder is
            // reached. It is the final visible state, shown only if even the
            // bundled flow cannot render — and in a smoke tool that state
            // must be LOUD, so it prints and shows the actual error.
            unavailable: FlowUnavailablePolicy.fallback(
              builder: (context, error) {
                debugPrint('stride smoke: flow unavailable: ${error.message}');
                return ColoredBox(
                  color: const Color(0xFF241024),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Flow unavailable\n\n${error.message}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Color(0xFFFBEFE9),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          );

    final banner = _banner;
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        body,
        if (banner != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: ColoredBox(
                color: const Color(0xCC000000),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Text(
                    banner,
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      color: Color(0xFFFBEFE9),
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SmokeOutcomeScreen extends StatelessWidget {
  const _SmokeOutcomeScreen({required this.outcome});

  final String outcome;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF241024),
      body: SafeArea(
        child: Center(
          child: Text(
            outcome,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFFBEFE9),
              fontSize: 20,
              fontWeight: FontWeight.w700,
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
              'Set --dart-define=RESTAGE_BASE_URL and '
              '--dart-define=RESTAGE_API_KEY to the staging backend to run '
              'the general-surface rollback smoke. Both are required: with a '
              'bad key, delivery would fail silently closed to the bundled '
              'flow and the smoke could false-pass.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
