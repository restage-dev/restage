import 'package:flutter/widgets.dart';

import 'document_path_codec.dart';
import 'geometry_registry.dart' show GeometryInstance;

void validatePositiveFrame(Size frame, {required String argumentName}) {
  if (!frame.width.isFinite ||
      !frame.height.isFinite ||
      frame.width <= 0 ||
      frame.height <= 0) {
    throw ArgumentError.value(
      frame,
      argumentName,
      'must contain finite positive dimensions',
    );
  }
}

Map<String, Rect> snapshotGeometry(
  Map<String, Rect> source, {
  required String argumentName,
}) {
  validateGeometry(source, argumentName: argumentName);
  return Map<String, Rect>.unmodifiable(source);
}

void validateGeometry(
  Map<String, Rect> rects, {
  required String argumentName,
}) {
  final identities = <String>{};
  for (final entry in rects.entries) {
    final List<Object> path;
    try {
      path = DocumentPathCodec.decode(entry.key);
    } on FormatException catch (error) {
      throw ArgumentError.value(
        entry.key,
        argumentName,
        'geometry keys must be canonical authored paths: ${error.message}',
      );
    }
    final identity = DocumentPathCodec.encode(path);
    if (!identities.add(identity)) {
      throw ArgumentError.value(
        entry.key,
        argumentName,
        'geometry keys must not repeat an authored-path identity',
      );
    }
    final rect = entry.value;
    if (!rect.left.isFinite ||
        !rect.top.isFinite ||
        !rect.width.isFinite ||
        !rect.height.isFinite ||
        rect.width < 0 ||
        rect.height < 0) {
      throw ArgumentError.value(
        rect,
        argumentName,
        'rects must have finite coordinates and non-negative dimensions',
      );
    }
  }
}

/// Every instance of every path in [rects]; a path [instances] omits has its
/// one rect. Each listed path must lead with its rect in [rects].
Map<String, List<GeometryInstance>> snapshotInstances(
  Map<String, Rect> rects,
  Map<String, List<GeometryInstance>>? instances, {
  required String argumentName,
}) {
  final result = <String, List<GeometryInstance>>{
    for (final entry in rects.entries)
      entry.key: List<GeometryInstance>.unmodifiable(
        <GeometryInstance>[GeometryInstance(entry.value)],
      ),
  };
  for (final entry in (instances ?? const {}).entries) {
    final list = entry.value;
    if (list.isEmpty || rects[entry.key] != list.first.rect) {
      throw ArgumentError.value(
        entry.key,
        argumentName,
        'instances must lead with the rect their path reports',
      );
    }
    for (final instance in list) {
      for (final rect in <Rect?>[instance.rect, instance.visibleRect]) {
        if (rect == null) continue;
        validateGeometry(
          <String, Rect>{entry.key: rect},
          argumentName: argumentName,
        );
      }
    }
    result[entry.key] = List<GeometryInstance>.unmodifiable(list);
  }
  return Map<String, List<GeometryInstance>>.unmodifiable(result);
}

/// The wire form of every path drawn more than once, naming an item, or
/// clipped. A clipped instance carries `visible`, null when hidden.
Map<String, Object?> encodeGeometryInstances(
  Map<String, List<GeometryInstance>> instances,
) =>
    <String, Object?>{
      for (final entry in instances.entries)
        if (entry.value.length > 1 ||
            entry.value.any(
              (instance) => instance.item != null || instance.isClipped,
            ))
          entry.key: <Object?>[
            for (final instance in entry.value)
              <String, Object?>{
                'rect': encodeGeometryRect(instance.rect),
                if (instance.item != null) 'item': instance.item,
                if (instance.isClipped)
                  'visible': switch (instance.visibleRect) {
                    final visible? => encodeGeometryRect(visible),
                    null => null,
                  },
              },
          ],
    };

/// The wire form of one rect: left, top, width, height.
List<double> encodeGeometryRect(Rect rect) =>
    <double>[rect.left, rect.top, rect.width, rect.height];
