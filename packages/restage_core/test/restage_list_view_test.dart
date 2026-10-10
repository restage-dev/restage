import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart';

const LibraryName _coreLibrary = LibraryName(<String>['restage', 'core']);
const LibraryName _rootLibrary = LibraryName(<String>['restage', 'surface']);

Widget _remote(String source, {DynamicContent? data}) {
  final Runtime runtime = Runtime()
    ..update(_coreLibrary, buildCoreWidgetLibrary())
    ..update(_rootLibrary, parseLibraryFile(source));
  return RemoteWidget(
    runtime: runtime,
    data: data ?? DynamicContent(const <String, Object?>{}),
    widget: const FullyQualifiedWidgetName(_rootLibrary, 'Surface'),
    onEvent: (_, __) {},
  );
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  EdgeInsets mediaPadding = EdgeInsets.zero,
}) async {
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(padding: mediaPadding),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(width: 400, height: 600, child: child),
        ),
      ),
    ),
  );
  await tester.pump();
}

Finder get _sliverList =>
    find.byWidgetPredicate((Widget widget) => widget is SliverList);

Finder get _sliverPadding =>
    find.byWidgetPredicate((Widget widget) => widget is SliverPadding);

void _traverseSemantics(SemanticsNode node) {
  node.getSemanticsData();
  node.visitChildren((SemanticsNode child) {
    _traverseSemantics(child);
    return true;
  });
}

RenderSliverList _listRender(WidgetTester tester) =>
    tester.renderObject<RenderSliverList>(_sliverList);

RenderSliverPadding _paddingRender(WidgetTester tester) =>
    tester.renderObject<RenderSliverPadding>(_sliverPadding);

class _UnknownCountListView extends RestageListView {
  _UnknownCountListView() : super();

  @override
  SliverChildDelegate get childrenDelegate =>
      SliverChildBuilderDelegate((_, __) => const SizedBox(height: 1));
}

class _RecordingController extends ScrollController {
  final List<double> corrections = <double>[];

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) =>
      _RecordingPosition(
        physics: physics,
        context: context,
        oldPosition: oldPosition,
        onCorrection: corrections.add,
      );
}

class _RecordingPosition extends ScrollPositionWithSingleContext {
  _RecordingPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
    required this.onCorrection,
  });

  final ValueChanged<double> onCorrection;

  @override
  void correctBy(double correction) {
    onCorrection(correction);
    super.correctBy(correction);
  }
}

typedef _PaddingSnapshot = ({
  SliverGeometry geometry,
  SliverGeometry childGeometry,
  SliverConstraints constraints,
  SliverConstraints childConstraints,
  Offset childPaintOffset,
  double childMainAxisPosition,
});

typedef _CorrectionSnapshot = ({
  List<double> corrections,
  double offset,
  Rect itemB,
  String semanticsLabel,
  _PaddingSnapshot padding,
});

_PaddingSnapshot _snapshot(WidgetTester tester) {
  final RenderSliverPadding render = _paddingRender(tester);
  final RenderSliver child = render.child!;
  return (
    geometry: render.geometry!,
    childGeometry: child.geometry!,
    constraints: render.constraints,
    childConstraints: child.constraints,
    childPaintOffset:
        (child.parentData! as SliverPhysicalParentData).paintOffset,
    childMainAxisPosition: render.childMainAxisPosition(child),
  );
}

