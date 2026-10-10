import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart';

const _core = LibraryName(['restage', 'core']);
const _local = LibraryName(['local']);
const _remote = LibraryName(['remote']);

Runtime _runtime(String source) => Runtime()
  ..update(_core, buildCoreWidgetLibrary())
  ..update(
    _local,
    LocalWidgetLibrary({
      'Label': (context, source) => GestureDetector(
            onTap: source.voidHandler(const ['onTap']),
            child: SizedBox(
              height: 20,
              child: Text(source.v<String>(const ['text'])!),
            ),
          ),
    }),
  )
  ..update(_remote, parseLibraryFile(source));

Widget _mount(
  Runtime runtime,
  DynamicContent data, {
  RemoteEventHandler? onEvent,
}) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: RemoteWidget(
        runtime: runtime,
        data: data,
        widget: const FullyQualifiedWidgetName(_remote, 'Main'),
        onEvent: onEvent,
      ),
    );

void main() {
  testWidgets('nested loops preserve visible children and bound events',
      (tester) async {
    final events = <(String, DynamicMap)>[];
    final data = DynamicContent({
      'items': [
        {'keep': false, 'label': 'first', 'index': 1},
        {'keep': true, 'label': 'second', 'index': 2},
        {'keep': false, 'label': 'third', 'index': 3},
      ],
    });
    final runtime = _runtime('''
import restage.core;
import local;
widget Main = Column(spacing: 7.0, children: [
  Label(text: "before"),
  ...for item in data.items: [
    ...for presence in switch item.keep {true: [0], false: []}:
      Label(text: item.label, onTap: event "select" {index: item.index}),
  ],
  Label(text: "after"),
]);
''');
    addTearDown(runtime.dispose);

    await tester.pumpWidget(_mount(
      runtime,
      data,
      onEvent: (name, arguments) => events.add((name, arguments)),
    ));
    expect(tester.takeException(), isNull);
    expect(
      tester.widget<RestageColumn>(find.byType(RestageColumn)).children,
      hasLength(3),
    );
    expect(find.text('first'), findsNothing);
    expect(find.text('third'), findsNothing);
    expect(
      tester.getTopLeft(find.text('second')).dy -
          tester.getTopLeft(find.text('before')).dy,
      27,
    );
    expect(
      tester.getTopLeft(find.text('after')).dy -
          tester.getTopLeft(find.text('second')).dy,
      27,
    );
    await tester.tap(find.text('second'));
    expect(events.single.$1, 'select');
    expect(events.single.$2, {'index': 2});

    data.update('items', [
      {'keep': true, 'label': 'third', 'index': 3},
      {'keep': true, 'label': 'first', 'index': 1},
    ]);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('second'), findsNothing);
    expect(
      tester.widgetList<Text>(find.byType(Text)).map((text) => text.data),
      ['before', 'third', 'first', 'after'],
    );
    await tester.tap(find.text('first'));
    expect(events.last.$1, 'select');
    expect(events.last.$2, {'index': 1});

    data.update('items', [
      {'keep': false, 'label': 'first', 'index': 1},
    ]);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(
      tester.widget<RestageColumn>(find.byType(RestageColumn)).children,
      hasLength(2),
    );
    expect(find.text('first'), findsNothing);
    expect(
      tester.getTopLeft(find.text('after')).dy -
          tester.getTopLeft(find.text('before')).dy,
      27,
    );
  });

  testWidgets('ordinary widget-list slots flatten nested and empty lists',
      (tester) async {
    final runtime = _runtime('''
import restage.core;
import local;
widget Main = Wrap(children: [
  [],
  Label(text: "first"),
  [[], [Label(text: "second"), [], Label(text: "third")]],
  [],
]);
''');
    addTearDown(runtime.dispose);

    await tester.pumpWidget(_mount(runtime, DynamicContent()));
    expect(tester.takeException(), isNull);
    expect(
      tester.widget<RestageWrap>(find.byType(RestageWrap)).children,
      hasLength(3),
    );
    expect(
      tester.widgetList<Text>(find.byType(Text)).map((text) => text.data),
      ['first', 'second', 'third'],
    );
  });

  for (final value in ['42', '{invalid: true}', '[[42]]']) {
    testWidgets('malformed widget lists retain RFW errors ($value)',
        (tester) async {
      final runtime = _runtime('''
import restage.core;
widget Main = SingleChildScrollView(child: Column(children: $value));
''');
      addTearDown(runtime.dispose);

      await tester.pumpWidget(_mount(runtime, DynamicContent()));
      expect(tester.takeException(), contains('Not a widget'));
      expect(find.byType(ErrorWidget), findsOneWidget);
      expect(
        tester.widget<RestageColumn>(find.byType(RestageColumn)).children,
        hasLength(1),
      );
    });
  }

  for (final arguments in ['', 'children: []', 'children: [[], [[]]]']) {
    testWidgets('empty widget-list slots have no children ($arguments)',
        (tester) async {
      final runtime = _runtime('''
import restage.core;
widget Main = Column($arguments);
''');
      addTearDown(runtime.dispose);

      await tester.pumpWidget(_mount(runtime, DynamicContent()));
      expect(tester.takeException(), isNull);
      expect(
        tester.widget<RestageColumn>(find.byType(RestageColumn)).children,
        isEmpty,
      );
    });
  }
}
