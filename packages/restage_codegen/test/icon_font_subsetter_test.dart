import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:restage_codegen/src/icon_font_subsetter.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  test('subsets the Material icon font to exactly the requested glyphs', () {
    final subsetter = FlutterIconFontSubsetter();
    const codePoints = {0xe87d, 0xe5cc, 0xf63a};

    final bytes = subsetter.subset(
      family: kMaterialIconsFamily,
      fontPackage: null,
      codePoints: codePoints,
    );

    expect(bytes.length, lessThan(8 * 1024));
    expect(readSfntCoveredCodePoints(bytes), codePoints);
    expect(
      subsetter.extension(family: kMaterialIconsFamily, fontPackage: null),
      '.otf',
    );
  });

  test('gives identical bytes whatever the code point order', () {
    final first = FlutterIconFontSubsetter().subset(
      family: kMaterialIconsFamily,
      fontPackage: null,
      codePoints: {0xf63a, 0xe87d},
    );
    final second = FlutterIconFontSubsetter().subset(
      family: kMaterialIconsFamily,
      fontPackage: null,
      codePoints: {0xe87d, 0xf63a},
    );

    expect(second, first);
  });

  test('reads a package font from the pubspec that declares it', () {
    final root = Directory.systemTemp.createTempSync('restage_icon_pkg_');
    addTearDown(() => root.deleteSync(recursive: true));
    final material = FlutterIconFontSubsetter().sourceFont(
      family: kMaterialIconsFamily,
      fontPackage: null,
    );
    material.copySync(p.join(root.path, 'Glyphs.otf'));
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: brand_icons
flutter:
  fonts:
    - family: Glyphs
      fonts:
        - asset: Glyphs.otf
''');
    final subsetter = FlutterIconFontSubsetter(
      packageRoot: (package) => package == 'brand_icons' ? root.path : null,
    );

    final bytes = subsetter.subset(
      family: 'Glyphs',
      fontPackage: 'brand_icons',
      codePoints: {0xe87d},
    );

    expect(readSfntCoveredCodePoints(bytes), {0xe87d});
  });

  test('names a missing Flutter SDK', () {
    final subsetter = FlutterIconFontSubsetter(
      flutterRoot: p.join(Directory.systemTemp.path, 'no_flutter_here'),
    );

    expect(
      () => subsetter.subset(
        family: kMaterialIconsFamily,
        fontPackage: null,
        codePoints: {0xe87d},
      ),
      throwsA(
        isA<IconFontSubsetException>().having(
          (error) => error.message,
          'message',
          contains('Material icon font is missing'),
        ),
      ),
    );
  });

  test('names a font family no pubspec declares', () {
    final root = Directory.systemTemp.createTempSync('restage_icon_app_');
    addTearDown(() => root.deleteSync(recursive: true));
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: app\n');
    final subsetter = FlutterIconFontSubsetter(appRoot: root.path);

    expect(
      () => subsetter.subset(
        family: 'AppGlyphs',
        fontPackage: null,
        codePoints: {1},
      ),
      throwsA(
        isA<IconFontSubsetException>().having(
          (error) => error.message,
          'message',
          contains('AppGlyphs icon font is not declared'),
        ),
      ),
    );
  });
}
