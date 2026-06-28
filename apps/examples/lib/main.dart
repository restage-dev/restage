import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'demo_event_feedback.dart';
import 'example_viewer.dart';
import 'main_draggable_sheet_demo.dart';
import 'main_hosted_paywall_demo.dart';
import 'main_modal_sheet_demo.dart';
import 'onboarding/apex_drop_demo.dart';
import 'onboarding/chrome_ladder_demo.dart';
import 'onboarding/crave_permission_demo.dart';
import 'onboarding/lumen_onboarding_demo.dart';
import 'onboarding/minimal_notice_demo.dart';
import 'onboarding/minimal_onboarding_demo.dart';
import 'onboarding/reel_cancel_demo.dart';
import 'onboarding/tally_onboarding_demo.dart';
import 'paywalls/ascend_premium.dart';
import 'paywalls/fluent_pro.dart';
import 'paywalls/lumen_premium.dart';
import 'paywalls/narrate_membership.dart';
import 'paywalls/pulse_premium.dart';
import 'paywalls/sentinel_protection.dart';
import 'stub_products.dart';
import 'user_factories.g.dart';
import 'widgets/minimal_custom_widget_demo.dart';

void main() {
  registerRestageCustomerWidgets();
  // Configure a stub product set so the "live prices" gallery tiles resolve
  // realistic prices through the remote-render path. A real app passes its
  // own store product IDs here and lets the billing gateway fill in prices.
  //
  // This example ships its demo paywalls as bundled `.rfw` assets, so it pins
  // `AssetVariantResolver` as the default. If you omit `resolver:` and pass a
  // `baseUrl`, `configure` installs `RestageVariantResolver` for Restage-hosted
  // (over-the-air) delivery instead — see `main_hosted_paywall_demo.dart` for a
  // hosted-delivery entrypoint. For a purely bundled app, pin
  // `AssetVariantResolver` (here, or per `RestagePaywall`).
  Restage.configure(
    apiKey: 'rs_pk_example',
    products: kStubProducts,
    resolver: const AssetVariantResolver(),
  );
  runApp(const RestageExampleApp());
}

class RestageExampleApp extends StatefulWidget {
  const RestageExampleApp({super.key});

  @override
  State<RestageExampleApp> createState() => _RestageExampleAppState();
}

class _RestageExampleAppState extends State<RestageExampleApp> {
  ThemeMode _themeMode = ThemeMode.light;

  void _toggleBrightness() {
    setState(() {
      _themeMode =
          _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    });
  }

  @override
  Widget build(BuildContext context) {
    // The gallery home has an AppBar, which sets the OS status-bar style from
    // the theme by default. Each full-screen demo is pushed as its own route
    // and declares its own status-bar style in ExampleViewer, keyed to that
    // surface's background brightness (which may not track the app theme).
    return MaterialApp(
      title: 'Restage Examples',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      themeMode: _themeMode,
      // Installed above the Navigator so pushed surfaces (the starters) can read
      // the brightness + flip it from their own in-surface toggle.
      builder: (context, child) => BrightnessScope(
        isDark: _themeMode == ThemeMode.dark,
        onToggle: _toggleBrightness,
        child: child!,
      ),
      home: _GalleryHome(
        isDark: _themeMode == ThemeMode.dark,
        onToggleBrightness: _toggleBrightness,
      ),
    );
  }
}

/// Exposes the app brightness and a toggle to descendants — including pushed
/// routes, since it sits above the Navigator (via `MaterialApp.builder`). Pure
/// Flutter, no state-management package.
class BrightnessScope extends InheritedWidget {
  /// Creates the brightness scope.
  const BrightnessScope({
    super.key,
    required this.isDark,
    required this.onToggle,
    required super.child,
  });

  /// Whether the app is currently in dark mode.
  final bool isDark;

  /// Flips the app between light and dark.
  final VoidCallback onToggle;

  /// The nearest scope. Asserts one is in the tree.
  static BrightnessScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<BrightnessScope>();
    assert(scope != null, 'No BrightnessScope in context');
    return scope!;
  }

  @override
  bool updateShouldNotify(BrightnessScope oldWidget) =>
      isDark != oldWidget.isDark;
}

