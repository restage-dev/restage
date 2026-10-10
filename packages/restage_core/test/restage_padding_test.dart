import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart';

const LibraryName _coreLibrary = LibraryName(<String>['restage', 'core']);
const LibraryName _probeLibrary = LibraryName(<String>['render', 'probe']);
const LibraryName _rootLibrary = LibraryName(<String>['application', 'root']);

class _GeometryProbe extends LeafRenderObjectWidget {
  const _GeometryProbe({
    required this.width,
    required this.height,
    required this.baseline,
  });

  final double width;
  final double height;
  final double? baseline;

  @override
  _RenderGeometryProbe createRenderObject(BuildContext context) =>
      _RenderGeometryProbe(width, height, baseline);
}

class _RenderGeometryProbe extends RenderBox {
  _RenderGeometryProbe(this.width, this.height, this.baseline);

  final double width;
  final double height;
  final double? baseline;
  BoxConstraints? actualConstraints;
  BoxConstraints? dryConstraints;
  double? widthIntrinsicArgument;
  double? heightIntrinsicArgument;

  @override
  void performLayout() {
    actualConstraints = constraints;
    size = constraints.constrain(Size(width, height));
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    dryConstraints = constraints;
    return constraints.constrain(Size(width, height));
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    widthIntrinsicArgument = height;
    return width;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    widthIntrinsicArgument = height;
    return width;
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    heightIntrinsicArgument = width;
    return height;
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    heightIntrinsicArgument = width;
    return height;
  }

  @override
  double? computeDryBaseline(
    covariant BoxConstraints constraints,
    TextBaseline baseline,
  ) =>
      this.baseline;

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      this.baseline;
}

Widget _buildProbe(BuildContext context, DataSource source) => _GeometryProbe(
      width: source.v<double>(<Object>['width']) ?? 0,
      height: source.v<double>(<Object>['height']) ?? 0,
      baseline: source.v<double>(<Object>['baseline']),
    );

class _OperationHost extends SingleChildRenderObjectWidget {
  const _OperationHost({
    required this.childConstraints,
    required super.child,
    super.key,
  });

  final BoxConstraints childConstraints;

  @override
  _RenderOperationHost createRenderObject(BuildContext context) =>
      _RenderOperationHost(childConstraints);
}

class _RenderOperationHost extends RenderProxyBox {
  _RenderOperationHost(this.childConstraints);

  final BoxConstraints childConstraints;
  double? actualBaseline;

  @override
  void performLayout() {
    child!.layout(childConstraints, parentUsesSize: true);
    actualBaseline = child!.getDistanceToBaseline(
      TextBaseline.alphabetic,
      onlyReal: true,
    );
    size = constraints.constrain(const Size(20, 20));
  }
}

({Runtime runtime, DynamicContent data}) _runtime(
  String source, {
  Map<String, Object?>? data,
}) {
  final content = DynamicContent(data ?? <String, Object?>{});
  return (
    runtime: Runtime()
      ..update(_coreLibrary, buildCoreWidgetLibrary())
      ..update(
        _probeLibrary,
        LocalWidgetLibrary(<String, LocalWidgetBuilder>{
          'Probe': _buildProbe,
        }),
      )
      ..update(_rootLibrary, parseLibraryFile(source)),
    data: content,
  );
}

