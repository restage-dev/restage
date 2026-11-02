import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_style/dart_style.dart';
import 'package:build/build.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:restage_codegen/src/capability_derivation.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/installed_native_call.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/source_state.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_codegen/src/surface_publication/package_surface_compiler_builder.dart';
import 'package:restage_codegen/src/measurement/measurement_source_discovery.dart';
import 'package:restage_codegen/src/measurement/measurement_route_emission.dart';
import 'package:restage_codegen/src/measurement/measurement_rfw_route_composer.dart';
import 'package:restage_compiler_core/restage_compiler_core.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;
import 'package:test/test.dart';

import 'helpers.dart';

Catalog _catalog() {
  final catalogs = [
    for (final package in ['restage_core', 'restage_material'])
      decodeCatalog(
        File(
          '../$package/lib/src/widget_catalog/catalog.json',
        ).readAsStringSync(),
      ),
  ];
  return Catalog(
    schemaVersion: kSupportedSchemaVersion,
    generatedAt: '',
    libraries: {for (final catalog in catalogs) ...catalog.libraries},
    widgets: [for (final catalog in catalogs) ...catalog.widgets],
    structuredTypes: [
      for (final catalog in catalogs) ...catalog.structuredTypes,
    ],
    unions: [for (final catalog in catalogs) ...catalog.unions],
  );
}

Future<TranslationResult> _translate(
  String source, {
  String className = 'NativeEventSource',
}) async {
  final probe = await parseMethodExpressionFromSourceForTest(
    source,
    className: className,
    rootPackage: 'apps_examples',
  );
  return ExpressionTranslator(
    catalog: _catalog(),
    helpers: HelperRegistry(),
  ).translate(
    probe.expression,
    hoistInMount: true,
    rootParams: [
      for (final parameter
          in probe.classes[className]!.unnamedConstructor!.formalParameters)
        if (parameter is FieldFormalParameterElement)
          RootContextParam(
            name: parameter.name!,
            type: parameter.type,
            typeCode: parameter.type.getDisplayString(),
            kind: RootContextParamKind.named,
            hostDataShape: null,
            field: parameter.field,
            isRequired: parameter.isRequired,
            defaultValueCode: null,
            hasNullDefault: false,
          ),
    ],
  );
}