/// Overlays a top-centre demo-chrome pill on [child]: a "delivered RFW blob"
/// label (so it's clear the surface is rendered from a render blob, not local
/// Flutter) plus a light/dark toggle to see the theme-adaptive repaint in place.
///
/// This is gallery chrome, not part of the starter surfaces — it lives here in
/// the host, so a copied starter file never carries it.
class ThemeToggleScope extends StatelessWidget {
  /// Wraps [child] with the top-centre demo-chrome pill.
  const ThemeToggleScope({super.key, required this.child});

  /// The surface the pill floats over.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = BrightnessScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Container(
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  padding: const EdgeInsets.only(left: 14),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.bolt_rounded,
                        size: 16,
                        color: scheme.onSecondaryContainer,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'RFW render blob',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSecondaryContainer,
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          scope.isDark
                              ? Icons.light_mode_outlined
                              : Icons.dark_mode_outlined,
                          size: 18,
                          color: scheme.onSecondaryContainer,
                        ),
                        tooltip: 'Toggle light / dark',
                        onPressed: scope.onToggle,
                      ),
                    ],
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

/// Demo gallery — picks an example surface to mount full-screen.
///
/// Each authored paywall (see `lib/paywalls/`) appears twice: once via direct
/// local render (the authoring preview, with placeholder prices) and once
/// via the delivered render blob (`RestagePaywall(id:)` decoding the bundled
/// `.rfw`, with live prices resolved from the stub product config). The
/// brightness toggle in the app bar flips the whole app between light and
/// dark so the theme-adaptive template can be seen repainting — and the
/// fixed-brand template can be seen holding its palette — in both.
class _GalleryHome extends StatelessWidget {
  const _GalleryHome({
    required this.isDark,
    required this.onToggleBrightness,
  });

