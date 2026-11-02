import 'dart:io';

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:restage_codegen/src/build_body.dart';
import 'package:restage_codegen/src/installed_native_call.dart';
import 'package:restage_codegen/src/builder_expression_lowering.dart';
import 'package:restage_codegen/src/capability_derivation.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final catalog = decodeCatalog(
    File(
      '../restage_core/lib/src/widget_catalog/catalog.json',
    ).readAsStringSync(),
  );

  for (final body in [
    "LayoutBuilder(builder: (context, constraints) { final itemKey = ObjectKey(items[0]); return Text('item', key: itemKey); })",
    "LayoutBuilder(builder: (context, constraints) { final itemKey = ObjectKey(items[0]); final alias=itemKey; return Text('item',key:alias); })",
    "LayoutBuilder(builder: (context, constraints) { final itemKey = ObjectKey(items[0]); return true ? Text('item',key:itemKey) : const SizedBox(); })",
    "LayoutBuilder(builder: (context, constraints) { final itemKey = ObjectKey(items[0]); return LayoutBuilder(builder: (context, inner) => Text('item', key: itemKey)); })",
    "GridView.custom(gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 1), childrenDelegate: SliverChildBuilderDelegate((context, index) { final itemKey = ObjectKey(items[index]); return Text('item', key: itemKey); }, childCount: 2))",
  ]) {
    test(
      'native key initializer retains its invocation frame: $body',
      () async {
        final result = await compileConstructedKey(body);
        expect(
          result.issues,
          isEmpty,
          reason: result.issues.map((issue) => issue.message).join('\n'),
        );
        expect(result.dsl, contains('native.call'));
        expect(result.dsl, contains('nativeKey'));
        expect(result.dsl, contains('nativeLocal'));
        expect(
          result.hoisted.where((value) => value.nativeCall != null),
          hasLength(1),
        );
        final manifest = deriveCapabilityManifest(
          rfw.parseLibraryFile(
            'import restage.core; widget Root = ${result.dsl};',
          ),
          catalog,
          hoisted: result.hoisted,
        );
        expect(
          manifest.issues,
          isEmpty,
          reason: manifest.issues.map((issue) => issue.message).join('\n'),
        );
        expect(manifest.manifest!.builtInFloor, 24);
      },
    );
  }
  for (final body in [
    "Text('item', key: ObjectKey(items[0]))",
    "LayoutBuilder(builder: (context, constraints) => Text('item', key: ObjectKey(items[0])))",
  ]) {
    test('fresh key without initializer refuses: $body', () async {
      final result = await compileConstructedKey(body);
      expect(
        result.issues.map((issue) => issue.message),
        contains(contains('explicit callback or helper prelude initializer')),
      );
      expect(
        result.hoisted.where((value) => value.nativeCall != null),
        isEmpty,
      );
    });
  }
  for (final callback in [
    'findIndex',
    '(Key key) => findIndex(key)',
    '(Key key) => items.indexWhere((item) => identical(item, (key as ObjectKey).value))',
  ]) {
    for (final nested in [false, true]) {
      test(
        'native key index callback retains original native inputs nested=$nested $callback',
        () async {
          final grid =
              "GridView.builder(gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:1),itemBuilder:(context,index) {final key=ObjectKey(items[index]);return Text('item',key:key);},findChildIndexCallback:$callback)";
          final result = await compileConstructedKey(
            nested
                ? "LayoutBuilder(builder:(context,constraints)=>$grid)"
                : grid,
          );
          expect(
            result.issues,
            isEmpty,
            reason: result.issues.map((i) => i.message).join('\n'),
          );
          expect(result.dsl, contains('nativeKeyIndex'));
          final manifest = deriveCapabilityManifest(
            rfw.parseLibraryFile(
              'import restage.core; widget Root = ${result.dsl};',
            ),
            catalog,
            hoisted: result.hoisted,
          );
          expect(
            manifest.issues,
            isEmpty,
            reason: manifest.issues.map((i) => i.message).join('\n'),
          );
          expect(manifest.manifest!.builtInFloor, 24);
        },
      );
    }
  }
  test('scalar ValueKey source bytes remain unchanged', () async {
    final result = await compileConstructedKey(
      "GridView.builder(gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:1),itemBuilder:(context,index)=>Text('item',key:ValueKey<int>(index)),findChildIndexCallback:(Key key)=>(key as ValueKey<int>).value)",
    );
    expect(result.issues, isEmpty);
    final fixture = File(
      'test/fixtures/constructed_key_scalar_baseline.rfwtxt',
    );
    if (Platform.environment['WRITE_SCALAR_KEY_BASELINE'] == '1')
      fixture.writeAsStringSync(result.dsl);
    expect(result.dsl, fixture.readAsStringSync());
    expect(result.dsl, isNot(contains('nativeKeyIndex')));
  });
  for (final key in [
    "const ObjectKey('first')",
    'stableKey',
    'P.stableKey',
    'topKey',
  ]) {
    test(
      'resolved constant native key is emitted and reconciled: $key',
      () async {
        for (final body in [
          "Text('item',key:$key)",
          "Row(children:[Text('item',key:$key)])",
        ]) {
          final result = await compileConstructedKey(body);
          expect(
            result.issues,
            isEmpty,
            reason: result.issues.map((i) => i.message).join('\n'),
          );
          expect(result.dsl, contains('key: data.context.'));
          expect(
            result.hoisted.where((h) => h.nativeConstant != null),
            hasLength(1),
          );
          if (body.startsWith('Row')) {
            expect(result.dsl, contains('__RestageBuilderContinuation'));
            expect(result.dsl, contains('nativeKey'));
          }
        }
      },
    );
  }
  for (final prelude in [
    "final child=Text('item',key:stableKey); final children=[child];",
    "const alias=stableKey; final children=[Text('item',key:alias)];",
    "const original=ObjectKey('first'); const alias=original; final children=[Text('item',key:alias)];",
    "final children=[Text('item',key:const ObjectKey('first'))];",
  ]) {
    test(
      'constant keyed collection resolves shared aliases: $prelude',
      () async {
        final result = await compileConstructedKey(
          'Row(children:[...children])',
          prelude: prelude,
        );
        expect(
          result.issues,
          isEmpty,
          reason: result.issues.map((i) => i.message).join('\n'),
        );
        expect(result.dsl, contains('__RestageBuilderContinuation'));
        expect(result.dsl, contains('nativeKey'));
        expect(result.dsl, contains('key: data.context.'));
      },
    );
  }
  test(
    'local native constant aliases preserve original imported authority',
    () async {
      final closure = await parseExpressionFromSourceForTest(
        """
import 'package:flutter/widgets.dart';
import 'native_keys.dart' as original;
ObjectKey Function() x() => () {const first=original.stableKey; const alias=first; return alias;};
""",
        rootPackage: 'apps_examples',
        otherFiles: {
          'lib/native_keys.dart':
              "import 'package:flutter/widgets.dart'; const stableKey=ObjectKey('first');",
        },
      );
      final expression =
          (((closure as FunctionExpression).body as BlockFunctionBody)
                      .block
                      .statements
                      .last
                  as ReturnStatement)
              .expression!;
      final value = installedNativeConstant(expression, type: 'flutter.Key');
      expect(value.nativeConstant!.source, 'original.stableKey');
      expect(value.nativeConstant!.inputs, isEmpty);
      expect(value.nativeConstant!.captures, isEmpty);
      expect(installedNativeConstantType(expression), 'flutter.Key');
    },
  );
  test('local native constant aliases retain private Symbol refusal', () async {
    final closure = await parseExpressionFromSourceForTest("""
import 'package:flutter/widgets.dart';
ObjectKey Function() x() => () {const first=ObjectKey(#_private); const alias=first; return alias;};
""", rootPackage: 'apps_examples');
    final expression =
        (((closure as FunctionExpression).body as BlockFunctionBody)
                    .block
                    .statements
                    .last
                as ReturnStatement)
            .expression!;
    expect(
      () => installedNativeConstant(expression, type: 'flutter.Key'),
      throwsA(
        isA<BuilderLoweringException>().having(
          (e) => e.reason,
          'reason',
          contains('Private Symbol'),
        ),
      ),
    );
  });
  test(
    'source native constant preserves private-symbol refusal as a diagnostic',
    () async {
      final result = await compileConstructedKey(
        "Text('item',key:const ObjectKey(#_private))",
      );
      expect(
        result.issues.map((i) => i.message),
        contains(contains('Private Symbol')),
      );
      expect(result.hoisted, isEmpty);
    },
  );
  for (final key in [
    'const CustomKey()',
    'unsupportedKey',
    "const GlobalObjectKey('constant')",
  ]) {
    test('unsupported constant key refuses explicitly: $key', () async {
      final result = await compileConstructedKey("Text('item',key:$key)");
      expect(
        result.issues.map((i) => i.message),
        contains(contains('constant Key family')),
      );
      expect(result.hoisted, isEmpty);
    });
  }
  test('actual constant ObjectKey uses a compiled native binding', () async {
    final result = await compileConstructedKey(
      "Text('item', key: const ObjectKey('constant'))",
    );
    expect(result.issues, isEmpty);
    expect(result.hoisted, hasLength(1));
    expect(result.hoisted.single.nativeCall, isNull);
    expect(
      result.hoisted.single.nativeContract,
      const NativeBindingContract(type: 'flutter.Key'),
    );
    expect(
      result.hoisted.single.mountSource((_) => throw StateError('No input')),
      contains("const ObjectKey('constant')"),
    );
  });
}

