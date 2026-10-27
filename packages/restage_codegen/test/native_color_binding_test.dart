import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/file_system/overlay_file_system.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:restage_codegen/src/build_body.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/hoisting.dart';
import 'package:restage_codegen/src/host_data_shape.dart';
import 'package:restage_codegen/src/installed_native_call.dart';
import 'package:dart_style/dart_style.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import 'helpers.dart';

Future<TranslationResult> _translate(String expression,
    {String type = 'Color', String prelude = ''}) async {
  final probe = await parseMethodExpressionFromSourceForTest('''
import 'package:flutter/material.dart';
class Probe extends StatelessWidget {
 const Probe({required this.color, this.flag = true});
 final $type color;
 final bool flag;
 @override Widget build(BuildContext context) { $prelude return $expression; }
}
''', className: 'Probe', rootPackage: 'apps_examples');
  return _translateResolved(probe);
}

TranslationResult _translateResolved(ResolvedMethodExpressionForTest probe) {
  final parameters = probe
      .classes['Probe']!.unnamedConstructor!.formalParameters
      .whereType<FieldFormalParameterElement>();
  final catalogs = [
    for (final package in ['restage_core', 'restage_svg'])
      decodeCatalog(File('../$package/lib/src/widget_catalog/catalog.json')
          .readAsStringSync())
  ];
  final catalog = Catalog(
      schemaVersion: kSupportedSchemaVersion,
      generatedAt: '1970-01-01T00:00:00Z',
      libraries: {
        for (final catalog in catalogs) ...catalog.libraries
      },
      widgets: [
        for (final catalog in catalogs) ...catalog.widgets
      ],
      structuredTypes: [
        for (final catalog in catalogs) ...catalog.structuredTypes
      ],
      unions: [
        for (final catalog in catalogs) ...catalog.unions
      ]);
  return ExpressionTranslator(catalog: catalog, helpers: HelperRegistry())
      .translate(probe.expression,
          hoistInMount: true,
          rootInlined: InlinedDefinitions(
              localBindings: extractInlinableBuildBody(probe.expression
                      .thisOrAncestorOfType<MethodDeclaration>()!
                      .body)!
                  .localBindings),
          rootParams: [
        for (final parameter in parameters)
          RootContextParam(
              name: parameter.name!,
              type: parameter.type,
              typeCode: parameter.type.getDisplayString(),
              kind: RootContextParamKind.named,
              hostDataShape: parameter.type.isDartCoreBool
                  ? HostDataScalarShape(
                      parameter.type, HostDataScalarKind.boolean)
                  : null,
              field: parameter.field,
              isRequired: true,
              defaultValueCode: null,
              hasNullDefault: false),
      ]);
}

String _nativeBindingSource(HoistedValue binding, StringBuffer factories,
    Set<String> emittedFactories) {
  final plan = binding.nativeCall ?? binding.nativeConstant;
  if (plan == null) return binding.mountSource((name) => name);
  final name = 'nativeColor${binding.key}';
  if (emittedFactories.add(name)) {
    final type = binding.nativeCall == null
        ? plan.resultDartType
        : 'r.NativeCallAdapter';
    final body = binding.nativeCall == null
        ? plan.source
        : plan.adapterSource(core: 'r.', shared: 's.');
    factories.writeln('$type $name() => $body;');
  }
  return '$name()';
}

// Resolve the unchanged fixture as a package library so native provenance is
// independent of the checkout's absolute path. The overlays never touch lib/.
Future<ResolvedUnitResult> _resolveFixture(
    String package, String fileName, List<String> companions) async {
  final root = Directory('../$package').resolveSymbolicLinksSync();
  final provider = OverlayResourceProvider(PhysicalResourceProvider.INSTANCE);
  for (final name in [fileName, ...companions]) {
    provider.setOverlay('$root/lib/$name',
        content: File('$root/test/fixtures/$name').readAsStringSync(),
        modificationStamp: 1);
  }
  final path = '$root/lib/$fileName';
  final contexts = AnalysisContextCollection(
      includedPaths: [path], resourceProvider: provider);
  addTearDown(contexts.dispose);
  final uri = 'package:$package/$fileName';
  final library = await contexts
      .contextFor(path)
      .currentSession
      .getLibraryByUri(uri) as LibraryElementResult;
  expect(library.element.identifier, uri);
  final resolved = await library.element.session
      .getResolvedLibraryByElement(library.element) as ResolvedLibraryResult;
  return resolved.units.first;
}

