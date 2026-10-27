import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart';

void main() {
  testWidgets(
      'generated nested callbacks retain creation cells across callers and parent invocations',
      (tester) async {
    const remote = LibraryName(['lexical']);
    final runtime = Runtime()
      ..update(const LibraryName(['restage', 'core']), buildCoreWidgetLibrary())
      ..update(
          remote,
          parseLibraryFile(File('test/fixtures/lexical_callbacks.rfwtxt')
              .readAsStringSync()));
    addTearDown(runtime.dispose);
    final data = DynamicContent();
    Widget? extra;
    late StateSetter update;
    var leftWidth = 100.0;
    Widget content() => Directionality(
        textDirection: TextDirection.ltr,
        child: StatefulBuilder(builder: (context, setState) {
          update = setState;
          Widget surface(double width, String key) => SizedBox(
              width: width,
              height: 100,
              child: RemoteWidget(
                  key: ValueKey(key),
                  runtime: runtime,
                  data: data,
                  widget: const FullyQualifiedWidgetName(remote, 'Root')));
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            surface(leftWidth, 'left'),
            surface(300, 'right'),
            if (extra != null) extra!,
          ]);
        }));
    await tester.pumpWidget(content());
    expect(tester.takeException(), isNull);
    expect(find.text('102'), findsNWidgets(2));
    expect(find.text('302'), findsNWidgets(2));
    final builders =
        tester.widgetList<LayoutBuilder>(find.byType(LayoutBuilder)).toList();
    final rightContext = tester.element(find.text('302').first);
    extra =
        builders[1].builder(rightContext, const BoxConstraints(maxWidth: 300));
    update(() {});
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('103'), findsOneWidget);
    expect(find.text('302'), findsNWidgets(2));
    update(() {
      extra = null;
      leftWidth = 200;
    });
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('202'), findsNWidgets(2));
    expect(find.text('302'), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
