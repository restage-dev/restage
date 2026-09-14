import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/library_registration.dart' as live_core;
import 'package:restage_cupertino/library_registration.dart' as live_cupertino;
import 'package:restage_material/library_registration.dart' as live_material;
import 'package:restage_material/restage_material.dart'
    show RestageDropdown, RestageSegmentedButton;
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart' hide Switch;

// Frozen at 539433aaef5a128d7654b0ac281fcab4e5b4dc93; see the oracle
// README for provenance and the policy forbidding automatic regeneration.
import 'sdk_size_oracle/core_registration.dart' as old_core;
import 'sdk_size_oracle/cupertino_registration.dart' as old_cupertino;
import 'sdk_size_oracle/material_registration.dart' as old_material;

const _root = LibraryName(['probe']);
const _fixture = '''
import restage.core;
import restage.material;
import restage.cupertino;
widget Main = SingleChildScrollView(child: Column(children: [
  Align(alignment: {x: 1.0, y: -1.0}, widthFactor: data.widthFactor,
    heightFactor: 2.0, child: SizedBox(width: 31.0, height: 12.0)),
  Padding(padding: [2.0, 3.0, 4.0, 5.0],
    child: Text(text: "preserve", fontSize: 19.0, maxLines: 2)),
  Checkbox(value: false, activeColor: 0xff123456,
    onChanged: [event "checkbox" {fixed: "yes", value: "old"},
      event "checkbox-again" {}]),
  CupertinoSwitch(value: true, onChanged: event "switch" {}),
  Slider(value: 0.2, divisions: 5, onChanged: event "slider" {}),
  TextField(maxLength: 9, onChanged: event "text" {},
    onSubmitted: event "submit" {}),
  CupertinoTextField(placeholder: "type", onChanged: event "ctext" {},
    onSubmitted: event "csubmit" {}),
  RestageDropdownString(items: [{value: "a", label: "A"}], selected: "a",
    onChanged: event "dropdown" {}),
  RestageSegmentedButtonString(items: [{value: "a", label: "A"}],
    selected: ["a"], onChanged: event "segment" {}),
  CupertinoPicker(itemExtent: 30.0, children: [Text(text: "one")],
    onSelectedItemChanged: event "picker" {}),
  CupertinoDatePicker(minimumYear: 2020, maximumYear: 2030,
    onDateTimeChanged: event "date" {}),
  CupertinoTimerPicker(onTimerDurationChanged: event "duration" {})
]));
''';

Map<String, Map<String, LocalWidgetBuilder>> _factories(bool original) => {
      'core': original
          ? old_core.kCoreLibraryFactories
          : live_core.kCoreLibraryFactories,
      'material': original
          ? old_material.kMaterialLibraryFactories
          : live_material.kMaterialLibraryFactories,
      'cupertino': original
          ? old_cupertino.kCupertinoLibraryFactories
          : live_cupertino.kCupertinoLibraryFactories,
    };

Future<
    ({
      Map<String, List<Widget>> built,
      List<Object?> events,
      Runtime runtime,
      DynamicContent data,
    })> _pump(
  WidgetTester tester, {
  required bool original,
  String fixture = _fixture,
}) async {
  final built = <String, List<Widget>>{};
  final events = <Object?>[];
  final runtime = Runtime();
  for (final family in _factories(original).entries) {
    runtime.update(
      LibraryName(['restage', family.key]),
      LocalWidgetLibrary({
        for (final entry in family.value.entries)
          entry.key: (context, source) {
            final widget = entry.value(context, source);
            (built[entry.key] ??= []).add(widget);
            // These picker factories are exercised using the real runtime's
            // DataSource and their produced callbacks below. Their independently
            // tested Flutter layout needs a finite height in a scroll view.
            if (widget is CupertinoPicker ||
                widget is CupertinoDatePicker ||
                widget is CupertinoTimerPicker) {
              return SizedBox(height: 200, child: widget);
            }
            return widget;
          },
      }),
    );
  }
  runtime.update(_root, parseLibraryFile(fixture));
  final data = DynamicContent({'widthFactor': 1.5});
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      home: Scaffold(
        body: RemoteWidget(
          runtime: runtime,
          widget: const FullyQualifiedWidgetName(_root, 'Main'),
          data: data,
          onEvent: (name, arguments) => events.add([name, arguments]),
        ),
      ),
    ),
  );
  await tester.pump();
  expect(tester.takeException(), isNull);
  return (built: built, events: events, runtime: runtime, data: data);
}

