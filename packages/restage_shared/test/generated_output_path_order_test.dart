// Proves `compareGeneratedOutputPaths` is actually reachable as shipped
// public API: this imports the documented public barrel, not a `src/` path.
// An unexported symbol isn't shipped, so only an outside-style import proves
// reachability.
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  group('compareGeneratedOutputPaths', () {
    test('orders a path before a lexicographically later sibling', () {
      expect(compareGeneratedOutputPaths('assets/a.rfw', 'assets/b.rfw'),
          lessThan(0));
      expect(compareGeneratedOutputPaths('assets/b.rfw', 'assets/a.rfw'),
          greaterThan(0));
    });

    test('treats identical paths as equal', () {
      expect(compareGeneratedOutputPaths('assets/a.rfw', 'assets/a.rfw'), 0);
    });

    test('orders a shorter prefix before a longer path that extends it', () {
      expect(
          compareGeneratedOutputPaths('assets/a', 'assets/a.rfw'), lessThan(0));
    });

    test('sorts a mixed list into ascending UTF-8 path-byte order', () {
      final paths = <String>[
        'assets/z.rfw',
        'META-INF/restage-bundle.json',
        'assets/a.rfw',
        'assets/aa.rfw',
      ]..sort(compareGeneratedOutputPaths);
      expect(paths, <String>[
        'META-INF/restage-bundle.json', // 'M' (0x4D) sorts before lowercase
        'assets/a.rfw',
        'assets/aa.rfw',
        'assets/z.rfw',
      ]);
    });

    test(
        'orders a Basic-Multilingual-Plane character before a supplementary '
        "one by code point, diverging from String's UTF-16 compareTo", () {
      const bmpChar = '\u{F000}'; // single UTF-16 code unit
      const supplementaryChar = '\u{10000}'; // UTF-16 surrogate pair

      // True UTF-8 byte order (and code point order): U+F000 < U+10000.
      expect(
        compareGeneratedOutputPaths(bmpChar, supplementaryChar),
        lessThan(0),
      );
      expect(
        compareGeneratedOutputPaths(supplementaryChar, bmpChar),
        greaterThan(0),
      );

      // Dart's default String.compareTo walks UTF-16 code units: the
      // supplementary character's leading surrogate (U+D800) is numerically
      // lower than the single-unit U+F000, so naive code-unit comparison
      // disagrees with the correct byte/code-point order pinned above.
      expect(bmpChar.compareTo(supplementaryChar), greaterThan(0));
    });

    test('rejects an unpaired UTF-16 surrogate', () {
      expect(
        () => compareGeneratedOutputPaths('\uD800', 'assets/a.rfw'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
