import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/widgets.dart' show Offset, Rect;
import 'package:restage_preview_host/src/document_path_codec.dart';

/// The authored node and frame-relative rectangle selected by a geometry hit.
@immutable
final class GeometryHit {
  /// Create a geometry hit.
  const GeometryHit({
    required this.encodedPath,
    required this.compactPath,
    required this.rect,
  });

  /// JSON-encoded compact path used as the geometry-map key.
  final String encodedPath;

  /// Decoded compact authored path.
  final List<Object> compactPath;

  /// Node rectangle in logical device-frame coordinates.
  final Rect rect;
}

/// Resolve [point] against a frame-relative authored-node geometry map.
///
/// The deepest authored node wins. A list index identifies sibling order but
/// does not add authored depth. Ties prefer the later sibling (the last index
/// in the compact path), then the smallest rectangle. Malformed keys are
/// ignored so invalid preview metadata cannot reach shell interaction state.
GeometryHit? hitTestGeometry(Map<String, Rect> geometry, Offset point) {
  final hits = orderedGeometryHits(geometry, point);
  return hits.isEmpty ? null : hits.first;
}

/// Return every authored-node geometry hit at [point] in canonical priority.
///
/// Provider-neutral shell consumers use this chain when the highest-priority
/// hit is not actionable and an ancestor or overlapping peer may be. Authored
/// string depth wins first; list indices affect only the later-sibling tie;
/// smaller rectangles win next. Map iteration order is retained for all
/// remaining ties. Malformed geometry keys are ignored.
List<GeometryHit> orderedGeometryHits(
  Map<String, Rect> geometry,
  Offset point,
) {
  final candidates = <_GeometryHitCandidate>[];
  var order = 0;

  for (final entry in geometry.entries) {
    final currentOrder = order++;
    if (!entry.value.contains(point)) continue;

    final List<Object> path;
    try {
      path = DocumentPathCodec.decode(entry.key);
    } on FormatException {
      continue;
    }
    final depth = path.whereType<String>().length - 1;
    final sibling = _lastSiblingIndex(path);
    final area = entry.value.width * entry.value.height;
    candidates.add(
      _GeometryHitCandidate(
        hit: GeometryHit(
          encodedPath: entry.key,
          compactPath: path,
          rect: entry.value,
        ),
        authoredDepth: depth,
        trailingSibling: sibling,
        area: area,
        order: currentOrder,
      ),
    );
  }
  candidates.sort(_compareCandidates);
  return List<GeometryHit>.unmodifiable(
    candidates.map((candidate) => candidate.hit),
  );
}

int _compareCandidates(
  _GeometryHitCandidate first,
  _GeometryHitCandidate second,
) {
  final depth = second.authoredDepth.compareTo(first.authoredDepth);
  if (depth != 0) return depth;
  final sibling = second.trailingSibling.compareTo(first.trailingSibling);
  if (sibling != 0) return sibling;
  final area = first.area.compareTo(second.area);
  if (area != 0) return area;
  return first.order.compareTo(second.order);
}

int _lastSiblingIndex(List<Object> path) {
  for (var index = path.length - 1; index >= 0; index--) {
    final segment = path[index];
    if (segment is int) return segment;
  }
  return -1;
}

final class _GeometryHitCandidate {
  const _GeometryHitCandidate({
    required this.hit,
    required this.authoredDepth,
    required this.trailingSibling,
    required this.area,
    required this.order,
  });

  final GeometryHit hit;
  final int authoredDepth;
  final int trailingSibling;
  final double area;
  final int order;
}
