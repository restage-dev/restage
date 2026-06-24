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
  group('RestageRadioGroup', () {
    testWidgets('renders one row per option in order', (tester) async {
      await tester.pumpWidget(
        _host(const RestageRadioGroup<String>(items: _threePlans)),
      );

      expect(find.text('Basic'), findsOneWidget);
      expect(find.text('Pro'), findsOneWidget);
      expect(find.text('Team'), findsOneWidget);
      expect(find.byType(RadioListTile<String>), findsNWidgets(3));
    });

    testWidgets('drives the group selection from selected', (tester) async {
      await tester.pumpWidget(
        _host(
          const RestageRadioGroup<String>(items: _threePlans, selected: 'pro'),
        ),
      );

      // The selection is driven by the RadioGroup ancestor's groupValue (the
      // modern API), not the deprecated per-tile groupValue — assert on the
      // ancestor that actually drives the rendered checkmark.
      final group = tester.widget<RadioGroup<String>>(
        find.byType(RadioGroup<String>),
      );
      expect(group.groupValue, 'pro');
    });

    testWidgets('fires onChanged with the tapped value (the settled event)',
        (tester) async {
      String? fired;
      await tester.pumpWidget(
        _host(
          RestageRadioGroup<String>(
            items: _threePlans,
            selected: 'basic',
            onChanged: (v) => fired = v,
          ),
        ),
      );

      await tester.tap(find.text('Team'));
      await tester.pump();

      expect(fired, 'team');
    });

    testWidgets('empty items renders nothing (fail-safe)', (tester) async {
      await tester.pumpWidget(
        _host(const RestageRadioGroup<String>(items: [])),
      );

      expect(find.byType(RadioListTile<String>), findsNothing);
      expect(find.byType(SizedBox), findsWidgets);
    });

    testWidgets('duplicate values are de-duplicated (single-select invariant)',
        (tester) async {
      await tester.pumpWidget(
        _host(
          const RestageRadioGroup<String>(
            items: [
              RestageSelectionOption(value: 'pro', label: 'Pro'),
              RestageSelectionOption(value: 'pro', label: 'Pro (dupe)'),
              RestageSelectionOption(value: 'team', label: 'Team'),
            ],
          ),
        ),
      );

      // Only the first 'pro' survives; the group has two rows.
      expect(find.byType(RadioListTile<String>), findsNWidgets(2));
      expect(find.text('Pro'), findsOneWidget);
      expect(find.text('Pro (dupe)'), findsNothing);
    });
  });
}
