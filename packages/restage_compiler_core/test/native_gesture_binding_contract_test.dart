import 'dart:convert';

import 'package:restage_compiler_core/restage_compiler_core.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;
import 'package:test/test.dart';

final _catalog = Catalog(
  schemaVersion: kSupportedSchemaVersion,
  generatedAt: '1970-01-01T00:00:00Z',
  libraries: {WidgetLibrary.core: const LibraryInfo(version: '1')},
  widgets: [
    WidgetEntry(
      wireId: WireId('w0001'),
      name: 'SpanHost',
      library: WidgetLibrary.core,
      category: WidgetCategory.decoration,
      description: 'Inline span host',
      flutterType: 'package:fixture/host.dart#SpanHost',
      childrenSlot: ChildrenSlot.none,
      properties: [
        PropertyEntry(
            wireId: WireId('p0001'),
            name: 'span',
            type: PropertyType.inlineSpan,
            description: 'Span'),
        PropertyEntry(
            wireId: WireId('p0002'),
            name: 'data',
            type: PropertyType.dataReference,
            description: 'App data'),
      ],
    )
  ],
);
rfw.RemoteWidgetLibrary _library(String recognizer) => rfw.parseLibraryFile(
    'import restage.core; widget Paywall = SpanHost(span: {text: "Hi", recognizer: $recognizer});');
SurfaceScreenHostDataSchema _schema(String type, {bool nullable = false}) =>
    SurfaceScreenHostDataSchema({
      'native': SurfaceScreenHostDataNativeBindingShapeV1(
          NativeBindingContract(type: type, nullable: nullable))
    });

SurfaceFitRequirementV1 _fit(
    rfw.RemoteWidgetLibrary library, SurfaceScreenHostDataSchema context,
    {int floor = 24}) {
  final resolution = rfw.RfwCatalogOccurrenceResolutionInput(
    artifactProvenance: 'fixture.artifact',
    sourceLibraryIdentity: 'fixture.library',
    sourceDeclarationIdentity: 'fixture.root',
    renderEntryNames: ['Paywall'],
    localSymbols: [
      for (final widget in library.widgets)
        rfw.RfwCatalogLocalSymbol(name: widget.name)
    ],
    catalogConstructors: [
      rfw.RfwCatalogConstructorProvenance(
          constructorName: 'SpanHost',
          catalogLibraryNamespace: WidgetLibrary.core.namespace,
          catalogWidgetWireId: WireId('w0001'))
    ],
  );
  final blob = rfw.encodeLibraryBlob(library);
  final hash = CapabilitySidecar.hashBlob(blob);
  final payload = BlobSurfacePayload(minClient: floor, blob: blob);
  final publication = SurfacePublication(
      surface: Surface.paywall,
      slug: 'gesture',
      sourceKind: SurfaceSourceKind.paywall,
      payloadKind: SurfacePayloadKind.blob,
      payloadContentHash: payload.contentHash,
      compiledScreenContracts: {
        hash: SurfaceCompiledScreenContractV1(
            context: context,
            events: SurfaceScreenEventSchema(events: []),
            catalogResolution: resolution,
            catalog: _catalog),
      });
  final sidecar = utf8.encode(jsonEncode(CapabilitySidecar(
          blobSha256: hash,
          manifest:
              CapabilityManifest(builtInFloor: floor, requiredLibraries: []))
      .toJson()));
  final manifest = SurfacePublicationManifest(publications: [
    SurfacePublicationManifestEntry(publication: publication, artifacts: [
      SurfacePublicationArtifact(
          contentHash: hash,
          id: 'gesture',
          path: 'screen.rfw',
          role: SurfacePublicationArtifactRole.screenBlob),
      SurfacePublicationArtifact(
          contentHash: CapabilitySidecar.hashBlob(sidecar),
          id: 'gesture',
          path: 'screen.capability.json',
          role: SurfacePublicationArtifactRole.capabilitySidecar),
    ]),
  ]);
  return manifest
      .validateArtifactClosure(
          {'screen.rfw': blob, 'screen.capability.json': sidecar})
      .single
      .projectFitRequirement();
}

