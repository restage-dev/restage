import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/stub_products.dart';

/// End-to-end proof that the Fluent Pro paywall, authored with a
/// `Navigator.push` from its "VIEW ALL PLANS" control to the second
/// `@PaywallSource` "Choose a plan" screen, lowers to a flow at build time and
/// hosts through the bundled delivery path.
///
/// This drives the REAL committed bundled assets
/// (`assets/paywalls/fluent_pro.flow.json` + the two
/// `assets/onboarding/screens/paywall_fluent_pro*.rfw` blobs) through the
/// production present path — `RestagePaywall(id:)` + the default
/// `AssetVariantResolver` flow arm — exactly as a shipped app would.
///
/// The "Choose a plan" screen is **select-then-subscribe** (faithful to the
/// entry): tapping a tier SELECTS it (the check moves; no charge), and the
/// pinned "START MY FREE WEEK" CTA charges the SELECTED tier's distinct slot.
/// The tests pin both the visible selection (the moved check) and the CTA
/// re-target — never per-tier purchase firing.
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 3600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Finds an [Icon] by its glyph codepoint. The rendered IconData carries the
/// right glyph but not the source `IconData` identity (directional icons also
/// drop their `matchTextDirection` flag), so a strict `byIcon()` equality would
/// miss it.
Finder _iconByCodePoint(IconData icon) => find.byWidgetPredicate(
      (widget) => widget is Icon && widget.icon?.codePoint == icon.codePoint,
    );

/// The single selection check on the choose-a-plan screen.
final Finder _selectionCheck = _iconByCodePoint(Icons.check_rounded);

/// Asserts that exactly one selection check is visible and that it sits on the
/// `selectedLabel` tier — i.e. its vertical centre is nearer that tier's title
/// than any other tier's title. The four tier cards are stacked far enough apart
/// (badge/ribbon rows + gaps) that nearest-title unambiguously identifies the
/// card the top-right check belongs to.
void _expectCheckOnTier(
  WidgetTester tester,
  String selectedLabel,
  List<String> allLabels,
) {
  expect(_selectionCheck, findsOneWidget);
  final checkY = tester.getRect(_selectionCheck).center.dy;
  var nearest = allLabels.first;
  var best = double.infinity;
  for (final label in allLabels) {
    final distance =
        (tester.getRect(find.text(label)).center.dy - checkY).abs();
    if (distance < best) {
      best = distance;
      nearest = label;
    }
  }
  expect(
    nearest,
    selectedLabel,
    reason: 'the selection check should sit on the "$selectedLabel" card',
  );
}

