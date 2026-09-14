import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

const int _check = 0xe156;

/// The shape generated surface code emits: a `const` value naming the exact
/// widgets and icons one surface draws.
const SurfaceVocabulary _oneScreen = SurfaceVocabulary(
  widgets: RestageWidgetLibraries.fromVocabulary(
    core: <String, LocalWidgetBuilder>{
      'Column': buildColumn,
      'Text': buildText,
    },
    material: <String, LocalWidgetBuilder>{'Icon': buildIcon},
  ),
  icons: RestageIconTable.fromFamilies(families: <String, Map<int, IconData>>{
    RestageIconTable.materialIconsFamily: <int, IconData>{_check: Icons.check},
  }),
);

const SurfaceVocabulary _iconsOnly = SurfaceVocabulary(
  icons: RestageIconTable.fromFamilies(families: <String, Map<int, IconData>>{
    RestageIconTable.materialIconsFamily: <int, IconData>{
      0xe16a: Icons.close,
    },
  }),
);

void main() {
  setUp(() {
    InstalledWidgetLibraries.reset();
    InstalledIconTable.reset();
  });

  tearDown(() {
    InstalledIconTable.reset();
    InstalledWidgetLibraries.install(RestageWidgetLibraries.builtIn());
  });

  test('the empty vocabulary names nothing and installs nothing', () {
    expect(SurfaceVocabulary.none.isEmpty, isTrue);

    SurfaceVocabulary.none.addToInstalled();

    expect(InstalledWidgetLibraries.current, same(RestageWidgetLibraries.none));
    expect(InstalledIconTable.current, same(RestageIconTable.none));
  });

  test('a vocabulary installs its widgets and its icons', () {
    _oneScreen.addToInstalled();

    expect(InstalledWidgetLibraries.current.core.keys, {'Column', 'Text'});
    expect(InstalledWidgetLibraries.current.material.keys, {'Icon'});
    expect(
      InstalledIconTable.current.lookUp(
        RestageIconTable.materialIconsFamily,
        _check,
      ),
      Icons.check,
    );
  });

  test('installing the same vocabulary twice changes nothing', () {
    _oneScreen.addToInstalled();
    final libraries = InstalledWidgetLibraries.current;
    final icons = InstalledIconTable.current;

    _oneScreen.addToInstalled();

    expect(InstalledWidgetLibraries.current.core.keys, libraries.core.keys);
    expect(
      InstalledIconTable.current.lookUp(
        RestageIconTable.materialIconsFamily,
        _check,
      ),
      icons.lookUp(RestageIconTable.materialIconsFamily, _check),
    );
  });

  test('several surfaces union into one installation', () {
    _oneScreen.addToInstalled();
    _iconsOnly.addToInstalled();

    expect(InstalledWidgetLibraries.current.core.keys, {'Column', 'Text'});
    expect(
      InstalledIconTable.current.lookUp(
        RestageIconTable.materialIconsFamily,
        0xe16a,
      ),
      Icons.close,
    );
    expect(
      InstalledIconTable.current.lookUp(
        RestageIconTable.materialIconsFamily,
        _check,
      ),
      Icons.check,
    );
  });

  test('a widgets-only vocabulary is not empty', () {
    const vocabulary = SurfaceVocabulary(
      widgets: RestageWidgetLibraries.fromVocabulary(
        core: <String, LocalWidgetBuilder>{'Text': buildText},
      ),
    );

    expect(vocabulary.isEmpty, isFalse);
    expect(vocabulary.icons, same(RestageIconTable.none));
  });
}
