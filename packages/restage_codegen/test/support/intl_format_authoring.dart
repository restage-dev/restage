import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/element/element.dart';
import 'package:intl/intl.dart' as i;
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/host_data_shape.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;

import '../helpers.dart';
import '../shared_resolvers.dart';

final _catalog = requireNativeCatalog(decodeCatalog(
  File(File('packages/restage_core/lib/src/widget_catalog/catalog.json')
              .existsSync()
          ? 'packages/restage_core/lib/src/widget_catalog/catalog.json'
          : '../restage_core/lib/src/widget_catalog/catalog.json')
      .readAsStringSync(),
));

Future<TranslationResult> translateFormatting(String body,
    {bool hoist = true,
    String extraSource = '',
    bool indexHelpers = false}) async {
  final probe = await parseMethodExpressionFromSourceForTest('''
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart' as i;
$extraSource
class Probe extends StatelessWidget {
  const Probe({super.key, required this.start, required this.count, required this.locale});
  final DateTime start;
  final int count;
  final String locale;
  @override
  Widget build(BuildContext context) => $body;
}
''', className: 'Probe', methodName: 'build');
  final constructor = probe.classes['Probe']!.unnamedConstructor!;
  final root = <RootContextParam>[];
  for (final parameter
      in constructor.formalParameters.where((p) => p.name != 'key')) {
    final shape = deriveHostDataShape(parameter.type, root: parameter.name!);
    root.add(RootContextParam(
      name: parameter.name!,
      type: parameter.type,
      typeCode: parameter.type.getDisplayString(),
      kind: RootContextParamKind.named,
      hostDataShape: shape.shape,
      hostDataProblem: shape.problem,
      field: parameter is FieldFormalParameterElement ? parameter.field : null,
      isRequired: parameter.isRequired,
      defaultValueCode: parameter.defaultValueCode,
      hasNullDefault: false,
    ));
  }
  return ExpressionTranslator(catalog: _catalog, helpers: HelperRegistry())
      .translate(
    probe.expression,
    rootParams: root,
    rootInlined: InlinedDefinitions(
        helpers: indexHelpers
            ? inlinableHelperDefinitionsIn(probe.expression)
            : const {}),
    hoistInMount: hoist,
    buildContextParameter:
        probe.classes['Probe']!.getMethod('build')!.formalParameters.first,
  );
}

Future<List<ValueProgram>> authoredFormattingPrograms(
    List<String> expressions) async {
  final result = await translateFormatting(
      'Column(children: [${expressions.map((e) => 'Text($e)').join(',')}])',
      hoist: false);
  final issues = result.issues.where((issue) => !issue.code.isBuildNotice);
  if (issues.isNotEmpty || result.hoisted.isNotEmpty) {
    throw StateError('Formatting source did not compile directly: $issues');
  }
  final root = rfw
      .parseLibraryFile('import restage.core;widget root=${result.dsl};')
      .widgets
      .single
      .root as rfw.ConstructorCall;
  return [
    for (final child in root.arguments['children']! as List)
      ValueProgram.decode(
          ((child as rfw.ConstructorCall).arguments['text']! as Map)['program']!
              as String,
          operations: kIntlValueOperations),
  ];
}

