// The cases the delivery-path parity gate runs, one per payload kind plus the
// refusals each kind has to keep making.
//
// Frames are built two ways on purpose. A well-formed frame comes from the
// shared payload types, so a case cannot drift away from what the publisher
// really writes. A malformed frame is written byte by byte here, because the
// shared types refuse to construct the very shapes the refusal cases exist to
// probe — a corpus that can only express valid inputs tests nothing about
// failing closed.

import 'dart:convert';
import 'dart:typed_data';

import 'package:restage_shared/restage_shared.dart';

import 'surface_artifact_parity_corpus.dart';

/// The built-in catalog version the corpus treats as installed.
const int installedBuiltInVersion = 4;

/// A floor one step above [installedBuiltInVersion] — high enough that this
/// build must refuse it.
const int unrenderableBuiltInFloor = installedBuiltInVersion + 1;

/// What the corpus presents to the render gate: a build with one custom
/// library registered.
final InstalledCapability corpusInstalled = InstalledCapability(
  builtInCatalogVersion: installedBuiltInVersion,
  installedLibraries: const <InstalledLibrary>[
    InstalledLibrary(namespace: 'acme.widgets', version: 3),
  ],
);

/// Every case, in a stable order. The accompanying test pins one verdict per
/// entry by name, so adding a case here without pinning its verdict fails.
List<ParityCase> parityCases() => <ParityCase>[
      // ---- blob, the accepting shapes -----------------------------------
      ParityCase(
        name: 'blob: plain',
        artifactBytes: blobFrame(blob: const <int>[9, 8, 7]),
        surfaceType: Surface.paywall,
        surfaceSlug: 'pro_upgrade',
        version: 12,
        publishedAt: DateTime.utc(2026, 8, 13, 10, 30),
        installed: corpusInstalled,
      ),
      ParityCase(
        name: 'blob: with a satisfied library requirement',
        artifactBytes: blobFrame(
          blob: const <int>[1],
          requiredLibraries: const <LibraryRequirement>[
            LibraryRequirement(namespace: 'acme.widgets', minVersion: 2),
          ],
        ),
        surfaceType: Surface.paywall,
        surfaceSlug: 'pro_upgrade',
        version: 3,
        publishedAt: DateTime.utc(2026, 8, 13, 10, 30),
        installed: corpusInstalled,
      ),
      ParityCase(
        name: 'blob: an engagement surface, not a paywall',
        artifactBytes: blobFrame(blob: const <int>[4, 4]),
        surfaceType: Surface.message,
        surfaceSlug: 'welcome_back',
        version: 2,
        publishedAt: DateTime.utc(2026, 8, 13),
        installed: corpusInstalled,
      ),

      // ---- blob, the refusals -------------------------------------------
      ParityCase(
        name: 'blob: the declared hash is not the bytes',
        artifactBytes: blobFrame(blob: const <int>[9, 8, 7]),
        declaredContentHash: contentHashOf(const <int>[0, 0, 0]),
        surfaceType: Surface.paywall,
        surfaceSlug: 'pro_upgrade',
        version: 12,
        publishedAt: DateTime.utc(2026, 8, 13),
        installed: corpusInstalled,
      ),
      ParityCase(
        name: 'blob: truncated frame',
        // The declared hash is left truthful for the SHORTENED bytes, so the
        // hash gate passes and the frame gate is the one under test. Declaring
        // the pre-truncation hash would prove only that the hash gate works,
        // which a different case already does.
        artifactBytes: truncate(blobFrame(blob: const <int>[9, 8, 7]), 6),
        surfaceType: Surface.paywall,
        surfaceSlug: 'pro_upgrade',
        version: 12,
        publishedAt: DateTime.utc(2026, 8, 13),
        installed: corpusInstalled,
      ),
      ParityCase(
        name: 'blob: trailing bytes after the frame',
        artifactBytes: append(
          blobFrame(blob: const <int>[9, 8, 7]),
          const <int>[0xFF],
        ),
        surfaceType: Surface.paywall,
        surfaceSlug: 'pro_upgrade',
        version: 12,
        publishedAt: DateTime.utc(2026, 8, 13),
        installed: corpusInstalled,
      ),
      ParityCase(
        name: 'blob: unknown payload kind',
        artifactBytes: unknownKindFrame(),
        surfaceType: Surface.paywall,
        surfaceSlug: 'pro_upgrade',
        version: 12,
        publishedAt: DateTime.utc(2026, 8, 13),
        installed: corpusInstalled,
      ),
      ParityCase(
        name: 'blob: empty frame',
        artifactBytes: Uint8List(0),
        surfaceType: Surface.paywall,
        surfaceSlug: 'pro_upgrade',
        version: 12,
        publishedAt: DateTime.utc(2026, 8, 13),
        installed: corpusInstalled,
      ),
      ParityCase(
        name: 'blob: requirement section missing',
        artifactBytes: blobFrameWithoutRequirementSection(
          blob: const <int>[9, 8, 7],
        ),
        surfaceType: Surface.paywall,
        surfaceSlug: 'pro_upgrade',
        version: 12,
        publishedAt: DateTime.utc(2026, 8, 13),
        installed: corpusInstalled,
      ),
      ParityCase(
        name: 'blob: requirements out of canonical order',
        artifactBytes: rawBlobFrame(
          minClient: 1,
          blob: const <int>[1],
          requirements: const <({String namespace, int minVersion})>[
            (namespace: 'zeta.widgets', minVersion: 1),
            (namespace: 'acme.widgets', minVersion: 1),
          ],
        ),
        surfaceType: Surface.paywall,
        surfaceSlug: 'pro_upgrade',
        version: 12,
        publishedAt: DateTime.utc(2026, 8, 13),
        installed: corpusInstalled,
      ),
      ParityCase(
        name: 'blob: floor above this build',
        artifactBytes: blobFrame(
          blob: const <int>[1],
          minClient: unrenderableBuiltInFloor,
        ),
        surfaceType: Surface.paywall,
        surfaceSlug: 'pro_upgrade',
        version: 12,
        publishedAt: DateTime.utc(2026, 8, 13),
        installed: corpusInstalled,
      ),
      ParityCase(
        name: 'blob: requires a library this build lacks',
        artifactBytes: blobFrame(
          blob: const <int>[1],
          requiredLibraries: const <LibraryRequirement>[
            LibraryRequirement(namespace: 'nowhere.widgets', minVersion: 1),
          ],
        ),
        surfaceType: Surface.paywall,
        surfaceSlug: 'pro_upgrade',
        version: 12,
        publishedAt: DateTime.utc(2026, 8, 13),
        installed: corpusInstalled,
      ),
      ParityCase(
        name: 'blob: requires a newer version of a present library',
        artifactBytes: blobFrame(
          blob: const <int>[1],
          requiredLibraries: const <LibraryRequirement>[
            LibraryRequirement(namespace: 'acme.widgets', minVersion: 99),
          ],
        ),
        surfaceType: Surface.paywall,
        surfaceSlug: 'pro_upgrade',
        version: 12,
        publishedAt: DateTime.utc(2026, 8, 13),
        installed: corpusInstalled,
      ),
      ParityCase(
        name: 'blob: a different slug than was asked for',
        artifactBytes: blobFrame(blob: const <int>[1]),
        surfaceType: Surface.paywall,
        surfaceSlug: 'some_other_paywall',
        requestedSlug: 'pro_upgrade',
        version: 12,
        publishedAt: DateTime.utc(2026, 8, 13),
        installed: corpusInstalled,
      ),
      ParityCase(
        name: 'blob: a different surface category than was asked for',
        artifactBytes: blobFrame(blob: const <int>[1]),
        surfaceType: Surface.survey,
        surfaceSlug: 'pro_upgrade',
        requestedSurfaceType: Surface.paywall,
        version: 12,
        publishedAt: DateTime.utc(2026, 8, 13),
        installed: corpusInstalled,
      ),

      // ---- flow ----------------------------------------------------------
      ParityCase(
        name: 'flow: plain',
        artifactBytes: flowFrame(),
        surfaceType: Surface.onboarding,
        surfaceSlug: 'first_run',
        version: 5,
        publishedAt: DateTime.utc(2026, 8, 13, 11),
        installed: corpusInstalled,
      ),
      ParityCase(
        name: 'flow: with a satisfied library requirement',
        artifactBytes: flowFrame(
          requiredLibraries: const <LibraryRequirement>[
            LibraryRequirement(namespace: 'acme.widgets', minVersion: 3),
          ],
        ),
        surfaceType: Surface.onboarding,
        surfaceSlug: 'first_run',
        version: 5,
        publishedAt: DateTime.utc(2026, 8, 13, 11),
        installed: corpusInstalled,
      ),
      ParityCase(
        name: 'flow: the declared hash is not the bytes',
        artifactBytes: flowFrame(),
        declaredContentHash: contentHashOf(const <int>[7]),
        surfaceType: Surface.onboarding,
        surfaceSlug: 'first_run',
        version: 5,
        publishedAt: DateTime.utc(2026, 8, 13),
        installed: corpusInstalled,
      ),
      ParityCase(
        name: 'flow: truncated frame',
        artifactBytes: truncate(flowFrame(), 24),
        surfaceType: Surface.onboarding,
        surfaceSlug: 'first_run',
        version: 5,
        publishedAt: DateTime.utc(2026, 8, 13),
        installed: corpusInstalled,
      ),
      ParityCase(
        name: 'flow: a screen blob that is not the one the graph names',
        artifactBytes: flowFrameWithSubstitutedScreenBytes(),
        surfaceType: Surface.onboarding,
        surfaceSlug: 'first_run',
        version: 5,
        publishedAt: DateTime.utc(2026, 8, 13),
        installed: corpusInstalled,
      ),
      ParityCase(
        name: 'flow: floor above this build',
        artifactBytes: flowFrame(minClient: unrenderableBuiltInFloor),
        surfaceType: Surface.onboarding,
        surfaceSlug: 'first_run',
        version: 5,
        publishedAt: DateTime.utc(2026, 8, 13),
        installed: corpusInstalled,
      ),
      ParityCase(
        name: 'flow: requires a library this build lacks',
        artifactBytes: flowFrame(
          requiredLibraries: const <LibraryRequirement>[
            LibraryRequirement(namespace: 'nowhere.widgets', minVersion: 1),
          ],
        ),
        surfaceType: Surface.onboarding,
        surfaceSlug: 'first_run',
        version: 5,
        publishedAt: DateTime.utc(2026, 8, 13),
        installed: corpusInstalled,
      ),
      ParityCase(
        name: 'flow: a different slug than was asked for',
        artifactBytes: flowFrame(),
        surfaceType: Surface.onboarding,
        surfaceSlug: 'second_run',
        requestedSlug: 'first_run',
        version: 5,
        publishedAt: DateTime.utc(2026, 8, 13),
        installed: corpusInstalled,
      ),

      // ---- screen (a blob frame delivered under the strict screen wire) ---
      ParityCase(
        name: 'screen: plain',
        artifactBytes: blobFrame(blob: const <int>[3, 1, 4]),
        surfaceType: Surface.general,
        surfaceSlug: 'feature_announcement',
        version: 9,
        publishedAt: DateTime.utc(2026, 8, 13, 12),
        installed: corpusInstalled,
      ),
      ParityCase(
        name: 'screen: the declared hash is not the bytes',
        artifactBytes: blobFrame(blob: const <int>[3, 1, 4]),
        declaredContentHash: contentHashOf(const <int>[5]),
        surfaceType: Surface.general,
        surfaceSlug: 'feature_announcement',
        version: 9,
        publishedAt: DateTime.utc(2026, 8, 13),
        installed: corpusInstalled,
      ),
      ParityCase(
        name: 'screen: floor above this build',
        artifactBytes: blobFrame(
          blob: const <int>[3, 1, 4],
          minClient: unrenderableBuiltInFloor,
        ),
        surfaceType: Surface.general,
        surfaceSlug: 'feature_announcement',
        version: 9,
        publishedAt: DateTime.utc(2026, 8, 13),
        installed: corpusInstalled,
      ),
    ];

