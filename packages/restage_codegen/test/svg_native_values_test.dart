import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';
import 'package:dart_style/dart_style.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:restage_codegen/src/catalog_validator.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/emit_utils.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/installed_native_call.dart';
import 'package:restage_shared/rfw_formats.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

void main() {
  test(
    'SVG native value fixtures compile actual source into installed factories',
    () async {
      final fixture = File(
        '../restage_svg/test/fixtures/native_value_source.dart',
      );
      final temporary = Directory.systemTemp.createTempSync(
        'svg-value-source-',
      );
      addTearDown(() => temporary.deleteSync(recursive: true));
      final lib = Directory('${temporary.path}/lib')..createSync();
      final source = fixture.copySync('${lib.path}/native_value_source.dart');
      File(
        '../restage_svg/test/fixtures/native_value_source.g.dart',
      ).copySync('${lib.path}/native_value_source.g.dart');
      final configFile = File('../../.dart_tool/package_config.json').absolute;
      final config =
          jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
      for (final package in config['packages'] as List) {
        package['rootUri'] = configFile.uri
            .resolve(package['rootUri'] as String)
            .toString();
      }
      (config['packages'] as List).add({
        'name': 'restage_svg_value_fixture',
        'rootUri': temporary.uri.toString(),
        'packageUri': 'lib/',
        'languageVersion': '3.9',
      });
      final tool = Directory('${temporary.path}/.dart_tool')..createSync();
      File(
        '${tool.path}/package_config.json',
      ).writeAsStringSync(jsonEncode(config));
      final path = source.path;
      final contexts = AnalysisContextCollection(includedPaths: [path]);
      addTearDown(contexts.dispose);
      final unit =
          await contexts.contextFor(path).currentSession.getResolvedUnit(path)
              as ResolvedUnitResult;
      expect(
        unit.errors.where(
          (e) => e.diagnosticCode.severity == DiagnosticSeverity.ERROR,
        ),
        isEmpty,
        reason: unit.errors.join('\n'),
      );
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
      expect(
        unit.libraryElement.uri.toString(),
        'package:restage_svg_value_fixture/native_value_source.dart',
      );
      final cls = unit.unit.declarations
          .whereType<ClassDeclaration>()
          .singleWhere(
            (c) => c.declaredFragment?.element.name == 'ValueSource',
          );
      final element = unit.libraryElement.classes.singleWhere(
        (c) => c.name == 'ValueSource',
      );
      final params = element.unnamedConstructor!.formalParameters
          .whereType<FieldFormalParameterElement>();
      final root = [
        for (final p in params)
          RootContextParam(
            name: p.name!,
            type: p.type,
            typeCode: p.type.getDisplayString(),
            kind: RootContextParamKind.named,
            hostDataShape: null,
            field: p.field,
            isRequired: true,
            defaultValueCode: null,
            hasNullDefault: false,
          ),
      ];
      final output = StringBuffer("part of 'native_value_source.dart';\n");
      for (final name in [
        'fresh',
        'constants',
        'failing',
        'staged',
        'stagedHeaders',
        'stagedHeaderLiteral',
        'stagedFile',
        'stagedCallbacks',
        'stagedValues',
        'refused',
        'refusedFileConstruction',
        'refusedMapper',
        'refusedHeaders',
        'refusedGetter',
      ]) {
        final method = cls.body.members
            .whereType<MethodDeclaration>()
            .singleWhere((m) => m.name.lexeme == name);
        final expression = (method.body as ExpressionFunctionBody).expression;
        final result =
            ExpressionTranslator(
              catalog: catalog,
              helpers: HelperRegistry(),
            ).translate(
              expression,
              rootParams: root,
              buildContextParameter:
                  method.declaredFragment!.element.formalParameters.first,
              hoistInMount: true,
            );
        if (name.startsWith('refused')) {
          expect(
            result.issues.where((i) => !i.code.isInformational),
            isNotEmpty,
          );
          expect(result.hoisted.where((h) => h.nativeCall != null), isEmpty);
          continue;
        }
        expect(
          result.issues.where((i) => !i.code.isInformational),
          isEmpty,
          reason: '$name: ${result.issues.map((i) => i.message).join('\n')}',
        );
        expect(
          validateModelAgainstCatalog(
            parseLibraryFile(
              'import restage.svg; import restage.core; widget Root = ${result.dsl};',
            ),
            catalog,
            operations: result.valueOperations,
          ),
          isEmpty,
          reason: name,
        );
        if (name != 'constants') {
          expect(
            result.hoisted.where((h) => h.nativeCall != null),
            isNotEmpty,
            reason: name,
          );
        } else {
          expect(result.hoisted, hasLength(4));
        }
        output.writeln('const ${name}Dsl = ${dartStringLiteral(result.dsl)};');
        output.writeln(
          'Map<String,r.NativeBinding<Object?>> ${name}Bindings(ValueSource source) => {',
        );
        for (final h in result.hoisted) {
          final contract = h.nativeContract!;
          final value =
              h.nativeCall?.adapterSource(core: 'r.', shared: 's.') ??
              h.mountSource((name) => 'source.$name');
          output.writeln(
            '${dartStringLiteral(h.key)}: r.NativeBinding<Object?>(contract: ${nativeContractSource(contract, 's.')}, value: $value),',
          );
        }
        output.writeln('};');
        output.writeln(
          'Map<String,Object?> ${name}Context(ValueSource source) => {for(final entry in ${name}Bindings(source).entries) entry.key: entry.value.contract.reference(entry.key)};',
        );
      }
      final generated = DartFormatter(
        languageVersion: Version(3, 9, 0),
      ).format(output.toString());
      expect(generated, isNot(contains(temporary.path)));
      final file = File(
        '../restage_svg/test/fixtures/native_value_source.g.dart',
      );
      if (Platform.environment['WRITE_SVG_NATIVE_VALUES'] == '1')
        file.writeAsStringSync(generated);
      expect(file.readAsStringSync(), generated);
    },
  );
}
