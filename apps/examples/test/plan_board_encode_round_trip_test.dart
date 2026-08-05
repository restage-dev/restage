import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/main_plan_board_demo.dart' as demo;
import 'package:restage_example/user_factories.g.dart';
import 'package:restage_example/widgets/plan_board.dart';
import 'package:restage_example/widgets/pricing_card.dart' show PlanTier;

/// The MAP ENCODE-SIDE SOUND NET (source → encode → wire → decode → pixels).
///
/// The `plan_board_showcase` screen AUTHORS map literals in ordinary Flutter
/// (`lib/onboarding/screens/plan_board_showcase.dart`). Build-time codegen
/// ENCODES each map into the committed blob as an ordered list of `key`/`value`
/// entry objects. Both key sets are deliberately authored out of canonical
/// order — the string keys are not alphabetical, and the enum keys are in
/// neither declaration order nor its reverse — so a canonicalising regression
/// fails here instead of passing by coincidence. This test loads the COMMITTED
/// `.rfw` binary — the exact artifact that ships — renders it through the REAL
/// RFW runtime and generated `PlanBoard` factory (not a mock), and asserts each
/// reconstructed key, value and runtime type.
///
/// Together with `plan_board_decode_golden_test.dart`, which pins the decode
/// half against hand-authored wire entry lists, this closes the round trip for
/// map-shaped properties.
void main() {
  setUp(() {
    Restage.debugReset();
    registerRestageCustomerWidgets();
    Restage.configure(
      apiKey: 'rs_pk_test',
      resolver: const AssetVariantResolver(),
    );
  });

  PlanBoard renderedBoard(WidgetTester tester) =>
      tester.widget<PlanBoard>(find.byType(PlanBoard));

  testWidgets(
    'the built plan_board_showcase blob round-trips every authored map entry '
    'through the real generated factory',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const MaterialApp(home: demo.PlanBoardDemo()));
      await tester.pumpAndSettle();

      final board = renderedBoard(tester);

      // The authored order survives the wire, and nothing else arrives with
      // it. An exact key list is both the positive and its own absence
      // assertion: an extra entry, a dropped entry or a canonicalised order
      // all fail it.
      expect(board.plans.keys.toList(), ['team', 'pro', 'starter']);
      expect(board.plans, hasLength(3));

      expect(board.plans['team']!.name, 'Team');
      expect(board.plans['team']!.name.runtimeType, String);
      expect(board.plans['team']!.price.amount, 4900);
      expect(board.plans['team']!.price.amount.runtimeType, int);
      expect(board.plans['team']!.price.currency, 'USD');
      expect(board.plans['team']!.badge, 'Most seats');
      expect(board.plans['team']!.tier, PlanTier.team);
      expect(board.plans['team']!.tier.runtimeType, PlanTier);

      expect(board.plans['pro']!.name, 'Pro');
      expect(board.plans['pro']!.price.amount, 1900);
      expect(board.plans['pro']!.tier, PlanTier.pro);
      // Authored without a badge: the omitted optional stays absent rather
      // than arriving as an empty string or a neighbour's value.
      expect(board.plans['pro']!.badge, isNull);

      expect(board.plans['starter']!.name, 'Starter');
      expect(board.plans['starter']!.price.amount, 0);
      // A non-default currency rides the wire; the tier was omitted and takes
      // the data class's own default.
      expect(board.plans['starter']!.price.currency, 'EUR');
      expect(board.plans['starter']!.badge, isNull);
      expect(board.plans['starter']!.tier, PlanTier.starter);

      // The enum-keyed map reconstructs to real enum keys, in the authored
      // order — which is neither PlanTier's declaration order nor its reverse,
      // so enumerating the enum's constants could not produce this list.
      expect(board.highlights.keys.toList(), [PlanTier.team, PlanTier.starter]);
      expect(board.highlights, hasLength(2));
      expect(board.highlights.keys.first.runtimeType, PlanTier);

      expect(board.highlights[PlanTier.team]!.name, 'Team');
      expect(board.highlights[PlanTier.team]!.price.amount, 4900);
      expect(board.highlights[PlanTier.starter]!.name, 'Starter');
      expect(board.highlights[PlanTier.starter]!.price.currency, 'EUR');
      // The tier the author never highlighted is absent, not defaulted in.
      expect(board.highlights.containsKey(PlanTier.pro), isFalse);
    },
  );

  testWidgets(
    'the demo entrypoint itself runs and paints the reconstructed maps',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // The test above pumps the demo's WIDGET with configuration this file
      // supplies. This one calls the entrypoint's own `main()`, so its
      // registration and configuration are the ones under test — a demo that
      // renders only because a test configured it for it would pass the test
      // above and fail on a device.
      Restage.debugReset();
      // Establish the binding's frame clock before `runApp`. Calling the
      // entrypoint into a binding that has never pumped starts the loading
      // indicator's ticker against a zero baseline.
      await tester.pumpWidget(const SizedBox.shrink());
      demo.main();
      await tester.pumpAndSettle();

      expect(find.byType(PlanBoard), findsOneWidget);
      final board = tester.widget<PlanBoard>(find.byType(PlanBoard));
      expect(board.plans.keys.toList(), ['team', 'pro', 'starter']);
      expect(board.highlights.keys.toList(), [PlanTier.team, PlanTier.starter]);

      // The maps reach real pixels, not just the widget's fields: each string
      // key and each enum key is painted by the board's own build method.
      expect(find.text('team — Team'), findsOneWidget);
      expect(find.text('starter — Starter'), findsOneWidget);
      expect(find.text('Best in team: Team'), findsOneWidget);
      expect(find.text('Best in starter: Starter'), findsOneWidget);
      // The tier that was never highlighted paints nowhere.
      expect(find.text('Best in pro: Pro'), findsNothing);
    },
  );
}