Future<TranslationResult> compileConstructedKey(
  String body, {
  String prelude = '',
}) async {
  final catalog = decodeCatalog(
    File(
      '../restage_core/lib/src/widget_catalog/catalog.json',
    ).readAsStringSync(),
  );
  final probe = await parseMethodExpressionFromSourceForTest(
    '''
import 'package:flutter/widgets.dart';
const topKey = ObjectKey('first');
class CustomKey extends LocalKey {const CustomKey();}
class P extends StatelessWidget {
  const P({required this.items, required this.findIndex, required this.count});
  final List<Object> items;
  final int? Function(Key) findIndex;
  final int count;
  static const stableKey = ObjectKey('first');
  static const otherKey = ObjectKey('second');
  static const unsupportedKey = CustomKey();
  Widget build(BuildContext context) ${prelude.isEmpty ? '=> $body;' : '{ $prelude return $body; }'}
}
''',
    className: 'P',
    rootPackage: 'apps_examples',
  );
  final parameters = probe.classes['P']!.unnamedConstructor!.formalParameters;
  final extracted = extractInlinableBuildBody(
    probe.expression.thisOrAncestorOfType<MethodDeclaration>()!.body,
  )!;
  expect(inlinableBuildBodyProblem(extracted), isNull);
  return ExpressionTranslator(
    catalog: catalog,
    helpers: HelperRegistry(),
  ).translate(
    probe.expression,
    hoistInMount: true,
    rootInlined: InlinedDefinitions(localBindings: extracted.localBindings),
    rootParams: [
      for (final parameter in parameters)
        RootContextParam(
          name: parameter.name!,
          type: parameter.type,
          typeCode: parameter.type.getDisplayString(),
          kind: RootContextParamKind.named,
          hostDataShape: null,
          field: (parameter as FieldFormalParameterElement).field,
          isRequired: true,
          defaultValueCode: null,
          hasNullDefault: false,
        ),
    ],
  );
}