Future<_CorrectionSnapshot> _runNativeListCorrection(
  WidgetTester tester, {
  required bool guarded,
}) async {
  final _RecordingController controller = _RecordingController();
  final DynamicContent data = DynamicContent(<String, Object?>{
    'leadingHeight': 10.0,
  });
  const String source = '''
import restage.core;
widget Surface = ListView(
  padding: [0.0, 0.0, 0.0, 0.0],
  children: [
    SizedBox(height: data.leadingHeight, child: Text(text: "A")),
    SizedBox(height: data.leadingHeight, child: Text(text: "B")),
    SizedBox(height: 400.0, child: Text(text: "0")),
    SizedBox(height: 400.0, child: Text(text: "1")),
    SizedBox(height: 400.0, child: Text(text: "2")),
    SizedBox(height: 400.0, child: Text(text: "3"))
  ]
);
''';

  Widget native(double leadingHeight) => ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          SizedBox(height: leadingHeight, child: const Text('A')),
          SizedBox(height: leadingHeight, child: const Text('B')),
          const SizedBox(height: 400, child: Text('0')),
          const SizedBox(height: 400, child: Text('1')),
          const SizedBox(height: 400, child: Text('2')),
          const SizedBox(height: 400, child: Text('3')),
        ],
      );

  Widget mounted(Widget child) => PrimaryScrollController(
        controller: controller,
        child: child,
      );

  await _pump(
    tester,
    mounted(guarded ? _remote(source, data: data) : native(10)),
  );
  expect(find.byType(RestageListView), guarded ? findsOneWidget : findsNothing);
  expect(_paddingRender(tester).child, isA<RenderSliverList>());
  expect(find.text('A'), findsOneWidget);
  expect(find.text('B'), findsOneWidget);

  controller.jumpTo(1200);
  await tester.pump();
  expect(find.text('A'), findsNothing);
  expect(find.text('B'), findsNothing);

  if (guarded) {
    data.update('leadingHeight', 200.0);
    await tester.pump();
  } else {
    await _pump(tester, mounted(native(200)));
  }
  expect(find.text('A'), findsNothing);
  expect(find.text('B'), findsNothing);

  controller.corrections.clear();
  controller.jumpTo(0);
  await tester.pump();

  final Finder itemB = find.ancestor(
    of: find.text('B'),
    matching: find.byWidgetPredicate(
      (Widget widget) => widget is SizedBox && widget.height == 200,
    ),
  );
  expect(itemB, findsOneWidget);
  final SemanticsNode semantics = tester.getSemantics(find.text('B'));
  final SemanticsNode? root = tester
      .binding.renderViews.single.owner?.semanticsOwner?.rootSemanticsNode;
  expect(root, isNotNull);
  _traverseSemantics(root!);
  final _CorrectionSnapshot result = (
    corrections: List<double>.of(controller.corrections),
    offset: controller.offset,
    itemB: tester.getRect(itemB),
    semanticsLabel: semantics.getSemanticsData().label,
    padding: _snapshot(tester),
  );

  await tester.pumpWidget(const SizedBox.shrink());
  controller.dispose();
  return result;
}

void _expectGeometryEquals(SliverGeometry actual, SliverGeometry expected) {
  expect(actual.scrollExtent, expected.scrollExtent);
  expect(actual.paintOrigin, expected.paintOrigin);
  expect(actual.paintExtent, expected.paintExtent);
  expect(actual.layoutExtent, expected.layoutExtent);
  expect(actual.maxPaintExtent, expected.maxPaintExtent);
  expect(
      actual.maxScrollObstructionExtent, expected.maxScrollObstructionExtent);
  expect(actual.hitTestExtent, expected.hitTestExtent);
  expect(actual.visible, expected.visible);
  expect(actual.hasVisualOverflow, expected.hasVisualOverflow);
  expect(actual.scrollOffsetCorrection, expected.scrollOffsetCorrection);
  expect(actual.cacheExtent, expected.cacheExtent);
}

void _expectUnrepairedGeometryEquals(
  SliverGeometry actual,
  SliverGeometry expected,
) {
  expect(actual.paintOrigin, expected.paintOrigin);
  expect(actual.paintExtent, expected.paintExtent);
  expect(actual.layoutExtent, expected.layoutExtent);
  expect(
      actual.maxScrollObstructionExtent, expected.maxScrollObstructionExtent);
  expect(actual.hitTestExtent, expected.hitTestExtent);
  expect(actual.visible, expected.visible);
  expect(actual.hasVisualOverflow, expected.hasVisualOverflow);
  expect(actual.scrollOffsetCorrection, expected.scrollOffsetCorrection);
  expect(actual.cacheExtent, expected.cacheExtent);
}

