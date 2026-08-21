/// The one place a generated handle's name is derived from its source
/// declaration.
///
/// Every annotated screen and flow gets exactly one top-level handle, named by
/// lower-camel-casing the declaration's Dart name and appending `Ref`. The
/// derivation lives here rather than beside each emitter so the screen and
/// flow frontends cannot drift into two spellings of the same rule — they did,
/// and that divergence is what this module exists to prevent.
library;

/// Pascal-cases [value], dropping leading underscores and treating `_` as a
/// word separator. Falls back to [fallback] when nothing survives.
String pascalIdentifier(String value, {required String fallback}) {
  final words = value
      .replaceFirst(RegExp('^_+'), '')
      .split('_')
      .where((word) => word.isNotEmpty);
  final result = words
      .map(
        (word) => '${word.substring(0, 1).toUpperCase()}${word.substring(1)}',
      )
      .join();
  return result.isEmpty ? fallback : result;
}

/// Lower-camel-cases [value] through [pascalIdentifier].
String lowerCamelIdentifier(String value, {required String fallback}) {
  final pascal = pascalIdentifier(value, fallback: fallback);
  return '${pascal.substring(0, 1).toLowerCase()}${pascal.substring(1)}';
}

/// The single generated handle for the declaration named [declarationName].
///
/// This is the whole naming rule: `<declarationName>Ref`, lower-camel. Its
/// static type says which kind of surface it is; there is no second holder.
///
/// Every emitter that names a handle calls this. The rule is not spelled
/// inline anywhere else — that is the point of the function, and a second
/// spelling is how the screen and flow frontends drifted apart before.
String generatedHandleName(
  String declarationName, {
  required String fallback,
}) =>
    '${lowerCamelIdentifier(declarationName, fallback: fallback)}Ref';
