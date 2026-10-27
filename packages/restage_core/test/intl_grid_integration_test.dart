import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' as i;
import 'package:restage_core/restage_core.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart';

void main() {
  testWidgets(
      'authored Intl Grid predicate retains lexical theme device locale after updates',
      (tester) async {
    const items = ['a', 'b'];
    final runtime = Runtime()
      ..update(const LibraryName(['restage', 'core']), buildCoreWidgetLibrary())
      ..update(
          const LibraryName(['test']),
          parseLibraryFile(File('test/fixtures/intl_grid_compiled.rfwtxt')
              .readAsStringSync()));
    addTearDown(runtime.dispose);
    final data = DynamicContent({
      'context': {'items': items},
      // Deliberately different from the actual callback's inherited scope.
      'device': {'boldText': true, 'languageCode': 'xx'},
    });
    final remote = RemoteWidget(
        runtime: runtime,
        data: data,
        widget: const FullyQualifiedWidgetName(LibraryName(['test']), 'Root'));
    final native = LayoutBuilder(
        builder: (outer, constraints) => GridView.builder(
              primary: false,
              shrinkWrap: true,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2, mainAxisExtent: 40),
              itemCount: items.length,
              itemBuilder: (_, index) =>
                  Text(items[index], key: ValueKey<String>(items[index])),
              findChildIndexCallback: (key) {
                final id = (key as ValueKey<String>).value;
                final index = items.indexWhere((item) =>
                    i.Intl.select(
                      Theme.of(outer).brightness == Brightness.light &&
                              !MediaQuery.of(outer).boldText
                          ? Localizations.localeOf(outer).languageCode
                          : 'hidden',
                      {'fr': item, 'other': 'hidden'},
                    ) ==
                    id);
                return index < 0 ? null : index;
              },
            ));
    final content = Center(
        child: SizedBox(
            width: 320,
            child: Column(
                mainAxisSize: MainAxisSize.min, children: [native, remote])));
    for (final (brightness, bold, locale, expected)
        in <(Brightness, bool, String, int?)>[
      (Brightness.light, false, 'fr', 1),
      (Brightness.dark, false, 'fr', null),
      (Brightness.light, true, 'fr', null),
      (Brightness.light, false, 'ar', null),
      (Brightness.light, false, 'fr', 1),
    ]) {
      await tester.pumpWidget(Localizations(
          locale: Locale(locale),
          delegates: const [DefaultWidgetsLocalizations.delegate],
          child: Directionality(
              textDirection: TextDirection.ltr,
              child: MediaQuery(
                  data: MediaQueryData(boldText: bold),
                  child: Theme(
                      data: ThemeData(brightness: brightness),
                      child: content)))));
      await tester.pump();
      final grids = tester.widgetList<GridView>(find.byType(GridView)).toList();
      expect(grids, hasLength(2));
      final callbacks = [
        for (final grid in grids)
          (grid.childrenDelegate as SliverChildBuilderDelegate)
              .findChildIndexCallback!
      ];
      final nativeIndex = callbacks[0](const ValueKey<String>('b'));
      expect(nativeIndex, expected, reason: '$brightness/$bold/$locale native');
      expect(callbacks[1](const ValueKey<String>('b')), nativeIndex,
          reason: '$brightness/$bold/$locale remote');
      expect(callbacks[1](const ValueKey<String>('missing')), isNull);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
