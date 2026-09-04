import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/onboarding/bare_surface_demo.dart';
import 'package:restage_example/onboarding/crave_permission_demo.dart';
import 'package:restage_example/onboarding/minimal_notice_demo.dart';
import 'package:restage_example/onboarding/lumen_onboarding_demo.dart';
import 'package:restage_example/onboarding/minimal_onboarding_demo.dart';
import 'package:restage_example/onboarding/reel_cancel_demo.dart';
import 'package:restage_example/onboarding/tally_onboarding_demo.dart';
import 'package:restage_example/surfaces/starter_host_data_demo.dart';
import 'package:restage_example/widgets/minimal_custom_widget_demo.dart';
import 'package:restage_example/user_factories.g.dart';

/// The engagement surfaces draw no host chrome, so in-flow back is the app bar
/// each screen carries. The bar implies its control from the route's history, so
/// the first screen must show none and the next must show one — the regression
/// these pin is a back arrow offered where there is nothing to go back to.
void main() {
  setUp(() {
    Restage.debugReset();
    Restage.configure(
      apiKey: 'rs_pk_test',
      resolver: const AssetVariantResolver(),
    );
    registerRestageWidgets();
  });

  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  // Mounts [surface] as the app's only route, so an app bar's back control can
  // come only from the flow's own history.
  Future<void> pumpSurface(WidgetTester tester, Widget surface) async {
    useTallSurface(tester);
    await tester.pumpWidget(MaterialApp(home: surface));
    await tester.pumpAndSettle();
  }

  Future<void> unmountSurface(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  /// Drives [surface] from its first screen to its second by tapping [advance],
  /// asserting the back control appears only on the second.
  Future<void> expectBackOnSecondScreenOnly(
    WidgetTester tester,
    Widget surface, {
    required String advance,
    required String secondScreen,
  }) async {
    await pumpSurface(tester, surface);
    final backOnFirst = find.byType(BackButton).evaluate().length;

    await tester.tap(find.text(advance));
    await tester.pumpAndSettle();
    final reachedSecond = find.text(secondScreen).evaluate().length;
    final backOnSecond = find.byType(BackButton).evaluate().length;
    await unmountSurface(tester);

    expect(backOnFirst, 0,
        reason: 'the first screen has nothing to go back to');
    expect(reachedSecond, 1);
    expect(backOnSecond, 1, reason: 'the second screen implies back');
  }

  /// A single-screen starter: its bar implies back because the gallery route
  /// can pop, which is the only escape those surfaces have.
  Future<void> expectBackOnASingleScreen(
    WidgetTester tester,
    Widget surface,
  ) async {
    useTallSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => surface),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final bars = find.byType(AppBar).evaluate().length;
    final backs = find.byType(BackButton).evaluate().length;
    await unmountSurface(tester);

    expect(bars, 1, reason: 'the starter screen carries an app bar');
    expect(backs, 1, reason: 'the pushed route implies back into the gallery');
  }

  testWidgets('Lumen: back appears on the second screen only', (tester) async {
    await expectBackOnSecondScreenOnly(
      tester,
      const LumenOnboardingDemo(),
      advance: 'Get started',
      secondScreen: "I'm new to meditation",
    );
  });

  testWidgets('the onboarding starter: back appears on the second screen only',
      (tester) async {
    await expectBackOnSecondScreenOnly(
      tester,
      const MinimalOnboardingDemo(),
      advance: 'Get started',
      secondScreen: 'How do you want to start?',
    );
  });

  testWidgets('Crave: back appears on the second screen only', (tester) async {
    await expectBackOnSecondScreenOnly(
      tester,
      const CravePermissionDemo(),
      advance: 'Use current location',
      secondScreen: 'Start browsing',
    );
  });

  testWidgets('Tally: back appears on the second screen only', (tester) async {
    await expectBackOnSecondScreenOnly(
      tester,
      const TallyOnboardingDemo(),
      advance: 'Get started',
      secondScreen: 'Pay off debt',
    );
  });

  testWidgets('Reel: back appears on the second screen only', (tester) async {
    await expectBackOnSecondScreenOnly(
      tester,
      const ReelCancelDemo(),
      advance: 'It’s too expensive',
      secondScreen: 'Almost every day',
    );
  });

  testWidgets('the bare surface starter implies back', (tester) async {
    await expectBackOnASingleScreen(tester, const BareSurfaceDemo());
  });

  testWidgets('the minimal notice starter implies back', (tester) async {
    await expectBackOnASingleScreen(tester, const MinimalNoticeDemo());
  });

  testWidgets('the custom widget starter implies back', (tester) async {
    await expectBackOnASingleScreen(tester, const MinimalCustomWidgetDemo());
  });

  testWidgets('the host data starter implies back', (tester) async {
    await expectBackOnASingleScreen(tester, const StarterHostDataDemo());
  });
}
