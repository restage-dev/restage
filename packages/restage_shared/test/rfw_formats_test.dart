// Smoke test for the vendored rfw `formats` sublibrary.
//
// Confirms the dedicated rfw_formats barrel re-exports the parser and the
// binary encoder/decoder, and that a tiny .rfwtxt source survives a parse →
// encode → decode → re-encode round-trip with byte-identical output.

import 'package:restage_shared/rfw_formats.dart';
import 'package:test/test.dart';

void main() {
  group('vendored rfw formats — library round-trip', () {
    test('parse → encode → decode → re-encode is byte-identical', () {
      // A small but non-trivial .rfwtxt source exercising imports, an
      // initialState (stateful widget), an args reference, and a switch.
      const source = '''
import core.widgets;

widget Hello = Container(
  child: Text(text: "hello"),
);

widget Counter { count: 0 } = Container(
  child: switch args.theme {
    "dark": Text(text: "dark"),
    "light": Text(text: "light"),
    default: Text(text: "default"),
  },
);
''';

      final parsed = parseLibraryFile(source);
      expect(parsed.imports, hasLength(1));
      expect(
        parsed.imports.single.name.parts,
        equals(<String>['core', 'widgets']),
      );
      expect(parsed.widgets, hasLength(2));
      expect(parsed.widgets[0].name, equals('Hello'));
      expect(parsed.widgets[1].name, equals('Counter'));
      expect(parsed.widgets[1].initialState, isNotNull);
      expect(parsed.widgets[1].initialState!['count'], equals(0));

      final encodedOnce = encodeLibraryBlob(parsed);
      final decoded = decodeLibraryBlob(encodedOnce);
      final encodedTwice = encodeLibraryBlob(decoded);

      expect(
        encodedTwice,
        orderedEquals(encodedOnce),
        reason: 'Re-encoding the decoded library must be byte-identical '
            'to the original encoding.',
      );
    });
  });

  group('vendored rfw formats — data round-trip', () {
    test('parseDataFile → encodeDataBlob → decodeDataBlob is deep-equal', () {
      final parsed = parseDataFile('{ greeting: "hello", count: 42 }');
      expect(
        parsed,
        equals(<String, Object?>{
          'greeting': 'hello',
          'count': 42,
        }),
      );

      final encoded = encodeDataBlob(parsed);
      final decoded = decodeDataBlob(encoded);

      expect(
        decoded,
        equals(<String, Object?>{
          'greeting': 'hello',
          'count': 42,
        }),
      );

      // Re-encoding the decoded value should also be byte-identical, which
      // tells us the binary form stable-round-trips.
      expect(
        encodeDataBlob(decoded),
        orderedEquals(encoded),
      );
    });
  });
}
