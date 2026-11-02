import 'dart:io';
import 'dart:convert';

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:restage_codegen/src/build_body.dart';
import 'package:restage_codegen/src/builder_expression_lowering.dart';
import 'package:restage_codegen/src/widget_builder_lowering.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/factory_emitter.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/host_data_shape.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/native_catalog_index.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import 'helpers.dart';

final class _CapturedKey implements ValueNative {
  _CapturedKey(this.value);

  @override
  final Object value;
  @override
  final NativeBindingContract contract = const NativeBindingContract(
    type: 'flutter.Key',
  );
}

final class _KeyReferenceReader implements ValueReader {
  _KeyReferenceReader(this.key);

  final ValueNative key;

  @override
  int length(List<Object> path) => throw StateError('Unexpected list capture');
  @override
  Object? read(List<Object> path, ValueType type) {
    expect(path, hasLength(1));
    expect(type.kind, 'native');
    expect(type.nativeType, 'flutter.Key');
    expect(type.matches(key), isTrue);
    return key;
  }
}

void main() {
  final catalog = decodeCatalog(
    File(
      '../restage_core/lib/src/widget_catalog/catalog.json',
    ).readAsStringSync(),
  );
  for (final type in [
    'Key',
    'Key?',
    'ObjectKey',
    'GlobalKey',
    'ValueKey<String>',
  ]) {
    for (final form in [
      'native',
      'lazy',
      'list',
      'alias',
      'nested',
      'this',
      'thisAlias',
      'spreadAlias',
      'widgetAlias',
      'conditionalWidgetAlias',
      'helperWidgetAlias',
      'chainWidgetAlias',
      'directHelper',
    ]) {
      final lazy = form == 'lazy' || form == 'nested';
      test('borrows $type at $form construction', () async {
        final text =
            "Text('item', key: ${form == 'alias' || form == 'thisAlias'
                ? 'alias'
                : form == 'this'
                ? 'this.itemKey'
                : 'itemKey'})";
        final body = form == 'nested'
            ? 'Padding(padding: EdgeInsets.zero, child: $text)'
            : text;
        final probe = await parseMethodExpressionFromSourceForTest(
          '''
import 'package:flutter/widgets.dart';
class P extends StatelessWidget {
  const P({required this.itemKey});
  final $type itemKey;
  List<Widget> childrenFor($type key) => [Text('item', key: key)];
  Widget childFor($type key) => Text('item', key: key);
  Widget build(BuildContext context) ${form == 'alias' || form == 'thisAlias'
              ? '{final alias = ${form == 'thisAlias' ? 'this.itemKey' : 'itemKey'}; return $body;}'
              : form == 'conditionalWidgetAlias'
              ? '{final child = true ? $body : const SizedBox(); return Column(children: [child]);}'
              : form == 'helperWidgetAlias'
              ? '{final child = childFor(itemKey); return Column(children: [child]);}'
              : form == 'chainWidgetAlias'
              ? '{final first = (true ? childFor(itemKey) : const SizedBox()); final child = (first); return Column(children: [(child)]);}'
              : form == 'widgetAlias'
              ? '{final child = $body; return Column(children: [child]);}'
              : form == 'spreadAlias'
              ? '{final children = [$body]; return Column(children: [...children]);}'
              : '=> ${lazy
                    ? 'LayoutBuilder(builder: (context, constraints) => $body)'
                    : form == 'list'
                    ? 'Column(children: [$body])'
                    : form == 'directHelper'
                    ? 'Column(children: childrenFor(itemKey))'
                    : body};'}
}
''',
          className: 'P',
          rootPackage: 'apps_examples',
        );
        final parameter =
            probe.classes['P']!.unnamedConstructor!.formalParameters.single;
        final extracted = extractInlinableBuildBody(
          probe.expression.thisOrAncestorOfType<MethodDeclaration>()!.body,
        )!;
        expect(inlinableBuildBodyProblem(extracted), isNull);
        final result =
            ExpressionTranslator(
              catalog: catalog,
              helpers: HelperRegistry(),
            ).translate(
              probe.expression,
              hoistInMount: true,
              rootInlined: InlinedDefinitions(
                localBindings: extracted.localBindings,
              ),
              rootParams: [
                RootContextParam(
                  name: 'itemKey',
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
        expect(
          result.issues,
          isEmpty,
          reason: result.issues.map((issue) => issue.message).join('\n'),
        );
        expect(result.dsl, contains('key: data.context.'));
        expect(result.hoisted, isNotEmpty);
        for (final value in result.hoisted) {
          expect(value.mountSource((name) => 'mount.$name'), 'mount.itemKey');
          expect(
            value.nativeContract,
            NativeBindingContract(
              type: 'flutter.Key',
              nullable: type == 'Key?',
            ),
          );
        }
        if (form == 'lazy' ||
            form == 'list' ||
            form.endsWith('WidgetAlias') ||
            form == 'widgetAlias' ||
            form == 'spreadAlias' ||
            form == 'directHelper')
          expect(result.dsl, contains('nativeKey'));
        if (type == 'Key' && form == 'lazy') {
          final fixture = File('../restage_core/test/fixtures/native_key.json');
          final encoded =
              '${const JsonEncoder.withIndent('  ').convert({
                'source': 'import restage.core; widget Root = ${result.dsl};',
                'slot': result.hoisted.single.key,
              })}\n';
          if (Platform.environment['UPDATE_NATIVE_KEY_FIXTURE'] == '1') {
            fixture.writeAsStringSync(encoded);
          }
          expect(fixture.readAsStringSync(), encoded);
        }
      });
    }
  }
  for (final form in ['spread', 'helper', 'widget']) {
    final helper = form == 'helper';
    test('borrowed collection retains runtime reorder form=$form', () async {
      final source =
          """
import 'package:flutter/widgets.dart';
class P extends StatelessWidget {
  const P({required this.first, required this.second, required this.reverse});
  final Key first;
  final Key second;
  final bool reverse;
  List<Widget> childrenFor(Key key) => [AnimatedContainer(key: key, duration: Duration.zero, width: 20, height: 20)];
  Widget childFor(Key key) => AnimatedContainer(key: key, duration: Duration.zero, width: 20, height: 20);
  Widget build(BuildContext context) {
    final firstKey = this.first;
    final secondKey = this.second;
    ${form == 'widget' ? 'final leftWidget = reverse ? childFor(firstKey) : AnimatedContainer(key: firstKey, duration: Duration.zero, width: 20, height: 20); final rightBranch = reverse ? AnimatedContainer(key: secondKey, duration: Duration.zero, width: 20, height: 20) : childFor(secondKey); final rightWidget = (rightBranch);' : ''}
    final left = ${helper
              ? 'childrenFor(firstKey)'
              : form == 'widget'
              ? '[leftWidget]'
              : '[AnimatedContainer(key: firstKey, duration: Duration.zero, width: 20, height: 20)]'};
    final right = ${helper
              ? 'childrenFor(secondKey)'
              : form == 'widget'
              ? '[rightWidget]'
              : '[AnimatedContainer(key: secondKey, duration: Duration.zero, width: 20, height: 20)]'};
    return Row(children: [...(reverse ? [...right, ...left] : [...left, ...right])]);
  }
}
""";
      final probe = await parseMethodExpressionFromSourceForTest(
        source,
        className: 'P',
        rootPackage: 'apps_examples',
      );
      final extracted = extractInlinableBuildBody(
        probe.expression.thisOrAncestorOfType<MethodDeclaration>()!.body,
      )!;
      expect(inlinableBuildBodyProblem(extracted), isNull);
      final result =
          ExpressionTranslator(
            catalog: catalog,
            helpers: HelperRegistry(),
          ).translate(
            probe.expression,
            hoistInMount: true,
            rootInlined: InlinedDefinitions(
              localBindings: extracted.localBindings,
            ),
            rootParams: [
              for (final parameter
                  in probe.classes['P']!.unnamedConstructor!.formalParameters)
                RootContextParam(
                  name: parameter.name!,
                  type: parameter.type,
                  typeCode: parameter.type.getDisplayString(),
                  kind: RootContextParamKind.named,
                  hostDataShape: deriveHostDataShape(
                    parameter.type,
                    root: parameter.name!,
                  ).shape,
                  field: (parameter as FieldFormalParameterElement).field,
                  isRequired: true,
                  defaultValueCode: null,
                  hasNullDefault: false,
                ),
            ],
          );
      expect(
        result.issues,
        isEmpty,
        reason: result.issues.map((issue) => issue.message).join('\n'),
      );
      expect(result.dsl, contains('nativeKey'));
      final fixture = File(
        '../restage_core/test/fixtures/native_key_spread${form == 'spread' ? '' : '_$form'}.json',
      );
      final encoded =
          '${const JsonEncoder.withIndent('  ').convert({
            'source': 'import restage.core; widget Root = ${result.dsl};',
            'slots': {for (final value in result.hoisted) value.label: value.key},
          })}\n';
      if (Platform.environment['UPDATE_NATIVE_KEY_FIXTURE'] == '1')
        fixture.writeAsStringSync(encoded);
      expect(fixture.readAsStringSync(), encoded);
    });
  }
  test(
    'collection helper stages unused named arguments in source order',
    () async {
      final probe = await parseMethodExpressionFromSourceForTest(
        """
import 'package:flutter/widgets.dart';
class P extends StatelessWidget {
  const P({required this.itemKey, required this.zero, required this.index});
  final Key itemKey;
  final int zero;
  final int index;
  List<Widget> childrenFor(Key key, {required int later, required int earlier}) =>
      [AnimatedContainer(key: key, duration: Duration.zero, width: 20, height: 20)];
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) =>
      Row(children: childrenFor(itemKey, earlier: 1 ~/ zero, later: [0][index])));
}
""",
        className: 'P',
        rootPackage: 'apps_examples',
      );
      final result =
          ExpressionTranslator(
            catalog: catalog,
            helpers: HelperRegistry(),
          ).translate(
            probe.expression,
            hoistInMount: true,
            rootParams: [
              for (final parameter
                  in probe.classes['P']!.unnamedConstructor!.formalParameters)
                RootContextParam(
                  name: parameter.name!,
                  type: parameter.type,
                  typeCode: parameter.type.getDisplayString(),
                  kind: RootContextParamKind.named,
                  hostDataShape: deriveHostDataShape(
                    parameter.type,
                    root: parameter.name!,
                  ).shape,
                  field: (parameter as FieldFormalParameterElement).field,
                  isRequired: true,
                  defaultValueCode: null,
                  hasNullDefault: false,
                ),
            ],
          );
      expect(
        result.issues,
        isEmpty,
        reason: result.issues.map((issue) => issue.message).join('\n'),
      );
      expect(result.dsl, contains('~/'));
      expect(result.dsl, contains('nativeKey'));
      final fixture = File(
        '../restage_core/test/fixtures/native_key_helper_arguments.json',
      );
      final encoded =
          '${const JsonEncoder.withIndent('  ').convert({
            'source': 'import restage.core; widget Root = ${result.dsl};',
            'slot': result.hoisted.single.key,
          })}\n';
      if (Platform.environment['UPDATE_NATIVE_KEY_FIXTURE'] == '1')
        fixture.writeAsStringSync(encoded);
      expect(fixture.readAsStringSync(), encoded);
    },
  );
  test(
    'borrowed key helper preserves lexical writes and early returns',
    () async {
      final keyCatalog = decodeCatalog(
        File('test/fixtures/native_key_restage_core.json').readAsStringSync(),
      );
      final probe = await parseMethodExpressionFromSourceForTest(
        r"""
import 'package:flutter/widgets.dart';
class P extends StatelessWidget {
  const P({required this.itemKey});
  final Key itemKey;
  Widget childFor(Key key, int seed) {
    var count = seed;
    count += 2;
    if (count > 2) return Text('$count', key: key);
    return Text('small', key: key);
  }
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) => childFor(itemKey, 1));
}
""",
        className: 'P',
        rootPackage: 'apps_examples',
      );
      final parameter =
          probe.classes['P']!.unnamedConstructor!.formalParameters.single;
      final result =
          ExpressionTranslator(
            catalog: keyCatalog,
            helpers: HelperRegistry(),
          ).translate(
            probe.expression,
            hoistInMount: true,
            rootParams: [
              RootContextParam(
                name: 'itemKey',
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
      expect(
        result.issues,
        isEmpty,
        reason: result.issues.map((issue) => issue.message).join('\n'),
      );
      final encoded = RegExp(
        r'program: ("(?:\\.|[^"\\])*")',
      ).firstMatch(result.dsl)!.group(1)!;
      final program = BuilderProgram.decode(jsonDecode(encoded) as String);
      expect(program.values.locals, isNotEmpty);
      final original = Object();
      final captured = _CapturedKey(original);
      final invocation = program.invoke(
        captures: _KeyReferenceReader(captured),
        parameters: {},
      );
      expect(invocation.values.values, contains('3'));
      expect(invocation.values.values, isNot(contains('small')));
      expect(invocation.keyType, 'nativeKey');
      expect(invocation.projectedKey, same(captured));
      expect((invocation.projectedKey! as ValueNative).value, same(original));
    },
  );

  test(
    'nullable callback result resolves a null alias before body emission',
    () async {
      final probe = await parseMethodExpressionFromSourceForTest(
        """
import 'package:flutter/widgets.dart';
class P {
  Widget? build() { final child = null; return child; }
}
""",
        className: 'P',
        rootPackage: 'apps_examples',
      );
      final extracted = extractInlinableBuildBody(
        probe.expression.thisOrAncestorOfType<MethodDeclaration>()!.body,
      )!;
      final values = BuilderExpressionLowering(
        capture: (_) => throw StateError('Unexpected capture'),
      );
      final lowering = WidgetBuilderLowering(
        expressions: values,
        contract: const WidgetBuilderContract(
          parameters: [],
          nullableResult: true,
        ),
        scope: 'nullable',
        resolve: (expression) => expression is SimpleIdentifier
            ? extracted.localBindings[expression.element] ?? expression
            : expression,
        translateBody: (_) =>
            throw StateError('A null result must not emit a body'),
      );
      final result = lowering.resultFor(probe.expression);
      expect(result.kind, 'null');
      expect(lowering.bodies, isEmpty);
      expect(lowering.expressions.nodes, isEmpty);
    },
  );
  for (final call in {
    '(null as Other).items()': false,
    'Other().items()': false,
    'this.items()': false,
    'items()': true,
    'Other.staticItems()': true,
    'topItems()': true,
  }.entries) {
    test('collection helper receiver admission ${call.key}', () async {
      final probe = await parseMethodExpressionFromSourceForTest(
        """
import 'package:flutter/widgets.dart';
List<Widget> topItems() => [const Text('top')];
class Other {
  List<Widget> items() => [const Text('other')];
  static List<Widget> staticItems() => [const Text('static')];
}
class P extends StatelessWidget {
  const P({required this.itemKey});
  final Key itemKey;
  List<Widget> items() => [const Text('own')];
  Widget build(BuildContext context) => Column(children: [Text('item', key: itemKey), ...${call.key}]);
}
""",
        className: 'P',
        rootPackage: 'apps_examples',
      );
      final parameter =
          probe.classes['P']!.unnamedConstructor!.formalParameters.single;
      final result =
          ExpressionTranslator(
            catalog: catalog,
            helpers: HelperRegistry(),
          ).translate(
            probe.expression,
            hoistInMount: true,
            rootParams: [
              RootContextParam(
                name: 'itemKey',
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
      if (call.value) {
        expect(
          result.issues,
          isEmpty,
          reason: result.issues.map((issue) => issue.message).join('\n'),
        );
        expect(result.dsl, contains('nativeKey'));
      } else {
        expect(result.issues, hasLength(1));
        expect(result.issues.single.code, IssueCode.propertyValueTypeMismatch);
        expect(
          result.issues.single.message,
          'Widget spreads require an analyzable list expression: ${call.key}',
        );
        expect(result.dsl, isNot(contains('Text(text: "other")')));
      }
    });
  }
  test('native factory passes the key to the actual Flutter constructor', () {
    final entry = catalog.widgets.firstWhere((entry) => entry.name == 'Text');
    expect(
      emitFactoryFunction(entry, nativeIndex: NativeCatalogIndex(catalog)),
      contains(
        "key: RestageDecoders.nativeBinding<Key>(context, source, <Object>['key'], type: 'flutter.Key')",
      ),
    );
  });
}
