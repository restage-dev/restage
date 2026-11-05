import 'dart:io';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'dart:isolate';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/factory_emitter.dart';
import 'package:restage_compiler_core/restage_compiler_core.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:restage_codegen/src/builder_expression_lowering.dart';
import 'package:restage_codegen/src/widget_builder_lowering.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;
import 'package:test/test.dart';
import 'helpers.dart';

final class _EmptyReader implements ValueReader {
  @override
  int length(List<Object> path) => throw StateError('Unexpected capture');
  @override
  Object? read(List<Object> path, ValueType type) =>
      throw StateError('Unexpected capture');
}

final class _MapReader implements ValueReader {
  _MapReader(this.values);
  final Map<String, Object?> values;
  @override
  Object? read(List<Object> path, ValueType type) {
    Object? value = values;
    for (final segment in path) {
      value = segment is int
          ? (value! as List)[segment]
          : (value! as Map)[segment];
    }
    return value;
  }

  @override
  int length(List<Object> path) =>
      (read(path, const ValueType('list', item: ValueType.string))! as List)
          .length;
}

void main() {
  test('widget callback locals use shared lexical control flow', () async {
    final uri = await Isolate.resolvePackageUri(
      Uri.parse('package:restage_core/src/widget_catalog/catalog.json'),
    );
    final catalog = decodeCatalog(File.fromUri(uri!).readAsStringSync());
    final expression = await parseExpressionFromSourceForTest(r"""
      import 'package:flutter/widgets.dart';
      Widget x() => LayoutBuilder(builder: (context, constraints) {
        var value = 1;
        final before = value++;
        if (constraints.maxWidth > 100) value += 3;
        return Text('$before:$value');
      });
    """, rootPackage: 'apps_examples');
    final translated = ExpressionTranslator(
      catalog: catalog,
      helpers: HelperRegistry(),
    ).translate(expression);
    expect(translated.issues, isEmpty, reason: translated.issues.toString());
    final root =
        rfw
                .parseLibraryFile(
                  'import restage.core;widget Root=${translated.dsl};',
                )
                .widgets
                .single
                .root
            as rfw.ConstructorCall;
    final envelope =
        (root.arguments['builder']! as rfw.ConstructorCall).arguments;
    final program = BuilderProgram.decode(envelope['program']! as String);
    expect(
      program
          .invoke(
            captures: _EmptyReader(),
            parameters: {
              'arg1': {'maxWidth': 200.0},
            },
          )
          .values
          .values,
      contains('1:5'),
    );
    expect(
      program
          .invoke(
            captures: _EmptyReader(),
            parameters: {
              'arg1': {'maxWidth': 50.0},
            },
          )
          .values
          .values,
      contains('1:2'),
    );
  });
  test('nested widget block helpers retain guarded local work', () async {
    final uri = await Isolate.resolvePackageUri(
      Uri.parse('package:restage_core/src/widget_catalog/catalog.json'),
    );
    final catalog = decodeCatalog(File.fromUri(uri!).readAsStringSync());
    final expression = await parseExpressionFromSourceForTest(r"""
      import 'package:flutter/widgets.dart';
      Widget helper(double width) {
        var value = 1;
        if (width > 100) { value += 2; return Text('$value'); }
        value += 4;
        return Text('$value');
      }
      Widget x() => LayoutBuilder(builder: (context, c) => SizedBox(child: helper(c.maxWidth)));
    """, rootPackage: 'apps_examples');
    final translated = ExpressionTranslator(
      catalog: catalog,
      helpers: HelperRegistry(),
    ).translate(expression);
    expect(
      translated.issues,
      isEmpty,
      reason: translated.issues.map((issue) => issue.message).join('\n'),
    );
    final root =
        rfw
                .parseLibraryFile(
                  'import restage.core;widget Root=${translated.dsl};',
                )
                .widgets
                .single
                .root
            as rfw.ConstructorCall;
    final envelope =
        (root.arguments['builder']! as rfw.ConstructorCall).arguments;
    final program = BuilderProgram.decode(envelope['program']! as String);
    final wide = program
        .invoke(
          captures: _EmptyReader(),
          parameters: {
            'arg1': {'maxWidth': 200.0},
          },
        )
        .values
        .values;
    expect(wide, contains('3'));
    expect(wide, isNot(contains('5')));
    final narrow = program
        .invoke(
          captures: _EmptyReader(),
          parameters: {
            'arg1': {'maxWidth': 50.0},
          },
        )
        .values
        .values;
    expect(narrow, contains('5'));
    expect(narrow, isNot(contains('3')));
  });
  test(
    'required nullable builder preserves supplied null through parsed RFW',
    () async {
      final expression = await parseExpressionFromSourceForTest("""
import 'package:flutter/widgets.dart';
Widget x()=>Probe(builder:null);
class Probe extends StatelessWidget {
  const Probe({required this.builder});
  final WidgetBuilder? builder;
  Widget build(BuildContext context)=>builder?.call(context) ?? const SizedBox();
}
""", rootPackage: 'apps_examples');
      const property = PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: 'builder',
        type: PropertyType.widgetBuilder,
        description: '',
        required: true,
        constructorNullable: true,
        builderContract: WidgetBuilderContract(
          parameters: [WidgetBuilderParameter.buildContext],
        ),
      );
      final widget = entry(
        name: 'Probe',
        flutterType: 'package:apps_examples/_expr_probe.dart#Probe',
        properties: [property],
      );
      final catalog = catalogWith([widget]);
      final result = ExpressionTranslator(
        catalog: catalog,
        helpers: HelperRegistry(),
      ).translate(expression);
      expect(
        result.issues,
        isEmpty,
        reason: result.issues.map((i) => i.message).join('\n'),
      );
      final library = rfw.parseLibraryFile(
        'import restage.core;widget Root=${result.dsl};',
      );
      final root = library.widgets.single.root as rfw.ConstructorCall;
      expect(root.arguments['builder'], {
        RfwConstructorPresenceProtocol.markerKey: 1,
      });
      expect(deriveSurfaceCapability(library, catalog).builtInFloor, 1);
      expect(
        () => deriveSurfaceCapability(
          rfw.parseLibraryFile('import restage.core;widget Root=Probe();'),
          catalog,
        ),
        throwsFormatException,
      );
      final factory = emitFactoryFunction(
        widget,
      )!.replaceAll(RegExp(r'\s+'), ' ');
      expect(factory, contains('RestageRfwConstructorPresence.read('));
      expect(
        factory,
        contains(
          'RestageBuilderBinding.optional(source, restagePresenceBuilder.valuePath',
        ),
      );
      expect(
        factory,
        contains('if (restagePresenceBuilder.supplied) #builder:'),
      );
      expect(factory, contains('Function.apply(Probe.new,'));
    },
  );

  test('app value builders deliver their body and project their values', () async {
    Future<(Expression, TranslationResult)> translate(
      String body, {
      String value = 'Tally',
    }) async {
      final expression = await parseExpressionFromSourceForTest("""
import 'package:flutter/widgets.dart';
enum Tier { free, pro }
class Tally {
  const Tally(this.count, this.label, this.tier, this.tags, this.accent);
  final int count;
  final String? label;
  final Tier tier;
  final List<String> tags;
  final Color accent;
}
class Ordered { const Ordered(this.name, this.size); final String name; final int size; }
class Swapped { const Swapped(this.size, this.name); final int size; final String name; }
Widget x() => Probe(builder: $body);
class Probe extends StatelessWidget {
  const Probe({required this.builder});
  final Widget Function(BuildContext, $value, Widget?) builder;
  Widget build(BuildContext context) => const SizedBox();
}
""", rootPackage: 'apps_examples');
      final property = PropertyEntry(
        wireId: WireId('p9001'),
        name: 'builder',
        type: PropertyType.widgetBuilder,
        description: '',
        required: true,
        builderContract: const WidgetBuilderContract(
          parameters: [
            WidgetBuilderParameter.buildContext,
            WidgetBuilderParameter.data,
            WidgetBuilderParameter.child,
          ],
        ),
      );
      final uri = await Isolate.resolvePackageUri(
        Uri.parse('package:restage_core/src/widget_catalog/catalog.json'),
      );
      final core = decodeCatalog(File.fromUri(uri!).readAsStringSync());
      // The core catalog with the probe, which needs an allocated identity.
      final catalog = Catalog(
        schemaVersion: core.schemaVersion,
        generatedAt: core.generatedAt,
        libraries: core.libraries,
        structuredTypes: core.structuredTypes,
        unions: core.unions,
        designTokens: core.designTokens,
        exclusions: core.exclusions,
        flutterVersion: core.flutterVersion,
        compatRules: core.compatRules,
        widgets: [
          ...core.widgets,
          WidgetEntry(
            wireId: WireId('w9001'),
            name: 'Probe',
            library: WidgetLibrary.core,
            category: WidgetCategory.layout,
            description: '',
            flutterType: 'package:apps_examples/_expr_probe.dart#Probe',
            childrenSlot: ChildrenSlot.none,
            properties: [property],
          ),
        ],
      );
      return (
        expression,
        ExpressionTranslator(
          catalog: catalog,
          helpers: HelperRegistry(),
        ).translate(expression),
      );
    }

    final (expression, result) = await translate(
      r"(context, t, child) => Text('${t.label ?? 'none'} ${t.count} ${t.tier.name}')",
    );
    expect(
      result.issues,
      isEmpty,
      reason: result.issues.map((i) => i.message).join('\n'),
    );
    final callback =
        ((expression as InstanceCreationExpression)
                        .argumentList
                        .arguments
                        .single
                    as NamedArgument)
                .argumentExpression
            as FunctionExpression;
    final slot = AppValueSlot.of(callback)!;
    const tally = ValueType(
      'record',
      fields: {
        'count': ValueType.integer,
        'label': ValueType('String', nullable: true),
        'tier': ValueType.string,
        'tags': ValueType('list', item: ValueType.string),
        'accent': colorValueType,
      },
    );
    expect(slot.contract.parameters, [
      WidgetBuilderParameter.buildContext,
      WidgetBuilderParameter.data,
      WidgetBuilderParameter.child,
    ]);
    expect(slot.data.map((k, v) => MapEntry(k, v.toJson())), {
      'arg1': tally.toJson(),
    });
    final root =
        rfw
                .parseLibraryFile(
                  'import restage.core;widget Root=${result.dsl};',
                )
                .widgets
                .single
                .root
            as rfw.ConstructorCall;
    final program = BuilderProgram.decode(
      (root.arguments['builder']! as rfw.ConstructorCall).arguments['program']!
          as String,
    );
    validateBuilderProgramContract(program, slot.contract, data: slot.data);
    expect(
      program
          .invoke(
            captures: _EmptyReader(),
            parameters: {
              'arg1': {
                'count': 3,
                'label': null,
                'tier': 'pro',
                'tags': <String>[],
              },
            },
          )
          .values
          .values,
      contains('none 3 pro'),
    );
    expect(
      slot.callback('b'),
      "(_restageArg0, _restageArg1, _restageArg2) => b.build(_restageArg0, "
      "<String, Object?>{'arg1': <String, Object?>{'count': _restageArg1.count, "
      "'label': _restageArg1.label, 'tier': _restageArg1.tier.name, "
      "'tags': <Object?>[for (final _restageItem1 in _restageArg1.tags) "
      "_restageItem1], 'accent': RestageBuilderBinding.color(_restageArg1.accent)}})",
    );
    expect(
      slot.binding('s', 'c', 'builder'),
      contains("data: const <String, ValueType>{'arg1': ValueType('record', "),
    );

    final (counter, _) = await translate(
      r"(context, n, child) => Text('$n')",
      value: 'int',
    );
    final counted = AppValueSlot.of(
      ((counter as InstanceCreationExpression).argumentList.arguments.single
                  as NamedArgument)
              .argumentExpression
          as FunctionExpression,
    )!;
    expect(
      AppValueSlot.owning(
        'P(builder: ${counted.callback(AppValueSlot.bindingName('builder'))})',
        {'builder': counted},
        source: 's',
        context: 'c',
        sdk: 'r.',
      ),
      r"r.RestageBuilderBinding.construct((_restageBindings) { "
      r"final _restageBinding$builder = r.RestageBuilderBinding("
      r"r.RestageValueBinding.dataSource(s, c), const <Object>['builder'], "
      r"contract: const r.WidgetBuilderContract(parameters: "
      r"[r.WidgetBuilderParameter.buildContext, r.WidgetBuilderParameter.data, "
      r"r.WidgetBuilderParameter.child]), data: const <String, r.ValueType>"
      r"{'arg1': r.ValueType('int')}); "
      r"_restageBindings.add(_restageBinding$builder); "
      r"return P(builder: (_restageArg0, _restageArg1, _restageArg2) => "
      r"_restageBinding$builder.build(_restageArg0, "
      r"<String, Object?>{'arg1': _restageArg1})); })",
    );
    expect(counted.signature, isNot(slot.signature));
    // A copied body records into its own recording and returns through
    // the delivered body.
    final counterCallback =
        (counter.argumentList.arguments.single as NamedArgument)
                .argumentExpression
            as FunctionExpression;
    expect(AppValueSlot.parameterNames(counterCallback), [
      'context',
      'n',
      'child',
    ]);
    expect(
      counted.callback(
        'b',
        names: AppValueSlot.parameterNames(counterCallback),
        body: "return _restageRender(Text(n.toString()));",
      ),
      "(context, n, child) { final _restageSlotRecording = "
      "RestageRecording(); _restageRender(Object? _) => b.build(context, "
      "<String, Object?>{'arg1': n}, recorded: "
      "_restageSlotRecording.values); return _restageRender(Text(n.toString())); }",
    );
    BuilderProgram recordedProgram(ValueType type) => BuilderProgram(
      values: ValueProgram(
        nodes: [ValueNode('parameter', type, name: 'recorded:k')],
        root: 0,
        parameters: {'recorded:k': type},
      ),
      result: const BuilderResult.body(0, values: {'v0': 0}),
      bodyCount: 1,
    );
    validateBuilderProgramContract(
      recordedProgram(ValueType.string),
      counted.contract,
      data: counted.data,
    );
    for (final (program, contract) in [
      (
        recordedProgram(ValueType.string),
        const WidgetBuilderContract(
          parameters: [
            WidgetBuilderParameter.buildContext,
            WidgetBuilderParameter.boxConstraints,
          ],
        ),
      ),
      (recordedProgram(colorValueType), counted.contract),
    ]) {
      expect(
        () => validateBuilderProgramContract(program, contract),
        throwsFormatException,
      );
    }

    // Reordering a value's fields keeps the signature.
    Future<String> signatureOf(String value) async {
      final (expression, _) = await translate(
        r"(context, t, child) => Text(t.name)",
        value: value,
      );
      final argument =
          (expression as InstanceCreationExpression)
                  .argumentList
                  .arguments
                  .single
              as NamedArgument;
      return AppValueSlot.of(
        argument.argumentExpression as FunctionExpression,
      )!.signature;
    }

    expect(await signatureOf('Swapped'), await signatureOf('Ordered'));

    // A nested child list reads the value's fields.
    final (_, nested) = await translate(
      r"(context, t, child) => "
      r"Column(children: [Text('${t.count} ${t.tier.name}', "
      r"style: TextStyle(color: t.accent)), Text('y')])",
    );
    expect(
      nested.issues,
      isEmpty,
      reason: nested.issues.map((i) => i.message).join('\n'),
    );

    final (_, passthrough) = await translate(
      '(context, t, child) => child ?? Text(t.label!)',
    );
    expect(passthrough.issues.map((i) => i.message), [
      contains('passes its child through'),
    ]);
  });

  test(
    'nullable builder values emit a parseable false-arm discriminator',
    () async {
      final uri = await Isolate.resolvePackageUri(
        Uri.parse('package:restage_core/src/widget_catalog/catalog.json'),
      );
      final catalog = decodeCatalog(File.fromUri(uri!).readAsStringSync());
      final expression = await parseExpressionFromSourceForTest("""
import 'package:flutter/widgets.dart';
Widget x()=>LayoutBuilder(builder:(context,c)=>SizedBox(width:c.maxWidth>400 ? null : 20.0));
""", rootPackage: 'apps_examples');
      final result = ExpressionTranslator(
        catalog: catalog,
        helpers: HelperRegistry(),
      ).translate(expression);
      expect(
        result.issues,
        isEmpty,
        reason: result.issues.map((i) => i.message).join('\n'),
      );
      final root =
          rfw
                  .parseLibraryFile(
                    'import restage.core;widget Root=${result.dsl};',
                  )
                  .widgets
                  .single
                  .root
              as rfw.ConstructorCall;
      final envelope =
          (root.arguments['builder']! as rfw.ConstructorCall).arguments;
      final body =
          (envelope['bodies']! as List).single as rfw.WidgetBuilderDeclaration;
      final width =
          (body.widget as rfw.ConstructorCall).arguments['width']!
              as rfw.Switch;
      expect(width.outputs.keys, [false]);
      final program = BuilderProgram.decode(envelope['program']! as String);
      expect(
        program
            .invoke(
              captures: _EmptyReader(),
              parameters: {
                'arg1': {'maxWidth': 500.0},
              },
            )
            .values
            .values
            .single,
        isNull,
      );
      expect(
        program
            .invoke(
              captures: _EmptyReader(),
              parameters: {
                'arg1': {'maxWidth': 300.0},
              },
            )
            .values
            .values
            .single,
        20.0,
      );
    },
  );

  test(
    'enum interpolation preserves native spelling and rejects custom conversion',
    () async {
      final uri = await Isolate.resolvePackageUri(
        Uri.parse('package:restage_core/src/widget_catalog/catalog.json'),
      );
      final catalog = decodeCatalog(File.fromUri(uri!).readAsStringSync());
      final expression = await parseExpressionFromSourceForTest(r"""
import 'package:flutter/widgets.dart';
Widget x()=>OrientationBuilder(builder:(context,o)=>Text('$o|${o.name}|${o.toString()}'));
""", rootPackage: 'apps_examples');
      final translated = ExpressionTranslator(
        catalog: catalog,
        helpers: HelperRegistry(),
      ).translate(expression);
      expect(
        translated.issues,
        isEmpty,
        reason: translated.issues.map((i) => i.message).join('\n'),
      );
      final root =
          rfw
                  .parseLibraryFile(
                    'import restage.core;widget Root=${translated.dsl};',
                  )
                  .widgets
                  .single
                  .root
              as rfw.ConstructorCall;
      final envelope =
          (root.arguments['builder']! as rfw.ConstructorCall).arguments;
      final program = BuilderProgram.decode(envelope['program']! as String);
      expect(
        program
            .invoke(captures: _EmptyReader(), parameters: {'arg1': 'landscape'})
            .values
            .values
            .single,
        'Orientation.landscape|landscape|Orientation.landscape',
      );

      final nullable = await parseExpressionFromSourceForTest(r"""
enum Choice { first }
String x(Choice? value)=>'$value|${value?.name}|${value.toString()}';
""");
      final lowering = BuilderExpressionLowering(capture: (e) => e.toSource());
      final values = lowering.program(lowering.lower(nullable));
      for (final value in [null, 'first']) {
        expect(
          ValueEvaluator(
            values,
            captures: _MapReader({
              for (final key in lowering.captureDsl.keys) key: value,
            }),
            parameters: {},
          ).evaluate(),
          value == null ? 'null|null|null' : 'Choice.first|first|Choice.first',
        );
      }

      final mixed = await parseExpressionFromSourceForTest(r"""
enum First { item }
enum Second { item }
String x()=> '${First.item == Second.item}';
""");
      expect(
        () => BuilderExpressionLowering(
          capture: (e) => e.toSource(),
        ).lower(mixed),
        throwsA(
          isA<BuilderLoweringException>().having(
            (e) => e.reason,
            'reason',
            contains('matching declared enum identities'),
          ),
        ),
      );
      final custom = await parseExpressionFromSourceForTest(r"""
enum Choice { first; @override String toString()=>'custom'; }
String x()=> '${Choice.first}';
""");
      expect(
        () => BuilderExpressionLowering(
          capture: (e) => e.toSource(),
        ).lower(custom),
        throwsA(
          isA<BuilderLoweringException>().having(
            (e) => e.reason,
            'reason',
            contains('custom toString'),
          ),
        ),
      );
      final customName = await parseExpressionFromSourceForTest(r"""
enum Choice { first; @override String toString()=>'custom'; }
String x()=> '${Choice.first.name}';
""");
      final names = BuilderExpressionLowering(capture: (e) => e.toSource());
      expect(
        ValueEvaluator(
          names.program(names.lower(customName)),
          captures: _EmptyReader(),
          parameters: {},
        ).evaluate(),
        'first',
      );
    },
  );

  test(
    'nested contexts and aliases retain lexical depth through collections',
    () async {
      final uri = await Isolate.resolvePackageUri(
        Uri.parse('package:restage_core/src/widget_catalog/catalog.json'),
      );
      final catalog = decodeCatalog(File.fromUri(uri!).readAsStringSync());
      final expression = await parseExpressionFromSourceForTest("""
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
Widget x()=>LayoutBuilder(builder:(outer,c) {
  final alias=outer;
  return LayoutBuilder(builder:(inner,box)=>Column(children:[
    if(box.maxWidth>400) Text(read(alias)),
    Text(Theme.of(inner).brightness.name),
    Text(defaultTargetPlatform.name),
  ]));
});
String read(BuildContext context)=>Theme.of(context).brightness.name;
""", rootPackage: 'apps_examples');
      final result = ExpressionTranslator(
        catalog: catalog,
        helpers: HelperRegistry(),
      ).translate(expression);
      expect(
        result.issues,
        isEmpty,
        reason: result.issues.map((i) => i.message).join('\n'),
      );
      final root = rfw
          .parseLibraryFile('import restage.core;widget root=${result.dsl};')
          .widgets
          .single
          .root;
      final programs = <BuilderProgram>[];
      void visit(Object? value) {
        if (value is rfw.ConstructorCall) {
          if (value.name == kBuilderContinuationWidgetName)
            programs.add(
              BuilderProgram.decode(value.arguments['program']! as String),
            );
          visit(value.arguments);
        } else if (value is Map) {
          for (final child in value.values) {
            visit(child);
          }
        } else if (value is List) {
          for (final child in value) {
            visit(child);
          }
        } else if (value is rfw.WidgetBuilderDeclaration) {
          visit(value.widget);
        }
      }

      visit(root);
      expect(programs, hasLength(3));
      expect(
        programs[0].values.parameters.keys,
        isNot(contains('context:theme:brightness')),
      );
      expect(
        programs[1].values.parameters.keys,
        isNot(contains('context:ancestor:1:theme:brightness')),
      );
      expect(
        programs[2].values.parameters.keys,
        containsAll([
          'context:ancestor:1:theme:brightness',
          'context:theme:brightness',
          'context:device:defaultTargetPlatform',
        ]),
      );
    },
  );

  test(
    'nested callback captures helper aggregate arguments as inert values',
    () async {
      final uri = await Isolate.resolvePackageUri(
        Uri.parse('package:restage_core/src/widget_catalog/catalog.json'),
      );
      final catalog = decodeCatalog(File.fromUri(uri!).readAsStringSync());
      final expression = await parseExpressionFromSourceForTest('''
import 'package:flutter/widgets.dart';
Widget x()=>LayoutBuilder(builder:(context,c)=>nested(['a','b']));
Widget nested(List<String> labels)=>LayoutBuilder(builder:(context,c)=>Text(labels[0]));
''', rootPackage: 'apps_examples');
      final result = ExpressionTranslator(
        catalog: catalog,
        helpers: HelperRegistry(),
      ).translate(expression);
      expect(
        result.issues,
        isEmpty,
        reason: result.issues.map((i) => i.message).join('\n'),
      );
      expect(result.dsl, contains(kBuilderContinuationWidgetName));
    },
  );

  test(
    'source ValueKey generic identity and explicit null presence survive collections',
    () async {
      final uri = await Isolate.resolvePackageUri(
        Uri.parse('package:restage_core/src/widget_catalog/catalog.json'),
      );
      final catalog = decodeCatalog(File.fromUri(uri!).readAsStringSync());
      final expression = await parseExpressionFromSourceForTest('''
import 'package:flutter/widgets.dart';
Widget x()=>LayoutBuilder(builder:(context,c)=>Column(children:[
  SizedBox(key:ValueKey<int>(1)), SizedBox(key:ValueKey<double>(1)),
  SizedBox(key:ValueKey<num>(1)), SizedBox(key:ValueKey<Object>(1)),
  SizedBox(key:ValueKey<String?>(null)), SizedBox(key:ValueKey(null)), SizedBox(key:null),
]));
''', rootPackage: 'apps_examples');
      final translated = ExpressionTranslator(
        catalog: catalog,
        helpers: HelperRegistry(),
      ).translate(expression);
      expect(
        translated.issues,
        isEmpty,
        reason: translated.issues.map((i) => i.message).join('\n'),
      );
      final root =
          rfw
                  .parseLibraryFile(
                    'import restage.core;widget root=${translated.dsl};',
                  )
                  .widgets
                  .single
                  .root
              as rfw.ConstructorCall;
      final slot =
          (root.arguments['builder']! as rfw.ConstructorCall).arguments;
      final column =
          (slot['bodies']! as List).single as rfw.WidgetBuilderDeclaration;
      final children =
          ((column.widget as rfw.ConstructorCall).arguments['children']!
                  as rfw.ConstructorCall)
              .arguments;
      final program = BuilderProgram.decode(children['program']! as String);
      final items = program.invokeAll(captures: _EmptyReader(), parameters: {});
      expect(items.map((item) => item.keyType), [
        'int',
        'double',
        'num',
        'Object',
        'String?',
        'Null',
        'Object',
      ]);
      expect(items.take(6).every((item) => item.hasKey), isTrue);
      expect(items.last.hasKey, isFalse);
      expect(items[5].projectedKey, isNull);
      expect(items[1].projectedKey, isA<double>());
    },
  );

  test('nullable member and index reads preserve coalescing demand', () async {
    final expression = await parseExpressionFromSourceForTest(
      "class Row { final String title; const Row(this.title); } String x(Row? row,List<String>? labels)=>row?.title ?? labels?[0] ?? 'none';",
    );
    final lowering = BuilderExpressionLowering(capture: (e) => e.toSource());
    final program = lowering.program(lowering.lower(expression));
    Object? evaluate(Object? row, Object? labels) => ValueEvaluator(
      program,
      captures: _MapReader({
        for (final capture in lowering.captureDsl.entries)
          capture.key: capture.value == 'row' ? row : labels,
      }),
      parameters: {},
    ).evaluate();
    expect(evaluate(null, null), 'none');
    expect(evaluate({'title': 'first'}, []), 'first');
    expect(evaluate(null, ['fallback']), 'fallback');
    expect(() => evaluate(null, []), throwsRangeError);
  });

  test(
    'callback theme colors and tokens use the local native context',
    () async {
      final uri = await Isolate.resolvePackageUri(
        Uri.parse('package:restage_core/src/widget_catalog/catalog.json'),
      );
      final catalog = decodeCatalog(File.fromUri(uri!).readAsStringSync());
      final expression = await parseExpressionFromSourceForTest('''
import 'package:flutter/material.dart';
Widget x()=>LayoutBuilder(builder:(context,c)=>ColoredBox(
  color:c.maxWidth>400 ? Theme.of(context).colorScheme.primary : Colors.red,
  child:SizedBox(width:c.constrainWidth(10),child:Text(Theme.of(context).brightness==Brightness.dark ? 'd'+'ark' : 'light')),
));
''', rootPackage: 'apps_examples');
      final translated = ExpressionTranslator(
        catalog: catalog,
        helpers: HelperRegistry(),
      ).translate(expression);
      expect(
        translated.issues,
        isEmpty,
        reason: translated.issues.map((i) => i.message).join('\n'),
      );
      expect(translated.dsl, isNot(contains('data.theme')));
      final root =
          rfw
                  .parseLibraryFile(
                    'import restage.core;widget root=${translated.dsl};',
                  )
                  .widgets
                  .single
                  .root
              as rfw.ConstructorCall;
      final slot =
          (root.arguments['builder']! as rfw.ConstructorCall).arguments;
      final program = BuilderProgram.decode(slot['program']! as String);
      for (final width in [320.0, 500.0]) {
        final frame = program.invoke(
          captures: _EmptyReader(),
          parameters: {
            'arg1': {'minWidth': 20.0, 'maxWidth': width},
            'context:theme:colorScheme.primary': argbColorValue(0xff123456),
            'context:theme:brightness': 'dark',
          },
        );
        expect(
          frame.values.values,
          containsAll([
            ...(width > 400
                    ? argbColorValue(0xff123456)
                    : {...argbColorValue(0xfff44336), 'material': 'red'})
                .values,
            20.0,
            'dark',
          ]),
        );
      }
    },
  );

  test(
    'widget helpers preserve eager arguments, lazy arms and projected root keys',
    () async {
      final uri = await Isolate.resolvePackageUri(
        Uri.parse('package:restage_core/src/widget_catalog/catalog.json'),
      );
      final catalog = decodeCatalog(File.fromUri(uri!).readAsStringSync());
      for (final root in [
        'card(true,12 ~/ c.maxWidth.toInt())',
        "SizedBox(child:c.maxWidth > 0 ? card(true,12 ~/ c.maxWidth.toInt()) : Text('off'))",
      ]) {
        final expression = await parseExpressionFromSourceForTest("""
import 'package:flutter/widgets.dart';
Widget x()=>LayoutBuilder(builder:(context,c)=>$root);
Widget card(bool first,int other)=>SizedBox(${root.startsWith('card') ? "key:ValueKey('selected')," : ''} width:first ? 80.0 : other.toDouble());
""", rootPackage: 'apps_examples');
        final translated = ExpressionTranslator(
          catalog: catalog,
          helpers: HelperRegistry(),
        ).translate(expression);
        expect(
          translated.issues,
          isEmpty,
          reason: translated.issues.map((i) => i.message).join('\n'),
        );
        final rootCall =
            rfw
                    .parseLibraryFile(
                      'import restage.core;widget root=${translated.dsl};',
                    )
                    .widgets
                    .single
                    .root
                as rfw.ConstructorCall;
        final slot =
            (rootCall.arguments['builder']! as rfw.ConstructorCall).arguments;
        final program = BuilderProgram.decode(slot['program']! as String);
        BuilderInvocation invoke(double width) => program.invoke(
          captures: _EmptyReader(),
          parameters: {
            'arg1': {'maxWidth': width},
          },
        );
        if (root.startsWith('card')) {
          expect(invoke(2).projectedKey, 'selected');
          expect(
            () => invoke(0),
            throwsA(isA<IntegerDivisionByZeroException>()),
          );
        } else {
          expect(() => invoke(0), returnsNormally);
          expect(invoke(2).values.values, contains(80.0));
        }
      }
    },
  );

  test(
    'callback app effects and recursion refuse with source locations',
    () async {
      final uri = await Isolate.resolvePackageUri(
        Uri.parse('package:restage_core/src/widget_catalog/catalog.json'),
      );
      final catalog = decodeCatalog(File.fromUri(uri!).readAsStringSync());
      for (final body in [
        "{ print('side effect'); return Text('x'); }",
        "=>again(1)",
      ]) {
        final expression = await parseExpressionFromSourceForTest("""
import 'package:flutter/widgets.dart';
Widget x()=>LayoutBuilder(builder:(context,c)$body);
Widget again(int n)=>again(n);
""", rootPackage: 'apps_examples');
        final result = ExpressionTranslator(
          catalog: catalog,
          helpers: HelperRegistry(),
        ).translate(expression);
        expect(result.issues, isNotEmpty);
        expect(
          result.issues.every((issue) => issue.location.isNotEmpty),
          isTrue,
        );
      }
    },
  );

  test(
    'pure helper arguments and unused locals retain eager evaluation',
    () async {
      for (final source in [
        'int x()=>pick(true,12 ~/ 0); int pick(bool first,int other)=>first ? 1 : other;',
        'int x()=>pick(); int pick(){final unused=12 ~/ 0;return 1;}',
      ]) {
        final expression = await parseExpressionFromSourceForTest(source);
        final helpers = inlinableHelperDefinitionsIn(expression);
        late BuilderExpressionLowering lowering;
        lowering = BuilderExpressionLowering(
          capture: (e) => throw StateError(e.toSource()),
          extension: (e, lowering) {
            if (e is MethodInvocation) {
              final helper =
                  helpers[e.methodName.element] ??
                  pureBuilderHelperFor(e, e.methodName.element);
              if (helper != null) return lowering.lowerHelper(helper, e);
            }
            return null;
          },
        );
        final root = lowering.lower(expression);
        expect(
          () => ValueEvaluator(
            lowering.program(root),
            captures: _EmptyReader(),
            parameters: {},
          ).evaluate(),
          throwsA(isA<IntegerDivisionByZeroException>()),
        );
      }
    },
  );

  test(
    'production translator emits native responsive callbacks and nested scopes',
    () async {
      final uri = await Isolate.resolvePackageUri(
        Uri.parse('package:restage_core/src/widget_catalog/catalog.json'),
      );
      final catalog = decodeCatalog(File.fromUri(uri!).readAsStringSync());
      final source = await parseExpressionFromSourceForTest("""
import 'package:flutter/widgets.dart';
Widget x() => LayoutBuilder(builder: (context, outer) => SizedBox(
  width: outer.maxWidth / 2,
  child: LayoutBuilder(builder: (context, c) => SizedBox(width:outer.constrainWidth(c.maxWidth),child:Text(c.maxWidth < outer.maxWidth ? 'inner' : 'outer'))),
));
""", rootPackage: 'apps_examples');
      final result = ExpressionTranslator(
        catalog: catalog,
        helpers: HelperRegistry(),
      ).translate(source);
      expect(
        result.issues,
        isEmpty,
        reason: result.issues.map((i) => i.message).join('\n'),
      );
      expect(result.dsl, contains('LayoutBuilder('));
      final library = rfw.parseLibraryFile(
        'import restage.core; widget root = ${result.dsl};',
      );
      expect(library.widgets, isNotEmpty);
    },
  );

  test(
    'production collection plans keep dead arms lazy and nested loops scoped',
    () async {
      final uri = await Isolate.resolvePackageUri(
        Uri.parse('package:restage_core/src/widget_catalog/catalog.json'),
      );
      final catalog = decodeCatalog(File.fromUri(uri!).readAsStringSync());
      final expression = await parseExpressionFromSourceForTest(r'''
import 'package:flutter/widgets.dart';
class Item { final String title; const Item(this.title); }
Widget x() => LayoutBuilder(builder: (context, c) {
  final items = <Item>[];
  final labels = ['a', 'b'];
  return Column(children: [
    if (c.maxWidth > 400) ...[
      Text(items[c.maxWidth.toInt()].title),
      for (final label in labels) Text('$label:${12 ~/ 0}'),
    ] else Text('small'),
    for (final n in [1,2]) if (n.isEven) Text('$n'),
  ]);
});
''', rootPackage: 'apps_examples');
      final translator = ExpressionTranslator(
        catalog: catalog,
        helpers: HelperRegistry(),
      );
      final result = translator.translate(expression);
      expect(
        result.issues,
        isEmpty,
        reason: result.issues.map((i) => i.message).join('\n'),
      );
      expect(translator.translate(expression).dsl, result.dsl);
      final root =
          rfw
                  .parseLibraryFile(
                    'import restage.core; widget root=${result.dsl};',
                  )
                  .widgets
                  .single
                  .root
              as rfw.ConstructorCall;
      final slot =
          (root.arguments['builder']! as rfw.ConstructorCall).arguments;
      final program = BuilderProgram.decode(slot['program']! as String);
      final frame = program.invoke(
        captures: _EmptyReader(),
        parameters: {
          'arg1': {'maxWidth': 320.0},
        },
      );
      final column =
          (slot['bodies']! as List).single as rfw.WidgetBuilderDeclaration;
      final children =
          ((column.widget as rfw.ConstructorCall).arguments['children']!
                  as rfw.ConstructorCall)
              .arguments;
      final lexicalContext = ValueOperationContext(
        frame: frame.frame,
        locals: frame.frame!.visibleTypes,
      );
      final collection = BuilderProgram.decode(
        children['program']! as String,
        context: lexicalContext,
      );
      final captureValues = <String, Object?>{};
      for (final entry in (children['captures']! as Map).entries) {
        final reference = entry.value as rfw.WidgetBuilderArgReference;
        captureValues[entry.key as String] = frame.values[reference.parts.last];
      }
      final items = collection.invokeAll(
        captures: _MapReader(captureValues),
        parameters: {},
        context: lexicalContext,
      );
      expect(items.map((item) => item.values.values.single).toList(), [
        'small',
        '2',
      ]);
    },
  );

  test('resolved helper callback preserves immutable local values', () async {
    final uri = await Isolate.resolvePackageUri(
      Uri.parse('package:restage_core/src/widget_catalog/catalog.json'),
    );
    final catalog = decodeCatalog(File.fromUri(uri!).readAsStringSync());
    final expression = await parseExpressionFromSourceForTest('''
import 'package:flutter/widgets.dart';
Widget x()=>LayoutBuilder(builder:layout);
Widget layout(BuildContext context, BoxConstraints c) {
  if (!c.hasBoundedWidth) return SizedBox(width:80.0);
  final width=c.maxWidth/2;
  return SizedBox(width:width);
}
''', rootPackage: 'apps_examples');
    final result = ExpressionTranslator(
      catalog: catalog,
      helpers: HelperRegistry(),
    ).translate(expression);
    expect(
      result.issues,
      isEmpty,
      reason: result.issues.map((i) => i.message).join('\n'),
    );
    expect(result.dsl, contains(kBuilderContinuationWidgetName));
    final root =
        rfw
                .parseLibraryFile(
                  'import restage.core;widget root=${result.dsl};',
                )
                .widgets
                .single
                .root
            as rfw.ConstructorCall;
    final slot = (root.arguments['builder']! as rfw.ConstructorCall).arguments;
    final program = BuilderProgram.decode(slot['program']! as String);
    expect(
      program
          .invoke(
            captures: _EmptyReader(),
            parameters: {
              'arg1': {'maxWidth': 320.0, 'hasBoundedWidth': true},
            },
          )
          .values
          .values,
      contains(160.0),
    );
    expect(
      program
          .invoke(
            captures: _EmptyReader(),
            parameters: {
              'arg1': {'maxWidth': double.infinity, 'hasBoundedWidth': false},
            },
          )
          .values
          .values,
      contains(80.0),
    );
  });

  test(
    'ordinary block closure retains local constraints arithmetic and lazy branches',
    () async {
      final expression = await parseExpressionFromSourceForTest('''
import 'package:flutter/widgets.dart';
Widget x() => LayoutBuilder(builder: (context, c) {
  final width = c.hasBoundedWidth ? c.maxWidth / 2 : 80.0;
  return SizedBox(width: width, child: Text(width >= 200 ? 'wide' : 'narrow'));
});
''', rootPackage: 'apps_examples');
      final callback =
          ((expression as InstanceCreationExpression)
                          .argumentList
                          .arguments
                          .single
                      as NamedArgument)
                  .argumentExpression
              as FunctionExpression;
      late WidgetBuilderLowering lowering;
      lowering = WidgetBuilderLowering(
        expressions: BuilderExpressionLowering(
          capture: (e) =>
              throw StateError('Unexpected capture ${e.toSource()}'),
        ),
        contract: const WidgetBuilderContract(
          parameters: [
            WidgetBuilderParameter.buildContext,
            WidgetBuilderParameter.boxConstraints,
          ],
        ),
        scope: 'scope',
        translateBody: (body) {
          final box = body as InstanceCreationExpression;
          final width = box.argumentList.arguments.first.argumentExpression;
          final text =
              (box.argumentList.arguments.last.argumentExpression
                      as InstanceCreationExpression)
                  .argumentList
                  .arguments
                  .first
                  .argumentExpression;
          return 'SizedBox(width: ${lowering.value(width, asDouble: true)}, child: Text(text: ${lowering.value(text)}))';
        },
      );
      final dsl = lowering.lower(callback);
      final library = rfw.parseLibraryFile(
        'import core; widget root = Probe(builder: $dsl);',
      );
      final slot =
          ((library.widgets.single.root as rfw.ConstructorCall)
                      .arguments['builder']!
                  as rfw.ConstructorCall)
              .arguments;
      final program = BuilderProgram.decode(slot['program']! as String);
      for (final (width, expected, label) in [
        (320.0, 160.0, 'narrow'),
        (500.0, 250.0, 'wide'),
        (double.infinity, 80.0, 'narrow'),
      ]) {
        final result = program.invoke(
          captures: _EmptyReader(),
          parameters: {
            'arg1': {'hasBoundedWidth': width.isFinite, 'maxWidth': width},
          },
        );
        expect(result.values, {'v0': expected, 'v1': label});
      }
    },
  );
}
