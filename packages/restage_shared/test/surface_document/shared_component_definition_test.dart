import 'dart:typed_data';

import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart'
    show decodeLibraryBlob, encodeLibraryBlob, parseLibraryFile;
import 'package:test/test.dart';

Uint8List _blob(String text) => encodeLibraryBlob(parseLibraryFile(text));

const _surface = '''
import core;
widget Pill = Padding(padding: [4.0], child: Text(text: args.label));
widget Card = Column(children: [Pill(label: args.a), Badge()]);
widget Badge = Text(text: "new");
widget root = Card(a: "Pro");
''';

void main() {
  group('a shared component', () {
    test('built from a surface fingerprints as the copy in it', () {
      final surface = _blob(_surface);
      final component = componentLibraryBlob(surface, 'Card');
      final library = decodeLibraryBlob(component);
      expect(
          [for (final w in library.widgets) w.name], ['main', 'Badge', 'Pill']);
      final copy = componentFingerprint(surface, 'Card', const {});
      final version =
          componentFingerprint(component, kSharedComponentEntryName, const {});
      expect(version.fingerprint, copy.fingerprint);
      expect(copy.parts, ['Pill', 'Badge']);
      expect(componentReachedDeclarations(surface, 'Card'), {'Pill', 'Badge'});
    });

    for (final (name, edited, same) in [
      ('renaming a part', _surface.replaceAll('Pill', 'Chip'), true),
      (
        'reordering map keys',
        _surface.replaceFirst(
            'Padding(padding: [4.0], child: Text(text: args.label))',
            'Padding(child: Text(text: args.label), padding: [4.0])'),
        true,
      ),
      ('changing a value', _surface.replaceFirst('4.0', '8.0'), false),
      ('changing a part', _surface.replaceFirst('"new"', '"hot"'), false),
    ]) {
      test('${same ? 'keeps' : 'changes'} its fingerprint on $name', () {
        final before = componentFingerprint(_blob(_surface), 'Card', const {});
        final after = componentFingerprint(_blob(edited), 'Card', const {});
        expect(after.fingerprint == before.fingerprint, same);
      });
    }

    test('changes its fingerprint with its slot defaults', () {
      final surface = _blob(_surface);
      final plain = componentFingerprint(surface, 'Card', const {});
      final slotted = componentFingerprint(surface, 'Card', const {
        'Card': {'a': 'Pro'},
      });
      expect(slotted.fingerprint, isNot(plain.fingerprint));
    });
  });
}
