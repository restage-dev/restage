import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:dart_style/dart_style.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/capability_derivation.dart';
import 'package:restage_compiler_core/restage_compiler_core.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/installed_native_call.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/measurement/measurement_source_discovery.dart';
import 'package:restage_codegen/src/measurement/measurement_route_emission.dart';
import 'package:restage_codegen/src/measurement/measurement_rfw_route_composer.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/rfw_formats.dart' as fmt;
import 'package:restage_codegen/src/source_state.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const _gestureKinds = [
  'Tap',
  'Double',
  'Long',
  'Borrowed',
  'Live',
  'Tearoff',
  'Context'
];

void main() {
  test('gesture bindings are generated from ordinary resolved Flutter source',
      () async {
    final library = await _resolvedGestureLibrary();
    final catalog = decodeCatalog(
        File('../restage_core/lib/src/widget_catalog/catalog.json')
            .readAsStringSync());
    final output = StringBuffer("part of 'gesture_bindings_source.dart';\n");
    for (final kind in _gestureKinds) {
      final issues = <Issue>[];
      final blueprint = await extractSourceBuildBlueprint(
          sourceClass: library.classes
              .singleWhere((element) => element.name == 'Gesture${kind}Screen'),
          library: library,
          astNodeFor: resolvedAstNodeFor,
          issues: issues,
          location: 'package:apps_examples/_expr_probe.dart',
          catalog: catalog);
      expect(issues, isEmpty);
      expect(blueprint, isNotNull);
      final result =
          ExpressionTranslator(catalog: catalog, helpers: HelperRegistry())
              .translate(blueprint!.rootExpression,
                  rootParams: blueprint.rootParams,
                  rootState: blueprint.state,
                  rootEventHandlers: blueprint.eventHandlers,
                  buildContextParameter: blueprint.buildContextParameter,
                  rootInlined: blueprint.inlined,
                  rootBuildArguments: blueprint.buildArguments,
                  hoistInMount: true);
      expect(
          result.issues.where((issue) => !issue.code.isInformational), isEmpty,
          reason: result.issues.map((issue) => issue.message).join('; '));
      expect(result.dsl, isNotEmpty);
      final artifact = fmt.parseLibraryFile(
          'import restage.core; widget Surface = ${result.dsl};');
      expect(
          surfaceScreenContractGaps(artifact,
              events: SurfaceScreenEventSchema(events: []),
              context: _nativeSchema(result)),
          isEmpty);
      output.writeln(
          'const gesture${kind}Library = ${jsonEncode('import restage.core; widget Surface = ${result.dsl};').replaceAll(r'$', r'\$')};');
      output.writeln(
          'Map<String, r.NativeBinding<Object?>> gesture${kind}Bindings(Gesture${kind}Screen source) => {');
      for (final value in result.hoisted) {
        final contract = value.nativeContract!;
        final installed =
            value.nativeCall?.adapterSource(core: 'r.', shared: 's.');
        output.writeln(
            '${jsonEncode(value.key)}: r.NativeBinding(contract: ${nativeContractSource(contract, 's.')}, value: ${installed ?? value.mountSource((name) => 'source.$name')}),');
      }
      output.writeln('};');
      output.writeln(
          'Map<String, Object?> gesture${kind}Context() => ${jsonEncode({
            for (final value in result.hoisted)
              value.key: {
                'kind': 'nativeBinding',
                'key': value.key,
                'type': value.nativeContract!.type,
                'nullable': value.nativeContract!.nullable,
              }
          })};');
    }
    final generated = DartFormatter(languageVersion: Version(3, 5, 0))
        .format(output.toString());
    final fixture =
        File('../restage/test/fixtures/gesture_bindings_source.g.dart');
    if (Platform.environment['WRITE_GESTURE_BINDINGS_FIXTURE'] == '1')
      fixture.writeAsStringSync(generated);
    expect(fixture.readAsStringSync(), generated);
  });
  test('production gesture discovery composes exact native callback routes',
      () async {
    final library = await _resolvedGestureLibrary();
    final catalog = decodeCatalog(
        File('../restage_core/lib/src/widget_catalog/catalog.json')
            .readAsStringSync());
    final output = StringBuffer("part of 'gesture_bindings_source.dart';\n");
    for (final kind in ['Tap', 'Borrowed']) {
      final source = library.classes
          .singleWhere((element) => element.name == 'Gesture${kind}Screen');
      final issues = <Issue>[];
      final blueprint = await extractSourceBuildBlueprint(
          sourceClass: source,
          library: library,
          astNodeFor: resolvedAstNodeFor,
          issues: issues,
          location: 'package:apps_examples/_expr_probe.dart',
          catalog: catalog);
      expect(issues, isEmpty);
      final discovery = MeasurementSourceDiscovery.discover(
          MeasurementSourceDiscoveryInput(
              authority: MeasurementSourceAuthority.screen,
              sourceClass: source,
              rootExpression: blueprint!.rootExpression,
              catalog: catalog,
              rootLocalBindings: blueprint.inlined.localBindings,
              rootHelpers: blueprint.inlined.helpers));
      expect(
          discovery.disposition, MeasurementSourceDiscoveryDisposition.accepted,
          reason: discovery.rejectionReason);
      expect(discovery.events, hasLength(kind == 'Tap' ? 7 : 0));
      final codes = {
        for (final (index, node) in discovery.nodes.indexed)
          node.structuralOccurrenceKey: CodeIdentityId('code.gesture.$index')
      };
      final plan = _routePlan(discovery, codes);
      final emission = MeasurementRouteEmissionPlan.fromDiscovery(
          discovery: discovery,
          routePlan: plan,
          codeIdentityByStructuralOccurrenceKey: codes);
      final result = ExpressionTranslator(
              catalog: catalog,
              helpers: HelperRegistry(),
              measurementRouteEmissionPlan: emission)
          .translate(blueprint.rootExpression,
              rootParams: blueprint.rootParams,
              buildContextParameter: blueprint.buildContextParameter,
              rootInlined: blueprint.inlined,
              rootBuildArguments: blueprint.buildArguments,
              hoistInMount: true);
      expect(
          result.issues.where((issue) => !issue.code.isInformational), isEmpty,
          reason: result.issues.map((issue) => issue.message).join('; '));
      final wireLibrary = fmt.parseLibraryFile(
          'import restage.core; widget Surface = ${result.dsl};');
      final composed = MeasurementRfwRouteComposer.composeBlob(
          blob: fmt.encodeLibraryBlob(wireLibrary), routePlan: plan);
      expect(composed.generatedReferences,
          plan.routes.map((route) => route.generatedReferenceId.value).toSet());
      expect(
          surfaceScreenContractGaps(fmt.decodeLibraryBlob(composed.blob),
              events: SurfaceScreenEventSchema(events: []),
              context: _nativeSchema(result)),
          isEmpty);
      output.writeln(
          'const gestureMeasured${kind}Blob = ${jsonEncode(base64Encode(composed.blob))};');
      output.writeln(
          'Map<String, r.NativeBinding<Object?>> gestureMeasured${kind}Bindings(Gesture${kind}Screen source) => {');
      for (final value in result.hoisted) {
        output.writeln(
            '${jsonEncode(value.key)}: r.NativeBinding(contract: ${nativeContractSource(value.nativeContract!, 's.')}, value: ${value.nativeCall?.adapterSource(core: 'r.', shared: 's.') ?? value.mountSource((name) => 'source.$name')}),');
      }
      output.writeln('};');
      output.writeln(
          'Map<String, Object?> gestureMeasured${kind}Context() => ${jsonEncode({
            for (final value in result.hoisted)
              value.key: {
                'kind': 'nativeBinding',
                'key': value.key,
                'type': value.nativeContract!.type,
                'nullable': value.nativeContract!.nullable
              }
          })};');
      output.writeln(
          'const Map<String, String> gestureMeasured${kind}Routes = ${jsonEncode({
            for (final (index, event) in discovery.events.indexed)
              event.resolvedEvent.declarationProvenance.memberName: plan.routes
                  .singleWhere((route) =>
                      route.generatedReferenceId.value ==
                      'reference.gesture.$index')
                  .carrier
          })};');
    }
    final generated = DartFormatter(languageVersion: Version(3, 5, 0))
        .format(output.toString());
    final fixture = File('../restage/test/fixtures/gesture_measurement.g.dart');
    if (Platform.environment['WRITE_GESTURE_BINDINGS_FIXTURE'] == '1')
      fixture.writeAsStringSync(generated);
    expect(fixture.readAsStringSync(), generated);
  });
  test(
      'native gesture declarations require client24 with installed host schema',
      () async {
    final library = await _resolvedGestureLibrary();
    final catalog = decodeCatalog(
        File('../restage_core/lib/src/widget_catalog/catalog.json')
            .readAsStringSync());
    final floors = <String, int>{};
    for (final kind in _gestureKinds) {
      final issues = <Issue>[];
      final blueprint = await extractSourceBuildBlueprint(
          sourceClass: library.classes
              .singleWhere((element) => element.name == 'Gesture${kind}Screen'),
          library: library,
          astNodeFor: resolvedAstNodeFor,
          issues: issues,
          location: library.identifier,
          catalog: catalog);
      expect(issues, isEmpty);
      final result =
          ExpressionTranslator(catalog: catalog, helpers: HelperRegistry())
              .translate(blueprint!.rootExpression,
                  rootParams: blueprint.rootParams,
                  buildContextParameter: blueprint.buildContextParameter,
                  rootInlined: blueprint.inlined,
                  rootBuildArguments: blueprint.buildArguments,
                  hoistInMount: true);
      expect(
          result.issues.where((issue) => !issue.code.isInformational), isEmpty);
      final artifact = fmt.parseLibraryFile(
          'import restage.core; widget Surface = ${result.dsl};');
      final capability =
          deriveCapabilityManifest(artifact, catalog, hoisted: result.hoisted);
      floors[kind] = capability.manifest!.builtInFloor;
    }
    expect(floors, {for (final kind in _gestureKinds) kind: 24});
  });
}

