import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/onboarding/stride_first_run_demo.dart';

/// Give the test a tall canvas so the full-screen surfaces render without a
/// false RenderFlex overflow under the wide Ahem test font.
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
  });

  testWidgets(
      'the reminder gate grants → ready → completes with the untyped result',
      (tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(const MaterialApp(home: StrideFirstRunDemo()));
    await tester.pumpAndSettle();

    // Welcome.
    expect(find.text('Welcome to Stride'), findsOneWidget);
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    // Goals (the screen added in v2).
    expect(find.text('Set your pace'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // The reminder prime (the host-action gate screen).
    expect(find.text('Never miss a run'), findsOneWidget);
    await tester.tap(find.text('Turn on reminders'));
    await tester.pumpAndSettle();

    // Granted → the ready screen (the gate advanced on a granted result).
    expect(find.text('You\'re all set'), findsOneWidget);
    await tester.tap(find.text('Start running'));
    await tester.pumpAndSettle();

    // Completed → entered the app, and the host READ the untyped Map: the
    // "Onboarding complete" line renders only when the host observed
    // `result['completed'] == true` in the outbound-filtered result. This is
    // the host-boundary assertion — a regression that fires completion with
    // an empty or wrong map goes RED here.
    expect(find.text('Today\'s run'), findsOneWidget);
    expect(find.text('Onboarding complete'), findsOneWidget);
  });

  testWidgets('the reminder gate holds when the OS permission is declined',
      (tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(
      const MaterialApp(home: StrideFirstRunDemo(grantReminders: false)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Never miss a run'), findsOneWidget);
    await tester.tap(find.text('Turn on reminders'));
    await tester.pumpAndSettle();

    // Declined: the flow holds on the prime, never reaching the ready screen.
    expect(find.text('Never miss a run'), findsOneWidget);
    expect(find.text('You\'re all set'), findsNothing);
  });

  testWidgets('"Maybe later" carries the user into the app without the grant',
      (tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(const MaterialApp(home: StrideFirstRunDemo()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Never miss a run'), findsOneWidget);
    await tester.tap(find.text('Maybe later'));
    await tester.pumpAndSettle();

    // The host handled the `skip` custom event → entered the app without the
    // grant, never reaching the ready screen — and WITHOUT the completion
    // marker (no terminal result was delivered), which attributes this
    // hand-off to the custom event, not to onComplete.
    expect(find.text('Today\'s run'), findsOneWidget);
    expect(find.text('You\'re all set'), findsNothing);
    expect(find.text('Onboarding complete'), findsNothing);
  });

  testWidgets('declined, then "Maybe later" — the recovery path off the hold',
      (tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(
      const MaterialApp(home: StrideFirstRunDemo(grantReminders: false)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // Declined → held on the prime.
    await tester.tap(find.text('Turn on reminders'));
    await tester.pumpAndSettle();
    expect(find.text('Never miss a run'), findsOneWidget);

    // The hold is never a dead end: "Maybe later" still carries the user in.
    await tester.tap(find.text('Maybe later'));
    await tester.pumpAndSettle();
    expect(find.text('Today\'s run'), findsOneWidget);
    expect(find.text('Onboarding complete'), findsNothing);
  });
}