// ---------------------------------------------------------------------------
// Well-formed frames, built through the shared types.
// ---------------------------------------------------------------------------

/// A blob frame exactly as a publisher writes one.
Uint8List blobFrame({
  required List<int> blob,
  int minClient = 2,
  List<LibraryRequirement> requiredLibraries = const <LibraryRequirement>[],
}) =>
    BlobSurfacePayload(
      minClient: minClient,
      blob: Uint8List.fromList(blob),
      requiredLibraries: requiredLibraries,
    ).canonicalBytes;

/// A flow frame exactly as a publisher writes one: a two-state graph with one
/// screen, and the screen's bytes hashed into the graph.
Uint8List flowFrame({
  int minClient = 2,
  List<LibraryRequirement> requiredLibraries = const <LibraryRequirement>[],
  List<int> screenBytes = const <int>[1, 2, 3],
}) {
  final bytes = Uint8List.fromList(screenBytes);
  return FlowSurfacePayload(
    flowDocument: _flowGraph(minClient: minClient, screenBytes: bytes),
    screenBlobs: <String, Uint8List>{'welcome': bytes},
    requiredLibraries: requiredLibraries,
  ).canonicalBytes;
}

FlowDocument _flowGraph({
  required int minClient,
  required Uint8List screenBytes,
}) =>
    FlowDocument(
      flow: 'first_run',
      version: 1,
      schemaVersion: 1,
      minClient: minClient,
      initial: 'welcome',
      actions: const <String, FlowActionContract>{},
      screenArtifacts: <String, ScreenArtifact>{
        'welcome': ScreenArtifact(
          path: 'welcome.rfw',
          version: 1,
          schemaVersion: 1,
          minClient: minClient,
          contentHash: FlowContentHash.compute(screenBytes),
        ),
      },
      states: const <String, FlowState>{
        'welcome': ScreenFlowState(
          screen: 'welcome',
          on: <String, FlowTransition>{'next': FlowTransition.goto('done')},
        ),
        'done': EndFlowState(result: <String, Object?>{'completed': true}),
      },
    );

