import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle;
import 'package:meta/meta.dart';
import 'package:restage_shared/restage_shared.dart' show SurfacePayload;

import '../runtime/local_values.dart' show SurfaceSections;

final Expando<SurfaceSections> _sections =
    Expando<SurfaceSections>('restage.surfaceSections');

/// Attaches [sections] to a resolved surface; empty sections attach nothing.
@internal
T attachSurfaceSections<T extends Object>(
    T resolved, SurfaceSections sections) {
  if (sections.iconFonts.isNotEmpty || sections.localSeeds.isNotEmpty) {
    _sections[resolved] = sections;
  }
  return resolved;
}

/// The sections delivered with [resolved], or none.
@internal
SurfaceSections surfaceSectionsFor(Object resolved) =>
    _sections[resolved] ?? SurfaceSections.none;

final Expando<SurfacePayload> _payloads =
    Expando<SurfacePayload>('restage.surfacePayload');

/// Attaches the verified [payload] a surface was resolved from, and its
/// sections.
@internal
T attachSurfacePayload<T extends Object>(T resolved, SurfacePayload payload) {
  _payloads[resolved] = payload;
  return attachSurfaceSections(resolved, surfaceSectionsOf(payload));
}

/// The payload [resolved] was decoded or built from, when one was attached.
@internal
SurfacePayload? surfacePayloadFor(Object resolved) => _payloads[resolved];

/// Carries the payload and sections of [from] onto its copy [to].
@internal
T copySurfaceSections<T extends Object>(Object from, T to) {
  final payload = _payloads[from];
  if (payload != null) _payloads[to] = payload;
  return attachSurfaceSections(to, surfaceSectionsFor(from));
}

/// The sections a delivered payload frame carries.
@internal
SurfaceSections surfaceSectionsOf(SurfacePayload payload) => SurfaceSections(
      iconFonts: payload.iconFonts,
      localSeeds: payload.localSeeds,
    );

/// The logical path of the local-seed sidecar beside a bundled artifact.
@internal
String localSeedSidecarPath(String artifactPath) {
  final slash = artifactPath.lastIndexOf('/');
  final dot = artifactPath.indexOf('.', slash + 1);
  final stem = dot < 0 ? artifactPath : artifactPath.substring(0, dot);
  return '$stem.local.json';
}

/// Decodes a bundled local-seed sidecar: `{"<id>": {"<key>": value}}`.
/// Null when absent or malformed.
@internal
SurfaceSections? decodeLocalSeedSidecar(List<int>? bytes) {
  if (bytes == null) return null;
  try {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, Object?>) return null;
    final seeds = <String, Map<String, Object>>{};
    for (final MapEntry(:key, :value) in decoded.entries) {
      if (value is! Map<String, Object?>) return null;
      seeds[key] = <String, Object>{
        for (final entry in value.entries)
          if (entry.value != null) entry.key: entry.value!,
      };
    }
    return SurfaceSections(localSeeds: seeds);
  } on Object {
    return null;
  }
}

/// Reads the local-seed sidecar beside [artifactPath] from [bundle], if any.
@internal
Future<SurfaceSections> loadLocalSeedSidecar(
  AssetBundle bundle,
  String artifactPath,
) async {
  try {
    final data = await bundle.load(localSeedSidecarPath(artifactPath));
    return decodeLocalSeedSidecar(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        ) ??
        SurfaceSections.none;
  } on Object {
    return SurfaceSections.none;
  }
}
