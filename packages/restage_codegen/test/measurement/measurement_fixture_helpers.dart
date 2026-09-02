import 'package:build/build.dart';
import 'package:restage_codegen/src/measurement/measurement_route_emission.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as fmt;
import 'package:test/test.dart';

import '../helpers.dart';

void expectUnmeasuredScreenPublication({
  required TestReaderWriter readerWriter,
  required String packageName,
  required String sourcePath,
  required String bundlePath,
  required Surface surface,
  required String slug,
}) {
  final manifest = SurfacePublicationManifestV1Codec.decodeJson(
    readerWriter.testing.readString(
      AssetId(packageName, 'lib/generated/restage.publication.json'),
    ),
  );
  expect(manifest.publications, hasLength(1));
  final entry = manifest.publications.single;
  expect(entry.publication.surface, surface);
  expect(entry.publication.slug, slug);
  expect(entry.publication.sourceKind, SurfaceSourceKind.screen);
  expect(entry.publication.payloadKind, SurfacePayloadKind.blob);
  expect(entry.sources, <String>[sourcePath]);

  final screenRoot = 'assets/${surface.wireName}/screens/$slug';
  final blobPath = '$screenRoot.rfw';
  final sidecarPath = '$screenRoot.capability.json';
  final textPath = '$screenRoot.rfwtxt';
  expect(
    <String, SurfacePublicationArtifactRole>{
      for (final artifact in entry.artifacts) artifact.path: artifact.role,
    },
    <String, SurfacePublicationArtifactRole>{
      blobPath: SurfacePublicationArtifactRole.screenBlob,
      sidecarPath: SurfacePublicationArtifactRole.capabilitySidecar,
    },
  );
  expect(
    entry.artifacts.map((artifact) => artifact.id).toSet(),
    <String?>{slug},
  );

  final bundle = RestageBundleCodec.decode(
    readerWriter.testing.readBytes(AssetId(packageName, bundlePath)),
  );
  expect(bundle.packageName, packageName);
  expect(bundle.authoredLibraryPath, sourcePath);
  expect(
    <String, RestageBundleEntryRole>{
      for (final artifact in bundle.entries)
        artifact.logicalPath: artifact.role,
    },
    <String, RestageBundleEntryRole>{
      blobPath: RestageBundleEntryRole.screenBlob,
      sidecarPath: RestageBundleEntryRole.capabilitySidecar,
      textPath: RestageBundleEntryRole.rfwText,
    },
  );

  final deliveryFiles = <String, List<int>>{
    for (final artifact in bundle.entries)
      if (artifact.role != RestageBundleEntryRole.rfwText)
        artifact.logicalPath: artifact.bytes,
  };
  expect(manifest.validateArtifactClosure(deliveryFiles), hasLength(1));

  final blob = bundle.entries.singleWhere(
    (artifact) => artifact.logicalPath == blobPath,
  );
  final library = fmt.decodeLibraryBlob(blob.bytes);
  expect(library.widgets, isNotEmpty);
  expectNoMeasurementRfwIdentities(library);
}

void expectNoMeasurementRfwIdentities(fmt.RemoteWidgetLibrary library) {
  expect(_measurementRfwIdentities(library), isEmpty);
}

List<fmt.AnyEventHandler> rfwEventHandlers(
  fmt.RemoteWidgetLibrary library,
) {
  final handlers = <fmt.AnyEventHandler>[];

  void visit(Object? node) {
    switch (node) {
      case final fmt.EventHandler handler:
        handlers.add(handler);
        visit(handler.eventArguments);
      case final fmt.SetStateHandler handler:
        handlers.add(handler);
        visit(handler.value);
      case final fmt.ConstructorCall call:
        visit(call.arguments);
      case final fmt.WidgetBuilderDeclaration builder:
        visit(builder.widget);
      case final fmt.Loop loop:
        visit(loop.input);
        visit(loop.output);
      case final fmt.Switch branch:
        visit(branch.input);
        branch.outputs.values.forEach(visit);
      case final Map<Object?, Object?> map:
        map.values.forEach(visit);
      case final List<Object?> list:
        list.forEach(visit);
      default:
        break;
    }
  }

  for (final widget in library.widgets) {
    visit(widget.initialState);
    visit(widget.root);
  }
  return handlers;
}

Set<String> _measurementRfwIdentities(fmt.RemoteWidgetLibrary library) {
  final identities = <String>{};
  for (final import in library.imports) {
    final name = import.name.parts.join('.');
    if (name == 'restage.measurement') identities.add('import:$name');
  }

  void visit(Object? node) {
    switch (node) {
      case final fmt.ConstructorCall call:
        if (const <String>{
          'MeasurementPresented',
          'MeasurementSourcePresented',
        }.contains(call.name)) {
          identities.add('constructor:${call.name}');
        }
        visit(call.arguments);
      case final fmt.EventHandler handler:
        if (handler.eventArguments.containsKey(
          kMeasurementRouteArgumentKeyV1,
        )) {
          identities.add('argument:$kMeasurementRouteArgumentKeyV1');
        }
        visit(handler.eventArguments);
      case final fmt.WidgetBuilderDeclaration builder:
        visit(builder.widget);
      case final fmt.Loop loop:
        visit(loop.input);
        visit(loop.output);
      case final fmt.Switch branch:
        visit(branch.input);
        branch.outputs.values.forEach(visit);
      case final Map<Object?, Object?> map:
        map.values.forEach(visit);
      case final List<Object?> list:
        list.forEach(visit);
      default:
        break;
    }
  }

  for (final widget in library.widgets) {
    visit(widget.initialState);
    visit(widget.root);
  }
  return identities;
}
