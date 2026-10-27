import 'dart:io';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;
import 'package:test/test.dart';
import 'helpers.dart' as helpers;

final _native = decodeCatalog(File(
        Directory('packages/restage_core').existsSync()
            ? 'packages/restage_core/lib/src/widget_catalog/catalog.json'
            : '../restage_core/lib/src/widget_catalog/catalog.json')
    .readAsStringSync());
Future<TranslationResult> _translate(String body, {bool custom = false}) async {
  final expression = await helpers.parseExpressionFromSourceForTest('''
import 'package:flutter/material.dart';
Widget x()=>LayoutBuilder(builder:(context,c){$body});
dynamic forward(dynamic value)=>value;
class Probe extends StatelessWidget {
  const Probe({this.color,this.weight,this.style,this.gradient});
  final Color? color;
  final FontWeight? weight;
  final TextStyle? style;
  final Gradient? gradient;
  Widget build(BuildContext context)=>const SizedBox();
}
''', rootPackage: 'apps_examples');
  return ExpressionTranslator(
          catalog: custom
              ? helpers.nativeProbeCatalog([
                  ('color', PropertyType.color),
                  ('weight', PropertyType.fontWeight),
                  ('gradient', PropertyType.gradient),
                  ('style', PropertyType.structured),
                ], structured: {
                  'style': 'TextStyle'
                })
              : _native,
          helpers: HelperRegistry())
      .translate(expression);
}

BuilderProgram _program(TranslationResult result) {
  expect(result.issues, isEmpty,
      reason: result.issues.map((issue) => issue.message).join('\n'));
  final root = rfw
      .parseLibraryFile('import restage.core;widget Root=${result.dsl};')
      .widgets
      .single
      .root as rfw.ConstructorCall;
  final slot = root.arguments['builder']! as rfw.ConstructorCall;
  return BuilderProgram.decode(slot.arguments['program']! as String);
}

final class _NoCaptures implements ValueReader {
  @override
  Object? read(List<Object> path, ValueType type) => throw StateError('$path');
  @override
  int length(List<Object> path) => throw StateError('$path');
}

Object? _width(BuilderProgram program, double? fontSize) => program
    .invoke(
        captures: _NoCaptures(),
        parameters: {'context:theme:defaultTextStyle.fontSize': fontSize})
    .values
    .values
    .single;
double? _nullableWidth(double? width) => width;
double? _nativeDynamic(double? fontSize) {
  final dynamic width = fontSize;
  // Exercise Dart's implicit dynamic argument check in the native control.
  // ignore: argument_type_not_assignable
  return _nullableWidth(width);
}

double? _nativeAsserted(double? fontSize) {
  final dynamic width = fontSize;
  // ignore: argument_type_not_assignable
  return _nullableWidth(width!);
}

double? _nativePromoted(double? fontSize) {
  final double? width = fontSize;
  if (width == null) return _nullableWidth(1.0);
  return _nullableWidth(width + 1.0);
}

