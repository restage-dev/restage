import 'dart:math';

/// Returns true when [value] is a canonical UUIDv4 string.
bool isValidUuidV4(String value) {
  if (value.length != 36) return false;
  for (var i = 0; i < value.length; i++) {
    final c = value.codeUnitAt(i);
    if (i == 8 || i == 13 || i == 18 || i == 23) {
      if (c != 0x2D) return false;
      continue;
    }
    final isHex = (c >= 0x30 && c <= 0x39) ||
        (c >= 0x61 && c <= 0x66) ||
        (c >= 0x41 && c <= 0x46);
    if (!isHex) return false;
  }
  if (value.codeUnitAt(14) != 0x34) return false;
  final variant = value.codeUnitAt(19);
  return variant == 0x38 ||
      variant == 0x39 ||
      variant == 0x61 ||
      variant == 0x62 ||
      variant == 0x41 ||
      variant == 0x42;
}

/// Generates a canonical UUIDv4 using a secure random source by default.
String generateUuidV4({Random? random}) {
  final source = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => source.nextInt(256));
  bytes[6] = (bytes[6] & 0x0F) | 0x40;
  bytes[8] = (bytes[8] & 0x3F) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}
