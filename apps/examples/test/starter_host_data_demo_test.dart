import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/surfaces/starter_host_data_demo.dart';

void main() {
  setUp(() {
    Restage.debugReset();
    Restage.configure(
      apiKey: 'rs_pk_test',
      resolver: const AssetVariantResolver(),
    );
  });

  testWidgets('renders the rows the app passed in', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: StarterHostDataDemo()));
    await tester.pumpAndSettle();

    expect(find.text("Sam's checklist"), findsOneWidget);
    expect(find.text('Fill in your profile'), findsOneWidget);
    expect(find.text('Invite a teammate'), findsOneWidget);
    expect(find.text('Turn on sync'), findsOneWidget);
    expect(find.text('To do'), findsNWidgets(3));
    expect(find.text('Done'), findsNothing);
  });

  testWidgets('a tap reaches the app, which changes the row', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: StarterHostDataDemo()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Invite a teammate'));
    await tester.pumpAndSettle();

    expect(find.text('Done'), findsOneWidget);
    expect(find.text('To do'), findsNWidgets(2));

    await tester.tap(find.text('Invite a teammate'));
    await tester.pumpAndSettle();

    expect(find.text('Done'), findsNothing);
    expect(find.text('To do'), findsNWidgets(3));
  });
}