/// A flow frame whose screen bytes are NOT the ones the graph hashed.
///
/// Built by writing the frame directly, because the shared payload type refuses
/// to construct this — which is the whole point of covering it: the refusal has
/// to survive the move to a fetched frame, where the graph and the screen bytes
/// arrive together but from a store rather than from a publisher.
Uint8List flowFrameWithSubstitutedScreenBytes() {
  final honest = Uint8List.fromList(const <int>[1, 2, 3]);
  final graph = _flowGraph(minClient: 2, screenBytes: honest);
  return _rawFlowFrame(
    flowDocumentBytes: FlowDocumentCodec.encodeCanonicalJson(graph),
    screens: <String, List<int>>{
      'welcome': const <int>[9, 9, 9]
    },
    requirements: const <({String namespace, int minVersion})>[],
  );
}

// ---------------------------------------------------------------------------
// Hand-written frames — the shapes the shared types will not build.
// ---------------------------------------------------------------------------

/// A blob frame carrying a payload kind nothing understands.
Uint8List unknownKindFrame() {
  final writer = _FrameWriter()
    ..lengthPrefixed(utf8.encode('sculpture'))
    ..uint32(1)
    ..lengthPrefixed(const <int>[1])
    ..uint32(0);
  return writer.take();
}

/// A blob frame with the trailing requirement section omitted entirely.
Uint8List blobFrameWithoutRequirementSection({required List<int> blob}) {
  final writer = _FrameWriter()
    ..lengthPrefixed(utf8.encode(kBlobPayloadKind))
    ..uint32(2)
    ..lengthPrefixed(blob);
  return writer.take();
}

