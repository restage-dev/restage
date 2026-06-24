/// Returns the first Dartdoc paragraph without leading comment markers.
String? stripDartdocSlashes(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final stripped = <String>[];
  for (final line in raw.split('\n')) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('///')) {
      stripped.add(trimmed.substring(3).trimLeft());
    } else if (trimmed.startsWith('/**') ||
        trimmed.startsWith('*/') ||
        trimmed == '*') {
      continue;
    } else if (trimmed.startsWith('* ')) {
      stripped.add(trimmed.substring(2));
    } else {
      stripped.add(trimmed);
    }
  }
  final firstParagraph = <String>[];
  for (final line in stripped) {
    if (line.isEmpty) {
      if (firstParagraph.isNotEmpty) break;
      continue;
    }
    firstParagraph.add(line);
  }
  if (firstParagraph.isEmpty) return null;
  return firstParagraph.join(' ').trim();
}
