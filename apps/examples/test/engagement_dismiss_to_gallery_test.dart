import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/onboarding/apex_drop_demo.dart';
import 'package:restage_example/onboarding/chrome_ladder_demo.dart';
import 'package:restage_example/onboarding/crave_permission_demo.dart';
import 'package:restage_example/onboarding/lumen_onboarding_demo.dart';
import 'package:restage_example/onboarding/reel_cancel_demo.dart';
import 'package:restage_example/stub_products.dart';
import 'package:restage_example/user_factories.g.dart';

/// Drive-and-assert proof that every engagement surface — and every host-owned
/// terminal screen it hands off to — stays escapable back to the gallery.
///
/// The gallery hosts these surfaces full-bleed with its own escape control off,
/// so the only way back is the surface's own affordance. These tests push each
/// surface over a sentinel home (standing in for the gallery), drive it, tap the
/// dismiss affordance, and assert the sentinel is on stage again — i.e. the host
/// route popped. A rendered-but-no-op control (the bug being fixed) leaves the
/// surface on stage and FAILS the assertion.
void main() {
  const galleryMarker = '— gallery —';

  setUp(() {
    Restage.debugReset();
    Restage.configure(
      apiKey: 'rs_pk_test',
      products: kStubProducts,
      resolver: const AssetVariantResolver(),
    );
    registerRestageCustomerWidgets();
  });

  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  // Pushes [surface] over a sentinel "gallery" home so a dismiss has somewhere
  // to pop to, mirroring how the gallery hosts each engagement surface.
  Future<void> pushSurface(WidgetTester tester, Widget surface) async {
    useTallSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => surface),
                ),
                child: const Text(galleryMarker),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text(galleryMarker));
    await tester.pumpAndSettle();
    // The surface is on stage; the gallery marker is covered by the pushed route.
    expect(find.text(galleryMarker), findsNothing);
  }

  Future<void> tapDismiss(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('gallery-dismiss')));
    await tester.pumpAndSettle();
  }

  group('Lumen meditation onboarding', () {
    testWidgets('the flow-root close returns to the gallery', (tester) async {
      await pushSurface(tester, const LumenOnboardingDemo());
      expect(find.text('Welcome to Lumen'), findsOneWidget);

      await tapDismiss(tester);

      expect(find.text('Welcome to Lumen'), findsNothing);
      expect(find.text(galleryMarker), findsOneWidget);
    });

    testWidgets('the terminal completion screen returns to the gallery',
        (tester) async {
      await pushSurface(tester, const LumenOnboardingDemo());
      // Drive the whole flow to the "Subscription started" terminal.
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
      await tester.tap(find.text('Start free trial'));
      await tester.pumpAndSettle();
      expect(find.text('Subscription started'), findsOneWidget);

      await tapDismiss(tester);

      expect(find.text('Subscription started'), findsNothing);
      expect(find.text(galleryMarker), findsOneWidget);
    });
  });

  group('Crave location primer', () {
    testWidgets('the persistent close returns to the gallery', (tester) async {
      await pushSurface(tester, const CravePermissionDemo());
      expect(find.text('Restaurants right around you'), findsOneWidget);

      await tapDismiss(tester);

      expect(find.text('Restaurants right around you'), findsNothing);
      expect(find.text(galleryMarker), findsOneWidget);
    });

    testWidgets('the terminal entered-app screen returns to the gallery',
        (tester) async {
      await pushSurface(tester, const CravePermissionDemo());
      await tester.tap(find.text('Use current location'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start browsing'));
      await tester.pumpAndSettle();
      expect(find.text('Browsing restaurants'), findsOneWidget);

      await tapDismiss(tester);

      expect(find.text('Browsing restaurants'), findsNothing);
      expect(find.text(galleryMarker), findsOneWidget);
    });
  });

  group('ApexDrop in-app message', () {
    testWidgets('the terminal shop screen returns to the gallery',
        (tester) async {
      await pushSurface(tester, const ApexDropDemo());
      // The message's own × already pops (covered by apex_drop_flow_test); the
      // gap is the "acted → shop" terminal, which was a dead end.
      await tester.tap(find.text('Shop the drop'));
      await tester.pumpAndSettle();
      expect(find.text('Browsing the drop'), findsOneWidget);

      await tapDismiss(tester);

      expect(find.text('Browsing the drop'), findsNothing);
      expect(find.text(galleryMarker), findsOneWidget);
    });
  });

  group('Reel cancellation survey', () {
    testWidgets('the persistent close returns to the gallery', (tester) async {
      await pushSurface(tester, const ReelCancelDemo());
      expect(find.text('Why are you leaving?'), findsOneWidget);

      await tapDismiss(tester);

      expect(find.text('Why are you leaving?'), findsNothing);
      expect(find.text(galleryMarker), findsOneWidget);
    });

    testWidgets('the terminal outcome screen returns to the gallery',
        (tester) async {
      await pushSurface(tester, const ReelCancelDemo());
      await tester.tap(find.text('It’s too expensive'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Almost every day'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep my discount'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue watching'));
      await tester.pumpAndSettle();
      expect(find.text('Membership kept'), findsOneWidget);

      await tapDismiss(tester);

      expect(find.text('Membership kept'), findsNothing);
      expect(find.text(galleryMarker), findsOneWidget);
    });
  });

  group('Chrome customization ladder', () {
    testWidgets('the control-bar close returns to the gallery', (tester) async {
      await pushSurface(tester, const ChromeLadderDemo());
      expect(find.byType(ChromeLadderDemo), findsOneWidget);

      await tester.tap(find.byKey(const Key('chrome-ladder-close')));
      await tester.pumpAndSettle();

      expect(find.byType(ChromeLadderDemo), findsNothing);
      expect(find.text(galleryMarker), findsOneWidget);
    });
  });
}
