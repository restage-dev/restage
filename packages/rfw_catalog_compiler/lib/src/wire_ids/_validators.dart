import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Shape validators shared by the strict-parse and replay-time paths;
/// each caller passes its own exception factory.

/// Throws via [raise] when [value] is `null` or empty; returns the
/// non-null string otherwise.
String requireNonEmpty(
  String? value,
  String path,
  Exception Function(String message) raise,
) {
  if (value == null || value.isEmpty) {
    throw raise('$path must be a non-empty string');
  }
  return value;
}

/// Validates the `at` and `by` fields carried by every wire-ID event.
void validateCommonEventFields({
  required String at,
  required String by,
  required String kindName,
  required Exception Function(String message) raise,
}) {
  final parsed = DateTime.tryParse(at);
  if (at.isEmpty || parsed == null || !parsed.isUtc) {
    throw raise('$kindName.at must be ISO-8601 UTC');
  }
  if (by.isEmpty) {
    throw raise('$kindName.by must be a non-empty string');
  }
}

/// Validates the catalog's stability tier string for the event-log
/// wire form (the schema-layer surface is enum-typed; this helper
/// continues to guard the on-disk string).
void validateStability(
  String value,
  Exception Function(String message) raise,
) =>
    validateEnumName('stability', value, Stability.values, raise);

/// Validates that [value] names a [DesignTokenType] enum member.
void validateTokenType(
  String value,
  Exception Function(String message) raise,
) =>
    validateEnumName('tokenType', value, DesignTokenType.values, raise);

/// Validates that [value] matches one of the [values] member names.
/// [fieldName] appears in the error message ("$fieldName must be one of …").
void validateEnumName<T extends Enum>(
  String fieldName,
  String value,
  List<T> values,
  Exception Function(String message) raise,
) {
  for (final member in values) {
    if (member.name == value) return;
  }
  throw raise(
    '$fieldName must be one of ${values.map((m) => m.name).join(', ')}',
  );
}

/// Validates a design-token literal-fallback payload against the
/// declared [tokenType].
///
/// A `null` value is always accepted (it means "no literal fallback").
/// Otherwise the value's runtime type must match the token type's
/// expected JSON encoding (integer for color / duration / fontWeight,
/// number for length / fontSize). Unknown token types are routed back
/// through [validateTokenType] so the caller sees a consistent error.
void validateLiteralFallback(
  String tokenType,
  Object? value,
  Exception Function(String message) raise,
) {
  if (value == null) return;
  switch (tokenType) {
    case 'color':
    case 'duration':
    case 'fontWeight':
      if (value is int) return;
      throw raise(
        'literalFallback for $tokenType token must be an integer',
      );
    case 'length':
    case 'fontSize':
      if (value is num) return;
      throw raise(
        'literalFallback for $tokenType token must be a number',
      );
    default:
      validateTokenType(tokenType, raise);
  }
}

/// Validates the `{path, resolverName}` shape of a design-token
/// resolver payload.
void validateResolverShape(
  Map<String, Object?> resolver,
  Exception Function(String message) raise,
) {
  final unknown = resolver.keys.toSet().difference(
    const {'path', 'resolverName'},
  );
  if (unknown.isNotEmpty) {
    throw raise('resolver has unknown field(s): ${unknown.join(', ')}');
  }
  final path = resolver['path'];
  final resolverName = resolver['resolverName'];
  if (path == null && resolverName == null) {
    throw raise('resolver requires at least one of path or resolverName');
  }
  if (path != null && path is! String) {
    throw raise('resolver.path must be a string');
  }
  if (resolverName != null && resolverName is! String) {
    throw raise('resolver.resolverName must be a string');
  }
}

final _transitionIdPattern = RegExp(r'^tx[0-9]{4,}$');
final _hasNonZeroDigit = RegExp('[1-9]');

/// Returns whether [value] is a syntactically valid `tx*` transition
/// identifier. The suffix must contain at least one non-zero digit so
/// `tx0000` is rejected.
bool isValidTransitionId(String value) {
  if (!_transitionIdPattern.hasMatch(value)) return false;
  return _hasNonZeroDigit.hasMatch(value.substring(2));
}
