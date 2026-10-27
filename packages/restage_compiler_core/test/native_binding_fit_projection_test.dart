import 'dart:convert';
import 'package:test/test.dart';
import 'package:restage_compiler_core/restage_compiler_core.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;

SurfaceFitRequirementV1 _requirement(bool dataReference) {
  const type = ValueType.native('flutter.Key');
  const declaration = NativeBindingContract(type: 'flutter.Key');
  const program = ValueProgram(
      nodes: [ValueNode('capture', type, name: 'key')],
      root: 0,
      captures: {'key': type});
  final library = rfw.RemoteWidgetLibrary([
    rfw.Import(rfw.LibraryName(['restage', 'core']))
  ], [
    rfw.WidgetDeclaration(
        'Paywall',
        null,
        rfw.ConstructorCall('Host', {
          'value': {
            'version': 1,
            'program': program.encode(),
            'captures': {
              'key': dataReference
                  ? rfw.DataReference(['context', 'key'])
                  : declaration.reference('key')
            }
          }
        }))
  ]);
  final catalog = Catalog(
      schemaVersion: kSupportedSchemaVersion,
      generatedAt: '1970-01-01T00:00:00Z',
      libraries: {
        WidgetLibrary.core: const LibraryInfo(version: '1')
      },
      widgets: [
        WidgetEntry(
            wireId: WireId('w0001'),
            name: 'Host',
            library: WidgetLibrary.core,
            category: WidgetCategory.layout,
            description: 'Host',
            flutterType: 'package:fixture/host.dart#Host',
            childrenSlot: ChildrenSlot.none,
            properties: [])
      ]);
  final resolution = rfw.RfwCatalogOccurrenceResolutionInput(
      artifactProvenance: 'fixture.artifact',
      sourceLibraryIdentity: 'fixture.library',
      sourceDeclarationIdentity: 'fixture.root',
      renderEntryNames: [
        'Paywall'
      ],
      localSymbols: [
        rfw.RfwCatalogLocalSymbol(name: 'Paywall')
      ],
      catalogConstructors: [
        rfw.RfwCatalogConstructorProvenance(
            constructorName: 'Host',
            catalogLibraryNamespace: WidgetLibrary.core.namespace,
            catalogWidgetWireId: WireId('w0001'))
      ]);
  final context = SurfaceScreenHostDataSchema(
      {'key': const SurfaceScreenHostDataNativeBindingShapeV1(declaration)});
  final events = SurfaceScreenEventSchema(events: []);
  expect(surfaceScreenContractGaps(library, events: events, context: context),
      isEmpty);
  final blob = rfw.encodeLibraryBlob(library);
  final hash = CapabilitySidecar.hashBlob(blob);
  final capabilities =
      CapabilityManifest(builtInFloor: 24, requiredLibraries: []);
  final payload = BlobSurfacePayload(minClient: 24, blob: blob);
  final publication = SurfacePublication(
      surface: Surface.paywall,
      slug: 'probe',
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
      CapabilitySidecar(blobSha256: hash, manifest: capabilities).toJson()));
  final manifest = SurfacePublicationManifest(publications: [
    SurfacePublicationManifestEntry(publication: publication, artifacts: [
      SurfacePublicationArtifact(
          contentHash: hash,
          id: 'probe',
          path: 'assets/screen.rfw',
          role: SurfacePublicationArtifactRole.screenBlob),
      SurfacePublicationArtifact(
          contentHash: CapabilitySidecar.hashBlob(sidecar),
          id: 'probe',
          path: 'assets/screen.capability.json',
          role: SurfacePublicationArtifactRole.capabilitySidecar)
    ])
  ]);
  final closure = manifest.validateArtifactClosure({
    'assets/screen.rfw': blob,
    'assets/screen.capability.json': sidecar
  }).single;
  final fit = closure.projectFitRequirement();
  return fit;
}

void main() {
  for (final dataReference in [false, true]) {
    test(
        'native fit requires exact installed binding: data reference $dataReference',
        () {
      final fit = _requirement(dataReference);
      const declaration = NativeBindingContract(type: 'flutter.Key');
      expect(fit.requiredContext.inputs.keys, ['key']);
      expect(
          (fit.requiredContext.inputs['key']!
                  as SurfaceScreenHostDataNativeBindingShapeV1)
              .contract,
          declaration);
      SurfaceFitVerdictV1 evaluate(
              Map<String, SurfaceScreenHostDataShape> inputs) =>
          SurfaceFitEvaluator.evaluate(
              host: SurfaceHostContractV1(
                  hosting: const SurfaceHostingV1(
                      contentKind: SurfaceContentKindV1.single,
                      presentation: SurfacePresentationV1.inline),
                  providedContext: SurfaceScreenHostDataSchema(inputs),
                  handledEvents: SurfaceScreenEventSchema(events: [])),
              requirement: fit,
              installed: InstalledCapability(
                  builtInCatalogVersion: 24,
                  installedLibraries: [],
                  vocabulary: fit.requiredVocabulary));
      expect(
          evaluate({
            'key': const SurfaceScreenHostDataNativeBindingShapeV1(declaration)
          }).accepted,
          isTrue);
      final missing = evaluate({});
      expect(missing.accepted, isFalse);
      expect(missing.failures.single.code,
          SurfaceFitFailureCodeV1.missingHostField);
      for (final wrong in [
        const NativeBindingContract(type: 'flutter.Color'),
        const NativeBindingContract(type: 'flutter.Key', nullable: true)
      ]) {
        final verdict =
            evaluate({'key': SurfaceScreenHostDataNativeBindingShapeV1(wrong)});
        expect(verdict.accepted, isFalse);
        expect(verdict.failures.single.path, r'$.requiredContext.key');
      }
    });
  }
}
