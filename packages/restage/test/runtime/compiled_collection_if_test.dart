import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/measurement/measurement_rfw_presentation.dart';
import 'package:restage/src/runtime/context_data.dart';
import 'package:restage_core/restage_core.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:rfw/rfw.dart';

void main() {
  testWidgets(
      'compiled collection-if filters children and retains source items',
      (tester) async {
    const libraryName = LibraryName(['test', 'filtered']);
    final library = decodeLibraryBlob(
      File('test/fixtures/collection_if/filtered_rows.rfw').readAsBytesSync(),
    );
    final runtime = Runtime()
      ..update(const LibraryName(['restage', 'core']), buildCoreWidgetLibrary())
      ..update(libraryName, library);
    installMeasurementRfwPresentationLibrary(runtime);
    addTearDown(runtime.dispose);
    final events = <Map<String, Object?>>[];
    final data = DynamicContent({
      'context': ContextSnapshot.of({
        'rows': [
          _row('monthly', 'Monthly', visible: false),
          _row('annual', 'Annual', visible: true),
          _row('lifetime', 'Lifetime', visible: false),
        ],
      }).value,
    });
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RemoteWidget(
        runtime: runtime,
        data: data,
        widget:
            FullyQualifiedWidgetName(libraryName, library.widgets.first.name),
        onEvent: (name, arguments) {
          if (name == 'pick') events.add(arguments);
        },
      ),
    ));

    List<String> labels() => tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data!)
        .toList();
    int childCount() => tester
        .widget<Column>(find.byWidgetPredicate((widget) => widget is Column))
        .children
        .length;

    expect(tester.takeException(), isNull);
    expect(labels(), ['Before', 'Annual', 'After']);
    expect(childCount(), 3);
    await tester.tap(find.text('Annual'));
    expect(events.single['value'], 'annual');
    expect(events.single[kMeasurementPublicationItemArgumentKeyV1], '2');

    data.update(
        'context',
        ContextSnapshot.of({
          'rows': [
            _row('monthly', 'Monthly', visible: true),
            _row('annual', 'Annual', visible: true),
            _row('lifetime', 'Lifetime', visible: true),
          ],
        }).value);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(labels(), ['Before', 'Monthly', 'Annual', 'Lifetime', 'After']);
    expect(childCount(), 5);
    await tester.tap(find.text('Lifetime'));
    expect(events.last['value'], 'lifetime');
    expect(events.last[kMeasurementPublicationItemArgumentKeyV1], '3');

    data.update(
        'context',
        ContextSnapshot.of({
          'rows': [_row('annual', 'Annual', visible: false)],
        }).value);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(labels(), ['Before', 'After']);
    expect(childCount(), 2);
  });
}

Map<String, Object?> _row(
  String id,
  String title, {
  required bool visible,
}) =>
    {
      'id': id,
      'title': title,
      'visible': visible,
    };