void main() {
  test('borrowed recognizer uses the declared native contract at SDK24', () {
    final library = _library('{borrowed: data.context.native}');
    final schema = _schema('flutter.GestureRecognizer');
    expect(
        deriveSurfaceCapability(library, _catalog, hostDataContract: schema)
            .builtInFloor,
        24);
    expect(deriveSurfaceCapability(library, _catalog).builtInFloor, 24);
    expect(_fit(library, schema).requiredContext.inputs['native']!.toJson(),
        schema.inputs['native']!.toJson());
    expect(() => _fit(library, schema, floor: 23), throwsFormatException);
    for (final wrong in [
      'flutter.TabController',
      'flutter.GestureTapDownCallback'
    ]) {
      expect(() => _fit(library, _schema(wrong)), throwsFormatException,
          reason: wrong);
    }
    expect(
        () => _fit(
            library,
            SurfaceScreenHostDataSchema(const {
              'native': SurfaceScreenHostDataScalarShapeV1(
                  SurfaceScreenHostDataScalarKind.string),
            })),
        throwsFormatException);
    expect(() => _fit(library, const SurfaceScreenHostDataSchema.empty()),
        throwsFormatException);
  });

  test('borrowed recognizer raw preview requires its actual installed scope',
      () {
    final library = _library('{borrowed: data.context.native}');
    expect(nativeBindingsNeedInstalledHost(library, _catalog), isTrue);
    expect(
        nativeBindingsNeedInstalledHost(library, _catalog, context: {
          'native':
              const NativeBindingContract(type: 'flutter.GestureRecognizer')
                  .reference('native'),
        }),
        isTrue);
    final recipe = _library('{kind: "tap", onTap: event "tap" {}}');
    expect(nativeBindingsNeedInstalledHost(recipe, _catalog), isFalse);
    expect(
        deriveSurfaceCapability(recipe, _catalog,
                hostDataContract: _schema('flutter.GestureRecognizer'))
            .builtInFloor,
        lessThan(24));
    expect(
        nativeBindingsNeedInstalledHost(_library('null'), _catalog), isFalse);
  });

  test('every typed detail setter validates its fixed native signature', () {
    for (final kind in kTextSpanRecognizerDetailCallbacks.entries) {
      for (final setter in kind.value.entries) {
        final library = _library(
            '{kind: "${kind.key}", ${setter.key}: data.context.native}');
        for (final nullable in [false, true]) {
          expect(
              _fit(library, _schema(setter.value, nullable: nullable))
                  .requiredContext
                  .isEmpty,
              isFalse,
              reason: '${kind.key}.${setter.key}');
        }
        expect(() => _fit(library, _schema('flutter.TabController')),
            throwsFormatException,
            reason: '${kind.key}.${setter.key}');
        expect(nativeBindingsNeedInstalledHost(library, _catalog), isTrue,
            reason: '${kind.key}.${setter.key}');
        expect(
            nativeBindingsNeedInstalledHost(library, _catalog, context: {
              'native':
                  NativeBindingContract(type: setter.value).reference('native'),
            }),
            isTrue);
        final absent = _library('{kind: "${kind.key}", ${setter.key}: null}');
        expect(nativeBindingsNeedInstalledHost(absent, _catalog), isFalse);
        expect(
            deriveSurfaceCapability(absent, _catalog,
                    hostDataContract: _schema(setter.value))
                .builtInFloor,
            lessThan(24));
      }
    }
  });

  test('existing no-argument native events share preview consumer resolution',
      () {
    final library =
        _library('{kind: "tap", onTap: {nativeEvent: data.context.native}}');
    expect(nativeBindingsNeedInstalledHost(library, _catalog), isTrue);
    expect(
        nativeBindingsNeedInstalledHost(library, _catalog, context: {
          'native':
              const NativeBindingContract(type: '()->void').reference('native'),
        }),
        isTrue);
    expect(
        nativeBindingsNeedInstalledHost(
            _library('{kind: "tap", onTap: event "tap" {}}'), _catalog),
        isFalse);
  });

  test('typed validation visits all native consumers through local forwarding',
      () {
    final library = rfw.parseLibraryFile('import restage.core; '
        'widget Forward = SpanHost(span: args.span); '
        'widget Paywall = Forward(span: {recognizer: {borrowed: data.context.native}, children: ['
        '{recognizer: {kind: "tap", onTapDown: data.context.wrong}}]});');
    final schema = SurfaceScreenHostDataSchema({
      ..._schema('flutter.GestureRecognizer').inputs,
      'wrong': const SurfaceScreenHostDataNativeBindingShapeV1(
          NativeBindingContract(type: 'flutter.TabController')),
    });
    final valid = SurfaceScreenHostDataSchema({
      ...schema.inputs,
      'wrong': const SurfaceScreenHostDataNativeBindingShapeV1(
          NativeBindingContract(type: 'flutter.GestureTapDownCallback')),
    });
    expect(_fit(library, valid).requiredContext.inputs.length, 2);
    expect(() => _fit(library, schema), throwsFormatException);
  });

  test('native field arguments retain local call scopes', () {
    final library = rfw.parseLibraryFile('import restage.core; '
        'widget Forward = SpanHost(span: {recognizer: {borrowed: args.recognizer}}); '
        'widget Paywall = Forward(recognizer: data.context.native);');
    expect(
        _fit(library, _schema('flutter.GestureRecognizer'))
            .requiredContext
            .isEmpty,
        isFalse);
    expect(() => _fit(library, _schema('flutter.TabController')),
        throwsFormatException);
  });

  test('ordinary app records with gesture-shaped fields remain ordinary data',
      () {
    final library = rfw.parseLibraryFile(
        'import restage.core; widget Paywall = '
        'SpanHost(data: {recognizer: {borrowed: data.context.native}, onTapDown: data.context.native});');
    final reads = <String>[];
    validateRfwNativeReferences(library, _catalog,
        scope: RfwProgramScope(library.widgets.map((widget) => widget.root),
            operations: {}),
        onReference: (_, type, nativeOnly) => reads.add(type.nativeType!));
    expect(reads, isEmpty);
    expect(nativeBindingsNeedInstalledHost(library, _catalog), isFalse);
  });
}
