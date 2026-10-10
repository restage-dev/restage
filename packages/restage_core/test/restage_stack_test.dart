import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart';

const LibraryName _coreLibrary = LibraryName(<String>['restage', 'core']);
const LibraryName _probeLibrary = LibraryName(<String>['render', 'probe']);
const LibraryName _rootLibrary = LibraryName(<String>['application', 'root']);
const TextBaseline _baseline = TextBaseline.alphabetic;

final Map<String, _RenderProbe> _probes = <String, _RenderProbe>{};

class _Probe extends LeafRenderObjectWidget {
  const _Probe({
    required this.id,
    this.width = 10,
    this.height = 10,
    this.baseline = 5,
    this.failDryLayout = false,
    super.key,
  });

  final String id;
  final double width;
  final double height;
  final double? baseline;
  final bool failDryLayout;

  @override
  _RenderProbe createRenderObject(BuildContext context) =>
      _probes[id] = _RenderProbe(
        Size(width, height),
        baseline,
        failDryLayout,
      );
}

class _RenderProbe extends RenderBox {
  _RenderProbe(this.naturalSize, this.baseline, this.failDryLayout);

  final Size naturalSize;
  final double? baseline;
  final bool failDryLayout;
  BoxConstraints? actualConstraints;
  int layouts = 0;
  int dryLayouts = 0;
  int dryBaselines = 0;

  @override
  void layout(Constraints constraints, {bool parentUsesSize = false}) {
    actualConstraints = constraints as BoxConstraints;
    super.layout(constraints, parentUsesSize: parentUsesSize);
  }

  @override
  void performLayout() {
    layouts += 1;
    size = constraints.constrain(naturalSize);
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    dryLayouts += 1;
    if (failDryLayout) {
      throw StateError('dry layout was not requested');
    }
    return constraints.constrain(naturalSize);
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      this.baseline;

  @override
  double? computeDryBaseline(
    covariant BoxConstraints constraints,
    TextBaseline baseline,
  ) {
    dryBaselines += 1;
    return this.baseline;
  }

  @override
  bool hitTestSelf(Offset position) => true;
}

Widget _buildProbe(BuildContext context, DataSource source) => _Probe(
      id: source.v<String>(<Object>['id'])!,
      width: source.v<double>(<Object>['width']) ?? 10,
      height: source.v<double>(<Object>['height']) ?? 10,
      baseline: source.v<double>(<Object>['baseline']),
    );

class _OperationHost extends SingleChildRenderObjectWidget {
  const _OperationHost({
    required this.childConstraints,
    this.dryFirst = false,
    this.paintChild = true,
    required super.child,
    super.key,
  });

  final BoxConstraints childConstraints;
  final bool dryFirst;
  final bool paintChild;

  @override
  _RenderOperationHost createRenderObject(BuildContext context) =>
      _RenderOperationHost(childConstraints, dryFirst, paintChild);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderOperationHost renderObject,
  ) {
    renderObject
      ..childConstraints = childConstraints
      ..dryFirst = dryFirst
      ..paintChild = paintChild;
  }
}

class _RenderOperationHost extends RenderProxyBox {
  _RenderOperationHost(
    this.childConstraints,
    this.dryFirst,
    this.paintChild,
  );

  BoxConstraints childConstraints;
  bool dryFirst;
  bool paintChild;
  double? actualBaseline;
  double? dryBaseline;
  Size? drySize;

  @override
  void performLayout() {
    if (dryFirst) {
      dryBaseline = child!.getDryBaseline(childConstraints, _baseline);
    }
    child!.layout(childConstraints, parentUsesSize: true);
    actualBaseline = child!.getDistanceToBaseline(_baseline, onlyReal: true);
    drySize = child!.getDryLayout(childConstraints);
    if (!dryFirst) {
      dryBaseline = child!.getDryBaseline(childConstraints, _baseline);
    }
    size = constraints.constrain(const Size(100, 100));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (paintChild) {
      super.paint(context, offset);
    }
  }
}

({Runtime runtime, DynamicContent data}) _runtime(
  String source, {
  Map<String, Object?> data = const <String, Object?>{},
}) {
  final content = DynamicContent(data);
  return (
    runtime: Runtime()
      ..update(_coreLibrary, buildCoreWidgetLibrary())
      ..update(
        _probeLibrary,
        LocalWidgetLibrary(<String, LocalWidgetBuilder>{'Probe': _buildProbe}),
      )
      ..update(_rootLibrary, parseLibraryFile(source)),
    data: content,
  );
}