void main() {
  test('dynamic values take the implicit cast of their destination', () async {
    for (final (body, admitted) in [
      ("final dynamic v = 'x'; return SizedBox(width: v);", false),
      ('final dynamic v = 3; return Text(v);', false),
      ("return SizedBox(width: forward('x'));", false),
      ('return Text(forward(3));', false),
      ('return SizedBox(width: forward(3));', false),
      ('return SizedBox(width: forward(3.0));', true),
      ("return Text(forward('x'));", true),
      ("return ColoredBox(color: forward('x'));", false),
      ('return ColoredBox(color: forward(3));', false),
      ('return ColoredBox(color: forward(Colors.red));', true),
    ]) {
      final result = await _translate(body);
      expect(result.issues, admitted ? isEmpty : isNotEmpty, reason: body);
    }
  });

  test('nullable native destinations admit literal and Null aliases', () async {
    for (final (declaration, value) in [
      ('', 'null'),
      ('final Null value=null;', 'value'),
    ]) {
      for (final argument in [
        'color:$value',
        'weight:$value',
        'style:TextStyle(color:$value,fontWeight:$value)',
      ]) {
        final program = _program(await _translate(
            '$declaration return Probe($argument);',
            custom: true));
        program.validate();
        final invocation =
            program.invoke(captures: _NoCaptures(), parameters: {});
        expect(invocation.values.values, everyElement(isNull),
            reason: argument);
      }
    }
  });
  test('dynamic native aliases obey custom destination contracts', () async {
    for (final (declaration, argument, rejected) in [
      ('final dynamic value=Colors.red;', 'color:value', false),
      ('final Color value=Colors.red;', 'color:value', false),
      (
        'final dynamic value=DefaultTextStyle.of(context).style.fontWeight;',
        'weight:value',
        true
      ),
      ('final dynamic value=Colors.red;', 'color:forward(value)', false),
      ('final dynamic value=const Color(0xff123456);', 'color:value', false),
      (
        'final dynamic value=const Color(0xff123456);',
        'color:forward(value)',
        false
      ),
      ('final dynamic value=const FontWeight(550);', 'weight:value', false),
    ]) {
      final result = await _translate('$declaration return Probe($argument);',
          custom: true);
      if (rejected) {
        expect(result.issues.map((issue) => issue.message),
            contains(contains('runtime subtype')),
            reason: argument);
      } else {
        _program(result).validate();
        if (declaration.contains('Colors.red')) {
          expect(result.dsl, contains('material: "red"'), reason: argument);
        }
      }
    }
  });
  test('dynamic native aliases retain proofs through structured destinations',
      () async {
    for (final (initializer, argument, rejected) in [
      ('Colors.red', 'style:TextStyle(color:value)', false),
      (
        'DefaultTextStyle.of(context).style.fontWeight',
        'style:TextStyle(fontWeight:value)',
        true
      ),
      (
        'Colors.red',
        'gradient:LinearGradient(colors:[value,Colors.black])',
        false
      ),
      ('const Color(0xff123456)', 'style:TextStyle(color:value)', false),
      ('const FontWeight(550)', 'style:TextStyle(fontWeight:value)', false),
      (
        'const Color(0xff123456)',
        'gradient:LinearGradient(colors:[value,Colors.black])',
        false
      ),
    ]) {
      final result = await _translate(
          'final dynamic value=$initializer; return Probe($argument);',
          custom: true);
      if (rejected) {
        expect(result.issues.map((issue) => issue.message),
            contains(contains('runtime subtype')),
            reason: argument);
      } else {
        _program(result).validate();
        if (initializer == 'Colors.red') {
          expect(result.dsl, contains('material: "red"'), reason: argument);
        }
      }
    }
  });
  test('dynamic nullable aliases match native nullable arguments', () async {
    for (final declaration in [
      'final dynamic width=DefaultTextStyle.of(context).style.fontSize;',
      'final double? width=DefaultTextStyle.of(context).style.fontSize;',
      'final dynamic value=DefaultTextStyle.of(context).style.fontSize; final dynamic width=forward(value);',
    ]) {
      final program = _program(
          await _translate('$declaration return SizedBox(width:width);'));
      for (final value in [null, 12.25]) {
        expect(_width(program, value), _nativeDynamic(value));
      }
    }
    final nullAlias = _program(await _translate(
        'final Null width=null; return SizedBox(width:width);'));
    expect(_width(nullAlias, null), isNull);
  });
  test('dynamic alias fixes preserve authored assertions and actual promotions',
      () async {
    final asserted = _program(await _translate(
        'final dynamic width=DefaultTextStyle.of(context).style.fontSize; return SizedBox(width:width!);'));
    expect(() => _nativeAsserted(null), throwsA(isA<TypeError>()));
    expect(() => _width(asserted, null), throwsA(isA<TypeError>()));
    expect(_width(asserted, 12.25), _nativeAsserted(12.25));
    final promoted = _program(await _translate(
        'final double? width=DefaultTextStyle.of(context).style.fontSize; if(width==null) return const SizedBox(width:1.0); return SizedBox(width:width + 1.0);'));
    for (final value in [null, 12.25]) {
      expect(_width(promoted, value), _nativePromoted(value));
    }
  });
}
