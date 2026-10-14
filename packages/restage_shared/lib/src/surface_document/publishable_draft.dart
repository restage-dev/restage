import 'dart:typed_data';

import 'package:restage_shared/src/flow_document/flow_document.dart';
import 'package:restage_shared/src/flow_document/flow_document_hash.dart';
import 'package:restage_shared/src/rfw_formats.dart';
import 'package:restage_shared/src/rfw_reachability.dart';
import 'package:restage_shared/src/surface_document/surface_document.dart';

/// Root declaration names, by precedence: an editor-authored `main`, a
/// generated `Paywall`, a generated flow screen's `OnboardingScreen`.
const List<String> kSurfaceRootWidgetNames = [
  'main',
  'Paywall',
  'OnboardingScreen',
];

/// The root widget a surface library renders: the first of
/// [kSurfaceRootWidgetNames] declared exactly once, else the library's single
/// declaration, else null.
///
/// Throws [FormatException] when `main` is declared more than once.
String? surfaceRootWidgetName(Iterable<String> declarationNames) {
  final names = declarationNames.toList();
  for (final root in kSurfaceRootWidgetNames) {
    final count = names.where((name) => name == root).length;
    if (count == 1) return root;
    if (count > 1) {
      if (root == 'main') {
        throw const FormatException('Multiple main declarations.');
      }
      return null;
    }
  }
  return names.length == 1 ? names.single : null;
}

/// What publishing [draft] ships: the draft without its editor state, each
/// library trimmed to the declarations its root widget reaches
/// ([surfaceRootWidgetName]). A flow's trimmed screens are rebound in its
/// flow document. A library without a root is left whole. Returns [draft]
/// itself when nothing changes.
SurfacePayload publishableDraftPayload(SurfacePayload draft) {
  final stripped = draft.withoutEditorState();
  switch (stripped) {
    case BlobSurfacePayload():
      final blob = _trimmed(stripped.blob);
      if (blob == null) return stripped;
      return BlobSurfacePayload(
        minClient: stripped.minClient,
        blob: blob,
        requiredLibraries: stripped.requiredLibraries,
        iconFonts: stripped.iconFonts,
        localSeeds: stripped.localSeeds,
      );
    case FlowSurfacePayload():
      final trimmed = <String, Uint8List>{
        for (final MapEntry(key: id, value: blob)
            in stripped.screenBlobs.entries)
          if (_trimmed(blob) case final screen?) id: screen,
      };
      if (trimmed.isEmpty) return stripped;
      final document = stripped.flowDocument;
      return FlowSurfacePayload(
        flowDocument: document.copyWith(
          screenArtifacts: {
            for (final MapEntry(key: id, value: artifact)
                in document.screenArtifacts.entries)
              id: switch (trimmed[id]) {
                final blob? => artifact.withBlob(blob),
                null => artifact,
              },
          },
        ),
        screenBlobs: {...stripped.screenBlobs, ...trimmed},
        requiredLibraries: stripped.requiredLibraries,
        iconFonts: stripped.iconFonts,
        localSeeds: stripped.localSeeds,
      );
  }
}

/// [blob] trimmed to what its root reaches, or null when that changes
/// nothing or the blob has no root.
Uint8List? _trimmed(Uint8List blob) {
  final RemoteWidgetLibrary library;
  try {
    library = decodeLibraryBlob(blob);
  } on Object {
    // Publish validation reports a blob that is not a library.
    return null;
  }
  final String? root;
  try {
    root = surfaceRootWidgetName(library.widgets.map((widget) => widget.name));
  } on FormatException {
    return null;
  }
  if (root == null) return null;
  final retained = retainReachableFrom(library, root);
  if (identical(retained, library)) return null;
  return encodeLibraryBlob(retained);
}

extension on ScreenArtifact {
  ScreenArtifact withBlob(Uint8List blob) => ScreenArtifact(
        path: path,
        version: version,
        schemaVersion: schemaVersion,
        minClient: minClient,
        contentHash: FlowContentHash.compute(blob),
      );
}