Future<
    ({
      RenderStack render,
      _RenderOperationHost host,
      DynamicContent data,
    })> _mount(
  WidgetTester tester,
  String body, {
  BoxConstraints constraints = const BoxConstraints.tightFor(
    width: 100,
    height: 80,
  ),
  Map<String, Object?> data = const <String, Object?>{},
  bool dryFirst = false,
  bool paintChild = true,
  TextDirection direction = TextDirection.ltr,
}) async {
  _probes.clear();
  final result = _runtime('''
import restage.core;
import render.probe;
widget Subject = $body;
''', data: data);
  await tester.pumpWidget(
    Directionality(
      textDirection: direction,
      child: _OperationHost(
        key: UniqueKey(),
        childConstraints: constraints,
        dryFirst: dryFirst,
        paintChild: paintChild,
        child: RemoteWidget(
          runtime: result.runtime,
          data: result.data,
          widget: const FullyQualifiedWidgetName(_rootLibrary, 'Subject'),
          onEvent: (_, __) {},
        ),
      ),
    ),
  );
  await tester.pump();
  return (
    render: tester.renderObject<RenderStack>(find.byType(RestageStack)),
    host: tester.renderObject<_RenderOperationHost>(
      find.byType(_OperationHost),
    ),
    data: result.data,
  );
}

StackParentData _data(String id) => _probes[id]!.parentData! as StackParentData;

void _expectTransform(RenderStack stack, RenderBox child, Offset expected) {
  final Matrix4 transform = Matrix4.identity();
  stack.applyPaintTransform(child, transform);
  expect(child.localToGlobal(Offset.zero, ancestor: stack), expected);
  expect(transform.storage[12], expected.dx);
  expect(transform.storage[13], expected.dy);
}

String _positioned({
  required String id,
  required String geometry,
  double? baseline = 5,
}) {
  final baselineArgument =
      baseline == null ? '' : 'baseline: ${_rfwDouble(baseline)},';
  return 'Positioned($geometry child: Probe(id: "$id", '
      '$baselineArgument))';
}

String _rfwDouble(double value) => value.toString().replaceFirst('e+', 'e');

