import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart';

Widget _native() => LayoutBuilder(builder: (context, constraints) {
      var calls = 0;
      final rows = [1, 2, 3].where((row) {
        calls++;
        return row > 1;
      });
      return Column(children: [
        for (final row in rows) Text('row$row'),
        ...[4, 5].map((row) {
          final label = row * 2;
          return Text('map$label');
        }).toList(),
        Text('calls$calls'),
      ]);
    });

void main() {
  testWidgets('authored filtered loops and widget map match native Column',
      (tester) async {
    const library = LibraryName(['collections']);
    final runtime = Runtime()
      ..update(const LibraryName(['restage', 'core']), buildCoreWidgetLibrary())
      ..update(
          library,
          parseLibraryFile(
              File('test/fixtures/collections.rfwtxt').readAsStringSync()));
    addTearDown(runtime.dispose);
    List<String?> labels() =>
        tester.widgetList<Text>(find.byType(Text)).map((w) => w.data).toList();
    Widget mount(Widget child) =>
        Directionality(textDirection: TextDirection.ltr, child: child);
    await tester.pumpWidget(mount(_native()));
    final expected = labels();
    expect(expected, ['row2', 'row3', 'map8', 'map10', 'calls3']);
    await tester.pumpWidget(mount(RemoteWidget(
        runtime: runtime,
        data: DynamicContent(),
        widget: const FullyQualifiedWidgetName(library, 'Root'))));
    expect(tester.takeException(), isNull);
    expect(labels(), expected);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