void main() {
  test('fresh Color constructor arguments require an ordered invocation frame',
      () async {
    for (final expression in [
      'ColoredBox(color: MaterialColor(0xff102030, {500: color}))',
      'ColoredBox(color: MaterialColor(0xff102030, {500: Colors.red}))',
      'ColoredBox(color: true ? MaterialColor(0xff102030, {500: color}) : Colors.red)',
      'ColoredBox(color: MaterialColor(0xff102030, {500: color}) as Color)',
      'ColoredBox(color: flag ? MaterialColor(0xff102030, {500: color}) : Colors.red)',
      'LayoutBuilder(builder: (context, constraints) => ColoredBox(color: MaterialColor(0xff102030, {500: color})))',
    ]) {
      final result = await _translate(expression);
      expect(result.issues.where((issue) => !issue.code.isBuildNotice),
          isNotEmpty);
    }
  });

  test('fresh root Color locals require an ordered build prelude', () async {
    for (final declaration in ['final', 'final Color']) {
      for (final value in [
        'local',
        'true ? local : Colors.red',
        'local as Color',
        'flag ? local : Colors.red',
        'alias',
      ]) {
        final result = await _translate('ColoredBox(color: $value)',
            prelude:
                '$declaration local = MaterialColor(0xff102030, {500: color}); '
                'final alias = true ? (local as Color) : Colors.red;');
        expect(result.issues.where((issue) => !issue.code.isBuildNotice),
            isNotEmpty,
            reason: '$declaration $value');
        expect(
            result.hoisted.where((value) => value.kind == HoistValueKind.color),
            isEmpty,
            reason: '$declaration $value');
      }
    }
  });

  test('computed Color results cross as native objects, never as ARGB',
      () async {
    for (final (value, crosses) in [
      ('color as MaterialColor', true),
      ('(color as Object) as Color', true),
      ('[color].single', true),
      ('flag ? color : MaterialColor(0xff102030, {500: color})', false),
      ('flag ? color : Color(0xff102030)', true),
      ('flag ? color : color.withAlpha(128)', true),
      ('flag ? color : (() => color)()', true),
      ('(flag ? color : Colors.red) as MaterialColor', true),
      (
        '(flag && DateTime.now().millisecondsSinceEpoch > 0) ? color : Colors.red',
        true
      ),
    ]) {
      final result = await _translate('ColoredBox(color: $value)');
      expect(result.issues.where((issue) => !issue.code.isBuildNotice),
          crosses ? isEmpty : isNotEmpty,
          reason: value);
      expect(result.hoisted.map((value) => value.nativeContract?.type),
          crosses ? contains('flutter.Color') : isEmpty,
          reason: value);
      expect(
          result.hoisted.where((value) => value.kind == HoistValueKind.color),
          isEmpty,
          reason: value);
    }
  });

  test('closed base and canonical Color recipes retain exact translation',
      () async {
    for (final value in [
      'const Color(0xff123456)',
      'const Color.from(alpha: 1, red: .2, green: .3, blue: .4)',
      'flag ? Colors.red : Colors.blue',
      'Color(flag ? 0xff123456 : 0xffabcdef)',
    ]) {
      final result = await _translate('ColoredBox(color: $value)');
      expect(result.issues.where((issue) => !issue.code.isBuildNotice), isEmpty,
          reason: value);
      expect(
          result.hoisted.where((value) => value.kind == HoistValueKind.color),
          isEmpty,
          reason: value);
    }
  });

  test('native Color constructors and aliases generate installed factories',
      () async {
    final unit = await _resolveFixture(
        'restage_core', 'native_color_constructors.dart', [
      'native_color_constructors.g.dart',
      'native_color_constants.dart',
    ]);
    final declaration =
        unit.unit.declarations.whereType<ClassDeclaration>().single;
    final element = unit.libraryElement.classes.single;
    final factories = StringBuffer();
    final emittedFactories = <String>{};
    final output = StringBuffer();
    for (final name in [
      'fresh',
      'accent',
      'constant',
      'baseConstant',
      'alias',
      'imported',
      'importedStatic',
      'wrappedConst',
      'staticAlias',
      'localAlias',
      'layout',
      'nullable',
      'nullableLayout'
    ]) {
      final method = declaration.body.members
          .whereType<MethodDeclaration>()
          .singleWhere((method) => method.name.lexeme == name);
      final expression = method.body is ExpressionFunctionBody
          ? (method.body as ExpressionFunctionBody).expression
          : (method.body as BlockFunctionBody)
              .block
              .statements
              .whereType<ReturnStatement>()
              .single
              .expression!;
      final result = _translateResolved(ResolvedMethodExpressionForTest(
          expression: expression, classes: {'Probe': element}));
      expect(
          result.issues.where((issue) => !issue.code.isInformational), isEmpty,
          reason: '$name: ${result.issues.map((issue) => issue.message)}');
      if (!name.startsWith('nullable')) {
        expect(result.hoisted, isNotEmpty, reason: name);
      }
      output.writeln('const nativeColorDsl$name = ${jsonEncode(result.dsl)};');
      output.writeln(
          'Map<String, r.NativeBinding<Object?>> nativeColorBindings$name(Map<int, Color> swatch) => {');
      for (final binding in result.hoisted) {
        expect(binding.kind, HoistValueKind.nativeBinding, reason: name);
        final value =
            _nativeBindingSource(binding, factories, emittedFactories);
        output.writeln(
            '${jsonEncode(binding.key)}: r.NativeBinding(contract: ${nativeContractSource(binding.nativeContract!, 's.')}, value: $value),');
      }
      output.writeln('};');
    }
    final generated = DartFormatter(languageVersion: Version(3, 5, 0))
        .format("part of 'native_color_constructors.dart';\n$factories$output");
    final file =
        File('../restage_core/test/fixtures/native_color_constructors.g.dart');
    if (Platform.environment['WRITE_NATIVE_COLOR_FIXTURE'] == '1') {
      file.writeAsStringSync(generated);
    }
    expect(file.readAsStringSync(), generated);
  });

  test('inert Color selectors generate exact native consumer factories',
      () async {
    final unit = await _resolveFixture('restage_svg',
        'native_color_selectors.dart', ['native_color_selectors.g.dart']);
    final declaration =
        unit.unit.declarations.whereType<ClassDeclaration>().single;
    final element = unit.libraryElement.classes.single;
    final factories = StringBuffer();
    final emittedFactories = <String>{};
    final output = StringBuffer();
    for (final name in [
      'conditional',
      'alias',
      'borrowedBoth',
      'coalesce',
      'nullable',
      'nullableCoalesce',
      'nested',
      'layout',
      'svgTheme',
      'svgFilter',
      'svgBoth',
    ]) {
      final method = declaration.body.members
          .whereType<MethodDeclaration>()
          .singleWhere((method) => method.name.lexeme == name);
      final result = _translateResolved(ResolvedMethodExpressionForTest(
          expression: extractInlinableBuildBody(method.body)!.expression,
          classes: {'Probe': element}));
      expect(
          result.issues.where((issue) => !issue.code.isInformational), isEmpty,
          reason: '$name: ${result.issues.map((issue) => issue.message)}');
      expect(result.hoisted, isNotEmpty, reason: name);
      expect(result.hoisted.map((value) => value.kind),
          everyElement(HoistValueKind.nativeBinding),
          reason: name);
      expect(result.hoisted.any((value) => value.nativeCall != null), isTrue,
          reason: name);
      output
          .writeln('const nativeSelectorDsl$name = ${jsonEncode(result.dsl)};');
      output.writeln('Map<String, r.NativeBinding<Object?>> '
          'nativeSelectorBindings$name({required bool flag, required Color color, '
          'required Color? maybeColor, required Color other}) => {');
      for (final binding in result.hoisted) {
        final value =
            _nativeBindingSource(binding, factories, emittedFactories);
        output.writeln('${jsonEncode(binding.key)}: r.NativeBinding('
            'contract: ${nativeContractSource(binding.nativeContract!, 's.')}, '
            'value: $value),');
      }
      output.writeln('};');
    }
    final generated = DartFormatter(languageVersion: Version(3, 9, 0))
        .format("part of 'native_color_selectors.dart';\n$factories$output");
    final file =
        File('../restage_svg/test/fixtures/native_color_selectors.g.dart');
    if (Platform.environment['WRITE_NATIVE_SELECTOR_FIXTURE'] == '1') {
      file.writeAsStringSync(generated);
    }
    expect(file.readAsStringSync(), generated);
  });

  test('SVG callback Color locals retain exact nominal native values',
      () async {
    final unit = await _resolveFixture('restage_svg',
        'native_color_source.dart', ['native_color_source.g.dart']);
    final declaration =
        unit.unit.declarations.whereType<ClassDeclaration>().single;
    final element = unit.libraryElement.classes.single;
    final method = declaration.body.members
        .whereType<MethodDeclaration>()
        .singleWhere((method) => method.name.lexeme == 'local');
    final result = _translateResolved(ResolvedMethodExpressionForTest(
        expression: (method.body as ExpressionFunctionBody).expression,
        classes: {'Probe': element}));
    expect(result.issues.where((issue) => !issue.code.isInformational), isEmpty,
        reason: '${result.issues.map((issue) => issue.message)}');
    expect(result.dsl, contains('nativeLocal'));
    final factories = StringBuffer();
    final emittedFactories = <String>{};
    final output = StringBuffer();
    output.writeln('const nativeSvgColorDsl = ${jsonEncode(result.dsl)};');
    output.writeln(
        'Map<String, r.NativeBinding<Object?>> nativeSvgColorBindings(Map<int, Color> swatch) => {');
    for (final binding in result.hoisted) {
      final value = _nativeBindingSource(binding, factories, emittedFactories);
      output.writeln(
          '${jsonEncode(binding.key)}: r.NativeBinding(contract: ${nativeContractSource(binding.nativeContract!, 's.')}, value: $value),');
    }
    output.writeln('};');
    final generated = DartFormatter(languageVersion: Version(3, 9, 0))
        .format("part of 'native_color_source.dart';\n$factories$output");
    final file =
        File('../restage_svg/test/fixtures/native_color_source.g.dart');
    if (Platform.environment['WRITE_NATIVE_COLOR_FIXTURE'] == '1')
      file.writeAsStringSync(generated);
    expect(file.readAsStringSync(), generated);
  });

  test('SVG themes and filters keep native Color references', () async {
    final cases = <String, Object?>{};
    final unit = await _resolveFixture('restage_svg',
        'native_color_source.dart', ['native_color_source.g.dart']);
    final declaration =
        unit.unit.declarations.whereType<ClassDeclaration>().single;
    final element = unit.libraryElement.classes.single;
    for (final name in ['theme', 'filter', 'layout', 'wrapped']) {
      final method = declaration.body.members
          .whereType<MethodDeclaration>()
          .singleWhere((method) => method.name.lexeme == name);
      final result = _translateResolved(ResolvedMethodExpressionForTest(
          expression: (method.body as ExpressionFunctionBody).expression,
          classes: {'Probe': element}));
      expect(
          result.issues.where((issue) => !issue.code.isInformational), isEmpty,
          reason: '$name: ${result.issues.map((issue) => issue.message)}');
      expect(result.hoisted, hasLength(1));
      final binding = result.hoisted.single;
      expect(binding.nativeContract?.type, 'flutter.Color');
      cases[name] = {'dsl': result.dsl, 'key': binding.key};
    }
    final generated = '${const JsonEncoder.withIndent('  ').convert(cases)}\n';
    final file = File('../restage_svg/test/fixtures/native_color_sources.json');
    if (Platform.environment['WRITE_NATIVE_COLOR_FIXTURE'] == '1') {
      file.writeAsStringSync(generated);
    }
    expect(file.readAsStringSync(), generated);
  });

  test('ordinary Color fields and aliases keep native binding declarations',
      () async {
    final cases = <String, Object?>{};
    for (final (name, type, prelude, expression) in [
      ('root', 'Color', '', 'ColoredBox(color: this.color)'),
      ('cast', 'Color', '', 'ColoredBox(color: color as Color)'),
      ('selected', 'Color', '', 'ColoredBox(color: true ? color : Colors.red)'),
      (
        'selectedElse',
        'Color',
        '',
        'ColoredBox(color: false ? Colors.red : color)'
      ),
      (
        'wrappedAlias',
        'Color',
        'final first = color; final alias = true ? (first as Color) : Colors.red;',
        'ColoredBox(color: alias as Color)'
      ),
      ('material', 'MaterialColor', '', 'ColoredBox(color: color)'),
      ('accent', 'MaterialAccentColor', '', 'ColoredBox(color: color)'),
      ('alias', 'Color', 'final alias = color;', 'ColoredBox(color: alias)'),
      (
        'layout',
        'Color',
        '',
        'LayoutBuilder(builder: (context, constraints) => ColoredBox(color: color))'
      ),
      (
        'style',
        'Color',
        '',
        "Text('color', style: TextStyle(color: color, decorationColor: color, shadows: [Shadow(color: color)]))"
      ),
      (
        'gradient',
        'Color',
        '',
        'DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [color, color])))'
      ),
      (
        'shadow',
        'Color',
        '',
        'Container(decoration: BoxDecoration(boxShadow: [BoxShadow(color: color)]))'
      ),
    ]) {
      final result = await _translate(expression, type: type, prelude: prelude);
      expect(result.issues.where((issue) => !issue.code.isBuildNotice), isEmpty,
          reason: '$name: ${result.issues.map((issue) => issue.message)}');
      expect(result.hoisted, hasLength(1), reason: name);
      final binding = result.hoisted.single;
      expect(binding.nativeContract?.type, 'flutter.Color', reason: name);
      expect(binding.kind, HoistValueKind.nativeBinding, reason: name);
      cases[name] = {'dsl': result.dsl, 'key': binding.key};
    }
    final generated = '${const JsonEncoder.withIndent('  ').convert(cases)}\n';
    final file =
        File('../restage_core/test/fixtures/native_color_sources.json');
    if (Platform.environment['WRITE_NATIVE_COLOR_FIXTURE'] == '1') {
      file.writeAsStringSync(generated);
    }
    expect(file.readAsStringSync(), generated);
  });
}
