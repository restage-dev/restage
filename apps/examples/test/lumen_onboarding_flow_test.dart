import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/onboarding/lumen_onboarding_demo.dart';
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
      resolver: const AssetVariantResolver(),
    );
    registerRestageWidgets();
  });

  testWidgets(
      'drives welcome → questions → reminder gate (granted) → recap → paywall '
      '→ continue completes the flow', (tester) async {
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

    // The paywall step: the continue action ends the flow.
    expect(find.text('Unlock Lumen Plus'), findsOneWidget,
        reason: _seen(tester));
    await tester.tap(find.text('Start free trial'));
    await tester.pumpAndSettle();

    expect(find.text('Onboarding complete'), findsOneWidget);
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
}

String _seen(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((widget) => widget.data ?? widget.textSpan?.toPlainText())
    .whereType<String>()
    .join(' | ');
