import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart';

const _core = LibraryName(['restage', 'core']);
const _probes = LibraryName(['render', 'probes']);
const _root = LibraryName(['app', 'root']);
const _max = BoxConstraints(maxWidth: double.maxFinite, maxHeight: 100);
const _baseline = TextBaseline.alphabetic;

class _Probe extends LeafRenderObjectWidget {
  const _Probe(this.natural, this.baseline, this.responsive);
  final Size natural;
  final double? baseline;
  final String? responsive;

  @override
  _ProbeBox createRenderObject(BuildContext context) =>
      _ProbeBox(natural, baseline, responsive);
}

class _ProbeBox extends RenderBox {
  _ProbeBox(this.natural, this.baseline, this.responsive);
  final Size natural;
  final double? baseline;
  final String? responsive;
  final actual = <BoxConstraints>[];
  final dry = <BoxConstraints>[];
  final baselines = <BoxConstraints>[];
  final intrinsics = <(String, double)>[];

  double _height(double width) =>
      responsive == null ? natural.height : (width < 50 ? 1e308 : 10);
  double? _baseline(double width) => responsive == null
      ? baseline
      : responsive == 'high'
          ? (width < 50 ? 1e308 : 10)
          : (responsive == 'negative' && width < 50 ? -1e308 : 0);
  Size _size(BoxConstraints value) => value.constrain(responsive == null
      ? natural
      : Size(value.maxWidth, _height(value.maxWidth)));

  @override
  void performLayout() {
    actual.add(constraints);
    size = _size(constraints);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    dry.add(constraints);
    return _size(constraints);
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    intrinsics.add(('minWidth', height));
    return natural.width;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    intrinsics.add(('maxWidth', height));
    return natural.width;
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    intrinsics.add(('minHeight', width));
    return _height(width);
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    intrinsics.add(('maxHeight', width));
    return _height(width);
  }

  @override
  double? computeDryBaseline(
      BoxConstraints constraints, TextBaseline baseline) {
    baselines.add(constraints);
    return _baseline(constraints.maxWidth);
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      _baseline(constraints.maxWidth);
}

class _Host extends SingleChildRenderObjectWidget {
  const _Host(this.operation, {required super.child, super.key});
  final void Function(RenderBox) operation;

  @override
  _HostBox createRenderObject(BuildContext context) => _HostBox(operation);

  @override
  void updateRenderObject(BuildContext context, _HostBox renderObject) {
    renderObject.operation = operation;
    renderObject.markNeedsLayout();
  }
}

class _HostBox extends RenderProxyBox {
  _HostBox(this.operation);
  void Function(RenderBox) operation;

  @override
  void performLayout() {
    operation(child!);
    size = constraints.smallest;
  }

