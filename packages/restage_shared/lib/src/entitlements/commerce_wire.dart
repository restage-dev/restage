/// Store values accepted by commerce requests.
const commerceAppStoreValue = 'app_store';
const commercePlayStoreValue = 'play_store';
const commerceStoreValues = {commerceAppStoreValue, commercePlayStoreValue};
final _commerceOfferIdPattern = RegExp(r'^[a-z][a-z0-9._-]{0,127}$');

/// Rejects fields outside a request's wire shape.
void rejectUnknownCommerceFields(
  Map<String, dynamic> json,
  Set<String> allowed,
) {
  for (final key in json.keys) {
    if (!allowed.contains(key)) {
      throw ArgumentError.value(key, 'json', 'Unsupported field');
    }
  }
}

/// Reads a required non-empty string.
String requiredCommerceString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) return value;
  throw ArgumentError.value(value, key, 'Expected a non-empty string');
}

/// Reads an optional non-empty string.
String? optionalCommerceString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is String && value.isNotEmpty) return value;
  throw ArgumentError.value(value, key, 'Expected a non-empty string or null');
}

/// Reads an optional integer.
int? optionalCommerceInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null || value is int) return value as int?;
  throw ArgumentError.value(value, key, 'Expected an int or null');
}

/// Reads a required list of non-empty strings.
List<String> requiredCommerceStringList(
  Map<String, dynamic> json,
  String key,
) {
  final value = json[key];
  if (value is! List) {
    throw ArgumentError.value(value, key, 'Expected a list of strings');
  }
  return [
    for (final entry in value)
      if (entry is String && entry.isNotEmpty)
        entry
      else
        throw ArgumentError.value(
          value,
          key,
          'Expected a list of non-empty strings',
        ),
  ];
}

/// Reads a required UUIDv4.
String requiredCommerceUuidV4(
  Map<String, dynamic> json,
  String key, {
  bool lowercase = true,
}) {
  final value = requiredCommerceString(json, key);
  requireCommerceUuidV4(value, key, lowercase: lowercase);
  return value;
}

/// Validates a UUIDv4 value.
void requireCommerceUuidV4(
  String value,
  String key, {
  bool lowercase = true,
}) {
  if (!_isUuidV4(value) || (lowercase && value != value.toLowerCase())) {
    throw ArgumentError.value(value, key, 'Expected a canonical UUID v4');
  }
}

/// Validates a logical offer identifier.
void requireCommerceOfferId(String value, String key) {
  if (!_commerceOfferIdPattern.hasMatch(value)) {
    throw ArgumentError.value(
      value,
      key,
      'Expected a logical offer identifier',
    );
  }
}

/// Reads an ISO-8601 timestamp in UTC.
DateTime requiredCommerceDateTime(Map<String, dynamic> json, String key) {
  final value = requiredCommerceString(json, key);
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw ArgumentError.value(value, key, 'Expected an ISO-8601 timestamp');
  }
  return parsed.toUtc();
}

/// Preserves known response codes and maps later additions to unknown.
String normalizeCommerceResponseCode(String value, Set<String> known) =>
    known.contains(value) ? value : 'unknown';

bool _isUuidV4(String value) {
  if (value.length != 36) return false;
  for (var i = 0; i < value.length; i += 1) {
    final codeUnit = value.codeUnitAt(i);
    if (i == 8 || i == 13 || i == 18 || i == 23) {
      if (codeUnit != 0x2d) return false;
      continue;
    }
    final isHex = (codeUnit >= 0x30 && codeUnit <= 0x39) ||
        (codeUnit >= 0x41 && codeUnit <= 0x46) ||
        (codeUnit >= 0x61 && codeUnit <= 0x66);
    if (!isHex) return false;
  }
  if (value.codeUnitAt(14) != 0x34) return false;
  final variant = value.codeUnitAt(19);
  return variant == 0x38 ||
      variant == 0x39 ||
      variant == 0x41 ||
      variant == 0x42 ||
      variant == 0x61 ||
      variant == 0x62;
}
