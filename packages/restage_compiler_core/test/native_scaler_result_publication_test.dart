import 'dart:convert';
import 'dart:io';

import 'package:restage_compiler_core/restage_compiler_core.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;
import 'package:test/test.dart';

void main() {
  final catalog = decodeCatalog(
      File('../restage_core/lib/src/widget_catalog/catalog.json')
          .readAsStringSync());
  for (final widgetName in ['Text', 'TextRich']) {
    for (final installedCall in [false, true]) {
      test(
          '$widgetName admits a closed native scaler result, call=$installedCall',
          () {
        const type = ValueType.native('flutter.TextScaler', nullable: true);
        const borrowed =
            NativeBindingContract(type: 'flutter.TextScaler', nullable: true);
        const callable = NativeBindingContract(
            type: 'installed.scaler',
            call: NativeCallContract(
                inputs: [], result: type, implementation: 'test.scaler.v1'));
        final key = installedCall ? 'makeScaler' : 'scaler';
        final declaration = installedCall ? callable : borrowed;
        final values = installedCall
            ? ValueProgram(nodes: [
                ValueNode('native.call', type, value: {
                  'binding': key,
                  'contract': callable.toJson(),
                  'captures': <String, String>{},
                })
              ], root: 0)
            : const ValueProgram(
                nodes: [ValueNode('capture', type, name: 'scaler')],
                root: 0,
                captures: {'scaler': type});
        final library = rfw.RemoteWidgetLibrary([
          rfw.Import(rfw.LibraryName(['restage', 'core']))
        ], [
          rfw.WidgetDeclaration(
              'Paywall',
              null,
              rfw.ConstructorCall(widgetName, {
                if (widgetName == 'Text') 'text': 'Native scaler',
                if (widgetName == 'TextRich')
                  'textSpan': {'text': 'Native scaler'},
                'textScaler': {
                  'version': 1,
                  'program': values.encode(),
                  'captures': <String, Object?>{
                    if (!installedCall) 'scaler': borrowed.reference(key)
                  }
                },
              })),
        ]);
        final context = SurfaceScreenHostDataSchema(
            {key: SurfaceScreenHostDataNativeBindingShapeV1(declaration)});
        final events = SurfaceScreenEventSchema(events: []);
        final operations = nativeCallOperations(context, {});
        final derived = deriveSurfaceCapability(library, catalog,
            operations: operations, hostDataContract: context);
        expect(derived.builtInFloor, 24);
        expect(
            surfaceScreenContractGaps(library,
                events: events, context: context),
            isEmpty);
        final blob = rfw.encodeLibraryBlob(library);
        final hash = CapabilitySidecar.hashBlob(blob);
        final capability = CapabilityManifest(
            builtInFloor: derived.builtInFloor,
            requiredLibraries: derived.requiredLibraries);
        final resolution = rfw.RfwCatalogOccurrenceResolutionInput(
            artifactProvenance: 'scaler.artifact',
            sourceLibraryIdentity: 'scaler.library',
            sourceDeclarationIdentity: 'scaler.root',
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
                    catalogWidgetWireId: widget.wireId)
            ]);
        final payload = BlobSurfacePayload(minClient: 24, blob: blob);
        final publication = SurfacePublication(
            surface: Surface.paywall,
            slug: 'scaler',
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
        final sidecar = utf8.encode(jsonEncode(
            CapabilitySidecar(blobSha256: hash, manifest: capability)
                .toJson()));
        final manifest = SurfacePublicationManifest(publications: [
          SurfacePublicationManifestEntry(publication: publication, artifacts: [
            SurfacePublicationArtifact(
                contentHash: hash,
                id: 'scaler',
                path: 'screen.rfw',
                role: SurfacePublicationArtifactRole.screenBlob),
            SurfacePublicationArtifact(
                contentHash: CapabilitySidecar.hashBlob(sidecar),
                id: 'scaler',
                path: 'screen.capability.json',
                role: SurfacePublicationArtifactRole.capabilitySidecar),
          ]),
        ]);
        final requirement = manifest
            .validateArtifactClosure(
                {'screen.rfw': blob, 'screen.capability.json': sidecar})
            .single
            .projectFitRequirement();
        expect(requirement.requiredContext.inputs.keys, [key]);
        expect(
            (requirement.requiredContext.inputs[key]
                    as SurfaceScreenHostDataNativeBindingShapeV1)
                .contract,
            declaration);
        SurfaceFitVerdictV1 fit(SurfaceScreenHostDataSchema supplied) =>
            SurfaceFitEvaluator.evaluate(
                host: SurfaceHostContractV1(
                    hosting: const SurfaceHostingV1(
                        contentKind: SurfaceContentKindV1.single,
                        presentation: SurfacePresentationV1.inline),
                    providedContext: supplied,
                    handledEvents: events),
                requirement: requirement,
                installed: InstalledCapability(
                    builtInCatalogVersion: 24,
                    installedLibraries: [],
                    vocabulary: requirement.requiredVocabulary));
        expect(fit(context).accepted, isTrue);
        expect(
            fit(const SurfaceScreenHostDataSchema.empty()).accepted, isFalse);
      });
    }
  }
}
