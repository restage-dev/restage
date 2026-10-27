import 'dart:io';
import 'dart:convert';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:restage_codegen/src/builder_expression_lowering.dart';
import 'package:restage_codegen/src/installed_native_call.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/catalog_validator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/widget_builder_lowering.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;
import 'package:restage_compiler_core/restage_compiler_core.dart';
import 'package:restage_compiler_core/src/rfw_program_envelope.dart';
import 'package:test/test.dart';

import 'helpers.dart';

Future<String> _project(String body) async {
  final callback = await parseExpressionFromSourceForTest('''
import 'package:flutter/material.dart';
WidgetBuilder x() => (context) $body;
''', rootPackage: 'apps_examples') as FunctionExpression;
  final expressions =
      BuilderExpressionLowering(capture: (_) => throw StateError('capture'));
  late WidgetBuilderLowering builder;
  builder = WidgetBuilderLowering(
      expressions: expressions,
      contract: const WidgetBuilderContract(
          parameters: [WidgetBuilderParameter.buildContext]),
      scope: 'b0',
      translateBody: (body) {
        final value = (body as InstanceCreationExpression)
            .argumentList
            .arguments
            .single
            .argumentExpression;
        return 'SizedBox(width: ${builder.value(value)})';
      });
  final result = builder.lower(callback);
  expect(expressions.parameters.containsKey('arg0'), isFalse);
  expect(expressions.nodes.any((node) => node.type.containsNative), isFalse);
  return result;
}

