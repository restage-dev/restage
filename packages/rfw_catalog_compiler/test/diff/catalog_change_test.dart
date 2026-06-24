import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

void main() {
  group('CatalogChange equality', () {
    final ref = WireIdRef(library: 'restage.core', wireId: WireId('w0001'));

    test('two EntryRemoved with the same kind + affected are equal', () {
      expect(
        EntryRemoved(kind: WireIdKind.widget, affected: ref),
        equals(EntryRemoved(kind: WireIdKind.widget, affected: ref)),
      );
    });

    test('EntryRemoved and EntryAdded with the same kind + affected differ',
        () {
      expect(
        EntryRemoved(kind: WireIdKind.widget, affected: ref),
        isNot(equals(EntryAdded(kind: WireIdKind.widget, affected: ref))),
      );
    });

    test('two EntryReplaced differing only in successor are not equal', () {
      final successorA =
          WireIdRef(library: 'restage.core', wireId: WireId('w0002'));
      final successorB =
          WireIdRef(library: 'restage.core', wireId: WireId('w0003'));
      expect(
        EntryReplaced(
          kind: WireIdKind.widget,
          affected: ref,
          successor: successorA,
        ),
        isNot(
          equals(
            EntryReplaced(
              kind: WireIdKind.widget,
              affected: ref,
              successor: successorB,
            ),
          ),
        ),
      );
    });
  });
}
