import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:restage_codegen/src/builder_expression_lowering.dart';
import 'package:restage_codegen/src/closed_callback_lowering.dart';
import 'package:restage_codegen/src/capability_derivation.dart';
import 'package:restage_codegen/src/catalog_validator.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/installed_native_call.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' show parseLibraryFile;
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  InstalledNativeCallPlan plan(Expression expression,
          {Map<Expression, String?> constantStrings = const {}}) =>
      planInstalledNativeCall(expression,
          resultType: const ValueType.native('test.Native'),
          captureFor: (_) => null,
          inputFor: (_) => null,
          constantStrings: constantStrings);

  test('inert native selections accept only nonthrowing stored inputs',
      () async {
    for (final (body, accepted) in <(String, bool)>[
      ('flag ? value : fallback', true),
      ('optional ?? fallback', true),
      ('(!flag || other && flag) ? value : fallback', true),
      ('optional == null ? fallback : value', true),
      ('flag ? value : make()', false),
      ('(value as Object)', true),
      ('(optional as Object?)', true),
      ('(optional as Object)', false),
      ('(wide as Native)', false),
      ('(dynamicValue as Native)', false),
      ('flag ? value : getter', false),
      ('flag ? value : Native()', false),
      ('flag ? value : values[0]', false),
      ('optional!', false),
      ('() => value', false),
      ('alias', false),
    ]) {
      final expression = await parseExpressionFromSourceForTest('''
class Native { const Native(); }
const fallback = Native();
Native make() => Native();
Native get getter => Native();
Object x(bool flag, bool other, Native value, Native? optional,
    Object wide, dynamic dynamicValue, List<Native> values, Native alias) => $body;
''');
      expect(
          isInertNativeSelection(expression,
              isBorrowedRead: (read) =>
                  read is SimpleIdentifier &&
                  const {
                    'flag',
                    'other',
                    'value',
                    'optional',
                    'wide',
                    'dynamicValue'
                  }.contains(read.name)),
          accepted,
          reason: body);
    }
    final constant = await parseExpressionFromSourceForTest(
        'class Native { const Native(); } const alias = Native(); Object x() => alias;');
    expect(
        isInertNativeSelection(constant, isBorrowedRead: (_) => false), isTrue);
  });

  test(
      'generic Function.apply dispatch is refused by resolved callable identity',
      () async {
    final refusal = throwsA(isA<BuilderLoweringException>().having(
        (error) => error.reason,
        'reason',
        contains('closed typed native calls')));
    for (final call in [
      'Function.apply(() => 1, [])',
      'dispatch(() => 1, [])',
      '(Function.apply)(() => 1, [])',
      'Holder.dispatch(() => 1, [])',
    ]) {
      for (final body in [call, '() => $call']) {
        final expression = await parseExpressionFromSourceForTest('''
const dispatch = Function.apply;
class Holder { static const dispatch = Function.apply; }
dynamic x() => $body;
''');
        expect(() => plan(expression), refusal, reason: body);
      }
    }
    for (final body in [
      'Function.apply',
      'dispatch',
      'Holder.dispatch',
      'dispatchers'
    ]) {
      final expression = await parseExpressionFromSourceForTest('''
const dispatch = Function.apply;
const dispatchers = [Function.apply];
class Holder { static const dispatch = Function.apply; }
dynamic x() => $body;
''');
      expect(() => plan(expression), refusal, reason: body);
      expect(() => installedNativeConstant(expression, type: 'test.Native'),
          refusal,
          reason: body);
    }
    final qualified = await parseExpressionFromSourceForTest('''
import 'dart:core' as core;
dynamic x() => core.Function.apply(() => 1, []);
''');
    expect(() => plan(qualified), refusal);
    final unrelated = await parseExpressionFromSourceForTest('''
class Function { static int apply(int value) => value; }
int x() => Function.apply(3);
''');
    expect(() => plan(unrelated), returnsNormally);
  });

  test('resolved constructor and type provenance changes native identity',
      () async {
    for (final body in [
      'Tint()',
      'Tint.named()',
      'Tint.new',
      '<Tint>[]',
      '() => Tint()'
    ]) {
      Future<InstalledNativeCallPlan> imported(String library) async =>
          plan(await parseExpressionFromSourceForTest(
              "import '$library.dart'; Object x() => $body;",
              otherFiles: {
                'lib/$library.dart': 'class Tint { Tint(); Tint.named(); }'
              }));
      final first = await imported('a');
      final second = await imported('b');
      expect(first.source, second.source);
      expect(first.key, isNot(second.key), reason: body);
      expect(first.contract.call!.implementation,
          isNot(second.contract.call!.implementation),
          reason: body);
    }
  });

  test('resolved constant values change native implementation identity',
      () async {
    Future<InstalledNativeCallPlan> constant(String value) async =>
        plan(await parseExpressionFromSourceForTest(
            "const name = '$value'; String Function() x() => () => name;"));
    expect((await constant('a')).key, isNot((await constant('b')).key));
    Future<String> color(int value) async =>
        installedNativeConstant(await parseExpressionFromSourceForTest('''
import 'package:flutter/material.dart' as f;
class Palette { static const color = f.Color($value); }
f.Color x() => Palette.color;
''', rootPackage: 'apps_examples'), type: 'flutter.Color').key;
    expect(await color(1), isNot(await color(2)));
  });

  test('constant name substitutions remove lexical input authority', () async {
    final expression = await parseExpressionFromSourceForTest('''
String Function() x() => () { const name = 'fixed'; return name; };
''') as FunctionExpression;
    final read = ((expression.body as BlockFunctionBody).block.statements.last
            as ReturnStatement)
        .expression!;
    final fixed = plan(expression, constantStrings: {read: 'fixed'});
    expect(fixed.source, contains('return "fixed";'));
    expect(fixed.inputs, isEmpty);
    expect(plan(read, constantStrings: {read: 'fixed'}).source, '"fixed"');
    expect(() => plan(read), throwsA(isA<BuilderLoweringException>()));
    expect(() => plan(expression, constantStrings: {read: 'other'}),
        throwsA(isA<BuilderLoweringException>()));
    final nullExpression = await parseExpressionFromSourceForTest('''
String? Function() x() => () { const String? name = null; return name; };
''') as FunctionExpression;
    final nullRead = ((nullExpression.body as BlockFunctionBody)
            .block
            .statements
            .last as ReturnStatement)
        .expression!;
    expect(plan(nullExpression, constantStrings: {nullRead: null}).source,
        contains('return null;'));
  });

  test('class static fields getters methods and tearoffs keep their owner',
      () async {
    final expression = await parseExpressionFromSourceForTest('''
int answer() => -1;
class Owner {
  static const constant = 2;
  static final field = 3;
  static int get getter => 4;
  static int answer() => 5;
  int Function() x() => () { final tearoff = answer; return constant + field + getter + answer() + tearoff(); };
}
''', enclosingClassName: 'Owner');
    final compiled = plan(expression).source;
    for (final member in ['constant', 'field', 'getter', 'answer']) {
      expect(compiled, contains('Owner.$member'));
    }
    final shadowed = await parseExpressionFromSourceForTest('''
class Owner {
  static int answer() => 1;
  int Function(int) x() => (int Owner) => answer() + Owner;
}
''', enclosingClassName: 'Owner');
    expect(() => plan(shadowed), throwsA(isA<BuilderLoweringException>()));
  });

  test('nullable compiled constants keep nullable binding declarations',
      () async {
    final expression = await parseExpressionFromSourceForTest('''
import 'package:flutter/material.dart' as f;
const f.Color? absent = null;
f.Color? x() => absent;
''', rootPackage: 'apps_examples');
    final constant = installedNativeConstant(expression, type: 'flutter.Color');
    expect(constant.nativeContract!.nullable, isTrue);
    expect(constant.mountSource((_) => throw StateError('input')), 'absent');
  });

  test('root and returned-widget native effects are refused before emission',
      () async {
    final catalog = decodeCatalog(
        File('../restage_core/lib/src/widget_catalog/catalog.json')
            .readAsStringSync());
    for (final builder in [false, true]) {
      final root =
          "f.ColoredBox(child: f.Opacity(opacity: badOpacity), color: f.MaterialColor(1, swatch('later')))";
      final expression = await parseExpressionFromSourceForTest('''
import 'package:flutter/material.dart' as f;
double badOpacity = -1;
Map<int, f.Color> swatch(String label) => {};
f.Widget x() => ${builder ? 'f.LayoutBuilder(builder: (context, constraints) => $root)' : root};
''', rootPackage: 'apps_examples');
      final result =
          ExpressionTranslator(catalog: catalog, helpers: HelperRegistry())
              .translate(expression, hoistInMount: true);
      expect(
          result.issues.where((issue) =>
              issue.message.contains('explicit callback or helper prelude')),
          isNotEmpty);
      expect(
          result.hoisted.where((value) => value.nativeCall != null), isEmpty);
    }
  });

  test('native interpolation braces relocated captures and static members',
      () async {
    final expression = await parseExpressionFromSourceForTest(r'''
class Owner {
  static const label = 'static';
  String Function() x(int count) => () => '$label:$count:${count++}';
}
''', enclosingClassName: 'Owner');
    final compiled = planInstalledNativeCall(expression,
        resultType: const ValueType.native('callback'),
        captureFor: (_) =>
            const InstalledNativeCapture('count', ValueType.integer),
        inputFor: (_) => null);
    expect(
        compiled.source,
        contains(
            r'${Owner.label}:${_restageCapture0.value}:${_restageCapture0.value++}'));
  });

  test(
      'private Symbol constants fail closed rather than losing library identity',
      () async {
    for (final package in ['apps_examples', 'restage']) {
      final expression = await parseExpressionFromSourceForTest(r'''
import 'package:flutter/widgets.dart' as f;
f.ObjectKey x() => const f.ObjectKey(#_token);
''', rootPackage: package);
      expect(() => installedNativeConstant(expression, type: 'flutter.Key'),
          throwsA(isA<BuilderLoweringException>()));
    }
    final public = await parseExpressionFromSourceForTest(r'''
import 'package:flutter/widgets.dart' as f;
f.ObjectKey x() => const f.ObjectKey(#token);
''', rootPackage: 'apps_examples');
    expect(installedNativeConstant(public, type: 'flutter.Key').nativeConstant,
        isNotNull);
  });

  test('native calls refuse an unbound root prelude local', () async {
    final expression = await parseExpressionFromSourceForTest(
        'int Function() x(int count) => () => count;');
    final lowering = BuilderExpressionLowering(capture: (_) => '1');
    expect(
        () => lowering.lowerInstalledNativeCall(expression,
            resultType: const ValueType.native('callback'), install: (_) {}),
        throwsA(isA<BuilderLoweringException>()));
  });

  test('native closures refuse enum cells projected as strings', () async {
    final expression = await parseExpressionFromSourceForTest(
        'enum Mode { first } Mode Function() x(Mode mode) => () => mode;');
    expect(
        () => planInstalledNativeCall(expression,
            resultType: const ValueType.native('callback'),
            captureFor: (_) =>
                const InstalledNativeCapture('mode', ValueType.string),
            inputFor: (_) => null),
        throwsA(isA<BuilderLoweringException>()));
  });

  test('callback statement lowering captures the declared mutable cell',
      () async {
    final expression = await parseExpressionFromSourceForTest('''
int Function() Function() x() => () {
  var count = 0;
  return () => count++;
};
''') as FunctionExpression;
    final installed = <InstalledNativeCallPlan>[];
    final lowering = BuilderExpressionLowering(
        capture: (_) => throw StateError('capture'),
        extension: (value, current) => value is FunctionExpression
            ? current.lowerInstalledNativeCall(value,
                resultType: const ValueType.native('callback'),
                install: installed.add)
            : null);
    final root = closedValueCallback(lowering).body(expression.body);
    final program = lowering.program(root);
    program.validate(operations: lowering.operations);
    expect(program.locals, hasLength(1));
    expect(installed.single.captures.values.single.slot,
        program.locals.keys.single);
    expect(program.nodes[program.root].op, 'let');
  });

  test(
      'ordinary source installs a lazy native color and derives its capability',
      () async {
    final expression = await parseExpressionFromSourceForTest('''
import 'package:flutter/material.dart' as f;
f.Widget x() => f.LayoutBuilder(builder: (context, constraints) {
  final color = f.MaterialColor(0xff102030,
      <int, f.Color>{500: const f.Color(0xff102030)});
  return f.ColoredBox(color: color);
});
''', rootPackage: 'apps_examples');
    final catalog = decodeCatalog(
        File('../restage_core/lib/src/widget_catalog/catalog.json')
            .readAsStringSync());
    final result =
        ExpressionTranslator(catalog: catalog, helpers: HelperRegistry())
            .translate(expression, hoistInMount: true);
    expect(result.issues.where((issue) => !issue.code.isInformational), isEmpty,
        reason: result.issues.map((issue) => issue.message).join('; '));
    expect(result.hoisted.where((value) => value.nativeCall != null),
        hasLength(1));
    final capability = deriveCapabilityManifest(
        parseLibraryFile('import restage.core; widget Root = ${result.dsl};'),
        catalog,
        hoisted: result.hoisted);
    expect(capability.manifest!.builtInFloor, 24);
    final emitted =
        parseLibraryFile('import restage.core; widget Root = ${result.dsl};');
    expect(
        validateModelAgainstCatalog(emitted, catalog,
            operations: result.valueOperations),
        isEmpty);
    expect(() => validateModelAgainstCatalog(emitted, catalog),
        throwsFormatException);
    expect(
        () => deriveCapabilityManifest(
            parseLibraryFile(
                'import restage.core; widget Root = ${result.dsl};'),
            catalog),
        throwsFormatException);
  });

  test('closure captures use resolved elements and retain native writes',
      () async {
    final expression = await parseExpressionFromSourceForTest('''
int Function(int) x(int count) => (int ignored) {
  final shadow = (int count) => count + 10;
  return count++ + shadow(ignored);
};
''');
    final plan = planInstalledNativeCall(expression,
        resultType: const ValueType.native('callback'),
        captureFor: (element) => element.name == 'count'
            ? const InstalledNativeCapture('counter', ValueType.integer)
            : null,
        inputFor: (_) => null);
    expect(plan.captures.length, 1);
    expect(plan.source, contains('(int count) => count + 10'));
    expect(plan.source, contains('_restageCapture0.value++'));
    expect(plan.source, contains('shadow(ignored)'));
    expect(plan.node.value,
        containsPair('captures', {'_restageCapture0': 'counter'}));
    final generated = plan.adapterSource(core: 'r.', shared: 'r.');
    expect(generated, contains('r.NativeCallAdapter('));
    expect(generated, contains('.cast<int>()'));
    expect(generated, contains('final int Function(int) _restageResult'));
    expect(plan.binding.nativeCall, same(plan));
  });

  test('promoted capture reads preserve their analyzed type', () async {
    final expression = await parseExpressionFromSourceForTest('''
int Function() x(int? count) => () {
  if (count == null) return 0;
  return count + 1;
};
''');
    final plan = planInstalledNativeCall(expression,
        resultType: const ValueType.native('callback'),
        captureFor: (_) => const InstalledNativeCapture(
            'counter', ValueType('int', nullable: true)),
        inputFor: (_) => null);
    expect(
        plan.source, contains('_restageAs<int>(_restageCapture0.value) + 1'));
  });

  test('constructor leaves native indexing inside the installed body',
      () async {
    final expression = await parseExpressionFromSourceForTest('''
import 'package:flutter/widgets.dart';
ObjectKey x(List<Object> items, int index) => ObjectKey(items[index]);
''', rootPackage: 'apps_examples');
    final plan = planInstalledNativeCall(expression,
        resultType: const ValueType.native('flutter.Key'),
        captureFor: (element) => element.name == 'index'
            ? const InstalledNativeCapture('index', ValueType.integer)
            : null,
        inputFor: (_) => const InstalledNativeInput(
            0, ValueType.native('dart.List<Object>')));
    expect(plan.source, 'ObjectKey(_restageInput0[_restageCapture0.value])');
    expect(plan.inputs.single.node, 0);
    expect(plan.adapterSource(core: '', shared: ''),
        contains('as ValueNative).value'));
  });

  test('installed body changes alter the declared build identity', () async {
    Future<InstalledNativeCallPlan> plan(String body) async =>
        planInstalledNativeCall(
            await parseExpressionFromSourceForTest(
                'int Function() x() => () => $body;'),
            resultType: const ValueType.native('callback'),
            captureFor: (_) => null,
            inputFor: (_) => null);
    final before = await plan('1');
    final after = await plan('2');
    expect(before.contract.call!.implementation,
        isNot(after.contract.call!.implementation));
    expect(before.key, isNot(after.key));
  });

  test('source instance capture is refused', () async {
    final expression = await parseExpressionFromSourceForTest('''
class Owner {
  int count = 0;
  int Function() x() => () => count++;
}
''', enclosingClassName: 'Owner');
    expect(
        () => planInstalledNativeCall(expression,
            resultType: const ValueType.native('callback'),
            captureFor: (_) => null,
            inputFor: (_) => null),
        throwsA(isA<BuilderLoweringException>()));
  });

  test('generated identifiers do not shadow authored closure locals', () async {
    final expression = await parseExpressionFromSourceForTest('''
int Function(int) x(int count) => (int _restageCapture0) => count++ + _restageCapture0;
''');
    final plan = planInstalledNativeCall(expression,
        resultType: const ValueType.native('callback'),
        captureFor: (_) =>
            const InstalledNativeCapture('count', ValueType.integer),
        inputFor: (_) => null);
    expect(
        plan.source, contains('_restage_Capture0.value++ + _restageCapture0'));
    expect(plan.adapterSource(core: '', shared: ''),
        contains('(_restage_Inputs, _restage_Cells)'));
  });

  test('writes cannot silently snapshot an immutable input', () async {
    final expression = await parseExpressionFromSourceForTest(
        'int Function() x(int count) => () => count++;');
    expect(
        () => planInstalledNativeCall(expression,
            resultType: const ValueType.native('callback'),
            captureFor: (_) => null,
            inputFor: (_) => const InstalledNativeInput(0, ValueType.integer)),
        throwsA(isA<BuilderLoweringException>()));
  });
}
