import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:restage_material/restage_material.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

const _threePlans = <RestageSelectionOption>[
  RestageSelectionOption(value: 'basic', label: 'Basic'),
  RestageSelectionOption(value: 'pro', label: 'Pro'),
  RestageSelectionOption(value: 'team', label: 'Team'),
];

void main() {
  group('RestageDropdown', () {
    testWidgets('shows the selected option as the current value',
        (tester) async {
      await tester.pumpWidget(
        _host(
          const RestageDropdown<String>(items: _threePlans, selected: 'pro'),
        ),
      );

      // The closed field shows the selected label.
      expect(find.text('Pro'), findsOneWidget);
      expect(find.byType(DropdownButton<String>), findsOneWidget);
    });

    testWidgets('opening the menu lists every option', (tester) async {
      await tester.pumpWidget(
        _host(
          RestageDropdown<String>(
            items: _threePlans,
            selected: 'basic',
            // A non-null onChanged is required for the field to be enabled
            // (Flutter disables a DropdownButton when onChanged is null).
            onChanged: (_) {},
          ),
        ),
      );

      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();

      // The open menu route shows every option label (the selected value also
      // appears as the closed field's value, hence findsWidgets throughout).
      expect(find.text('Pro'), findsWidgets);
      expect(find.text('Team'), findsWidgets);
      expect(find.text('Basic'), findsWidgets);
    });

    testWidgets('fires onChanged with the chosen value (the settled event)',
        (tester) async {
      String? fired;
      await tester.pumpWidget(
        _host(
          RestageDropdown<String>(
            items: _threePlans,
            selected: 'basic',
            onChanged: (v) => fired = v,
          ),
        ),
      );

      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Team').last);
      await tester.pumpAndSettle();

      expect(fired, 'team');
    });

    testWidgets('empty items renders nothing (fail-safe)', (tester) async {
      await tester.pumpWidget(
        _host(const RestageDropdown<String>(items: [])),
      );

      expect(find.byType(DropdownButton<String>), findsNothing);
    });

    testWidgets('a selected value matching no option degrades to the hint',
        (tester) async {
      // 'gone' is not among the options — a stale/hostile value. Without the
      // coercion this would trip DropdownButton's value assert; instead the
      // field shows the hint.
      await tester.pumpWidget(
        _host(
          const RestageDropdown<String>(
            items: _threePlans,
            selected: 'gone',
            hint: 'Choose a plan',
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Choose a plan'), findsOneWidget);
    });

    testWidgets('duplicate values are de-duplicated', (tester) async {
      await tester.pumpWidget(
        _host(
          RestageDropdown<String>(
            items: const [
              RestageSelectionOption(value: 'pro', label: 'Pro'),
              RestageSelectionOption(value: 'pro', label: 'Pro (dupe)'),
              RestageSelectionOption(value: 'team', label: 'Team'),
            ],
            selected: 'pro',
            onChanged: (_) {},
          ),
        ),
      );

      // No duplicate-value assert tripped at build.
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      // The open menu shows the surviving option but never the dropped dupe.
      expect(find.text('Team'), findsWidgets);
      expect(find.text('Pro (dupe)'), findsNothing);
    });
  });
}
