/// Serializes [value] using the JSON Canonicalization Scheme from RFC 8785.
///
/// The accepted value tree is the I-JSON subset: `null`, booleans, finite
/// IEEE-754 numbers, Unicode strings, lists, and maps with string keys. Object
/// keys are ordered by unsigned UTF-16 code units, arrays retain their input
/// order, and invalid Unicode or non-finite numbers fail loudly.
String canonicalizeJsonRfc8785(Object? value) {
  final output = StringBuffer();
  _writeCanonicalJson(output, value);
  return output.toString();
}

void _writeCanonicalJson(StringBuffer output, Object? value) {
  switch (value) {
    case null:
      output.write('null');
    case bool():
      output.write(value ? 'true' : 'false');
    case num():
      output.write(_serializeNumber(value));
    case String():
      _writeString(output, value);
    case List<Object?>():
      output.write('[');
      for (var index = 0; index < value.length; index++) {
        if (index != 0) output.write(',');
        _writeCanonicalJson(output, value[index]);
      }
      output.write(']');
    case Map<Object?, Object?>():
      final entries = <MapEntry<String, Object?>>[];
      for (final entry in value.entries) {
        final key = entry.key;
        if (key is! String) {
          throw FormatException(
            'RFC 8785 object keys must be strings; found ${key.runtimeType}.',
          );
        }
        entries.add(MapEntry(key, entry.value));
      }
      entries.sort((a, b) => _compareUtf16(a.key, b.key));
      output.write('{');
      for (var index = 0; index < entries.length; index++) {
        if (index != 0) output.write(',');
        final entry = entries[index];
        _writeString(output, entry.key);
        output.write(':');
        _writeCanonicalJson(output, entry.value);
      }
      output.write('}');
    default:
      throw FormatException(
        'RFC 8785 cannot serialize ${value.runtimeType}; '
        'the value is not JSON-safe.',
      );
  }
}

String _serializeNumber(num value) {
  final ieee754 = value.toDouble();
  if (!ieee754.isFinite) {
    throw FormatException(
      'RFC 8785 cannot serialize non-finite number $value.',
    );
  }
  if (value is int && BigInt.from(ieee754) != BigInt.from(value)) {
    throw FormatException(
      'RFC 8785 cannot serialize integer $value because it is not exactly '
      'representable as an IEEE-754 binary64 value. Encode higher-precision '
      'integers as strings.',
    );
  }
  if (ieee754 == 0) return '0';

  // Dart and ECMAScript both use a shortest-round-tripping binary64 decimal
  // conversion. Dart retains `.0` for an integral double; ECMAScript's JSON
  // number form does not, so remove only that redundant suffix (including
  // immediately before an exponent). Exponent thresholds and signs already
  // match the ECMAScript form pinned by RFC 8785 Appendix B.
  final shortest = ieee754.toString();
  final exponent = shortest.indexOf('e');
  if (exponent == -1) return _stripIntegralDoubleSuffix(shortest);
  final normalized = _stripIntegralDoubleSuffix(
    shortest.substring(0, exponent),
  );
  return '$normalized${shortest.substring(exponent)}';
}

String _stripIntegralDoubleSuffix(String value) =>
    value.endsWith('.0') ? value.substring(0, value.length - 2) : value;

void _writeString(StringBuffer output, String value) {
  output.write('"');
  for (var index = 0; index < value.length; index++) {
    final codeUnit = value.codeUnitAt(index);
    if (_isHighSurrogate(codeUnit)) {
      if (index + 1 >= value.length ||
          !_isLowSurrogate(value.codeUnitAt(index + 1))) {
        throw const FormatException(
          'RFC 8785 cannot serialize a lone high UTF-16 surrogate.',
        );
      }
      output
        ..writeCharCode(codeUnit)
        ..writeCharCode(value.codeUnitAt(++index));
      continue;
    }
    if (_isLowSurrogate(codeUnit)) {
      throw const FormatException(
        'RFC 8785 cannot serialize a lone low UTF-16 surrogate.',
      );
    }
    switch (codeUnit) {
      case 0x08:
        output.write(r'\b');
      case 0x09:
        output.write(r'\t');
      case 0x0a:
        output.write(r'\n');
      case 0x0c:
        output.write(r'\f');
      case 0x0d:
        output.write(r'\r');
      case 0x22:
        output.write(r'\"');
      case 0x5c:
        output.write(r'\\');
      default:
        if (codeUnit <= 0x1f) {
          output
            ..write(r'\u')
            ..write(codeUnit.toRadixString(16).padLeft(4, '0'));
        } else {
          output.writeCharCode(codeUnit);
        }
    }
  }
  output.write('"');
}

int _compareUtf16(String a, String b) {
  final commonLength = a.length < b.length ? a.length : b.length;
  for (var index = 0; index < commonLength; index++) {
    final difference = a.codeUnitAt(index) - b.codeUnitAt(index);
    if (difference != 0) return difference;
  }
  return a.length - b.length;
}

bool _isHighSurrogate(int codeUnit) => codeUnit >= 0xd800 && codeUnit <= 0xdbff;

bool _isLowSurrogate(int codeUnit) => codeUnit >= 0xdc00 && codeUnit <= 0xdfff;
