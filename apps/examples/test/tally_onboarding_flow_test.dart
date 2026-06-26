import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/onboarding/tally_onboarding_demo.dart';

/// Tall canvas so the full-screen onboarding renders without a false
/// RenderFlex overflow under the wide Ahem test font.
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

// The per-goal labels, keyed by the captured `goal` flow-state value. The fork
// routes each goal to its tailored SETUP screen; the decision routes the same
// goal to its tailored RECAP. Keeping these in tables lets the "other arms are
// absent" negatives be derived rather than hand-listed (a relabel touches one
// place).
const _goalCta = {
  'debt': 'Pay off debt',
  'savings': 'Build savings',
  'invest': 'Start investing',
};
const _setup = {
  'debt': 'Your payoff plan',
  'savings': 'Your savings plan',
  'invest': 'Your starter portfolio',
};
const _recap = {
  'debt': 'Your payoff plan\nis ready',
  'savings': 'Auto-save is\nready to go',
  'invest': 'Your portfolio\nis ready',
};
const _finalCta = {
  'debt': 'Make my first payment',
  'savings': 'Turn on auto-save',
  'invest': 'Fund my account',
};

void main() {
  setUp(() {
    Restage.debugReset();
    Restage.configure(
      apiKey: 'rs_pk_test',
      resolver: const AssetVariantResolver(),
    );
  });

  // Pumps the onboarding and advances welcome → the goal fork.
  Future<void> toGoalFork(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: TallyOnboardingDemo()));
    await tester.pumpAndSettle();
    expect(find.text('Get started'), findsOneWidget);
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(find.text('What are you\nworking toward?'), findsOneWidget,
        reason: 'the goal fork screen must render');
  }

  // Drives one branch arm end to end and asserts it routes correctly: the fork
  // reaches THIS goal's setup (and not the others), the decision routes to THIS
  // goal's recap (and not the others — the branch must be REAL, not a shared
  // screen), and the recap's goal-specific CTA completes the flow.
  Future<void> driveGoalArm(WidgetTester tester, String goal) async {
    _useTallSurface(tester);
    await toGoalFork(tester);

    await tester.tap(find.text(_goalCta[goal]!));
    await tester.pumpAndSettle();
    expect(find.text(_setup[goal]!), findsOneWidget);
    for (final other in _setup.keys.where((g) => g != goal)) {
      expect(find.text(_setup[other]!), findsNothing);
    }

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text(_recap[goal]!), findsOneWidget);
    for (final other in _recap.keys.where((g) => g != goal)) {
      expect(find.text(_recap[other]!), findsNothing);
    }

    await tester.tap(find.text(_finalCta[goal]!));
    await tester.pumpAndSettle();
    expect(find.text("You're all set"), findsOneWidget);
  }

  testWidgets('the debt goal forks to the debt setup → the debt recap',
      (tester) => driveGoalArm(tester, 'debt'));

  testWidgets('the savings goal forks to the savings setup → the savings recap',
      (tester) => driveGoalArm(tester, 'savings'));

  testWidgets(
      'the investing goal forks to the investing setup → the investing recap '
      '(the decision default)',
      (tester) => driveGoalArm(tester, 'invest'));
}
