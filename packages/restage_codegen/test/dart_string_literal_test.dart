import 'dart:convert';

import 'package:restage_codegen/src/emit_utils.dart';
import 'package:test/test.dart';

void main() {
  test('lone surrogates stay escaped', () {
    const value = 'a\uD800b\uDC00c';

    final literal = dartStringLiteral(value);

    expect(literal, r"'a\ud800b\udc00c'");
    expect(() => utf8.encode(literal), returnsNormally);
    expect(utf8.decode(utf8.encode(literal)), literal);
  });

  test('a surrogate pair stays one character', () {
    expect(dartStringLiteral('\u{1F600}'), "'\u{1F600}'");
  });

  test(r'quotes, backslashes and $ never break the literal', () {
    expect(dartStringLiteral(r"it's $x \ y"), r"'it\'s \$x \\ y'");
  });
}
