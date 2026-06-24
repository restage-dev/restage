import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/onboarding/reel_cancel_demo.dart';

/// Tall canvas so the full-screen survey renders without a false RenderFlex
/// overflow under the wide Ahem test font.
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUp(() {
    Restage.debugReset();
    Restage.configure(
      apiKey: 'rs_pk_test',
      resolver: const AssetVariantResolver(),
    );
  });

  // Drives the two linear questions to the save-offer screen.
  Future<void> toSaveOffer(WidgetTester tester) async {
    expect(find.text('Why are you leaving?'), findsOneWidget);
    await tester.tap(find.text('It’s too expensive'));
    await tester.pumpAndSettle();
    expect(find.text('How often did you watch?'), findsOneWidget);
    await tester.tap(find.text('Almost every day'));
    await tester.pumpAndSettle();
    expect(find.text('Wait — stay for half price'), findsOneWidget);
  }

  testWidgets(
      'questions → save-offer gate (redeemed) → retained confirmation → kept',
      (tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(const MaterialApp(home: ReelCancelDemo()));
    await tester.pumpAndSettle();

    await toSaveOffer(tester);

    // The save-offer host-action gate: the demo redeems, so the flow advances
    // to the retained confirmation (the one conditional branch).
    await tester.tap(find.text('Keep my discount'));
    await tester.pumpAndSettle();
    expect(find.text('Your discount is applied'), findsOneWidget);

    await tester.tap(find.text('Continue watching'));
    await tester.pumpAndSettle();
    expect(find.text('Membership kept'), findsOneWidget);
  });

  testWidgets('the save-offer gate holds when the redemption fails',
      (tester) async {
    // With a failed redemption the flow stays on the save-offer — the gate's
    // advance-or-stay semantics (it never proceeds on a redemption it did not
    // get).
    _useTallSurface(tester);
    await tester.pumpWidget(
      const MaterialApp(home: ReelCancelDemo(redeemOffer: false)),
    );
    await tester.pumpAndSettle();

    await toSaveOffer(tester);
    await tester.tap(find.text('Keep my discount'));
    await tester.pumpAndSettle();

    // Failed redemption: the flow holds on the save-offer, never reaching the
    // confirmation.
    expect(find.text('Wait — stay for half price'), findsOneWidget);
    expect(find.text('Your discount is applied'), findsNothing);
  });

  testWidgets('"No thanks, cancel" confirms the cancellation', (tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(const MaterialApp(home: ReelCancelDemo()));
    await tester.pumpAndSettle();

    await toSaveOffer(tester);
    await tester.tap(find.text('No thanks, cancel my membership'));
    await tester.pumpAndSettle();

    // The host handled the `cancel` custom event → the cancellation is
    // confirmed, never reaching the retained confirmation.
    expect(find.text('Membership cancelled'), findsOneWidget);
    expect(find.text('Your discount is applied'), findsNothing);
  });
}
