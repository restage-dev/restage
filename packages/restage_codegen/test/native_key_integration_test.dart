import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/file_system/overlay_file_system.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:restage_codegen/src/build_body.dart';
import 'package:restage_codegen/src/capability_derivation.dart';
import 'package:restage_codegen/src/catalog_validator.dart';
import 'package:restage_codegen/src/catalog_loader.dart';
import 'package:restage_codegen/src/widget_visitor.dart';
import 'package:restage_codegen/src/user_catalog_allocation.dart';
import 'package:restage_codegen/src/surface_publication/package_surface_compiler_builder.dart';
import 'package:restage_codegen/src/restage_widget_package_facts.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/factory_emitter.dart';
import 'package:restage_codegen/src/emit_utils.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/host_data_shape.dart';
import 'package:restage_codegen/src/widget_classification.dart';
import 'package:restage_codegen/src/native_catalog_index.dart';
import 'package:restage_codegen/src/surface_publication/host_data_contract.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_compiler_core/restage_compiler_core.dart';
import 'package:restage_compiler_core/src/rfw_program_envelope.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

Catalog keyCatalog(String package) => decodeCatalog(
  File('test/fixtures/native_key_$package.json').readAsStringSync(),
);

Future<ResolvedMethodExpressionForTest> resolveKeySource(String source) async {
  final root = Directory('../restage_svg').resolveSymbolicLinksSync();
  final path = '$root/lib/_key_probe.dart';
  final provider = OverlayResourceProvider(PhysicalResourceProvider.INSTANCE);
  provider.setOverlay(path, content: source, modificationStamp: 1);
  final contexts = AnalysisContextCollection(
    includedPaths: [path],
    resourceProvider: provider,
  );
  addTearDown(contexts.dispose);
  final library =
      await contexts
              .contextFor(path)
              .currentSession
              .getLibraryByUri('package:restage_svg/_key_probe.dart')
          as LibraryElementResult;
  final resolved =
      await library.element.session.getResolvedLibraryByElement(library.element)
          as ResolvedLibraryResult;
  final method = resolved.units.single.unit.declarations
      .whereType<ClassDeclaration>()
      .singleWhere((c) => c.namePart.typeName.lexeme == 'P')
      .body
      .members
      .whereType<MethodDeclaration>()
      .singleWhere((m) => m.name.lexeme == 'build');
  return ResolvedMethodExpressionForTest(
    expression: extractInlinableBuildBody(method.body)!.expression,
    classes: {for (final cls in library.element.classes) cls.name!: cls},
  );
}

Future<TranslationResult> translateKey(
  String body,
  Catalog catalog, {
  String prelude = '',
  String declarations = '',
  String keyType = 'Key',
  Map<String, WidgetClassification> classifications = const {},
}) async {
  final probe = await resolveKeySource('''
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
$declarations
class P extends StatelessWidget {
  const P({required this.itemKey, required this.items});
  final $keyType itemKey;
  final List<Object> items;
  Widget build(BuildContext context) { $prelude return $body; }
}
''');
  return translateKeyProbe(probe, catalog, classifications: classifications);
}

TranslationResult translateKeyProbe(
  ResolvedMethodExpressionForTest probe,
  Catalog catalog, {
  Map<String, WidgetClassification> classifications = const {},
  Map<String, CustomWidgetBlueprint> blueprints = const {},
}) {
  final parameters = probe.classes['P']!.unnamedConstructor!.formalParameters
      .whereType<FieldFormalParameterElement>();
  return ExpressionTranslator(
    catalog: catalog,
    helpers: HelperRegistry(),
    customWidgetClassifications: classifications,
    customWidgetBlueprints: blueprints,
  ).translate(
    probe.expression,
    hoistInMount: true,
    rootInlined: InlinedDefinitions(
      localBindings: extractInlinableBuildBody(
        probe.expression.thisOrAncestorOfType<MethodDeclaration>()!.body,
      )!.localBindings,
    ),
    rootParams: [
      for (final parameter in parameters)
        RootContextParam(
          name: parameter.name!,
          type: parameter.type,
          typeCode: parameter.type.getDisplayString(),
          kind: RootContextParamKind.named,
          hostDataShape: deriveHostDataShape(
            parameter.type,
            root: parameter.name!,
          ).shape,
          field: parameter.field,
          isRequired: true,
          defaultValueCode: null,
          hasNullDefault: false,
        ),
    ],
  );
}

