import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/error/error.dart';
import 'package:restage_codegen/src/catalog_validator.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/hoisting.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_shared/rfw_formats.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

void main() {
  test('production catalog validation rejects opaque native SVG arguments', () {
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
    final catalog = Catalog(
      schemaVersion: svg.schemaVersion,
      generatedAt: svg.generatedAt,
      libraries: {...core.libraries, ...svg.libraries},
      widgets: [...core.widgets, ...svg.widgets],
      structuredTypes: [...core.structuredTypes, ...svg.structuredTypes],
      unions: [...core.unions, ...svg.unions],
    );
    const consumers = {
      'SvgPictureAsset': [
        'bundle',
        'colorMapper',
        'errorBuilder',
        'imageBuilder',
      ],
      'SvgPictureNetwork': [
        'httpClient',
        'colorMapper',
        'errorBuilder',
        'imageBuilder',
      ],
      'SvgPictureString': ['colorMapper', 'errorBuilder', 'imageBuilder'],
      'SvgPictureMemory': ['colorMapper', 'errorBuilder', 'imageBuilder'],
      'SvgPictureFile': ['file', 'colorMapper', 'errorBuilder', 'imageBuilder'],
      'SvgPicture': ['bytesLoader', 'errorBuilder', 'imageBuilder'],
    };
    List<Issue> validate(String body) => validateModelAgainstCatalog(
      parseLibraryFile(
        'import restage.svg; import restage.core; widget Root = $body;',
      ),
      catalog,
    );
    for (final consumer in consumers.entries) {
      for (final field in consumer.value) {
        expect(
          validate('${consumer.key}($field: data.context.native)'),
          isEmpty,
        );
        expect(validate('${consumer.key}($field: null)'), isEmpty);
        for (final opaque in [
          'SizedBox()',
          '(frame) => SizedBox()',
          'event "unused" {}',
        ]) {
          for (final value in [opaque, 'switch true { true: $opaque }']) {
            final issues = validate('${consumer.key}($field: $value)');
            expect(
              issues.map((issue) => issue.code),
              contains(IssueCode.propertyValueTypeMismatch),
              reason: '${consumer.key}.$field: $value',
            );
          }
          final nested = validate(
            'SvgPicture(bytesLoader: {kind: "SvgAssetLoader", '
            'value: "tiny.svg", assetBundle: $opaque})',
          );
          expect(
            nested.map((issue) => issue.code),
            contains(IssueCode.propertyValueTypeMismatch),
          );
        }
      }
    }
    // Native builder slots take compiled builder programs, never raw RFW ones.
    expect(
      () => validate(
        'SvgPictureString(string: "<svg/>", '
        'placeholderBuilder: (frame) => SizedBox())',
      ),
      throwsFormatException,
    );
    expect(validate('SizedBox(child: SizedBox())'), isEmpty);
  });

  test(
    'all SVG constructors and loaders preserve exact bound options',
    () async {
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
      final catalog = Catalog(
        schemaVersion: svg.schemaVersion,
        generatedAt: svg.generatedAt,
        libraries: {...core.libraries, ...svg.libraries},
        widgets: [...core.widgets, ...svg.widgets],
        structuredTypes: [...core.structuredTypes, ...svg.structuredTypes],
        unions: [...core.unions, ...svg.unions],
      );
      final outputs = <String, Object>{};
      const cases = [
        'asset',
        'network',
        'string',
        'memory',
        'file',
        'boundLoader',
        'stringLoader',
        'bytesLoader',
        'assetLoader',
        'networkLoader',
        'fileLoader',
        'defaultAsset',
      ];
      final source = File(
        '../restage_svg/test/fixtures/borrowed_bindings.dart',
      );
      final path = source.resolveSymbolicLinksSync();
      final contexts = AnalysisContextCollection(includedPaths: [path]);
      addTearDown(contexts.dispose);
      final unit =
          await contexts.contextFor(path).currentSession.getResolvedUnit(path)
              as ResolvedUnitResult;
      expect(
        unit.errors.where(
          (error) => error.diagnosticCode.severity == DiagnosticSeverity.ERROR,
        ),
        isEmpty,
        reason: unit.errors.join('\n'),
      );
      final cls = unit.unit.declarations.whereType<ClassDeclaration>().single;
      for (final name in cases) {
        final method = cls.body.members
            .whereType<MethodDeclaration>()
            .singleWhere(
              (m) => m.name.lexeme == (name == 'file' ? 'filePicture' : name),
            );
        final expression = (method.body as ExpressionFunctionBody).expression;
        final params = unit
            .libraryElement
            .classes
            .single
            .unnamedConstructor!
            .formalParameters;
        final result =
            ExpressionTranslator(
              catalog: catalog,
              helpers: HelperRegistry(),
            ).translate(
              expression,
              hoistInMount: true,
              rootParams: [
                for (final p in params)
                  RootContextParam(
                    name: p.name!,
                    type: p.type,
                    typeCode: p.type.getDisplayString(),
                    kind: RootContextParamKind.named,
                    hostDataShape: null,
                    field: (p as FieldFormalParameterElement).field,
                    isRequired: true,
                    defaultValueCode: null,
                    hasNullDefault: false,
                  ),
              ],
            );
        expect(
          result.issues.where((i) => !i.code.isInformational),
          isEmpty,
          reason: '${name}: ${result.issues.map((i) => i.message).join('\n')}',
        );
        expect(
          validateModelAgainstCatalog(
            parseLibraryFile(
              'import restage.svg; widget Root = ${result.dsl};',
            ),
            catalog,
          ),
          isEmpty,
          reason: name,
        );
        expect(
          result.hoisted.every((h) => h.kind == HoistValueKind.nativeBinding),
          isTrue,
        );
        outputs[name] = {
          'dsl': result.dsl,
          'bindings': {
            for (final h in result.hoisted)
              h.key: {
                'source': h.mountSource((n) => n),
                'type': h.nativeContract!.type,
                'nullable': h.nativeContract!.nullable,
              },
          },
        };
      }
      final fixture = File('../restage_svg/test/fixtures/native_bindings.json');
      if (Platform.environment['WRITE_SVG_NATIVE_BINDINGS'] == '1')
        fixture.writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(outputs)}\n',
        );
      expect(jsonDecode(fixture.readAsStringSync()), outputs);
    },
  );
}
