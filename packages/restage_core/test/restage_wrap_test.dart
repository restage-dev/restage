import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart';

const _core = LibraryName(['restage', 'core']);
const _probes = LibraryName(['render', 'probes']);
const _root = LibraryName(['app', 'root']);
const _baseline = TextBaseline.alphabetic;

class _Probe extends LeafRenderObjectWidget {
  const _Probe(this.size, this.baseline);

  final Size size;
  final double? baseline;

  @override
  _ProbeBox createRenderObject(BuildContext context) =>
      _ProbeBox(size, baseline);
}

class _ProbeBox extends RenderBox {
  _ProbeBox(this.naturalSize, this.baseline);

  static final baselineOrder = <double>[];

  final Size naturalSize;
  final double? baseline;
  final actualConstraints = <BoxConstraints>[];
  final dryConstraints = <BoxConstraints>[];
  final baselineConstraints = <BoxConstraints>[];

  @override
  void performLayout() {
    actualConstraints.add(constraints);
    size = constraints.constrain(naturalSize);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    dryConstraints.add(constraints);
    return constraints.constrain(naturalSize);
  }

  @override
  double computeMinIntrinsicWidth(double height) => naturalSize.width;

  @override
  double computeMaxIntrinsicWidth(double height) => naturalSize.width;

  @override
  double computeMinIntrinsicHeight(double width) => naturalSize.height;

  @override
  double computeMaxIntrinsicHeight(double width) => naturalSize.height;

  @override
  double? computeDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
  ) {
    baselineOrder.add(naturalSize.width);
    baselineConstraints.add(constraints);
    return this.baseline;
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      this.baseline;
}

class _Host extends SingleChildRenderObjectWidget {
  const _Host(
    this.constraintsValue,
    this.dryFirst, {
    required this.dryOnly,
    required super.child,
    super.key,
  });

  final BoxConstraints constraintsValue;
  final bool dryFirst;
  final bool dryOnly;

  @override
  _HostBox createRenderObject(BuildContext context) =>
      _HostBox(constraintsValue, dryFirst, dryOnly);

  @override
  void updateRenderObject(BuildContext context, _HostBox renderObject) {
    renderObject
      ..constraintsValue = constraintsValue
      ..dryFirst = dryFirst
      ..dryOnly = dryOnly
      ..markNeedsLayout();
  }
}

class _HostBox extends RenderProxyBox {
  _HostBox(this.constraintsValue, this.dryFirst, this.dryOnly);

  BoxConstraints constraintsValue;
  bool dryFirst;
  bool dryOnly;
  double? baseline;

  @override
  void performLayout() {
    baseline = null;
    final render = child! as RenderWrap;
    if (dryFirst || dryOnly) {
      baseline = render.getDryBaseline(constraintsValue, _baseline);
    }
    if (!dryOnly) {
      render.layout(constraintsValue);
      baseline = render.getDistanceToBaseline(_baseline, onlyReal: true);
    }
    size = constraints.constrain(const Size(100, 100));
  }

  @override
  void paint(PaintingContext context, Offset offset) {}

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {}
}

Future<({RenderWrap render, double? baseline, DynamicContent data})> _mount(
  WidgetTester tester,
  String expression,
  BoxConstraints constraints, {
  bool dryFirst = false,
  bool dryOnly = false,
  DynamicContent? data,
}) async {
  final runtime = Runtime()
    ..update(_core, buildCoreWidgetLibrary())
    ..update(
      _probes,
      LocalWidgetLibrary({
        'Probe': (_, source) => _Probe(
              Size(
                source.v<double>(['width']) ?? 10,
                source.v<double>(['height']) ?? 10,
              ),
              source.v<double>(['baseline']),
            ),
      }),
    )
    ..update(
      _root,
      parseLibraryFile('''
import restage.core;
import render.probes;
widget Surface = $expression;
'''),
    );
  final content = data ?? DynamicContent();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: _Host(
        constraints,
        dryFirst,
        dryOnly: dryOnly,
        key: UniqueKey(),
        child: RemoteWidget(
          runtime: runtime,
          data: content,
          widget: const FullyQualifiedWidgetName(_root, 'Surface'),
          onEvent: (_, __) {},
        ),
      ),
    ),
  );
  final render = tester.renderObject<RenderWrap>(find.byType(RestageWrap));
  return (
    render: render,
    baseline: tester.renderObject<_HostBox>(find.byType(_Host)).baseline,
    data: content,
  );
}

