import 'surface_artifact_store.dart';

/// Web and other non-`dart:io` platforms keep entries in memory.
SurfaceArtifactStore createSurfaceArtifactStore({
  Future<String> Function()? directory,
}) =>
    MemorySurfaceArtifactStore();