Future<({RenderPadding render, _RenderOperationHost host})> _pumpPadding(
  WidgetTester tester, {
  required String padding,
  required BoxConstraints constraints,
  double? width,
  double? height,
  double? baseline,
  TextDirection direction = TextDirection.ltr,
}) async {
  final child = width == null
      ? ''
      : 'child: Probe(width: data.width, height: data.height, '
          'baseline: data.baseline),';
  final result = _runtime('''
import restage.core;
import render.probe;
widget Subject = Padding(padding: $padding, $child);
''', data: <String, Object?>{
    if (width != null) 'width': width,
    if (height != null) 'height': height,
    if (baseline != null) 'baseline': baseline,
  });
  await tester.pumpWidget(
    Directionality(
      textDirection: direction,
      child: _OperationHost(
        key: UniqueKey(),
        childConstraints: constraints,
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
    render: tester.renderObject<RenderPadding>(find.byType(RestagePadding)),
    host: tester.renderObject<_RenderOperationHost>(
      find.byType(_OperationHost),
    ),
  );
}

void main() {
  group('generated Padding', () {
    testWidgets('repairs only failed final additions', (tester) async {
      final result = await _pumpPadding(
        tester,
        padding: '[8e307, 8e307, 0.0, 0.0]',
        constraints: const BoxConstraints(),
        width: 1e308,
        height: 1e308,
        baseline: 1e308,
      );
      final render = result.render;
      final child = render.child! as _RenderGeometryProbe;

      expect(tester.widget<RestagePadding>(find.byType(RestagePadding)),
          isA<Padding>());
      expect(render.size, const Size(1e308, 1e308));
      expect(child.actualConstraints, const BoxConstraints());
      expect((child.parentData! as BoxParentData).offset,
          const Offset(8e307, 8e307));
      expect(render.getDryLayout(const BoxConstraints()),
          const Size(1e308, 1e308));
      expect(render.getMinIntrinsicWidth(double.infinity), 1e308);
      expect(render.getMaxIntrinsicWidth(double.infinity), 1e308);
      expect(render.getMinIntrinsicHeight(double.infinity), 1e308);
      expect(render.getMaxIntrinsicHeight(double.infinity), 1e308);
      expect(child.widthIntrinsicArgument, double.infinity);
      expect(child.heightIntrinsicArgument, double.infinity);
      expect(
        render.getDryBaseline(
          const BoxConstraints(),
          TextBaseline.alphabetic,
        ),
        isNull,
      );
      expect(result.host.actualBaseline, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('preserves authored child constraints and offset',
        (tester) async {
      final result = await _pumpPadding(
        tester,
        padding: '[8e307, 0.0, 0.0, 0.0]',
        constraints: const BoxConstraints(minWidth: 1.5e308),
        width: 1e308,
        height: 10,
        baseline: 5,
      );
      final child = result.render.child! as _RenderGeometryProbe;

      expect(result.render.size, const Size(1.5e308, 10));
      expect(child.size, const Size(1e308, 10));
      expect(child.actualConstraints!.minWidth, 7e307);
      expect(
          (child.parentData! as BoxParentData).offset, const Offset(8e307, 0));
      expect(
        result.render.getDryLayout(
          const BoxConstraints(minWidth: 1.5e308),
        ),
        const Size(1.5e308, 10),
      );
      expect(child.dryConstraints!.minWidth, 7e307);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps finite, zero, empty, and bounded results native',
        (tester) async {
      var result = await _pumpPadding(
        tester,
        padding: '[1e307, 1e307, 0.0, 0.0]',
        constraints: const BoxConstraints(),
        width: 4e307,
        height: 4e307,
        baseline: 4e307,
      );
      expect(result.render.size, const Size(5e307, 5e307));
      expect(result.render.getMinIntrinsicWidth(double.infinity), 5e307);
      expect(result.host.actualBaseline, 5e307);

      result = await _pumpPadding(
        tester,
        padding: '[0.0]',
        constraints: const BoxConstraints(),
        width: 1e308,
        height: 1e308,
        baseline: 1e308,
      );
      expect(result.render.size, const Size(1e308, 1e308));
      expect(result.host.actualBaseline, 1e308);

      result = await _pumpPadding(
        tester,
        padding: '[4.0, 8.0, 16.0, 32.0]',
        constraints: const BoxConstraints(),
      );
      expect(result.render.size, const Size(20, 40));
      expect(result.render.getDryLayout(const BoxConstraints()),
          const Size(20, 40));
      expect(result.render.getMinIntrinsicWidth(double.infinity), 20);
      expect(result.render.getMinIntrinsicHeight(double.infinity), 40);
      expect(result.host.actualBaseline, isNull);

      result = await _pumpPadding(
        tester,
        padding: '[8e307, 8e307, 0.0, 0.0]',
        constraints: const BoxConstraints.tightFor(width: 400, height: 100),
        width: 1e308,
        height: 1e308,
        baseline: 1e308,
      );
      expect(result.render.size, const Size(400, 100));
      expect(
        result.render.getDryLayout(
          const BoxConstraints.tightFor(width: 400, height: 100),
        ),
        const Size(400, 100),
      );
      expect(result.render.getMinIntrinsicWidth(double.infinity), 1e308);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('generated AnimatedPadding guards evaluated geometry and updates',
      (tester) async {
    var ends = 0;
    final result = _runtime(
      '''
import restage.core;
import render.probe;
widget Subject = AnimatedPadding(
  padding: [data.start, data.top, data.end, data.bottom],
  curve: data.curve,
  duration: 1000,
  onEnd: event "ended" {},
  child: Probe(width: 10.0, height: 10.0, baseline: 5.0),
);
''',
      data: <String, Object?>{
        'start': 0.0,
        'top': 0.0,
        'end': 0.0,
        'bottom': 0.0,
        'curve': 'elasticOut',
      },
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: _OperationHost(
          childConstraints: const BoxConstraints(
            minWidth: 100,
            minHeight: 100,
          ),
          child: RemoteWidget(
            runtime: result.runtime,
            data: result.data,
            widget: const FullyQualifiedWidgetName(_rootLibrary, 'Subject'),
            onEvent: (name, _) => ends += name == 'ended' ? 1 : 0,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(RestageAnimatedPadding), findsOneWidget);
    expect(
      tester.widget<RestageAnimatedPadding>(
        find.byType(RestageAnimatedPadding),
      ),
      isA<AnimatedPadding>(),
    );

    result.data
      ..update('start', 1.7e308)
      ..update('top', 4.0)
      ..update('bottom', 6.0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 166));

    var render = tester.renderObject<RenderPadding>(
      find.byType(RestagePadding),
    );
    var resolved = render.padding.resolve(TextDirection.ltr);
    var child = render.child! as _RenderGeometryProbe;
    expect(resolved.left, 0);
    expect(resolved.top, greaterThan(0));
    expect(resolved.bottom, greaterThan(0));
    expect(render.size, const Size(100, 100));
    expect(child.actualConstraints!.minWidth, 100);
    expect((child.parentData! as BoxParentData).offset.dx, 0);
    expect(
        render.getDryLayout(const BoxConstraints(minWidth: 123)), isA<Size>());
    expect(render.getMinIntrinsicWidth(211), 10);
    expect(
      render
          .getDryBaseline(
            const BoxConstraints(minWidth: 131),
            TextBaseline.alphabetic,
          )
          ?.isFinite,
      isTrue,
    );

    result.data
      ..update('start', 12.0)
      ..update('top', 3.0)
      ..update('end', 8.0)
      ..update('bottom', 5.0)
      ..update('curve', 'linear');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump();
    render = tester.renderObject<RenderPadding>(find.byType(RestagePadding));
    resolved = render.padding.resolve(TextDirection.ltr);
    expect(resolved, const EdgeInsets.fromLTRB(12, 3, 8, 5));
    expect((render.child!.parentData! as BoxParentData).offset,
        const Offset(12, 3));
    expect(ends, 1);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.rtl,
        child: _OperationHost(
          childConstraints: const BoxConstraints(
            minWidth: 100,
            minHeight: 100,
          ),
          child: RemoteWidget(
            runtime: result.runtime,
            data: result.data,
            widget: const FullyQualifiedWidgetName(_rootLibrary, 'Subject'),
            onEvent: (name, _) => ends += name == 'ended' ? 1 : 0,
          ),
        ),
      ),
    );
    await tester.pump();
    render = tester.renderObject<RenderPadding>(find.byType(RestagePadding));
    expect(render.padding.resolve(TextDirection.rtl),
        const EdgeInsets.fromLTRB(8, 3, 12, 5));
    expect((render.child!.parentData! as BoxParentData).offset,
        const Offset(8, 3));
    expect(ends, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('generated AnimatedPadding preserves finite and clamped frames',
      (tester) async {
    Future<({DynamicContent data, int Function() ends})> pumpCase(
      String curve,
    ) async {
      var endCount = 0;
      final result = _runtime(
        '''
import restage.core;
import render.probe;
widget Subject = AnimatedPadding(
  padding: [data.start, 0.0, 0.0, 0.0],
  curve: "$curve",
  duration: 1000,
  onEnd: event "ended" {},
  child: Probe(width: 10.0, height: 10.0, baseline: 5.0),
);
''',
        data: <String, Object?>{'start': 0.0},
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: _OperationHost(
            key: UniqueKey(),
            childConstraints: const BoxConstraints(minWidth: 100),
            child: RemoteWidget(
              runtime: result.runtime,
              data: result.data,
              widget: const FullyQualifiedWidgetName(
                _rootLibrary,
                'Subject',
              ),
              onEvent: (name, _) => endCount += name == 'ended' ? 1 : 0,
            ),
          ),
        ),
      );
      await tester.pump();
      return (data: result.data, ends: () => endCount);
    }

    var subject = await pumpCase('easeInBack');
    subject.data.update('start', 100.0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    var render = tester.renderObject<RenderPadding>(
      find.byType(RestagePadding),
    );
    expect(render.padding.resolve(TextDirection.ltr), EdgeInsets.zero);
    expect((render.child!.parentData! as BoxParentData).offset, Offset.zero);
    expect((render.child! as _RenderGeometryProbe).actualConstraints!.minWidth,
        100);
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump();
    expect(subject.ends(), 1);

    subject = await pumpCase('linear');
    subject.data.update('start', 1e308);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    render = tester.renderObject<RenderPadding>(find.byType(RestagePadding));
    final EdgeInsets midpoint = render.padding.resolve(TextDirection.ltr);
    expect(midpoint.left, closeTo(5e307, 1e293));
    expect(midpoint.left.isFinite, isTrue);
    expect(render.size.width, midpoint.left + 10);
    expect(
        render.getDryLayout(const BoxConstraints()).width, midpoint.left + 10);
    expect(render.getMinIntrinsicWidth(double.infinity), midpoint.left + 10);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(subject.ends(), 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('RestagePadding preserves mixed directional updates',
      (tester) async {
    final mixed = EdgeInsetsGeometry.lerp(
      const EdgeInsets.only(left: 20, top: 2),
      const EdgeInsetsDirectional.only(start: 8, end: 4, bottom: 6),
      0.5,
    )!;
    var direction = TextDirection.ltr;
    late StateSetter update;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return Directionality(
            textDirection: direction,
            child: RestagePadding(
              padding: mixed,
              child: const SizedBox(width: 10, height: 10),
            ),
          );
        },
      ),
    );
    var render = tester.renderObject<RenderPadding>(
      find.byType(RestagePadding),
    );
    expect(identical(render.padding, mixed), isTrue);
    expect((render.child!.parentData! as BoxParentData).offset,
        Offset(mixed.resolve(TextDirection.ltr).left, 1));

    update(() => direction = TextDirection.rtl);
    await tester.pump();
    render = tester.renderObject<RenderPadding>(find.byType(RestagePadding));
    expect(identical(render.padding, mixed), isTrue);
    expect((render.child!.parentData! as BoxParentData).offset,
        Offset(mixed.resolve(TextDirection.rtl).left, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('retargeting preserves finite begins and repairs poison',
      (tester) async {
    const duration = Duration(milliseconds: 1000);
    var negative = EdgeInsetsDirectional.zero;
    var axis = EdgeInsetsDirectional.zero;
    var poison = EdgeInsetsDirectional.zero;
    late StateSetter update;
    final negativeNative = GlobalKey();
    final negativeGuard = GlobalKey();
    final axisNative = GlobalKey();
    final axisGuard = GlobalKey();
    final poisonGuard = GlobalKey();
    final ends = <String, int>{};
    void ended(String name) =>
        ends.update(name, (value) => value + 1, ifAbsent: () => 1);

    Widget animated({
      required GlobalKey key,
      required bool guarded,
      required EdgeInsetsGeometry padding,
      required Curve curve,
      required String name,
    }) =>
        SizedBox(
          width: 120,
          height: 50,
          child: guarded
              ? RestageAnimatedPadding(
                  key: key,
                  padding: padding,
                  curve: curve,
                  duration: duration,
                  onEnd: () => ended(name),
                  child: const SizedBox(width: 10, height: 10),
                )
              : AnimatedPadding(
                  key: key,
                  padding: padding,
                  curve: curve,
                  duration: duration,
                  onEnd: () => ended(name),
                  child: const SizedBox(width: 10, height: 10),
                ),
        );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return Column(
              children: <Widget>[
                animated(
                  key: negativeNative,
                  guarded: false,
                  padding: negative,
                  curve: Curves.easeInBack,
                  name: 'negativeNative',
                ),
                animated(
                  key: negativeGuard,
                  guarded: true,
                  padding: negative,
                  curve: Curves.easeInBack,
                  name: 'negativeGuard',
                ),
                animated(
                  key: axisNative,
                  guarded: false,
                  padding: axis,
                  curve: Curves.linear,
                  name: 'axisNative',
                ),
                animated(
                  key: axisGuard,
                  guarded: true,
                  padding: axis,
                  curve: Curves.linear,
                  name: 'axisGuard',
                ),
                animated(
                  key: poisonGuard,
                  guarded: true,
                  padding: poison,
                  curve: Curves.elasticOut,
                  name: 'poisonGuard',
                ),
              ],
            );
          },
        ),
      ),
    );
    await tester.pump();
    RenderPadding render(GlobalKey key) =>
        key.currentContext!.findRenderObject()! as RenderPadding;
    EdgeInsets resolved(GlobalKey key) =>
        render(key).padding.resolve(TextDirection.ltr);

    update(() {
      negative = const EdgeInsetsDirectional.only(start: 100);
      axis = const EdgeInsetsDirectional.fromSTEB(1e308, 0, 1e308, 0);
      poison = const EdgeInsetsDirectional.only(start: 1.7e308);
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 166));
    expect(resolved(poisonGuard).left, 0);
    update(() => poison = const EdgeInsetsDirectional.only(start: 12));
    await tester.pump();
    expect(resolved(poisonGuard).left, 0);

    expect(resolved(negativeNative), EdgeInsets.zero);
    expect(resolved(negativeGuard), EdgeInsets.zero);
    update(() => negative = const EdgeInsetsDirectional.only(start: 20));
    await tester.pump();
    for (var i = 0; i < 20 && resolved(negativeGuard).left == 0; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(resolved(negativeGuard), resolved(negativeNative));
    expect(resolved(negativeGuard).left, greaterThan(0));

    for (var i = 0; i < 20 && resolved(axisNative).horizontal.isFinite; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(resolved(axisNative).horizontal, double.infinity);
    expect(resolved(axisGuard), EdgeInsets.zero);
    update(() => axis = const EdgeInsetsDirectional.fromSTEB(
          8e307,
          0,
          8e307,
          0,
        ));
    await tester.pump();
    for (var i = 0; i < 20 && !resolved(axisNative).horizontal.isFinite; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(resolved(axisGuard), resolved(axisNative));
    expect(resolved(axisGuard).horizontal.isFinite, isTrue);

    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump();
    expect(resolved(poisonGuard).left, 12);
    expect(ends, <String, int>{
      'negativeNative': 1,
      'negativeGuard': 1,
      'axisNative': 1,
      'axisGuard': 1,
      'poisonGuard': 1,
    });
    expect(tester.takeException(), isNull);
  });
}
