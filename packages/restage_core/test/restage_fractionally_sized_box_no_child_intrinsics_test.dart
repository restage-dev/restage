import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';

const Key _boxKey = ValueKey<String>('fractionally-sized-box');
const Key _frameworkChildKey = ValueKey<String>('framework-child');
const Key _restageChildKey = ValueKey<String>('restage-child');
const double _crossAxisExtent = 40.0;

class _ConstraintProbe extends LeafRenderObjectWidget {
  const _ConstraintProbe({super.key});

  @override
  _RenderConstraintProbe createRenderObject(BuildContext context) =>
      _RenderConstraintProbe();
}

class _RenderConstraintProbe extends RenderBox {
  BoxConstraints? receivedConstraints;

  @override
  void layout(Constraints constraints, {bool parentUsesSize = false}) {
    if (constraints is BoxConstraints) {
      receivedConstraints = constraints;
    }
    super.layout(constraints, parentUsesSize: parentUsesSize);
  }

  @override
  void performLayout() {
    size = constraints.smallest;
  }
}

Future<RenderFractionallySizedOverflowBox> _pumpBox(
  WidgetTester tester, {
  double? widthFactor,
  double? heightFactor,
}) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFractionallySizedBox(
        key: _boxKey,
        widthFactor: widthFactor,
        heightFactor: heightFactor,
      ),
    ),
  );

  return tester.renderObject<RenderFractionallySizedOverflowBox>(
    find.byKey(_boxKey),
  );
}

BoxConstraints? _receivedConstraints(WidgetTester tester, Key key) {
  return tester
      .renderObject<_RenderConstraintProbe>(find.byKey(key))
      .receivedConstraints;
}

void main() {
  testWidgets(
    'childless zero width factor repairs minimum intrinsic width',
    (WidgetTester tester) async {
      final renderObject = await _pumpBox(tester, widthFactor: 0.0);

      final value = renderObject.getMinIntrinsicWidth(_crossAxisExtent);

      expect(value.isFinite, isTrue);
      expect(value, 0.0);
    },
  );

  testWidgets(
    'childless zero width factor repairs maximum intrinsic width',
    (WidgetTester tester) async {
      final renderObject = await _pumpBox(tester, widthFactor: 0.0);

      final value = renderObject.getMaxIntrinsicWidth(_crossAxisExtent);

      expect(value.isFinite, isTrue);
      expect(value, 0.0);
    },
  );

  testWidgets(
    'childless zero height factor repairs minimum intrinsic height',
    (WidgetTester tester) async {
      final renderObject = await _pumpBox(tester, heightFactor: 0.0);

      final value = renderObject.getMinIntrinsicHeight(_crossAxisExtent);

      expect(value.isFinite, isTrue);
      expect(value, 0.0);
    },
  );

  testWidgets(
    'childless zero height factor repairs maximum intrinsic height',
    (WidgetTester tester) async {
      final renderObject = await _pumpBox(tester, heightFactor: 0.0);

      final value = renderObject.getMaxIntrinsicHeight(_crossAxisExtent);

      expect(value.isFinite, isTrue);
      expect(value, 0.0);
    },
  );

  testWidgets(
    'childless box without factors keeps zero intrinsic extents',
    (WidgetTester tester) async {
      final renderObject = await _pumpBox(tester);
      final values = <double>[
        renderObject.getMinIntrinsicWidth(_crossAxisExtent),
        renderObject.getMaxIntrinsicWidth(_crossAxisExtent),
        renderObject.getMinIntrinsicHeight(_crossAxisExtent),
        renderObject.getMaxIntrinsicHeight(_crossAxisExtent),
      ];

      expect(values.every((value) => value.isFinite), isTrue);
      expect(values, everyElement(0.0));
    },
  );

  testWidgets(
    'zero width factor on an unbounded axis gives the child the same '
    'constraints as an unauthored factor',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            children: <Widget>[
              RestageFractionallySizedBox(
                widthFactor: 0.0,
                child: _ConstraintProbe(key: _restageChildKey),
              ),
              FractionallySizedBox(
                child: _ConstraintProbe(key: _frameworkChildKey),
              ),
            ],
          ),
        ),
      );

      final restageConstraints = _receivedConstraints(tester, _restageChildKey);
      final frameworkConstraints =
          _receivedConstraints(tester, _frameworkChildKey);

      expect(restageConstraints, isNotNull);
      expect(frameworkConstraints, isNotNull);
      expect(restageConstraints, frameworkConstraints);
    },
  );

  testWidgets(
    'zero width factor on a bounded axis matches the framework zero factor',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: <Widget>[
              RestageFractionallySizedBox(
                widthFactor: 0.0,
                child: _ConstraintProbe(key: _restageChildKey),
              ),
              FractionallySizedBox(
                widthFactor: 0.0,
                child: _ConstraintProbe(key: _frameworkChildKey),
              ),
            ],
          ),
        ),
      );

      final restageConstraints = _receivedConstraints(tester, _restageChildKey);
      final frameworkConstraints =
          _receivedConstraints(tester, _frameworkChildKey);

      expect(restageConstraints, isNotNull);
      expect(frameworkConstraints, isNotNull);
      expect(restageConstraints, frameworkConstraints);
    },
  );

  testWidgets(
    'zero height factor on an unbounded axis gives the child the same '
    'constraints as an unauthored factor',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: <Widget>[
              RestageFractionallySizedBox(
                heightFactor: 0.0,
                child: _ConstraintProbe(key: _restageChildKey),
              ),
              FractionallySizedBox(
                child: _ConstraintProbe(key: _frameworkChildKey),
              ),
            ],
          ),
        ),
      );

      final restageConstraints = _receivedConstraints(tester, _restageChildKey);
      final frameworkConstraints =
          _receivedConstraints(tester, _frameworkChildKey);

      expect(restageConstraints, isNotNull);
      expect(frameworkConstraints, isNotNull);
      expect(restageConstraints, frameworkConstraints);
    },
  );

  testWidgets(
    'zero height factor on a bounded axis matches the framework zero factor',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: <Widget>[
              RestageFractionallySizedBox(
                heightFactor: 0.0,
                child: _ConstraintProbe(key: _restageChildKey),
              ),
              FractionallySizedBox(
                heightFactor: 0.0,
                child: _ConstraintProbe(key: _frameworkChildKey),
              ),
            ],
          ),
        ),
      );

      final restageConstraints = _receivedConstraints(tester, _restageChildKey);
      final frameworkConstraints =
          _receivedConstraints(tester, _frameworkChildKey);

      expect(restageConstraints, isNotNull);
      expect(frameworkConstraints, isNotNull);
      expect(restageConstraints, frameworkConstraints);
    },
  );
}