void main() {
  test(
    'ordinary native events emit installed callbacks through real event slots',
    () async {
      final source = File(
        '../restage_material/test/fixtures/native_event_source.dart',
      ).readAsStringSync();
      final output = StringBuffer("part of 'native_event_source.dart';\n");
      for (final (className, prefix, parameters, count) in [
        (
          'NativeEventSource',
          'nativeEvent',
          'required f.TabController tabs, required f.ScrollController scroll, required f.VoidCallback? borrowed',
          2,
        ),
        (
          'NativeLexicalEventSource',
          'nativeLexical',
          'required f.ValueChanged<int> observer',
          1,
        ),
      ]) {
        final result = await _translate(source, className: className);
        expect(
          result.issues.where((issue) => !issue.code.isInformational),
          isEmpty,
          reason: result.issues.map((issue) => issue.message).join('; '),
        );
        expect(result.dsl, contains('nativeEvent:'));
        expect(
          result.hoisted.where((value) => value.nativeCall != null),
          hasLength(count),
        );
        final library = rfw.parseLibraryFile(
          'import restage.core; import restage.material; widget Root = ${result.dsl};',
        );
        final capability = deriveCapabilityManifest(
          library,
          _catalog(),
          hoisted: result.hoisted,
        );
        expect(capability.manifest!.builtInFloor, 24);
        output.writeln('const ${prefix}Dsl = ${jsonEncode(result.dsl)};');
        output.writeln('Map<String, Object?> ${prefix}Data() => {');
        for (final value in result.hoisted) {
          if (value.nativeContract!.call == null)
            output.writeln(
              '${jsonEncode(value.key)}: ${jsonEncode(value.nativeContract!.reference(value.key))},',
            );
        }
        output.writeln('};');
        final nativeFactories = <String, String>{};
        for (final value in result.hoisted) {
          final call = value.nativeCall;
          if (call == null) continue;
          final name = '_${prefix}${value.key}Native';
          nativeFactories[value.key] = name;
          output.writeln(
            'r.NativeCallAdapter $name() => '
            '${call.adapterSource(core: 'r.', shared: 's.')};',
          );
        }
        output.writeln(
          'Map<String, r.NativeBinding<Object?>> ${prefix}Bindings({$parameters}) => {',
        );
        for (final value in result.hoisted) {
          final factory = nativeFactories[value.key];
          final installed = factory == null ? null : '$factory()';
          output.writeln(
            '${jsonEncode(value.key)}: r.NativeBinding(contract: ${nativeContractSource(value.nativeContract!, 's.')}, value: ${installed ?? value.mountSource((name) => name)}),',
          );
        }
        output.writeln('};');
      }
      final generated = DartFormatter(
        languageVersion: Version(3, 5, 0),
      ).format(output.toString());
      final file = File(
        '../restage_material/test/fixtures/native_event_source.g.dart',
      );
      if (Platform.environment['WRITE_NATIVE_EVENT_FIXTURE'] == '1')
        file.writeAsStringSync(generated);
      expect(file.readAsStringSync(), generated);
    },
  );

  test(
    'canonical publication installs ordinary event adapters in the generated mount',
    () async {
      final source =
          "import 'package:restage/restage.dart' as rs;\n${File('../restage_material/test/fixtures/native_event_source.dart').readAsStringSync()}"
              .replaceFirst(
                "part 'native_event_source.g.dart';",
                "part 'restage.generated/native_events.restage.g.dart';",
              )
              .replaceFirst(
                'class NativeEventSource',
                '@rs.Screen(id: "native_events", surface: rs.Surface.general)\nclass NativeEventSource',
              );
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      final result = await testBuilder(
        const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
        {'apps_examples|lib/native_events.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      final bundle = RestageSurfacePublicationBundle.fromJson(
        jsonDecode(
          readerWriter.testing.readString(
            AssetId(
              'apps_examples',
              kRestageSurfacePublicationCompilerBundlePath,
            ),
          ),
        ),
      );
      expect(bundle.valid, isTrue, reason: bundle.errors.join('\n'));
      final generated = utf8.decode(
        bundle
            .ownedOutputs['lib/restage.generated/native_events.restage.g.dart']!,
      );
      expect(generated, contains('NativeCallAdapter('));
      expect(generated, contains('animateTo(1)'));
      expect(generated, contains(kNativeVoidCallbackType));
      expect(
        bundle.artifacts.keys,
        contains('assets/general/screens/native_events.rfw'),
      );
    },
  );

  test(
    'production discovery and final composition preserve native event measurement routes',
    () async {
      final text =
          File('../restage_material/test/fixtures/native_event_source.dart')
              .readAsStringSync()
              .replaceAll(RegExp(r"^part '[^']+';\n", multiLine: true), '')
              .replaceFirst(
                'class NativeEventSource',
                '@rs.Screen(id: "nativeEvents", surface: rs.Surface.general)\nclass NativeEventSource',
              );
      final probe = await parseMethodExpressionFromSourceForTest(
        "import 'package:restage/restage.dart' as rs;\n$text",
        className: 'NativeEventSource',
        rootPackage: 'apps_examples',
      );
      final libraryElement =
          (probe.expression.root as CompilationUnit).declaredFragment!.element;
      final source = probe.classes['NativeEventSource']!;
      final issues = <Issue>[];
      final blueprint = await extractSourceBuildBlueprint(
        sourceClass: source,
        library: libraryElement,
        astNodeFor: resolvedAstNodeFor,
        issues: issues,
        location: libraryElement.identifier,
        catalog: _catalog(),
      );
      expect(issues, isEmpty);
      final discovery = MeasurementSourceDiscovery.discover(
        MeasurementSourceDiscoveryInput(
          authority: MeasurementSourceAuthority.screen,
          sourceClass: source,
          rootExpression: blueprint!.rootExpression,
          catalog: _catalog(),
          rootLocalBindings: blueprint.inlined.localBindings,
          rootHelpers: blueprint.inlined.helpers,
        ),
      );
      expect(
        discovery.disposition,
        MeasurementSourceDiscoveryDisposition.accepted,
        reason: discovery.rejectionReason,
      );
      expect(discovery.events, hasLength(3));
      final codes = {
        for (final (index, node) in discovery.nodes.indexed)
          node.structuralOccurrenceKey: CodeIdentityId(
            'code.native_event.$index',
          ),
      };
      final plan = _routePlan(discovery, codes);
      final emission = MeasurementRouteEmissionPlan.fromDiscovery(
        discovery: discovery,
        routePlan: plan,
        codeIdentityByStructuralOccurrenceKey: codes,
      );
      final result =
          ExpressionTranslator(
            catalog: _catalog(),
            helpers: HelperRegistry(),
            measurementRouteEmissionPlan: emission,
          ).translate(
            blueprint.rootExpression,
            rootParams: blueprint.rootParams,
            rootInlined: blueprint.inlined,
            buildContextParameter: blueprint.buildContextParameter,
            rootBuildArguments: blueprint.buildArguments,
            hoistInMount: true,
          );
      expect(
        result.issues.where((issue) => !issue.code.isInformational),
        isEmpty,
        reason: result.issues.map((issue) => issue.message).join('; '),
      );
      expect(result.dsl, contains('measurement: event'));
      final library = rfw.parseLibraryFile(
        'import restage.core; import restage.material; widget Surface = ${result.dsl};',
      );
      final composed = MeasurementRfwRouteComposer.composeBlob(
        blob: rfw.encodeLibraryBlob(library),
        routePlan: plan,
      );
      expect(
        composed.generatedReferences,
        plan.routes.map((route) => route.generatedReferenceId.value).toSet(),
      );
      final schema = SurfaceScreenHostDataSchema({
        for (final value in result.hoisted)
          value.key: SurfaceScreenHostDataNativeBindingShapeV1(
            value.nativeContract!,
          ),
      });
      expect(
        surfaceScreenContractGaps(
          rfw.decodeLibraryBlob(composed.blob),
          events: SurfaceScreenEventSchema(events: []),
          context: schema,
        ),
        isEmpty,
      );
    },
  );

  test(
    'inline span no-argument callbacks consume the same installed boundary',
    () async {
      final result = await _translate("""
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
class NativeEventSource extends StatelessWidget {
  const NativeEventSource({required this.tabs});
  final TabController tabs;
  @override Widget build(BuildContext context) => Text.rich(TextSpan(
    text: 'Tap', recognizer: TapGestureRecognizer()..onTap = () => tabs.animateTo(1)));
}
""");
      expect(
        result.issues.where((issue) => !issue.code.isInformational),
        isEmpty,
        reason: result.issues.map((issue) => issue.message).join('; '),
      );
      final capability = deriveCapabilityManifest(
        rfw.parseLibraryFile(
          'import restage.core; widget Root = ${result.dsl};',
        ),
        _catalog(),
        hoisted: result.hoisted,
      );
      expect(capability.manifest!.builtInFloor, 24);
    },
  );

  test(
    'effectful callback getters and callback-producing calls stay refused',
    () async {
      for (final value in ['getCallback()', 'callbackGetter']) {
        final result = await _translate('''
import 'package:flutter/material.dart' as f;
class NativeEventSource extends f.StatelessWidget {
  const NativeEventSource();
  f.VoidCallback getCallback() => () {};
  f.VoidCallback get callbackGetter => () {};
  @override f.Widget build(f.BuildContext context) => f.FilledButton(onPressed: $value, child: const f.Text('Tap'));
}
''');
        expect(
          result.issues.where((issue) => !issue.code.isInformational),
          isNotEmpty,
          reason: value,
        );
      }
    },
  );
}

MeasurementPublicationRoutePlanV1 _routePlan(
  MeasurementSourceDiscoveryResult discovery,
  Map<String, CodeIdentityId> codes,
) {
  final edge = ArtifactOccurrenceEdgeToken('edge.native_event');
  return MeasurementPublicationRoutePlanV1(
    surfaceId: SurfaceId('surface.native_event'),
    analyticsSurfaceKey: AnalyticsSurfaceKey('native_event'),
    deliverySurfaceType: DeliverySurfaceTypeId('surface.general'),
    minimumMeasurementClient: 1,
    completeManifestId: MeasurementManifestId('manifest.native_event'),
    privacyPolicyRevisionId: AuthorityRevisionId('privacy.native_event'),
    collectionBudgetRevisionId: AuthorityRevisionId('budget.native_event'),
    artifacts: [
      MeasurementPublicationRouteArtifactV1(
        artifactId: ArtifactId('artifact.native_event'),
        artifactKind: ArtifactKindId('rfw.blob'),
        occurrenceEdgeToken: edge,
        localManifestId: MeasurementManifestId('manifest.native_event-local'),
      ),
    ],
    codeIdentityBindings: [
      for (final (index, code) in codes.values.indexed)
        CodeIdentityBindingV1(
          codeIdentityId: code,
          canonicalNodeTokenId: NodeTokenId('node.native_event.$index'),
        ),
    ],
    nodes: [
      for (final node in discovery.nodes)
        MeasurementPublicationDraftNodeV1(
          codeIdentityId: codes[node.structuralOccurrenceKey]!,
          parentCodeIdentityId: codes[node.parentStructuralOccurrenceKey],
          artifactOccurrenceEdgeToken: edge,
        ),
    ],
    events: [
      for (final (index, event) in discovery.events.indexed)
        MeasurementPublicationDraftEventV1(
          nodeCodeIdentityId: codes[event.node.structuralOccurrenceKey]!,
          sourceEventIdentity: event.resolvedEvent.sourceEventIdentity,
          lineageId: PointLineageId('lineage.native_event.$index'),
          generatedReferenceId: GeneratedReferenceId(
            'reference.native_event.$index',
          ),
          dartSymbol: GeneratedDartSymbol('native_eventPoint$index'),
          displayMetadataRef: DisplayMetadataRef('display.native_event.$index'),
          normalizedInteractionKind: NormalizedInteractionKind.activate,
          privacyClass: MeasurementPrivacyClass.nonSensitive,
          semanticValueClass: SemanticValueClass.activityOnly,
          collectionClass: MeasurementCollectionClass.tier1KeepAll,
        ),
    ],
    routeSeeds: [
      for (final (index, _) in discovery.events.indexed)
        MeasurementPublicationDraftRouteSeedV1(
          generatedReferenceId: GeneratedReferenceId(
            'reference.native_event.$index',
          ),
          artifactOccurrenceEdgeToken: edge,
        ),
    ],
    presentations: const [],
    presentationRouteSeeds: const [],
    lineageIntents: [
      for (final (index, _) in discovery.events.indexed)
        MeasurementPublicationLineageIntentV1(
          transitionId: LineageTransitionId('transition.native_event.$index'),
          operation: LineageOperation.create,
          authority: LineageTransitionAuthority.exactToken,
          next: [
            MeasurementPublicationCurrentEndpointIntentV1(
              generatedReferenceId: GeneratedReferenceId(
                'reference.native_event.$index',
              ),
              lineageId: PointLineageId('lineage.native_event.$index'),
            ),
          ],
        ),
    ],
  );
}
