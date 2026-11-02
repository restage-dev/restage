import 'dart:io';

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/host_data_shape.dart';
import 'package:restage_codegen/src/intl_format_recognition.dart';
import 'package:restage_codegen/src/surface_publication/host_data_contract.dart';
import 'package:restage_codegen/src/surface_publication/screen_contract_reference_emitter.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;
import 'package:test/test.dart';

import 'helpers.dart';
import 'support/intl_format_authoring.dart';

void main() {
  test(
    'native Intl graph fixture matches its original authored cases',
    () async {
      expect(
        File(
          '../restage_core/test/fixtures/intl_authoring_programs.json',
        ).readAsStringSync(),
        await compileIntlProgramsFixture(),
      );
    },
  );
  test('native translated plural calls install deferred call adapters', () async {
    for (final expression in [
      "i.Intl.plural(count, one: 'one', other: 'items', name: 'items', args: [count])",
    ]) {
      final result = await translateFormatting(
        'LayoutBuilder(builder: (context, constraints) { '
        'final label = $expression; return Text(label); })',
      );
      expect(result.issues.where((i) => !i.code.isBuildNotice), isEmpty);
      expect(result.hoisted, isNotEmpty);
      expect(
        result.hoisted
            .singleWhere((value) => value.nativeCall != null)
            .nativeCall!
            .source,
        contains('i.'),
      );
    }
  });

  test(
    'DateTime host shape retains exact native epoch and UTC identity',
    () async {
      final probe = await parseMethodExpressionFromSourceForTest(
        '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';
class Probe extends StatelessWidget {
  final List<DateTime> dates;
  const Probe({required this.dates});
  Widget build(BuildContext context) => const SizedBox();
}
''',
        className: 'Probe',
        methodName: 'build',
        rootPackage: 'apps_examples',
      );
      final type = probe
          .classes['Probe']!
          .unnamedConstructor!
          .formalParameters
          .single
          .type;
      final fact = deriveHostDataShape(type, root: 'dates');
      expect(fact.problem, isNull);
      expect(fact.shape, isA<HostDataListShape>());
      expect(
        (fact.shape! as HostDataListShape).elementShape,
        isA<HostDataDateTimeShape>(),
      );
      expect(fact.shape!.requiresEncoding, isTrue);
      expect(hostDataContractShapeOf(fact.shape!).toJson(), {
        'kind': 'list',
        'items': {
          'kind': 'object',
          'fields': {
            'microsecondsSinceEpoch': {'kind': 'int'},
            'isUtc': {'kind': 'bool'},
          },
        },
      });
      final parameter =
          probe.classes['Probe']!.unnamedConstructor!.formalParameters.single;
      final output = emitPaywallMount(
        ResolvedWidgetMountInput(
          assetId: AssetId('restage_codegen', 'lib/_expr_probe.dart'),
          screen: probe.classes['Probe']!,
          rootParams: [
            RootContextParam(
              name: 'dates',
              type: type,
              typeCode: type.getDisplayString(),
              kind: RootContextParamKind.named,
              hostDataShape: fact.shape,
              field: (parameter as FieldFormalParameterElement).field,
              isRequired: true,
              defaultValueCode: null,
              hasNullDefault: false,
            ),
          ],
        ),
        id: 'date_values',
      );
      expect(output.source, isNotNull, reason: output.omissionMessage);
      expect(output.source, contains('.microsecondsSinceEpoch'));
      expect(output.source, contains('.isUtc'));
      expect(output.source, contains('for (final restageValue0 in '));
    },
  );
  test(
    'date chains lower through the common value route with all Text properties',
    () async {
      final result = await translateFormatting(
        'Text(i.DateFormat.yMMMd(locale).add_Hm().format(start), textAlign: TextAlign.end, maxLines: 2)',
        hoist: false,
      );
      expect(result.issues.where((i) => !i.code.isBuildNotice), isEmpty);
      expect(result.hoisted, isEmpty);
      expect(result.dsl, contains('intl.date.new'));
      expect(result.dsl, contains('intl.date.add'));
      expect(result.dsl, contains('intl.date.format'));
      expect(result.dsl, contains('data.context.start'));
      expect(result.dsl, contains('maxLines: 2'));
    },
  );

  test(
    'native local builder values format at callback delivery time',
    () async {
      final result = await translateFormatting(r"""
      LayoutBuilder(builder: (context, constraints) {
        final localCount = constraints.maxWidth.floor();
        return Text(i.Intl.plural(localCount,
          one: 'One item', other: '$localCount items', locale: locale));
      })
    """, hoist: false);
      expect(result.issues.where((i) => !i.code.isBuildNotice), isEmpty);
      expect(result.hoisted, isEmpty);
      expect(result.dsl, contains('intl.plural'));
      expect(result.dsl, contains('arg1'));
      expect(result.dsl, contains('floor'));
    },
  );

  test(
    'nested interpolation and custom String slots use the same value program',
    () async {
      final result = await translateFormatting(r"""
      Column(children: [
        Text('Starts ${i.DateFormat.yMMMd(locale).format(start)} ($count)'),
        Semantics(label: 'Price ${i.NumberFormat.compact(locale: locale).format(count)}',
          child: Text(i.Intl.gender('unknown', other:
            i.Intl.select('active', {'active': 'Ready', 'other': 'Waiting'})))),
      ])
    """, hoist: false);
      expect(result.issues.where((i) => !i.code.isBuildNotice), isEmpty);
      expect(result.dsl, contains('intl.date.format'));
      expect(result.dsl, contains('intl.number.format'));
      expect(result.dsl, contains('intl.gender'));
      expect(result.dsl, contains('intl.select'));
      expect(result.dsl, contains('concat'));
    },
  );

  test(
    'DateTime recipes and ordered formatter cascades remain native operations',
    () async {
      final result = await translateFormatting("""
      Text((i.DateFormat.yMd(locale)..useNativeDigits = false..add_Hms())
        .format(DateTime.utc(2024, 2, 30, 17, 23, 41, 123, 456).toLocal()))
    """, hoist: false);
      expect(result.issues.where((i) => !i.code.isBuildNotice), isEmpty);
      expect(result.dsl, contains('intl.date.digits'));
      expect(result.dsl, contains('intl.datetime.new'));
      expect(result.dsl, contains('intl.datetime.zone'));
    },
  );

  test(
    'DateTime.parse static calls classify and lower inside native callbacks',
    () async {
      const source = '2024-02-29T12:00:00.123456+05:30';
      final expression = await parseExpressionFromSourceForTest(
        "Object x() => DateTime.parse('$source');",
      );
      expect(isIntlValueExpression(expression), isTrue);
      final result = await translateFormatting("""
      LayoutBuilder(builder: (context, constraints) => Text(
        i.DateFormat.yMd('en_US').format(DateTime.parse('$source'))))
    """, hoist: false);
      expect(result.issues.where((i) => !i.code.isBuildNotice), isEmpty);
      expect(result.hoisted, isEmpty);
      final root =
          rfw
                  .parseLibraryFile(
                    'import restage.core;widget root=${result.dsl};',
                  )
                  .widgets
                  .single
                  .root
              as rfw.ConstructorCall;
      final slot =
          (root.arguments['builder']! as rfw.ConstructorCall).arguments;
      final program = BuilderProgram.decode(
        slot['program']! as String,
        operations: kIntlValueOperations,
      );
      final nodes = program.values.nodes;
      final parseIndex = nodes.indexWhere((n) => n.op == 'intl.datetime.new');
      expect(parseIndex, greaterThanOrEqualTo(0));
      final parse = nodes[parseIndex];
      expect(parse.value, {'constructor': 'parse', 'arguments': <String>[]});
      expect(nodes[parse.inputs.single].value, source);
      final format = nodes.singleWhere((n) => n.op == 'intl.date.format');
      expect(nodes[format.inputs.first].op, 'intl.date.new');
      expect(format.inputs.first, lessThan(parseIndex));
      expect(format.inputs.last, parseIndex);
    },
  );

  test('named translation options refuse without a native binding', () async {
    final result = await translateFormatting(
      'LayoutBuilder(builder: (context, constraints) { '
      "final label = i.Intl.plural(count, other: 'items', name: 'items', args: [count]); "
      'return Text(label); })',
      hoist: false,
    );
    expect(
      result.issues.map((i) => i.message).join(),
      contains('installed source declaration'),
    );
    expect(result.dsl, isNot(contains('intl.plural')));
  });

  test(
    'resolved formatter lookalikes never become native intl recipes',
    () async {
      final result = await translateFormatting(
        'Text(DateFormat().format(start))',
        extraSource:
            "class DateFormat { String format(DateTime value) => 'custom'; }",
      );
      expect(result.issues.where((i) => !i.code.isBuildNotice), isEmpty);
      expect(result.hoisted, isNotEmpty);
      expect(result.dsl, isNot(contains('intl.date')));
    },
  );
  test('remaining NumberFormat families and ordered cascades lower natively', () async {
    final constructors = [
      "i.NumberFormat('#,##0.000', locale)",
      'i.NumberFormat.decimalPattern(locale)',
      'i.NumberFormat.decimalPatternDigits(locale: locale, decimalDigits: 3)',
      'i.NumberFormat.percentPattern(locale)',
      'i.NumberFormat.decimalPercentPattern(locale: locale, decimalDigits: 1)',
      'i.NumberFormat.scientificPattern(locale)',
      "i.NumberFormat.currencyPattern(locale, 'EUR')",
      "i.NumberFormat.currency(locale: locale, name: 'EUR', symbol: 'EU', decimalDigits: 3, customPattern: '¤ #,##0.000')",
      "i.NumberFormat.simpleCurrency(locale: locale, name: 'EUR', decimalDigits: 2)",
      'i.NumberFormat.compact(locale: locale, explicitSign: true)',
      'i.NumberFormat.compactLong(locale: locale, explicitSign: true)',
      "i.NumberFormat.compactCurrency(locale: locale, name: 'EUR', symbol: 'EU', decimalDigits: 2)",
      "i.NumberFormat.compactSimpleCurrency(locale: locale, name: 'EUR', decimalDigits: 2)",
      '(i.NumberFormat.decimalPattern(locale)..minimumFractionDigits = 4..maximumFractionDigits = 2..turnOffGrouping())',
    ];
    final result = await translateFormatting(
      'Column(children: [${constructors.map((c) => 'Text($c.format(count))').join(',')}])',
      hoist: false,
    );
    expect(result.issues.where((i) => !i.code.isBuildNotice), isEmpty);
    expect(
      RegExp('intl.number.format').allMatches(result.dsl),
      hasLength(constructors.length),
    );
    expect(result.dsl, contains('intl.number.set'));
    expect(result.dsl, contains('intl.number.noGrouping'));
  });

  test('select preserves scalar and exact enum case identity', () async {
    final result = await translateFormatting(
      """
      Text(i.Intl.select(Status.active, {
        Status.active: 'exact', 'active': 'short', 'other': 'fallback',
      }))
    """,
      hoist: false,
      extraSource: 'enum Status { active }',
    );
    expect(result.issues.where((i) => !i.code.isBuildNotice), isEmpty);
    expect(result.dsl, contains('choiceEnum'));
    expect(result.dsl, contains('#Status'));
  });
  test(
    'immutable formatter aliases are values but later alias mutation refuses',
    () async {
      final supported = await translateFormatting("""
      LayoutBuilder(builder: (context, constraints) {
        final formatter = i.DateFormat.yMMMd(locale).add_Hm();
        return Text(formatter.format(start));
      })
    """, hoist: false);
      expect(supported.issues.where((i) => !i.code.isBuildNotice), isEmpty);
      expect(supported.dsl, contains('intl.date.format'));
      final refused = await translateFormatting("""
      LayoutBuilder(builder: (context, constraints) {
        final formatter = i.DateFormat.yMMMd(locale);
        return Text((formatter..useNativeDigits = false).format(start));
      })
    """, hoist: false);
      expect(
        refused.issues.map((i) => i.message).join(),
        contains('nonescaping constructor'),
      );
    },
  );
  test('custom enum string conversion is preserved through refusal', () async {
    final result = await translateFormatting(
      """
      Text(i.Intl.select(Status.active, {'active': 'short', 'other': 'fallback'}))
    """,
      hoist: false,
      extraSource:
          "enum Status { active; @override String toString() => 'other'; }",
    );
    expect(
      result.issues.map((i) => i.message).join(),
      contains('custom toString'),
    );
    expect(result.dsl, isNot(contains('intl.select')));
  });
  test(
    'formatting helper calls retain eager native argument evaluation',
    () async {
      final result = await translateFormatting(
        """
      Text(i.Intl.plural(count, other: pick(true, 'ok',
        i.DateFormat.yMd('unknown_locale').format(start))))
    """,
        hoist: false,
        indexHelpers: true,
        extraSource:
            'String pick(bool condition, String left, String right) => condition ? left : right;',
      );
      expect(result.issues.where((i) => !i.code.isBuildNotice), isEmpty);
      expect(result.dsl, contains('intl.date.format'));
      expect(result.dsl, contains('let'));
    },
  );
  test(
    'widget helper argument formatting requires its native eager boundary',
    () async {
      final result = await translateFormatting(
        'tile(i.DateFormat.yMd(locale).format(start))',
        hoist: false,
        indexHelpers: true,
        extraSource: 'Widget tile(String title) => Text(title);',
      );
      expect(
        result.issues.map((i) => i.message).join(),
        contains('installed native widget binding'),
      );
      expect(result.dsl, isNot(contains('intl.date.format')));
    },
  );
  test(
    'formatting in callback collection bodies keeps the installed operation registry',
    () async {
      final result = await translateFormatting(r"""
      LayoutBuilder(builder: (context, constraints) => Column(children: [
        for (final index in [1, 2]) Text(i.Intl.plural(index,
          one: 'One', other: '$index items', locale: locale)),
      ]))
    """, hoist: false);
      expect(result.issues.where((i) => !i.code.isBuildNotice), isEmpty);
      expect(result.dsl, contains('intl.plural'));
      expect(result.dsl, contains('collection0'));
    },
  );
  test('enum interpolation retains native enum String conversion', () async {
    final result = await translateFormatting(
      r"""
      Text(i.Intl.plural(count, other: '${Status.active}'))
    """,
      hoist: false,
      extraSource: 'enum Status { active }',
    );
    expect(result.issues.where((i) => !i.code.isBuildNotice), isEmpty);
    expect(result.dsl, contains('Status.'));
    final refused = await translateFormatting(
      r"""
      Text(i.Intl.plural(count, other: '${Status.active}'))
    """,
      hoist: false,
      extraSource:
          "enum Status { active; @override String toString() => 'changed'; }",
    );
    expect(
      refused.issues.map((i) => i.message).join(),
      contains('custom enum String conversion'),
    );
  });
  test(
    'formatting event callbacks require an installed callback timing boundary',
    () async {
      final result = await translateFormatting(
        'GestureDetector(onTap: () => submit(i.DateFormat.yMd(locale).format(start)))',
        hoist: false,
        extraSource: 'void submit(String value) {}',
      );
      expect(
        result.issues.map((i) => i.message).join(),
        contains('native callback binding'),
      );
      expect(result.dsl, isNot(contains('intl.date.format')));
    },
  );
  test(
    'native builder frames retain eager formatting arguments of widget helpers',
    () async {
      final result = await translateFormatting(
        """
      LayoutBuilder(builder: (context, constraints) => tile(
        i.DateFormat.yMd(locale).format(start)))
    """,
        hoist: false,
        indexHelpers: true,
        extraSource: 'Widget tile(String unused) => const SizedBox();',
      );
      expect(result.issues.where((i) => !i.code.isBuildNotice), isEmpty);
      expect(result.dsl, contains('intl.date.format'));
      expect(result.dsl, contains('let'));
    },
  );
}