void main() {
  late List<RestageEvent> events;

  setUp(() {
    events = <RestageEvent>[];
    Restage.debugReset();
    Restage.configure(
      apiKey: 'rs_pk_test',
      products: kStubProducts,
      resolver: const AssetVariantResolver(),
    );
  });

  // Mounts the paywall and lets the asynchronous bundled-flow load complete
  // before settling. A bare `pumpAndSettle()` immediately after `pumpWidget`
  // races the asset-bundle load under the test binding's fake-async clock; a
  // priming pump lets the load + first render land, then we settle.
  Future<void> mount(WidgetTester tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: RestagePaywall(
          id: 'fluent_pro',
          priceQueries: kStubPriceQueries,
          onEvent: events.add,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  }

  // Navigates the lowered flow from the entry to the pushed choose-a-plan screen.
  Future<void> openChoosePlan(WidgetTester tester) async {
    await mount(tester);
    await tester.tap(find.text('VIEW ALL PLANS'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a plan'), findsOneWidget);
  }

  const tierLabels = <String>[
    'Family Plan',
    'Personal',
    'Student Plan',
    'Monthly',
  ];

  testWidgets(
    'the lowered paywall hosts the bundled flow: entry -> view all plans -> '
    'choose a plan -> back -> entry',
    (tester) async {
      await mount(tester);

      // Entry screen rendered through the flow.
      expect(find.text('VIEW ALL PLANS'), findsOneWidget);
      expect(find.text('START MY FREE WEEK'), findsOneWidget);

      // Push -> the pushed "Choose a plan" screen (the restageNav0 transition).
      await tester.tap(find.text('VIEW ALL PLANS'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a plan'), findsOneWidget);
      expect(find.text('VIEW ALL PLANS'), findsNothing);

      // The authored back chevron is the sole back affordance (the built-in
      // flow chrome is suppressed for a paywall flow) -> in-flow back to entry.
      final backChevron = _iconByCodePoint(Icons.arrow_back_ios_new);
      await tester.tap(backChevron);
      await tester.pumpAndSettle();
      expect(find.text('VIEW ALL PLANS'), findsOneWidget);
      expect(find.text('Choose a plan'), findsNothing);
    },
  );

  testWidgets(
    'the choose-a-plan screen defaults to Personal selected and the CTA '
    'charges the annual product',
    (tester) async {
      await openChoosePlan(tester);

      // Default selection is the MOST POPULAR Personal tier — its check shows
      // and no purchase has fired yet (a tier is selected, never charged).
      _expectCheckOnTier(tester, 'Personal', tierLabels);
      expect(events.whereType<PurchaseInitiated>(), isEmpty);

      // The CTA charges the selected (default Personal -> annual) slot.
      await tester.tap(find.text('START MY FREE WEEK'));
      await tester.pumpAndSettle();

      final initiated = events.whereType<PurchaseInitiated>().toList();
      expect(initiated, hasLength(1));
      expect(initiated.single.productId, 'com.restage.pro.annual');
      expect(initiated.single.paywallId, 'fluent_pro');
    },
  );

  // Tapping a tier SELECTS it (the check moves; no charge); the CTA then charges
  // that tier's distinct slot. One CTA charge per fresh mount: a real purchase
  // dispatches an unawaited billing future, so the proof drives one charge per
  // mount, which is the load-bearing assertion.
  const movableTiers = <({String label, String slot, String productId})>[
    (label: 'Family Plan', slot: 'family', productId: 'com.restage.pro.family'),
    (
      label: 'Student Plan',
      slot: 'student',
      productId: 'com.restage.pro.student'
    ),
    (label: 'Monthly', slot: 'monthly', productId: 'com.restage.pro.monthly'),
  ];
  for (final tier in movableTiers) {
    testWidgets(
      'tapping "${tier.label}" selects it (the check moves, no charge) and the '
      'CTA then charges ${tier.productId}',
      (tester) async {
        await openChoosePlan(tester);

        // Tap the tier -> it SELECTS (no purchase fires).
        await tester.tap(find.text(tier.label));
        await tester.pumpAndSettle();
        expect(
          events.whereType<PurchaseInitiated>(),
          isEmpty,
          reason: 'tapping a tier selects it; it must not charge',
        );
        _expectCheckOnTier(tester, tier.label, tierLabels);

        // The CTA charges the now-selected tier's product, keyed on the served
        // paywall (not the onboarding flowId) — the adapter contract.
        await tester.tap(find.text('START MY FREE WEEK'));
        await tester.pumpAndSettle();

        final initiated = events.whereType<PurchaseInitiated>().toList();
        expect(initiated, hasLength(1));
        expect(initiated.single.productId, tier.productId);
        expect(initiated.single.paywallId, 'fluent_pro');

        // Charging did not advance the flow — still on the pushed screen.
        expect(find.text('Choose a plan'), findsOneWidget);
      },
    );
  }

  testWidgets(
      'the entry skip affordance (the back arrow) dismisses the paywall',
      (tester) async {
    await mount(tester);

    // The entry's top-left back arrow is the flow's skip terminator.
    final entryBack = _iconByCodePoint(Icons.arrow_back_rounded);
    await tester.tap(entryBack);
    await tester.pumpAndSettle();

    final dismissed = events.whereType<PaywallDismissed>().toList();
    expect(dismissed, isNotEmpty);
    expect(dismissed.last.reason, DismissReason.userClose);
  });
}
