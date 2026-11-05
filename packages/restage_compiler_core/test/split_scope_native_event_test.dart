// A split widget's delivered body takes a callback its wrapper recorded only
// when its catalog slot records it as the consuming slot's own type.
import 'dart:convert';

import 'package:restage_compiler_core/restage_compiler_core.dart';
import 'package:restage_compiler_core/src/rfw_scalar_callback_contract.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;
import 'package:test/test.dart';

const _ui = WidgetLibrary.custom('fixture.ui');

final _tap = PropertyEntry(
    wireId: WireId('p0002'),
    description: 'onTap',
    name: 'onTap',
    type: PropertyType.event);

const _read = rfw.WidgetBuilderArgReference('restageWidget', ['values', '_h1']);

Catalog _catalog(String recorded) => Catalog(
        schemaVersion: kSupportedSchemaVersion,
        generatedAt: '1970-01-01T00:00:00Z',
        libraries: {
          WidgetLibrary.core: const LibraryInfo(version: '1'),
          _ui: const LibraryInfo(version: '1', capabilityVersion: 1),
        },
        widgets: [
          WidgetEntry(
              wireId: WireId('w0001'),
              name: 'Tap',
              library: WidgetLibrary.core,
              category: WidgetCategory.layout,
              description: 'Tap',
              flutterType: 'package:fixture/tap.dart#Tap',
              childrenSlot: ChildrenSlot.none,
              properties: [_tap]),
          WidgetEntry(
              wireId: WireId('w0002'),
              name: 'Chip__split',
              library: _ui,
              category: null,
              description: 'Chip',
              flutterType: 'package:fixture/chip.dart#Chip__split',
              childrenSlot: ChildrenSlot.none,
              properties: [
                PropertyEntry(
                    wireId: WireId('p0001'),
                    name: 'restageWidget',
                    type: PropertyType.widgetBuilder,
                    description: 'restageWidget',
                    required: true,
                    builderContract: WidgetBuilderContract(parameters: const [
                      WidgetBuilderParameter.buildContext,
                      WidgetBuilderParameter.data,
                    ], nativeValues: {
                      '_h1': WidgetBuilderNativeValue(recorded),
                    })),
              ]),
        ]);

// `Chip__split` whose body places `Tap(onTap: <recorded callback>)`.
rfw.RemoteWidgetLibrary _library(
        {Object? onTap = const {'nativeEvent': _read}}) =>
    rfw.RemoteWidgetLibrary([
      rfw.Import(rfw.LibraryName(['restage', 'core'])),
      rfw.Import(rfw.LibraryName(['fixture', 'ui'])),
    ], [
      rfw.WidgetDeclaration(
          'Paywall',
          null,
          rfw.ConstructorCall('Chip__split', {
            'restageWidget':
                rfw.ConstructorCall(kBuilderContinuationWidgetName, {
              'version': 1,
              'program': const BuilderProgram(
                values: ValueProgram(
                  nodes: [ValueNode('literal', ValueType.boolean, value: true)],
                  root: 0,
                ),
                result: BuilderResult.body(0),
                bodyCount: 1,
              ).encode(),
              'captures': const <String, Object?>{},
              'bodies': [
                rfw.WidgetBuilderDeclaration('restageWidget',
                    rfw.ConstructorCall('Tap', {'onTap': onTap})),
              ],
            }),
          })),
    ]);

int _validate(String recorded, {Object? onTap = const {'nativeEvent': _read}}) {
  final library = _library(onTap: onTap);
  final catalog = _catalog(recorded);
  return validateRfwPropertyCallbacks(onTap, _tap, catalog,
      scope: RfwProgramScope([library.widgets.single.root],
          operations: {},
          scopedNativeValues: rfwBuilderScopeValues(library, catalog)));
}

SurfaceFitRequirementV1 _fit(String recorded) {
  final library = _library();
  final catalog = _catalog(recorded);
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
        for (final entry in catalog.widgets)
          rfw.RfwCatalogConstructorProvenance(
              constructorName: entry.name,
              catalogLibraryNamespace: entry.library.namespace,
              catalogWidgetWireId: entry.wireId)
      ]);
  final context = SurfaceScreenHostDataSchema(const {});
  final events = SurfaceScreenEventSchema(events: []);
  final blob = rfw.encodeLibraryBlob(library);
  final hash = CapabilitySidecar.hashBlob(blob);
  final derived =
      deriveSurfaceCapability(library, _catalog(kNativeVoidCallbackType));
  final capabilities = CapabilityManifest(
      builtInFloor: derived.builtInFloor,
      requiredLibraries: derived.requiredLibraries);
  final payload =
      BlobSurfacePayload(minClient: derived.builtInFloor, blob: blob);
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
  return manifest
      .validateArtifactClosure(
          {'assets/screen.rfw': blob, 'assets/screen.capability.json': sidecar})
      .single
      .projectFitRequirement();
}

final _wrongType = throwsA(isA<FormatException>().having((e) => e.message,
    'message', 'Native event requires a callback of its slot\'s type.'));

void main() {
  group("a split widget's recorded callback", () {
    test('of the slot type is admitted', () {
      expect(_validate(kNativeVoidCallbackType), 24);
    });

    test('of another type is refused', () {
      expect(() => _validate('(dart:core#bool)->void'), _wrongType);
    });

    test('that was never recorded is refused', () {
      const unrecorded =
          rfw.WidgetBuilderArgReference('restageWidget', ['values', '_h2']);
      expect(
          () => _validate(kNativeVoidCallbackType,
              onTap: const {'nativeEvent': unrecorded}),
          throwsFormatException);
    });
  });

  group('a published split widget', () {
    test('passes fit with its recorded callback', () {
      expect(_fit(kNativeVoidCallbackType).requiredContext.inputs, isEmpty);
    });

    test('is refused when its slot records another type', () {
      expect(() => _fit('(dart:core#bool)->void'), _wrongType);
    });
  });
}
