// How rfw keeps a stateful declaration's state across rebuilds. The compiler
// delivers a stateful widget only where these match Flutter.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart';

const _library = '''
import core;
widget Tile { on: false } = GestureDetector(
  onTap: set state.on = switch state.on { true: false, false: true },
  child: SizedBox(
    width: 100.0,
    height: 20.0,
    child: Text(
      text: [args.label, switch state.on { true: "+on", false: "-off" }],
      textDirection: "ltr",
    ),
  ),
);
widget Plain = Column(children: [
  Tile(label: data.context.label),
  Text(text: data.context.other, textDirection: "ltr"),
]);
widget Shifted = Column(children: [
  ...for extra in data.context.extra: Text(text: extra, textDirection: "ltr"),
  Tile(label: "t"),
]);
widget Looped = Column(children: [
  ...for item in data.context.items: Tile(label: item),
  Text(text: data.context.other, textDirection: "ltr"),
]);
''';

Future<DynamicContent> _pump(
  WidgetTester tester,
  String root,
  Map<String, Object> context,
) async {
  final runtime = Runtime()
    ..update(const LibraryName(['core']), createCoreWidgets())
    ..update(const LibraryName(['main']), parseLibraryFile(_library));
  final data = DynamicContent({'context': context});
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: RemoteWidget(
        runtime: runtime,
        data: data,
        widget: FullyQualifiedWidgetName(const LibraryName(['main']), root),
      ),
    ),
  );
  return data;
}

List<String> _texts(WidgetTester tester) => [
      for (final text in tester.widgetList<RichText>(find.byType(RichText)))
        text.text.toPlainText(),
    ];

void main() {
  testWidgets('a plain call site keeps its state when its argument changes', (
    tester,
  ) async {
    final data = await _pump(tester, 'Plain', {'label': 'a', 'other': 'x'});
    await tester.tap(find.text('a-off'));
    await tester.pump();
    expect(_texts(tester), ['a+on', 'x']);

    data.update('context', {'label': 'b', 'other': 'x'});
    await tester.pump();
    expect(_texts(tester), ['b+on', 'x']);
  });

  testWidgets(
      'a declaration in a loop over context data starts its state '
      'again when another context value changes', (tester) async {
    final data = await _pump(tester, 'Looped', {
      'items': ['a', 'b'],
      'other': 'x',
    });
    await tester.tap(find.text('a-off'));
    await tester.pump();
    expect(_texts(tester), ['a+on', 'b-off', 'x']);

    data.update('context', {
      'items': ['a', 'b'],
      'other': 'y',
    });
    await tester.pump();
    // Flutter would keep 'a+on'. The compiler keeps such a widget in the
    // app until the runtime can keep it too.
    expect(_texts(tester), ['a-off', 'b-off', 'y']);
  });

  testWidgets(
      'a declaration after a sibling whose count changes starts its '
      'state again', (tester) async {
    final data = await _pump(tester, 'Shifted', {'extra': <Object>[]});
    await tester.tap(find.text('t-off'));
    await tester.pump();
    expect(_texts(tester), ['t+on']);

    data.update('context', {
      'extra': ['B'],
    });
    await tester.pump();
    // Flutter would keep 't+on'. The compiler keeps such a widget in the
    // app until the runtime can keep it too.
    expect(_texts(tester), ['B', 't-off']);
  });
}
