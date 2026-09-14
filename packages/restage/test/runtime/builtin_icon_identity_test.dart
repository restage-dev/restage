import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_cupertino/icon_table.dart';
import 'package:restage_material/icon_table.dart';

// Deliberately asymmetric equality: the public const int-key map rejects it.
class _IntegerEqual {
  const _IntegerEqual(this.value);
  final int value;
  @override
  int get hashCode => value.hashCode;
  @override
  bool operator ==(Object other) => other == value;
}

void main() {
  tearDown(InstalledIconTable.reset);

  test(
      'all 9864 original constants retain identity inside the expanded sorted maps',
      () {
    final table = builtInIconTable();
    InstalledIconTable.install(table);
    var count = 0;
    for (final pair in [
      (RestageIconTable.materialIconsFamily, false, kMaterialIconTable),
      (RestageIconTable.materialIconsFamily, true, kMirroredMaterialIconTable),
      (RestageIconTable.cupertinoIconsFamily, false, kCupertinoIconTable),
      (
        RestageIconTable.cupertinoIconsFamily,
        true,
        kMirroredCupertinoIconTable
      ),
    ]) {
      final (family, mirrored, oracle) = pair;
      final actual = (mirrored ? table.mirrored : table.families)[family]!;
      final compatibilityPoints =
          family == RestageIconTable.materialIconsFamily && !mirrored
              ? kMirroredMaterialIconTable.keys
                  .where((key) => !oracle.containsKey(key))
              : const <int>[];
      final expectedKeys = {...oracle.keys, ...compatibilityPoints}.toList()
        ..sort();
      expect(actual.keys, orderedEquals(expectedKeys));
      expect(actual.length, expectedKeys.length);
      expect(actual.isEmpty, oracle.isEmpty);
      expect(
          actual.entries
              .where((entry) => oracle.containsKey(entry.key))
              .map((entry) => entry.value),
          orderedEquals(oracle.values));
      for (final entry in oracle.entries) {
        count++;
        expect(actual[entry.key], same(entry.value));
        expect(actual[entry.key.toDouble()], same(entry.value));
        expect(
            resolveInstalledIcon(entry.key,
                fontFamily: family, matchTextDirection: mirrored),
            same(entry.value));
      }
      for (final miss in <Object?>[
        null,
        '0xe000',
        -1,
        0x110000,
        1.5,
        double.nan,
        double.infinity,
        double.negativeInfinity,
        _IntegerEqual(oracle.keys.first)
      ]) {
        expect(actual[miss], oracle[miss]);
        expect(actual.containsKey(miss), oracle.containsKey(miss));
      }
      expect(() => actual[0] = Icons.check, throwsUnsupportedError);
      expect(() => actual.remove(oracle.keys.first), throwsUnsupportedError);
      expect(actual.clear, throwsUnsupportedError);
      expect(() => actual.addAll({0: Icons.check}), throwsUnsupportedError);
      expect(() => actual.update(oracle.keys.first, (_) => Icons.check),
          throwsUnsupportedError);
      expect(() => actual.putIfAbsent(0, () => Icons.check),
          throwsUnsupportedError);
    }
    expect(count, 9864);
    expect(table.lookUp('custom', 0), isNull);
  });

  test('all 299 mirrored-only Material points retain the old false wire form',
      () {
    final table = builtInIconTable();
    final points = kMirroredMaterialIconTable.keys
        .where((key) => !kMaterialIconTable.containsKey(key))
        .toList();
    expect(points, hasLength(299));
    for (final point in points) {
      final actual = table.lookUp(RestageIconTable.materialIconsFamily, point);
      expect(actual!.codePoint, point);
      expect(actual.fontFamily, 'MaterialIcons');
      expect(actual.fontPackage, isNull);
      expect(actual.fontFamilyFallback, isNull);
      expect(actual.matchTextDirection, isFalse);
      expect(
          table.lookUp(RestageIconTable.materialIconsFamily, point,
              matchTextDirection: true),
          same(kMirroredMaterialIconTable[point]));
    }
    expect(table.lookUp(RestageIconTable.materialIconsFamily, 0xe092),
        same(const IconData(0xe092, fontFamily: 'MaterialIcons')));
  });

  test('compatibility is local to builtin tables and custom entries still win',
      () {
    const custom = RestageIconTable.fromFamilies(
      families: {
        'MaterialIcons': {0xe092: Icons.check}
      },
      mirrored: {
        'MaterialIcons': {0xe092: Icons.arrow_back}
      },
    );
    InstalledIconTable.install(custom);
    InstalledIconTable.add(builtInIconTable());
    expect(resolveInstalledIcon(0xe092, fontFamily: 'MaterialIcons'),
        same(Icons.check));
    InstalledIconTable.install(const RestageIconTable.fromFamilies(
      mirrored: {
        'MaterialIcons': {0xe092: Icons.arrow_back}
      },
    ));
    expect(() => resolveInstalledIcon(0xe092, fontFamily: 'MaterialIcons'),
        throwsA(isA<RestageIconUnavailableError>()));
    expect(
        resolveInstalledIcon(0xe092,
            fontFamily: 'MaterialIcons', matchTextDirection: true),
        same(Icons.arrow_back));
  });

  test('outer maps, empty addition and custom union keep existing behavior',
      () {
    final full = builtInIconTable();
    const custom = RestageIconTable.fromFamilies(families: {
      RestageIconTable.materialIconsFamily: {0xe156: Icons.close},
      'custom': {7: Icons.check},
    });
    InstalledIconTable.install(custom);
    InstalledIconTable.add(RestageIconTable.none);
    expect(InstalledIconTable.current, same(custom));
    InstalledIconTable.add(full);
    final merged = InstalledIconTable.current;
    expect(merged.lookUp(RestageIconTable.materialIconsFamily, 0xe156),
        same(Icons.close));
    expect(merged.lookUp('custom', 7), same(Icons.check));
    expect(
        merged.lookUp(RestageIconTable.cupertinoIconsFamily,
            kCupertinoIconTable.keys.first),
        same(kCupertinoIconTable.values.first));
    full.families['custom'] = const {8: Icons.star};
    expect(full.lookUp('custom', 8), same(Icons.star));
    expect(merged.lookUp('custom', 8), isNull);
  });
}
