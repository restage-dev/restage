import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart';

const LibraryName _coreLibrary = LibraryName(<String>['restage', 'core']);
const LibraryName _probeLibrary = LibraryName(<String>['render', 'probe']);
const LibraryName _rootLibrary = LibraryName(<String>['application', 'root']);

Widget _buildSizeProbe(BuildContext context, DataSource source) => _SizeProbe(
      width: source.v<double>(<Object>['width']) ?? 0,
      height: source.v<double>(<Object>['height']) ?? 0,
    );

class _SizeProbe extends LeafRenderObjectWidget {
  const _SizeProbe({required this.width, required this.height});

  final double width;
  final double height;

  @override
  _RenderSizeProbe createRenderObject(BuildContext context) =>
      _RenderSizeProbe(width, height);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSizeProbe renderObject,
  ) {
    renderObject.target = Size(width, height);
  }
}

class _RenderSizeProbe extends RenderBox {
  _RenderSizeProbe(double width, double height) : _target = Size(width, height);

  Size _target;
  int dryLayoutCount = 0;

  set target(Size value) {
    if (value == _target) {
      return;
    }
    _target = value;
    markNeedsLayout();
  }

  @override
  void performLayout() => size = constraints.constrain(_target);

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    dryLayoutCount++;
    return constraints.constrain(_target);
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      size.height / 2;

  @override
  double? computeDryBaseline(
    covariant BoxConstraints constraints,
    TextBaseline baseline,
  ) =>
      getDryLayout(constraints).height / 2;
}

class _ConstraintHost extends SingleChildRenderObjectWidget {
  const _ConstraintHost({required this.childConstraints, required super.child});

  final BoxConstraints childConstraints;

  @override
  _RenderConstraintHost createRenderObject(BuildContext context) =>
      _RenderConstraintHost(childConstraints);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderConstraintHost renderObject,
  ) {
    renderObject.childConstraints = childConstraints;
  }
}

class _RenderConstraintHost extends RenderProxyBox {
  _RenderConstraintHost(this._childConstraints);

  BoxConstraints _childConstraints;
  double? childBaseline;

  set childConstraints(BoxConstraints value) {
    if (value == _childConstraints) {
      return;
    }
    _childConstraints = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    child!.layout(_childConstraints, parentUsesSize: true);
    childBaseline = child!.getDistanceToBaseline(
      TextBaseline.alphabetic,
      onlyReal: true,
    );
    size = constraints.constrain(const Size(20, 24));
  }
}

Future<DynamicContent> _pumpGenerated(
  WidgetTester tester, {
  required double width,
  required BoxConstraints constraints,
  required void Function(String, DynamicMap) onEvent,
}) async {
  final DynamicContent data = DynamicContent(<String, Object?>{
    'width': width,
    'height': 20.0,
  });
  final Runtime runtime = Runtime()
    ..update(_coreLibrary, buildCoreWidgetLibrary())
    ..update(
      _probeLibrary,
      LocalWidgetLibrary(<String, LocalWidgetBuilder>{
        'SizeProbe': _buildSizeProbe,
      }),
    )
    ..update(
      _rootLibrary,
      parseLibraryFile('''
import restage.core;
import render.probe;
widget Animated = AnimatedSize(
  alignment: {x: 1e308, y: 3.0},
  curve: "easeOutBack",
  duration: 700,
  reverseDuration: 200,
  clipBehavior: "antiAlias",
  onEnd: event "ended" {},
  child: SizeProbe(width: data.width, height: data.height),
);
'''),
    );
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: _ConstraintHost(
        childConstraints: constraints,
        child: RemoteWidget(
          runtime: runtime,
          data: data,
          widget: const FullyQualifiedWidgetName(_rootLibrary, 'Animated'),
          onEvent: onEvent,
        ),
      ),
    ),
  );
  await tester.pump();
  return data;
}

RenderAnimatedSize _render(GlobalKey key) =>
    key.currentContext!.findRenderObject()! as RenderAnimatedSize;