List<Object?> _snapshot(Map<String, List<Widget>> built) {
  T last<T extends Widget>(String name) => built[name]!.last as T;
  final align = last<Align>('Align');
  final padding = last<Padding>('Padding');
  final text = built['Text']!.whereType<Text>().firstWhere(
        (widget) => widget.data == 'preserve',
      );
  final checkbox = last<Checkbox>('Checkbox');
  final slider = last<Slider>('Slider');
  final field = last<TextField>('TextField');
  return [
    align.widthFactor,
    align.heightFactor,
    align.alignment,
    padding.padding,
    text.data,
    text.style?.fontSize,
    text.maxLines,
    checkbox.value,
    checkbox.activeColor,
    last<CupertinoSwitch>('CupertinoSwitch').value,
    slider.value,
    slider.min,
    slider.max,
    slider.divisions,
    field.obscureText,
    field.maxLines,
    field.maxLength,
    field.clipBehavior,
    last<CupertinoTextField>('CupertinoTextField').placeholder,
  ];
}

void _fire(Map<String, List<Widget>> built) {
  T last<T extends Widget>(String name) => built[name]!.last as T;
  final checkbox = last<Checkbox>('Checkbox');
  checkbox.onChanged!(true);
  checkbox.onChanged!(null);
  last<CupertinoSwitch>('CupertinoSwitch').onChanged!(false);
  last<Slider>('Slider').onChanged!(0.6);
  last<TextField>('TextField').onChanged!('hello');
  last<TextField>('TextField').onSubmitted!('done');
  last<CupertinoTextField>('CupertinoTextField').onChanged!('cupertino');
  last<CupertinoTextField>('CupertinoTextField').onSubmitted!('finished');
  last<RestageDropdown<String>>('RestageDropdownString').onChanged!(null);
  last<RestageSegmentedButton<String>>('RestageSegmentedButtonString')
      .onChanged!(<String>['a']);
  last<CupertinoPicker>('CupertinoPicker').onSelectedItemChanged!(0);
  last<CupertinoDatePicker>('CupertinoDatePicker')
      .onDateTimeChanged(DateTime.utc(2024, 2, 29, 12));
  last<CupertinoTimerPicker>('CupertinoTimerPicker')
      .onTimerDurationChanged(const Duration(hours: 2, minutes: 3));
}

void main() {
  test('every factory and name remains installed', () {
    final old = _factories(true);
    final live = _factories(false);
    expect(live.keys, old.keys);
    expect(old.values.fold<int>(0, (sum, map) => sum + map.length), 119);
    for (final key in old.keys) {
      expect(live[key]!.keys, old[key]!.keys);
    }
  });

  testWidgets(
    'real RFW factories preserve values, updates and callback payloads',
    (tester) async {
      final original = await _pump(tester, original: true);
      final oldSnapshot = _snapshot(original.built);
      _fire(original.built);
      final oldEvents = List<Object?>.of(original.events);
      expect(oldEvents.length, 15);
      expect(oldEvents.first, [
        'checkbox',
        {'fixed': 'yes', 'value': true},
      ]);
      expect(oldEvents[2], [
        'checkbox',
        {'fixed': 'yes', 'value': null},
      ]);
      expect(oldSnapshot.take(3), [1.5, 2.0, const Alignment(1, -1)]);
      original.data.update('widthFactor', 2.5);
      await tester.pump();
      final oldUpdated = _snapshot(original.built);
      expect(oldUpdated.first, 2.5);
      await tester.pumpWidget(const SizedBox());
      original.runtime.dispose();

      final live = await _pump(tester, original: false);
      expect(_snapshot(live.built), oldSnapshot);
      _fire(live.built);
      expect(live.events, oldEvents);
      live.data.update('widthFactor', 2.5);
      await tester.pump();
      expect(_snapshot(live.built), oldUpdated);
      await tester.pumpWidget(const SizedBox());
      live.runtime.dispose();
    },
  );

  testWidgets('absent callbacks stay disabled and scalar defaults stay exact', (
    tester,
  ) async {
    const fixture = '''
import restage.core;
import restage.material;
widget Main = Column(children: [Checkbox(value: true), TextField()]);
''';
    for (final original in [true, false]) {
      final run = await _pump(tester, original: original, fixture: fixture);
      final checkbox = run.built['Checkbox']!.last as Checkbox;
      final field = run.built['TextField']!.last as TextField;
      expect(checkbox.onChanged, isNull);
      expect(field.onChanged, isNull);
      expect(field.onSubmitted, isNull);
      expect(field.maxLines, 1);
      expect(field.obscureText, false);
      await tester.pumpWidget(const SizedBox());
      run.runtime.dispose();
    }
  });
}
