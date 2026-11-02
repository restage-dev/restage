import 'package:analyzer/dart/ast/ast.dart';
import 'package:restage_codegen/src/builder_expression_lowering.dart';
import 'package:restage_codegen/src/closed_callback_lowering.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';
import 'helpers.dart';

final class _EmptyReader implements ValueReader {
  @override
  int length(List<Object> path) => throw StateError('Unexpected capture');
  @override
  Object? read(List<Object> path, ValueType type) =>
      throw StateError('Unexpected capture');
}

void main() {
  Future<ValueProgram> lower(String body) async {
    final callback =
        await parseExpressionFromSourceForTest(
              'Object x() => () { $body };',
              rootPackage: 'apps_examples',
            )
            as FunctionExpression;
    final expressions = BuilderExpressionLowering(
      capture: (_) => throw StateError('Unexpected capture'),
    );
    final root = closedValueCallback(expressions).body(callback.body);
    final program = expressions.program(root);
    program.validate();
    return ValueProgram.decode(program.encode());
  }

  Object? run(ValueProgram program) => ValueEvaluator(
    program,
    captures: _EmptyReader(),
    parameters: {},
  ).evaluate();

  test(
    'assignment, compound and prefix/postfix results match native locals',
    () async {
      int native() {
        var value = 2;
        final before = value++;
        final after = ++value;
        value *= 3;
        value -= 2;
        value ~/= 2;
        value %= 4;
        return before * 100 + after * 10 + value;
      }

      final program = await lower('''
      var value = 2;
      final before = value++;
      final after = ++value;
      value *= 3;
      value -= 2;
      value ~/= 2;
      value %= 4;
      return before * 100 + after * 10 + value;
    ''');
      expect(run(program), native());
      expect(run(program), native());
      expect(valueProgramRequiredCapability(program), 24);
    },
  );
  test(
    'compound numeric operations preserve native value and runtime type',
    () async {
      final cases = <(String, num Function())>[
        (
          'num value = 5; value += 2; return value;',
          () {
            num value = 5;
            value += 2;
            return value;
          },
        ),
        (
          'num value = 5; value -= 2; return value;',
          () {
            num value = 5;
            value -= 2;
            return value;
          },
        ),
        (
          'num value = 5; value *= 2; return value;',
          () {
            num value = 5;
            value *= 2;
            return value;
          },
        ),
        (
          'num value = 5; value /= 2; return value;',
          () {
            num value = 5;
            value /= 2;
            return value;
          },
        ),
        (
          'num value = 5; value ~/= 2; return value;',
          () {
            num value = 5;
            value ~/= 2;
            return value;
          },
        ),
        (
          'num value = 5; value %= 2; return value;',
          () {
            num value = 5;
            value %= 2;
            return value;
          },
        ),
        (
          'num value = 5.5; value += 2; return value;',
          () {
            num value = 5.5;
            value += 2;
            return value;
          },
        ),
        (
          'num value = 5.5; value -= 2; return value;',
          () {
            num value = 5.5;
            value -= 2;
            return value;
          },
        ),
        (
          'num value = 5.5; value *= 2; return value;',
          () {
            num value = 5.5;
            value *= 2;
            return value;
          },
        ),
        (
          'num value = 5.5; value /= 2; return value;',
          () {
            num value = 5.5;
            value /= 2;
            return value;
          },
        ),
        (
          'num value = 5.5; value ~/= 2; return value;',
          () {
            num value = 5.5;
            value ~/= 2;
            return value;
          },
        ),
        (
          'num value = 5.5; value %= 2; return value;',
          () {
            num value = 5.5;
            value %= 2;
            return value;
          },
        ),
        (
          'double value = 5.5; value += 2; return value;',
          () {
            double value = 5.5;
            value += 2;
            return value;
          },
        ),
        (
          'double value = 5.5; value -= 2; return value;',
          () {
            double value = 5.5;
            value -= 2;
            return value;
          },
        ),
        (
          'double value = 5.5; value *= 2; return value;',
          () {
            double value = 5.5;
            value *= 2;
            return value;
          },
        ),
        (
          'double value = 5.5; value /= 2; return value;',
          () {
            double value = 5.5;
            value /= 2;
            return value;
          },
        ),
        (
          'double value = 5.5; value %= 2; return value;',
          () {
            double value = 5.5;
            value %= 2;
            return value;
          },
        ),
        (
          'int value = 5; value += 2; return value;',
          () {
            int value = 5;
            value += 2;
            return value;
          },
        ),
        (
          'int value = 5; value -= 2; return value;',
          () {
            int value = 5;
            value -= 2;
            return value;
          },
        ),
        (
          'int value = 5; value *= 2; return value;',
          () {
            int value = 5;
            value *= 2;
            return value;
          },
        ),
        (
          'int value = 5; value ~/= 2; return value;',
          () {
            int value = 5;
            value ~/= 2;
            return value;
          },
        ),
        (
          'int value = 5; value %= 2; return value;',
          () {
            int value = 5;
            value %= 2;
            return value;
          },
        ),
      ];
      for (final (source, native) in cases) {
        final expected = native();
        final actual = run(await lower(source));
        expect(actual, expected, reason: source);
        expect(actual.runtimeType, expected.runtimeType, reason: source);
      }
    },
  );
  test('nullable assignment is lazy and returns its assigned value', () async {
    final program = await lower('''
      int? value = null;
      value = 2;
      final first = value ??= 1 ~/ 0;
      value = null;
      final second = value ??= 3;
      return first + second;
    ''');
    expect(run(program), 5);
  });
  test(
    'typed double and string compound assignments preserve Dart types',
    () async {
      final program = await lower(r'''
      double value = 2;
      value = 3;
      value /= 2;
      var text = 'a';
      text += 'b';
      return '$text$value';
    ''');
      expect(run(program), 'ab1.5');
    },
  );
  test(
    'block shadowing and early returns preserve surrounding bindings',
    () async {
      final program = await lower('''
      var value = 1;
      if (value == 1) { var value = 20; value++; }
      { var value = 30; value++; }
      if (value == 2) return 99;
      value += 3;
      if (value == 4) return value;
      return 0;
    ''');
      expect(run(program), 4);
    },
  );
  test('unused mutable initializers still throw', () async {
    final program = await lower('var unused = 1 ~/ 0; return 1;');
    expect(() => run(program), throwsA(isA<IntegerDivisionByZeroException>()));
  });
  test('consecutive effect branches retain a linear graph', () async {
    final program = await lower(
      'var value = 0; ${List.generate(12, (i) => 'if (value == $i) value++;').join()} return value;',
    );
    expect(run(program), 12);
    expect(program.nodes.length, lessThan(200));
  });
  test(
    'resolved block helpers preserve named argument order and early returns',
    () async {
      final callback =
          await parseExpressionFromSourceForTest("""
      int helper({required int first, required int second}) {
        var value = first;
        if (second > 1) { value += second; return value; }
        return 0;
      }
      Object x() => () {
        var value = 0;
        final result = helper(second: ++value, first: ++value);
        return result * 10 + value;
      };
    """, rootPackage: 'apps_examples')
              as FunctionExpression;
      final expressions = BuilderExpressionLowering(
        capture: (_) => throw StateError('Unexpected capture'),
        extension: (expression, lowering) {
          if (expression is! MethodInvocation) return null;
          final helper = pureBuilderHelperFor(
            expression,
            expression.methodName.element,
          );
          return helper == null
              ? null
              : lowering.lowerHelper(helper, expression);
        },
      );
      final root = closedValueCallback(expressions).body(callback.body);
      expect(run(expressions.program(root)), 2);
    },
  );
  test('empty lexical metadata preserves existing wire fields', () async {
    final program = await lower('final value = 1; return value + 2;');
    expect(program.toJson().containsKey('locals'), isFalse);
    expect(program.toJson().containsKey('outerLocals'), isFalse);
    expect(valueProgramRequiredCapability(program), 19);
    expect(
      program.encode(),
      '{"version":1,"nodes":[{"op":"literal","type":{"kind":"int"},"value":1},{"op":"literal","type":{"kind":"int"},"value":2},{"op":"+","type":{"kind":"int"},"inputs":[0,1]},{"op":"let","type":{"kind":"int"},"inputs":[0,2]}],"root":3,"captures":{},"parameters":{}}',
    );
  });
}
