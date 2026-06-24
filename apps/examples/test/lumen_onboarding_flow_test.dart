import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/onboarding/lumen_onboarding_demo.dart';
import 'package:restage_example/stub_products.dart';
import 'package:restage_example/user_factories.g.dart';

/// The flow ends on a fit-to-display (bounded) paywall; give the test a tall
/// canvas so it renders without a false RenderFlex overflow under the wide Ahem
/// test font.
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUp(() {
    Restage.debugReset();
    Restage.configure(
      apiKey: 'rs_pk_test',
      products: kStubProducts,
      resolver: const AssetVariantResolver(),
    );
    registerRestageCustomerWidgets();
  });

  testWidgets(
      'drives welcome → questions → reminder gate (granted) → recap → paywall '
      '→ purchase completes the flow', (tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(const MaterialApp(home: LumenOnboardingDemo()));
    await tester.pumpAndSettle();

    // Welcome → experience question.
    expect(find.text('Welcome to Lumen'), findsOneWidget);
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    // Experience question → goal question (any option advances; the flow is
    // linear by design).
    expect(find.text('How much have you meditated?'), findsOneWidget);
    await tester.tap(find.text("I'm new to meditation"));
    await tester.pumpAndSettle();

    // Goal question → reminder priming.
    expect(find.text('What brings you here?'), findsOneWidget);
    await tester.tap(find.text('Sleep better'));
    await tester.pumpAndSettle();

    // The reminder host-action gate: the demo grants, so the flow advances to
    // the recap (the one conditional branch in the flow).
    expect(find.text('Stay on track'), findsOneWidget);
    await tester.tap(find.text('Enable daily reminders'));
    await tester.pumpAndSettle();

    // Recap → the embedded meditation paywall step.
    expect(find.text("You're all set"), findsOneWidget);
    await tester.tap(find.text('See your plan'));
    await tester.pumpAndSettle();

    // The paywall step: the purchase ends the flow.
    expect(find.text('Unlock Lumen Plus'), findsOneWidget,
        reason: _seen(tester));
    await tester.tap(find.text('Start free trial'));
    await tester.pumpAndSettle();

    expect(find.text('Subscription started'), findsOneWidget);
  });

  testWidgets('the reminder gate holds when the host action is declined',
      (tester) async {
    // With a declined decision the flow stays on the priming screen — the
    // gate's advance-or-stay semantics (it never proceeds on behaviour it did
    // not get).
    _useTallSurface(tester);
    await tester.pumpWidget(
      const MaterialApp(home: LumenOnboardingDemo(grantReminders: false)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    await tester.tap(find.text("I'm new to meditation"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sleep better'));
    await tester.pumpAndSettle();

    expect(find.text('Stay on track'), findsOneWidget);
    await tester.tap(find.text('Enable daily reminders'));
    await tester.pumpAndSettle();

    // Declined: the flow holds on the reminder screen, never reaching the recap.
    expect(find.text('Stay on track'), findsOneWidget);
    expect(find.text("You're all set"), findsNothing);
  });

  testWidgets(
      'a failed purchase does NOT complete the flow (no bare-tap claim)',
      (tester) async {
    // The honest money-path: the embedded paywall's purchase routes through the
    // billing gateway, and the flow completes ONLY on a successful outcome. A
    // failing gateway must leave the user on the paywall — never "Subscription
    // started" on a tap that did not purchase.
    _useTallSurface(tester);
    await tester.pumpWidget(
      const MaterialApp(
        home: LumenOnboardingDemo(billingGateway: _FailingGateway()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    await tester.tap(find.text("I'm new to meditation"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sleep better'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enable daily reminders'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('See your plan'));
    await tester.pumpAndSettle();

    expect(find.text('Unlock Lumen Plus'), findsOneWidget);
    await tester.tap(find.text('Start free trial'));
    await tester.pumpAndSettle();

    expect(find.text('Subscription started'), findsNothing,
        reason: 'a failed purchase must NOT complete the flow');
    expect(find.text('Unlock Lumen Plus'), findsOneWidget,
        reason: 'the user stays on the paywall after a failed purchase');
  });
}

/// A billing gateway that always fails — to prove the flow does not complete on
/// a purchase that did not succeed.
class _FailingGateway implements BillingGateway {
  const _FailingGateway();

  @override
  Future<PurchaseOutcome> purchase(String productId,
      {String? basePlanId}) async {
    return PurchaseOutcome.failed(
      productId: productId,
      errorCode: 'test_declined',
      message: 'Declined under flutter_test.',
    );
  }

  @override
  Future<RestoreOutcome> restore() async => RestoreOutcome.noPurchases();
}

String _seen(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((widget) => widget.data ?? widget.textSpan?.toPlainText())
    .whereType<String>()
    .join(' | ');
