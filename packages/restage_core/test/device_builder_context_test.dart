import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart' as rfw;
import 'package:rfw/rfw.dart';

const _paths = <String, ValueType>{
  'viewInsetsTop': ValueType.real,
  'viewInsetsBottom': ValueType.real,
  'viewInsetsLeft': ValueType.real,
  'viewInsetsRight': ValueType.real,
  'boldText': ValueType.boolean,
  'disableAnimations': ValueType.boolean,
  'accessibleNavigation': ValueType.boolean,
  'highContrast': ValueType.boolean,
};

Map<String, Object> _nativeValues(MediaQueryData media) => {
      'viewInsetsTop': media.viewInsets.top,
      'viewInsetsBottom': media.viewInsets.bottom,
      'viewInsetsLeft': media.viewInsets.left,
      'viewInsetsRight': media.viewInsets.right,
      'boldText': media.boldText,
      'disableAnimations': media.disableAnimations,
      'accessibleNavigation': media.accessibleNavigation,
      'highContrast': media.highContrast,
    };

String _label(MediaQueryData media) => _nativeValues(media).values.join('|');

void main() {
  for (final grid in [false, true]) {
    testWidgets(
        grid
            ? 'grid descendant device flags and insets match native across updates'
            : 'descendant device flags and insets match native across updates',
        (tester) async {
      const rootMedia = MediaQueryData(
        viewInsets: EdgeInsets.fromLTRB(101, 102, 103, 104),
      );
      const first = MediaQueryData(
        viewInsets: EdgeInsets.fromLTRB(1, 2, 3, 4),
        boldText: true,
        accessibleNavigation: true,
      );
      const second = MediaQueryData(
        viewInsets: EdgeInsets.fromLTRB(11, 12, 13, 14),
        disableAnimations: true,
        highContrast: true,
      );
      final local = ValueNotifier(first);
      addTearDown(local.dispose);
      final itemCount = ValueNotifier(1);
      addTearDown(itemCount.dispose);
      final nodes = <ValueNode>[];
      final strings = <int>[];
      for (final entry in _paths.entries) {
        if (strings.isNotEmpty) {
          strings.add(nodes.length);
          nodes.add(const ValueNode('literal', ValueType.string, value: '|'));
        }
        final parameter = nodes.length;
        nodes.add(ValueNode('parameter', entry.value,
            name: 'context:device:${entry.key}'));
        strings.add(nodes.length);
        nodes.add(ValueNode('string', ValueType.string, inputs: [parameter]));
      }
      final result = nodes.length;
      nodes.add(ValueNode('concat', ValueType.string, inputs: strings));
      final program = BuilderProgram(
        values: ValueProgram(
          nodes: nodes,
          root: result,
          parameters: {
            for (final entry in _paths.entries)
              'context:device:${entry.key}': entry.value,
          },
        ),
        result: BuilderResult.body(0, values: {'label': result}),
        bodyCount: 1,
        nullableResult: grid,
      );
      Widget scoped(Widget child) => ValueListenableBuilder<MediaQueryData>(
            valueListenable: local,
            child: child,
            builder: (context, media, child) =>
                MediaQuery(data: media, child: child!),
          );
      final callbackWidget = grid
          ? 'GridViewBuilder(primary:false,shrinkWrap:true,itemCount:data.count,gridDelegate:{_s:"SliverGridDelegateWithFixedCrossAxisCount",crossAxisCount:1,mainAxisExtent:30.0},itemBuilder:'
          : 'LayoutBuilder(builder:';
      final runtime = Runtime()
        ..update(
            const LibraryName(['restage', 'core']), buildCoreWidgetLibrary())
        ..update(
            const LibraryName(['test', 'native']),
            LocalWidgetLibrary({
              'LocalMedia': (context, source) =>
                  scoped(source.child(['child'])),
            }))
        ..update(const LibraryName(['test']), rfw.parseLibraryFile('''
import restage.core;
import test.native;
widget Root = LocalMedia(child: $callbackWidget
  __RestageBuilderContinuation(version:1,
    program:${jsonEncode(program.encode())}, captures:{},
    bodies:[(frame)=>Text(text:frame.values.label)])));
'''));
      addTearDown(runtime.dispose);
      final data = DynamicContent({
        'device': _nativeValues(rootMedia),
        'count': 1,
      });
      final remote = RemoteWidget(
        runtime: runtime,
        data: data,
        widget: const FullyQualifiedWidgetName(LibraryName(['test']), 'Root'),
      );
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: rootMedia,
          child: Center(
            child: SizedBox(
              width: 600,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                remote,
                scoped(grid
                    ? ValueListenableBuilder<int>(
                        valueListenable: itemCount,
                        builder: (context, count, child) => GridView.builder(
                          primary: false,
                          shrinkWrap: true,
                          itemCount: count,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 1,
                            mainAxisExtent: 30,
                          ),
                          itemBuilder: (context, index) =>
                              Text(_label(MediaQuery.of(context))),
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) =>
                            Text(_label(MediaQuery.of(context))))),
              ]),
            ),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(find.text(_label(first)), findsNWidgets(2));
      expect(find.text(_label(rootMedia)), findsNothing);
      local.value = second;
      await tester.pump();
      if (grid) {
        await tester.pumpAndSettle();
        for (final element in find.byType(GridView).evaluate()) {
          expect(_nativeValues(MediaQuery.of(element)), _nativeValues(second),
              reason: 'Grid parent inherited scope updated');
        }
        for (final element in find.byType(SliverGrid).evaluate()) {
          expect(_nativeValues(MediaQuery.of(element)), _nativeValues(second),
              reason: 'Native callback inherited scope updated');
        }
      }
      expect(tester.takeException(), isNull);
      if (grid) {
        // Native Grid retains its built children after this inherited-only
        // change; RFW must match that behavior despite the updated scope.
        expect(find.text(_label(first)), findsNWidgets(2));
        expect(find.text(_label(second)), findsNothing);
        itemCount.value = 2;
        data.update('count', 2);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text(_label(first)), findsNothing);
        expect(find.text(_label(second)), findsNWidgets(4));
      } else {
        expect(find.text(_label(first)), findsNothing);
        expect(find.text(_label(second)), findsNWidgets(2));
      }
      expect(find.text(_label(rootMedia)), findsNothing);
    });
  }
}
