import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'stub_products.dart';

/// Dev-only entrypoint for the **live surface refresh** smoke: a mounted
/// surface that updates itself in ~a second when a new version is published,
/// with no navigation and no app restart.
///
/// Live refresh is surface-general — the same lane serves paywalls, onboarding,
/// messages, and surveys identically. This entrypoint parks on a paywall
/// because an in-place content swap is the clearest thing to watch; the
/// onboarding counterpart is `main_live_onboarding_demo.dart`.
///
/// Point it at a backend that has the edge realtime service configured, and
/// pass the edge URL:
///
///     flutter run -t lib/main_live_refresh_demo.dart \
///       --dart-define=RESTAGE_BASE_URL=https://your-backend.example \
///       --dart-define=RESTAGE_API_KEY=rs_pk_... \
///       --dart-define=RESTAGE_EDGE_URL=https://your-edge.example
///
/// The smoke, end to end:
///  1. `restage surface publish narrate_membership --type paywall` (v1), then
///     launch this on a device → the paywall renders v1.
///  2. Make a visible content edit and republish (v2). The mounted paywall
///     swaps to v2 within ~2 seconds — the edge pushed the change signal and
///     the surface re-resolved in place.
///  3. Turn the device network off, republish (v3), then foreground the app.
///     The app-resume recheck catches the version it missed while offline and
///     applies v3. (No timers — the realtime lane runs only while mounted and
///     foregrounded; resume is the offline-gap backstop.)
///
/// The two triggers below opt this surface into both lanes: `updateChannel`
/// (the live edge push while mounted) and `appResume` (the resume recheck).
// Accept either flag name — `RESTAGE_BASE_URL` or `RESTAGE_BACKEND_URL` — and
// strip any trailing slash so the SDK's `<baseUrl>/sdk/v1/...` never doubles up.
const _baseUrlPrimary = String.fromEnvironment('RESTAGE_BASE_URL');
const _baseUrlBackend = String.fromEnvironment('RESTAGE_BACKEND_URL');
final _baseUrl =
    (_baseUrlPrimary.isNotEmpty ? _baseUrlPrimary : _baseUrlBackend)
        .replaceFirst(RegExp(r'/+$'), '');
const _apiKey =
    String.fromEnvironment('RESTAGE_API_KEY', defaultValue: 'rs_pk_demo');
const _edgeUrlRaw = String.fromEnvironment('RESTAGE_EDGE_URL');
const _surfaceId = 'narrate_membership';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final edgeUrl = _edgeUrlRaw.isEmpty ? null : Uri.tryParse(_edgeUrlRaw);
  if (_baseUrl.isEmpty || edgeUrl == null) {
    runApp(const _MisconfiguredApp());
    return;
  }

  // `configure` installs the hosted resolver wired to the base URL as the
  // default, and — because `liveRefreshEdgeUrl` is set with no custom
  // `updateChannel` — installs the Restage-hosted realtime channel too. The
  // mounted surface opts into it per-widget via `liveRefresh` below.
  Restage.configure(
    apiKey: _apiKey,
    baseUrl: _baseUrl,
    environment: RestageEnvironment.production,
    products: kStubProducts,
    liveRefreshEdgeUrl: edgeUrl,
  );

  // Bring your own channel (BYO): instead of `liveRefreshEdgeUrl`, drive live
  // refresh from your own infrastructure by implementing `SurfaceUpdateChannel`
  // and passing it as `updateChannel`. A signal means only "this surface may
  // have changed" — the SDK re-resolves through its normal delivery path, skips
  // unchanged content, and applies through the swap-safety gate, so a channel
  // signals opportunity and can never force a swap. A custom `updateChannel`
  // takes precedence over `liveRefreshEdgeUrl` when both are set.
  //
  //   class MyPushChannel implements SurfaceUpdateChannel {
  //     @override
  //     Stream<SurfaceUpdate> watch(SurfaceRef surface) => myPushStream
  //         .where((message) => message.matches(surface))
  //         .map((_) => SurfaceUpdate(surface));
  //   }
  //
  //   Restage.configure(
  //     apiKey: _apiKey,
  //     baseUrl: _baseUrl,
  //     products: kStubProducts,
  //     updateChannel: MyPushChannel(),
  //   );
  runApp(const _LiveRefreshApp());
}

class _LiveRefreshApp extends StatelessWidget {
  const _LiveRefreshApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Live surface refresh',
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: RestagePaywall(
          id: _surfaceId,
          priceQueries: kStubPriceQueries,
          // Opt this surface into both refresh lanes: the live edge push while
          // mounted, and the app-resume recheck for the offline gap.
          liveRefresh: const {
            SurfaceRefreshTrigger.updateChannel,
            SurfaceRefreshTrigger.appResume,
          },
          onEvent: (event) => debugPrint('paywall event: ${event.toMap()}'),
          loadingBuilder: (context) =>
              const Center(child: CircularProgressIndicator()),
          // Fail-closed: if delivery exhausts every tier, show a plain message
          // instead of a blank screen — live refresh never weakens this.
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'This surface is unavailable right now.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
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
              'Set --dart-define=RESTAGE_BASE_URL, RESTAGE_API_KEY, and '
              'RESTAGE_EDGE_URL to run the live surface refresh smoke.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
