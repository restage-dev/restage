import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_example/demo_event_feedback.dart';
import 'package:restage_example/example_viewer.dart';
import 'package:restage_example/main.dart' show RestageExampleApp;
import 'package:restage_example/paywalls/fluent_pro.dart';
import 'package:restage_example/paywalls/narrate_membership.dart';
import 'package:restage_example/paywalls/pulse_premium.dart';
import 'package:restage_example/paywalls/sentinel_protection.dart';
import 'package:restage_example/stub_products.dart';
import 'package:restage_example/user_factories.g.dart';
import 'package:restage/restage.dart';
import 'package:rfw/formats.dart' hide WidgetLibrary;

class _StaticResolver implements VariantResolver {
  _StaticResolver(this.bytes);
  final Uint8List bytes;
  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async =>
      ResolvedVariant(bytes: bytes, paywallId: id);
}

/// A deterministic billing gateway for the interactive tests. The default
/// gateway is the real [InAppPurchaseGateway], whose `purchase()` awaits a store
/// purchase stream that never delivers a terminal status under `flutter_test` —
/// so the SDK's (correct) in-flight billing guard, which releases only when a
/// purchase completes, would stay held and silently drop a second purchase tap.
/// This stub completes immediately, so the guard releases between taps and each
/// plan tap re-targets as it would on a real device. The purchase-initiated
/// events these tests assert fire before billing, so the outcome is irrelevant.
class _TestBillingGateway implements BillingGateway {
  @override
  Future<PurchaseOutcome> purchase(String productId,
          {String? basePlanId}) async =>
      PurchaseOutcome.failed(
        productId: productId,
        errorCode: 'test_no_store',
        message: 'No real store gateway under flutter_test.',
      );

  @override
  Future<RestoreOutcome> restore() async => RestoreOutcome.noPurchases();
}

/// A resolver that always fails — mirrors [_StaticResolver]'s shape but throws
/// instead of returning a variant. Throwing a [RestagePaywallError] drives the
/// runtime's `on RestagePaywallError` branch (the same path a resolver hitting
/// a 404 / network error takes), which surfaces `PaywallLoadFailed` and the
/// host's `errorBuilder` without reporting to `FlutterError` — so the failure
/// stays inside the contract under test rather than tripping the test harness.
class _FailingResolver implements VariantResolver {
  const _FailingResolver();
  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async =>
      throw const RestagePaywallError(
        code: RestageErrorCodes.assetNotFound,
        message: 'No variant for test',
        retryable: true,
      );
}

/// Loads the committed rfwtxt for [paywallId] and encodes it as the rfw
/// binary blob the runtime decodes. The committed rfwtxt is the canonical
/// codegen output — round-tripping it through the same encode/decode the
/// production runtime uses pins what the SDK actually delivers.
///
/// The encoded bytes depend only on [paywallId], so they are cached: the
/// state-enumeration matrix mounts each blob in both brightnesses and would
/// otherwise re-read + re-encode the same file per case.
final Map<String, Uint8List> _blobCache = {};
Uint8List _encodePaywall(String paywallId) => _blobCache.putIfAbsent(
      paywallId,
      () => Uint8List.fromList(
        encodeLibraryBlob(
          parseLibraryFile(
            File('assets/paywalls/$paywallId.rfwtxt').readAsStringSync(),
          ),
        ),
      ),
    );

/// The example app's seed colour — shared by every test that builds an
/// indigo-seeded scheme so the tests judge a single, consistent theme.
const _kExampleSeed = Colors.indigo;

/// The indigo-seeded [ColorScheme] for [brightness].
ColorScheme _exampleScheme(Brightness brightness) =>
    ColorScheme.fromSeed(seedColor: _kExampleSeed, brightness: brightness);

/// The example app's [ThemeData] for [brightness].
ThemeData _exampleTheme(Brightness brightness) =>
    ThemeData(useMaterial3: true, colorScheme: _exampleScheme(brightness));