void main() {
  group('generated Stack positioned geometry', () {
    testWidgets('repairs paired constraints and keeps native finite clamps',
        (tester) async {
      var mounted = await _mount(
        tester,
        'Stack(alignment: {x: 0.0, y: 0.0}, children: ['
        '${_positioned(id: 'pair', geometry: 'left: -1e308, right: -1e308, top: -1e308, bottom: -1e308,')}'
        '])',
      );
      expect(_probes['pair']!.actualConstraints, const BoxConstraints());
      expect(_probes['pair']!.size, const Size(10, 10));
      expect(_data('pair').offset, const Offset(-1e308, -1e308));
      expect(_data('pair').isPositioned, isTrue);
      expect(mounted.host.actualBaseline, -1e308);
      expect(mounted.host.dryBaseline, -1e308);
      expect(
        mounted.render.describeApproximatePaintClip(_probes['pair']!),
        const Rect.fromLTWH(0, 0, 100, 80),
      );
      _expectTransform(
        mounted.render,
        _probes['pair']!,
        const Offset(-1e308, -1e308),
      );

      mounted = await _mount(
        tester,
        'Stack(children: ['
        '${_positioned(id: 'clamp', geometry: 'left: 1e308, right: 1e308, top: 5.0, bottom: 5.0,')}'
        '])',
      );
      expect(
        _probes['clamp']!.actualConstraints,
        BoxConstraints.tight(const Size(0, 70)),
      );
      expect(_data('clamp').offset, const Offset(1e308, 5));
      expect(mounted.host.actualBaseline, 10);

      mounted = await _mount(
        tester,
        'Stack(children: ['
        '${_positioned(id: 'negative-size', geometry: 'left: 2.0, top: 3.0, width: -4.0, height: -5.0,')}'
        '])',
      );
      expect(
        _probes['negative-size']!.actualConstraints,
        BoxConstraints.tight(Size.zero),
      );
      expect(_data('negative-size').offset, const Offset(2, 3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('repairs subtraction and alignment by failed axis',
        (tester) async {
      var mounted = await _mount(
        tester,
        'Stack(alignment: {x: 0.0, y: 0.0}, children: ['
        '${_positioned(id: 'right', geometry: 'right: -1e308, top: 10.0,')}'
        '])',
        constraints: const BoxConstraints.tightFor(width: 1e308, height: 80),
        paintChild: false,
      );
      expect(_data('right').offset, const Offset(5e307, 10));
      expect(mounted.host.actualBaseline, 15);
      expect(mounted.host.dryBaseline, 15);
      expect(
        mounted.render.describeApproximatePaintClip(_probes['right']!),
        isNull,
      );
      _expectTransform(
        mounted.render,
        _probes['right']!,
        const Offset(5e307, 10),
      );

      mounted = await _mount(
        tester,
        'Stack(alignment: {x: 0.0, y: 0.0}, children: ['
        '${_positioned(id: 'bottom', geometry: 'left: 10.0, bottom: -1e308,')}'
        '])',
        constraints: const BoxConstraints.tightFor(width: 100, height: 1e308),
        paintChild: false,
        dryFirst: true,
      );
      expect(_data('bottom').offset, const Offset(10, 5e307));
      expect(mounted.host.actualBaseline, 5e307);
      expect(mounted.host.dryBaseline, 5e307);
      expect(
        mounted.render.describeApproximatePaintClip(_probes['bottom']!),
        isNull,
      );

      mounted = await _mount(
        tester,
        'Stack(alignment: {x: 1e308, y: 0.5}, children: ['
        'Probe(id: "mixed", baseline: 5.0)])',
      );
      expect(_data('mixed').offset, const Offset(45, 52.5));
      expect(mounted.host.actualBaseline, 57.5);
      expect(mounted.host.dryBaseline, 57.5);

      mounted = await _mount(
        tester,
        'Stack(alignment: {x: 8e307, y: -8e307}, children: ['
        'Probe(id: "large", baseline: 5.0)])',
        constraints: const BoxConstraints.tightFor(width: 12, height: 12),
      );
      expect(_data('large').offset, const Offset(8e307, -8e307));
      expect(mounted.host.actualBaseline, -8e307);
      expect(mounted.host.dryBaseline, -8e307);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps actual and dry baseline minimum aggregation identical',
        (tester) async {
      Future<void> checkAggregate({
        required String name,
        required double firstTop,
        required double firstBaseline,
        required double? expected,
        required bool dryFirst,
      }) async {
        final mounted = await _mount(
          tester,
          'Stack(children: ['
          '${_positioned(id: '$name-first', geometry: 'left: 0.0, top: ${_rfwDouble(firstTop)}, width: 10.0, height: 10.0,', baseline: firstBaseline)},'
          '${_positioned(id: '$name-second', geometry: 'left: 20.0, top: 0.0, width: 10.0, height: 10.0,', baseline: 5)}'
          '])',
          dryFirst: dryFirst,
        );
        expect(mounted.host.actualBaseline, expected);
        expect(mounted.host.dryBaseline, expected);
      }

      for (final dryFirst in <bool>[false, true]) {
        await checkAggregate(
          name: 'negative-$dryFirst',
          firstTop: -1e308,
          firstBaseline: -1e308,
          expected: null,
          dryFirst: dryFirst,
        );
        await checkAggregate(
          name: 'positive-$dryFirst',
          firstTop: 1e308,
          firstBaseline: 1e308,
          expected: 5,
          dryFirst: dryFirst,
        );
        await checkAggregate(
          name: 'ordinary-$dryFirst',
          firstTop: 10,
          firstBaseline: 5,
          expected: 5,
          dryFirst: dryFirst,
        );
      }

      final mounted = await _mount(
        tester,
        'Stack(children: ['
        '${_positioned(id: 'none', geometry: 'left: 0.0, top: 0.0, width: 10.0, height: 10.0,', baseline: null)},'
        '${_positioned(id: 'finite', geometry: 'left: 20.0, top: 0.0, width: 10.0, height: 10.0,', baseline: 5)}'
        '])',
        data: const <String, Object?>{},
      );
      expect(mounted.host.actualBaseline, 5);
      expect(mounted.host.dryBaseline, 5);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps fit and direction behavior native', (tester) async {
      for (final fit in <String>['loose', 'expand', 'passthrough']) {
        final mounted = await _mount(
          tester,
          'Stack(fit: "$fit", children: [Probe(id: "$fit", width: 20.0, height: 30.0, baseline: 5.0)])',
          constraints: const BoxConstraints(
            minWidth: 10,
            maxWidth: 100,
            minHeight: 15,
            maxHeight: 80,
          ),
        );
        final nativeChild = _RenderProbe(const Size(20, 30), 5, false);
        final native = RenderStack(
          fit: StackFit.values.byName(fit),
          textDirection: TextDirection.ltr,
          children: <RenderBox>[nativeChild],
        )..layout(
            const BoxConstraints(
              minWidth: 10,
              maxWidth: 100,
              minHeight: 15,
              maxHeight: 80,
            ),
          );
        expect(mounted.render.size, native.size);
        expect(_probes[fit]!.size, nativeChild.size);
        expect(_data(fit).offset,
            (nativeChild.parentData! as StackParentData).offset);
        native.dispose();
      }

      var direction = TextDirection.ltr;
      late StateSetter update;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return Directionality(
              textDirection: direction,
              child: const Center(
                child: SizedBox(
                  width: 100,
                  height: 80,
                  child: RestageStack(
                    alignment: AlignmentDirectional.topStart,
                    children: <Widget>[
                      Positioned(
                        top: 0,
                        child: _Probe(id: 'directional'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
      expect(_data('directional').offset, Offset.zero);
      update(() => direction = TextDirection.rtl);
      await tester.pump();
      expect(_data('directional').offset, const Offset(90, 0));
      final render =
          tester.renderObject<RenderStack>(find.byType(RestageStack));
      expect(render.alignment, same(AlignmentDirectional.topStart));
      expect(render.textDirection, TextDirection.rtl);
      expect(tester.takeException(), isNull);
    });

    testWidgets('accepts hostile optional scalars only as absence',
        (tester) async {
      final mounted = await _mount(
        tester,
        'Stack(children: [Positioned(left: data.left, child: Probe(id: "hostile", baseline: 5.0))])',
        data: <String, Object?>{'left': double.infinity},
      );
      expect(_data('hostile').left, isNull);
      expect(_data('hostile').isPositioned, isFalse);
      expect(mounted.render.size, const Size(100, 80));
      expect(mounted.host.actualBaseline, 5);
      expect(mounted.host.dryBaseline, 5);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('AnimatedPositioned repairs every interpolated scalar',
      (tester) async {
    final values = <String, Object?>{
      for (final name in <String>[
        'left',
        'top',
        'right',
        'bottom',
        'width',
        'height',
      ])
        name: 0.0,
    };
    final mounted = await _mount(
      tester,
      '''Stack(children: [
  AnimatedPositioned(left: data.left, duration: 1000, curve: "easeOutBack", child: Probe(id: "left", baseline: 5.0)),
  AnimatedPositioned(top: data.top, duration: 1000, curve: "easeOutBack", child: Probe(id: "top", baseline: 5.0)),
  AnimatedPositioned(right: data.right, duration: 1000, curve: "easeOutBack", child: Probe(id: "right", baseline: 5.0)),
  AnimatedPositioned(bottom: data.bottom, duration: 1000, curve: "easeOutBack", child: Probe(id: "bottom", baseline: 5.0)),
  AnimatedPositioned(width: data.width, duration: 1000, curve: "easeOutBack", child: Probe(id: "width", baseline: 5.0)),
  AnimatedPositioned(height: data.height, duration: 1000, curve: "easeOutBack", child: Probe(id: "height", baseline: 5.0)),
])''',
      constraints: const BoxConstraints(maxWidth: 100, maxHeight: 100),
      data: values,
    );
    expect(find.byType(AnimatedPositioned), findsNWidgets(6));
    final initialData = <String, StackParentData>{
      for (final name in values.keys) name: _data(name),
    };

    for (final name in values.keys) {
      mounted.data.update(name, double.maxFinite);
    }
    await tester.pump();
    var allAbsent = false;
    for (var i = 0; i < 20 && !allAbsent; i += 1) {
      await tester.pump(const Duration(milliseconds: 50));
      allAbsent = _data('left').left == null &&
          _data('top').top == null &&
          _data('right').right == null &&
          _data('bottom').bottom == null &&
          _data('width').width == null &&
          _data('height').height == null;
    }
    expect(allAbsent, isTrue);
    expect(values.keys.map((name) => _data(name).isPositioned),
        everyElement(isFalse));
    expect(mounted.render.size, const Size(10, 10));
    expect(mounted.host.actualBaseline, 5);
    expect(mounted.host.dryBaseline, 5);
    expect(mounted.render.getMinIntrinsicWidth(100), 0);
    expect(mounted.render.getMaxIntrinsicHeight(100), 0);

    await tester.pump(const Duration(milliseconds: 1200));
    expect(_data('left').left, double.maxFinite);
    expect(_data('top').top, double.maxFinite);
    expect(_data('right').right, double.maxFinite);
    expect(_data('bottom').bottom, double.maxFinite);
    expect(_data('width').width, double.maxFinite);
    expect(_data('height').height, double.maxFinite);
    expect(values.keys.map((name) => _data(name).isPositioned),
        everyElement(isTrue));

    for (final name in values.keys) {
      mounted.data.update(name, 12.0);
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1100));
    expect(_data('left').left, 12);
    expect(_data('top').top, 12);
    expect(_data('right').right, 12);
    expect(_data('bottom').bottom, 12);
    expect(_data('width').width, 12);
    expect(_data('height').height, 12);
    for (final name in values.keys) {
      expect(_data(name), same(initialData[name]));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('preserves overflow, clip, semantics, hit, and transforms',
      (tester) async {
    var taps = 0;
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 100,
            height: 80,
            child: RestageStack(
              alignment: const Alignment(1e308, -1),
              children: <Widget>[
                const _Probe(id: 'aligned'),
                Positioned(
                  left: -5,
                  top: 0,
                  width: 20,
                  height: 20,
                  child: Semantics(
                    label: 'stack child',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => taps += 1,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final render = tester.renderObject<RenderStack>(find.byType(RestageStack));
    final positioned = tester.renderObject<RenderBox>(
      find.bySemanticsLabel('stack child'),
    );
    expect(_data('aligned').offset, const Offset(45, 0));
    expect(
      render.describeApproximatePaintClip(positioned),
      const Rect.fromLTWH(0, 0, 100, 80),
    );
    expect(find.bySemanticsLabel('stack child'), findsOneWidget);
    await tester.tapAt(render.localToGlobal(const Offset(5, 5)));
    expect(taps, 1);
    _expectTransform(render, positioned, const Offset(-5, 0));
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('reuses parent data across updates and child-list changes',
      (tester) async {
    var left = 1.0;
    var includeSecond = false;
    late StateSetter update;
    const firstKey = ValueKey<String>('first');
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return SizedBox(
              width: 100,
              height: 80,
              child: RestageStack(
                children: <Widget>[
                  Positioned(
                    left: left,
                    top: 2,
                    child: const _Probe(id: 'reuse', key: firstKey),
                  ),
                  if (includeSecond)
                    const Positioned(
                      left: 20,
                      child: _Probe(id: 'second'),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
    final render = _probes['reuse']!;
    final parentData = render.parentData;
    update(() {
      left = 9;
      includeSecond = true;
    });
    await tester.pump();
    expect(_probes['reuse'], same(render));
    expect(_probes['reuse']!.parentData, same(parentData));
    expect(_data('reuse').offset, const Offset(9, 2));
    expect(_data('second').offset, const Offset(20, 0));
    update(() => includeSecond = false);
    await tester.pump();
    expect(_probes['reuse'], same(render));
    expect(_probes['reuse']!.parentData, same(parentData));
    expect(find.byKey(firstKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('actual layout performs no dry preflight', (tester) async {
    _probes.clear();
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 100,
          height: 80,
          child: RestageStack(
            children: <Widget>[
              Positioned(
                left: 0,
                top: 0,
                width: 10,
                height: 10,
                child: _Probe(id: 'actual-only', failDryLayout: true),
              ),
            ],
          ),
        ),
      ),
    );
    expect(_probes['actual-only']!.layouts, 1);
    expect(_probes['actual-only']!.dryLayouts, 0);
    expect(_probes['actual-only']!.dryBaselines, 0);
    expect(tester.takeException(), isNull);
  });
}
