import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/src/runtime/icon_table.dart';

const String _material = RestageIconTable.materialIconsFamily;
const String _cupertino = RestageIconTable.cupertinoIconsFamily;

const int _check = 0xe156;
const int _close = 0xe16a;
const int _star = 0xe838;

const RestageIconTable _checkOnly = RestageIconTable.fromFamilies(
  families: <String, Map<int, IconData>>{
    _material: <int, IconData>{_check: Icons.check},
  },
);

const RestageIconTable _closeOnly = RestageIconTable.fromFamilies(
  families: <String, Map<int, IconData>>{
    _material: <int, IconData>{_close: Icons.close},
  },
);

/// Names the same code point as [_checkOnly] under a different glyph.
const RestageIconTable _conflictingCheck = RestageIconTable.fromFamilies(
  families: <String, Map<int, IconData>>{
    _material: <int, IconData>{_check: Icons.star},
  },
);

const RestageIconTable _cupertinoOnly = RestageIconTable.fromFamilies(
  families: <String, Map<int, IconData>>{
    _cupertino: <int, IconData>{_star: CupertinoIcons.star},
  },
);

/// One Material code point that names both a glyph that mirrors in a
/// right-to-left locale and one that does not.
const int _trending = 0xe67e;

const RestageIconTable _trendingUpright = RestageIconTable.fromFamilies(
  families: <String, Map<int, IconData>>{
    _material: <int, IconData>{_trending: Icons.trending_neutral},
  },
);

const RestageIconTable _trendingMirrored = RestageIconTable.fromFamilies(
  families: <String, Map<int, IconData>>{},
  mirrored: <String, Map<int, IconData>>{
    _material: <int, IconData>{_trending: Icons.trending_flat},
  },
);

/// Names the same mirroring code point as [_trendingMirrored] under a
/// different glyph.
const RestageIconTable _conflictingMirrored = RestageIconTable.fromFamilies(
  families: <String, Map<int, IconData>>{},
  mirrored: <String, Map<int, IconData>>{
    _material: <int, IconData>{_trending: Icons.star},
  },
);

void main() {
  setUp(InstalledIconTable.reset);
  tearDown(InstalledIconTable.reset);

  test('direct additions select only when nonempty by default', () {
    InstalledIconTable.add(RestageIconTable.none);
    expect(InstalledIconTable.hasSelection, isFalse);
    InstalledIconTable.add(_checkOnly);
    expect(InstalledIconTable.hasSelection, isTrue);
  });

  test('implicit additions do not select the catalog', () {
    InstalledIconTable.add(_checkOnly, explicitSelection: false);
    expect(InstalledIconTable.current.isEmpty, isFalse);
    expect(InstalledIconTable.hasSelection, isFalse);
  });

  test('an explicit empty selection survives implicit additions', () {
    InstalledIconTable.add(RestageIconTable.none, explicitSelection: true);
    expect(InstalledIconTable.current, same(RestageIconTable.none));
    expect(InstalledIconTable.hasSelection, isTrue);
    InstalledIconTable.add(_checkOnly, explicitSelection: false);
    expect(InstalledIconTable.hasSelection, isTrue);
    InstalledIconTable.reset();
    expect(InstalledIconTable.hasSelection, isFalse);
  });

  test('adding to nothing installs the added table', () {
    InstalledIconTable.add(_checkOnly);

    expect(InstalledIconTable.current.lookUp(_material, _check), Icons.check);
  });

  test('adding unions within a family', () {
    InstalledIconTable.add(_checkOnly);
    InstalledIconTable.add(_closeOnly);

    expect(InstalledIconTable.current.lookUp(_material, _check), Icons.check);
    expect(InstalledIconTable.current.lookUp(_material, _close), Icons.close);
  });

  test('adding unions across families', () {
    InstalledIconTable.add(_checkOnly);
    InstalledIconTable.add(_cupertinoOnly);

    expect(InstalledIconTable.current.lookUp(_material, _check), Icons.check);
    expect(
      InstalledIconTable.current.lookUp(_cupertino, _star),
      CupertinoIcons.star,
    );
  });

  test('the installed code point wins over a later conflicting one', () {
    InstalledIconTable.add(_checkOnly);
    InstalledIconTable.add(_conflictingCheck);

    expect(InstalledIconTable.current.lookUp(_material, _check), Icons.check);
  });

  test('adding composes over a prior whole-table install', () {
    InstalledIconTable.install(_checkOnly);
    InstalledIconTable.add(_closeOnly);
    InstalledIconTable.add(_conflictingCheck);

    expect(InstalledIconTable.current.lookUp(_material, _check), Icons.check);
    expect(InstalledIconTable.current.lookUp(_material, _close), Icons.close);
  });

  test('adding unions both variants of one code point', () {
    InstalledIconTable.add(_trendingUpright);
    InstalledIconTable.add(_trendingMirrored);

    expect(
      InstalledIconTable.current.lookUp(_material, _trending),
      Icons.trending_neutral,
    );
    expect(
      InstalledIconTable.current
          .lookUp(_material, _trending, matchTextDirection: true),
      Icons.trending_flat,
    );
  });

  test('the installed mirroring code point wins over a later one', () {
    InstalledIconTable.add(_trendingMirrored);
    InstalledIconTable.add(_conflictingMirrored);

    expect(
      InstalledIconTable.current
          .lookUp(_material, _trending, matchTextDirection: true),
      Icons.trending_flat,
    );
  });

  test('adding an upright entry leaves the mirroring map alone', () {
    InstalledIconTable.add(_trendingMirrored);
    InstalledIconTable.add(_trendingUpright);

    expect(
      InstalledIconTable.current
          .lookUp(_material, _trending, matchTextDirection: true),
      Icons.trending_flat,
    );
    expect(
      InstalledIconTable.current.lookUp(_material, _trending),
      Icons.trending_neutral,
    );
  });

  test('adding an empty table leaves the installation untouched', () {
    InstalledIconTable.install(_checkOnly);
    InstalledIconTable.add(RestageIconTable.none);

    expect(InstalledIconTable.current, same(_checkOnly));
  });

  test('reset clears what add contributed', () {
    InstalledIconTable.add(_checkOnly);
    InstalledIconTable.add(_cupertinoOnly);
    InstalledIconTable.reset();

    expect(InstalledIconTable.current, same(RestageIconTable.none));
    expect(InstalledIconTable.current.lookUp(_material, _check), isNull);
    expect(InstalledIconTable.current.lookUp(_cupertino, _star), isNull);
  });
}
