/// Directory, relative to the app package, that holds release receipts.
const String receiptsDirectory = '.restage/receipts';

/// [value] reduced to one receipt path segment: lower case, with every
/// character other than an ASCII letter, digit, `.` or `_` replaced by `-`.
String receiptPathSegment(String value) {
  final buffer = StringBuffer();
  for (final rune in value.toLowerCase().runes) {
    final isDigit = rune >= 0x30 && rune <= 0x39;
    final isLetter = rune >= 0x61 && rune <= 0x7a;
    final isMark = rune == 0x2e || rune == 0x5f;
    buffer
        .write(isDigit || isLetter || isMark ? String.fromCharCode(rune) : '-');
  }
  final segment = buffer.toString();
  return segment.isEmpty ? 'unnamed' : segment;
}
