import 'dart:convert' show jsonDecode, jsonEncode;

/// Strict JSON codec for compact authored-widget paths.
///
/// A compact path starts with a widget declaration name, then repeats a slot
/// name and an optional non-negative list index. Slot names are opaque: in
/// particular, `args` is a valid authored slot and has no structural meaning
/// in this representation.
abstract final class DocumentPathCodec {
  /// Encode [path] as the compact JSON representation used by marker keys.
  static String encode(List<Object> path) => jsonEncode(validate(path));

  /// Decode and validate a compact JSON marker key.
  static List<Object> decode(String encoded) {
    final Object? decoded = jsonDecode(encoded);
    if (decoded is! List<Object?>) {
      throw const FormatException('Document path must be a JSON array.');
    }
    final path = validate(decoded);
    if (jsonEncode(path) != encoded) {
      throw const FormatException(
        'Document path must use its canonical JSON encoding.',
      );
    }
    return path;
  }

  /// Validate [path] and return an immutable copy.
  static List<Object> validate(List<Object?> path) {
    if (path.isEmpty || path.first is! String) {
      throw const FormatException(
        'Document path must start with a widget declaration name.',
      );
    }

    final validated = <Object>[path.first!];
    for (var index = 1; index < path.length; index++) {
      final segment = path[index];
      if (segment is String) {
        validated.add(segment);
        continue;
      }
      if (segment is int &&
          segment >= 0 &&
          index > 1 &&
          path[index - 1] is String) {
        validated.add(segment);
        continue;
      }
      throw FormatException(
        'Invalid compact document-path segment at index $index.',
      );
    }
    return List<Object>.unmodifiable(validated);
  }
}
