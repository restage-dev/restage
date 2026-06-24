import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

void main() {
  group('WireId', () {
    test('parses kind prefix and sequence', () {
      final id = WireId('w0042');
      expect(id.kind, WireIdKind.widget);
      expect(id.sequence, 42);
      expect(id.value, 'w0042');
    });

    test('round-trips through all six kinds', () {
      const kindForPrefix = {
        'w0001': WireIdKind.widget,
        'p0001': WireIdKind.property,
        's0001': WireIdKind.structured,
        'v0001': WireIdKind.variant,
        'u0001': WireIdKind.union,
        't0001': WireIdKind.designToken,
      };
      for (final entry in kindForPrefix.entries) {
        final id = WireId(entry.key);
        expect(id.kind, entry.value);
        expect(id.value, entry.key);
      }
    });

    test('parameter IDs use the a prefix and expose a sentinel', () {
      final id = WireId('a0001');

      expect(id.kind, WireIdKind.parameter);
      expect(id.sequence, 1);
      expect(id.value, 'a0001');
      expect(WireId.unallocated(WireIdKind.parameter).value, 'a0000');
    });

    test('parameter sentinel cannot be constructed from public text', () {
      expect(() => WireId('a0000'), throwsArgumentError);
    });

    test('rejects too-short input', () {
      expect(() => WireId('w12'), throwsArgumentError);
    });

    test('rejects unknown kind prefix', () {
      expect(
        () => WireId('z0001'),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            contains('w/p/s/v/u/t/a'),
          ),
        ),
      );
    });

    test('rejects non-numeric sequence', () {
      expect(() => WireId('w0xab'), throwsArgumentError);
    });

    test('rejects negative sequence', () {
      expect(() => WireId('w-001'), throwsArgumentError);
    });

    test('rejects reserved zero sequence sentinels', () {
      expect(() => WireId('w0000'), throwsArgumentError);
      expect(() => WireId('p0000'), throwsArgumentError);
    });

    test('equality is value-based', () {
      expect(WireId('w0001'), WireId('w0001'));
      expect(WireId('w0001').hashCode, WireId('w0001').hashCode);
      expect(WireId('w0001'), isNot(WireId('w0002')));
      expect(WireId('w0001'), isNot(WireId('p0001')));
    });

    test('toString returns the string form', () {
      expect(WireId('w0042').toString(), 'w0042');
    });

    test('preserves sequence for high-digit IDs', () {
      // Canonical high-digit form: padLeft(4) is a no-op past four digits,
      // so the sequence carries no extra leading zero.
      final id = WireId('p12345');
      expect(id.kind, WireIdKind.property);
      expect(id.sequence, 12345);
    });

    test('rejects non-canonical spellings of the same sequence', () {
      // All of these parse to a positive sequence but are not the canonical
      // zero-padded spelling, so they would compare unequal to the canonical
      // wire ID despite naming the same (kind, sequence). The constructor
      // must reject them so string equality matches identity.
      for (final nonCanonical in [
        'w+123', // leading sign
        'w 123', // leading whitespace
        'w123 ', // trailing whitespace
        'w\t123', // embedded tab
        'w00001', // extra zero-padding (canonical is w0001)
        'p012345', // extra zero-padding past four digits (canonical p12345)
      ]) {
        expect(
          () => WireId(nonCanonical),
          throwsArgumentError,
          reason: '"$nonCanonical" is not canonical and must be rejected',
        );
      }
    });

    test('non-canonical and canonical forms never coexist as equal', () {
      // The whole point of the guard: a value that survives construction is
      // the unique canonical spelling, so equality-by-string is sound.
      expect(WireId('w0001').value, 'w0001');
      expect(() => WireId('w00001'), throwsArgumentError);
    });
  });

  group('WireIdKind prefixes', () {
    test('expose single-character prefix strings', () {
      expect(WireIdKind.widget.prefix, 'w');
      expect(WireIdKind.property.prefix, 'p');
      expect(WireIdKind.structured.prefix, 's');
      expect(WireIdKind.variant.prefix, 'v');
      expect(WireIdKind.union.prefix, 'u');
      expect(WireIdKind.designToken.prefix, 't');
      expect(WireIdKind.parameter.prefix, 'a');
    });
  });

  group('WireIdRef', () {
    test('equality is library + wireId based', () {
      const lib = 'restage.core';
      expect(
        WireIdRef(library: lib, wireId: WireId('w0001')),
        WireIdRef(library: lib, wireId: WireId('w0001')),
      );
      expect(
        WireIdRef(library: lib, wireId: WireId('w0001')),
        isNot(WireIdRef(library: lib, wireId: WireId('w0002'))),
      );
      expect(
        WireIdRef(library: lib, wireId: WireId('w0001')),
        isNot(WireIdRef(library: 'other', wireId: WireId('w0001'))),
      );
    });

    test('toString renders library:wireId', () {
      final ref = WireIdRef(library: 'restage.core', wireId: WireId('w0042'));
      expect(ref.toString(), 'restage.core:w0042');
    });
  });
}
