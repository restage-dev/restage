import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:restage_codegen/src/capability_derivation.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/source_state.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' show parseLibraryFile;
import 'package:test/test.dart';

void main() {
  test(
    'authored radii distinguish constructor programs and native builder frame scalars',
    () async {
      final file = File(
        File(
          '../restage_core/test/fixtures/computed_native_shape.dart',
        ).resolveSymbolicLinksSync(),
      );
      final contexts = AnalysisContextCollection(includedPaths: [file.path]);
      addTearDown(contexts.dispose);
      final result =
          await contexts
                  .contextFor(file.path)
                  .currentSession
                  .getResolvedUnit(file.path)
              as ResolvedUnitResult;
      final core = decodeCatalog(
        File(
          '../restage_core/lib/src/widget_catalog/catalog.json',
        ).readAsStringSync(),
      );
      const owner = WidgetLibrary.custom('example.native');
      final catalog = Catalog(
        schemaVersion: core.schemaVersion,
        generatedAt: core.generatedAt,
        libraries: {
          ...core.libraries,
          owner: const LibraryInfo(version: '1', capabilityVersion: 1),
        },
        widgets: [
          ...core.widgets,
          WidgetEntry(
            wireId: WireId.unallocatedWidget,
            name: 'NativeShapeProbe',
            library: owner,
            category: WidgetCategory.decoration,
            description: 'Native shape',
            flutterType: '${file.uri}#NativeShapeProbe',
            childrenSlot: ChildrenSlot.none,
            properties: [
              PropertyEntry(
                wireId: WireId.unallocatedProperty,
                name: 'shape',
                type: PropertyType.shapeBorder,
                description: 'Native shape',
              ),
            ],
          ),
        ],
        structuredTypes: core.structuredTypes,
        unions: core.unions,
      );
      final expression =
          (result.unit.declarations
                      .whereType<FunctionDeclaration>()
                      .firstWhere(
                        (entry) => entry.name.lexeme == 'computedNativeShape',
                      )
                      .functionExpression
                      .body
                  as ExpressionFunctionBody)
              .expression;
      final translation = ExpressionTranslator(
        catalog: catalog,
        helpers: HelperRegistry(),
      ).translate(expression, hoistInMount: false);
      expect(
        translation.issues.where((issue) => !issue.code.isInformational),
        isEmpty,
        reason: translation.issues.map((issue) => issue.message).join('; '),
      );
      final library = parseLibraryFile(
        'import restage.core; import example.native; widget Root = ${translation.dsl};',
      );
      final manifest = deriveCapabilityManifest(library, catalog).manifest!;
      expect(manifest.requiredLibraries.single.minGenerated, 1);
      BlobRenderVerdict gate(int generated) =>
          BlobRenderCapabilityGate.evaluate(
            required: manifest,
            installed: InstalledCapability(
              builtInCatalogVersion: 23,
              installedLibraries: [
                InstalledLibrary(
                  namespace: owner.namespace,
                  version: 1,
                  generated: generated,
                ),
              ],
            ),
          );
      expect(gate(2).accepted, isTrue);
      expect(gate(3).accepted, isTrue);
      // A free arithmetic expression is not admitted by normal top-level
      // translation. Do not invent a binding to manufacture an envelope.
      final direct =
          (result.unit.declarations
                      .whereType<FunctionDeclaration>()
                      .firstWhere(
                        (entry) => entry.name.lexeme == 'directNativeShape',
                      )
                      .functionExpression
                      .body
                  as ExpressionFunctionBody)
              .expression;
      final refused = ExpressionTranslator(
        catalog: catalog,
        helpers: HelperRegistry(),
      ).translate(direct, hoistInMount: false);
      expect(
        refused.issues.where((issue) => !issue.code.isInformational),
        isNotEmpty,
      );
      final issues = <Issue>[];
      final blueprint = await extractSourceBuildBlueprint(
        sourceClass: result.libraryElement.classes.firstWhere(
          (entry) => entry.name == 'NativeShapeScreen',
        ),
        library: result.libraryElement,
        astNodeFor: resolvedAstNodeFor,
        issues: issues,
        location: file.path,
        catalog: catalog,
      );
      expect(issues, isEmpty);
      expect(blueprint, isNotNull);
      final authored =
          ExpressionTranslator(
            catalog: catalog,
            helpers: HelperRegistry(),
          ).translate(
            blueprint!.rootExpression,
            rootParams: blueprint.rootParams,
            rootState: blueprint.state,
            rootEventHandlers: blueprint.eventHandlers,
            buildContextParameter: blueprint.buildContextParameter,
            rootInlined: blueprint.inlined,
            rootBuildArguments: blueprint.buildArguments,
            hoistInMount: true,
          );
      expect(
        authored.issues.where((issue) => !issue.code.isInformational),
        isEmpty,
        reason: authored.issues.map((issue) => issue.message).join('; '),
      );
      final source =
          'import restage.core; import example.native; widget Root = ${authored.dsl};\n';
      final requirement = deriveCapabilityManifest(
        parseLibraryFile(source),
        catalog,
      ).manifest!;
      expect(
        requirement.requiredLibraries.single.minGenerated,
        3,
        reason: source,
      );
      for (final generated in [2, 3]) {
        final accepted = BlobRenderCapabilityGate.evaluate(
          required: requirement,
          installed: InstalledCapability(
            builtInCatalogVersion: 23,
            installedLibraries: [
              InstalledLibrary(
                namespace: owner.namespace,
                version: 1,
                generated: generated,
              ),
            ],
          ),
        ).accepted;
        expect(accepted, generated == 3);
      }
      final fixture = File(
        '../restage_core/test/fixtures/computed_native_shape.rfwtxt',
      );
      if (Platform.environment['WRITE_COMPUTED_SHAPE_FIXTURE'] == '1')
        fixture.writeAsStringSync(source);
      expect(fixture.readAsStringSync(), source);
    },
  );
}
