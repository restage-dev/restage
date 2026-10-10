// Exercises derived layout overflow through generated factories and a real
// Runtime, checking offsets, dry geometry, constraints and intrinsic widths.

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart';

const LibraryName _coreLibrary = LibraryName(<String>['restage', 'core']);
const LibraryName _probeLibrary = LibraryName(<String>['render', 'probe']);
const LibraryName _applicationLibrary = LibraryName(<String>[
  'application',
  'widgets',
]);
const LibraryName _rootLibrary = LibraryName(<String>['restage', 'paywall']);

const double _kViewport = 300;
const double _kChildExtent = 10;

const String _threeChildren = '''
[
  SizedBox(width: 10.0, height: 10.0),
  SizedBox(width: 10.0, height: 10.0),
  SizedBox(width: 10.0, height: 10.0)
]
''';

const String _fourChildren = '''
[
  SizedBox(width: 10.0, height: 10.0),
  SizedBox(width: 10.0, height: 10.0),
  SizedBox(width: 10.0, height: 10.0),
  SizedBox(width: 10.0, height: 10.0)
]
''';

Widget _buildConstraintProbe(BuildContext context, DataSource source) =>
    _ConstraintProbe(
      intrinsicWidth:
          source.v<double>(<Object>['intrinsicWidth']) ?? _kChildExtent,
      intrinsicHeight:
          source.v<double>(<Object>['intrinsicHeight']) ?? _kChildExtent,
      naturalWidth: source.v<double>(<Object>['naturalWidth']) ?? 0,
      naturalHeight: source.v<double>(<Object>['naturalHeight']) ?? 0,
      failWidthIntrinsic:
          source.v<bool>(<Object>['failWidthIntrinsic']) ?? false,
      heightFromWidth: source.v<bool>(<Object>['heightFromWidth']) ?? false,
      baseline: source.v<double>(<Object>['baseline']),
      omitDryBaseline: source.v<bool>(<Object>['omitDryBaseline']) ?? false,
    );

Widget _buildBaselineProbe(BuildContext context, DataSource source) =>
    _BaselineProbe(child: source.child(<Object>['child']));

Widget _buildApplicationIntrinsicWidth(
  BuildContext context,
  DataSource source,
) =>
    const _ApplicationIntrinsicWidth();

Widget _buildApplicationAspectRatio(BuildContext context, DataSource source) =>
    const _ApplicationAspectRatio();

Widget _buildApplicationFittedBox(BuildContext context, DataSource source) =>
    const _ApplicationFittedBox();

class _ApplicationIntrinsicWidth extends StatelessWidget {
  const _ApplicationIntrinsicWidth();

  @override
  Widget build(BuildContext context) => const SizedBox(width: 7, height: 5);
}

class _ApplicationAspectRatio extends StatelessWidget {
  const _ApplicationAspectRatio();

  @override
  Widget build(BuildContext context) => const SizedBox(width: 7, height: 5);
}

class _ApplicationFittedBox extends StatelessWidget {
  const _ApplicationFittedBox();

  @override
  Widget build(BuildContext context) => const SizedBox(width: 7, height: 5);
}

class _ConstraintProbe extends LeafRenderObjectWidget {
  const _ConstraintProbe({
    super.key,
    this.intrinsicWidth = _kChildExtent,
    this.intrinsicHeight = _kChildExtent,
    this.naturalWidth = 0,
    this.naturalHeight = 0,
    this.failWidthIntrinsic = false,
    this.heightFromWidth = false,
    this.baseline,
    this.omitDryBaseline = false,
  });

  final double intrinsicWidth;
  final double intrinsicHeight;
  final double naturalWidth;
  final double naturalHeight;
  final bool failWidthIntrinsic;
  final bool heightFromWidth;
  final double? baseline;
  final bool omitDryBaseline;

  @override
  _RenderConstraintProbe createRenderObject(BuildContext context) =>
      _RenderConstraintProbe(
        intrinsicWidth: intrinsicWidth,
        intrinsicHeight: intrinsicHeight,
        naturalWidth: naturalWidth,
        naturalHeight: naturalHeight,
        failWidthIntrinsic: failWidthIntrinsic,
        heightFromWidth: heightFromWidth,
        baseline: baseline,
        omitDryBaseline: omitDryBaseline,
      );
}

class _RenderConstraintProbe extends RenderBox {
  _RenderConstraintProbe({
    required this.intrinsicWidth,
    required this.intrinsicHeight,
    required this.naturalWidth,
    required this.naturalHeight,
    required this.failWidthIntrinsic,
    required this.heightFromWidth,
    required this.baseline,
    required this.omitDryBaseline,
  });

  final double intrinsicWidth;
  final double intrinsicHeight;
  final double naturalWidth;
  final double naturalHeight;
  final bool failWidthIntrinsic;
  final bool heightFromWidth;
  final double? baseline;
  final bool omitDryBaseline;
  BoxConstraints? receivedConstraints;
  double? lastIntrinsicWidthHeight;
  double? lastIntrinsicHeightWidth;

  // Record the exact argument before RenderObject's debug-only validation. This
  // keeps the observation available even when an invalid derived constraint
  // prevents performLayout from running.
  @override
  void layout(Constraints constraints, {bool parentUsesSize = false}) {
    if (constraints is BoxConstraints) {
      receivedConstraints = constraints;
    }
    super.layout(constraints, parentUsesSize: parentUsesSize);
  }

  @override
  void performLayout() {
    size = constraints.constrain(Size(naturalWidth, naturalHeight));
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    return constraints.constrain(Size(naturalWidth, naturalHeight));
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    lastIntrinsicWidthHeight = height;
    if (failWidthIntrinsic) {
      throw StateError('Width intrinsic should not be requested.');
    }
    return intrinsicWidth;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    lastIntrinsicWidthHeight = height;
    if (failWidthIntrinsic) {
      throw StateError('Width intrinsic should not be requested.');
    }
    return intrinsicWidth;
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    lastIntrinsicHeightWidth = width;
    return heightFromWidth ? width : intrinsicHeight;
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    lastIntrinsicHeightWidth = width;
    return heightFromWidth ? width : intrinsicHeight;
  }

  @override
  double? computeDryBaseline(
    covariant BoxConstraints constraints,
    TextBaseline baseline,
  ) {
    if (omitDryBaseline) {
      return null;
    }
    return this.baseline ?? (constraints.hasTightHeight ? 31.0 : 17.0);
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      this.baseline;

  @override
  bool hitTestSelf(Offset position) => true;
}

class _ConstraintHost extends SingleChildRenderObjectWidget {
  const _ConstraintHost({
    required this.childConstraints,
    required super.child,
  });

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

class _BaselineProbe extends SingleChildRenderObjectWidget {
  const _BaselineProbe({required super.child});

  @override
  _RenderBaselineProbe createRenderObject(BuildContext context) =>
      _RenderBaselineProbe();
}

class _RenderBaselineProbe extends RenderProxyBox {
  double? childBaseline;

  @override
  void performLayout() {
    child!.layout(constraints, parentUsesSize: true);
    childBaseline = child!.getDistanceToBaseline(
      TextBaseline.alphabetic,
      onlyReal: true,
    );
    size = child!.size;
  }
}

class _RenderConstraintHost extends RenderProxyBox {
  _RenderConstraintHost(this._childConstraints);

  BoxConstraints _childConstraints;

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
    size = constraints.constrain(child!.size);
  }
}

class _OverrideAlignmentGeometry extends AlignmentDirectional {
  const _OverrideAlignmentGeometry() : super(0, 0);

  @override
  Alignment resolve(TextDirection? direction) =>
      const _OverrideResolvedAlignment();
}

class _OverrideResolvedAlignment extends Alignment {
  const _OverrideResolvedAlignment() : super(0, 0);