  @override
  void paint(PaintingContext context, Offset offset) {}

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {}
}

Future<
    ({
      RenderFlex render,
      Runtime runtime,
      DynamicContent data,
      double? baseline
    })> _mount(
  WidgetTester tester,
  String expression, {
  BoxConstraints constraints = _max,
  bool actual = false,
  bool dryFirst = false,
  DynamicContent? data,
  void Function(RenderFlex)? configure,
}) async {
  final runtime = Runtime()
    ..update(_core, buildCoreWidgetLibrary())
    ..update(
      _probes,
      LocalWidgetLibrary({
        'Probe': (_, source) => _Probe(
              Size(source.v<double>(['width']) ?? 10,
                  source.v<double>(['height']) ?? 10),
              source.v<double>(['baseline']),
              source.v<String>(['responsive']),
            ),
      }),
    )
    ..update(_root, _library(expression));
  final content = data ?? DynamicContent();
  double? actualBaseline;
  var ready = configure == null;
  await tester.pumpWidget(Directionality(
    textDirection: TextDirection.ltr,
    child: _Host(
      key: UniqueKey(),
      (render) {
        if (!ready) return;
        if (dryFirst) render.getDryBaseline(constraints, _baseline);
        if (actual) {
          render.layout(constraints);
          if (render.hasSize) {
            actualBaseline =
                render.getDistanceToBaseline(_baseline, onlyReal: true);
          }
        }
      },
      child: RemoteWidget(
        runtime: runtime,
        data: content,
        widget: const FullyQualifiedWidgetName(_root, 'Surface'),
        onEvent: (_, __) {},
      ),
    ),
  ));
  final render = tester.renderObject<RenderFlex>(find.byWidgetPredicate(
      (widget) => widget is RestageRow || widget is RestageColumn));
  if (configure != null) {
    configure(render);
    ready = true;
    tester.renderObject<_HostBox>(find.byType(_Host)).markNeedsLayout();
    await tester.pump();
  }
  return (
    render: render,
    runtime: runtime,
    data: content,
    baseline: actualBaseline,
  );
}

RemoteWidgetLibrary _library(String expression) => parseLibraryFile('''
import restage.core;
import render.probes;
widget Surface = $expression;
''');

List<_ProbeBox> _children(RenderFlex render) => [
      for (var child = render.firstChild;
          child != null;
          child = render.childAfter(child))
        if (child is _ProbeBox) child,
    ];

List<Offset> _offsets(RenderFlex render) => [
      for (var child = render.firstChild;
          child != null;
          child = render.childAfter(child))
        (child.parentData! as FlexParentData).offset,
    ];

void _baselineAlign(RenderFlex render) {
  render
    ..textBaseline = _baseline
    ..crossAxisAlignment = CrossAxisAlignment.baseline;
}

void main() {
  for (final name in ['Row', 'Column']) {
    final horizontal = name == 'Row';
    final bound = horizontal
        ? _max
        : const BoxConstraints(maxWidth: 100, maxHeight: double.maxFinite);
    double main(Size value) => horizontal ? value.width : value.height;

    for (final gap in [
      -1.0,
      -double.maxFinite,
      0.0,
      -0.0,
      double.nan,
      double.infinity
    ]) {
      testWidgets('$name repairs invalid bound spacing $gap before allocation',
          (tester) async {
        final mounted = await _mount(
            tester,
            '''$name(spacing: data.gap, children: [
Probe(width: 0.0, height: 0.0), Expanded(flex: 2, child: Probe())])''',
            constraints: bound,
            actual: true,
            data: DynamicContent({'gap': gap}));
        expect(mounted.render.spacing, 0);
        expect(mounted.render.spacing.isNegative, gap == 0 && gap.isNegative);
        expect(main(_children(mounted.render).last.actual.single.biggest),
            double.maxFinite);
        expect(mounted.render.size.isFinite, isTrue);
        expect(tester.takeException(), isNull);
      });
    }

    for (final factor in [3, 7]) {
      testWidgets('$name rejects flex $factor before child acceptance',
          (tester) async {
        final mounted = await _mount(tester,
            '$name(children: [Expanded(flex: $factor, child: Probe())])',
            constraints: bound);
        final render = mounted.render;
        final child = _children(render).single;
        expect(() => render.getDryLayout(bound), throwsFlutterError);
        expect(
            () => render.getDryBaseline(bound, _baseline), throwsFlutterError);
        expect(child.dry, isEmpty);
        expect(child.baselines, isEmpty);
        render.layout(bound);
        expect(tester.takeException().toString(), contains('allocation'));
        expect(child.actual, isEmpty);
        expect(child.hasSize, isFalse);
        expect(render.hasSize, isFalse);
      });
    }

    for (final factor in [1, 2, 5]) {
      testWidgets('$name preserves finite maximum allocation for flex $factor',
          (tester) async {
        final mounted = await _mount(tester,
            '$name(children: [Expanded(flex: $factor, child: Probe())])',
            constraints: bound, actual: true);
        final render = mounted.render;
        final child = _children(render).single;
        expect(main(render.size), double.maxFinite);
        expect(main(child.actual.single.biggest), double.maxFinite);
        expect(main(render.getDryLayout(bound)), double.maxFinite);
        expect(child.dry, [child.actual.single]);
        expect(render.getDryLayout(bound), render.size);
        expect(child.dry.length, 1);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
        '$name refines unsafe maximum using exact non-flex accumulation',
        (tester) async {
      final dimension = horizontal ? 'width' : 'height';
      final mounted = await _mount(
          tester,
          '''$name(children: [
Probe($dimension: 1e308, baseline: 4.0),
Expanded(flex: 3, child: Probe(baseline: 4.0)),
])''',
          constraints: bound,
          actual: true);
      final render = mounted.render;
      final children = _children(render);
      expect(main(children.last.actual.single.biggest), 7.976931348623157e307);
      expect(render.getDryLayout(bound), render.size);
      for (final child in children) {
        expect(child.actual.length, 1);
        expect(child.dry, [child.actual.single]);
      }
      expect(render.getDryBaseline(bound, _baseline), mounted.baseline);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$name preserves zero flex space after non-flex infinity',
        (tester) async {
      final dimension = horizontal ? 'width' : 'height';
      final mounted = await _mount(
          tester,
          '''$name(children: [
Probe($dimension: 1.7976931348623157e308),
Probe($dimension: 1.7976931348623157e308),
Expanded(flex: 3, child: Probe()),
])''',
          constraints: bound);
      expect(main(mounted.render.getDryLayout(bound)), double.maxFinite);
      final children = _children(mounted.render);
      expect(main(children.last.dry.single.biggest), 0);
      expect(children.map((child) => child.dry.length), [1, 1, 1]);
    });

    testWidgets('$name repairs child sum and keeps the finite final clamp',
        (tester) async {
      final dimension = horizontal ? 'width' : 'height';
      final expression = '''$name(spacing: 5e307, children: [
Probe($dimension: 1e308), Probe($dimension: 4e307)])''';
      final unbounded = horizontal
          ? const BoxConstraints(maxHeight: 100)
          : const BoxConstraints(maxWidth: 100);
      var mounted = await _mount(tester, expression,
          constraints: unbounded, actual: true);
      expect(main(mounted.render.size), 1.4e308);
      expect(mounted.render.getDryLayout(unbounded), mounted.render.size);
      expect(mounted.render.spacing, 5e307);
      expect(_offsets(mounted.render), [
        Offset.zero,
        horizontal ? const Offset(1e308, 0) : const Offset(0, 1e308)
      ]);
      expect(_children(mounted.render).map((child) => child.actual.length),
          [1, 1]);
      final tight = horizontal
          ? const BoxConstraints.tightFor(width: 100, height: 10)
          : const BoxConstraints.tightFor(width: 10, height: 100);
      mounted =
          await _mount(tester, expression, constraints: tight, actual: true);
      expect(main(mounted.render.size), 100);
      expect(mounted.render.getDryLayout(tight), mounted.render.size);
      expect(_offsets(mounted.render).last,
          horizontal ? const Offset(1.5e308, 0) : const Offset(0, 1.5e308));
      expect(tester.takeException(), isNull);
    });

    testWidgets('$name repairs an earlier overflowing stored offset',
        (tester) async {
      final dimension = horizontal ? 'width' : 'height';
      final mounted = await _mount(
          tester,
          '''$name(spacing: 5e307, children: [
Probe($dimension: 1e308), Probe($dimension: 4e307), Probe($dimension: 2e307)])''',
          constraints: bound,
          actual: true);
      expect(_offsets(mounted.render), [
        Offset.zero,
        horizontal ? const Offset(1e308, 0) : const Offset(0, 1e308),
        horizontal ? const Offset(1.4e308, 0) : const Offset(0, 1.4e308),
      ]);
      expect(_children(mounted.render).map((child) => child.actual.length),
          [1, 1, 1]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$name preserves zero negative and ordinary flexible factors',
        (tester) async {
      final mounted = await _mount(
          tester,
          '''$name(children: [
Flexible(flex: 0, child: Probe()), Flexible(flex: -1, child: Probe()),
Flexible(flex: 3, fit: "loose", child: Probe())])''',
          constraints: const BoxConstraints(maxWidth: 100, maxHeight: 100),
          actual: true);
      expect(main(mounted.render.size), 100);
      expect(_children(mounted.render).map((child) => child.actual.length),
          [1, 1, 1]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$name keeps all four requested intrinsic classes',
        (tester) async {
      final dimension = horizontal ? 'width' : 'height';
      final mounted = await _mount(tester, '''$name(spacing: 5e307, children: [
Probe($dimension: 1e308), Probe($dimension: 4e307)])''');
      final render = mounted.render;
      expect(render.getMinIntrinsicWidth(double.infinity),
          horizontal ? 1.4e308 : 10);
      expect(render.getMaxIntrinsicWidth(double.infinity),
          horizontal ? 1.4e308 : 10);
      expect(render.getMinIntrinsicHeight(double.infinity),
          horizontal ? 10 : 1.4e308);
      expect(render.getMaxIntrinsicHeight(double.infinity),
          horizontal ? 10 : 1.4e308);
      expect(_children(render).every((child) => child.dry.isEmpty), isTrue);
      expect(render.spacing, 5e307);
    });
  }

  testWidgets(
      'non-baseline cross intrinsics preserve native constraint substitution',
      (tester) async {
    final mounted = await _mount(tester,
        'Row(children: [Expanded(flex: 3, child: Probe(height: 12.0))])');
    final render = mounted.render;
    final child = _children(render).single;
    expect(render.getMaxIntrinsicHeight(double.infinity), 12);
    expect(
        child.intrinsics, [('maxWidth', double.infinity), ('maxHeight', 10.0)]);
    expect(render.getMaxIntrinsicWidth(100), 10);
    expect(child.dry, isEmpty);
    expect(child.baselines, isEmpty);
  });

  testWidgets(
      'baseline cross intrinsics validate allocations before child queries',
      (tester) async {
    final mounted = await _mount(
        tester, '''Row(children: [Expanded(flex: 3, child: Probe())])''',
        configure: _baselineAlign);
    final render = mounted.render;
    final child = _children(render).single;
    expect(() => render.getMinIntrinsicHeight(double.maxFinite),
        throwsFlutterError);
    expect(() => render.getMaxIntrinsicHeight(double.maxFinite),
        throwsFlutterError);
    expect(child.intrinsics, isEmpty);
    expect(child.baselines, isEmpty);
    expect(render.getMaxIntrinsicWidth(100), 10);
  });

  testWidgets('baseline cross intrinsic refinement keeps exact child queries',
      (tester) async {
    final mounted = await _mount(
        tester,
        '''Row(children: [
Probe(width: 1e308, height: 12.0, baseline: 4.0),
Expanded(flex: 3, child: Probe(height: 12.0, baseline: 4.0))])''',
        configure: _baselineAlign);
    expect(mounted.render.getMaxIntrinsicHeight(double.maxFinite), 12);
    final probes = _children(mounted.render);
    expect(probes.first.intrinsics,
        [('maxWidth', double.infinity), ('maxHeight', 1e308)]);
    expect(probes.last.intrinsics, [('maxHeight', 7.976931348623157e307)]);
    expect(probes.last.baselines.map((value) => value.maxWidth),
        [7.976931348623157e307, 7.976931348623157e307]);
    expect(probes.every((child) => child.dry.isEmpty), isTrue);
  });

  testWidgets('spacing fallback rechecks allocation before child acceptance',
      (tester) async {
    const bound = BoxConstraints(maxWidth: double.maxFinite);
    var mounted = await _mount(
        tester,
        '''Row(spacing: 1e308, children: [
Probe(width: 0.0, height: 1e308, baseline: 1e308),
Expanded(flex: 3, child: Probe(height: 1e308, baseline: 0.0))])''',
        configure: _baselineAlign);
    expect(() => mounted.render.getDryLayout(bound), throwsFlutterError);
    expect(_children(mounted.render).last.dry.single.maxWidth,
        7.976931348623157e307);
    expect(mounted.render.spacing, 1e308);
    mounted = await _mount(
        tester,
        '''Row(spacing: 1e308, children: [
Probe(width: 0.0, height: 1e308, baseline: 1e308),
Expanded(flex: 3, child: Probe(height: 1e308, baseline: 0.0))])''',
        configure: _baselineAlign,
        constraints: bound,
        actual: true);
    final child = _children(mounted.render).last;
    expect(tester.takeException().toString(), contains('allocation'));
    expect(child.actual.single.maxWidth, 7.976931348623157e307);
    expect(mounted.render.hasSize, isFalse);
    expect(mounted.render.spacing, 1e308);
  });

  for (final dryFirst in [false, true]) {
    for (final aligned in [false, true]) {
      testWidgets(
          'horizontal main position repairs baseline cache dryFirst $dryFirst aligned $aligned',
          (tester) async {
        const bound =
            BoxConstraints(maxWidth: double.maxFinite, maxHeight: 100);
        final mounted = await _mount(
            tester,
            '''Row(spacing: 5e307, children: [
Probe(width: 1e308), Probe(width: 4e307),
Expanded(child: Probe(responsive: "high", width: 0.0))])''',
            constraints: bound,
            actual: true,
            dryFirst: dryFirst,
            configure: aligned ? _baselineAlign : null);
        expect(mounted.render.size, const Size(double.maxFinite, 10));
        expect(mounted.baseline, 10);
        expect(mounted.render.getDryBaseline(bound, _baseline), 10);
        expect(_offsets(mounted.render),
            [Offset.zero, const Offset(1e308, 0), const Offset(1.4e308, 0)]);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('finite negative baselines remain native dryFirst $dryFirst',
        (tester) async {
      const bound = BoxConstraints(maxWidth: 100, maxHeight: 100);
      final mounted = await _mount(
          tester,
          '''Row(children: [
Probe(baseline: -5.0), Probe(baseline: -10.0)])''',
          constraints: bound,
          actual: true,
          dryFirst: dryFirst,
          configure: _baselineAlign);
      expect(mounted.render.size, const Size(100, 15));
      expect(_offsets(mounted.render), [Offset.zero, const Offset(10, 5)]);
      expect(mounted.baseline, -5);
      expect(mounted.render.getDryBaseline(bound, _baseline), -5);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'horizontal dry cross position repairs cache dryFirst $dryFirst',
        (tester) async {
      const bound = BoxConstraints(maxWidth: 100, maxHeight: 100);
      final mounted = await _mount(
          tester,
          '''Row(spacing: 20.0, children: [
Expanded(child: Probe(responsive: "high", width: 0.0)),
Expanded(child: Probe(responsive: "negative", width: 0.0))])''',
          constraints: bound,
          actual: true,
          dryFirst: dryFirst,
          configure: _baselineAlign);
      expect(mounted.render.size, const Size(100, 20));
      expect(_offsets(mounted.render), [Offset.zero, const Offset(50, 10)]);
      expect(mounted.baseline, 10);
      expect(mounted.render.getDryBaseline(bound, _baseline), 10);
      expect(mounted.render.spacing, 20);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'hidden dry size repairs baseline cache with dryFirst $dryFirst',
        (tester) async {
      const bound = BoxConstraints(maxWidth: 100);
      final mounted = await _mount(
          tester,
          '''Row(spacing: 20.0,
children: [
Expanded(child: Probe(responsive: "high", width: 0.0)),
Expanded(child: Probe(responsive: "low", width: 0.0))])''',
          constraints: bound,
          actual: true,
          dryFirst: dryFirst,
          configure: _baselineAlign);
      final render = mounted.render;
      expect(render.size, const Size(100, 20));
      expect(mounted.baseline, 10);
      expect(render.getDryBaseline(bound, _baseline), 10);
      expect(render.getMinIntrinsicHeight(100), 20);
      expect(render.getMaxIntrinsicHeight(100), 20);
      expect(render.spacing, 20);
      for (final child in _children(render)) {
        expect(child.actual.map((value) => value.maxWidth), [40, 50]);
        expect(child.dry.map((value) => value.maxWidth), [40, 50]);
        expect(
            child.baselines.map((value) => value.maxWidth).toSet(), {40, 50});
      }
      expect(tester.takeException(), isNull);
    });

    for (final up in [false, true]) {
      for (final baselineIndex in [0, 2]) {
        testWidgets(
            'vertical speculative offsets repair dryFirst $dryFirst up $up baseline $baselineIndex',
            (tester) async {
          const bound =
              BoxConstraints(maxHeight: double.maxFinite, maxWidth: 10);
          final sizes =
              up ? ['2e307', '4e307', '1e308'] : ['1e308', '4e307', '2e307'];
          final mounted = await _mount(
              tester,
              '''Column(spacing: 5e307,
children: [
${List.generate(3, (i) => 'Probe(height: ${sizes[i]}${i == baselineIndex ? ', baseline: 5.0' : ''})').join(',')}
])''',
              constraints: bound,
              actual: true,
              dryFirst: dryFirst,
              configure: (render) => render.verticalDirection =
                  up ? VerticalDirection.up : VerticalDirection.down);
          final render = mounted.render;
          final expected = up
              ? (baselineIndex == 0
                  ? 1.5976931348623158e308
                  : 1.9769313486231573e307)
              : (baselineIndex == 0 ? 5.0 : 1.4e308);
          expect(mounted.baseline, expected);
          expect(render.getDryBaseline(bound, _baseline), expected);
          expect(_offsets(render).every((value) => value.isFinite), isTrue);
          expect(render.spacing, 5e307);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets(
        'overflowing optional baseline sum stays null dryFirst $dryFirst',
        (tester) async {
      const bound = BoxConstraints(maxHeight: double.maxFinite, maxWidth: 10);
      final mounted = await _mount(
          tester,
          '''Column(spacing: 5e307, children: [
Probe(height: 1e308), Probe(height: 5e307, baseline: 4e307)])''',
          constraints: bound,
          actual: true,
          dryFirst: dryFirst);
      final render = mounted.render;
      expect(mounted.baseline, isNull);
      expect(render.getDryBaseline(bound, _baseline), isNull);
      expect(_offsets(render).last, const Offset(0, 1.5e308));
      expect(render.spacing, 5e307);
      expect(tester.takeException(), isNull);
    });
  }

  for (final alignment in MainAxisAlignment.values) {
    for (final up in [false, true]) {
      testWidgets('vertical loose baseline preserves $alignment up $up',
          (tester) async {
        const bound =
            BoxConstraints(minHeight: 90, maxHeight: 100, maxWidth: 20);
        final mounted = await _mount(
            tester,
            '''Column(mainAxisSize: "min",
mainAxisAlignment: "${alignment.name}", children: [
Probe(height: 10.0), Flexible(fit: "loose", child: Probe(height: 20.0, baseline: 35.0))])''',
            constraints: bound,
            actual: true,
            dryFirst: true,
            configure: (render) => render.verticalDirection =
                up ? VerticalDirection.up : VerticalDirection.down);
        final render = mounted.render;
        final native = RenderFlex(
          direction: Axis.vertical,
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: alignment,
          verticalDirection: up ? VerticalDirection.up : VerticalDirection.down,
          children: [
            _ProbeBox(const Size(10, 10), null, null),
            _ProbeBox(const Size(10, 20), 35, null)
          ],
        );
        (native.lastChild!.parentData! as FlexParentData)
          ..flex = 1
          ..fit = FlexFit.loose;
        native.layout(bound);
        expect(render.size, native.size);
        expect(_offsets(render), _offsets(native));
        expect(render.getDryBaseline(bound, _baseline),
            native.getDryBaseline(bound, _baseline));
        expect(mounted.baseline, native.getDryBaseline(bound, _baseline));
        native.dispose();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
      'generated fields and parent data update without changing identity',
      (tester) async {
    final mounted = await _mount(
        tester,
        '''Row(spacing: data.gap, children: [
Expanded(flex: data.flex, child: Probe()), Spacer(), Flexible(child: Probe())])''',
        constraints: const BoxConstraints(maxWidth: 100, maxHeight: 20),
        actual: true,
        data: DynamicContent({'gap': 2.0, 'flex': 1}));
    expect(tester.widget<RestageRow>(find.byType(RestageRow)), isA<Row>());
    final render = mounted.render;
    expect(render.textDirection, TextDirection.ltr);
    expect((render.firstChild!.parentData! as FlexParentData).flex, 1);
    mounted.data
      ..update('gap', 3.0)
      ..update('flex', 2);
    await tester.pump();
    expect(tester.renderObject(find.byType(RestageRow)), same(render));
    expect(render.spacing, 3);
    expect((render.firstChild!.parentData! as FlexParentData).flex, 2);
    expect(render.size, const Size(100, 10));
    expect(tester.takeException(), isNull);
  });

  for (final name in ['Row', 'Column']) {
    for (final children in ['', 'Probe(width: 0.0, height: 0.0)']) {
      testWidgets('$name keeps empty and zero controls $children',
          (tester) async {
        final mounted = await _mount(
            tester, '$name(spacing: 1e308, children: [$children])',
            constraints: const BoxConstraints(maxWidth: 100, maxHeight: 100),
            actual: true);
        expect(mounted.render.size.isFinite, isTrue);
        expect(
            mounted.render.getDryBaseline(
                const BoxConstraints(maxWidth: 100, maxHeight: 100), _baseline),
            isNull);
        if (name == 'Column') {
          expect(tester.widget(find.byType(RestageColumn)), isA<Column>());
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('public Flex widgets preserve fields and inherited updates',
      (tester) async {
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.rtl,
      child: Builder(builder: (context) {
        const row = RestageRow(
          mainAxisAlignment: MainAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.ideographic,
          verticalDirection: VerticalDirection.up,
          spacing: 7,
        );
        final render = row.createRenderObject(context);
        expect(render.direction, Axis.horizontal);
        expect(render.textDirection, TextDirection.rtl);
        expect(render.mainAxisAlignment, MainAxisAlignment.end);
        expect(render.mainAxisSize, MainAxisSize.min);
        expect(render.crossAxisAlignment, CrossAxisAlignment.baseline);
        expect(render.textBaseline, TextBaseline.ideographic);
        expect(render.verticalDirection, VerticalDirection.up);
        expect(render.spacing, 7);
        const column =
            RestageColumn(textDirection: TextDirection.ltr, spacing: 3);
        column.updateRenderObject(context, render);
        expect(render.direction, Axis.vertical);
        expect(render.textDirection, TextDirection.ltr);
        expect(render.mainAxisAlignment, MainAxisAlignment.start);
        expect(render.mainAxisSize, MainAxisSize.max);
        expect(render.crossAxisAlignment, CrossAxisAlignment.center);
        expect(render.textBaseline, isNull);
        expect(render.verticalDirection, VerticalDirection.down);
        expect(render.spacing, 3);
        render.dispose();
        return const SizedBox();
      }),
    ));
  });

  testWidgets('a same-named custom library keeps its native Row',
      (tester) async {
    final runtime = Runtime()
      ..update(_core, buildCoreWidgetLibrary())
      ..update(
          _probes,
          LocalWidgetLibrary({
            'Row': (_, __) =>
                const Row(children: [SizedBox(width: 10, height: 10)]),
          }))
      ..update(_root, parseLibraryFile('''
import render.probes;
widget Surface = Row();
'''));
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: _Host(
          (render) => render
              .layout(const BoxConstraints(maxWidth: 100, maxHeight: 100)),
          child: RemoteWidget(
              runtime: runtime,
              data: DynamicContent(),
              widget: const FullyQualifiedWidgetName(_root, 'Surface'),
              onEvent: (_, __) {})),
    ));
    expect(find.byType(Row), findsOneWidget);
    expect(find.byType(RestageRow), findsNothing);
    expect(tester.renderObject(find.byType(Row)).runtimeType, RenderFlex);
  });
}
