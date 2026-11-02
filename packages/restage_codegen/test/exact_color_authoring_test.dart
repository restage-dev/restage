import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:restage_codegen/src/builder_expression_lowering.dart';
import 'package:restage_codegen/src/capability_derivation.dart';
import 'package:restage_codegen/src/catalog_validator.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_shared/restage_shared.dart'
    show ValueEvaluator, ValueReader, ValueType;
import 'package:restage_shared/rfw_formats.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

final class _NoCaptures implements ValueReader {
  @override
  Object? read(List<Object> path, ValueType type) => throw StateError('$path');
  @override
  int length(List<Object> path) => throw StateError('$path');
}

void main() {
  const originalForms = [
    'direct',
    'local',
    'imported',
    'prefixed',
    'nested',
    'builderDirect',
    'builderAliases',
    'fractional',
  ];
  const argbForms = [
    'materialShade',
    'argbDirect',
    'argbAliases',
    'argbMaskedDirect',
    'argbMaskedAliases',
    'builderArgbDirect',
    'builderArgbAliases',
    'builderArgbMaskedDirect',
    'builderArgbMaskedAliases',
  ];
  const materialForms = [
    'materialDirect',
    'materialAliasFixture',
    'materialPrefixed',
    'materialImported',
    'materialNested',
    'accentBuilder',
    'baseBuilder',
    'nestedMaterialBuilder',
    'subtypeRefused',
  ];
  late Catalog catalog;
  late ResolvedUnitResult unit;
  setUpAll(() async {
    final path = File(
      '../restage_svg/test/fixtures/exact_colors.dart',
    ).resolveSymbolicLinksSync();
    final contexts = AnalysisContextCollection(includedPaths: [path]);
    addTearDown(contexts.dispose);
    unit =
        await contexts.contextFor(path).currentSession.getResolvedUnit(path)
            as ResolvedUnitResult;
    final svg = decodeCatalog(
      File(
        '../restage_svg/lib/src/widget_catalog/catalog.json',
      ).readAsStringSync(),
    );
    final core = decodeCatalog(
      File(
        '../restage_core/lib/src/widget_catalog/catalog.json',
      ).readAsStringSync(),
    );
    catalog = Catalog(
      schemaVersion: svg.schemaVersion,
      generatedAt: svg.generatedAt,
      libraries: {...core.libraries, ...svg.libraries},
      widgets: [...core.widgets, ...svg.widgets],
      structuredTypes: [...core.structuredTypes, ...svg.structuredTypes],
      unions: [...core.unions, ...svg.unions],
    );
  });
  TranslationResult compile(String name) {
    final declaration = unit.unit.declarations
        .whereType<FunctionDeclaration>()
        .firstWhere((entry) => entry.name.lexeme == name);
    final expression =
        (declaration.functionExpression.body as ExpressionFunctionBody)
            .expression;
    return ExpressionTranslator(
      catalog: catalog,
      helpers: HelperRegistry(),
    ).translate(expression, hoistInMount: false);
  }

  test(
    'canonical Material source forms preserve exact tokens through builders',
    () {
      for (final name in materialForms) {
        final result = compile(name);
        expect(
          result.issues.where((issue) => !issue.code.isInformational),
          isEmpty,
          reason: '$name: ${result.issues.map((i) => i.message).join("; ")}',
        );
        expect(result.dsl, contains('material:'), reason: name);
        expect(
          validateModelAgainstCatalog(
            parseLibraryFile(
              'import restage.svg; import restage.core; widget Screen = ${result.dsl};',
            ),
            catalog,
          ),
          isEmpty,
          reason: name,
        );
      }
    },
  );
  test(
    'exact optional Color source forms parse and use current native decoding',
    () {
      final sources = <String>[];
      for (final name in [...originalForms, ...argbForms, ...materialForms]) {
        final result = compile(name);
        expect(
          result.issues.where((issue) => !issue.code.isInformational),
          isEmpty,
          reason: '$name: ${result.issues.map((i) => i.message).join("; ")}',
        );
        final source = 'widget $name = ${result.dsl};';
        final library = parseLibraryFile(
          'import restage.svg; import restage.core; $source',
        );
        expect(
          validateModelAgainstCatalog(library, catalog),
          isEmpty,
          reason: name,
        );
        final capability = deriveCapabilityManifest(library, catalog).manifest!;
        if (originalForms.contains(name)) {
          expect(capability.builtInFloor, 19, reason: name);
          expect(capability.requiredLibraries.single.minGenerated, 3);
        }
        if (materialForms.contains(name))
          expect(capability.builtInFloor, 24, reason: name);
        sources.add(source);
      }
      final fixture = File('../restage_svg/test/fixtures/exact_colors.rfwtxt');
      final source =
          'import restage.svg; import restage.core;\n${sources.join("\n")}\n';
      if (Platform.environment['WRITE_EXACT_COLOR_FIXTURE'] == '1')
        fixture.writeAsStringSync(source);
      expect(fixture.readAsStringSync(), source);
    },
  );
  test('canonical native shade getters retain installed getter evaluation', () {
    final result = compile('materialShade');
    expect(result.issues, isEmpty);
    expect(result.dsl, contains('0xFFF44336'));
  });
  test('native color constructor arguments evaluate in source order', () {
    for (final (name, error) in [
      ('argbDivisionFirst', isA<UnsupportedError>()),
      ('argbClampFirst', isA<ArgumentError>()),
      ('rgboDivisionFirst', isA<UnsupportedError>()),
      ('rgboClampFirst', isA<ArgumentError>()),
    ]) {
      final declaration = unit.unit.declarations
          .whereType<FunctionDeclaration>()
          .firstWhere((entry) => entry.name.lexeme == name);
      final expression =
          (declaration.functionExpression.body as ExpressionFunctionBody)
              .expression;
      final lowering = BuilderExpressionLowering(
        capture: (_) => throw StateError('Unexpected capture'),
      );
      lowering.parameter(
        declaration.declaredFragment!.element.formalParameters.single,
        'denominator',
        ValueType.integer,
      );
      final root = lowering.lower(expression);
      expect(lowering.provesNativeBase(root, 'Color'), isTrue, reason: name);
      final program = lowering.program(root)..validate();
      expect(
        () => ValueEvaluator(
          program,
          captures: _NoCaptures(),
          parameters: const {'denominator': 0},
        ).evaluate(),
        throwsA(error),
        reason: name,
      );
    }
  });
  test(
    'optional Color projection keeps null dynamic and nonfinite refusals',
    () {
      for (final name in [
        'unprovenSubtypeRefused',
        'nullRefused',
        'dynamicRefused',
        'nonfiniteRefused',
      ]) {
        final result = compile(name);
        expect(
          result.issues.where((issue) => !issue.code.isInformational),
          isNotEmpty,
          reason: name,
        );
        expect(result.dsl, isNot(contains('SvgPicture')), reason: name);
      }
    },
  );
}
