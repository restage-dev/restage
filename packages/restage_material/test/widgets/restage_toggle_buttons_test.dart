import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_material/restage_material.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

const _threeLabels = <Widget>[
  Text('Bold'),
  Text('Italic'),
  Text('Underline'),
];

void main() {
  group('RestageToggleButtons', () {
    testWidgets('renders one toggle per child, in order', (tester) async {
      await tester.pumpWidget(
        _host(
          const RestageToggleButtons(
            isSelected: [true, false, false],
            children: _threeLabels,
          ),
        ),
      );

      expect(find.byType(ToggleButtons), findsOneWidget);
      expect(find.text('Bold'), findsOneWidget);
      expect(find.text('Italic'), findsOneWidget);
      expect(find.text('Underline'), findsOneWidget);
    });

    testWidgets('drives selection from isSelected, in order', (tester) async {
      await tester.pumpWidget(
        _host(
          const RestageToggleButtons(
            isSelected: [false, true, false],
            children: _threeLabels,
          ),
        ),
      );

      final toggle = tester.widget<ToggleButtons>(find.byType(ToggleButtons));
      expect(toggle.isSelected, [false, true, false]);
    });

    testWidgets('fires onPressed with the tapped index (the settled event)',
        (tester) async {
      int? pressed;
      await tester.pumpWidget(
        _host(
          RestageToggleButtons(
            isSelected: const [false, false, false],
            onPressed: (i) => pressed = i,
            children: _threeLabels,
          ),
        ),
      );

      await tester.tap(find.text('Underline'));
      await tester.pump();

      expect(pressed, 2);
    });

    testWidgets('empty children renders nothing (fail-safe)', (tester) async {
      await tester.pumpWidget(
        _host(
          const RestageToggleButtons(isSelected: [], children: []),
        ),
      );

      expect(find.byType(ToggleButtons), findsNothing);
      expect(find.byType(SizedBox), findsWidgets);
    });

    testWidgets(
        'isSelected SHORTER than children pads with false — never throws '
        '(layer-b clamp)', (tester) async {
      // A mismatched-length wire must NOT trip Flutter's
      // assert(children.length == isSelected.length). The wrapper pads the
      // short isSelected with `false` (unselected) up to children.length.
      await tester.pumpWidget(
        _host(
          const RestageToggleButtons(
            isSelected: [true], // shorter than 3 children
            children: _threeLabels,
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      final toggle = tester.widget<ToggleButtons>(find.byType(ToggleButtons));
      // First reflects the author's true; the padded tail is false.
      expect(toggle.isSelected, [true, false, false]);
    });

    testWidgets(
        'isSelected LONGER than children truncates — never throws '
        '(layer-b clamp)', (tester) async {
      await tester.pumpWidget(
        _host(
          const RestageToggleButtons(
            isSelected: [true, false, true, true, false], // longer than 3
            children: _threeLabels,
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      final toggle = tester.widget<ToggleButtons>(find.byType(ToggleButtons));
      // Truncated to children.length, preserving the leading flags.
      expect(toggle.isSelected, [true, false, true]);
    });
  });
}
