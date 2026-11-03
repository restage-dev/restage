import 'dart:convert';

import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:test/test.dart';

// The canonical encoding of strings and key order, through the plain-string
// path and the escaping one.
void main() {
  String encoded(Object? value) =>
      utf8.decode(CanonicalJsonCodec.encode(value));

  test('plain strings and strings that need escaping encode as before', () {
    expect(encoded('plain text'), '"plain text"');
    expect(encoded(''), '""');
    expect(encoded('a"b'), r'"a\"b"');
    expect(encoded(r'a\b'), r'"a\\b"');
    expect(encoded('\b\t\n\f\r'), r'"\b\t\n\f\r"');
    expect(encoded('\u0001x\u001f'), r'"\u0001x\u001f"');
    expect(encoded('\u007f'), '"\u007f"');
    expect(
      encoded('caf\u00e9 \u{1F600} \uE000\uFFFD'),
      '"caf\u00e9 \u{1F600} \uE000\uFFFD"',
    );
    expect(
      CanonicalJsonCodec.encode('\u{1F600}'),
      [0x22, 0xF0, 0x9F, 0x98, 0x80, 0x22],
    );
  });

  test('an unpaired surrogate is refused, in a value or a key', () {
    expect(
      () => CanonicalJsonCodec.encode('a\uD800'),
      throwsA(isA<CanonicalFormatException>()),
    );
    expect(
      () => CanonicalJsonCodec.encode({'\uDC00': 1, 'a': 2}),
      throwsA(isA<CanonicalFormatException>()),
    );
  });

  test('keys sort in UTF-8 order, with or without surrogates', () {
    expect(
      encoded({'b': 1, 'a': 2, 'ab': 3, 'B': 4}),
      '{"B":4,"a":2,"ab":3,"b":1}',
    );
    // UTF-16 puts the emoji's high surrogate before U+FFFD; UTF-8 after it.
    expect(
      encoded({'\u{1F600}': 1, '\uFFFD': 2, 'z': 3}),
      '{"z":3,"\uFFFD":2,"\u{1F600}":1}',
    );
  });
}
