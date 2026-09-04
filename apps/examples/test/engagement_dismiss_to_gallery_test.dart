import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/onboarding/apex_drop_demo.dart';
import 'package:restage_example/onboarding/crave_permission_demo.dart';
import 'package:restage_example/onboarding/lumen_onboarding_demo.dart';
import 'package:restage_example/onboarding/minimal_onboarding_demo.dart';
import 'package:restage_example/onboarding/reel_cancel_demo.dart';
import 'package:restage_example/user_factories.g.dart';

/// Drive-and-assert proof that every engagement surface — and every host-owned
/// terminal screen it hands off to — stays escapable back to the gallery.
///
/// The gallery hosts these surfaces full-bleed with its own escape control off,
/// and the surfaces draw no close of their own, so leaving is the platform's own
/// back. These tests push each surface over a sentinel home (standing in for the
/// gallery), drive it, send system back, and assert the sentinel is on stage
/// again — i.e. the host route popped. From mid-flow the first back must step
/// back a screen rather than leave.
void main() {
  const galleryMarker = '— gallery —';

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

  // Unmounts the surface before the expectations so a regression reports
  // cleanly instead of deferring behind the still-mounted error boundary.
  Future<void> unmountSurface(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  // The engagement surfaces draw no close of their own: leaving is the
  // platform's own back. While the flow has history this steps back one screen;
  // at the first screen the host route pops and the gallery returns.
  Future<void> systemBack(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  group('Lumen meditation onboarding', () {
    testWidgets('system back at the flow root returns to the gallery',
        (tester) async {
      await pushSurface(tester, const LumenOnboardingDemo());
      expect(find.text('Welcome to Lumen'), findsOneWidget);

      await systemBack(tester);

      expect(find.text('Welcome to Lumen'), findsNothing);
      expect(find.text(galleryMarker), findsOneWidget);
    });

    testWidgets('system back steps back, then leaves the surface',
        (tester) async {
      // The flow parks its screen history on this route, so a close that only
      // asked the route to pop would step back a screen instead of closing.
      await pushSurface(tester, const LumenOnboardingDemo());
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();
      expect(find.text("I'm new to meditation"), findsOneWidget);

      // From screen two, system back steps back one screen.
      await systemBack(tester);
      final steppedBack = find.text('Welcome to Lumen').evaluate().length == 1;
      final secondGone = find.text("I'm new to meditation").evaluate().isEmpty;
      final stillHosted = find.text(galleryMarker).evaluate().isEmpty;

      // From the first screen it leaves the surface.
      await systemBack(tester);
      final backAtGallery = find.text(galleryMarker).evaluate().length == 1;
      await unmountSurface(tester);

      expect(steppedBack, isTrue);
      expect(secondGone, isTrue);
      expect(stillHosted, isTrue);
      expect(backAtGallery, isTrue);
    });

    testWidgets(
        'system back on the terminal completion screen returns to the gallery',
        (tester) async {
      await pushSurface(tester, const LumenOnboardingDemo());
      // Drive the whole flow to the "Onboarding complete" terminal.
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
      expect(find.text('Onboarding complete'), findsOneWidget);

      await systemBack(tester);

      expect(find.text('Onboarding complete'), findsNothing);
      expect(find.text(galleryMarker), findsOneWidget);
    });
  });

  group('Crave location primer', () {
    testWidgets('system back at the first screen returns to the gallery',
        (tester) async {
      await pushSurface(tester, const CravePermissionDemo());
      expect(find.text('Restaurants right around you'), findsOneWidget);

      await systemBack(tester);

      expect(find.text('Restaurants right around you'), findsNothing);
      expect(find.text(galleryMarker), findsOneWidget);
    });

    testWidgets('system back steps back, then leaves the surface',
        (tester) async {
      await pushSurface(tester, const CravePermissionDemo());
      await tester.tap(find.text('Use current location'));
      await tester.pumpAndSettle();
      expect(find.text('Start browsing'), findsOneWidget);

      // From screen two, system back steps back one screen.
      await systemBack(tester);
      final steppedBack =
          find.text('Restaurants right around you').evaluate().length == 1;
      final secondGone = find.text('Start browsing').evaluate().isEmpty;
      final stillHosted = find.text(galleryMarker).evaluate().isEmpty;

      // From the first screen it leaves the surface.
      await systemBack(tester);
      final backAtGallery = find.text(galleryMarker).evaluate().length == 1;
      await unmountSurface(tester);

      expect(steppedBack, isTrue);
      expect(secondGone, isTrue);
      expect(stillHosted, isTrue);
      expect(backAtGallery, isTrue);
    });

    testWidgets(
        'system back on the terminal entered-app screen returns to the gallery',
        (tester) async {
      await pushSurface(tester, const CravePermissionDemo());
      await tester.tap(find.text('Use current location'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start browsing'));
      await tester.pumpAndSettle();
      expect(find.text('Browsing restaurants'), findsOneWidget);

      await systemBack(tester);

      expect(find.text('Browsing restaurants'), findsNothing);
      expect(find.text(galleryMarker), findsOneWidget);
    });
  });

  group('ApexDrop in-app message', () {
    testWidgets(
        'system back on the terminal shop screen returns to the gallery',
        (tester) async {
      await pushSurface(tester, const ApexDropDemo());
      // The message's own × already pops (covered by apex_drop_flow_test); the
      // gap is the "acted → shop" terminal, which was a dead end.
      await tester.tap(find.text('Shop the drop'));
      await tester.pumpAndSettle();
      expect(find.text('Browsing the drop'), findsOneWidget);

      await systemBack(tester);

      expect(find.text('Browsing the drop'), findsNothing);
      expect(find.text(galleryMarker), findsOneWidget);
    });
  });

  group('Reel cancellation survey', () {
    testWidgets('system back at the first screen returns to the gallery',
        (tester) async {
      await pushSurface(tester, const ReelCancelDemo());
      expect(find.text('Why are you leaving?'), findsOneWidget);

      await systemBack(tester);

      expect(find.text('Why are you leaving?'), findsNothing);
      expect(find.text(galleryMarker), findsOneWidget);
    });

    testWidgets('system back steps back, then leaves the surface',
        (tester) async {
      await pushSurface(tester, const ReelCancelDemo());
      await tester.tap(find.text('It’s too expensive'));
      await tester.pumpAndSettle();
      expect(find.text('Almost every day'), findsOneWidget);

      // From screen two, system back steps back one screen.
      await systemBack(tester);
      final steppedBack =
          find.text('Why are you leaving?').evaluate().length == 1;
      final secondGone = find.text('Almost every day').evaluate().isEmpty;
      final stillHosted = find.text(galleryMarker).evaluate().isEmpty;

      // From the first screen it leaves the surface.
      await systemBack(tester);
      final backAtGallery = find.text(galleryMarker).evaluate().length == 1;
      await unmountSurface(tester);

      expect(steppedBack, isTrue);
      expect(secondGone, isTrue);
      expect(stillHosted, isTrue);
      expect(backAtGallery, isTrue);
    });

    testWidgets(
        'system back on the terminal outcome screen returns to the gallery',
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

      await systemBack(tester);

      expect(find.text('Membership kept'), findsNothing);
      expect(find.text(galleryMarker), findsOneWidget);
    });
  });

  group('Onboarding starter', () {
    testWidgets('system back steps back, then leaves the surface',
        (tester) async {
      await pushSurface(tester, const MinimalOnboardingDemo());
      expect(find.text('Welcome'), findsOneWidget);
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();
      expect(find.text('How do you want to start?'), findsOneWidget);

      // From screen two, system back steps back one screen.
      await systemBack(tester);
      final steppedBack = find.text('Welcome').evaluate().length == 1;
      final secondGone =
          find.text('How do you want to start?').evaluate().isEmpty;
      final stillHosted = find.text(galleryMarker).evaluate().isEmpty;

      // From the first screen it leaves the surface.
      await systemBack(tester);
      final backAtGallery = find.text(galleryMarker).evaluate().length == 1;
      await unmountSurface(tester);

      expect(steppedBack, isTrue);
      expect(secondGone, isTrue);
      expect(stillHosted, isTrue);
      expect(backAtGallery, isTrue);
    });
  });
}