  @override
  Offset alongOffset(Offset other) => const Offset(13, 17);
}

Future<void> _pump(
  WidgetTester tester,
  String paywallSource, {
  Map<String, Object?>? data,
  BoxConstraints? childConstraints,
  void Function(String, DynamicMap)? onEvent,
  TextDirection textDirection = TextDirection.ltr,
}) async {
  final runtime = Runtime()
    ..update(_coreLibrary, buildCoreWidgetLibrary())
    ..update(
      _probeLibrary,
      LocalWidgetLibrary(<String, LocalWidgetBuilder>{
        'BaselineProbe': _buildBaselineProbe,
        'ConstraintProbe': _buildConstraintProbe,
      }),
    )
    ..update(
      _applicationLibrary,
      LocalWidgetLibrary(<String, LocalWidgetBuilder>{
        'IntrinsicWidth': _buildApplicationIntrinsicWidth,
        'AspectRatio': _buildApplicationAspectRatio,
        'FittedBox': _buildApplicationFittedBox,
      }),
    )
    ..update(_rootLibrary, parseLibraryFile(paywallSource));
  final remote = RemoteWidget(
    runtime: runtime,
    data: DynamicContent(data ?? <String, Object?>{}),
    widget: const FullyQualifiedWidgetName(_rootLibrary, 'Paywall'),
    onEvent: onEvent ?? (_, __) {},
  );
  await tester.pumpWidget(
    Directionality(
      textDirection: textDirection,
      child: childConstraints == null
          ? Center(
              child: SizedBox(
                width: _kViewport,
                height: _kViewport,
                child: remote,
              ),
            )
          : _ConstraintHost(
              childConstraints: childConstraints,
              child: remote,
            ),
    ),
  );
  await tester.pump();
}

RemoteWidget _animatedAlignRemote(
  DynamicContent data,
  String source,
  void Function(String, DynamicMap) onEvent,
) {
  final runtime = Runtime()
    ..update(_coreLibrary, buildCoreWidgetLibrary())
    ..update(_rootLibrary, parseLibraryFile(source));
  return RemoteWidget(
    runtime: runtime,
    data: data,
    widget: const FullyQualifiedWidgetName(_rootLibrary, 'Paywall'),
    onEvent: onEvent,
  );
}

String _source(String child, {bool importsProbe = false}) => '''
import restage.core;
${importsProbe ? 'import render.probe;' : ''}
widget Paywall = Offstage(child: $child);
''';

Finder _findWidget(Type type) => find.byType(type, skipOffstage: false);

List<Offset> _childOffsets(List<RenderBox> children) => children
    .map(
      (child) =>
          (child.parentData! as ContainerBoxParentData<RenderBox>).offset,
    )
    .toList();

RenderFlex _flex(WidgetTester tester, Type type) =>
    tester.renderObject<RenderFlex>(_findWidget(type));

RenderWrap _wrap(WidgetTester tester) =>
    tester.renderObject<RenderWrap>(_findWidget(RestageWrap));

_RenderConstraintProbe _probe(WidgetTester tester) =>
    tester.renderObject<_RenderConstraintProbe>(_findWidget(_ConstraintProbe));

RenderIntrinsicWidth _intrinsicWidth(WidgetTester tester) =>
    tester.renderObject<RenderIntrinsicWidth>(
      find.byWidgetPredicate(
        (widget) => widget is IntrinsicWidth,
        skipOffstage: false,
      ),
    );

RenderAspectRatio _aspectRatio(WidgetTester tester) =>
    tester.renderObject<RenderAspectRatio>(_findWidget(RestageAspectRatio));

RenderFittedBox _fittedBox(WidgetTester tester) =>
    tester.renderObject<RenderFittedBox>(_findWidget(RestageFittedBox));

RenderPositionedBox _positioned(WidgetTester tester, Type type) =>
    tester.renderObject<RenderPositionedBox>(_findWidget(type));

void main() {
  group('flex spacing remains representable after child-count multiplication',
      () {
    testWidgets(
        'row child offsets stay finite when spacing multiplication grows',
        (tester) async {
      await _pump(
        tester,
        _source('Row(spacing: data.spacing, children: $_threeChildren)'),
        data: <String, Object?>{'spacing': 1e308},
      );

      final layoutException = tester.takeException();
      final offsets =
          _childOffsets(_flex(tester, RestageRow).getChildrenAsList());

      // RenderFlex clamps its own width to the 300px incoming maximum. These
      // horizontal child offsets are computed from the derived spacing after
      // that size is chosen, so the size clamp cannot make them finite.
      expect(
          offsets.map((offset) => offset.dx).every((x) => x.isFinite), isTrue);
      expect(layoutException, isNull);
    });

    testWidgets(
        'column child offsets stay finite when spacing multiplication grows',
        (tester) async {
      await _pump(
        tester,
        _source('Column(spacing: data.spacing, children: $_threeChildren)'),
        data: <String, Object?>{'spacing': 1e308},
      );

      final layoutException = tester.takeException();
      final offsets =
          _childOffsets(_flex(tester, RestageColumn).getChildrenAsList());

      // RenderFlex clamps its own height to the 300px incoming maximum. These
      // vertical child offsets retain the accumulated spacing directly and are
      // never passed through that clamp.
      expect(
          offsets.map((offset) => offset.dy).every((y) => y.isFinite), isTrue);
      expect(layoutException, isNull);
    });

    testWidgets(
        'row intrinsic width stays finite when spacing multiplication grows',
        (tester) async {
      await _pump(
        tester,
        _source(
          'SingleChildScrollView(scrollDirection: "horizontal", '
          'child: IntrinsicWidth(child: '
          'Row(spacing: data.spacing, children: $_threeChildren)))',
        ),
        data: <String, Object?>{'spacing': 1e308},
      );

      final layoutException = tester.takeException();
      final intrinsicWidth =
          _flex(tester, RestageRow).getMaxIntrinsicWidth(_kViewport);

      // This is the intrinsic result returned by RenderFlex itself. No box
      // constraint is applied to the value before this assertion can observe it.
      expect(intrinsicWidth.isFinite, isTrue);
      expect(layoutException, isNull);
    });

    testWidgets('finite flex spacing is honoured in offsets and intrinsics',
        (tester) async {
      await _pump(
        tester,
        _source('Row(spacing: data.spacing, children: $_threeChildren)'),
        data: <String, Object?>{'spacing': 1e3},
      );

      final layoutException = tester.takeException();
      final render = _flex(tester, RestageRow);
      final offsets = _childOffsets(render.getChildrenAsList());

      // Offsets expose the authored spacing without the flex box's own size
      // clamp, and the intrinsic query independently preserves the same value.
      expect(
        offsets.map((offset) => offset.dx).toList(),
        const <double>[0, 1010, 2020],
      );
      expect(render.getMaxIntrinsicWidth(_kViewport), 2030);
      expect(layoutException, isNull);
    });
  });

  group('wrap spacing remains representable while runs are accumulated', () {
    testWidgets('one-run wrap main-axis geometry stays finite', (tester) async {
      await _pump(
        tester,
        _source(
          'SingleChildScrollView(scrollDirection: "horizontal", '
          'child: Wrap(spacing: data.spacing, children: $_threeChildren))',
        ),
        data: <String, Object?>{'spacing': 1e308},
      );

      final layoutException = tester.takeException();
      final render = _wrap(tester);
      final dryWidth = render.getDryLayout(render.constraints).width;

      // The render object's real main-axis constraint is unbounded, keeping all
      // three children on one run. With no finite maximum available, constraint
      // clamping cannot hide the accumulated width returned by dry layout.
      expect(dryWidth.isFinite, isTrue);
      expect(layoutException, isNull);
    });

    testWidgets('three-run wrap cross-axis geometry stays finite',
        (tester) async {
      await _pump(
        tester,
        _source(
          'SingleChildScrollView(child: Center(child: '
          'SizedBox(width: 10.0, child: '
          'Wrap(runSpacing: data.runSpacing, children: $_threeChildren))))',
        ),
        data: <String, Object?>{'runSpacing': 1e308},
      );

      final layoutException = tester.takeException();
      final render = _wrap(tester);
      final dryHeight = render.getDryLayout(render.constraints).height;

      // The 10px main-axis bound makes one run per child, while the real cross
      // axis remains unbounded. The returned dry height therefore exposes the
      // accumulated run spacing without a finite clamp.
      expect(dryHeight.isFinite, isTrue);
      expect(layoutException, isNull);
    });

    testWidgets('finite wrap spacing and run spacing are honoured exactly',
        (tester) async {
      await _pump(
        tester,
        _source(
          'SingleChildScrollView(scrollDirection: "horizontal", '
          'child: SizedBox(width: 1020.0, child: '
          'Wrap(spacing: data.spacing, runSpacing: data.runSpacing, '
          'children: $_fourChildren)))',
        ),
        data: <String, Object?>{
          'spacing': 1e3,
          'runSpacing': 1e3,
        },
      );

      final layoutException = tester.takeException();
      final offsets = _childOffsets(_wrap(tester).getChildrenAsList());

      // Child offsets retain both authored values directly even though the
      // wrap's own cross-axis size is constrained by the viewport.
      expect(
        offsets,
        const <Offset>[
          Offset(0, 0),
          Offset(1010, 0),
          Offset(0, 1010),
          Offset(1010, 1010),
        ],
      );
      expect(layoutException, isNull);
    });
  });

  group('fractional child constraints remain representable', () {
    testWidgets('a huge finite width factor gives the child finite bounds',
        (tester) async {
      await _pump(
        tester,
        _source(
          'FractionallySizedBox(widthFactor: data.factor, '
          'child: ConstraintProbe())',
          importsProbe: true,
        ),
        data: <String, Object?>{'factor': 1e308},
      );

      final layoutException = tester.takeException();
      final received = _probe(tester).receivedConstraints;

      // The probe records the real tight width bounds at its layout entry. The
      // values are observed before any child or ancestor can constrain a size.
      expect(received, isNotNull);
      expect(received!.minWidth.isFinite, isTrue);
      expect(received.maxWidth.isFinite, isTrue);
      expect(layoutException, isNull);
    });

    testWidgets(
        'zero width factor on an unbounded axis matches unauthored constraints',
        (tester) async {
      await _pump(
        tester,
        _source(
          'Row(children: [FractionallySizedBox(widthFactor: data.factor, '
          'child: ConstraintProbe())])',
          importsProbe: true,
        ),
        data: <String, Object?>{'factor': 0.0},
      );

      final zeroFactorLayoutException = tester.takeException();
      final zeroFactorConstraints = _probe(tester).receivedConstraints;

      await _pump(
        tester,
        _source(
          'Row(children: [FractionallySizedBox(child: ConstraintProbe())])',
          importsProbe: true,
        ),
      );

      final unauthoredLayoutException = tester.takeException();
      final unauthoredConstraints = _probe(tester).receivedConstraints;

      // A Row gives this non-flex child an unbounded maximum width. An infinite
      // maximum is correct here because it is the ambient incoming constraint
      // passed through untouched, not a value derived from the factor.
      expect(zeroFactorConstraints, isNotNull);
      expect(unauthoredConstraints, isNotNull);
      expect(zeroFactorConstraints!.minWidth.isNaN, isFalse);
      expect(zeroFactorConstraints.maxWidth.isNaN, isFalse);
      expect(zeroFactorConstraints, unauthoredConstraints);
      expect(zeroFactorLayoutException, isNull);
      expect(unauthoredLayoutException, isNull);
    });

    testWidgets('a half width factor gives the child exactly half the width',
        (tester) async {
      await _pump(
        tester,
        _source(
          'FractionallySizedBox(widthFactor: data.factor, '
          'child: ConstraintProbe())',
          importsProbe: true,
        ),
        data: <String, Object?>{'factor': 0.5},
      );

      final layoutException = tester.takeException();
      final received = _probe(tester).receivedConstraints;

      // These are the exact tight bounds received by the child, not a
      // reconstruction from the factor.
      expect(received, isNotNull);
      expect(received!.minWidth, _kViewport * 0.5);
      expect(received.maxWidth, _kViewport * 0.5);
      expect(layoutException, isNull);
    });
  });

  group('fractional intrinsic division remains representable', () {
    testWidgets('zero width factor yields a finite intrinsic width',
        (tester) async {
      await _pump(
        tester,
        _source(
          'Row(children: [IntrinsicWidth(child: '
          'FractionallySizedBox(widthFactor: data.factor, '
          'child: ConstraintProbe()))])',
          importsProbe: true,
        ),
        data: <String, Object?>{'factor': 0.0},
      );

      final layoutException = tester.takeException();
      final render = tester.renderObject<RenderFractionallySizedOverflowBox>(
        _findWidget(RestageFractionallySizedBox),
      );
      final intrinsicWidth = render.getMaxIntrinsicWidth(_kViewport);

      // This is the quotient returned by the fractional render object. It is
      // observed before IntrinsicWidth can turn it into a child constraint.
      expect(intrinsicWidth.isFinite, isTrue);
      expect(layoutException, isNull);
    });

    testWidgets('a half width factor doubles the child intrinsic width',
        (tester) async {
      await _pump(
        tester,
        _source(
          'Row(children: [IntrinsicWidth(child: '
          'FractionallySizedBox(widthFactor: data.factor, '
          'child: ConstraintProbe()))])',
          importsProbe: true,
        ),
        data: <String, Object?>{'factor': 0.5},
      );

      final layoutException = tester.takeException();
      final render = tester.renderObject<RenderFractionallySizedOverflowBox>(
        _findWidget(RestageFractionallySizedBox),
      );

      // The render object's returned intrinsic is the 10px child's intrinsic
      // divided by the authored factor, with no constraint clamp in between.
      expect(render.getMaxIntrinsicWidth(_kViewport), 20);
      expect(layoutException, isNull);
    });

    testWidgets('repairs only NaN intrinsic arguments', (tester) async {
      await _pump(
        tester,
        _source(
          'FractionallySizedBox(heightFactor: data.factor, '
          'child: ConstraintProbe())',
          importsProbe: true,
        ),
        data: <String, Object?>{'factor': 0.0},
      );

      final render = tester.renderObject<RenderFractionallySizedOverflowBox>(
        _findWidget(RestageFractionallySizedBox),
      );
      expect(render.getMaxIntrinsicWidth(double.infinity), _kChildExtent);
      expect(_probe(tester).lastIntrinsicWidthHeight, double.infinity);

      await _pump(
        tester,
        _source(
          'FractionallySizedBox(heightFactor: data.factor, '
          'child: ConstraintProbe())',
          importsProbe: true,
        ),
        data: <String, Object?>{'factor': 2.0},
      );

      final overflowRender =
          tester.renderObject<RenderFractionallySizedOverflowBox>(
        _findWidget(RestageFractionallySizedBox),
      );
      expect(overflowRender.getMaxIntrinsicWidth(1e308), _kChildExtent);
      expect(_probe(tester).lastIntrinsicWidthHeight, double.infinity);
      expect(tester.takeException(), isNull);
    });

    testWidgets('guards generated fractional offsets and baselines',
        (tester) async {
      await _pump(
        tester,
        _source(
          'BaselineProbe(child: FractionallySizedBox('
          'alignment: {x: 1e308, y: 3.0}, widthFactor: 0.25, '
          'heightFactor: 0.5882352941176471, child: ConstraintProbe('
          'naturalWidth: 20.0, naturalHeight: 1e308, baseline: 1e308)))',
          importsProbe: true,
        ),
        childConstraints: const BoxConstraints.tightFor(
          width: 80,
          height: 1.7e308,
        ),
      );

      final render = tester.renderObject<RenderFractionallySizedOverflowBox>(
        _findWidget(RestageFractionallySizedBox),
      );
      final offset = (render.child!.parentData! as BoxParentData).offset;
      final host = tester.renderObject<_RenderBaselineProbe>(
        _findWidget(_BaselineProbe),
      );
      expect(offset.dx, 30);
      expect(offset.dy, 1.3999999999999999e308);
      expect(host.childBaseline, isNull);
      expect(
        render.getDryBaseline(
          render.constraints,
          TextBaseline.alphabetic,
        ),
        isNull,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('shifted geometry remains representable', () {
    testWidgets('direct alignment preserves resolved offset behavior',
        (tester) async {
      const nativeHostKey = ValueKey<String>('native alignment host');
      const nativeChildKey = ValueKey<String>('native alignment child');
      const restageHostKey = ValueKey<String>('restage alignment host');
      const restageChildKey = ValueKey<String>('restage alignment child');
      const alignment = _OverrideAlignmentGeometry();

      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 100,
                height: 100,
                child: Align(
                  key: nativeHostKey,
                  alignment: alignment,
                  child: SizedBox(
                    key: nativeChildKey,
                    width: 20,
                    height: 20,
                  ),
                ),
              ),
              SizedBox(
                width: 100,
                height: 100,
                child: RestageAlign(
                  key: restageHostKey,
                  alignment: alignment,
                  child: SizedBox(
                    key: restageChildKey,
                    width: 20,
                    height: 20,
                  ),
                ),
              ),
            ],
          ),
        ),
      );

      final nativeOffset = tester.getTopLeft(find.byKey(nativeChildKey)) -
          tester.getTopLeft(find.byKey(nativeHostKey));
      final restageOffset = tester.getTopLeft(find.byKey(restageChildKey)) -
          tester.getTopLeft(find.byKey(restageHostKey));
      expect(nativeOffset, const Offset(13, 17));
      expect(restageOffset, nativeOffset);
      expect(tester.takeException(), isNull);
    });

    testWidgets('generated alignment centers only a failed offset axis',
        (tester) async {
      await _pump(
        tester,
        _source(
          'Align(alignment: {x: data.x, y: 0.5}, '
          'child: SizedBox(width: 20.0, height: 20.0))',
        ),
        data: <String, Object?>{'x': 1e308},
      );

      var render = _positioned(tester, RestageAlign);
      var childOffset = (render.child!.parentData! as BoxParentData).offset;
      expect(render.size, const Size(_kViewport, _kViewport));
      expect(childOffset, const Offset(140, 210));
      expect(tester.takeException(), isNull);

      await _pump(
        tester,
        _source(
          'Align(alignment: {x: data.x, y: 0.5}, '
          'child: SizedBox(width: 20.0, height: 20.0))',
        ),
        data: <String, Object?>{'x': 1e300},
      );

      render = _positioned(tester, RestageAlign);
      childOffset = (render.child!.parentData! as BoxParentData).offset;
      expect(
          childOffset,
          const Alignment(1e300, 0.5).alongOffset(
            const Offset(_kViewport - 20, _kViewport - 20),
          ));

      await _pump(
        tester,
        _source(
          'Align(alignment: {start: data.start, y: -0.5}, '
          'child: SizedBox(width: 20.0, height: 20.0))',
        ),
        data: <String, Object?>{'start': 1e308},
      );
      render = _positioned(tester, RestageAlign);
      childOffset = (render.child!.parentData! as BoxParentData).offset;
      expect(childOffset.dx, 140);
      expect(childOffset.dy, 70);
      expect(tester.takeException(), isNull);
    });

    testWidgets('generated factors guard actual dry and intrinsic results',
        (tester) async {
      await _pump(
        tester,
        _source(
          'Row(children: [Align(widthFactor: data.factor, '
          'heightFactor: data.factor, child: ConstraintProbe('
          'naturalWidth: 1e308, naturalHeight: 20.0, '
          'intrinsicWidth: 1e308, intrinsicHeight: 1e308))])',
          importsProbe: true,
        ),
        data: <String, Object?>{'factor': 2.0},
      );

      final render = _positioned(tester, RestageAlign);
      expect(render.size.width, 1e308);
      expect(render.getDryLayout(render.constraints).width, 1e308);
      expect(render.getMinIntrinsicWidth(20), 1e308);
      expect(render.getMaxIntrinsicWidth(20), 1e308);
      expect(render.getMinIntrinsicHeight(20), 1e308);
      expect(render.getMaxIntrinsicHeight(20), 1e308);
      expect(tester.takeException(), isNull);

      await _pump(
        tester,
        _source(
          'Align(widthFactor: data.factor, child: ConstraintProbe('
          'naturalWidth: 1e308, naturalHeight: 20.0))',
          importsProbe: true,
        ),
        data: <String, Object?>{'factor': 2.0},
        childConstraints: const BoxConstraints(
          maxWidth: 1.5e308,
          maxHeight: 40,
        ),
      );

      final bounded = _positioned(tester, RestageAlign);
      expect(bounded.size.width, 1.5e308);
      expect(bounded.getDryLayout(bounded.constraints).width, 1.5e308);
      expect(tester.takeException(), isNull);
    });

    testWidgets('generated optional baseline overflow becomes absent',
        (tester) async {
      await _pump(
        tester,
        _source(
          'BaselineProbe(child: Align(alignment: {x: 0.0, y: 3.0}, '
          'child: ConstraintProbe('
          'naturalWidth: 20.0, naturalHeight: 1e308, baseline: 1e308)))',
          importsProbe: true,
        ),
        childConstraints: const BoxConstraints.tightFor(
          width: 80,
          height: 1.7e308,
        ),
      );

      var render = _positioned(tester, RestageAlign);
      final offset = (render.child!.parentData! as BoxParentData).offset;
      expect(offset.dy, 1.3999999999999999e308);
      final host = tester.renderObject<_RenderBaselineProbe>(
        _findWidget(_BaselineProbe),
      );
      expect(host.childBaseline, isNull);
      expect(
        render.getDryBaseline(
          render.constraints,
          TextBaseline.alphabetic,
        ),
        isNull,
      );
      expect(tester.takeException(), isNull);

      await _pump(
        tester,
        _source(
          'BaselineProbe(child: Align(child: Padding('
          'padding: [0.0, 0.0, 0.0, 0.0], child: ConstraintProbe('
          'naturalWidth: 20.0, naturalHeight: 20.0, baseline: 7.0))))',
          importsProbe: true,
        ),
        childConstraints: const BoxConstraints.tightFor(
          width: 80,
          height: 100,
        ),
      );

      render = _positioned(tester, RestageAlign);
      final finiteHost = tester.renderObject<_RenderBaselineProbe>(
        _findWidget(_BaselineProbe),
      );
      expect(finiteHost.childBaseline, 47);
      expect(
        render.getDryBaseline(
          render.constraints,
          TextBaseline.alphabetic,
        ),
        47,
      );

      await _pump(
        tester,
        _source(
          'BaselineProbe(child: Align(child: SizedBox(child: ConstraintProbe('
          'naturalWidth: 20.0, naturalHeight: 20.0, '
          'omitDryBaseline: true))))',
          importsProbe: true,
        ),
        childConstraints: const BoxConstraints.tightFor(
          width: 80,
          height: 100,
        ),
      );

      render = _positioned(tester, RestageAlign);
      final absentHost = tester.renderObject<_RenderBaselineProbe>(
        _findWidget(_BaselineProbe),
      );
      expect(absentHost.childBaseline, isNull);
      expect(
        render.getDryBaseline(
          render.constraints,
          TextBaseline.alphabetic,
        ),
        isNull,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('generated Center uses the guarded render object',
        (tester) async {
      await _pump(
        tester,
        _source('Center(widthFactor: 0.0, heightFactor: 0.0)'),
      );

      final widget = tester.widget<RestageCenter>(_findWidget(RestageCenter));
      final render = _positioned(tester, RestageCenter);
      expect(widget, isA<Center>());
      expect(render.size.isFinite, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('generated AnimatedAlign guards interpolated geometry',
        (tester) async {
      var ends = 0;
      const source = '''
import restage.core;
widget Paywall = Offstage(child: AnimatedAlign(
  alignment: {x: data.x, y: 0.5},
  widthFactor: data.factor,
  curve: "easeOutBack",
  duration: 1000,
  onEnd: event "aligned" {},
  child: SizedBox(width: 2.0, height: 20.0),
));
''';
      await _pump(
        tester,
        source,
        data: <String, Object?>{'x': 0.0, 'factor': 1.0},
        onEvent: (name, _) => ends += name == 'aligned' ? 1 : 0,
      );
      expect(_findWidget(RestageAnimatedAlign), findsOneWidget);

      await _pump(
        tester,
        source,
        data: <String, Object?>{'x': 1e308, 'factor': 1.7e308},
        onEvent: (name, _) => ends += name == 'aligned' ? 1 : 0,
      );
      await tester.pump(const Duration(milliseconds: 500));

      var align = tester.widget<RestageAlign>(_findWidget(RestageAlign));
      var render = _positioned(tester, RestageAlign);
      var offset = (render.child!.parentData! as BoxParentData).offset;
      expect(align.widthFactor, isNull);
      expect(render.size, const Size(_kViewport, _kViewport));
      expect(offset.dx, (_kViewport - 2) / 2);
      expect(offset.dy.isFinite, isTrue);
      expect(ends, 0);
      expect(tester.takeException(), isNull);

      await tester.pump(const Duration(milliseconds: 600));
      align = tester.widget<RestageAlign>(_findWidget(RestageAlign));
      render = _positioned(tester, RestageAlign);
      offset = (render.child!.parentData! as BoxParentData).offset;
      expect(align.widthFactor, 1.7e308);
      expect(render.size.width, _kViewport);
      expect(offset.dx, (_kViewport - 2) / 2);
      expect(ends, 1);
      expect(tester.takeException(), isNull);

      await _pump(
        tester,
        source,
        data: <String, Object?>{'x': 0.0, 'factor': 2.0},
        onEvent: (name, _) => ends += name == 'aligned' ? 1 : 0,
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      align = tester.widget<RestageAlign>(_findWidget(RestageAlign));
      render = _positioned(tester, RestageAlign);
      expect(align.widthFactor, 2.0);
      expect(render.size.isFinite, isTrue);
      expect(ends, 1);
      expect(tester.takeException(), isNull);

      final directionalSource = source.replaceFirst(
        '{x: data.x, y: 0.5}',
        '{start: data.x, y: 0.5}',
      );
      await _pump(
        tester,
        directionalSource,
        data: <String, Object?>{'x': 1e308},
        onEvent: (name, _) => ends += name == 'aligned' ? 1 : 0,
      );
      await tester.pump(const Duration(milliseconds: 500));

      align = tester.widget<RestageAlign>(_findWidget(RestageAlign));
      render = _positioned(tester, RestageAlign);
      offset = (render.child!.parentData! as BoxParentData).offset;
      expect(align.widthFactor, isNull);
      expect(offset.dx, (_kViewport - 2) / 2);
      expect(offset.dy.isFinite, isTrue);
      expect(ends, 1);
      expect(tester.takeException(), isNull);

      await tester.pump(const Duration(milliseconds: 600));
      align = tester.widget<RestageAlign>(_findWidget(RestageAlign));
      render = _positioned(tester, RestageAlign);
      offset = (render.child!.parentData! as BoxParentData).offset;
      expect(align.alignment, isA<AlignmentDirectional>());
      expect(align.widthFactor, 2.0);
      expect(offset.dx, (_kViewport - 2) / 2);
      expect(offset.dy.isFinite, isTrue);
      expect(ends, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('generated AnimatedAlign preserves linear RTL updates',
        (tester) async {
      var ends = 0;
      const source = '''
import restage.core;
widget Paywall = Offstage(child: AnimatedAlign(
  alignment: {start: data.start, y: 0.0},
  widthFactor: data.factor,
  curve: "linear",
  duration: 1000,
  onEnd: event "aligned" {},
  child: SizedBox(width: 20.0, height: 20.0),
));
''';
      await _pump(
        tester,
        source,
        data: <String, Object?>{'start': -1.0, 'factor': 1.0},
        onEvent: (name, _) => ends += name == 'aligned' ? 1 : 0,
      );

      var align = tester.widget<RestageAlign>(_findWidget(RestageAlign));
      var render = _positioned(tester, RestageAlign);
      var offset = (render.child!.parentData! as BoxParentData).offset;
      expect(align.widthFactor, 1.0);
      expect(offset, const Offset(0, 140));

      await _pump(
        tester,
        source,
        data: <String, Object?>{'start': 1.0, 'factor': 2.0},
        onEvent: (name, _) => ends += name == 'aligned' ? 1 : 0,
      );
      await tester.pump(const Duration(milliseconds: 500));

      align = tester.widget<RestageAlign>(_findWidget(RestageAlign));
      render = _positioned(tester, RestageAlign);
      offset = (render.child!.parentData! as BoxParentData).offset;
      expect(align.widthFactor, 1.5);
      expect(offset, const Offset(140, 140));
      expect(ends, 0);

      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      align = tester.widget<RestageAlign>(_findWidget(RestageAlign));
      render = _positioned(tester, RestageAlign);
      offset = (render.child!.parentData! as BoxParentData).offset;
      expect(align.widthFactor, 2.0);
      expect(offset, const Offset(280, 140));
      expect(ends, 1);

      await _pump(
        tester,
        source,
        data: <String, Object?>{'start': 1.0, 'factor': 2.0},
        onEvent: (name, _) => ends += name == 'aligned' ? 1 : 0,
        textDirection: TextDirection.rtl,
      );

      align = tester.widget<RestageAlign>(_findWidget(RestageAlign));
      render = _positioned(tester, RestageAlign);
      offset = (render.child!.parentData! as BoxParentData).offset;
      expect(align.widthFactor, 2.0);
      expect(offset, const Offset(0, 140));
      expect(ends, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('generated AnimatedAlign retargets after directional overflow',
        (tester) async {
      var ends = 0;
      final data = DynamicContent(<String, Object?>{
        'start': 0.0,
        'y': 0.0,
      });
      final remote = _animatedAlignRemote(
        data,
        '''
import restage.core;
widget Paywall = AnimatedAlign(
  alignment: {start: data.start, y: data.y},
  curve: "easeOutBack",
  duration: 1000,
  onEnd: event "aligned" {},
  child: SizedBox(width: 20.0, height: 20.0),
);
''',
        (name, _) => ends += name == 'aligned' ? 1 : 0,
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(width: 300, height: 300, child: remote),
          ),
        ),
      );
      await tester.pump();

      data
        ..update('start', double.maxFinite)
        ..update('y', 40.0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      var align = tester.widget<RestageAlign>(_findWidget(RestageAlign));
      var render = _positioned(tester, RestageAlign);
      var raw = align.alignment.resolve(TextDirection.ltr);
      var offset = (render.child!.parentData! as BoxParentData).offset;
      expect(raw.x.isFinite, isFalse);
      expect(raw.y.isFinite, isTrue);
      expect(offset.dx, 140);
      expect(offset.dy.isFinite, isTrue);
      final finiteY = raw.y;

      data
        ..update('start', 12.0)
        ..update('y', 6.0);
      await tester.pump();

      align = tester.widget<RestageAlign>(_findWidget(RestageAlign));
      raw = align.alignment.resolve(TextDirection.ltr);
      expect(raw.x, 0);
      expect(raw.y, finiteY);

      await tester.pump(const Duration(milliseconds: 250));

      align = tester.widget<RestageAlign>(_findWidget(RestageAlign));
      render = _positioned(tester, RestageAlign);
      raw = align.alignment.resolve(TextDirection.ltr);
      offset = (render.child!.parentData! as BoxParentData).offset;
      expect(raw.x.isFinite, isTrue);
      expect(raw.y.isFinite, isTrue);
      expect(offset.dx.isFinite, isTrue);
      expect(offset.dy.isFinite, isTrue);
      expect(tester.takeException(), isNull);

      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump();
      align = tester.widget<RestageAlign>(_findWidget(RestageAlign));
      render = _positioned(tester, RestageAlign);
      offset = (render.child!.parentData! as BoxParentData).offset;
      expect(
        align.alignment.resolve(TextDirection.ltr),
        const Alignment(12, 6),
      );
      expect(offset, const Offset(1820, 980));
      expect(ends, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('RestageAnimatedAlign preserves native negative retargets',
        (tester) async {
      var restageEnds = 0;
      var nativeEnds = 0;
      var alignment = AlignmentDirectional.center;
      late StateSetter update;
      final restageKey = GlobalKey();
      final nativeKey = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Row(
                children: <Widget>[
                  SizedBox(
                    width: 300,
                    height: 300,
                    child: RestageAnimatedAlign(
                      key: restageKey,
                      alignment: alignment,
                      curve: Curves.easeInBack,
                      duration: const Duration(seconds: 1),
                      onEnd: () => restageEnds++,
                      child: const SizedBox(width: 20, height: 20),
                    ),
                  ),
                  SizedBox(
                    width: 300,
                    height: 300,
                    child: AnimatedAlign(
                      key: nativeKey,
                      alignment: alignment,
                      curve: Curves.easeInBack,
                      duration: const Duration(seconds: 1),
                      onEnd: () => nativeEnds++,
                      child: const SizedBox(width: 20, height: 20),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
      await tester.pump();

      update(
        () => alignment = const AlignmentDirectional(100, 4),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      var restage =
          restageKey.currentContext!.findRenderObject()! as RenderPositionedBox;
      var native =
          nativeKey.currentContext!.findRenderObject()! as RenderPositionedBox;
      var restageRaw = restage.alignment.resolve(TextDirection.ltr);
      var nativeRaw = native.alignment.resolve(TextDirection.ltr);
      expect(restageRaw.x, lessThan(0));
      expect(restageRaw.y, lessThan(0));
      expect(restageRaw, nativeRaw);

      update(
        () => alignment = const AlignmentDirectional(20, 2),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      restage =
          restageKey.currentContext!.findRenderObject()! as RenderPositionedBox;
      native =
          nativeKey.currentContext!.findRenderObject()! as RenderPositionedBox;
      restageRaw = restage.alignment.resolve(TextDirection.ltr);
      nativeRaw = native.alignment.resolve(TextDirection.ltr);
      expect(restageRaw, nativeRaw);
      expect(
        (restage.child!.parentData! as BoxParentData).offset,
        (native.child!.parentData! as BoxParentData).offset,
      );
      expect(tester.takeException(), isNull);

      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump();
      restage =
          restageKey.currentContext!.findRenderObject()! as RenderPositionedBox;
      native =
          nativeKey.currentContext!.findRenderObject()! as RenderPositionedBox;
      expect(
        restage.alignment.resolve(TextDirection.ltr),
        const Alignment(20, 2),
      );
      expect(
        restage.alignment.resolve(TextDirection.ltr),
        native.alignment.resolve(TextDirection.ltr),
      );
      expect(restageEnds, 1);
      expect(nativeEnds, 1);
      expect(tester.takeException(), isNull);
    });
  });

  group('aspect-ratio results remain representable', () {
    testWidgets('generated layout preserves legal native results',
        (tester) async {
      await _pump(
        tester,
        _source(
          'AspectRatio(aspectRatio: 1e-308, '
          'child: ConstraintProbe(naturalWidth: 4.0, naturalHeight: 3.0))',
          importsProbe: true,
        ),
        childConstraints: const BoxConstraints(maxWidth: 1),
      );

      expect(tester.takeException(), isNull);
      var render = _aspectRatio(tester);
      expect(render.size, const Size(1, 1e308));
      expect(render.getDryLayout(render.constraints), const Size(1, 1e308));
      expect(
        render.getDryBaseline(
          render.constraints,
          TextBaseline.alphabetic,
        ),
        31,
      );
      expect(
        tester.widget(_findWidget(RestageAspectRatio)),
        isA<AspectRatio>(),
      );

      await _pump(
        tester,
        _source('AspectRatio(aspectRatio: 1e-320)'),
        childConstraints: const BoxConstraints(maxWidth: 1, maxHeight: 0.5),
      );

      expect(tester.takeException(), isNull);
      render = _aspectRatio(tester);
      final native = RenderAspectRatio(aspectRatio: 1e-320);
      final nativeSize = native.getDryLayout(render.constraints);
      expect(nativeSize.isFinite, isTrue);
      expect(render.size, nativeSize);
      expect(render.getDryLayout(render.constraints), nativeSize);
      native.dispose();
    });

    testWidgets('generated dry and intrinsic overflow fails before returning',
        (tester) async {
      await _pump(
        tester,
        _source(
          'AspectRatio(aspectRatio: 1e-320, '
          'child: ConstraintProbe(naturalWidth: 4.0, naturalHeight: 3.0))',
          importsProbe: true,
        ),
        childConstraints: const BoxConstraints(maxWidth: 1, maxHeight: 0.5),
      );

      expect(tester.takeException(), isNull);
      var render = _aspectRatio(tester);
      const divisionConstraints = BoxConstraints(maxWidth: 1);
      expect(
        () => render.getMinIntrinsicHeight(1),
        throwsA(isA<FlutterError>()),
      );
      expect(
        () => render.getMaxIntrinsicHeight(1),
        throwsA(isA<FlutterError>()),
      );
      expect(
        () => render.getDryBaseline(
          divisionConstraints,
          TextBaseline.alphabetic,
        ),
        throwsA(isA<FlutterError>()),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await _pump(
        tester,
        _source('AspectRatio(aspectRatio: 1e-320)'),
        childConstraints: const BoxConstraints(maxWidth: 1, maxHeight: 0.5),
      );
      expect(tester.takeException(), isNull);
      render = _aspectRatio(tester);
      expect(
        () => render.getDryLayout(divisionConstraints),
        throwsA(isA<FlutterError>()),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await _pump(
        tester,
        _source('AspectRatio(aspectRatio: 1e308)'),
        childConstraints: const BoxConstraints(maxHeight: 1),
      );
      expect(tester.takeException(), isNull);
      render = _aspectRatio(tester);
      const multiplicationConstraints = BoxConstraints(maxHeight: 2);
      expect(
        () => render.getMinIntrinsicWidth(2),
        throwsA(isA<FlutterError>()),
      );
      expect(
        () => render.getMaxIntrinsicWidth(2),
        throwsA(isA<FlutterError>()),
      );
      expect(
        () => render.getDryLayout(multiplicationConstraints),
        throwsA(isA<FlutterError>()),
      );
    });

    testWidgets('generated realization keeps custom namespaces distinct',
        (tester) async {
      await _pump(
        tester,
        '''
import application.widgets;
widget Paywall = AspectRatio();
''',
      );

      expect(tester.takeException(), isNull);
      expect(_findWidget(_ApplicationAspectRatio), findsOneWidget);
      expect(_findWidget(RestageAspectRatio), findsNothing);
    });
  });

  group('fitted-box aspect preservation remains representable', () {
    for (final fit in <String>['contain', 'scaleDown']) {
      testWidgets('generated $fit repairs only a non-finite native result',
          (tester) async {
        await _pump(
          tester,
          _source(
            'FittedBox(fit: "$fit", child: ConstraintProbe('
            'naturalWidth: 1e308, naturalHeight: 0.1))',
            importsProbe: true,
          ),
          childConstraints: const BoxConstraints(maxHeight: 0.05),
        );

        expect(tester.takeException(), isNull);
        final render = _fittedBox(tester);
        expect(render.size, const Size(1e308, 0.05));
        expect(
          render.getDryLayout(render.constraints),
          const Size(1e308, 0.05),
        );
        expect(_probe(tester).size, const Size(1e308, 0.1));
      });

      testWidgets('generated $fit preserves a finite native result',
          (tester) async {
        await _pump(
          tester,
          _source(
            'FittedBox(fit: "$fit", child: ConstraintProbe('
            'naturalWidth: 1e307, naturalHeight: 0.1))',
            importsProbe: true,
          ),
          childConstraints: const BoxConstraints(maxHeight: 0.05),
        );

        expect(tester.takeException(), isNull);
        final render = _fittedBox(tester);
        expect(render.size, const Size(5.0000000000000006e306, 0.05));
        expect(render.getDryLayout(render.constraints), render.size);
      });
    }

    testWidgets('no child and impossible expanding constraints stay explicit',
        (tester) async {
      const defaults = RestageFittedBox();
      expect(defaults.fit, BoxFit.contain);
      expect(defaults.alignment, Alignment.center);
      expect(defaults.clipBehavior, Clip.none);

      await _pump(
        tester,
        _source('FittedBox()'),
        childConstraints: const BoxConstraints(
          minWidth: 5,
          maxWidth: 50,
          minHeight: 7,
          maxHeight: 40,
        ),
      );

      expect(tester.takeException(), isNull);
      var render = _fittedBox(tester);
      expect(render.size, const Size(5, 7));
      expect(render.getDryLayout(render.constraints), const Size(5, 7));

      await _pump(
        tester,
        _source(
          'FittedBox(child: ConstraintProbe('
          'naturalWidth: 1e308, naturalHeight: 0.1))',
          importsProbe: true,
        ),
        childConstraints: const BoxConstraints(maxHeight: 0.05),
      );
      expect(tester.takeException(), isNull);
      render = _fittedBox(tester);
      const impossible = BoxConstraints(
        minWidth: double.infinity,
        maxWidth: double.infinity,
        maxHeight: 0.05,
      );
      expect(
        () => render.getDryLayout(impossible),
        throwsA(isA<FlutterError>()),
      );
    });

    testWidgets('layout, transform, hit test, and updates match Flutter',
        (tester) async {
      Future<void> pumpPair({
        required BoxFit fit,
        required TextDirection direction,
        required BoxConstraints constraints,
      }) async {
        await tester.pumpWidget(
          Directionality(
            textDirection: direction,
            child: Stack(
              children: <Widget>[
                _ConstraintHost(
                  childConstraints: constraints,
                  child: FittedBox(
                    key: const ValueKey<String>('native-fitted'),
                    fit: fit,
                    alignment: AlignmentDirectional.centerStart,
                    child: const _ConstraintProbe(
                      key: ValueKey<String>('native-fitted-child'),
                      naturalWidth: 40,
                      naturalHeight: 10,
                    ),
                  ),
                ),
                _ConstraintHost(
                  childConstraints: constraints,
                  child: RestageFittedBox(
                    key: const ValueKey<String>('restage-fitted'),
                    fit: fit,
                    alignment: AlignmentDirectional.centerStart,
                    child: const _ConstraintProbe(
                      key: ValueKey<String>('restage-fitted-child'),
                      naturalWidth: 40,
                      naturalHeight: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }

      void expectParity() {
        final native = tester.renderObject<RenderFittedBox>(
          find.byKey(const ValueKey<String>('native-fitted')),
        );
        final restage = tester.renderObject<RenderFittedBox>(
          find.byKey(const ValueKey<String>('restage-fitted')),
        );
        final nativeChild = tester.renderObject<RenderBox>(
          find.byKey(const ValueKey<String>('native-fitted-child')),
        );
        final restageChild = tester.renderObject<RenderBox>(
          find.byKey(const ValueKey<String>('restage-fitted-child')),
        );
        final nativeTransform = Matrix4.identity();
        final restageTransform = Matrix4.identity();
        native.applyPaintTransform(nativeChild, nativeTransform);
        restage.applyPaintTransform(restageChild, restageTransform);

        expect(restage.size, native.size);
        expect(restageChild.size, nativeChild.size);
        expect(restageTransform.storage, nativeTransform.storage);
        expect(
          restage.hitTest(
            BoxHitTestResult(),
            position: restage.size.center(Offset.zero),
          ),
          native.hitTest(
            BoxHitTestResult(),
            position: native.size.center(Offset.zero),
          ),
        );
      }

      for (var index = 0; index < BoxFit.values.length; index++) {
        await pumpPair(
          fit: BoxFit.values[index],
          direction: index.isEven ? TextDirection.ltr : TextDirection.rtl,
          constraints: index.isEven
              ? const BoxConstraints.tightFor(width: 80, height: 20)
              : const BoxConstraints.tightFor(width: 60, height: 30),
        );
        expect(tester.takeException(), isNull);
        expectParity();
      }
    });

    testWidgets('generated realization keeps custom namespaces distinct',
        (tester) async {
      await _pump(
        tester,
        '''
import application.widgets;
widget Paywall = FittedBox();
''',
      );

      expect(tester.takeException(), isNull);
      expect(_findWidget(_ApplicationFittedBox), findsOneWidget);
      expect(_findWidget(RestageFittedBox), findsNothing);
    });
  });

  group('intrinsic steps remain representable at each requested operation', () {
    testWidgets('legal operations match the framework widget', (tester) async {
      final cases = <({
        BoxConstraints constraints,
        double? stepWidth,
        double? stepHeight,
      })>[
        (
          constraints: const BoxConstraints(maxWidth: 100, maxHeight: 80),
          stepWidth: null,
          stepHeight: null,
        ),
        (
          constraints: const BoxConstraints(maxWidth: 100, maxHeight: 80),
          stepWidth: 7,
          stepHeight: 11,
        ),
        (
          constraints: const BoxConstraints(maxWidth: 100, maxHeight: 80),
          stepWidth: 0,
          stepHeight: 0,
        ),
        (
          constraints: const BoxConstraints(
            minWidth: 50,
            maxWidth: 50,
            maxHeight: 80,
          ),
          stepWidth: 7,
          stepHeight: null,
        ),
      ];

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: <Widget>[
              for (var index = 0; index < cases.length; index++) ...<Widget>[
                _ConstraintHost(
                  childConstraints: cases[index].constraints,
                  child: IntrinsicWidth(
                    key: ValueKey<String>('framework-$index'),
                    stepWidth: cases[index].stepWidth,
                    stepHeight: cases[index].stepHeight,
                    child: _ConstraintProbe(
                      key: ValueKey<String>('framework-child-$index'),
                      intrinsicWidth: 13,
                      intrinsicHeight: 17,
                      naturalWidth: 5,
                      naturalHeight: 6,
                    ),
                  ),
                ),
                _ConstraintHost(
                  childConstraints: cases[index].constraints,
                  child: RestageIntrinsicWidth(
                    key: ValueKey<String>('restage-$index'),
                    stepWidth: cases[index].stepWidth,
                    stepHeight: cases[index].stepHeight,
                    child: _ConstraintProbe(
                      key: ValueKey<String>('restage-child-$index'),
                      intrinsicWidth: 13,
                      intrinsicHeight: 17,
                      naturalWidth: 5,
                      naturalHeight: 6,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      for (var index = 0; index < cases.length; index++) {
        final framework = tester.renderObject<RenderIntrinsicWidth>(
          find.byKey(ValueKey<String>('framework-$index')),
        );
        final restage = tester.renderObject<RenderIntrinsicWidth>(
          find.byKey(ValueKey<String>('restage-$index')),
        );
        final frameworkChild = tester.renderObject<_RenderConstraintProbe>(
          find.byKey(ValueKey<String>('framework-child-$index')),
        );
        final restageChild = tester.renderObject<_RenderConstraintProbe>(
          find.byKey(ValueKey<String>('restage-child-$index')),
        );

        expect(restage.size, framework.size);
        expect(restageChild.receivedConstraints,
            frameworkChild.receivedConstraints);
        expect(
          restage.getMinIntrinsicWidth(37),
          framework.getMinIntrinsicWidth(37),
        );
        expect(
          restage.getMaxIntrinsicWidth(37),
          framework.getMaxIntrinsicWidth(37),
        );
        expect(
          restage.getMinIntrinsicHeight(double.infinity),
          framework.getMinIntrinsicHeight(double.infinity),
        );
        expect(
          restage.getMaxIntrinsicHeight(double.infinity),
          framework.getMaxIntrinsicHeight(double.infinity),
        );
        expect(
          restage.getDryLayout(cases[index].constraints),
          framework.getDryLayout(cases[index].constraints),
        );
        expect(
          restage.getDryBaseline(
            cases[index].constraints,
            TextBaseline.alphabetic,
          ),
          framework.getDryBaseline(
            cases[index].constraints,
            TextBaseline.alphabetic,
          ),
        );
        expect(
          tester.widget(find.byKey(ValueKey<String>('restage-$index'))),
          isA<IntrinsicWidth>(),
        );
      }
    });

    testWidgets('the generated realization keeps custom namespaces distinct',
        (tester) async {
      await _pump(
        tester,
        '''
import application.widgets;
widget Paywall = IntrinsicWidth();
''',
      );

      expect(tester.takeException(), isNull);
      expect(_findWidget(_ApplicationIntrinsicWidth), findsOneWidget);
      expect(_findWidget(RestageIntrinsicWidth), findsNothing);
    });

    testWidgets('a width quotient overflow uses the unstepped width',
        (tester) async {
      await _pump(
        tester,
        _source(
          'IntrinsicWidth(stepWidth: 1e-308, child: ConstraintProbe('
          'intrinsicWidth: 1e308, naturalWidth: 12.0, naturalHeight: 9.0))',
          importsProbe: true,
        ),
        childConstraints: const BoxConstraints(maxHeight: 40),
      );

      expect(tester.takeException(), isNull);
      final render = _intrinsicWidth(tester);
      expect(
        _probe(tester).receivedConstraints,
        const BoxConstraints(
          minWidth: 1e308,
          maxWidth: 1e308,
          maxHeight: 40,
        ),
      );
      expect(render.size, const Size(1e308, 9));
      expect(render.getDryLayout(render.constraints), const Size(1e308, 9));
      expect(render.getMaxIntrinsicWidth(40), 1e308);
      expect(
        render.getDryBaseline(render.constraints, TextBaseline.alphabetic),
        17,
      );
    });

    testWidgets('a height quotient overflow omits the optional height tighten',
        (tester) async {
      await _pump(
        tester,
        _source(
          'IntrinsicWidth(stepHeight: 1e-308, child: ConstraintProbe('
          'intrinsicHeight: 1e308, naturalWidth: 12.0, naturalHeight: 9.0))',
          importsProbe: true,
        ),
        childConstraints: const BoxConstraints(
          minWidth: 50,
          maxWidth: 50,
          maxHeight: 40,
        ),
      );

      expect(tester.takeException(), isNull);
      final render = _intrinsicWidth(tester);
      expect(
        _probe(tester).receivedConstraints,
        const BoxConstraints(
          minWidth: 50,
          maxWidth: 50,
          maxHeight: 40,
        ),
      );
      expect(render.size, const Size(50, 9));
      expect(render.getDryLayout(render.constraints), const Size(50, 9));
      expect(render.getMaxIntrinsicHeight(50), 1e308);
      expect(
        render.getDryBaseline(render.constraints, TextBaseline.alphabetic),
        17,
      );
    });

    testWidgets('an unbounded width product uses the unstepped width',
        (tester) async {
      await _pump(
        tester,
        _source(
          'IntrinsicWidth(stepWidth: 1e308, child: ConstraintProbe('
          'intrinsicWidth: 1.5e308, naturalWidth: 12.0, naturalHeight: 9.0))',
          importsProbe: true,
        ),
        childConstraints: const BoxConstraints(maxHeight: 40),
      );

      expect(tester.takeException(), isNull);
      final render = _intrinsicWidth(tester);
      expect(
        _probe(tester).receivedConstraints,
        const BoxConstraints(
          minWidth: 1.5e308,
          maxWidth: 1.5e308,
          maxHeight: 40,
        ),
      );
      expect(render.size, const Size(1.5e308, 9));
      expect(render.getDryLayout(render.constraints), const Size(1.5e308, 9));
      expect(render.getMaxIntrinsicWidth(40), 1.5e308);
    });

    testWidgets('a bounded height product keeps the native finite clamp',
        (tester) async {
      await _pump(
        tester,
        _source(
          'IntrinsicWidth(stepHeight: 1e308, child: ConstraintProbe('
          'intrinsicHeight: 1.5e308, naturalHeight: 9.0))',
          importsProbe: true,
        ),
        childConstraints: const BoxConstraints(
          minWidth: 50,
          maxWidth: 50,
          maxHeight: 40,
        ),
      );

      expect(tester.takeException(), isNull);
      final render = _intrinsicWidth(tester);
      expect(
        _probe(tester).receivedConstraints,
        BoxConstraints.tight(const Size(50, 40)),
      );
      expect(render.size, const Size(50, 40));
      expect(render.getDryLayout(render.constraints), const Size(50, 40));
      expect(render.getMaxIntrinsicHeight(50), 1.5e308);
      expect(
        render.getDryBaseline(render.constraints, TextBaseline.alphabetic),
        31,
      );
    });

    testWidgets('an unbounded height product omits the optional height tighten',
        (tester) async {
      await _pump(
        tester,
        _source(
          'IntrinsicWidth(stepHeight: 1e308, child: ConstraintProbe('
          'intrinsicHeight: 1.5e308, naturalHeight: 9.0))',
          importsProbe: true,
        ),
        childConstraints: const BoxConstraints(
          minWidth: 50,
          maxWidth: 50,
        ),
      );

      expect(tester.takeException(), isNull);
      final render = _intrinsicWidth(tester);
      expect(
        _probe(tester).receivedConstraints,
        const BoxConstraints(minWidth: 50, maxWidth: 50),
      );
      expect(render.size, const Size(50, 9));
      expect(render.getDryLayout(render.constraints), const Size(50, 9));
      expect(render.getMaxIntrinsicHeight(50), 1.5e308);
      expect(
        render.getDryBaseline(render.constraints, TextBaseline.alphabetic),
        17,
      );
    });

    testWidgets('legal large width steps preserve native arithmetic',
        (tester) async {
      await _pump(
        tester,
        _source(
          'IntrinsicWidth(stepWidth: 8e307, child: ConstraintProbe('
          'intrinsicWidth: 1e308, naturalHeight: 9.0))',
          importsProbe: true,
        ),
        childConstraints: const BoxConstraints(maxHeight: 40),
      );

      expect(tester.takeException(), isNull);
      var render = _intrinsicWidth(tester);
      expect(render.getMaxIntrinsicWidth(40), 1.6e308);
      expect(_probe(tester).receivedConstraints!.minWidth, 1.6e308);

      await _pump(
        tester,
        _source(
          'IntrinsicWidth(stepWidth: 1.0, child: ConstraintProbe('
          'intrinsicWidth: 1e308, naturalHeight: 9.0))',
          importsProbe: true,
        ),
        childConstraints: const BoxConstraints(maxHeight: 40),
      );

      expect(tester.takeException(), isNull);
      render = _intrinsicWidth(tester);
      expect(render.getMaxIntrinsicWidth(40), 9223372036854776000.0);
      expect(
        _probe(tester).receivedConstraints!.minWidth,
        9223372036854776000.0,
      );
    });

    testWidgets('zero steps keep native null-step behavior', (tester) async {
      await _pump(
        tester,
        _source(
          'IntrinsicWidth(stepWidth: 0.0, stepHeight: 0.0, child: '
          'ConstraintProbe(intrinsicWidth: 10.0, intrinsicHeight: 20.0, '
          'naturalWidth: 8.0, naturalHeight: 9.0))',
          importsProbe: true,
        ),
        childConstraints: const BoxConstraints(maxWidth: 100, maxHeight: 40),
      );

      expect(tester.takeException(), isNull);
      final render = _intrinsicWidth(tester);
      expect(
        _probe(tester).receivedConstraints,
        const BoxConstraints(minWidth: 10, maxWidth: 10, maxHeight: 40),
      );
      expect(render.getMaxIntrinsicWidth(40), 10);
      expect(render.getMaxIntrinsicHeight(10), 20);
      expect(render.getDryLayout(render.constraints), const Size(10, 9));
      expect(
        render.getDryBaseline(render.constraints, TextBaseline.alphabetic),
        17,
      );
    });

    testWidgets('a tight width bypasses the width intrinsic and step',
        (tester) async {
      await _pump(
        tester,
        _source(
          'IntrinsicWidth(stepWidth: 1e-308, child: ConstraintProbe('
          'failWidthIntrinsic: true, naturalWidth: 12.0, naturalHeight: 9.0))',
          importsProbe: true,
        ),
        childConstraints: const BoxConstraints(
          minWidth: 50,
          maxWidth: 50,
          maxHeight: 40,
        ),
      );

      expect(tester.takeException(), isNull);
      final render = _intrinsicWidth(tester);
      expect(
        _probe(tester).receivedConstraints,
        const BoxConstraints(
          minWidth: 50,
          maxWidth: 50,
          maxHeight: 40,
        ),
      );
      expect(render.getDryLayout(render.constraints), const Size(50, 9));
      expect(
        render.getDryBaseline(render.constraints, TextBaseline.alphabetic),
        17,
      );
    });

    testWidgets('intrinsic height uses the resolved intrinsic width',
        (tester) async {
      await _pump(
        tester,
        _source(
          'IntrinsicWidth(stepWidth: 4.0, stepHeight: 5.0, child: '
          'ConstraintProbe(intrinsicWidth: 11.0, heightFromWidth: true))',
          importsProbe: true,
        ),
        childConstraints: const BoxConstraints(maxWidth: 100, maxHeight: 40),
      );

      expect(tester.takeException(), isNull);
      final render = _intrinsicWidth(tester);
      expect(render.getMaxIntrinsicWidth(double.infinity), 12);
      expect(render.getMinIntrinsicHeight(double.infinity), 15);
      expect(render.getMaxIntrinsicHeight(double.infinity), 15);
    });

    testWidgets('no child keeps the native empty results', (tester) async {
      await _pump(
        tester,
        _source('IntrinsicWidth(stepWidth: 1e-308, stepHeight: 1e-308)'),
        childConstraints: const BoxConstraints(
          minWidth: 5,
          maxWidth: 50,
          minHeight: 7,
          maxHeight: 40,
        ),
      );

      expect(tester.takeException(), isNull);
      final render = _intrinsicWidth(tester);
      expect(render.size, const Size(5, 7));
      expect(render.getDryLayout(render.constraints), const Size(5, 7));
      expect(render.getMinIntrinsicWidth(40), 0);
      expect(render.getMaxIntrinsicWidth(40), 0);
      expect(render.getMinIntrinsicHeight(50), 0);
      expect(render.getMaxIntrinsicHeight(50), 0);
      expect(
        render.getDryBaseline(render.constraints, TextBaseline.alphabetic),
        isNull,
      );
    });
  });
}
