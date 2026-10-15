import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/render_host/render_core.dart';
import 'package:rfw/rfw.dart';

const String _path = '["main","children",0]';

void main() {
  late GlobalKey frameKey;
  late GeometryRegistry registry;
  late LocalWidgetBuilder marker;

  setUp(() {
    frameKey = GlobalKey();
    registry = GeometryRegistry(
      frameRenderBox: () =>
          frameKey.currentContext?.findRenderObject() as RenderBox?,
    );
    marker = buildMarkerWidgetLibrary(registry).widgets.values.single;
  });

  tearDown(() => registry.dispose());

  Widget frame(List<Widget> children) => Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            key: frameKey,
            width: 100,
            height: 300,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ),
      );

  Widget instance(
    WidgetTester tester, {
    required double height,
    Object? item,
    Key? key,
  }) =>
      KeyedSubtree(
        key: key,
        child: Builder(
          builder: (context) => marker(
            context,
            _Source(
              path: _path,
              item: item,
              childWidget: SizedBox(width: 10, height: height),
            ),
          ),
        ),
      );

  testWidgets('one path drawn three times reports three rects in order',
      (tester) async {
    await tester.pumpWidget(frame(<Widget>[
      instance(tester, height: 10),
      instance(tester, height: 20),
      instance(tester, height: 30),
    ]));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(registry.registeredPathCount, 1);
    expect(
      registry.captureInstances()[_path]!.map((instance) => instance.rect),
      const <Rect>[
        Rect.fromLTWH(0, 0, 10, 10),
        Rect.fromLTWH(0, 10, 10, 20),
        Rect.fromLTWH(0, 30, 10, 30),
      ],
    );
    expect(registry.capture()[_path], const Rect.fromLTWH(0, 0, 10, 10));
  });

  testWidgets('each instance carries the item its marker names',
      (tester) async {
    await tester.pumpWidget(frame(<Widget>[
      instance(tester, height: 10, item: 'basic'),
      instance(tester, height: 10, item: 2),
      instance(tester, height: 10),
    ]));
    await tester.pump();

    expect(
      registry.captureInstances()[_path]!.map((instance) => instance.item),
      <String?>['basic', '2', null],
    );
  });

  testWidgets('instances follow the drawn order after a reorder',
      (tester) async {
    await tester.pumpWidget(frame(<Widget>[
      instance(tester, height: 10, item: 'a', key: const ValueKey('a')),
      instance(tester, height: 20, item: 'b', key: const ValueKey('b')),
    ]));
    await tester.pump();
    await tester.pumpWidget(frame(<Widget>[
      instance(tester, height: 20, item: 'b', key: const ValueKey('b')),
      instance(tester, height: 10, item: 'a', key: const ValueKey('a')),
    ]));
    await tester.pump();

    expect(
      registry.captureInstances()[_path]!.map((instance) => instance.item),
      <String?>['b', 'a'],
    );
    expect(registry.capture()[_path], const Rect.fromLTWH(0, 0, 10, 20));
  });

  testWidgets('reveal scrolls an instance below the fold into view',
      (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            key: frameKey,
            width: 100,
            height: 100,
            child: SingleChildScrollView(
              child: Column(
                children: <Widget>[
                  for (final item in const <String>['a', 'b', 'c'])
                    instance(tester, height: 80, item: item),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(registry.captureInstances()[_path]![2].rect.top, 160);

    expect(registry.reveal(_path, index: 2), isTrue);
    await tester.pumpAndSettle();

    final revealed = registry.captureInstances()[_path]![2].rect;
    expect(revealed.top, greaterThanOrEqualTo(0));
    expect(revealed.bottom, lessThanOrEqualTo(100));
    expect(registry.reveal('["missing"]'), isFalse);
  });

  testWidgets('a scroll view clips instances without dropping them',
      (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            key: frameKey,
            width: 100,
            height: 100,
            child: SingleChildScrollView(
              child: Column(
                children: <Widget>[
                  for (final item in const <String>['a', 'b', 'c'])
                    instance(tester, height: 80, item: item),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final instances = registry.captureInstances()[_path]!;
    expect(instances.map((instance) => instance.rect), const <Rect>[
      Rect.fromLTWH(45, 0, 10, 80),
      Rect.fromLTWH(45, 80, 10, 80),
      Rect.fromLTWH(45, 160, 10, 80),
    ]);
    expect(instances.map((instance) => instance.visibleRect), const <Rect?>[
      Rect.fromLTWH(45, 0, 10, 80),
      Rect.fromLTWH(45, 80, 10, 20),
      null,
    ]);
  });

  testWidgets('a scrolled list hit-tests the first instance still showing',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            key: frameKey,
            width: 100,
            height: 100,
            child: SingleChildScrollView(
              controller: controller,
              child: Column(
                children: <Widget>[
                  for (final item in const <String>['a', 'b', 'c'])
                    instance(tester, height: 80, item: item),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    controller.jumpTo(120);
    await tester.pump();
    await tester.pump();

    final snapshot = GeometrySnapshot(
      epoch: 0,
      generation: 0,
      rects: registry.capture(),
      instances: registry.captureInstances(),
    );
    expect(snapshot.instances[_path]!.first.visibleRect, isNull);
    expect(snapshot.visibleRects[_path], const Rect.fromLTWH(45, 0, 10, 40));
  });

  testWidgets('removing one instance keeps the others', (tester) async {
    final snapshots = <Map<String, List<GeometryInstance>>>[];
    registry.instanceSnapshots.listen(snapshots.add);
    await tester.pumpWidget(frame(<Widget>[
      instance(tester, height: 10, item: 'a', key: const ValueKey('a')),
      instance(tester, height: 20, item: 'b', key: const ValueKey('b')),
    ]));
    await tester.pump();
    await tester.pumpWidget(frame(<Widget>[
      instance(tester, height: 20, item: 'b', key: const ValueKey('b')),
    ]));
    await tester.pump();

    expect(registry.registeredPathCount, 1);
    expect(
      snapshots.last[_path],
      const <GeometryInstance>[
        GeometryInstance(Rect.fromLTWH(0, 0, 10, 20), item: 'b'),
      ],
    );
  });
}

final class _Source implements DataSource {
  const _Source({required this.path, required this.childWidget, this.item});

  final String path;
  final Object? item;
  final Widget childWidget;

  @override
  T? v<T extends Object>(List<Object> argsKey) {
    final value = switch (argsKey) {
      ['path'] => path,
      ['item'] => item,
      _ => null,
    };
    return value is T ? value : null;
  }

  @override
  Widget child(List<Object> argsKey) => childWidget;

  @override
  Widget? optionalChild(List<Object> argsKey) => childWidget;

  @override
  List<Widget> childList(List<Object> argsKey) => const <Widget>[];

  @override
  bool isList(List<Object> argsKey) => false;

  @override
  bool isMap(List<Object> argsKey) => false;

  @override
  int length(List<Object> argsKey) => 0;

  @override
  Widget builder(List<Object> argsKey, DynamicMap builderArg) => childWidget;

  @override
  Widget? optionalBuilder(List<Object> argsKey, DynamicMap builderArg) => null;

  @override
  VoidCallback? voidHandler(
    List<Object> argsKey, [
    DynamicMap? extraArguments,
  ]) =>
      null;

  @override
  T? handler<T extends Function>(
    List<Object> argsKey,
    HandlerGenerator<T> generator,
  ) =>
      null;
}
