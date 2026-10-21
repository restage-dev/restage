import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart' as core;
import 'package:restage_material/restage_material.dart';
import 'package:rfw/formats.dart' show parseLibraryFile;
import 'package:rfw/rfw.dart' hide Switch;

const _rootLibrary = LibraryName(['test']);

typedef _Layout = ({Axis axis, bool reverse});

const _layouts = <_Layout>[
  (axis: Axis.vertical, reverse: false),
  (axis: Axis.vertical, reverse: true),
  (axis: Axis.horizontal, reverse: false),
];

Widget _native(int? depth, _Layout layout) => Scaffold(
      appBar: AppBar(
        title: const Text('Bar'),
        scrolledUnderElevation: 4,
        notificationPredicate: depth == null
            ? defaultScrollNotificationPredicate
            : (notification) => notification.depth == depth,
      ),
      body: ListView(
        children: [
          SizedBox(
            height: 200,
            child: ListView(
              scrollDirection: layout.axis,
              reverse: layout.reverse,
              children: [
                for (var i = 0; i < 30; i++)
                  SizedBox(width: 50, height: 50, child: Text('inner $i')),
              ],
            ),
          ),
          for (var i = 0; i < 30; i++)
            SizedBox(height: 50, child: Text('outer $i')),
        ],
      ),
    );

Widget _delivered(String predicate, _Layout layout, DynamicContent data) {
  final runtime = Runtime()
    ..update(
        const LibraryName(['restage', 'core']), core.buildCoreWidgetLibrary())
    ..update(
      const LibraryName(['restage', 'material']),
      buildMaterialWidgetLibrary(),
    )
    ..update(_rootLibrary, parseLibraryFile('''
import restage.core;
import restage.material;
widget Screen = Scaffold(
  appBar: AppBar(
    title: Text(text: "Bar"),
    scrolledUnderElevation: 4.0,
    $predicate
  ),
  body: ListView(
    children: [
      SizedBox(
        height: 200.0,
        child: ListView(
          scrollDirection: "${layout.axis.name}",
          reverse: ${layout.reverse},
          children: [
            ...for i in data.items:
              SizedBox(width: 50.0, height: 50.0, child: Text(text: i.inner)),
          ],
        ),
      ),
      ...for i in data.items:
        SizedBox(height: 50.0, child: Text(text: i.outer)),
    ],
  ),
);
'''));
  return RemoteWidget(
    runtime: runtime,
    data: data,
    widget: const FullyQualifiedWidgetName(_rootLibrary, 'Screen'),
  );
}

DynamicContent _data([Map<String, Object> extra = const {}]) => DynamicContent({
      'items': [
        for (var i = 0; i < 30; i++) {'inner': 'inner $i', 'outer': 'outer $i'},
      ],
      ...extra,
    });

/// The bar's elevation after each drag on the nested list, then the outer one.
Future<List<double>> _elevations(
  WidgetTester tester,
  Widget screen,
  _Layout layout,
) async {
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  double elevation() => tester
      .widget<Material>(find
          .descendant(of: find.byType(AppBar), matching: find.byType(Material))
          .first)
      .elevation;
  final forward = layout.axis == Axis.vertical
      ? Offset(0, layout.reverse ? 120 : -120)
      : const Offset(-120, 0);
  final inner = tester.getCenter(find.byType(Scrollable).at(1));
  final outer = tester.getRect(find.byType(Scrollable).first).bottomCenter -
      const Offset(0, 100);
  final elevations = <double>[elevation()];
  for (final (start, offset) in [
    (inner, forward),
    (inner, -forward),
    (outer, const Offset(0, -120)),
    (outer, const Offset(0, 120)),
  ]) {
    await tester.dragFrom(start, offset);
    await tester.pumpAndSettle();
    elevations.add(elevation());
  }
  return elevations;
}

void main() {
  for (final layout in _layouts) {
    final label = '${layout.axis.name}${layout.reverse ? ' reversed' : ''}';
    for (final depth in [null, 0, 1]) {
      testWidgets('depth $depth predicate matches native ($label)',
          (tester) async {
        final native =
            await _elevations(tester, _native(depth, layout), layout);
        final delivered = await _elevations(
          tester,
          _delivered(
            depth == null ? '' : 'notificationPredicate: $depth,',
            layout,
            _data(),
          ),
          layout,
        );
        expect(delivered, native);
        if (layout.axis == Axis.horizontal) {
          expect(native[1], 0.0);
        } else if (!layout.reverse) {
          expect(native[1], depth == 1 ? 4.0 : 0.0);
          expect(native[3], depth == 1 ? 0.0 : 4.0);
        }
      });
    }

    testWidgets('runtime depth matches native ($label)', (tester) async {
      final native = await _elevations(tester, _native(1, layout), layout);
      final delivered = await _elevations(
        tester,
        _delivered(
          'notificationPredicate: data.depth,',
          layout,
          _data({'depth': 1}),
        ),
        layout,
      );
      expect(delivered, native);
    });
  }
}
