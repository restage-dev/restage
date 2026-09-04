import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/example_viewer.dart';
import 'package:restage_example/main.dart';
import 'package:restage_example/onboarding/minimal_onboarding_demo.dart';
import 'package:restage_example/user_factories.g.dart';

/// The demo pill and the viewer's reserved band are separate switches. A screen
/// that carries an app bar takes no band, and the pill then sits inside the
/// bar's toolbar row rather than stacking a second bar above it.
void main() {
  setUp(() {
    Restage.debugReset();
    Restage.configure(
      apiKey: 'rs_pk_test',
      resolver: const AssetVariantResolver(),
    );
    registerRestageWidgets();
  });

  Future<void> unmountSurface(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets('with no reserved band the pill sits inside the app bar',
      (tester) async {
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: BrightnessScope(
          isDark: false,
          onToggle: () {},
          child: const ExampleViewer(
            child: ThemeToggleScope(child: MinimalOnboardingDemo()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Advance to the screen that carries an app bar.
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    // The toolbar row, not the whole AppBar: the bar's rect includes the top
    // padding, so only the row shows whether the pill shares it.
    final barFinder = find.descendant(
      of: find.byType(AppBar),
      matching: find.byType(NavigationToolbar),
    );
    final pillFinder = find.text('RFW render blob');
    final foundBar = barFinder.evaluate().length;
    final foundPill = pillFinder.evaluate().length;
    Rect? bar;
    Rect? pill;
    if (foundBar == 1 && foundPill == 1) {
      bar = tester.getRect(barFinder);
      pill = tester.getRect(pillFinder);
    }
    await unmountSurface(tester);

    expect(foundBar, 1, reason: 'the second screen carries an app bar');
    expect(foundPill, 1, reason: 'the demo pill is on stage');
    expect(pill!.top, greaterThanOrEqualTo(bar!.top),
        reason: 'the pill starts below the top of the toolbar row');
    expect(pill.bottom, lessThanOrEqualTo(bar.bottom),
        reason: 'the pill ends above the bottom of the toolbar row, sharing '
            'it rather than stacking in a band above it');
  });
}