void main() {
  testWidgets('generated animation repairs actual dry and shifted geometry',
      (tester) async {
    var ends = 0;
    final DynamicContent data = await _pumpGenerated(
      tester,
      width: 0,
      constraints: const BoxConstraints(maxHeight: 20),
      onEvent: (name, _) => ends += name == 'ended' ? 1 : 0,
    );

    expect(find.byType(RestageAnimatedSize), findsOneWidget);
    final RestageAnimatedSize widget =
        tester.widget<RestageAnimatedSize>(find.byType(RestageAnimatedSize));
    expect(widget, isA<AnimatedSize>());
    expect(widget.reverseDuration, const Duration(milliseconds: 200));
    expect(widget.clipBehavior, Clip.antiAlias);

    data.update('width', double.maxFinite);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    final RenderAnimatedSize render = tester.renderObject<RenderAnimatedSize>(
      find.byType(RestageAnimatedSize),
    );
    final _RenderSizeProbe child = render.child! as _RenderSizeProbe;
    final Offset offset = (child.parentData! as BoxParentData).offset;
    expect(render.size, const Size(double.maxFinite, 20));
    expect(offset, Offset.zero);
    final _RenderConstraintHost host =
        tester.renderObject<_RenderConstraintHost>(
      find.byType(_ConstraintHost),
    );
    expect(host.childBaseline, 10);
    const BoxConstraints alternate = BoxConstraints(maxHeight: 17);
    final int dryCallsBefore = child.dryLayoutCount;
    expect(
      render.getDryLayout(alternate),
      const Size(double.maxFinite, 17),
    );
    final int dryCallsAfter = child.dryLayoutCount;
    expect(dryCallsAfter, greaterThan(dryCallsBefore));
    expect(
      render.getDryLayout(alternate),
      const Size(double.maxFinite, 17),
    );
    expect(child.dryLayoutCount, dryCallsAfter);
    expect(render.getDryLayout(render.constraints), render.size);
    expect(
      render.getDryBaseline(render.constraints, TextBaseline.alphabetic),
      10,
    );
    expect(render.constraints.runtimeType, BoxConstraints);
    expect(child.constraints.runtimeType, BoxConstraints);
    expect(tester.takeException(), isNull);

    data.update('width', 1e307);
    await tester.pump();
    expect(render.state, RenderAnimatedSizeState.changed);
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();

    expect(render.size, const Size(1e307, 20));
    expect(render.getDryLayout(render.constraints), render.size);
    expect(ends, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('legal and bounded frames preserve native results',
      (tester) async {
    const Duration duration = Duration(milliseconds: 700);
    const BoxConstraints unbounded = BoxConstraints(maxHeight: 20);
    const BoxConstraints bounded = BoxConstraints(
      maxWidth: 1.5e308,
      maxHeight: 20,
    );
    final GlobalKey nativeLegalKey = GlobalKey();
    final GlobalKey restageLegalKey = GlobalKey();
    final GlobalKey nativeBoundedKey = GlobalKey();
    final GlobalKey restageBoundedKey = GlobalKey();
    StateSetter? update;
    double legalWidth = 0;
    double boundedWidth = 0;

    Widget animated({
      required GlobalKey key,
      required bool restage,
      required double width,
      required BoxConstraints constraints,
    }) =>
        _ConstraintHost(
          childConstraints: constraints,
          child: restage
              ? RestageAnimatedSize(
                  key: key,
                  duration: duration,
                  curve: Curves.easeOutBack,
                  child: SizedBox(width: width, height: 20),
                )
              : AnimatedSize(
                  key: key,
                  duration: duration,
                  curve: Curves.easeOutBack,
                  child: SizedBox(width: width, height: 20),
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
                  key: nativeLegalKey,
                  restage: false,
                  width: legalWidth,
                  constraints: unbounded,
                ),
                animated(
                  key: restageLegalKey,
                  restage: true,
                  width: legalWidth,
                  constraints: unbounded,
                ),
                animated(
                  key: nativeBoundedKey,
                  restage: false,
                  width: boundedWidth,
                  constraints: bounded,
                ),
                animated(
                  key: restageBoundedKey,
                  restage: true,
                  width: boundedWidth,
                  constraints: bounded,
                ),
              ],
            );
          },
        ),
      ),
    );
    await tester.pump();
    update!(() {
      legalWidth = 8e307;
      boundedWidth = double.maxFinite;
    });
    await tester.pump();

    for (final Duration elapsed in const <Duration>[
      Duration(milliseconds: 350),
      Duration(milliseconds: 400),
    ]) {
      await tester.pump(elapsed);
      final RenderAnimatedSize nativeLegal = _render(nativeLegalKey);
      final RenderAnimatedSize restageLegal = _render(restageLegalKey);
      final RenderAnimatedSize nativeBounded = _render(nativeBoundedKey);
      final RenderAnimatedSize restageBounded = _render(restageBoundedKey);
      expect(restageLegal.size, nativeLegal.size);
      expect(restageLegal.getDryLayout(unbounded),
          nativeLegal.getDryLayout(unbounded));
      expect(restageBounded.size, nativeBounded.size);
      expect(restageBounded.getDryLayout(bounded),
          nativeBounded.getDryLayout(bounded));
    }

    expect(_render(nativeLegalKey).size, const Size(8e307, 20));
    expect(_render(nativeBoundedKey).size, const Size(1.5e308, 20));
    expect(tester.takeException(), isNull);
  });

  testWidgets('updates reverse churn reparent no-child and tight paths',
      (tester) async {
    final GlobalKey key = GlobalKey();
    StateSetter? update;
    double width = 20;
    Duration duration = const Duration(milliseconds: 400);
    Duration? reverseDuration = const Duration(milliseconds: 100);
    Curve curve = Curves.linear;
    AlignmentGeometry alignment = AlignmentDirectional.centerStart;
    Clip clipBehavior = Clip.hardEdge;
    TextDirection direction = TextDirection.ltr;
    bool secondSlot = false;
    var firstEnds = 0;
    var laterEnds = 0;
    VoidCallback onEnd = () => firstEnds++;

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          final Widget child = _ConstraintHost(
            childConstraints:
                const BoxConstraints(maxWidth: 200, maxHeight: 40),
            child: RestageAnimatedSize(
              key: key,
              duration: duration,
              reverseDuration: reverseDuration,
              curve: curve,
              alignment: alignment,
              clipBehavior: clipBehavior,
              onEnd: onEnd,
              child: SizedBox(width: width, height: 20),
            ),
          );
          return Directionality(
            textDirection: direction,
            child: Column(
              children: <Widget>[
                if (!secondSlot) child else const SizedBox(height: 24),
                if (secondSlot) child else const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
    await tester.pump();

    update!(() {
      width = 100;
      duration = const Duration(milliseconds: 600);
      reverseDuration = const Duration(milliseconds: 250);
      curve = Curves.easeIn;
      alignment = AlignmentDirectional.bottomEnd;
      clipBehavior = Clip.antiAlias;
      direction = TextDirection.rtl;
      onEnd = () => laterEnds++;
    });
    await tester.pump();
    final RenderAnimatedSize render = _render(key);
    expect(render.duration, duration);
    expect(render.reverseDuration, reverseDuration);
    expect(render.curve, curve);
    expect(render.alignment, alignment);
    expect(render.textDirection, direction);
    expect(render.clipBehavior, clipBehavior);
    expect(render.onEnd, onEnd);

    await tester.pump(const Duration(milliseconds: 650));
    expect(render.size, const Size(100, 20));
    expect(firstEnds, 0);
    expect(laterEnds, 1);

    update!(() => width = 20);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(render.isAnimating, isTrue);
    await tester.pump(const Duration(milliseconds: 310));
    expect(render.size, const Size(20, 20));
    expect(laterEnds, 2);

    update!(() => width = 80);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    update!(() {
      width = 60;
      secondSlot = true;
    });
    await tester.pump();
    expect(_render(key), same(render));
    expect(render.attached, isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 650));
    expect(render.size, const Size(60, 20));
    expect(render.getDryLayout(render.constraints), render.size);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: <Widget>[
            RestageAnimatedSize(duration: Duration(milliseconds: 1)),
            SizedBox(
              width: 30,
              height: 25,
              child: RestageAnimatedSize(
                duration: Duration(milliseconds: 1),
                child: SizedBox(width: 10, height: 10),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    final List<RenderAnimatedSize> renders = tester
        .renderObjectList<RenderAnimatedSize>(
          find.byType(RestageAnimatedSize),
        )
        .toList();
    expect(renders[0].size, Size.zero);
    expect(renders[1].size, const Size(30, 25));
    expect(tester.takeException(), isNull);
  });
}
