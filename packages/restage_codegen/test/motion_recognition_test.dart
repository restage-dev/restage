import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:restage_codegen/src/motion_recognition.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// The motion adopt-target helper. Imperative animation (an
/// `AnimationController` or a directly-constructed Flutter spring) cannot be
/// auto-substituted the way
/// the number/currency idiom can — there is no by-construction equivalent that
/// would pass the semantic-rewrite oracle — so these widgets are only ever
/// NAMED in a deferral diagnostic, never silently swapped in. This pins the
/// adopt-target vocabulary + message and the element-gated spring recogniser.
void main() {
  Future<InstanceCreationExpression> resolveFlutter(String body) async {
    final expr = await parseExpressionFromSourceForTest(
      '''
import 'package:flutter/physics.dart';
Object x() => $body;
''',
      rootPackage: 'apps_examples',
    );
    return expr as InstanceCreationExpression;
  }

  group('springAdoptTarget (element-gated on package:flutter/)', () {
    test('a Flutter SpringDescription names RestageMotion', () async {
      final expr =
          await resolveFlutter('SpringDescription(mass: 1, stiffness: 100, '
              'damping: 10)');
      expect(springAdoptTarget(expr), 'RestageMotion');
    });

    test('a Flutter SpringSimulation names RestageMotion', () async {
      final expr = await resolveFlutter(
        'SpringSimulation(SpringDescription(mass: 1, stiffness: 100, '
        'damping: 10), 0, 1, 0)',
      );
      expect(springAdoptTarget(expr), 'RestageMotion');
    });

    test('an unrelated Flutter physics construction is not named', () async {
      final expr = await resolveFlutter('Tolerance()');
      expect(springAdoptTarget(expr), isNull);
    });

    test('a customer look-alike SpringDescription is NOT named (element gate)',
        () async {
      // A customer class named SpringDescription resolves to a non-flutter
      // library; the gate withholds the hint (a coincidental name is not a
      // Flutter spring).
      final expr = await parseExpressionFromSourceForTest('''
class SpringDescription {
  SpringDescription({double? mass, double? stiffness, double? damping});
}
Object x() => SpringDescription(mass: 1, stiffness: 100, damping: 10);
''');
      expect(springAdoptTarget(expr as InstanceCreationExpression), isNull);
    });
  });

  group('isImperativeMotionType (element-gated motion State-field type)', () {
    // Resolves the static type of `(null as <typeExpr>)` under a real Flutter
    // import — the simplest way to get a resolved Flutter `DartType` whose
    // element library is `package:flutter/`.
    Future<DartType> resolveFlutterType(
      String typeExpr, {
      String import = 'package:flutter/animation.dart',
    }) async {
      final expr = await parseExpressionFromSourceForTest(
        "import '$import';\nObject? x() => (null as $typeExpr);",
        rootPackage: 'apps_examples',
      );
      return expr.staticType!;
    }

    test('a Flutter AnimationController is an imperative-motion type',
        () async {
      final type = await resolveFlutterType('AnimationController');
      expect(isImperativeMotionType(type), isTrue);
    });

    test('a Flutter Animation is an imperative-motion type', () async {
      final type = await resolveFlutterType('Animation<double>');
      expect(isImperativeMotionType(type), isTrue);
    });

    test('a Flutter CurvedAnimation is an imperative-motion type', () async {
      final type = await resolveFlutterType('CurvedAnimation');
      expect(isImperativeMotionType(type), isTrue);
    });

    test('a Flutter Ticker is an imperative-motion type', () async {
      final type = await resolveFlutterType(
        'Ticker',
        import: 'package:flutter/scheduler.dart',
      );
      expect(isImperativeMotionType(type), isTrue);
    });

    test('an unrelated Flutter physics type (Tolerance) is NOT motion',
        () async {
      final type = await resolveFlutterType(
        'Tolerance',
        import: 'package:flutter/physics.dart',
      );
      expect(isImperativeMotionType(type), isFalse);
    });

    test('a look-alike AnimationController is NOT motion (element gate)',
        () async {
      // A customer class named AnimationController resolves to a non-flutter
      // library; the gate withholds the hint (a coincidental name is not a
      // Flutter animation controller).
      final expr = await parseExpressionFromSourceForTest('''
class AnimationController {}
Object? x() => (null as AnimationController);
''');
      expect(isImperativeMotionType(expr.staticType), isFalse);
    });

    test('a primitive type (String) is NOT motion', () async {
      final expr = await parseExpressionFromSourceForTest(
        'Object? x() => (null as String);',
      );
      expect(isImperativeMotionType(expr.staticType), isFalse);
    });
  });

  group('motionDeferMessage', () {
    test('the general message names all four motion widgets', () {
      final message = motionDeferMessage();
      for (final widget in kMotionAdoptTargets) {
        expect(message, contains(widget));
      }
    });

    test('a spring adopt-target leads with RestageMotion', () {
      expect(motionDeferMessage('RestageMotion'), contains('RestageMotion'));
    });

    test('the vocabulary is exactly the four motion widgets', () {
      expect(kMotionAdoptTargets, {
        'RestageMotion',
        'RestageFadeIn',
        'RestagePulse',
        'RestageStagger',
      });
    });
  });
}