  final bool isDark;
  final VoidCallback onToggleBrightness;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Restage SDK Examples'),
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            key: const Key('gallery-brightness-toggle'),
            icon: Icon(
              isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            ),
            tooltip: isDark ? 'Switch to light mode' : 'Switch to dark mode',
            onPressed: onToggleBrightness,
          ),
        ],
      ),
      // Centre the gallery within a comfortable reading width so it doesn't
      // stretch edge-to-edge on tablet / desktop / web windows.
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              // Barebones, copy-me starters — the smallest file per capability,
              // system-themed so they repaint with the brightness toggle. The
              // deliberate inverse of the polished branded library below: copy
              // one, retitle it, restyle it, ship it.
              const _SectionHeader('Starters — minimal, copy-me'),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Each renders from a delivered RFW blob — real Flutter '
                  'widgets, no webview.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.3,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              _ExampleTile(
                title: 'Minimal paywall',
                subtitle: 'The smallest plan-select paywall: tap a plan, the '
                    'CTA re-targets, buy. Theme-adaptive (delivered blob).',
                leading: const Icon(Icons.lock_open_outlined),
                destination: const _RemotePaywallScreen(
                  id: 'minimal_paywall',
                  priceQueries: kStubPriceQueries,
                ),
                showThemeToggle: true,
              ),
              _ExampleTile(
                title: 'Minimal onboarding',
                subtitle:
                    'A short flow that navigates, captures an answer, and '
                    'branches on it: welcome → question → a tailored ending.',
                leading: const Icon(Icons.alt_route_outlined),
                destination: const MinimalOnboardingDemo(),
                // The host supplies its own flow chrome (a persistent close +
                // an in-flow back), so no gallery escape button on top.
                showThemeToggle: true,
              ),
              _ExampleTile(
                title: 'Minimal surface',
                subtitle:
                    'The smallest flow — one screen. A notice (any screen '
                    'you render): the CTA acts, the × dismisses.',
                leading: const Icon(Icons.campaign_outlined),
                destination: const MinimalNoticeDemo(),
                showThemeToggle: true,
              ),
              _ExampleTile(
                title: 'Custom widget',
                subtitle: 'Your own @RestageWidget (StatBadge), inlined into a '
                    'delivered blob and rendered through RFW.',
                leading: const Icon(Icons.extension_outlined),
                destination: const MinimalCustomWidgetDemo(),
                showEscapeButton: true,
                showThemeToggle: true,
              ),
              const Divider(height: 32),
              const _SectionHeader('Authored in Flutter (local preview)'),
              _ExampleTile(
                title: 'Pulse Premium',
                subtitle: 'Dark segmented-tier surface. Tap a tier or plan — '
                    'the CTA re-targets.',
                leading: const Icon(Icons.graphic_eq_rounded),
                destination: const PulsePremiumPaywall(),
                // Fixed near-black canvas regardless of app theme.
                surfaceBrightness: Brightness.dark,
              ),
              _ExampleTile(
                title: 'Ascend — Free 30-Day Trial',
                subtitle: 'Trial-timeline surface. Tap "Start free trial" — a '
                    'modal sheet rises; "See All Plans" swaps the content.',
                leading: const Icon(Icons.terrain_rounded),
                destination: const AscendPremiumPaywall(),
                // Fixed white canvas regardless of app theme.
                surfaceBrightness: Brightness.light,
              ),
              _ExampleTile(
                title: 'Fluent Pro',
                subtitle: 'Gradient-hero free-trial surface. Tap a plan — the '
                    'selected check moves and the CTA re-targets; "View all '
                    'plans" pushes the all-tiers screen.',
                leading: const Icon(Icons.auto_awesome_outlined),
                destination: const FluentProPaywall(),
                // Fixed dark-gradient canvas regardless of app theme.
                surfaceBrightness: Brightness.dark,
              ),
              _ExampleTile(
                title: 'Sentinel Protection',
                subtitle:
                    'Light savings-badge selector. Tap a plan — the radio '
                    'moves and the CTA re-targets.',
                leading: const Icon(Icons.verified_user_outlined),
                destination: const SentinelProtectionPaywall(),
                // Fixed light canvas regardless of app theme.
                surfaceBrightness: Brightness.light,
              ),
              _ExampleTile(
                title: 'Narrate Membership',
                subtitle:
                    'Expandable plan cards. Tap a plan — it expands with its '
                    'benefits and CTA while the other collapses.',
                leading: const Icon(Icons.headphones_outlined),
                destination: const NarrateMembershipPaywall(),
                // Fixed white canvas regardless of app theme.
                surfaceBrightness: Brightness.light,
              ),
              _ExampleTile(
                title: 'Lumen Premium',
                subtitle: 'Calm meditation plan-selector. Tap a plan — the '
                    'radio moves and the CTA re-targets. The subscription '
                    'climax of the meditation onboarding below.',
                leading: const Icon(Icons.self_improvement_outlined),
                destination: const LumenPremiumPaywall(),
                // Fixed light calm canvas regardless of app theme.
                surfaceBrightness: Brightness.light,
              ),
              const Divider(height: 32),
              const _SectionHeader('Delivered render blob (live prices)'),
              _ExampleTile(
                title: 'Pulse Premium — live',
                subtitle: 'Bundled .rfw with the tri-state tier + plan '
                    'selection — the tap state travels inside the blob.',
                leading: const Icon(Icons.graphic_eq_outlined),
                destination: const _RemotePaywallScreen(
                  id: 'pulse_premium',
                  priceQueries: kStubPriceQueries,
                ),
                // Same fixed near-black canvas as the authored Pulse Premium.
                surfaceBrightness: Brightness.dark,
              ),
              _ExampleTile(
                title: 'Ascend — Free 30-Day Trial — live',
                subtitle: 'Bundled .rfw with the modal sheet + See-All-Plans '
                    'swap — the open/expand/select state travels in the blob.',
                leading: const Icon(Icons.terrain_outlined),
                destination: const _RemotePaywallScreen(
                  id: 'ascend_premium',
                  priceQueries: kStubPriceQueries,
                ),
                // Same fixed white canvas as the authored Ascend.
                surfaceBrightness: Brightness.light,
              ),
              _ExampleTile(
                title: 'Fluent Pro — live',
                subtitle: 'Bundled .rfw with the two-plan selection + a '
                    'Navigator.push lowered to a flow: "View all plans" → pick '
                    'a tier → back; every plan charges, inside the blob.',
                leading: const Icon(Icons.auto_awesome),
                destination: const _RemotePaywallScreen(
                  id: 'fluent_pro',
                  priceQueries: kStubPriceQueries,
                ),
                // Same fixed dark-gradient canvas as the authored Fluent Pro.
                surfaceBrightness: Brightness.dark,
              ),
              _ExampleTile(
                title: 'Sentinel Protection — live',
                subtitle: 'Bundled .rfw with the savings-badge selector — the '
                    'selected plan travels inside the blob.',
                leading: const Icon(Icons.verified_user),
                destination: const _RemotePaywallScreen(
                  id: 'sentinel_protection',
                  priceQueries: kStubPriceQueries,
                ),
                // Same fixed light canvas as the authored Sentinel Protection.
                surfaceBrightness: Brightness.light,
              ),
              _ExampleTile(
                title: 'Narrate Membership — live',
                subtitle: 'Bundled .rfw with the expandable plan cards — the '
                    'expand/collapse + selection travels inside the blob.',
                leading: const Icon(Icons.headphones),
                destination: const _RemotePaywallScreen(
                  id: 'narrate_membership',
                  priceQueries: kStubPriceQueries,
                ),
                // Same fixed white canvas as the authored Narrate Membership.
                surfaceBrightness: Brightness.light,
              ),
              _ExampleTile(
                title: 'Lumen Premium — live',
                subtitle: 'Bundled .rfw with the meditation plan-selector — '
                    'the selected plan travels inside the blob.',
                leading: const Icon(Icons.self_improvement),
                destination: const _RemotePaywallScreen(
                  id: 'lumen_premium',
                  priceQueries: kStubPriceQueries,
                ),
                // Same fixed light calm canvas as the authored Lumen Premium.
                surfaceBrightness: Brightness.light,
              ),
              _ExampleTile(
                title: 'Hello',
                subtitle: 'Minimal .rfw via RestagePaywall(id: "hello"). '
                    'Demonstrates the runtime decode + render path.',
                leading: const Icon(Icons.waving_hand_rounded),
                destination: const _RemotePaywallScreen(id: 'hello'),
                // Minimal demo blob with no own close affordance — the host
                // back button is its only escape.
                showEscapeButton: true,
              ),
              const Divider(height: 32),
              const _SectionHeader('Engagement surfaces (flow runtime)'),
              // The richest engagement surface: a multi-screen meditation
              // onboarding that ends on the embedded Lumen paywall. Welcome →
              // two personalization questions → a reminder host-action gate
              // (advance on a granted result) → recap → the paywall step;
              // purchasing ends the flow.
              _ExampleTile(
                title: 'Meditation onboarding → paywall',
                subtitle: 'A calm multi-screen flow: welcome → two questions → '
                    'enable reminders (a host-action gate) → your plan → the '
                    'meditation paywall. Purchase ends the flow.',
                leading: const Icon(Icons.spa_outlined),
                destination: const LumenOnboardingDemo(),
                showEscapeButton: false,
                // The Lumen flow paints on a fixed light calm canvas.
                surfaceBrightness: Brightness.light,
              ),
              // A location permission primer: the "Use current location" CTA
              // runs a host-action gate (advance only on a granted result);
              // "Not now" is a host-handled custom event that carries on
              // without the grant. The demo grants so the gallery walks the
              // happy path.
              _ExampleTile(
                title: 'Location permission primer',
                subtitle: 'A delivery-app location soft-ask: "Use current '
                    'location" runs a host-action gate; "Not now" carries on '
                    'without it.',
                leading: const Icon(Icons.location_on_outlined),
                destination: const CravePermissionDemo(),
                showEscapeButton: false,
                // The primer paints on a fixed white canvas.
                surfaceBrightness: Brightness.light,
              ),
              // A single-screen in-app message (a retail "drop" announcement):
              // "Shop the drop" acts (completes the flow), the × dismisses. The
              // smallest flow the runtime supports — one screen, one terminal
              // state.
              _ExampleTile(
                title: 'In-app message',
                subtitle: 'A single-screen flow: a retail "drop" announcement '
                    'whose CTA acts and whose × dismisses.',
                leading: const Icon(Icons.bolt_outlined),
                destination: const ApexDropDemo(),
                showEscapeButton: false,
                // The drop message paints on a fixed near-black canvas.
                surfaceBrightness: Brightness.dark,
              ),
              // A "before you cancel" retention survey: two linear questions →
              // a save-offer host-action gate ("Keep my discount" advances on a
              // redemption; "No thanks" fires a host-handled cancel). The demo
              // redeems so the gallery walks the retained path.
              _ExampleTile(
                title: 'Cancellation survey',
                subtitle: 'A streaming retention flow: two questions → a '
                    'save-offer host-action gate. Keep the discount or cancel.',
                leading: const Icon(Icons.live_tv_outlined),
                destination: const ReelCancelDemo(),
                showEscapeButton: false,
                // The survey paints on a fixed near-black streaming canvas.
                surfaceBrightness: Brightness.dark,
              ),
              // A goal-fork onboarding: the only surface here whose ANSWER forks
              // the path. "What are you working toward?" routes each money goal
              // to a genuinely different tailored screen, and a decision tailors
              // the ending on the captured goal (answer-driven branching, not a
              // recolored single path).
              _ExampleTile(
                title: 'Goal-fork onboarding',
                subtitle: 'A finance onboarding that branches on your answer: '
                    'pick a money goal → a tailored setup screen per goal → a '
                    'decision routes the ending. Personalization that forks.',
                leading: const Icon(Icons.savings_outlined),
                destination: const TallyOnboardingDemo(),
                showEscapeButton: false,
                // The flow paints on a fixed light cream canvas.
                surfaceBrightness: Brightness.light,
              ),
              const Divider(height: 32),
              const _SectionHeader('Capabilities (SDK mechanics)'),
              // SDK-mechanic demos, orthogonal to the themed surfaces above —
              // each shows one delivery / interaction capability rather than a
              // branded surface. They render their standalone entrypoint's
              // content inside the gallery so the capability is curated here, not
              // only reachable via `flutter run -t`.
              _ExampleTile(
                title: 'Modal sheet',
                subtitle: 'The declarative drag-to-dismiss bottom sheet. Tap '
                    '"See all plans" — a sheet rises; drag it down or tap the '
                    'scrim to dismiss.',
                leading: const Icon(Icons.vertical_align_bottom_outlined),
                destination: const ModalSheetDemo(),
                // The demo paints black behind a theme-surface card; system-back
                // returns to the gallery.
                showEscapeButton: true,
                surfaceBrightness: Brightness.dark,
              ),
              _ExampleTile(
                title: 'Draggable sheet',
                subtitle: 'The persistent, non-closeable detent sheet over a '
                    'map: peek ↔ mid ↔ full with snap physics and a tap-driven '
                    'expand channel.',
                leading: const Icon(Icons.map_outlined),
                destination: const DraggableSheetDemo(),
                showEscapeButton: true,
              ),
              _ExampleTile(
                title: 'Hosted delivery',
                subtitle:
                    'A paywall fetched through the hosted-delivery resolver '
                    '(served here by an in-app fake server), with the fail-closed '
                    'fallback — the over-the-air path, end to end.',
                leading: const Icon(Icons.cloud_download_outlined),
                destination: const HostedPaywallDemo(),
                surfaceBrightness: Brightness.dark,
              ),
              const Divider(height: 32),
              const _SectionHeader('Reference'),
              _ExampleTile(
                title: 'Chrome customization ladder',
                subtitle: 'Capability reference: a flow shown at the 5 '
                    'chrome-customization levels (Default / Theme / Slots / '
                    'Layout / DIY), with a persistent-vs-per-screen toggle. A '
                    'dev how-to for the back chrome, not a themed surface — '
                    'advance once, then switch rungs to see the affordance '
                    'change.',
                leading: const Icon(Icons.dashboard_customize_outlined),
                destination: const ChromeLadderDemo(),
                showEscapeButton: false,
                // The flow screens paint dark; the control bar below tracks the
                // app theme, but the status bar sits over the dark flow area.
                surfaceBrightness: Brightness.dark,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ExampleTile extends StatelessWidget {
  const _ExampleTile({
    required this.title,
    required this.subtitle,
    required this.leading,
    required this.destination,
    this.showEscapeButton = false,
    this.surfaceBrightness,
    this.showThemeToggle = false,
  });

  final String title;
  final String subtitle;
  final Widget leading;
  final Widget destination;

  /// Whether to overlay a top-centre light/dark toggle on the pushed surface.
  /// Set `true` for the system-themed starters so their repaint can be seen in
  /// place; the fixed-brand surfaces below leave it `false` (they hold palette).
  final bool showThemeToggle;

  /// Whether the pushed example overlays the gallery's "back to examples"
  /// escape control.
  ///
  /// Defaults to `false`: most paywalls carry their own close / back / skip
  /// affordance, which the host wires to return to the gallery (see
  /// `_returnsToGallery`), so a host button would just clash with it. Set `true`
  /// only for a closeless full-bleed surface that has no own escape — there the
  /// host button is the single way back. Engagement surfaces also leave it
  /// `false`: their own flow chrome + system-back own the escape.
  final bool showEscapeButton;

  /// The destination surface's background brightness, forwarded to
  /// [ExampleViewer.surfaceBrightness] so the OS status bar stays readable.
  /// `null` for surfaces that adapt to the app theme; an explicit value for the
  /// fixed-brightness ones (e.g. a bold dark-brand paywall, the dark-navy flow
  /// screens) so they don't pick up an unreadable status bar from the app theme.
  final Brightness? surfaceBrightness;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: leading,
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (routeContext) => ExampleViewer(
            showBackButton: showEscapeButton,
            surfaceBrightness: surfaceBrightness,
            // A local preview runs the authored paywall directly (outside
            // codegen), so its author-fired taps (`paywallEvent` /
            // `paywallPurchase`) need a dispatcher in scope. The delivered-blob
            // path brings its own via RestagePaywall; mounting one here too is
            // harmless (events resolve to the topmost dispatcher).
            child: RestagePaywallEventDispatcher(
              onEvent: (name, args) {
                debugPrint('preview event: $name $args');
                // The paywall's own close / skip affordance returns to the
                // gallery — the single, faithful escape.
                if (name == 'close' || name == 'skip') {
                  Navigator.of(routeContext).maybePop();
                }
              },
              child: showThemeToggle
                  ? ThemeToggleScope(child: destination)
                  : destination,
            ),
          ),
        ),
      ),
    );
  }
}