MeasurementPublicationRoutePlanV1 _routePlan(
    MeasurementSourceDiscoveryResult discovery,
    Map<String, CodeIdentityId> codes) {
  final edge = ArtifactOccurrenceEdgeToken('edge.gesture');
  return MeasurementPublicationRoutePlanV1(
      surfaceId: SurfaceId('surface.gesture'),
      analyticsSurfaceKey: AnalyticsSurfaceKey('gesture'),
      deliverySurfaceType: DeliverySurfaceTypeId('surface.general'),
      minimumMeasurementClient: 1,
      completeManifestId: MeasurementManifestId('manifest.gesture'),
      privacyPolicyRevisionId: AuthorityRevisionId('privacy.gesture'),
      collectionBudgetRevisionId: AuthorityRevisionId('budget.gesture'),
      artifacts: [
        MeasurementPublicationRouteArtifactV1(
            artifactId: ArtifactId('artifact.gesture'),
            artifactKind: ArtifactKindId('rfw.blob'),
            occurrenceEdgeToken: edge,
            localManifestId: MeasurementManifestId('manifest.gesture-local'))
      ],
      codeIdentityBindings: [
        for (final (index, code) in codes.values.indexed)
          CodeIdentityBindingV1(
              codeIdentityId: code,
              canonicalNodeTokenId: NodeTokenId('node.gesture.$index'))
      ],
      nodes: [
        for (final node in discovery.nodes)
          MeasurementPublicationDraftNodeV1(
              codeIdentityId: codes[node.structuralOccurrenceKey]!,
              parentCodeIdentityId: codes[node.parentStructuralOccurrenceKey],
              artifactOccurrenceEdgeToken: edge)
      ],
      events: [
        for (final (index, event) in discovery.events.indexed)
          MeasurementPublicationDraftEventV1(
              nodeCodeIdentityId: codes[event.node.structuralOccurrenceKey]!,
              sourceEventIdentity: event.resolvedEvent.sourceEventIdentity,
              lineageId: PointLineageId('lineage.gesture.$index'),
              generatedReferenceId:
                  GeneratedReferenceId('reference.gesture.$index'),
              dartSymbol: GeneratedDartSymbol('gesturePoint$index'),
              displayMetadataRef: DisplayMetadataRef('display.gesture.$index'),
              normalizedInteractionKind: NormalizedInteractionKind.activate,
              privacyClass: MeasurementPrivacyClass.nonSensitive,
              semanticValueClass: SemanticValueClass.activityOnly,
              collectionClass: MeasurementCollectionClass.tier1KeepAll)
      ],
      routeSeeds: [
        for (final (index, _) in discovery.events.indexed)
          MeasurementPublicationDraftRouteSeedV1(
              generatedReferenceId:
                  GeneratedReferenceId('reference.gesture.$index'),
              artifactOccurrenceEdgeToken: edge)
      ],
      presentations: const [],
      presentationRouteSeeds: const [],
      lineageIntents: [
        for (final (index, _) in discovery.events.indexed)
          MeasurementPublicationLineageIntentV1(
              transitionId: LineageTransitionId('transition.gesture.$index'),
              operation: LineageOperation.create,
              authority: LineageTransitionAuthority.exactToken,
              next: [
                MeasurementPublicationCurrentEndpointIntentV1(
                    generatedReferenceId:
                        GeneratedReferenceId('reference.gesture.$index'),
                    lineageId: PointLineageId('lineage.gesture.$index'))
              ])
      ]);
}

Future<LibraryElement> _resolvedGestureLibrary() async {
  final source = File('../restage/test/fixtures/gesture_bindings_source.dart')
      .readAsStringSync()
      .replaceAll(RegExp(r"^part '[^']+';\n", multiLine: true), '');
  final expression = await parseExpressionFromSourceForTest(
      '$source\nObject x() => 0;',
      rootPackage: 'apps_examples');
  final library =
      (expression.root as CompilationUnit).declaredFragment!.element;
  expect(library.identifier, 'package:apps_examples/_expr_probe.dart');
  return library;
}

SurfaceScreenHostDataSchema _nativeSchema(TranslationResult result) =>
    SurfaceScreenHostDataSchema({
      for (final value in result.hoisted)
        value.key:
            SurfaceScreenHostDataNativeBindingShapeV1(value.nativeContract!)
    });
