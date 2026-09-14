import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/src/runtime/icon_table.dart';

const String _material = RestageIconTable.materialIconsFamily;

/// One Material code point that names both a glyph that mirrors in a
/// right-to-left locale and one that does not.
const int _sharedCodePoint = 0xe67e;

const RestageIconTable _twoIcons = RestageIconTable.fromFamilies(
  families: <String, Map<int, IconData>>{
    _material: <int, IconData>{
      0xe156: Icons.check,
      0xe16a: Icons.close,
    },
  },
);

const RestageIconTable _bothVariants = RestageIconTable.fromFamilies(
  families: <String, Map<int, IconData>>{
    _material: <int, IconData>{_sharedCodePoint: Icons.trending_neutral},
  },
  mirrored: <String, Map<int, IconData>>{
    _material: <int, IconData>{_sharedCodePoint: Icons.trending_flat},
  },
);

void main() {
  setUp(InstalledIconTable.reset);
  tearDown(InstalledIconTable.reset);

  test('nothing is installed by default', () {
    expect(InstalledIconTable.current, same(RestageIconTable.none));
    expect(InstalledIconTable.current.isEmpty, isTrue);
    expect(RestageIconTable.none.families, isEmpty);
    expect(RestageIconTable.none.mirrored, isEmpty);
  });

  test('installing a table reads back the same maps', () {
    InstalledIconTable.install(_twoIcons);

    expect(InstalledIconTable.current, same(_twoIcons));
    expect(InstalledIconTable.current.isEmpty, isFalse);
    expect(
      InstalledIconTable.current.families[_material],
      <int, IconData>{0xe156: Icons.check, 0xe16a: Icons.close},
    );
  });

  test('a known family and code point resolve to the installed icon', () {
    InstalledIconTable.install(_twoIcons);

    expect(
      resolveInstalledIcon(0xe156, fontFamily: _material),
      equals(Icons.check),
    );
    expect(
      resolveInstalledIcon(0xe16a, fontFamily: _material),
      equals(Icons.close),
    );
  });

  test('an unknown code point misses rather than resolving another glyph', () {
    InstalledIconTable.install(_twoIcons);

    expect(
      () => resolveInstalledIcon(0xe047, fontFamily: _material),
      throwsA(
        isA<RestageIconUnavailableError>()
            .having((error) => error.codePoint, 'codePoint', 0xe047)
            .having((error) => error.fontFamily, 'fontFamily', _material),
      ),
    );
  });

  test('an unknown family misses', () {
    InstalledIconTable.install(_twoIcons);

    expect(
      () => resolveInstalledIcon(0xe156, fontFamily: 'CupertinoIcons'),
      throwsA(
        isA<RestageIconUnavailableError>()
            .having((error) => error.codePoint, 'codePoint', 0xe156)
            .having(
                (error) => error.fontFamily, 'fontFamily', 'CupertinoIcons'),
      ),
    );
  });

  test('an empty installation misses every code point', () {
    expect(
      () => resolveInstalledIcon(0xe156, fontFamily: _material),
      throwsA(isA<RestageIconUnavailableError>()),
    );
  });

  test('the miss names the code point, the family and the fix', () {
    InstalledIconTable.install(_twoIcons);

    expect(
      () => resolveInstalledIcon(0xe047, fontFamily: _material),
      throwsA(
        isA<RestageIconUnavailableError>().having(
          (error) => error.toString(),
          'toString',
          allOf(
            contains('0xe047'),
            contains(_material),
            contains('InstalledIconTable.install()'),
          ),
        ),
      ),
    );
  });

  test('the miss is a plain Error, not an assertion failure', () {
    InstalledIconTable.install(_twoIcons);

    // The miss throws in release as well as debug, so the type must not
    // promise a debug-only failure to whoever reads the stack trace.
    expect(
      () => resolveInstalledIcon(0xe047, fontFamily: _material),
      throwsA(allOf(isA<Error>(), isNot(isA<AssertionError>()))),
    );
  });

  test('one code point resolves to a different glyph per variant', () {
    InstalledIconTable.install(_bothVariants);

    expect(
      resolveInstalledIcon(_sharedCodePoint, fontFamily: _material),
      equals(Icons.trending_neutral),
    );
    expect(
      resolveInstalledIcon(
        _sharedCodePoint,
        fontFamily: _material,
        matchTextDirection: true,
      ),
      equals(Icons.trending_flat),
    );
  });

  test('the two maps are independent', () {
    const mirroredOnly = RestageIconTable.fromFamilies(
      families: <String, Map<int, IconData>>{},
      mirrored: <String, Map<int, IconData>>{
        _material: <int, IconData>{_sharedCodePoint: Icons.trending_flat},
      },
    );

    expect(
      mirroredOnly.lookUp(
        _material,
        _sharedCodePoint,
        matchTextDirection: true,
      ),
      equals(Icons.trending_flat),
    );
    expect(mirroredOnly.lookUp(_material, _sharedCodePoint), isNull);
    expect(
      _twoIcons.lookUp(_material, 0xe156, matchTextDirection: true),
      isNull,
    );
    expect(_twoIcons.lookUp(_material, 0xe156), equals(Icons.check));
  });

  test('a miss names the variant that was looked up', () {
    InstalledIconTable.install(_bothVariants);

    expect(
      () => resolveInstalledIcon(
        0xe047,
        fontFamily: _material,
        matchTextDirection: true,
      ),
      throwsA(
        isA<RestageIconUnavailableError>()
            .having(
              (error) => error.matchTextDirection,
              'matchTextDirection',
              isTrue,
            )
            .having(
              (error) => error.toString(),
              'toString',
              contains('matchTextDirection: true'),
            ),
      ),
    );
  });

  test('reset drops an installation so it cannot leak into the next test', () {
    InstalledIconTable.install(_twoIcons);

    InstalledIconTable.reset();

    expect(InstalledIconTable.current, same(RestageIconTable.none));
  });
}