void main() {
  testWidgets('generated finite-child estimates fail only when non-finite',
      (WidgetTester tester) async {
    await _pump(
      tester,
      _remote('''
import restage.core;
widget Surface = ListView(children: [
  SizedBox(height: 1.0),
  SizedBox(height: 1.0),
  SizedBox(height: 1.0)
]);
'''),
    );

    final SliverMultiBoxAdaptorElement element =
        tester.element(_sliverList) as SliverMultiBoxAdaptorElement;
    expect(
      element.estimateMaxScrollOffset(
        null,
        firstIndex: 0,
        lastIndex: 0,
        leadingScrollOffset: 0,
        trailingScrollOffset: 5e307,
      ),
      1.5e308,
    );
    expect(
      () => element.estimateMaxScrollOffset(
        null,
        firstIndex: 0,
        lastIndex: 0,
        leadingScrollOffset: 0,
        trailingScrollOffset: 1e308,
      ),
      throwsA(
        isA<FlutterError>().having(
          (FlutterError error) => error.toString(),
          'message',
          contains('ListView cannot estimate a finite scroll extent'),
        ),
      ),
    );
    final RestageListView list =
        tester.widget<RestageListView>(find.byType(RestageListView));
    expect(list, isA<ListView>());
    expect(list.scrollDirection, Axis.vertical);
    expect(list.reverse, isFalse);
    expect(list.shrinkWrap, isFalse);
    expect(list.controller, isNull);
    expect(list.primary, isNull);
    expect(list.restorationId, isNull);
    expect(list.childrenDelegate, isA<SliverChildListDelegate>());
    expect(list.childrenDelegate.estimatedChildCount, 3);
    expect(list.semanticChildCount, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unknown child count retains the native infinity sentinel',
      (WidgetTester tester) async {
    late Widget sliver;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (BuildContext context) {
            sliver = _UnknownCountListView().buildChildLayout(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await _pump(tester, CustomScrollView(slivers: <Widget>[sliver]));
    final SliverMultiBoxAdaptorElement element =
        tester.element(_sliverList) as SliverMultiBoxAdaptorElement;

    expect(
      element.estimateMaxScrollOffset(
        null,
        firstIndex: 0,
        lastIndex: 0,
        leadingScrollOffset: 0,
        trailingScrollOffset: 1e308,
      ),
      double.infinity,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('materialized child-sum overflow is rejected before publication',
      (WidgetTester tester) async {
    await _pump(
      tester,
      _remote('''
import restage.core;
widget Surface = ListView(children: [
  SizedBox(height: 1.0),
  SizedBox(height: 1e308),
  SizedBox(height: 1e308)
]);
'''),
    );
    final RenderSliverList render = _listRender(tester);
    expect(render.geometry!.scrollExtent, 1.5e308);

    final List<Object> errors = <Object>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      errors.add(details.exception);
    };
    try {
      tester.state<ScrollableState>(find.byType(Scrollable)).position.jumpTo(
            1.1e308,
          );
      await tester.pump();
    } finally {
      FlutterError.onError = previous;
    }

    final List<double?> offsets = <double?>[];
    render.visitChildren((RenderObject child) {
      offsets.add(
        (child.parentData! as SliverMultiBoxAdaptorParentData).layoutOffset,
      );
    });
    expect(offsets, contains(1e308));
    expect(
      errors,
      contains(
        isA<FlutterError>().having(
          (FlutterError error) => error.toString(),
          'message',
          contains('ListView cannot estimate a finite scroll extent'),
        ),
      ),
    );
    expect(render.geometry?.scrollExtent, isNot(double.infinity));
    expect(tester.takeException(), isNull);
  });

  testWidgets('materialized finite child sum stays exact',
      (WidgetTester tester) async {
    await _pump(
      tester,
      _remote('''
import restage.core;
widget Surface = ListView(children: [
  SizedBox(height: 1.0),
  SizedBox(height: 5e307),
  SizedBox(height: 5e307)
]);
'''),
    );
    final RenderSliverList render = _listRender(tester);
    tester.state<ScrollableState>(find.byType(Scrollable)).position.jumpTo(
          5.5e307,
        );
    await tester.pump();

    expect(render.geometry!.scrollExtent, 1e308);
    expect(tester.takeException(), isNull);
  });

  testWidgets('generated padding repairs only failed extent fields',
      (WidgetTester tester) async {
    await _pump(
      tester,
      ListView(
        padding: const EdgeInsets.only(top: 8e307),
        children: const <Widget>[SizedBox(height: 1e308)],
      ),
    );
    final _PaddingSnapshot native = _snapshot(tester);
    expect(native.geometry.scrollExtent, double.infinity);
    expect(native.geometry.maxPaintExtent, double.infinity);

    await _pump(
      tester,
      _remote('''
import restage.core;
widget Surface = ListView(
  padding: [0.0, 8e307, 0.0, 0.0],
  children: [SizedBox(height: 1e308)]
);
'''),
    );
    final _PaddingSnapshot guarded = _snapshot(tester);

    expect(guarded.constraints.precedingScrollExtent, 0);
    expect(guarded.childConstraints.precedingScrollExtent, 8e307);
    expect(guarded.geometry.scrollExtent, guarded.childGeometry.scrollExtent);
    expect(
      guarded.geometry.maxPaintExtent,
      guarded.childGeometry.maxPaintExtent,
    );
    expect(guarded.geometry.scrollExtent, 1e308);
    expect(guarded.geometry.maxPaintExtent, 1e308);
    _expectUnrepairedGeometryEquals(guarded.geometry, native.geometry);
    _expectGeometryEquals(guarded.childGeometry, native.childGeometry);
    expect(guarded.childConstraints, native.childConstraints);
    expect(guarded.childPaintOffset, native.childPaintOffset);
    expect(guarded.childMainAxisPosition, native.childMainAxisPosition);
    expect(guarded.childMainAxisPosition, 600);
    expect(tester.takeException(), isNull);
  });

  for (final variant in <({
    String name,
    Axis axis,
    bool reverse,
    bool shrinkWrap,
    EdgeInsets? padding,
    EdgeInsets mediaPadding,
    Widget child,
  })>[
    (
      name: 'finite huge reverse shrink-wrap',
      axis: Axis.vertical,
      reverse: true,
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 1e307),
      mediaPadding: EdgeInsets.zero,
      child: const SizedBox(height: 1e307),
    ),
    (
      name: 'zero horizontal',
      axis: Axis.horizontal,
      reverse: false,
      shrinkWrap: false,
      padding: EdgeInsets.zero,
      mediaPadding: EdgeInsets.zero,
      child: const SizedBox(width: 1e308, height: 10),
    ),
    (
      name: 'implicit media query',
      axis: Axis.vertical,
      reverse: false,
      shrinkWrap: false,
      padding: null,
      mediaPadding: const EdgeInsets.fromLTRB(11, 13, 17, 19),
      child: const SizedBox(height: 40),
    ),
    (
      name: 'horizontal reverse',
      axis: Axis.horizontal,
      reverse: true,
      shrinkWrap: false,
      padding: const EdgeInsets.fromLTRB(10, 3, 20, 5),
      mediaPadding: EdgeInsets.zero,
      child: const SizedBox(width: 40, height: 10),
    ),
  ]) {
    testWidgets('${variant.name} padding remains native',
        (WidgetTester tester) async {
      ListView list(bool guarded) => guarded
          ? RestageListView(
              scrollDirection: variant.axis,
              reverse: variant.reverse,
              shrinkWrap: variant.shrinkWrap,
              padding: variant.padding,
              children: <Widget>[variant.child],
            )
          : ListView(
              scrollDirection: variant.axis,
              reverse: variant.reverse,
              shrinkWrap: variant.shrinkWrap,
              padding: variant.padding,
              children: <Widget>[variant.child],
            );

      await _pump(
        tester,
        list(false),
        mediaPadding: variant.mediaPadding,
      );
      final _PaddingSnapshot native = _snapshot(tester);
      await _pump(
        tester,
        list(true),
        mediaPadding: variant.mediaPadding,
      );
      final _PaddingSnapshot guarded = _snapshot(tester);

      _expectGeometryEquals(guarded.geometry, native.geometry);
      _expectGeometryEquals(guarded.childGeometry, native.childGeometry);
      expect(guarded.constraints, native.constraints);
      expect(guarded.childConstraints, native.childConstraints);
      expect(guarded.childPaintOffset, native.childPaintOffset);
      expect(guarded.childMainAxisPosition, native.childMainAxisPosition);
      if (variant.name == 'implicit media query') {
        expect(
          MediaQuery.of(tester.element(_sliverList)).padding,
          const EdgeInsets.fromLTRB(11, 0, 17, 0),
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('resolved padding is repaired before child deflation',
      (WidgetTester tester) async {
    await _pump(
      tester,
      RestageListView(
        padding: const EdgeInsets.symmetric(vertical: 1e308),
        children: const <Widget>[SizedBox(height: 10)],
      ),
    );
    var render = _paddingRender(tester);
    expect(render.resolvedPadding, EdgeInsets.zero);
    expect(render.child!.constraints.precedingScrollExtent, 0);
    expect(render.child!.constraints.isNormalized, isTrue);

    const EdgeInsets valid = EdgeInsets.fromLTRB(2, 3, 5, 7);
    await _pump(
      tester,
      RestageListView(
        padding: valid,
        children: const <Widget>[SizedBox(height: 10)],
      ),
    );
    render = _paddingRender(tester);
    expect(identical(render.resolvedPadding, valid), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scroll corrections pass through unchanged',
      (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    final _CorrectionSnapshot native = await _runNativeListCorrection(
      tester,
      guarded: false,
    );
    final _CorrectionSnapshot guarded = await _runNativeListCorrection(
      tester,
      guarded: true,
    );

    expect(native.corrections, <double>[180, 200]);
    expect(guarded.corrections, native.corrections);
    expect(native.offset, 380);
    expect(guarded.offset, native.offset);
    expect(native.itemB, const Rect.fromLTRB(200, -180, 600, 20));
    expect(guarded.itemB, native.itemB);
    expect(native.semanticsLabel, 'B');
    expect(guarded.semanticsLabel, native.semanticsLabel);
    expect(native.padding.geometry.scrollOffsetCorrection, isNull);
    expect(guarded.padding.geometry.scrollOffsetCorrection, isNull);
    _expectGeometryEquals(guarded.padding.geometry, native.padding.geometry);
    _expectGeometryEquals(
      guarded.padding.childGeometry,
      native.padding.childGeometry,
    );
    expect(guarded.padding.constraints, native.padding.constraints);
    expect(guarded.padding.childConstraints, native.padding.childConstraints);
    expect(guarded.padding.childPaintOffset, native.padding.childPaintOffset);
    expect(
      guarded.padding.childMainAxisPosition,
      native.padding.childMainAxisPosition,
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('inherited scrolling, updates, and semantics stay intact',
      (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    final ScrollController controller = ScrollController();
    final List<ScrollNotification> notifications = <ScrollNotification>[];
    final PageStorageBucket bucket = PageStorageBucket();
    var order = <String>['a', 'b', 'c', 'd'];

    Widget build() => PageStorage(
          bucket: bucket,
          child: PrimaryScrollController(
            controller: controller,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: SizedBox(
                width: 200,
                height: 100,
                child: NotificationListener<ScrollNotification>(
                  onNotification: (ScrollNotification notification) {
                    notifications.add(notification);
                    return false;
                  },
                  child: RestageListView(
                    key: const PageStorageKey<String>('list'),
                    padding: EdgeInsets.zero,
                    children: order
                        .map(
                          (String id) => Semantics(
                            key: ValueKey<String>(id),
                            label: 'item $id',
                            child: const SizedBox(height: 40),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ),
          ),
        );

    await tester.pumpWidget(build());
    await tester.pump();
    final Element a = tester.element(find.byKey(const ValueKey<String>('a')));
    expect(
      tester.widget<Scrollable>(find.byType(Scrollable)).controller,
      same(controller),
    );
    controller.jumpTo(20);
    await tester.pump();
    order = order.reversed.toList();
    await tester.pumpWidget(build());
    await tester.pump();

    expect(
      tester.element(find.byKey(const ValueKey<String>('a'))),
      same(a),
    );
    expect(notifications, isNotEmpty);
    expect(controller.offset, 20);
    expect(
      tester
          .widget<RestageListView>(find.byType(RestageListView))
          .restorationId,
      isNull,
    );
    final SemanticsNode? root = tester
        .binding.renderViews.single.owner?.semanticsOwner?.rootSemanticsNode;
    expect(root, isNotNull);
    _traverseSemantics(root!);
    expect(tester.takeException(), isNull);

    semantics.dispose();
    controller.dispose();
  });
}