List<(String, Object? Function())> intlArgumentCases() {
  const bad = "i.DateFormat.yMd('unknown_locale').format(DateTime.utc(2024))";
  String invalidLocale() =>
      i.DateFormat.yMd('unknown_locale').format(DateTime.utc(2024));
  return <(String, Object? Function())>[
    (
      "i.Intl.plural(one: $bad, 1 ~/ 0, other: 'other')",
      () => i.Intl.plural(one: invalidLocale(), 1 ~/ 0, other: 'other')
    ),
    (
      "i.Intl.gender(female: $bad, '\${1 ~/ 0}', other: 'other')",
      () => i.Intl.gender(female: invalidLocale(), '${1 ~/ 0}', other: 'other')
    ),
    (
      "i.Intl.select(locale: $bad, '\${1 ~/ 0}', {'other': 'other'})",
      () => i.Intl.select(
          locale: invalidLocale(), '${1 ~/ 0}', {'other': 'other'})
    ),
    (
      "i.Intl.select('active', locale: '\${1 ~/ 0}', {'other': $bad})",
      () => i.Intl.select(
          'active', locale: '${1 ~/ 0}', {'other': invalidLocale()})
    ),
    (
      "i.Intl.select('active', {'other': $bad, 'active': '\${1 ~/ 0}'})",
      () => i.Intl.select(
          'active', {'other': invalidLocale(), 'active': '${1 ~/ 0}'})
    ),
    (
      "i.Intl.select('active', {'other': $bad}, locale: '\${1 ~/ 0}')",
      () => i.Intl.select('active', {'other': invalidLocale()},
          locale: '${1 ~/ 0}')
    ),
    (
      "i.Intl.plural(1, one: 'one', other: 'other')",
      () => i.Intl.plural(1, one: 'one', other: 'other')
    ),
    (
      "i.Intl.gender('male', other: 'they', male: 'he')",
      () => i.Intl.gender('male', other: 'they', male: 'he')
    ),
    (
      "i.Intl.select('active', {'active': 'yes', 'other': 'no'}, locale: 'en_US')",
      () => i.Intl.select('active', {'active': 'yes', 'other': 'no'},
          locale: 'en_US')
    ),
    (
      "i.Intl.plural(one: 'one', 1, other: 'other')",
      () => i.Intl.plural(one: 'one', 1, other: 'other')
    ),
    (
      "i.Intl.gender(other: 'they', 'male', male: 'he')",
      () => i.Intl.gender(other: 'they', 'male', male: 'he')
    ),
    (
      "i.Intl.select(meaning: null, 'active', {'active': 'yes', 'other': 'no'}, locale: 'en_US')",
      () => i.Intl.select(
          meaning: null,
          'active',
          {'active': 'yes', 'other': 'no'},
          locale: 'en_US')
    ),
  ];
}

List<(String, DateTime)> intlEpochCases() {
  return <(String, DateTime)>[
    (
      'DateTime.fromMicrosecondsSinceEpoch(1234567)',
      DateTime.fromMicrosecondsSinceEpoch(1234567)
    ),
    (
      'DateTime.fromMillisecondsSinceEpoch(1234)',
      DateTime.fromMillisecondsSinceEpoch(1234)
    ),
    (
      'DateTime.fromMicrosecondsSinceEpoch(isUtc: true, 1234567)',
      DateTime.fromMicrosecondsSinceEpoch(isUtc: true, 1234567)
    ),
    (
      'DateTime.fromMicrosecondsSinceEpoch(1234567, isUtc: false)',
      DateTime.fromMicrosecondsSinceEpoch(1234567, isUtc: false)
    ),
    (
      'DateTime.fromMillisecondsSinceEpoch(isUtc: false, 1234)',
      DateTime.fromMillisecondsSinceEpoch(isUtc: false, 1234)
    ),
    (
      'DateTime.fromMillisecondsSinceEpoch(1234, isUtc: true)',
      DateTime.fromMillisecondsSinceEpoch(1234, isUtc: true)
    ),
  ];
}

/// Compiles the original native-oracle cases through the normal translator.
Future<String> compileIntlProgramsFixture() async {
  final sources = [
    for (final entry in intlArgumentCases()) entry.$1,
    for (final (source, _) in intlEpochCases())
      "i.DateFormat.yMd('en_US').format($source)",
    "i.DateFormat.yMd('en_US').format(DateTime.fromMicrosecondsSinceEpoch(isUtc: i.DateFormat.yMd('unknown_locale').format(DateTime.utc(2024)) == '', 1 ~/ 0))",
  ];
  final programs = await authoredFormattingPrograms(sources);
  return '${const JsonEncoder.withIndent('  ').convert({
        'version': 1,
        'cases': [
          for (var index = 0; index < sources.length; index++)
            {'source': sources[index], 'program': programs[index].toJson()},
        ],
      })}\n';
}

/// Normal owner entry point for the focused source-to-native Intl fixture.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    throw ArgumentError('Expected the Intl graph fixture output path.');
  }
  try {
    final output = await compileIntlProgramsFixture();
    File(arguments.single).writeAsStringSync(output);
    stdout.writeln('Wrote Intl authored-program fixture: ${arguments.single}');
  } finally {
    sharedResolvers.reset();
  }
}