void main() {
  test(
      'catalog LayoutBuilder stages a context input before its returned widget',
      () async {
    final expression = await parseExpressionFromSourceForTest('''
import 'package:flutter/material.dart' as f;
f.Widget x() => f.LayoutBuilder(builder: (context, constraints) {
  final color = f.MaterialColor(context.hashCode, <int, f.Color>{});
  return f.ColoredBox(color: color);
});
''', rootPackage: 'apps_examples');
    final catalog = decodeCatalog(
        File('../restage_core/lib/src/widget_catalog/catalog.json')
            .readAsStringSync());
    final result =
        ExpressionTranslator(catalog: catalog, helpers: HelperRegistry())
            .translate(expression, hoistInMount: true);
    expect(result.issues.where((issue) => !issue.code.isInformational), isEmpty,
        reason: result.issues.map((issue) => issue.message).join('; '));
    final call = result.hoisted
        .singleWhere((value) => value.nativeCall != null)
        .nativeCall!;
    expect(call.contract.call!.inputs.single.nativeType,
        builderContextNativeValueType.nativeType);
    expect(result.dsl, contains('LayoutBuilder(builder:'));
    expect(result.dsl, contains('nativeLocal'));
    final library = rfw.parseLibraryFile(
        'import restage.core; widget Paywall = ${result.dsl};');
    final context = SurfaceScreenHostDataSchema({
      for (final value in result.hoisted)
        value.key:
            SurfaceScreenHostDataNativeBindingShapeV1(value.nativeContract!),
    });
    final operations = nativeCallOperations(context, {});
    expect(
        validateModelAgainstCatalog(library, catalog, operations: operations),
        isEmpty);
    expect(() => validateModelAgainstCatalog(library, catalog),
        throwsFormatException);
    final scope = RfwProgramScope(library.widgets.map((widget) => widget.root),
        operations: operations);
    final root = library.widgets.single.root as rfw.ConstructorCall;
    final layout =
        catalog.widgets.singleWhere((widget) => widget.name == 'LayoutBuilder');
    final contract = layout.properties
        .singleWhere((property) => property.name == 'builder')
        .builderContract!;
    validateRfwBuilderContract(root.arguments['builder'], contract,
        scope: scope);
    final capability =
        deriveSurfaceCapability(library, catalog, operations: operations);
    expect(capability.builtInFloor, 24);
    final events = SurfaceScreenEventSchema(events: []);
    expect(surfaceScreenContractGaps(library, events: events, context: context),
        isEmpty);
    final resolution = rfw.RfwCatalogOccurrenceResolutionInput(
        artifactProvenance: 'callback.context.artifact',
        sourceLibraryIdentity: 'callback.context.library',
        sourceDeclarationIdentity: 'callback.context.root',
        renderEntryNames: [
          'Paywall'
        ],
        localSymbols: [
          rfw.RfwCatalogLocalSymbol(name: 'Paywall')
        ],
        catalogConstructors: [
          for (final widget in catalog.widgets)
            rfw.RfwCatalogConstructorProvenance(
                constructorName: widget.name,
                catalogLibraryNamespace: widget.library.namespace,
                catalogWidgetWireId: widget.wireId),
        ]);
    final blob = rfw.encodeLibraryBlob(library);
    final hash = CapabilitySidecar.hashBlob(blob);
    final payload = BlobSurfacePayload(minClient: 24, blob: blob);
    final publication = SurfacePublication(
        surface: Surface.paywall,
        slug: 'callback-context',
        sourceKind: SurfaceSourceKind.paywall,
        payloadKind: SurfacePayloadKind.blob,
        payloadContentHash: payload.contentHash,
        compiledScreenContracts: {
          hash: SurfaceCompiledScreenContractV1(
              context: context,
              events: events,
              catalogResolution: resolution,
              catalog: catalog)
        });
    final sidecar = utf8.encode(jsonEncode(CapabilitySidecar(
            blobSha256: hash,
            manifest: CapabilityManifest(
                builtInFloor: capability.builtInFloor,
                requiredLibraries: capability.requiredLibraries))
        .toJson()));
    final manifest = SurfacePublicationManifest(publications: [
      SurfacePublicationManifestEntry(publication: publication, artifacts: [
        SurfacePublicationArtifact(
            contentHash: hash,
            id: 'callback-context',
            path: 'screen.rfw',
            role: SurfacePublicationArtifactRole.screenBlob),
        SurfacePublicationArtifact(
            contentHash: CapabilitySidecar.hashBlob(sidecar),
            id: 'callback-context',
            path: 'screen.capability.json',
            role: SurfacePublicationArtifactRole.capabilitySidecar),
      ]),
    ]);
    final fit = manifest
        .validateArtifactClosure(
            {'screen.rfw': blob, 'screen.capability.json': sidecar})
        .single
        .projectFitRequirement();
    expect(fit.requiredContext.inputs.keys, context.inputs.keys);
    expect(
        (fit.requiredContext.inputs[call.key]
                as SurfaceScreenHostDataNativeBindingShapeV1)
            .contract,
        call.contract);
    expect(
        () => deriveSurfaceCapability(library, catalog), throwsFormatException);
  });

  test('unread context aliases leave the existing callback bytes unchanged',
      () async {
    expect(
        await _project(
            '{ final alias = context; return SizedBox(width: 3.0); }'),
        await _project('=> SizedBox(width: 3.0)'));
    expect(
        await _project(
            '{ final alias = context; return SizedBox(width: MediaQuery.sizeOf(alias).width); }'),
        await _project('=> SizedBox(width: MediaQuery.sizeOf(context).width)'));
  });

  test('mutable context aliases cannot retain a stale inherited projection',
      () async {
    await expectLater(
        _project(
            '{ var alias = context; alias = context; return SizedBox(width: MediaQuery.sizeOf(alias).width); }'),
        throwsA(isA<BuilderLoweringException>()));
  });

  test(
      'callback nominal identity agrees with installed Dart type and root context stays refused',
      () async {
    final expression = await parseExpressionFromSourceForTest('''
import 'package:flutter/widgets.dart';
BuildContext Function() x(BuildContext root) => () => root;
''', rootPackage: 'apps_examples') as FunctionExpression;
    final root = (expression.body as ExpressionFunctionBody).expression;
    expect(installedNativeTypeId(root.staticType!),
        builderContextNativeValueType.nativeType);
    final lowering =
        BuilderExpressionLowering(capture: (_) => throw StateError('capture'));
    expect(
        () => lowering.lowerInstalledNativeCall(expression,
            resultType: const ValueType.native('callback'), install: (_) {}),
        throwsA(isA<BuilderLoweringException>()));
  });
}
