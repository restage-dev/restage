import 'package:flutter/widgets.dart';

import 'document_path_codec.dart';

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
