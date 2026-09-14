import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart'
    show
        InstalledIconTable,
        RestageIconTable,
        RestageIconUnavailableError,
        resolveInstalledIcon;
import 'package:restage_material/icon_table.dart'
    show kMaterialIconTable, kMirroredMaterialIconTable;

const String _material = RestageIconTable.materialIconsFamily;

// A `const` context. This declaration stops compiling if the generated tables
// ever stop being `const`, which is what keeps the icon font shakeable.
const RestageIconTable _constPinnedTable = RestageIconTable.fromFamilies(
  families: <String, Map<int, IconData>>{_material: kMaterialIconTable},
  mirrored: <String, Map<int, IconData>>{_material: kMirroredMaterialIconTable},
);

void main() {
  setUp(InstalledIconTable.reset);
  tearDown(InstalledIconTable.reset);

  test('the generated tables are const maps', () {
    expect(
      identical(_constPinnedTable.families[_material], kMaterialIconTable),
      isTrue,
    );
    expect(
      identical(
        _constPinnedTable.mirrored[_material],
        kMirroredMaterialIconTable,
      ),
      isTrue,
    );
  });

  test('the generated table carries the whole Material icon set', () {
    expect(kMaterialIconTable, hasLength(greaterThan(8000)));
    expect(kMaterialIconTable[0xe156], equals(Icons.check));
    expect(kMaterialIconTable[0xe4a1], equals(Icons.pets));
  });

  test('every entry is keyed by its own code point in the Material font', () {
    for (final entry in kMaterialIconTable.entries) {
      expect(entry.value.codePoint, entry.key);
      expect(entry.value.fontFamily, _material);
      expect(entry.value.fontPackage, isNull);
    }
  });

  test('entries are ordered by ascending code point', () {
    final keys = kMaterialIconTable.keys.toList();

    expect(keys, orderedEquals(List<int>.of(keys)..sort()));
  });

  test('a code point several names share takes the first name', () {
    // 0xe4a1 is `pets` alone, so the tie-break only ever runs among names
    // that agree on every field.
    expect(kMaterialIconTable[0xe4a1], equals(Icons.pets));
  });

  test('both glyphs of a mirroring code point survive', () {
    // 0xe67e is both `trending_flat` and `trending_neutral`, and the two
    // differ: only the first mirrors under a right-to-left text direction.
    expect(kMaterialIconTable[0xe67e], equals(Icons.trending_neutral));
    expect(kMaterialIconTable[0xe67e]!.matchTextDirection, isFalse);
    expect(kMirroredMaterialIconTable[0xe67e], equals(Icons.trending_flat));
    expect(kMirroredMaterialIconTable[0xe67e]!.matchTextDirection, isTrue);
  });

  test('every mirroring entry is keyed by its own code point', () {
    for (final entry in kMirroredMaterialIconTable.entries) {
      expect(entry.value.codePoint, entry.key);
      expect(entry.value.fontFamily, _material);
      expect(entry.value.matchTextDirection, isTrue);
    }
  });

  test('installing the whole table resolves any Material code point', () {
    InstalledIconTable.install(_constPinnedTable);

    expect(
      resolveInstalledIcon(0xe4a1, fontFamily: _material),
      equals(Icons.pets),
    );
    expect(
      resolveInstalledIcon(0xf055d, fontFamily: _material),
      equals(Icons.rocket_launch),
    );
  });

  test('a Material-only table resolves nothing in another family', () {
    InstalledIconTable.install(_constPinnedTable);

    expect(InstalledIconTable.current.families.keys, <String>[_material]);
    expect(
      () => resolveInstalledIcon(
        0xe4a1,
        fontFamily: RestageIconTable.cupertinoIconsFamily,
      ),
      throwsA(isA<RestageIconUnavailableError>()),
    );
  });
}