/// Whether [event] is the paywall's own dismissal — its close / skip affordance
/// (delivered as a [PaywallCustomEvent]) or a lowered flow's skip terminator
/// (delivered as a [PaywallDismissed] with [DismissReason.userClose]) — the cue
/// to return to the gallery. The programmatic [PaywallDismissed] fired on
/// dispose is excluded, so returning never pops the gallery itself.
bool _returnsToGallery(RestageEvent event) =>
    (event is PaywallCustomEvent &&
        (event.eventName == 'close' || event.eventName == 'skip')) ||
    (event is PaywallDismissed && event.reason == DismissReason.userClose);

/// Mounts a bundled `.rfw` asset via `RestagePaywall(id:)`.
///
/// The default resolver loads `assets/paywalls/<id>.rfw` from `rootBundle`.
/// Any [priceQueries] are handed to the runtime so
/// `data.products.<slot>.localizedPrice` resolves to a real string; with the
/// empty default the price slots read back empty and the layout shows the
/// binding placeholder. Tapping a purchase button fires the paywall's events;
/// with the stub (non-billing) configuration these resolve to no-op
/// purchase-initiated events.
class _RemotePaywallScreen extends StatelessWidget {
  const _RemotePaywallScreen({required this.id, this.priceQueries = const {}});

  final String id;
  final Map<String, PriceInfo> priceQueries;

  @override
  Widget build(BuildContext context) {
    return RestagePaywall(
      id: id,
      priceQueries: priceQueries,
      onEvent: (event) {
        debugPrint('paywall event: ${event.toMap()}');
        // The paywall's own close / skip (or a lowered flow's skip terminator)
        // returns to the gallery — the single, faithful escape. The navigation
        // back is the visible result, so no SnackBar for these.
        if (_returnsToGallery(event)) {
          Navigator.of(context).maybePop();
          return;
        }
        // Give every other delivered-paywall tap a visible result so no
        // affordance reads as broken in the demo. A real app performs the
        // actual action (start a purchase, restore entitlements, open Terms /
        // Privacy) here; the example just confirms the tap was received. Load
        // failures are surfaced by errorBuilder below, not as a SnackBar.
        showDemoPaywallEventFeedback(context, event);
      },
      // Model graceful failure: if the blob can't be resolved or decoded, show
      // a plain message instead of a blank screen. A real app would offer a
      // retry or fall back to a hard-coded paywall here.
      errorBuilder: (context, error) => Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'This paywall is unavailable right now.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ),
      ),
    );
  }
}