void main() {
  final core = keyCatalog('restage_core');
  final material = keyCatalog('restage_material');
  final svg = keyCatalog('restage_svg');
  test('production Material Icon factory accepts its key argument', () {
    final icon = material.widgets.single;
    final emitted = emitFactoryFunction(
      icon,
      nativeIndex: NativeCatalogIndex(material),
    );
    expect(emitted, contains('restageIcon('));
    expect(emitted, contains('key: RestageDecoders.nativeBinding<Key>('));
  });
  for (final (catalog, body) in [
    (core, "Text('item', key: itemKey)"),
    (material, 'Icon(Icons.check, key: itemKey)'),
    (svg, "SvgPicture.string('<svg/>', key: itemKey)"),
  ]) {
    test(
      'production validator admits the actual native key slot: $body',
      () async {
        final result = await translateKey(body, catalog);
        expect(
          result.issues,
          isEmpty,
          reason: result.issues.map((issue) => issue.message).join('\n'),
        );
        final library = rfw.parseLibraryFile('widget Root = ${result.dsl};');
        final issues = validateModelAgainstCatalog(
          library,
          catalog,
          operations: result.valueOperations,
          hostDataContract: hostDataContractOf(
            const [],
            hoisted: result.hoisted,
          ),
        );
        expect(
          issues,
          isEmpty,
          reason: issues.map((issue) => issue.message).join('\n'),
        );
        final capability = deriveCapabilityManifest(
          library,
          catalog,
          hoisted: result.hoisted,
        );
        expect(capability.issues, isEmpty);
        expect(capability.manifest!.builtInFloor, 24);
        expect(nativeBindingsNeedInstalledHost(library, catalog), isTrue);
      },
    );
  }
  for (final nullable in [false, true]) {
    test('borrowed builder key uses nominal capture nullable=$nullable', () async {
      final result = await translateKey(
        "LayoutBuilder(builder:(context,constraints)=>Text('item',key:itemKey))",
        core,
        keyType: nullable ? 'Key?' : 'Key',
      );
      expect(
        result.issues,
        isEmpty,
        reason: result.issues.map((issue) => issue.message).join('\n'),
      );
      final library = rfw.parseLibraryFile('widget Root = ${result.dsl};');
      final scope = RfwProgramScope(
        library.widgets.map((widget) => widget.root),
        operations: result.valueOperations,
      );
      final root = library.widgets.single.root as rfw.ConstructorCall;
      final builder = scope.decode(root.arguments['builder'])!;
      Iterable<BuilderResult> results(BuilderResult result) sync* {
        yield result;
        for (final child in result.descendants) yield* results(child);
      }

      expect(
        results(
          builder.builder!.result,
        ).where((result) => result.key != null).map((result) => result.keyType),
        everyElement('nativeKey'),
      );
      expect(
        results(builder.builder!.result).where((result) => result.key != null),
        isNotEmpty,
      );
      final capture = builder.values.captures.values.single;
      expect(capture.kind, 'native');
      expect(capture.nativeType, 'flutter.Key');
      expect(capture.nullable, nullable);
      expect(
        validateModelAgainstCatalog(
          library,
          core,
          operations: result.valueOperations,
          hostDataContract: hostDataContractOf(
            const [],
            hoisted: result.hoisted,
          ),
        ),
        isEmpty,
      );
      final fixture = File('test/fixtures/native_key_lazy_$nullable.json');
      final encoded =
          '${jsonEncode({'dsl': result.dsl, 'slot': result.hoisted.single.key, 'nullable': nullable})}\n';
      if (Platform.environment['WRITE_NATIVE_KEY_FACTORIES'] == '1')
        fixture.writeAsStringSync(encoded);
      expect(fixture.readAsStringSync(), encoded);
    });
  }
  test('ordinary keyless Text keeps its previous capability floor', () {
    final result = deriveCapabilityManifest(
      rfw.parseLibraryFile('widget Root = Text(text:"item");'),
      core,
    );
    expect(result.manifest!.builtInFloor, 1);
  });
  test(
    'typed native key validation rejects malformed, foreign and unknown references',
    () {
      const declared = NativeBindingContract(type: 'flutter.Key');
      final host = SurfaceScreenHostDataSchema({
        'declared': const SurfaceScreenHostDataNativeBindingShapeV1(declared),
      });
      for (final key in [
        '{kind:"nativeBinding",key:"declared",type:"flutter.Key",nullable:false}',
        'data.context.declared',
      ]) {
        final library = rfw.parseLibraryFile(
          'widget Root = Text(text:"item",key:$key);',
        );
        expect(
          validateModelAgainstCatalog(library, core, hostDataContract: host),
          isEmpty,
          reason: key,
        );
      }
      // Rejected as an issue or, for a malformed program, a FormatException.
      for (final key in [
        '{kind:"nativeBinding",key:"unknown",type:"flutter.Key",nullable:false}',
        'data.context.unknown',
        'data.other.declared',
        '{}',
        '[]',
        '42',
        '{kind:"nativeBinding",key:"declared",type:"flutter.Color",nullable:false}',
        '{kind:"nativeBinding",key:"declared",type:"flutter.Key"}',
        '{kind:"nativeLocal",slot:"missing",type:"flutter.Key",nullable:false}',
      ]) {
        final library = rfw.parseLibraryFile(
          'widget Root = Text(text:"item",key:$key);',
        );
        try {
          expect(
            validateModelAgainstCatalog(library, core, hostDataContract: host),
            isNotEmpty,
            reason: key,
          );
        } on FormatException {
          // Rejected.
        }
      }
      expect(
        validateModelAgainstCatalog(
          rfw.parseLibraryFile(
            'widget Root = Text(text:"item",typo:data.context.declared);',
          ),
          core,
          hostDataContract: host,
        ),
        isNotEmpty,
      );
    },
  );
  test('custom native constructor uses the same Key property route only for RFW', () async {
    final widgetSource = File(
      '../restage_svg/test/fixtures/native_key_widget.dart',
    ).readAsStringSync();
    final probe = await resolveKeySource(
      '$widgetSource\n'
      'class P extends StatelessWidget { const P({required this.itemKey}); final Key itemKey; Widget build(BuildContext context) => NativeKeyWidget(key:itemKey); }',
    );
    final library = probe.classes['P']!.library;
    final asset = AssetId('restage_svg', 'lib/_key_probe.dart');
    final facts = indexRestageWidgetPackage([
      (assetId: asset, library: library),
    ]);
    final refs = builtInStructuredRefs(
      core,
      kStructuredRefDecoders.keys.toSet(),
    );
    final result = visitRestageWidgetsInPackage(
      library,
      asset,
      packageFacts: facts,
      nativeStructuredRefs: refs,
    );
    expect(
      result.issues,
      isEmpty,
      reason: result.issues.map((i) => i.message).join('\n'),
    );
    final allocated = allocateUserCatalogFromWidgets(
      package: 'key_fixture',
      widgets: result.widgets,
    ).catalog;
    final entry = allocated.widgets.singleWhere(
      (widget) => widget.name == 'NativeKeyWidget',
    );
    final key = entry.properties.singleWhere(
      (property) => property.name == 'key',
    );
    expect(key.constructorNullable, isTrue);
    expect(
      key.structuredRef,
      refs['package:flutter/src/foundation/key.dart#Key'],
    );
    for (final target in [
      WidgetVisitorTarget.a2ui,
      WidgetVisitorTarget.widgetbook,
    ]) {
      final projected = visitRestageWidgetsInPackage(
        library,
        asset,
        packageFacts: facts,
        nativeStructuredRefs: refs,
        target: target,
      );
      expect(
        projected.widgets
            .expand((widget) => widget.properties)
            .where((property) => property.name == 'key'),
        isEmpty,
      );
    }
    final catalog = Catalog(
      schemaVersion: kSupportedSchemaVersion,
      generatedAt: core.generatedAt,
      libraries: {
        ...core.libraries,
        entry.library: const LibraryInfo(version: '1', capabilityVersion: 1),
      },
      widgets: [...core.widgets, ...allocated.widgets],
      structuredTypes: core.structuredTypes,
      unions: core.unions,
    );
    final translation = translateKeyProbe(probe, catalog);
    expect(
      translation.issues.where((issue) => !issue.code.isInformational),
      isEmpty,
    );
    expect(translation.dsl, startsWith('NativeKeyWidget(key: data.context.'));
    final keyed = deriveCapabilityManifest(
      rfw.parseLibraryFile('widget Root=${translation.dsl};'),
      catalog,
      hoisted: translation.hoisted,
    ).manifest!;
    final keyless = deriveCapabilityManifest(
      rfw.parseLibraryFile('widget Root=NativeKeyWidget();'),
      catalog,
    ).manifest!;
    expect(keyed.builtInFloor, 24);
    expect(keyed.requiredLibraries.single.minGenerated, 3);
    expect(keyless.builtInFloor, 1);
    expect(keyless.requiredLibraries.single.minGenerated, 1);
    // A keyed version needs generated code v3; older builds are refused.
    for (final (generated, outcome) in [
      (2, LibraryCompatibility.tooOld),
      (3, LibraryCompatibility.satisfied),
    ]) {
      final installed = InstalledLibrary(
        namespace: entry.library.namespace,
        version: 1,
        generated: generated,
      );
      expect(
        LibraryCompatibility.evaluate(
          installed,
          keyed.requiredLibraries.single,
        ),
        outcome,
      );
    }

    final reorder = await resolveKeySource(
      '$widgetSource\n'
      'class P extends StatelessWidget { const P({required this.itemKey, required this.otherKey, required this.reverse}); final Key itemKey; final Key otherKey; final bool reverse; Widget build(BuildContext context) => Row(children: reverse ? [NativeKeyWidget(key:otherKey), NativeKeyWidget(key:itemKey)] : [NativeKeyWidget(key:itemKey), NativeKeyWidget(key:otherKey)]); }',
    );
    final reordered = translateKeyProbe(reorder, catalog);
    expect(
      reordered.issues.where((issue) => !issue.code.isInformational),
      isEmpty,
      reason: reordered.issues.map((i) => i.message).join('\n'),
    );
    expect(reordered.dsl, contains('nativeKey'));
    final reorderFile = File('test/fixtures/native_key_custom_reorder.json');
    final reorderJson =
        '${jsonEncode({
          'dsl': reordered.dsl,
          'bindings': {for (final value in reordered.hoisted) value.key: value.mountSource((name) => name)},
        })}\n';
    if (Platform.environment['WRITE_NATIVE_KEY_FACTORIES'] == '1')
      reorderFile.writeAsStringSync(reorderJson);
    expect(reorderFile.readAsStringSync(), reorderJson);
    final factory = emitFactoryFunction(
      entry,
      nativeIndex: NativeCatalogIndex(catalog),
      publicName: true,
    );
    expect(factory, contains('key: RestageDecoders.nativeBinding<Key>('));
    final defaults = <String, String>{};
    String? defaultSlot;
    for (final (name, argument, prelude) in [
      ('omitted', '', ''),
      ('explicitNull', 'key:null', ''),
      ('parenthesizedNull', 'key:((null))', ''),
      ('constantNull', 'key:absentKey', ''),
      ('constantNullAlias', 'key:alias', 'const alias=(absentKey);'),
      ('borrowed', 'key:itemKey', ''),
    ]) {
      final defaultsProbe = await resolveKeySource(
        '$widgetSource\n'
        'const Key? absentKey=null;'
        'class P extends StatelessWidget {const P({required this.itemKey});final Key itemKey;Widget build(BuildContext context){$prelude return DefaultNativeKeyWidget($argument);}}',
      );
      final translated = translateKeyProbe(defaultsProbe, catalog);
      expect(
        translated.issues.where((issue) => !issue.code.isInformational),
        isEmpty,
        reason: translated.issues.map((i) => i.message).join('\n'),
      );
      defaults[name] = translated.dsl;
      if (translated.hoisted.isNotEmpty)
        defaultSlot = translated.hoisted.single.key;
      final tree = rfw.parseLibraryFile('widget Root=${translated.dsl};');
      expect(
        validateModelAgainstCatalog(
          tree,
          catalog,
          operations: translated.valueOperations,
          hostDataContract: hostDataContractOf(
            const [],
            hoisted: translated.hoisted,
          ),
        ),
        isEmpty,
      );
      final capability = deriveCapabilityManifest(
        tree,
        catalog,
        hoisted: translated.hoisted,
      ).manifest!;
      expect(
        capability.builtInFloor,
        name == 'borrowed' ? 24 : 1,
        reason: name,
      );
      expect(
        capability.requiredLibraries.single.minGenerated,
        name == 'omitted' ? 1 : 3,
        reason: name,
      );
      final requirement = capability.requiredLibraries.single;
      for (final generated in [1, 2, 3]) {
        final fit = BlobRenderCapabilityGate.evaluate(
          required: capability,
          installed: InstalledCapability(
            builtInCatalogVersion: name == 'borrowed' ? 24 : 1,
            installedLibraries: [
              InstalledLibrary(
                namespace: requirement.namespace,
                version: requirement.minVersion,
                generated: generated,
              ),
            ],
          ),
        );
        expect(
          fit.accepted,
          name == 'omitted' || generated >= 3,
          reason: '$name generated=$generated',
        );
      }
    }
    // A mounted surface carries a key that compares by value, so the widget
    // stays delivered with that key.
    for (final (argument, prelude, verdict) in [
      ("const ValueKey<String>('override')", '', null),
      ("(const ValueKey<String>('override'))", '', null),
      ('alias', "const alias=ValueKey<String>('override');", null),
    ]) {
      final override = await resolveKeySource(
        '$widgetSource\n'
        'class P extends StatelessWidget {const P();Widget build(BuildContext context){$prelude return DefaultNativeKeyWidget(key:$argument);}}',
      );
      final translated = translateKeyProbe(override, catalog);
      expect(
        [
          for (final island in translated.islands) island.id,
          for (final issue in translated.issues)
            if (!issue.code.isBuildNotice) issue.code.name,
        ],
        [if (verdict != null) verdict],
        reason: argument,
      );
      if (verdict == null) {
        expect(
          translated.dsl,
          startsWith('DefaultNativeKeyWidget(key: '),
          reason: argument,
        );
      }
    }
    // The key's value, without the placement the widget is named by.
    final presence = RegExp(
      r'key: (\{[^}]*\})',
    ).firstMatch(defaults['explicitNull']!)!.group(1)!;
    for (final (source, generated) in [
      (
        'widget Forward=DefaultNativeKeyWidget(key:args.key); widget Root=Forward();',
        1,
      ),
      (
        'widget Forward=DefaultNativeKeyWidget(key:args.key); widget Root=Forward(key:$presence);',
        3,
      ),
      (
        'widget Root=DefaultNativeKeyWidget(key:switch data.show {true:$presence,default:args.absent});',
        3,
      ),
      (
        'widget Root=DefaultNativeKeyWidget(key:switch data.show {true:args.absent,default:args.absent});',
        1,
      ),
    ]) {
      final capability = deriveCapabilityManifest(
        rfw.parseLibraryFile(source),
        catalog,
      ).manifest!;
      expect(capability.builtInFloor, 1, reason: source);
      expect(
        capability.requiredLibraries.single.minGenerated,
        generated,
        reason: source,
      );
    }
    final defaultsFile = File('test/fixtures/native_key_defaults.json');
    final defaultsJson =
        '${jsonEncode({'sources': defaults, 'slot': defaultSlot})}\n';
    if (Platform.environment['WRITE_NATIVE_KEY_FACTORIES'] == '1')
      defaultsFile.writeAsStringSync(defaultsJson);
    expect(defaultsFile.readAsStringSync(), defaultsJson);
    final factories = formatGeneratedDart(
      <String>[
        "// Generated by native_key_integration_test.dart.\nimport 'package:flutter/material.dart';\nimport 'package:flutter_svg/flutter_svg.dart';\nimport 'package:restage_core/restage_core.dart';\nimport 'package:restage_svg/src/native_values.dart';\nimport 'package:rfw/rfw.dart';\nimport 'native_key_widget.dart';\nimport 'package:rfw_catalog_schema/rfw_catalog_schema.dart' show WidgetBuilderContract, WidgetBuilderParameter;\nimport 'package:vector_graphics/src/vector_graphics.dart' show RenderingStrategy;\n",
        for (final catalog in [core, material, svg])
          for (final widget in catalog.widgets)
            emitFactoryFunction(
              widget,
              nativeIndex: NativeCatalogIndex(catalog),
              publicName: true,
            )!,
        factory!,
        emitFactoryFunction(
          allocated.widgets.singleWhere(
            (widget) => widget.name == 'DefaultNativeKeyWidget',
          ),
          nativeIndex: NativeCatalogIndex(catalog),
          publicName: true,
        )!,
      ].join('\n'),
      languageVersion: libraryLanguageVersion(library),
    );
    final file = File(
      '../restage_svg/test/fixtures/native_key_factories.g.dart',
    );
    if (Platform.environment['WRITE_NATIVE_KEY_FACTORIES'] == '1')
      file.writeAsStringSync(factories);
    expect(file.readAsStringSync(), factories);
  });
  for (final guarded in [false, true]) {
    test(
      guarded
          ? 'production compiler renders a guarded owner of an original key '
                'from the app'
          : 'production codegen builder emits a borrowed key through its catalog gate',
      () async {
        final source =
            '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';
part 'restage.generated/key_probe.restage.g.dart';
@Paywall(id: 'key_probe')
class KeyProbe extends StatelessWidget {
  const KeyProbe({required this.itemKey});
  final Key itemKey;
  Widget build(BuildContext context) => ${guarded ? 'Row(key:itemKey)' : "Text('item', key: itemKey)"};
}
''';
        final rw = await readerWriterWithFilesystemSources(
          rootPackage: 'apps_examples',
          includeFlutter: true,
        );
        rw.testing.writeString(
          AssetId('restage_core', 'lib/src/widget_catalog/catalog.json'),
          encodeCatalog(core),
        );
        rw.testing.writeString(
          AssetId('apps_examples', 'lib/paywalls/key_probe.dart'),
          source,
        );
        final result = await testBuilders(
          [const PackageSurfaceCompilerBuilder(BuilderOptions.empty)],
          {'apps_examples|lib/paywalls/key_probe.dart': source},
          rootPackage: 'apps_examples',
          readerWriter: rw,
          flattenOutput: true,
        );
        expect(result.succeeded, isTrue);
        final bundle = RestageSurfacePublicationBundle.fromJson(
          jsonDecode(
            rw.testing.readString(
              AssetId(
                'apps_examples',
                kRestageSurfacePublicationCompilerBundlePath,
              ),
            ),
          ),
        );
        expect(bundle.valid, isTrue, reason: bundle.errors.join('\n'));
        final bytes = bundle
            .ownedOutputs['assets/paywalls/screens/paywall_key_probe.rfw']!;
        final library = rfw.decodeLibraryBlob(Uint8List.fromList(bytes));
        final root = library.widgets.single.root as rfw.ConstructorCall;
        if (guarded) {
          expect(root.name, 'key__probe_Row_0');
          return;
        }
        expect(root.arguments['key'], isA<rfw.DataReference>());
        final sidecar = jsonDecode(
          utf8.decode(
            bundle
                .ownedOutputs['assets/paywalls/screens/paywall_key_probe.capability.json']!,
          ),
        );
        expect(sidecar['manifest']['builtInFloor'], 24);
      },
    );
  }
}