/// Mounts [paywallId]'s decoded blob and collects the events it fires. The
/// interactive-selection groups all drive the delivered blob (the same
/// state/`set`/`switch` the runtime decodes), pinned to one brightness since
/// selection is brightness-independent.
Future<List<RestageEvent>> _pumpInteractivePaywall(
  WidgetTester tester,
  String paywallId,
) async {
  _useTallSurface(tester);
  final bytes = _encodePaywall(paywallId);
  final events = <RestageEvent>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: _exampleTheme(Brightness.dark),
      home: Scaffold(
        body: RestagePaywall(
          id: paywallId,
          resolver: _StaticResolver(bytes),
          priceQueries: kStubPriceQueries,
          onEvent: events.add,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return events;
}

/// Scrolls [label] into view and taps it (the CTA buttons are plain text).
Future<void> _tapText(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

/// Scrolls the plan row carrying [label] into view and taps it. Plan rows are
/// wrapped in the selector's `GestureDetector`, so tap the nearest such ancestor
/// of the label rather than the text itself.
Future<void> _tapPlanRow(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(
    find.ancestor(
      of: find.text(label),
      matching: find.byType(GestureDetector),
    ),
  );
  await tester.pumpAndSettle();
}

/// Taps a text label inside the open modal sheet (a `BottomSheet`). When the
/// sheet is open the underlay stays mounted behind the scrim, so a bare
/// `find.text` for a label shared by the footer and the sheet (e.g. the
/// "Start free trial" CTA) is ambiguous — scoping to the `BottomSheet` picks the
/// sheet's copy.
Future<void> _tapSheetText(WidgetTester tester, String label) async {
  final target = find.descendant(
    of: find.byType(BottomSheet),
    matching: find.text(label),
  );
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

/// The product id of the most recent purchase the paywall fired, or null.
String? _lastPurchasedProductId(List<RestageEvent> events) {
  final ids =
      events.whereType<PurchaseInitiated>().map((e) => e.productId).toList();
  return ids.isEmpty ? null : ids.last;
}

/// Gives the test a tall canvas so a fit-to-display (bounded, unscrolled)
/// paywall renders without a RenderFlex overflow under the test's wide Ahem
/// font. These tests pin render / prices / interaction — not fit; the
/// device-fit gate is the Inter + safe-area fit-test (run separately). Width
/// stays 800 so the full-width-CTA geometry assertions are unchanged.
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// The standard interactive-plan-selection group for [paywallId]: the
/// [defaultPlan] (`'annual'` or `'monthly'`) is the pre-selected plan, so the
/// CTA buys it when nothing is tapped; tapping the other plan row re-targets the
/// CTA, and re-selecting the default flips it back. [ctaLabel] is the purchase
/// button's text.
///
/// This drives the *delivered blob* — the same state/`set`/`switch` the runtime
/// decodes — and asserts the purchase fires for the selected product, not a
/// fixed slot. It does not touch the (intentionally per-paywall) selector
/// widgets; it pins their shared observable contract.
void _interactivePlanSelectionGroup({
  required String paywallId,
  required String ctaLabel,
  String defaultPlan = 'annual',
  // The plan-row labels `_tapPlanRow` taps. Default to 'Annual'/'Monthly' (the
  // common selector copy); override for selectors with their own plan names
  // (e.g. 'Personal'/'Family', '1-year plan'/'1-month plan').
  String? defaultPlanLabel,
  String? otherPlanLabel,
  // The product the *other* plan buys. Defaults to the monthly/annual
  // complement of [defaultPlan]; override when the other plan is neither
  // (e.g. Fluent Pro's Family row buys the family product).
  String? otherProduct,
}) {
  // The pre-selected plan and its complement, with the products they buy.
  final defaultIsAnnual = defaultPlan == 'annual';
  final defaultLabel =
      defaultPlanLabel ?? (defaultIsAnnual ? 'Annual' : 'Monthly');
  final otherLabel = otherPlanLabel ?? (defaultIsAnnual ? 'Monthly' : 'Annual');
  final defaultProduct = 'com.restage.pro.$defaultPlan';
  final resolvedOtherProduct = otherProduct ??
      (defaultIsAnnual ? 'com.restage.pro.monthly' : 'com.restage.pro.annual');

  group('interactive plan selection — $paywallId', () {
    testWidgets('defaults to the $defaultLabel plan when nothing is tapped',
        (tester) async {
      final events = await _pumpInteractivePaywall(tester, paywallId);
      await _tapText(tester, ctaLabel);
      expect(_lastPurchasedProductId(events), defaultProduct);
    });

    testWidgets('selecting $otherLabel re-targets the CTA to that product',
        (tester) async {
      final events = await _pumpInteractivePaywall(tester, paywallId);
      await _tapPlanRow(tester, otherLabel);
      await _tapText(tester, ctaLabel);
      expect(_lastPurchasedProductId(events), resolvedOtherProduct);
    });

    testWidgets('selecting $otherLabel then $defaultLabel re-targets back',
        (tester) async {
      final events = await _pumpInteractivePaywall(tester, paywallId);
      await _tapPlanRow(tester, otherLabel);
      await _tapPlanRow(tester, defaultLabel);
      await _tapText(tester, ctaLabel);
      expect(_lastPurchasedProductId(events), defaultProduct);
    });
  });
}

void main() {
  setUp(() {
    Restage.debugReset();
    Restage.configure(
      apiKey: 'rs_pk_test',
      products: kStubProducts,
      resolver: const AssetVariantResolver(),
      billingGateway: _TestBillingGateway(),
    );
    registerRestageCustomerWidgets();
  });

  group('gallery escape — a paywall close returns to the gallery', () {
    // The Fluent Pro card has its own back affordance (`paywallEvent('close')`);
    // tapping it should return to the gallery (no host back button needed).
    final backArrow = find.byWidgetPredicate(
      (widget) =>
          widget is Icon &&
          widget.icon?.codePoint == Icons.arrow_back_rounded.codePoint,
    );

    testWidgets('local preview: the close affordance pops back to the gallery',
        (tester) async {
      _useTallSurface(tester);
      await tester.pumpWidget(const RestageExampleApp());
      await tester.pumpAndSettle();

      await _tapText(tester, 'Fluent Pro');
      // On the paywall now (the gallery is covered).
      expect(find.text('Personal'), findsOneWidget);

      // The paywall's own back affordance fires `close` -> returns to gallery.
      await tester.tap(backArrow);
      await tester.pumpAndSettle();
      expect(find.text('Restage SDK Examples'), findsOneWidget);
      expect(find.text('Personal'), findsNothing);
    });

    testWidgets('delivered blob: the close affordance pops back to the gallery',
        (tester) async {
      _useTallSurface(tester);
      await tester.pumpWidget(const RestageExampleApp());
      await tester.pumpAndSettle();

      await _tapText(tester, 'Fluent Pro — live');
      expect(find.text('Personal'), findsOneWidget);

      // In the blob the `close` event surfaces as a PaywallCustomEvent, which
      // the host maps to a gallery return.
      await tester.tap(backArrow);
      await tester.pumpAndSettle();
      expect(find.text('Restage SDK Examples'), findsOneWidget);
      expect(find.text('Personal'), findsNothing);
    });

    // The hosted-delivery tile renders Narrate (which carries its own close
    // affordance) through the fake-server over-the-air path. Narrate's close
    // surfaces as a `close` PaywallCustomEvent that the demo's own onEvent maps
    // to a host pop — without that wiring the close button fires but does nothing
    // (the SDK shadows the gallery's ambient dispatcher), trapping the user.
    final hostedClose = find.byWidgetPredicate(
      (widget) =>
          widget is Icon &&
          widget.icon?.codePoint == Icons.close_rounded.codePoint,
    );

    testWidgets(
        'hosted delivery: the served paywall close pops back to the gallery',
        (tester) async {
      _useTallSurface(tester);
      await tester.pumpWidget(const RestageExampleApp());
      await tester.pumpAndSettle();

      await _tapText(tester, 'Hosted delivery');
      // The fake server fetch + decode + render settles; Narrate is on stage.
      await tester.pumpAndSettle();
      expect(find.text('Restage SDK Examples'), findsNothing);
      expect(hostedClose, findsWidgets);

      await tester.tap(hostedClose.first);
      await tester.pumpAndSettle();
      expect(find.text('Restage SDK Examples'), findsOneWidget);
    });
  });

  group('remote-render path (codegen → encode → decode → render)', () {
    testWidgets(
        'default asset resolver loads the committed blob from rootBundle',
        (tester) async {
      // The gallery's "live prices" tiles mount RestagePaywall(id:) with no
      // explicit resolver, falling back to the configured default — here
      // AssetVariantResolver (set in setUp), which loads
      // assets/paywalls/<id>.rfw from rootBundle. Pinning that path (rather
      // than the _StaticResolver the other tests use) confirms the
      // bundled-asset render the gallery and integration tests depend on.
      _useTallSurface(tester);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RestagePaywall(
              id: 'pulse_premium',
              priceQueries: kStubPriceQueries,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Pulse'), findsOneWidget);
      // The default tier (Premium) annual price the committed blob renders.
      expect(find.text(r'$83.99'), findsOneWidget);
    });
  });

  group('Fluent Pro — gradient-hero two-plan selection', () {
    testWidgets('renders the hero, the plan cards, and the CTA (local)',
        (tester) async {
      _useTallSurface(tester);
      await tester.pumpWidget(const MaterialApp(home: FluentProPaywall()));
      await tester.pumpAndSettle();
      expect(find.text('Family'), findsOneWidget);
      expect(find.text('Personal'), findsOneWidget);
      expect(find.text('MOST POPULAR'), findsOneWidget);
      expect(find.text('START MY FREE WEEK'), findsOneWidget);
    });

    testWidgets('fluent_pro round-trips through the SDK runtime',
        (tester) async {
      _useTallSurface(tester);
      final bytes = _encodePaywall('fluent_pro');
      final failures = <PaywallLoadFailed>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RestagePaywall(
            id: 'fluent_pro',
            resolver: _StaticResolver(bytes),
            priceQueries: kStubPriceQueries,
            onEvent: (e) {
              if (e is PaywallLoadFailed) failures.add(e);
            },
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(
        failures.map((f) => '${f.errorCode}: ${f.message}').toList(),
        isEmpty,
      );
      expect(find.text('Personal'), findsOneWidget);
      expect(find.text('MOST POPULAR'), findsOneWidget);
    });

    // The plan-selection re-target contract is driven by
    // _interactivePlanSelectionGroup('fluent_pro', ...) below.
  });

  group('Sentinel Protection — savings-badge plan selection', () {
    testWidgets('renders the header, the plan cards, and the CTA (local)',
        (tester) async {
      _useTallSurface(tester);
      await tester
          .pumpWidget(const MaterialApp(home: SentinelProtectionPaywall()));
      await tester.pumpAndSettle();
      expect(find.text('Select your protection plan'), findsOneWidget);
      expect(find.text('1-year plan'), findsOneWidget);
      expect(find.text('1-month plan'), findsOneWidget);
      expect(find.text('Save 50%'), findsOneWidget);
      expect(find.text('Start subscription'), findsOneWidget);
    });

    testWidgets('sentinel_protection round-trips through the SDK runtime',
        (tester) async {
      _useTallSurface(tester);
      final bytes = _encodePaywall('sentinel_protection');
      final failures = <PaywallLoadFailed>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RestagePaywall(
            id: 'sentinel_protection',
            resolver: _StaticResolver(bytes),
            priceQueries: kStubPriceQueries,
            onEvent: (e) {
              if (e is PaywallLoadFailed) failures.add(e);
            },
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(
        failures.map((f) => '${f.errorCode}: ${f.message}').toList(),
        isEmpty,
      );
      expect(find.text('Select your protection plan'), findsOneWidget);
      expect(find.text('Save 50%'), findsOneWidget);
    });

    // The plan-selection re-target contract is driven by
    // _interactivePlanSelectionGroup('sentinel_protection', ...) below.
  });

  group('Narrate Membership — expandable plan cards', () {
    testWidgets('renders the status card, the plan cards, and the CTA (local)',
        (tester) async {
      _useTallSurface(tester);
      await tester
          .pumpWidget(const MaterialApp(home: NarrateMembershipPaywall()));
      await tester.pumpAndSettle();
      expect(find.text('CURRENT MEMBERSHIP'), findsOneWidget);
      expect(find.text('Get the most out of Narrate'), findsOneWidget);
      expect(find.text('Standard'), findsOneWidget);
      expect(find.text('Premium Plus'), findsOneWidget);
      expect(find.text('Try Standard free'), findsOneWidget);
      expect(find.text('Try Premium Plus free'), findsNothing);
    });

    testWidgets('narrate_membership round-trips through the SDK runtime',
        (tester) async {
      _useTallSurface(tester);
      final bytes = _encodePaywall('narrate_membership');
      final failures = <PaywallLoadFailed>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RestagePaywall(
            id: 'narrate_membership',
            resolver: _StaticResolver(bytes),
            priceQueries: kStubPriceQueries,
            onEvent: (e) {
              if (e is PaywallLoadFailed) failures.add(e);
            },
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(
        failures.map((f) => '${f.errorCode}: ${f.message}').toList(),
        isEmpty,
      );
      expect(find.text('Get the most out of Narrate'), findsOneWidget);
      expect(find.text('Try Standard free'), findsOneWidget);
    });

    testWidgets(
        'selecting a card expands it (and collapses the other) + re-targets '
        'the purchase inside the blob', (tester) async {
      final events =
          await _pumpInteractivePaywall(tester, 'narrate_membership');

      // Default: Standard expanded (its CTA shows), Premium collapsed.
      expect(find.text('Try Standard free'), findsOneWidget);
      expect(find.text('Try Premium Plus free'), findsNothing);
      await _tapText(tester, 'Try Standard free');
      expect(_lastPurchasedProductId(events), 'com.restage.pro.monthly');

      // Selecting Premium Plus expands it (and collapses Standard).
      await _tapPlanRow(tester, 'Premium Plus');
      expect(find.text('Try Standard free'), findsNothing);
      expect(find.text('Try Premium Plus free'), findsOneWidget);
      await _tapText(tester, 'Try Premium Plus free');
      expect(_lastPurchasedProductId(events), 'com.restage.pro.annual');

      // Re-selecting Standard flips it back.
      await _tapPlanRow(tester, 'Standard');
      expect(find.text('Try Standard free'), findsOneWidget);
      await _tapText(tester, 'Try Standard free');
      expect(_lastPurchasedProductId(events), 'com.restage.pro.monthly');
    });
  });

  group('fixed-brand — pulse_premium is toggle-safe', () {
    // The bold template is a deliberate single-brightness brand surface:
    // it hardcodes its palette and never reads the ambient theme, so the
    // gallery's brightness toggle can't change — or break — it.
    const brandCanvas = Color(0xFF0B0B12);

    Future<Color?> pulseScaffoldBgUnder(
      WidgetTester tester,
      Brightness brightness,
    ) async {
      _useTallSurface(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: _exampleTheme(brightness),
          home: const PulsePremiumPaywall(),
        ),
      );
      await tester.pumpAndSettle();
      return tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor;
    }

    testWidgets('keeps its fixed brand canvas in both brightnesses',
        (tester) async {
      final underLight = await pulseScaffoldBgUnder(tester, Brightness.light);
      final underDark = await pulseScaffoldBgUnder(tester, Brightness.dark);
      expect(underLight, brandCanvas);
      expect(underDark, brandCanvas);
    });
  });

  group('design-state enumeration — brightness × price', () {
    // The full design-state matrix: each template, both
    // brightnesses, both price states. Price state maps to the render path —
    // local render shows the binding placeholder ($X.XX); the delivered blob
    // resolves live prices from the stub product config.
    Future<void> pumpLocal(
      WidgetTester tester,
      Widget paywall,
      Brightness brightness,
    ) async {
      _useTallSurface(tester);
      await tester.pumpWidget(
        MaterialApp(theme: _exampleTheme(brightness), home: paywall),
      );
      await tester.pumpAndSettle();
    }

    Future<List<PaywallLoadFailed>> pumpRemote(
      WidgetTester tester,
      String id,
      Brightness brightness,
    ) async {
      _useTallSurface(tester);
      final bytes = _encodePaywall(id);
      final failures = <PaywallLoadFailed>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: _exampleTheme(brightness),
          home: Scaffold(
            body: RestagePaywall(
              id: id,
              resolver: _StaticResolver(bytes),
              priceQueries: kStubPriceQueries,
              onEvent: (e) {
                if (e is PaywallLoadFailed) failures.add(e);
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return failures;
    }

    // Each template, identified by its id, local-mount builder, and the
    // heading that pins it on screen. The local and remote cases are uniform
    // across templates, so they enumerate from this one table.
    // The live (delivered-blob) annual + monthly prices each template shows by
    // default. pulse_premium's tier strip drives a per-tier price, so its
    // default (Premium tier) shows the Premium slot prices.
    final templates = <({
      String id,
      Widget Function() build,
      String heading,
      String annualPrice,
      String monthlyPrice,
    })>[
      (
        id: 'pulse_premium',
        build: PulsePremiumPaywall.new,
        heading: 'Pulse',
        annualPrice: r'$83.99',
        monthlyPrice: r'$7.99',
      ),
    ];

    for (final brightness in [Brightness.light, Brightness.dark]) {
      final label = brightness.name;
      for (final t in templates) {
        testWidgets('${t.id} · local · placeholder prices · $label',
            (tester) async {
          await pumpLocal(tester, t.build(), brightness);
          expect(find.text(t.heading), findsOneWidget);
          // Both plan rows show the binding placeholder on the local path.
          expect(find.text(r'$X.XX'), findsNWidgets(2));
        });

        testWidgets('${t.id} · remote · live prices · $label', (tester) async {
          final failures = await pumpRemote(tester, t.id, brightness);
          expect(failures, isEmpty);
          expect(find.text(t.heading), findsOneWidget);
          expect(find.text(t.annualPrice), findsOneWidget);
          expect(find.text(t.monthlyPrice), findsOneWidget);
        });
      }
    }
  });

  // The Ascend recreation is now a multi-screen flow with a collapsed-by-
  // default plan sheet, so it does not fit the shared (both-rows-visible)
  // interactive contract; its disclosure + flow render are covered in
  // ascend_flow_test.dart.

  // pulse_premium drives BOTH a tier strip AND a period toggle into a single
  // tier x period charge, so it doesn't fit the shared single-axis contract;
  // its tier + period + feature-list behaviour is covered in the dedicated
  // group below.

  // Fluent Pro names its rows Personal (the default, monthly) / Family; its
  // hero + render are covered in the 'Fluent Pro' group above.
  _interactivePlanSelectionGroup(
    paywallId: 'fluent_pro',
    ctaLabel: 'START MY FREE WEEK',
    defaultPlan: 'monthly',
    defaultPlanLabel: 'Personal',
    otherPlanLabel: 'Family',
    // The Family row buys the family product (the $119.99 plan it displays),
    // not the annual product.
    otherProduct: 'com.restage.pro.family',
  );

  // Sentinel Protection names its rows '1-year plan' (the default, annual) /
  // '1-month plan'; its render is covered in the 'Sentinel Protection' group.
  _interactivePlanSelectionGroup(
    paywallId: 'sentinel_protection',
    ctaLabel: 'Start subscription',
    defaultPlanLabel: '1-year plan',
    otherPlanLabel: '1-month plan',
  );

  // Lumen Premium — the meditation paywall that climaxes the onboarding flow.
  // Annual is the default; tapping 'Monthly' re-targets the purchase (the L9
  // dead-control guard: the plan choice must actually move the money path).
  _interactivePlanSelectionGroup(
    paywallId: 'lumen_premium',
    ctaLabel: 'Start free trial',
    defaultPlanLabel: 'Annual',
    otherPlanLabel: 'Monthly',
  );

  group('tri-state tier strip — pulse_premium', () {
    // The second selection axis (beyond the plan toggle): an `int` tier strip
    // (Basic | Premium | Premium+) whose selected segment fills. It travels
    // inside the delivered blob as a `switch state.selectedTier`, so this drives
    // the tap and asserts the fill moves — not just that the strip renders.
    const accent = Color(0xFF7B61FF);
    const transparent = Color(0x00000000);

    // The fill colour of the tier segment labelled [label] — its nearest
    // Container ancestor in the delivered blob.
    Color? tierFill(WidgetTester tester, String label) {
      final container = tester.widget<Container>(
        find
            .ancestor(of: find.text(label), matching: find.byType(Container))
            .first,
      );
      final decoration = container.decoration;
      return decoration is BoxDecoration ? decoration.color : container.color;
    }

    testWidgets('moves its selected fill on tap', (tester) async {
      await _pumpInteractivePaywall(tester, 'pulse_premium');
      // Default tier is Premium (index 1): only Premium is filled.
      expect(tierFill(tester, 'Premium'), accent);
      expect(tierFill(tester, 'Basic'), transparent);
      expect(tierFill(tester, 'Premium+'), transparent);

      // Tap Premium+ → the fill moves to Premium+.
      await _tapText(tester, 'Premium+');
      expect(tierFill(tester, 'Premium+'), accent);
      expect(tierFill(tester, 'Premium'), transparent);

      // Tap Basic → the fill moves to Basic.
      await _tapText(tester, 'Basic');
      expect(tierFill(tester, 'Basic'), accent);
      expect(tierFill(tester, 'Premium+'), transparent);
    });

    testWidgets('the tier + period both re-target the CTA', (tester) async {
      final events = await _pumpInteractivePaywall(tester, 'pulse_premium');
      // Default: the Premium tier (index 1) + Monthly.
      await _tapText(tester, 'Subscribe & pay');
      expect(
        _lastPurchasedProductId(events),
        'com.restage.tier.premium.monthly',
      );

      // The period cards re-target within the tier.
      await _tapPlanRow(tester, 'Annual');
      await _tapText(tester, 'Subscribe & pay');
      expect(
        _lastPurchasedProductId(events),
        'com.restage.tier.premium.annual',
      );

      // The tier strip re-targets too (period stays Annual).
      await _tapText(tester, 'Basic');
      await _tapText(tester, 'Subscribe & pay');
      expect(
        _lastPurchasedProductId(events),
        'com.restage.tier.basic.annual',
      );

      await _tapText(tester, 'Premium+');
      await _tapText(tester, 'Subscribe & pay');
      expect(
        _lastPurchasedProductId(events),
        'com.restage.tier.premiumplus.annual',
      );
    });

    testWidgets('the tier strip drives the feature list', (tester) async {
      await _pumpInteractivePaywall(tester, 'pulse_premium');

      // A core feature shows at every tier; a mid-tier feature is hidden on the
      // entry tier; a top-tier-only feature shows only on the top tier — so
      // selecting a tier visibly changes the list.
      await _tapText(tester, 'Basic');
      expect(find.text('Verified badge'), findsOneWidget);
      expect(find.text('Edit window'), findsNothing);
      expect(find.text('Bookmark folders'), findsNothing);

      await _tapText(tester, 'Premium');
      expect(find.text('Edit window'), findsOneWidget);
      expect(find.text('Bookmark folders'), findsNothing);

      await _tapText(tester, 'Premium+');
      expect(find.text('Edit window'), findsOneWidget);
      expect(find.text('Bookmark folders'), findsOneWidget);
    });
  });

  group('delivered-blob CTA full-width (regression: double.infinity → hug)',
      () {
    // A full-width CTA must keep its full width in the DELIVERED blob, not only
    // the local widget mount. `SizedBox(width: double.infinity)` does not
    // survive lowering — the transpiler folds the non-finite double to null, so
    // the button hugs its content once decoded. These templates instead use a
    // transpilable full-width pattern (a stretched column child), and this test
    // pins the rendered CTA at the full content width on the decoded path,
    // where the regression actually shows.
    //
    // The default 800x600 test surface (same as the round-trip tests above):
    // its content column is 744 wide (800 minus the 28+28 scroll padding), and
    // each CTA's label width sits well below that — so a full-width CTA reads as
    // ~744 while a hugging one stays flat at its label width. The gap is the
    // test. (A *narrower* surface would clamp a hugging CTA to the column and
    // make it look full-width — exactly how this regression hid from the
    // geometry-agnostic matrix tests.)
    const contentWidth = 744.0;

    Future<double> ctaWidth(
      WidgetTester tester, {
      required String id,
      required Finder cta,
    }) async {
      _useTallSurface(tester);
      final failures = <PaywallLoadFailed>[];
      await tester.pumpWidget(MaterialApp(
        theme: _exampleTheme(Brightness.light),
        home: Scaffold(
          body: RestagePaywall(
            id: id,
            resolver: _StaticResolver(_encodePaywall(id)),
            priceQueries: kStubPriceQueries,
            onEvent: (e) {
              if (e is PaywallLoadFailed) failures.add(e);
            },
          ),
        ),
      ));
      await tester.pumpAndSettle();
      // If the CTA has regressed to hugging its content, the now-too-narrow
      // button overflows its own label under the wide test-only Ahem font.
      // Clear that benign layout exception so the failure surfaces as the width
      // assertion below (the real signal) rather than a generic test-framework
      // error. With the fix in place there is no overflow and this is a no-op.
      tester.takeException();
      expect(failures, isEmpty, reason: '$id blob failed to load');
      expect(cta, findsOneWidget, reason: '$id CTA not found');
      return tester.getSize(cta).width;
    }

    testWidgets('pulse_premium primary CTA spans the full content width',
        (tester) async {
      // pulse_premium's CTA is a styled Container wrapped by a GestureDetector
      // (so the gesture, not a FilledButton, owns the tap). It spans full-width
      // because the surrounding Column uses `crossAxisAlignment: stretch`;
      // measure that gesture wrapper.
      final width = await ctaWidth(
        tester,
        id: 'pulse_premium',
        cta: find.ancestor(
          of: find.text('Subscribe & pay'),
          matching: find.byType(GestureDetector),
        ),
      );
      expect(width, greaterThan(contentWidth - 2));
    });

    testWidgets('fluent_pro primary CTA spans the full content width',
        (tester) async {
      // fluent_pro's CTA is a styled Container wrapped by a GestureDetector,
      // full-width via the surrounding Column's `crossAxisAlignment: stretch`.
      final width = await ctaWidth(
        tester,
        id: 'fluent_pro',
        cta: find.ancestor(
          of: find.text('START MY FREE WEEK'),
          matching: find.byType(GestureDetector),
        ),
      );
      expect(width, greaterThan(contentWidth - 2));
    });
  });

  group('delivered-blob host feedback (affordance audit)', () {
    // The gallery's delivered-paywall host wires onEvent to
    // showDemoPaywallEventFeedback, so a tap on Restore (which fires a host
    // event, not in-blob behavior) has a visible result instead of silently
    // doing nothing. This pins that wiring end-to-end: tapping the pulse_premium
    // blob's Restore affordance surfaces its feedback SnackBar — proving the
    // delivered-blob → host event → SnackBar path.
    Future<void> pumpPulseWithFeedback(WidgetTester tester) async {
      _useTallSurface(tester);
      final bytes = _encodePaywall('pulse_premium');
      await tester.pumpWidget(
        MaterialApp(
          theme: _exampleTheme(Brightness.light),
          home: Builder(
            builder: (context) => RestagePaywall(
              id: 'pulse_premium',
              resolver: _StaticResolver(bytes),
              priceQueries: kStubPriceQueries,
              onEvent: (event) => showDemoPaywallEventFeedback(context, event),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('tapping Restore surfaces a feedback SnackBar', (tester) async {
      await pumpPulseWithFeedback(tester);

      await tester.ensureVisible(find.text('Restore'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore'));
      await tester.pump(); // start the SnackBar animation
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Restore requested'), findsOneWidget);
    });
  });

  group('delivered-blob load failure (errorBuilder fallback)', () {
    // The gallery's delivered-paywall host gives RestagePaywall an errorBuilder
    // that paints a plain "unavailable" surface (not a blank/crashed screen)
    // when the blob can't be resolved or decoded. This pins that contract: a
    // resolver that fails paints the SAME fallback string the gallery uses, the
    // normal heading never appears, and — because a load failure surfaces
    // through errorBuilder, not the SnackBar host-feedback channel — no feedback
    // SnackBar is shown for the failure.
    const fallbackText = 'This paywall is unavailable right now.';

    testWidgets('a failing resolver paints the fallback, not a heading',
        (tester) async {
      final failures = <PaywallLoadFailed>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: _exampleTheme(Brightness.light),
          home: Builder(
            builder: (context) => RestagePaywall(
              // pulse_premium's heading is the negative control: it must NOT
              // appear.
              id: 'pulse_premium',
              resolver: const _FailingResolver(),
              priceQueries: kStubPriceQueries,
              // Same wiring as the gallery host: feedback SnackBars for taps,
              // load failures handled by errorBuilder below — never a SnackBar.
              onEvent: (event) {
                if (event is PaywallLoadFailed) failures.add(event);
                showDemoPaywallEventFeedback(context, event);
              },
              errorBuilder: (context, error) => Scaffold(
                appBar: AppBar(),
                body: Center(child: Text(fallbackText)),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The load failure painted the fallback rather than a blank/crashed
      // screen, and the real paywall heading never rendered.
      expect(find.text(fallbackText), findsOneWidget);
      expect(find.text('Pulse'), findsNothing);

      // The failure did flow through PaywallLoadFailed (errorBuilder is driven
      // by the same error), but it surfaces ONLY through errorBuilder — the
      // SnackBar host-feedback channel stays silent for a load failure.
      expect(failures, isNotEmpty,
          reason: 'expected a PaywallLoadFailed event');
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  test('gallery app constructs without throwing', () {
    expect(RestageExampleApp.new, returnsNormally);
  });

  group('gallery navigation (back affordance)', () {
    testWidgets(
        'tapping a tile mounts the example under a back button, and '
        'the back button returns to the gallery menu', (tester) async {
      _useTallSurface(tester);
      await tester.pumpWidget(const RestageExampleApp());
      await tester.pumpAndSettle();

      // The gallery menu is showing and the back affordance is not.
      expect(find.text('Restage SDK Examples'), findsOneWidget);
      expect(find.byType(ExampleViewer), findsNothing);
      expect(find.byTooltip('Back to examples'), findsNothing);

      // Open a closeless full-bleed surface — one that has no own close
      // affordance, so it keeps the host back button as its only escape. The
      // "Hello" demo blob is exactly that surface (the only tile with the host
      // escape button enabled).
      await tester.tap(find.text('Hello'));
      await tester.pumpAndSettle();

      // The example mounts full-screen under the back affordance, and the
      // gallery menu is no longer the active (on-stage) route.
      expect(find.byType(ExampleViewer), findsOneWidget);
      expect(find.byTooltip('Back to examples'), findsOneWidget);
      expect(find.text('Restage SDK Examples'), findsNothing);

      // The back button returns to the gallery menu.
      await tester.tap(find.byTooltip('Back to examples'));
      await tester.pumpAndSettle();

      expect(find.text('Restage SDK Examples'), findsOneWidget);
      expect(find.byType(ExampleViewer), findsNothing);
      expect(find.byTooltip('Back to examples'), findsNothing);
    });
  });

  group('ExampleViewer publishes a readable per-surface status-bar style', () {
    // Each full-screen example is pushed under ExampleViewer with no app bar,
    // so ExampleViewer declares the status-bar style itself — keyed to the
    // *surface's* background brightness, which may not track the app theme.
    // (Flutter's overlay-style naming is inverted: `.light` = light icons for a
    // dark surface; `.dark` = dark icons for a light surface.) The bar itself
    // is not widget-testable; this asserts the published style, reading the
    // region ExampleViewer wraps the surface in.
    SystemUiOverlayStyle viewerStyle(WidgetTester tester) {
      final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.descendant(
          of: find.byType(ExampleViewer),
          matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
        ),
      );
      return region.value;
    }

    testWidgets(
        'a fixed-dark surface gets light icons even under a light app theme',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
          home: const ExampleViewer(
            surfaceBrightness: Brightness.dark,
            child: ColoredBox(color: Color(0xFF0F0820)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Dark surface → light icons, regardless of the light app theme.
      expect(viewerStyle(tester).statusBarIconBrightness, Brightness.light);
    });

    testWidgets('a null surface brightness follows the app theme',
        (tester) async {
      // Light app theme → dark icons.
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
          home: const ExampleViewer(child: SizedBox()),
        ),
      );
      await tester.pumpAndSettle();
      expect(viewerStyle(tester).statusBarIconBrightness, Brightness.dark);

      // Dark app theme → light icons.
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            colorSchemeSeed: Colors.indigo,
            brightness: Brightness.dark,
          ),
          home: const ExampleViewer(child: SizedBox()),
        ),
      );
      await tester.pumpAndSettle();
      expect(viewerStyle(tester).statusBarIconBrightness, Brightness.light);
    });

    testWidgets('a fixed-light surface gets dark icons even under a dark theme',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            colorSchemeSeed: Colors.indigo,
            brightness: Brightness.dark,
          ),
          home: const ExampleViewer(
            surfaceBrightness: Brightness.light,
            child: ColoredBox(color: Color(0xFFFFFFFF)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(viewerStyle(tester).statusBarIconBrightness, Brightness.dark);
    });
  });

  // ascend_premium opens its plan selection inside a modal sheet (the lowered
  // showModalBottomSheet), so the standard plan-selection group (which expects
  // visible plan rows) does not apply. This drives the three modal states on the
  // DELIVERED blob and asserts the purchase re-targets — the same modal-sheet
  // mechanics the trial-timeline template pins, proven on the delivered blob.
  group('modal plan sheet — ascend_premium', () {
    testWidgets(
        'footer opens the sheet, See All Plans swaps content, plan selection '
        're-targets the CTA', (tester) async {
      final events = await _pumpInteractivePaywall(tester, 'ascend_premium');

      // State 1 — sheet closed: the sheet content is not in the tree yet.
      expect(find.text('Free 30-Day Trial'), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);

      // State 2 — tap the footer "Start free trial" to open the modal sheet.
      // Sheet closed, so the footer is the only "Start free trial".
      await _tapText(tester, 'Start free trial');
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('Free 30-Day Trial'), findsOneWidget);
      expect(find.text('See All Plans'), findsOneWidget);
      expect(find.text('Monthly'), findsNothing);

      // The collapsed CTA (inside the sheet) buys the default (annual) plan.
      await _tapSheetText(tester, 'Start free trial');
      expect(_lastPurchasedProductId(events), 'com.restage.pro.annual');

      // State 3 — See All Plans swaps the content in place: the plan list
      // appears and the See-All-Plans button is removed.
      await _tapSheetText(tester, 'See All Plans');
      expect(find.text('Monthly'), findsOneWidget);
      expect(find.text('See All Plans'), findsNothing);

      // Selecting Monthly re-targets the sheet CTA.
      await _tapPlanRow(tester, 'Monthly');
      await _tapSheetText(tester, 'Start free trial');
      expect(_lastPurchasedProductId(events), 'com.restage.pro.monthly');
    });
  });
}
