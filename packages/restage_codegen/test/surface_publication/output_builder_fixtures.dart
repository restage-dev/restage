// Shared minimal compiler-handoff fixtures for RestageOutputsBuilder tests.
// Deliberately hand-built (never through the real roster/screen/flow
// builders) so these tests stay scoped to the outputs builder alone.
import 'dart:convert';

import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_shared/restage_shared.dart';

const String compilerJsonPath =
    'lib/src/surface_publication/surface_publication.compiler.json';

typedef OutputsFixture = ({
  String libraryPath,
  SurfacePublicationManifestEntryV1 entry,
  Map<String, List<int>> files,
  Map<String, List<int>> ownedOutputs,
});

/// Builds one minimal, fully valid flow-graph publication fixture — the
/// simplest publication shape that does not require a screen event contract
/// or capability fingerprint. Includes the compiled screen blob's canonical
/// `.rfwtxt` sibling as a compiler-handoff owned output (never a manifest
/// artifact), matching how the real pipeline produces it.
OutputsFixture flowFixture({
  required String slug,
  required String libraryPath,
  required List<int> screenBytes,
  String? pathSegment,
  bool includeRfwText = true,
}) {
  // The FlowDocument's own `flow` identity must be an ASCII identifier, but
  // the artifact filenames need not match it — callers that want a specific
  // (for example non-ASCII) filename pass `pathSegment` separately.
  final segment = pathSegment ?? slug;
  final document = FlowDocument(
    flow: slug,
    version: 1,
    schemaVersion: 1,
    minClient: 1,
    initial: 'start',
    screenArtifacts: <String, ScreenArtifact>{
      'start': ScreenArtifact(
        path: 'start.rfw',
        version: 1,
        schemaVersion: 1,
        minClient: 1,
        contentHash: FlowContentHash.compute(screenBytes),
      ),
    },
    states: const <String, FlowState>{
      'start': ScreenFlowState(
        screen: 'start',
        on: <String, FlowTransition>{'next': FlowTransition.goto('done')},
      ),
      'done': EndFlowState(result: <String, Object?>{'completed': true}),
    },
    deliveryMode: FlowDeliveryMode.general,
  );
  final flowBytes = utf8.encode(FlowDocumentCodec.encodePrettyJson(document));
  final sidecarBytes = utf8.encode(
    jsonEncode(
      CapabilitySidecar(
        blobSha256: CapabilitySidecar.hashBlob(screenBytes),
        manifest: CapabilityManifest(
          builtInFloor: 1,
          requiredLibraries: const <LibraryRequirement>[],
        ),
      ).toJson(),
    ),
  );
  final flowPath = 'assets/general/flows/$segment.flow.json';
  final blobPath = 'assets/general/screens/$segment.rfw';
  final sidecarPath = 'assets/general/screens/$segment.capability.json';
  final publication = SurfacePublicationV1(
    surface: Surface.general,
    slug: slug,
    sourceKind: SurfaceSourceKind.flowGraph,
    payloadKind: SurfacePayloadKind.flow,
    payloadContentHash: CapabilitySidecar.hashBlob(flowBytes),
    deliveryMode: FlowDeliveryMode.general,
  );
  final entry = SurfacePublicationManifestEntryV1(
    artifacts: <SurfacePublicationArtifactV1>[
      SurfacePublicationArtifactV1(
        contentHash: CapabilitySidecar.hashBlob(flowBytes),
        path: flowPath,
        role: SurfacePublicationArtifactRoleV1.flowDocument,
      ),
      SurfacePublicationArtifactV1(
        contentHash: CapabilitySidecar.hashBlob(screenBytes),
        id: 'start',
        path: blobPath,
        role: SurfacePublicationArtifactRoleV1.screenBlob,
      ),
      SurfacePublicationArtifactV1(
        contentHash: CapabilitySidecar.hashBlob(sidecarBytes),
        id: 'start',
        path: sidecarPath,
        role: SurfacePublicationArtifactRoleV1.capabilitySidecar,
      ),
    ],
    publication: publication,
  );
  final rfwTextPath = 'assets/general/screens/$segment.rfwtxt';
  final rfwTextBytes = utf8.encode(
    'Restage widget tree text for $segment (deterministic test fixture).',
  );
  return (
    libraryPath: libraryPath,
    entry: entry,
    files: <String, List<int>>{
      flowPath: flowBytes,
      blobPath: screenBytes,
      sidecarPath: sidecarBytes,
    },
    ownedOutputs: includeRfwText
        ? <String, List<int>>{rfwTextPath: rfwTextBytes}
        : const <String, List<int>>{},
  );
}

/// Encodes the compiler handoff JSON for a set of fixtures.
String compilerJsonFor(List<OutputsFixture> fixtures) {
  final manifest = SurfacePublicationManifestV1(
    publications: [for (final fixture in fixtures) fixture.entry],
  );
  final artifacts = <String, List<int>>{
    for (final fixture in fixtures) ...fixture.files,
  };
  final ownedOutputs = <String, List<int>>{
    for (final fixture in fixtures) ...fixture.ownedOutputs,
  };
  // The real compiler attributes every output file it writes — manifest
  // artifacts and ancillary .rfwtxt text alike — at the same choke point it
  // writes the bytes (see package_surface_compiler.dart's _putFile). This
  // fixture matches that: no derived/sibling attribution, direct only.
  final libraryPaths = <String, String>{
    for (final fixture in fixtures) ...{
      for (final path in fixture.files.keys) path: fixture.libraryPath,
      for (final path in fixture.ownedOutputs.keys) path: fixture.libraryPath,
    },
  };
  final bundle = RestageSurfacePublicationBundle.valid(
    manifest: manifest,
    artifacts: artifacts,
    ownedOutputs: ownedOutputs,
    artifactLibraryPaths: libraryPaths,
  );
  return bundle.encodeCanonicalJson();
}
