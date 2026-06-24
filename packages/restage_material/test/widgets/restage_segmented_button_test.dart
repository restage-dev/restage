import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:restage_material/restage_material.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

const _threeOptions = <RestageSelectionOption>[
  RestageSelectionOption(value: 'day', label: 'Day'),
  RestageSelectionOption(value: 'week', label: 'Week'),
  RestageSelectionOption(value: 'month', label: 'Month'),
];

void main() {
  group('RestageSegmentedButton', () {
    testWidgets('renders one segment per item, in order', (tester) async {
      await tester.pumpWidget(
        _host(
          const RestageSegmentedButton<String>(
            items: _threeOptions,
            selected: ['day'],
          ),
        ),
      );

      expect(find.byType(SegmentedButton<String>), findsOneWidget);
      expect(find.text('Day'), findsOneWidget);
      expect(find.text('Week'), findsOneWidget);
      expect(find.text('Month'), findsOneWidget);
    });

    testWidgets('drives selection from selected (single-select)',
        (tester) async {
      await tester.pumpWidget(
        _host(
          const RestageSegmentedButton<String>(
            items: _threeOptions,
            selected: ['week'],
          ),
        ),
      );

      final button = tester.widget<SegmentedButton<String>>(
        find.byType(SegmentedButton<String>),
      );
      expect(button.selected, {'week'});
    });

    testWidgets(
        'fires onChanged with the SEGMENT-ORDERED settled list (not set '
        'order) when a segment is tapped', (tester) async {
      List<String>? fired;
      await tester.pumpWidget(
        _host(
          RestageSegmentedButton<String>(
            items: _threeOptions,
            selected: const ['day'],
            onChanged: (v) => fired = v,
          ),
        ),
      );

      await tester.tap(find.text('Month'));
      await tester.pump();

      // Single-select: tapping Month settles to ['month'].
      expect(fired, ['month']);
    });

    testWidgets(
        'multi-select fires the whole selection in SEGMENT order, '
        'regardless of tap order', (tester) async {
      List<String>? fired;
      await tester.pumpWidget(
        _host(
          RestageSegmentedButton<String>(
            items: _threeOptions,
            selected: const ['month'], // start with the LAST segment selected
            multiSelectionEnabled: true,
            onChanged: (v) => fired = v,
          ),
        ),
      );

      // Add 'day' (the FIRST segment) to the selection. The fired list must be
      // in SEGMENT order [day, month], NOT tap/insertion order [month, day]
      // and NOT Set-iteration order — the wire must be deterministic.
      await tester.tap(find.text('Day'));
      await tester.pump();

      expect(fired, ['day', 'month']);
    });

    testWidgets('multi-select renders multiple selected segments',
        (tester) async {
      await tester.pumpWidget(
        _host(
          const RestageSegmentedButton<String>(
            items: _threeOptions,
            selected: ['day', 'month'],
            multiSelectionEnabled: true,
          ),
        ),
      );

      final button = tester.widget<SegmentedButton<String>>(
        find.byType(SegmentedButton<String>),
      );
      expect(button.selected, {'day', 'month'});
    });

    testWidgets('empty items renders nothing (fail-safe)', (tester) async {
      await tester.pumpWidget(
        _host(const RestageSegmentedButton<String>(items: [], selected: [])),
      );

      expect(find.byType(SegmentedButton<String>), findsNothing);
      expect(find.byType(SizedBox), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'a selected value not in items degrades gracefully — never throws',
        (tester) async {
      // Flutter's SegmentedButton does not assert on a selected value absent
      // from segments, but a hostile/stale value must not render a phantom
      // selection. The wrapper filters selected to known segment values.
      await tester.pumpWidget(
        _host(
          const RestageSegmentedButton<String>(
            items: _threeOptions,
            selected: ['year'], // not a segment value
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      final button = tester.widget<SegmentedButton<String>>(
        find.byType(SegmentedButton<String>),
      );
      // The unknown value is dropped; with emptySelectionAllowed defaulting
      // true in the wrapper, the selection is empty rather than a crash.
      expect(button.selected, isEmpty);
    });

    testWidgets(
        'single-select with 2+ selected values clamps to the first — never '
        'trips assert(selected.length < 2 || multiSelectionEnabled)',
        (tester) async {
      // A tampered wire could carry two selected values while
      // multiSelectionEnabled is false. Flutter asserts against that; the
      // wrapper keeps only the first (in segment order) so it never crashes.
      await tester.pumpWidget(
        _host(
          const RestageSegmentedButton<String>(
            items: _threeOptions,
            selected: ['week', 'month'], // 2 selected, single-select mode
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      final button = tester.widget<SegmentedButton<String>>(
        find.byType(SegmentedButton<String>),
      );
      // Keeps the first in SEGMENT order (week precedes month).
      expect(button.selected, {'week'});
    });

    testWidgets(
        'duplicate-value items are de-duped — never trips the unique-value '
        'requirement', (tester) async {
      await tester.pumpWidget(
        _host(
          const RestageSegmentedButton<String>(
            items: [
              RestageSelectionOption(value: 'day', label: 'Day'),
              RestageSelectionOption(value: 'day', label: 'Day again'),
              RestageSelectionOption(value: 'week', label: 'Week'),
            ],
            selected: ['day'],
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      // First occurrence wins; the second 'day' is dropped.
      expect(find.text('Day'), findsOneWidget);
      expect(find.text('Day again'), findsNothing);
      expect(find.text('Week'), findsOneWidget);
    });

    testWidgets('honors multiSelectionEnabled and emptySelectionAllowed bools',
        (tester) async {
      await tester.pumpWidget(
        _host(
          const RestageSegmentedButton<String>(
            items: _threeOptions,
            selected: [],
            emptySelectionAllowed: true,
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      final button = tester.widget<SegmentedButton<String>>(
        find.byType(SegmentedButton<String>),
      );
      expect(button.emptySelectionAllowed, isTrue);
      expect(button.selected, isEmpty);
    });
  });
}
