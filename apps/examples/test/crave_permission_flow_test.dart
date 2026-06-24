import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/onboarding/crave_permission_demo.dart';

/// Give the test a tall canvas so the full-screen primer renders without a false
/// RenderFlex overflow under the wide Ahem test font.
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

  testWidgets('the location gate grants → confirmation → enters the app',
      (tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(const MaterialApp(home: CravePermissionDemo()));
    await tester.pumpAndSettle();

    // The primer (the host-action gate screen).
    expect(find.text('Restaurants right around you'), findsOneWidget);
    await tester.tap(find.text('Use current location'));
    await tester.pumpAndSettle();

    // Granted → the confirmation (the gate advanced on a granted result).
    expect(find.text('You’re all set'), findsOneWidget);
    await tester.tap(find.text('Start browsing'));
    await tester.pumpAndSettle();

    // Completed → entered the app.
    expect(find.text('Browsing restaurants'), findsOneWidget);
  });

  testWidgets('the location gate holds when the OS permission is declined',
      (tester) async {
    // With a declined decision the flow stays on the primer — the gate's
    // advance-or-stay semantics (it never proceeds on permission it did not
    // get).
    _useTallSurface(tester);
    await tester.pumpWidget(
      const MaterialApp(home: CravePermissionDemo(grantLocation: false)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Restaurants right around you'), findsOneWidget);
    await tester.tap(find.text('Use current location'));
    await tester.pumpAndSettle();

    // Declined: the flow holds on the primer, never reaching the confirmation.
    expect(find.text('Restaurants right around you'), findsOneWidget);
    expect(find.text('You’re all set'), findsNothing);
  });

  testWidgets('"Not now" carries the user into the app without the grant',
      (tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(const MaterialApp(home: CravePermissionDemo()));
    await tester.pumpAndSettle();

    expect(find.text('Restaurants right around you'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    // The host handled the `skip` custom event → entered the app without the
    // grant, never reaching the confirmation.
    expect(find.text('Browsing restaurants'), findsOneWidget);
    expect(find.text('You’re all set'), findsNothing);
  });
}
