import 'dart:typed_data';

import 'package:restage_codegen/src/a2ui/rfc8785_canonical_json.dart';
import 'package:test/test.dart';

double _doubleFromBits(String hexadecimal) {
  final bytes = ByteData(8)
    ..setUint32(
      0,
      int.parse(hexadecimal.substring(0, 8), radix: 16),
    )
    ..setUint32(4, int.parse(hexadecimal.substring(8), radix: 16));
  return bytes.getFloat64(0);
}

void main() {
  group('canonicalizeJsonRfc8785', () {
    test('matches the complete RFC 8785 Appendix B number corpus', () {
      const finite = <(String, String)>[
        ('0000000000000000', '0'),
        ('8000000000000000', '0'),
        ('0000000000000001', '5e-324'),
        ('8000000000000001', '-5e-324'),
        ('7fefffffffffffff', '1.7976931348623157e+308'),
        ('ffefffffffffffff', '-1.7976931348623157e+308'),
        ('4340000000000000', '9007199254740992'),
        ('c340000000000000', '-9007199254740992'),
        ('4430000000000000', '295147905179352830000'),
        ('44b52d02c7e14af5', '9.999999999999997e+22'),
        ('44b52d02c7e14af6', '1e+23'),
        ('44b52d02c7e14af7', '1.0000000000000001e+23'),
        ('444b1ae4d6e2ef4e', '999999999999999700000'),
        ('444b1ae4d6e2ef4f', '999999999999999900000'),
        ('444b1ae4d6e2ef50', '1e+21'),
        ('3eb0c6f7a0b5ed8c', '9.999999999999997e-7'),
        ('3eb0c6f7a0b5ed8d', '0.000001'),
        ('41b3de4355555553', '333333333.3333332'),
        ('41b3de4355555554', '333333333.33333325'),
        ('41b3de4355555555', '333333333.3333333'),
        ('41b3de4355555556', '333333333.3333334'),
        ('41b3de4355555557', '333333333.33333343'),
        ('becbf647612f3696', '-0.0000033333333333333333'),
        ('43143ff3c1cb0959', '1424953923781206.2'),
      ];

      for (final (bits, expected) in finite) {
        expect(
          canonicalizeJsonRfc8785(_doubleFromBits(bits)),
          expected,
          reason: 'IEEE 754 bits $bits',
        );
      }

      for (final bits in ['7fffffffffffffff', '7ff0000000000000']) {
        expect(
          () => canonicalizeJsonRfc8785(_doubleFromBits(bits)),
          throwsFormatException,
          reason: 'non-finite IEEE 754 bits $bits',
        );
      }
    });

    test('rejects Dart integers that are not exact binary64 values', () {
      for (final value in [
        int.parse('9007199254740993'),
        int.parse('9223372036854775807'),
      ]) {
        expect(
          () => canonicalizeJsonRfc8785(value),
          throwsFormatException,
          reason: '$value is not exactly representable as binary64',
        );
      }
    });

    test('admits exactly representable integers beyond the safe range', () {
      expect(
        canonicalizeJsonRfc8785(int.parse('9007199254740992')),
        '9007199254740992',
      );
      expect(
        canonicalizeJsonRfc8785(int.parse('4611686018427387904')),
        '4611686018427388000',
      );
    });

    test('uses the RFC 8785 section 3.2.2 string escaping rules', () {
      expect(
        canonicalizeJsonRfc8785("\u20ac\$\u000f\nA'B\"\\\\\"/"),
        r'''"€$\u000f\nA'B\"\\\\\"/"''',
      );
      expect(
        canonicalizeJsonRfc8785('\b\t\n\f\r\u0000\u001f'),
        r'''"\b\t\n\f\r\u0000\u001f"''',
      );
    });

    test('rejects lone UTF-16 surrogates instead of emitting invalid Unicode',
        () {
      expect(
        () => canonicalizeJsonRfc8785(String.fromCharCode(0xd800)),
        throwsFormatException,
      );
      expect(
        () => canonicalizeJsonRfc8785(String.fromCharCode(0xdead)),
        throwsFormatException,
      );
    });

    test('matches the RFC 8785 section 3.2.3 UTF-16 property order', () {
      final value = <String, Object?>{
        '\ufb33': 'Hebrew Letter Dalet With Dagesh',
        '\ud83d\ude00': 'Emoji: Grinning Face',
        '\u20ac': 'Euro Sign',
        '\u00f6': 'Latin Small Letter O With Diaeresis',
        '\u0080': 'Control',
        '1': 'One',
        '\r': 'Carriage Return',
      };

      expect(
        canonicalizeJsonRfc8785(value),
        r'''{"\r":"Carriage Return","1":"One","":"Control","ö":"Latin Small Letter O With Diaeresis","€":"Euro Sign","😀":"Emoji: Grinning Face","דּ":"Hebrew Letter Dalet With Dagesh"}''',
      );
    });

    test('sorts nested object keys recursively and preserves array order', () {
      final first = <String, Object?>{
        'z': [
          {'b': 2, 'a': 1},
          'second',
          'first',
        ],
        'a': {
          'd': {'y': false, 'x': true},
          'c': null,
        },
      };
      final reordered = <String, Object?>{
        'a': {
          'c': null,
          'd': {'x': true, 'y': false},
        },
        'z': [
          {'a': 1, 'b': 2},
          'second',
          'first',
        ],
      };

      expect(
        canonicalizeJsonRfc8785(first),
        canonicalizeJsonRfc8785(reordered),
      );
      expect(
        canonicalizeJsonRfc8785(first),
        '''{"a":{"c":null,"d":{"x":true,"y":false}},"z":[{"a":1,"b":2},"second","first"]}''',
      );
    });
  });
}
