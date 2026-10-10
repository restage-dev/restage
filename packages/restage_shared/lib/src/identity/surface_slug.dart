/// The grammar every surface id must match.
///
/// Surface ids travel through delivery URLs, tokens, analytics keys, and
/// generated asset paths, so they are restricted to lowercase ASCII letters,
/// digits, hyphens, and underscores, start with a letter or digit, and are at
/// most 64 characters long.
final RegExp surfaceSlugPattern = RegExp(r'^[a-z0-9][a-z0-9_-]{0,63}$');

/// The maximum length of a surface id.
const int maximumSurfaceSlugLength = 64;

/// The message shown when a surface id is refused.
const String surfaceSlugRefusalMessage =
    'A surface id must be 1 to 64 characters of lowercase letters, digits, '
    'hyphens, or underscores, and must start with a letter or digit.';

/// Whether [value] is a well-formed surface id.
bool isValidSurfaceSlug(String value) => surfaceSlugPattern.hasMatch(value);

/// Returns [value] when it is a well-formed surface id.
///
/// Throws [ArgumentError] with [surfaceSlugRefusalMessage] otherwise.
String validateSurfaceSlug(String value, {String field = 'surfaceSlug'}) {
  if (!isValidSurfaceSlug(value)) {
    throw ArgumentError.value(value, field, surfaceSlugRefusalMessage);
  }
  return value;
}