/// A blob frame with an arbitrary requirement section, canonical or not.
Uint8List rawBlobFrame({
  required int minClient,
  required List<int> blob,
  required List<({String namespace, int minVersion})> requirements,
}) {
  final writer = _FrameWriter()
    ..lengthPrefixed(utf8.encode(kBlobPayloadKind))
    ..uint32(minClient)
    ..lengthPrefixed(blob)
    ..uint32(requirements.length);
  for (final requirement in requirements) {
    writer
      ..lengthPrefixed(utf8.encode(requirement.namespace))
      ..uint32(requirement.minVersion);
  }
  return writer.take();
}

Uint8List _rawFlowFrame({
  required List<int> flowDocumentBytes,
  required Map<String, List<int>> screens,
  required List<({String namespace, int minVersion})> requirements,
}) {
  final writer = _FrameWriter()
    ..lengthPrefixed(utf8.encode(kFlowPayloadKind))
    ..lengthPrefixed(flowDocumentBytes)
    ..uint32(screens.length);
  final ids = screens.keys.toList()..sort();
  for (final id in ids) {
    writer
      ..lengthPrefixed(utf8.encode(id))
      ..lengthPrefixed(screens[id]!);
  }
  writer.uint32(requirements.length);
  for (final requirement in requirements) {
    writer
      ..lengthPrefixed(utf8.encode(requirement.namespace))
      ..uint32(requirement.minVersion);
  }
  return writer.take();
}

/// Keeps the first [length] bytes.
Uint8List truncate(Uint8List bytes, int length) =>
    Uint8List.fromList(bytes.sublist(0, length));

/// Appends [extra] to [bytes].
Uint8List append(Uint8List bytes, List<int> extra) =>
    Uint8List.fromList(<int>[...bytes, ...extra]);

final class _FrameWriter {
  final BytesBuilder _builder = BytesBuilder();

  void uint32(int value) {
    final bytes = Uint8List(4);
    ByteData.view(bytes.buffer).setUint32(0, value);
    _builder.add(bytes);
  }

  void lengthPrefixed(List<int> bytes) {
    uint32(bytes.length);
    _builder.add(bytes);
  }

  Uint8List take() => _builder.toBytes();
}
