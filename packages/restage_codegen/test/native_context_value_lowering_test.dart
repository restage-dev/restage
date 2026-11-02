import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:restage_codegen/src/framework_const_values.dart';
import 'package:restage_codegen/src/builder_expression_lowering.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';
import 'helpers.dart';

final class _NoCaptures implements ValueReader {
  @override
  Object? read(List<Object> path, ValueType type) => throw StateError('$path');
  @override
  int length(List<Object> path) => throw StateError('$path');
}

Future<ValueProgram> _lower(String expression) async {
  final ast = await parseExpressionFromSourceForTest('''
import 'dart:ui';
import 'package:flutter/material.dart';
dynamic x(BuildContext context) => $expression;
''', rootPackage: 'apps_examples');
  final lowering = BuilderExpressionLowering(capture: (e) => e.toSource());
  final program = lowering.program(lowering.lower(ast));
  program.validate();
  return program;
}

Object? _evaluate(ValueProgram program, Map<String, Object?> parameters) =>
    ValueEvaluator(
      program,
      captures: _NoCaptures(),
      parameters: parameters,
    ).evaluate();

void main() {
  test(
    'native context null shortening preserves chain and parentheses boundaries',
    () async {
      final cases = <String, double? Function(_NativeStyle?)>{
        'Theme.of(context).textTheme.bodyMedium?.fontSize!': (style) =>
            style?.fontSize!,
        '(Theme.of(context).textTheme.bodyMedium?.fontSize)!': (style) =>
            (style?.fontSize)!,
        'Theme.of(context).textTheme.bodyMedium?.fontSize!.round().toDouble()':
            (style) => style?.fontSize!.round().toDouble(),
        'Theme.of(context).textTheme.bodyMedium?.fontSize?.round().toDouble()':
            (style) => style?.fontSize?.round().toDouble(),
        '(Theme.of(context).textTheme.bodyMedium?.fontSize)!.round().toDouble()':
            (style) => (style?.fontSize)!.round().toDouble(),
      };
      for (final entry in cases.entries) {
        final program = await _lower(entry.key);
        for (final style in [
          null,
          const _NativeStyle(null),
          const _NativeStyle(1.25),
        ]) {
          Object? expected;
          try {
            expected = entry.value(style);
          } on TypeError {
            expected = TypeError;
          }
          Object? evaluate() => _evaluate(program, {
            'context:theme:textTheme.bodyMedium.\$present': style != null,
            if (style != null)
              'context:theme:textTheme.bodyMedium.fontSize': style.fontSize,
          });
          if (expected == TypeError) {
            expect(evaluate, throwsA(isA<TypeError>()), reason: entry.key);
          } else {
            expect(evaluate(), expected, reason: entry.key);
          }
        }
      }
      final dead = await _lower(
        'false ? Theme.of(context).textTheme.bodyMedium?.fontSize! : 7.25',
      );
      expect(_evaluate(dead, {}), 7.25);
    },
  );

  test(
    'inert field and index null shortening shares the native chain rules',
    () async {
      for (final expression in [
        'row?.child!.size!',
        'row?.child?.size!',
        '(row?.child)!.size!',
        'row?.children?[1 ~/ 0].size!',
      ]) {
        final ast = await parseExpressionFromSourceForTest(
          'class Leaf {const Leaf(this.size);final double? size;} class Row {const Row(this.child,this.children);final Leaf? child;final List<Leaf>? children;} double? x(Row? row)=>$expression;',
        );
        final lowering = BuilderExpressionLowering(
          capture: (value) => value.toSource(),
        );
        final program = lowering.program(lowering.lower(ast));
        program.validate();
        Object? evaluate(Object? row) => ValueEvaluator(
          program,
          captures: _DataReader({'c0': row}),
          parameters: {},
        ).evaluate();
        if (expression.startsWith('(')) {
          expect(() => evaluate(null), throwsA(isA<TypeError>()));
        } else {
          expect(evaluate(null), isNull);
        }
        if (expression.contains('children')) {
          expect(evaluate({'child': null, 'children': null}), isNull);
          expect(
            () => evaluate({
              'child': null,
              'children': [
                {'size': 1.25},
              ],
            }),
            throwsA(isA<IntegerDivisionByZeroException>()),
          );
        } else {
          if (expression.contains('child?.')) {
            expect(evaluate({'child': null, 'children': null}), isNull);
          } else {
            expect(
              () => evaluate({'child': null, 'children': null}),
              throwsA(isA<TypeError>()),
            );
          }
          expect(
            () => evaluate({
              'child': {'size': null},
              'children': null,
            }),
            throwsA(isA<TypeError>()),
          );
          expect(
            evaluate({
              'child': {'size': 1.25},
              'children': null,
            }),
            1.25,
          );
        }
      }
    },
  );

  test(
    'native context leaf and intermediate assertions remain lazy and exact',
    () async {
      final leaf = await _lower('DefaultTextStyle.of(context).style.fontSize!');
      expect(
        () =>
            _evaluate(leaf, {'context:theme:defaultTextStyle.fontSize': null}),
        throwsA(isA<TypeError>()),
      );
      expect(
        _evaluate(leaf, {'context:theme:defaultTextStyle.fontSize': 12.25}),
        12.25,
      );
      final intermediate = await _lower(
        'Theme.of(context).textTheme.bodyMedium!.fontSize',
      );
      expect(
        () => _evaluate(intermediate, {
          'context:theme:textTheme.bodyMedium.\$present': false,
          'context:theme:textTheme.bodyMedium.fontSize': null,
        }),
        throwsA(isA<TypeError>()),
      );
      expect(
        _evaluate(intermediate, {
          'context:theme:textTheme.bodyMedium.\$present': true,
          'context:theme:textTheme.bodyMedium.fontSize': null,
        }),
        isNull,
      );
      final dead = await _lower(
        'false ? Theme.of(context).textTheme.bodyMedium!.fontSize! : 7.25',
      );
      expect(_evaluate(dead, {}), 7.25);
    },
  );
  test(
    'exact native color records mix context constants and channel access',
    () async {
      final constant = await _lower(
        'const Color.from(alpha:0.812345,red:-0.125,green:1.375,blue:0.123456,colorSpace:ColorSpace.extendedSRGB)',
      );
      final expected = {
        'a': 0.812345,
        'r': -0.125,
        'g': 1.375,
        'b': 0.123456,
        'colorSpace': 'extendedSRGB',
        'material': '',
      };
      expect(_evaluate(constant, {}), expected);
      final mixed = await _lower(
        'Theme.of(context).brightness == Brightness.dark ? Theme.of(context).colorScheme.primary : const Color(0xff123456)',
      );
      expect(
        _evaluate(mixed, {
          'context:theme:brightness': 'dark',
          'context:theme:colorScheme.primary': expected,
        }),
        expected,
      );
      expect(
        _evaluate(mixed, {'context:theme:brightness': 'light'}),
        argbColorValue(0xff123456),
      );
      final channel = await _lower('Theme.of(context).colorScheme.primary.r');
      expect(
        _evaluate(channel, {'context:theme:colorScheme.primary': expected}),
        -0.125,
      );
      final weight = await _lower('const FontWeight(550)');
      expect(_evaluate(weight, {}), 550);
      final decoration = await _lower('TextDecoration.underline');
      expect(_evaluate(decoration, {}), 1);
      await expectLater(
        _lower('Theme.of(context).colorScheme.primary == Colors.red'),
        throwsA(isA<BuilderLoweringException>()),
      );
      await expectLater(
        _lower('const FontWeight(550) == FontWeight.w500'),
        throwsA(isA<BuilderLoweringException>()),
      );
      final alias = await parseExpressionFromSourceForTest(
        "import 'dart:ui'; const color=Color.from(alpha:0.812345,red:-0.125,green:1.375,blue:0.123456,colorSpace:ColorSpace.extendedSRGB); Color x()=>color;",
      );
      final aliasConstant =
          ((alias as SimpleIdentifier).element as PropertyAccessorElement)
              .variable
              .computeConstantValue()!;
      expect(
        encodeFrameworkConst(aliasConstant)!.dsl,
        contains('extendedSRGB'),
      );
      expect(encodeFrameworkConst(aliasConstant)!.dsl, contains('0.123456'));
      final aliasLowering = BuilderExpressionLowering(
        capture: (e) => e.toSource(),
      );
      expect(
        _evaluate(aliasLowering.program(aliasLowering.lower(alias)), {}),
        expected,
      );
      final host = await parseExpressionFromSourceForTest(
        "import 'dart:ui'; Color x(Color host)=>host;",
      );
      expect(
        () => BuilderExpressionLowering(
          capture: (e) => 'data.context.host',
        ).lower(host),
        throwsA(isA<BuilderLoweringException>()),
      );
    },
  );
}

final class _NativeStyle {
  const _NativeStyle(this.fontSize);
  final double? fontSize;
}

final class _DataReader implements ValueReader {
  _DataReader(this.values);
  final Map<String, Object?> values;
  @override
  Object? read(List<Object> path, ValueType type) {
    Object? value = values;
    for (final key in path)
      value = key is int ? (value as List)[key] : (value as Map)[key];
    return value;
  }

  @override
  int length(List<Object> path) =>
      (read(path, const ValueType('list', item: ValueType.real)) as List)
          .length;
}
