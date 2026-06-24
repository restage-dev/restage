import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_example/onboarding/chrome_ladder_demo.dart';
import 'package:restage_example/stub_products.dart';
import 'package:restage_example/user_factories.g.dart';
import 'package:restage/restage.dart';

/// Drives the chrome-customization ladder demo, asserting each rung changes the
/// chrome on REAL behavior (the specific custom icon / position / tappability),
/// never `findsOneWidget` for "an affordance exists". Any assertion that runs
/// while a flow screen (hence a `RuntimeErrorBoundary`) is mounted is captured
/// first and asserted after unmounting, so a failing `expect` can't be masked
/// into a binding hang by the error boundary.
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

  // Mounts the demo on [rung] and advances welcome → value so the flow has
  // history (`canBack` is true) and the back affordance is shown.
  Future<void> pumpAtValue(
    WidgetTester tester,
    ChromeRung rung, {
    bool persistent = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home:
            ChromeLadderDemo(initialRung: rung, initialPersistent: persistent),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'Theme rung renders the custom back icon — specific icon, color, '
      'and size', (tester) async {
    await pumpAtValue(tester, ChromeRung.theme);

    final icon = tester.widget<Icon>(find.byIcon(kChromeLadderThemeIcon));
    final iconData = icon.icon;
    final color = icon.color;
    final size = icon.size;
    await tester.pumpWidget(const SizedBox());

    expect(iconData, kChromeLadderThemeIcon);
    expect(color, kChromeLadderThemeColor);
    expect(size, kChromeLadderThemeSize);
  });

  testWidgets('Slots rung renders the custom back control and it drives back',
      (tester) async {
    await pumpAtValue(tester, ChromeRung.slots);

    final present =
        find.byKey(const Key('chrome-ladder-slots-back')).evaluate().length;
    if (present == 1) {
      await tester.tap(find.byKey(const Key('chrome-ladder-slots-back')));
      await tester.pumpAndSettle();
    }
    final welcomeBack = find.text('Welcome to Aura').evaluate().length;
    await tester.pumpWidget(const SizedBox());

    expect(present, 1, reason: 'the Slots rung shows the custom back control');
    expect(welcomeBack, 1, reason: 'tapping the custom control pops back');
  });

  testWidgets(
      'Layout rung positions the back control on the right and it '
      'drives back', (tester) async {
    await pumpAtValue(tester, ChromeRung.layout);

    final finder = find.byKey(const Key('chrome-ladder-layout-back'));
    final present = finder.evaluate().length;
    final width = tester.getSize(find.byType(ChromeLadderDemo)).width;
    double? dx;
    if (present == 1) {
      dx = tester.getCenter(finder).dx;
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }
    final welcomeBack = find.text('Welcome to Aura').evaluate().length;
    await tester.pumpWidget(const SizedBox());

    expect(present, 1, reason: 'the Layout rung shows its back control');
    expect(dx, isNotNull);
    expect(
      dx! > width / 2,
      isTrue,
      reason: 'the Layout rung positions the back control on the right',
    );
    expect(welcomeBack, 1, reason: 'tapping it pops back');
  });

  testWidgets('Layout rung persistent mode keeps custom chrome outside motion',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ChromeLadderDemo(
          initialRung: ChromeRung.layout,
          initialPersistent: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Get started'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));

    final finder = find.byKey(const Key('chrome-ladder-layout-back'));
    final present = finder.evaluate().length;
    final opacity = present == 1 ? _effectiveOpacity(tester, finder) : 0.0;
    final animating = tester.hasRunningAnimations;
    await tester.pumpWidget(const SizedBox());

    expect(present, 1, reason: 'the Layout rung shows its custom back control');
    expect(animating, isTrue, reason: 'the assertion samples mid-transition');
    expect(
      opacity,
      greaterThan(0.99),
      reason: 'persistent Layout chrome should frame the flow, not fade with '
          'the transitioning screen',
    );
  });

  testWidgets(
      'Default rung renders the built-in back chevron and it drives '
      'back', (tester) async {
    await pumpAtValue(tester, ChromeRung.defaultChrome);

    final present = find.bySemanticsLabel('Back').evaluate().length;
    if (present == 1) {
      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
    }
    final welcomeBack = find.text('Welcome to Aura').evaluate().length;
    await tester.pumpWidget(const SizedBox());

    expect(present, 1, reason: 'the Default rung shows the built-in chevron');
    expect(welcomeBack, 1, reason: 'tapping it pops back');
  });

  testWidgets('the rung selector switches the active chrome live',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ChromeLadderDemo(initialRung: ChromeRung.theme)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    // Starts on Theme (the custom icon is shown), then switch to Slots.
    final themeIconBefore =
        find.byIcon(kChromeLadderThemeIcon).evaluate().length;
    final slotsBefore =
        find.byKey(const Key('chrome-ladder-slots-back')).evaluate().length;
    // Guard the tap so a missing selector fails on the assertion below (clean)
    // rather than throwing mid-test while the error boundary is mounted.
    final hasSlotsSegment = find.text('Slots').evaluate().isNotEmpty;
    if (hasSlotsSegment) {
      await tester.tap(find.text('Slots'));
      await tester.pumpAndSettle();
    }
    final themeIconAfter =
        find.byIcon(kChromeLadderThemeIcon).evaluate().length;
    final slotsAfter =
        find.byKey(const Key('chrome-ladder-slots-back')).evaluate().length;
    // The flow position is preserved across the rung switch (still on value).
    final stillOnValue = find.text('Build a daily practice').evaluate().length;
    await tester.pumpWidget(const SizedBox());

    expect(hasSlotsSegment, isTrue, reason: 'the rung selector offers Slots');
    expect(themeIconBefore, 1, reason: 'starts on the Theme rung');
    expect(slotsBefore, 0);
    expect(themeIconAfter, 0,
        reason: 'the Theme chrome is gone after switching');
    expect(slotsAfter, 1, reason: 'the Slots chrome is now shown');
    expect(stillOnValue, 1,
        reason: 'switching rungs preserves the flow screen');
  });

  testWidgets(
      'the persistent-chrome toggle keeps a working back affordance in '
      'both modes', (tester) async {
    await pumpAtValue(tester, ChromeRung.theme);

    final iconWhenPersistent =
        find.byIcon(kChromeLadderThemeIcon).evaluate().length;
    // Flip persistent → per-screen via the toggle.
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    final iconWhenPerScreen =
        find.byIcon(kChromeLadderThemeIcon).evaluate().length;
    // The back affordance still drives a pop in per-screen mode.
    final backPresent = find.bySemanticsLabel('Back').evaluate().length;
    if (backPresent == 1) {
      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
    }
    final welcomeBack = find.text('Welcome to Aura').evaluate().length;
    await tester.pumpWidget(const SizedBox());

    expect(iconWhenPersistent, 1,
        reason: 'custom chrome shown when persistent');
    expect(iconWhenPerScreen, 1, reason: 'custom chrome shown when per-screen');
    expect(welcomeBack, 1, reason: 'back still works after the toggle');
  });

  testWidgets('shows the persistent-chrome guidance caption', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ChromeLadderDemo(initialRung: ChromeRung.theme)),
    );
    await tester.pumpAndSettle();

    // The caption tells the user how to observe the persistent-vs-per-screen
    // difference (it is only visible during a transition), so the toggle does
    // not read as inert.
    final caption = find.textContaining(
      'the back affordance holds its place when on',
    );
    final present = caption.evaluate().length;
    await tester.pumpWidget(const SizedBox());

    expect(present, 1, reason: 'the guidance caption is shown under the bar');
  });

  testWidgets('the control bar uses a theme surface color, not a fixed navy',
      (tester) async {
    // Collects the set of non-null Material colors under the demo (so the
    // assertion is on real values, never a throwing `firstWhere` that could
    // hang behind the flow's error boundary). The control-bar Material is the
    // one tinted with the theme surface; the old build used a fixed navy.
    Set<Color> materialColors() => find
        .descendant(
          of: find.byType(ChromeLadderDemo),
          matching: find.byType(Material),
        )
        .evaluate()
        .map((e) => (e.widget as Material).color)
        .whereType<Color>()
        .toSet();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
        home: const ChromeLadderDemo(initialRung: ChromeRung.theme),
      ),
    );
    await tester.pumpAndSettle();
    final lightSurface = Theme.of(tester.element(find.byType(ChromeLadderDemo)))
        .colorScheme
        .surfaceContainerHighest;
    final lightColors = materialColors();
    await tester.pumpWidget(const SizedBox());

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.indigo,
          brightness: Brightness.dark,
        ),
        home: const ChromeLadderDemo(initialRung: ChromeRung.theme),
      ),
    );
    await tester.pumpAndSettle();
    final darkSurface = Theme.of(tester.element(find.byType(ChromeLadderDemo)))
        .colorScheme
        .surfaceContainerHighest;
    final darkColors = materialColors();
    await tester.pumpWidget(const SizedBox());

    const oldNavy = Color(0xFF13264A);
    expect(lightColors, contains(lightSurface),
        reason: 'the bar tracks the light theme surface');
    expect(darkColors, contains(darkSurface),
        reason: 'the bar tracks the dark theme surface');
    expect(lightSurface, isNot(darkSurface),
        reason: 'the surface differs between light and dark');
    expect(lightColors, isNot(contains(oldNavy)),
        reason: 'the old fixed navy is gone in light mode');
    expect(darkColors, isNot(contains(oldNavy)),
        reason: 'the old fixed navy is gone in dark mode');
  });

  testWidgets('loads the flow when mounted cleanly in a dark theme',
      (tester) async {
    // A freshly-mounted demo loads the first screen regardless of theme. A
    // re-pump of the *same* widget structure (e.g. a two-brightness loop in one
    // test) reuses this State instead, so the flow stays where it was rather
    // than re-loading welcome — which is why the chrome-ladder patrol slice
    // walks each brightness in its own test. A real fresh mount (a new route,
    // the gallery) re-loads correctly, as here.
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: const ChromeLadderDemo(initialRung: ChromeRung.defaultChrome),
      ),
    );
    await tester.pumpAndSettle();
    final welcomeLoaded = find.text('Welcome to Aura').evaluate().length;
    await tester.pumpWidget(const SizedBox());

    expect(welcomeLoaded, 1, reason: 'the demo loads the flow in a dark theme');
  });
}

double _effectiveOpacity(WidgetTester tester, Finder leaf) {
  var opacity = 1.0;
  tester.element(leaf).visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is FadeTransition) {
      opacity *= widget.opacity.value;
    } else if (widget is Opacity) {
      opacity *= widget.opacity;
    }
    return widget is! ChromeLadderDemo;
  });
  return opacity;
}
