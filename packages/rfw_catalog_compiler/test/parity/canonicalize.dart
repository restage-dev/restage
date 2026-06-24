import 'dart:convert';

/// Returns a deterministic JSON string for semantic catalog comparisons.
///
/// JSON objects are sorted recursively by key and emitted with two-space
/// indentation. Lists keep their original order because catalog order remains
/// part of the consumer-visible shape.
String canonicalizeJson(Object? value) {
  final normalized = _canonicalize(value);
  return '${const JsonEncoder.withIndent('  ').convert(normalized)}\n';
}

/// Decodes [source] as JSON and returns its deterministic representation.
String canonicalizeJsonSource(String source) {
  return canonicalizeJson(jsonDecode(source));
}

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return {
      for (final key in keys) key: _canonicalize(value[key]),
    };
  }
  if (value is List) {
    return [
      for (final item in value) _canonicalize(item),
    ];
  }
  return value;
}