List<_ProbeBox> _children(RenderWrap render) => [
      for (var child = render.firstChild;
          child != null;
          child = render.childAfter(child))
        child as _ProbeBox,
    ];

List<Offset> _offsets(RenderWrap render) => [
      for (var child = render.firstChild;
          child != null;
          child = render.childAfter(child))
        (child.parentData! as WrapParentData).offset,
    ];

String _probeList(List<(double, double, double?)> values) => values
    .map(
      (value) => 'Probe(width: ${_number(value.$1)}, '
          'height: ${_number(value.$2)}'
          '${value.$3 == null ? '' : ', baseline: ${_number(value.$3!)}'})',
    )
    .join(',');

String _number(double value) => value.toString().replaceFirst('e+', 'e');

void main() {
  testWidgets('generated Wrap preserves native run admission', (tester) async {
    final mounted = await _mount(
      tester,
      'Wrap(spacing: 1e308, children: [${_probeList(const [
            (20, 20, null),
            (20, 20, null),
            (20, 20, null),
          ])}])',
      const BoxConstraints.tightFor(width: 100),
    );

    expect(mounted.render.size, const Size(100, 60));
    expect(
      _offsets(mounted.render),
      const [Offset.zero, Offset(0, 20), Offset(0, 40)],
    );
    expect(mounted.render.spacing, 1e308);
    expect(tester.takeException(), isNull);
  });

  for (final horizontal in [true, false]) {
    final direction = horizontal ? 'horizontal' : 'vertical';
    Size oriented(double main, double cross) =>
        horizontal ? Size(main, cross) : Size(cross, main);
    Offset positioned(double main, double cross) =>
        horizontal ? Offset(main, cross) : Offset(cross, main);
    BoxConstraints mainBound(double value) => horizontal
        ? BoxConstraints(maxWidth: value)
        : BoxConstraints(maxHeight: value);

    testWidgets('$direction repairs one-run spacing overflow', (tester) async {
      final mounted = await _mount(
        tester,
        'Wrap(direction: "$direction", spacing: 1e308, '
        'children: [${_probeList([
              (horizontal ? 10 : 4, horizontal ? 4 : 10, null),
              (horizontal ? 10 : 4, horizontal ? 4 : 10, null),
              (horizontal ? 10 : 4, horizontal ? 4 : 10, null),
            ])}])',
        const BoxConstraints(),
      );
      expect(mounted.render.size, oriented(30, 4));
      expect(
        _offsets(mounted.render),
        [positioned(0, 0), positioned(10, 0), positioned(20, 0)],
      );
      expect(
          _children(mounted.render)
              .map((child) => child.actualConstraints.length),
          [1, 1, 1]);
      expect(
        mounted.render.getDryLayout(const BoxConstraints()),
        oriented(30, 4),
      );
      expect(mounted.render.spacing, 1e308);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$direction repairs exact multi-run spacing', (tester) async {
      final mounted = await _mount(
        tester,
        'Wrap(direction: "$direction", runSpacing: 1e308, '
        'children: [${_probeList([
              (horizontal ? 10 : 4, horizontal ? 4 : 10, null),
              (horizontal ? 10 : 4, horizontal ? 4 : 10, null),
              (horizontal ? 10 : 4, horizontal ? 4 : 10, null),
            ])}])',
        mainBound(10),
      );
      expect(mounted.render.size, oriented(10, 12));
      expect(
        _offsets(mounted.render),
        [positioned(0, 0), positioned(0, 4), positioned(0, 8)],
      );
      expect(mounted.render.runSpacing, 1e308);
      expect(tester.takeException(), isNull);
    });
  }

  for (final runSpacing in [0.0, 1e308]) {
    testWidgets('cross repair reforms runs from runSpacing $runSpacing',
        (tester) async {
      final mounted = await _mount(
        tester,
        'Wrap(spacing: 1e308, runSpacing: ${_number(runSpacing)}, '
        'children: [${_probeList(const [
              (40, 1e308, null),
              (40, 1e308, null),
            ])}])',
        const BoxConstraints(maxWidth: 100),
      );
      expect(mounted.render.size, const Size(80, 1e308));
      expect(_offsets(mounted.render), const [Offset.zero, Offset(40, 0)]);
      expect(
        _children(mounted.render)
            .map((child) => child.actualConstraints.length),
        [1, 1],
      );
      expect(mounted.render.spacing, 1e308);
      expect(mounted.render.runSpacing, runSpacing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('keeps bounded clamps and unused final overflow', (tester) async {
    final mounted = await _mount(
      tester,
      'Wrap(spacing: 1e308, children: [${_probeList(const [
            (40, 1e308, null),
            (40, 1e308, null),
          ])}])',
      const BoxConstraints(maxWidth: 100, maxHeight: 100),
    );
    expect(mounted.render.size, const Size(40, 100));
    expect(_offsets(mounted.render), const [Offset.zero, Offset(0, 1e308)]);
    expect(mounted.render.spacing, 1e308);
    expect(tester.takeException(), isNull);
  });

  testWidgets('repairs actual positions after a finite constrained size',
      (tester) async {
    final mounted = await _mount(
      tester,
      'Wrap(runSpacing: 1e308, children: [Probe(), Probe(), Probe()])',
      const BoxConstraints.tightFor(width: 10, height: 100),
    );
    expect(mounted.render.size, const Size(10, 100));
    expect(_offsets(mounted.render), const [
      Offset.zero,
      Offset(0, 10),
      Offset(0, 20),
    ]);
    expect(mounted.render.runSpacing, 1e308);
    expect(
      _children(mounted.render).map((child) => child.actualConstraints.length),
      [1, 1, 1],
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('reapplies authored spacing when constraints change',
      (tester) async {
    final mounted = await _mount(
      tester,
      'Wrap(spacing: 1e308, children: [Probe(), Probe(), Probe()])',
      const BoxConstraints(),
    );
    final render = mounted.render;
    final host = tester.renderObject<_HostBox>(find.byType(_Host));
    expect(render.size, const Size(30, 10));
    expect(_offsets(render), const [
      Offset.zero,
      Offset(10, 0),
      Offset(20, 0),
    ]);

    host
      ..constraintsValue = const BoxConstraints(maxWidth: 10)
      ..markNeedsLayout();
    await tester.pump();
    expect(tester.renderObject(find.byType(RestageWrap)), same(render));
    expect(render.size, const Size(10, 30));
    expect(_offsets(render), const [
      Offset.zero,
      Offset(0, 10),
      Offset(0, 20),
    ]);
    expect(render.spacing, 1e308);

    host
      ..constraintsValue = const BoxConstraints()
      ..markNeedsLayout();
    await tester.pump();
    expect(tester.renderObject(find.byType(RestageWrap)), same(render));
    expect(render.size, const Size(30, 10));
    expect(_offsets(render), const [
      Offset.zero,
      Offset(10, 0),
      Offset(20, 0),
    ]);
    expect(render.spacing, 1e308);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps finite huge positions and empty run controls',
      (tester) async {
    final mounted = await _mount(
      tester,
      'Wrap(spacing: 2e307, children: [${_probeList(const [
            (3e307, 10, null),
            (3e307, 10, null),
            (3e307, 10, null),
          ])}])',
      const BoxConstraints(),
    );
    expect(mounted.render.size, const Size(1.3e308, 10));
    expect(_offsets(mounted.render), const [
      Offset.zero,
      Offset(5e307, 0),
      Offset(1e308, 0),
    ]);
    expect(tester.takeException(), isNull);

    for (final expression in [
      'Wrap(spacing: 1e308, runSpacing: 1e308, children: [])',
      'Wrap(spacing: 1e308, runSpacing: 1e308, children: [Probe()])',
      'Wrap(spacing: 1e308, runSpacing: 1e308, children: [Probe(), Probe()])',
    ]) {
      final control = await _mount(
        tester,
        expression,
        const BoxConstraints(maxWidth: 100),
      );
      expect(control.render.size.isFinite, isTrue);
      expect(control.render.spacing, 1e308);
      expect(control.render.runSpacing, 1e308);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('matches native directions flips and alignments', (tester) async {
    for (final direction in Axis.values) {
      for (final textDirection in TextDirection.values) {
        for (final verticalDirection in VerticalDirection.values) {
          final alignment = WrapAlignment.values[
              (direction.index + textDirection.index) %
                  WrapAlignment.values.length];
          final runAlignment = WrapAlignment.values[
              (verticalDirection.index + 3) % WrapAlignment.values.length];
          final crossAlignment = WrapCrossAlignment.values[
              (textDirection.index + verticalDirection.index) %
                  WrapCrossAlignment.values.length];
          final mounted = await _mount(
            tester,
            'Wrap(direction: "${direction.name}", '
            'alignment: "${alignment.name}", runAlignment: "${runAlignment.name}", '
            'crossAxisAlignment: "${crossAlignment.name}", '
            'textDirection: "${textDirection.name}", '
            'verticalDirection: "${verticalDirection.name}", spacing: 3.0, '
            'runSpacing: 4.0, children: [${_probeList(const [
                  (13, 7, null),
                  (11, 9, null),
                  (17, 5, null),
                ])}])',
            const BoxConstraints.tightFor(width: 30, height: 40),
          );
          final native = RenderWrap(
            direction: direction,
            alignment: alignment,
            spacing: 3,
            runAlignment: runAlignment,
            runSpacing: 4,
            crossAxisAlignment: crossAlignment,
            textDirection: textDirection,
            verticalDirection: verticalDirection,
            children: [
              _ProbeBox(const Size(13, 7), null),
              _ProbeBox(const Size(11, 9), null),
              _ProbeBox(const Size(17, 5), null),
            ],
          )..layout(const BoxConstraints.tightFor(width: 30, height: 40));
          expect(mounted.render.size, native.size);
          expect(_offsets(mounted.render), _offsets(native));
          native.dispose();
          expect(tester.takeException(), isNull);
        }
      }
    }
  });

  testWidgets('dry baseline matches native flips and alignments',
      (tester) async {
    const constraints = BoxConstraints.tightFor(width: 30, height: 40);
    for (final direction in Axis.values) {
      for (final flipped in [false, true]) {
        _ProbeBox.baselineOrder.clear();
        final textDirection = flipped ? TextDirection.rtl : TextDirection.ltr;
        final verticalDirection =
            flipped ? VerticalDirection.up : VerticalDirection.down;
        final mounted = await _mount(
          tester,
          'Wrap(direction: "${direction.name}", alignment: "spaceAround", '
          'runAlignment: "spaceEvenly", crossAxisAlignment: "end", '
          'textDirection: "${textDirection.name}", '
          'verticalDirection: "${verticalDirection.name}", spacing: 3.0, '
          'runSpacing: 4.0, children: [${_probeList(const [
                (13, 7, 6),
                (11, 9, null),
                (17, 5, 2),
              ])}])',
          constraints,
          dryOnly: true,
        );
        final guardedOrder = List<double>.of(_ProbeBox.baselineOrder);
        _ProbeBox.baselineOrder.clear();
        final native = RenderWrap(
          direction: direction,
          alignment: WrapAlignment.spaceAround,
          spacing: 3,
          runAlignment: WrapAlignment.spaceEvenly,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.end,
          textDirection: textDirection,
          verticalDirection: verticalDirection,
          children: [
            _ProbeBox(const Size(13, 7), 6),
            _ProbeBox(const Size(11, 9), null),
            _ProbeBox(const Size(17, 5), 2),
          ],
        );
        expect(mounted.baseline, native.getDryBaseline(constraints, _baseline));
        expect(guardedOrder, _ProbeBox.baselineOrder);
        expect(guardedOrder, isNotEmpty);
        _ProbeBox.baselineOrder.clear();
        native.dispose();
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('guards direct sums and dry-backed intrinsic queries',
      (tester) async {
    var mounted = await _mount(
      tester,
      'Wrap(children: [${_probeList(const [
            (1e308, 10, null),
            (1e308, 10, null),
          ])}])',
      const BoxConstraints(maxWidth: 100),
    );
    expect(
      () => mounted.render.getMaxIntrinsicWidth(10),
      throwsFlutterError,
    );
    mounted = await _mount(
      tester,
      'Wrap(direction: "vertical", children: [${_probeList(const [
            (10, 1e308, null),
            (10, 1e308, null),
          ])}])',
      const BoxConstraints(maxHeight: 100),
    );
    expect(
      () => mounted.render.getMaxIntrinsicHeight(10),
      throwsFlutterError,
    );
    mounted = await _mount(
      tester,
      'Wrap(spacing: 1e308, children: [Probe(), Probe(), Probe()])',
      const BoxConstraints(maxWidth: 100),
    );
    expect(mounted.render.getMaxIntrinsicHeight(double.infinity), 10);
    mounted = await _mount(
      tester,
      'Wrap(direction: "vertical", spacing: 1e308, '
      'children: [Probe(), Probe(), Probe()])',
      const BoxConstraints(maxHeight: 100),
    );
    expect(mounted.render.getMaxIntrinsicWidth(double.infinity), 10);
  });

  for (final dryFirst in [false, true]) {
    testWidgets('repairs baseline positions dryFirst $dryFirst',
        (tester) async {
      const constraints = BoxConstraints.tightFor(width: 10);
      final mounted = await _mount(
        tester,
        'Wrap(runSpacing: 1e308, children: [${_probeList(const [
              (10, 10, null),
              (10, 10, null),
              (10, 10, 5),
            ])}])',
        constraints,
        dryFirst: dryFirst,
      );
      expect(mounted.baseline, 25);
      expect(mounted.render.getDryBaseline(constraints, _baseline), 25);
      expect(_offsets(mounted.render), const [
        Offset.zero,
        Offset(0, 10),
        Offset(0, 20),
      ]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('repairs baseline size before caching dryFirst $dryFirst',
        (tester) async {
      const constraints = BoxConstraints(maxWidth: 100);
      for (final bothSpacings in [false, true]) {
        final mounted = await _mount(
          tester,
          'Wrap(spacing: 1e308, '
          '${bothSpacings ? 'runSpacing: 1e308, ' : ''}'
          'children: [${_probeList(const [
                (40, 1e308, null),
                (40, 1e308, 5),
              ])}])',
          constraints,
          dryFirst: dryFirst,
        );
        expect(mounted.render.size, const Size(80, 1e308));
        expect(_offsets(mounted.render), const [Offset.zero, Offset(40, 0)]);
        expect(mounted.baseline, 5);
        expect(mounted.render.getDryBaseline(constraints, _baseline), 5);
        expect(mounted.render.spacing, 1e308);
        expect(mounted.render.runSpacing, bothSpacings ? 1e308 : 0);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets(
        'keeps optional final baseline overflow null dryFirst $dryFirst',
        (tester) async {
      const constraints = BoxConstraints.tightFor(width: 10);
      final mounted = await _mount(
        tester,
        'Wrap(runSpacing: 5e307, children: [${_probeList(const [
              (10, 1e308, null),
              (10, 10, 4e307),
            ])}])',
        constraints,
        dryFirst: dryFirst,
      );
      expect(mounted.baseline, isNull);
      expect(mounted.render.getDryBaseline(constraints, _baseline), isNull);
      expect(_offsets(mounted.render).last, const Offset(0, 1.5e308));
      expect(mounted.render.runSpacing, 5e307);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('repairs bounded dry baseline positions', (tester) async {
    const constraints = BoxConstraints.tightFor(width: 10, height: 100);
    final mounted = await _mount(
      tester,
      'Wrap(runSpacing: 1e308, children: '
      '[Probe(), Probe(), Probe(baseline: 5.0)])',
      constraints,
      dryFirst: true,
    );
    expect(mounted.render.size, const Size(10, 100));
    expect(mounted.baseline, 25);
    expect(mounted.render.getDryBaseline(constraints, _baseline), 25);
    expect(_offsets(mounted.render), const [
      Offset.zero,
      Offset(0, 10),
      Offset(0, 20),
    ]);
    expect(mounted.render.runSpacing, 1e308);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps a finite constrained baseline box unchanged',
      (tester) async {
    const constraints = BoxConstraints(maxWidth: 100, maxHeight: 100);
    final mounted = await _mount(
      tester,
      'Wrap(spacing: 1e308, children: [${_probeList(const [
            (40, 1e308, null),
            (40, 1e308, 5),
          ])}])',
      constraints,
      dryFirst: true,
    );
    expect(mounted.render.size, const Size(40, 100));
    expect(_offsets(mounted.render), const [Offset.zero, Offset(0, 1e308)]);
    expect(mounted.baseline, 1e308);
    expect(mounted.render.getDryBaseline(constraints, _baseline), 1e308);
    expect(mounted.render.spacing, 1e308);
    expect(tester.takeException(), isNull);
  });

  testWidgets('preserves absent and extrapolated baselines', (tester) async {
    const constraints = BoxConstraints(maxWidth: 100);
    var mounted = await _mount(
      tester,
      'Wrap(children: [Probe(), Probe()])',
      constraints,
      dryFirst: true,
    );
    expect(mounted.baseline, isNull);
    expect(mounted.render.getDryBaseline(constraints, _baseline), isNull);
    mounted = await _mount(
      tester,
      'Wrap(children: [Probe(baseline: 35.0)])',
      constraints,
      dryFirst: true,
    );
    expect(mounted.baseline, 35);
    expect(mounted.render.getDryBaseline(constraints, _baseline), 35);
  });

  testWidgets('fails before storing child-only non-finite geometry',
      (tester) async {
    final mounted = await _mount(
      tester,
      'Wrap(children: [${_probeList(const [
            (1e308, 10, null),
            (1e308, 10, null),
          ])}])',
      const BoxConstraints(),
    );
    final error = tester.takeException();
    expect(error, isA<FlutterError>());
    expect(error.toString(), contains('Wrap cannot produce finite geometry'));
    expect(mounted.render.hasSize, isFalse);
    expect(
      _children(mounted.render)
          .expand((child) => child.actualConstraints)
          .every((value) => value.isNormalized),
      isTrue,
    );
  });

  testWidgets('generated fields update on the same native-compatible widget',
      (tester) async {
    final data = DynamicContent({'spacing': 3.0, 'runSpacing': 4.0});
    final mounted = await _mount(
      tester,
      'Wrap(spacing: data.spacing, runSpacing: data.runSpacing, '
      'children: [Probe(), Probe()])',
      const BoxConstraints(maxWidth: 100),
      data: data,
    );
    final render = mounted.render;
    expect(tester.widget<RestageWrap>(find.byType(RestageWrap)), isA<Wrap>());
    expect(render.spacing, 3);
    expect(render.runSpacing, 4);
    data
      ..update('spacing', 5.0)
      ..update('runSpacing', 6.0);
    await tester.pump();
    expect(tester.renderObject(find.byType(RestageWrap)), same(render));
    expect(render.spacing, 5);
    expect(render.runSpacing, 6);
    data
      ..update('spacing', -double.maxFinite)
      ..update('runSpacing', double.infinity);
    await tester.pump();
    expect(render.spacing, 0);
    expect(render.runSpacing, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('public Wrap fields and inherited updates stay native',
      (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.rtl,
        child: Builder(
          builder: (context) {
            const widget = RestageWrap(
              direction: Axis.vertical,
              alignment: WrapAlignment.end,
              spacing: 3,
              runAlignment: WrapAlignment.center,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.end,
              verticalDirection: VerticalDirection.up,
              clipBehavior: Clip.hardEdge,
            );
            final render = widget.createRenderObject(context);
            expect(render.direction, Axis.vertical);
            expect(render.alignment, WrapAlignment.end);
            expect(render.spacing, 3);
            expect(render.runAlignment, WrapAlignment.center);
            expect(render.runSpacing, 4);
            expect(render.crossAxisAlignment, WrapCrossAlignment.end);
            expect(render.textDirection, TextDirection.rtl);
            expect(render.verticalDirection, VerticalDirection.up);
            expect(render.clipBehavior, Clip.hardEdge);
            const Wrap().updateRenderObject(context, render);
            expect(render.direction, Axis.horizontal);
            expect(render.spacing, 0);
            expect(render.runSpacing, 0);
            render.dispose();
            return const SizedBox();
          },
        ),
      ),
    );
  });
}
