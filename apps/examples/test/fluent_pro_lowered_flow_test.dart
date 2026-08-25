import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

/// End-to-end proof that the Fluent Pro paywall, authored with a
/// `Navigator.push` from its "VIEW ALL PLANS" control to the second
/// `@Paywall` "Choose a plan" screen, lowers to a flow at build time and
/// hosts through the bundled delivery path.
///
/// This drives the REAL committed bundled assets
/// (`assets/paywalls/fluent_pro.flow.json` + the two
/// `assets/paywalls/screens/paywall_fluent_pro*.rfw` blobs) through the
/// production present path — `RestagePaywall(id:)` + the default
/// `AssetVariantResolver` flow arm — exactly as a shipped app would.
///
/// The "Choose a plan" screen is select-then-continue: tapping a tier selects
/// it, and the pinned "START MY FREE WEEK" CTA reports the selected tier.
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
        home: RestagePaywall(id: 'fluent_pro', onEvent: events.add),
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

  Map<String, Object?>? lastContinueArgs() {
    final actions = events
        .whereType<PaywallCustomEvent>()
        .where((event) => event.eventName == 'continue')
        .map((event) => event.args)
        .toList();
    return actions.isEmpty ? null : actions.last;
  }

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
    'the choose-a-plan screen defaults to Personal selected',
    (tester) async {
      await openChoosePlan(tester);

      // Default selection is the MOST POPULAR Personal tier.
      _expectCheckOnTier(tester, 'Personal', tierLabels);
      expect(lastContinueArgs(), isNull);

      await tester.tap(find.text('START MY FREE WEEK'));
      await tester.pumpAndSettle();
      expect(lastContinueArgs()?['plan'], 'personal');
    },
  );

  const movableTiers = <({String label, String plan})>[
    (label: 'Family Plan', plan: 'family'),
    (label: 'Student Plan', plan: 'student'),
    (label: 'Monthly', plan: 'monthly'),
  ];
  for (final tier in movableTiers) {
    testWidgets(
      'tapping "${tier.label}" selects it and the CTA reports it',
      (tester) async {
        await openChoosePlan(tester);

        await tester.tap(find.text(tier.label));
        await tester.pumpAndSettle();
        expect(lastContinueArgs(), isNull);
        _expectCheckOnTier(tester, tier.label, tierLabels);

        await tester.tap(find.text('START MY FREE WEEK'));
        await tester.pumpAndSettle();
        expect(lastContinueArgs()?['plan'], tier.plan);

        // The action did not advance the flow.
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
