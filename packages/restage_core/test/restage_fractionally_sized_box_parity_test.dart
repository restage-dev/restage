import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';

const List<double?> _factors = <double?>[null, 0.5, 1.0, 2.0, 1e3];
const AlignmentGeometry _alignment = AlignmentDirectional.bottomEnd;
const double _intrinsicHeight = 37;
const double _intrinsicWidth = 41;
const Key _flutterBoxKey = ValueKey<String>('flutter-box');
const Key _restageBoxKey = ValueKey<String>('restage-box');
const Key _flutterChildKey = ValueKey<String>('flutter-child');
const Key _restageChildKey = ValueKey<String>('restage-child');

class _ParityCase {
  const _ParityCase({
    required this.name,
    required this.constraints,
    required this.widthFactor,
    required this.heightFactor,
  });

  final String name;
  final BoxConstraints constraints;
  final double? widthFactor;
  final double? heightFactor;
}

Iterable<_ParityCase> _parityCases() sync* {
  for (final double? widthFactor in _factors) {
    for (final double? heightFactor in _factors) {
      yield _ParityCase(
        name: 'bounded width=$widthFactor height=$heightFactor',
        constraints: BoxConstraints.tight(const Size(80, 60)),
        widthFactor: widthFactor,
        heightFactor: heightFactor,
      );
    }
  }

  for (final double? heightFactor in _factors) {
    yield _ParityCase(
      name: 'unbounded width, height=$heightFactor',
      constraints: const BoxConstraints(minHeight: 60, maxHeight: 60),
      widthFactor: null,
      heightFactor: heightFactor,
    );
  }

  for (final double? widthFactor in _factors) {
    yield _ParityCase(
      name: 'unbounded height, width=$widthFactor',
      constraints: const BoxConstraints(minWidth: 80, maxWidth: 80),
      widthFactor: widthFactor,
      heightFactor: null,
    );
  }

  yield const _ParityCase(
    name: 'unbounded width and height',
    constraints: BoxConstraints(),
    widthFactor: null,
    heightFactor: null,
  );
}

class _ConstraintHost extends SingleChildRenderObjectWidget {
  const _ConstraintHost({
    required this.childConstraints,
    required super.child,
  });

  final BoxConstraints childConstraints;

  @override
  _RenderConstraintHost createRenderObject(BuildContext context) {
    return _RenderConstraintHost(childConstraints);
  }

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

  set childConstraints(BoxConstraints value) {
    if (_childConstraints == value) {
      return;
    }
    _childConstraints = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final RenderBox? child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(_childConstraints, parentUsesSize: true);
    size = constraints.constrain(child.size);
  }
}

class _GeometryProbe extends LeafRenderObjectWidget {
  const _GeometryProbe({super.key});

  @override
  _RenderGeometryProbe createRenderObject(BuildContext context) {
    return _RenderGeometryProbe();
  }
}

class _RenderGeometryProbe extends RenderBox {
  BoxConstraints? receivedConstraints;

  // Record the exact constraints at hand-over, before layout can reject or
  // otherwise obscure them.
  @override
  void layout(Constraints constraints, {bool parentUsesSize = false}) {
    if (constraints is BoxConstraints) {
      receivedConstraints = constraints;
    }
    super.layout(constraints, parentUsesSize: parentUsesSize);
  }

  @override
  void performLayout() {
    size = constraints.constrain(const Size(23, 17));
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    return constraints.constrain(const Size(23, 17));
  }

  @override
  double computeMinIntrinsicWidth(double height) => height + 11;

  @override
  double computeMaxIntrinsicWidth(double height) => height + 29;

  @override
  double computeMinIntrinsicHeight(double width) => width + 13;

  @override
  double computeMaxIntrinsicHeight(double width) => width + 31;

  @override
  double? computeDryBaseline(
    covariant BoxConstraints constraints,
    TextBaseline baseline,
  ) {
    return computeDryLayout(constraints).height * 0.75;
  }
}

Offset? _childOffset(RenderFractionallySizedOverflowBox renderObject) {
  final RenderBox? child = renderObject.child;
  if (child == null) {
    return null;
  }
  return (child.parentData! as BoxParentData).offset;
}

void main() {
  for (final _ParityCase parityCase in _parityCases()) {
    for (final TextDirection textDirection in TextDirection.values) {
      for (final bool hasChild in <bool>[true, false]) {
        testWidgets(
          '${parityCase.name}, $textDirection, '
          '${hasChild ? 'with child' : 'without child'}',
          (WidgetTester tester) async {
            await tester.pumpWidget(
              Directionality(
                textDirection: textDirection,
                child: Stack(
                  alignment: Alignment.topLeft,
                  children: <Widget>[
                    _ConstraintHost(
                      childConstraints: parityCase.constraints,
                      child: FractionallySizedBox(
                        key: _flutterBoxKey,
                        alignment: _alignment,
                        widthFactor: parityCase.widthFactor,
                        heightFactor: parityCase.heightFactor,
                        child: hasChild
                            ? const _GeometryProbe(key: _flutterChildKey)
                            : null,
                      ),
                    ),
                    _ConstraintHost(
                      childConstraints: parityCase.constraints,
                      child: RestageFractionallySizedBox(
                        key: _restageBoxKey,
                        alignment: _alignment,
                        widthFactor: parityCase.widthFactor,
                        heightFactor: parityCase.heightFactor,
                        child: hasChild
                            ? const _GeometryProbe(key: _restageChildKey)
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            );

            expect(tester.takeException(), isNull);

            final RenderFractionallySizedOverflowBox flutterRender =
                tester.renderObject<RenderFractionallySizedOverflowBox>(
              find.byKey(_flutterBoxKey),
            );
            final RenderFractionallySizedOverflowBox restageRender =
                tester.renderObject<RenderFractionallySizedOverflowBox>(
              find.byKey(_restageBoxKey),
            );

            expect(restageRender.size, flutterRender.size);
            expect(_childOffset(restageRender), _childOffset(flutterRender));

            if (hasChild) {
              final _RenderGeometryProbe flutterChild =
                  tester.renderObject<_RenderGeometryProbe>(
                find.byKey(_flutterChildKey),
              );
              final _RenderGeometryProbe restageChild =
                  tester.renderObject<_RenderGeometryProbe>(
                find.byKey(_restageChildKey),
              );
              expect(
                restageChild.receivedConstraints,
                flutterChild.receivedConstraints,
              );
            } else {
              expect(restageRender.child, isNull);
              expect(flutterRender.child, isNull);
            }

            expect(
              restageRender.getMinIntrinsicWidth(_intrinsicHeight),
              flutterRender.getMinIntrinsicWidth(_intrinsicHeight),
            );
            expect(
              restageRender.getMaxIntrinsicWidth(_intrinsicHeight),
              flutterRender.getMaxIntrinsicWidth(_intrinsicHeight),
            );
            expect(
              restageRender.getMinIntrinsicHeight(_intrinsicWidth),
              flutterRender.getMinIntrinsicHeight(_intrinsicWidth),
            );
            expect(
              restageRender.getMaxIntrinsicHeight(_intrinsicWidth),
              flutterRender.getMaxIntrinsicHeight(_intrinsicWidth),
            );
            expect(
              restageRender.getDryLayout(parityCase.constraints),
              flutterRender.getDryLayout(parityCase.constraints),
            );
            expect(
              restageRender.getDryBaseline(
                parityCase.constraints,
                TextBaseline.alphabetic,
              ),
              flutterRender.getDryBaseline(
                parityCase.constraints,
                TextBaseline.alphabetic,
              ),
            );
          },
        );
      }
    }
  }
}
