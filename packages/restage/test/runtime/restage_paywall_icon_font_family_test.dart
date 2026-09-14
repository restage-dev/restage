import 'dart:typed_data';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:rfw/formats.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One code point, deliberately present in both installed families under a
/// different glyph, so only the family the surface names can select correctly.
const int _sharedCodePoint = 0xe156;

class _IconFamilyResolver implements VariantResolver {
  _IconFamilyResolver(this.fontFamily);

  /// The family the surface names, or null to omit the property entirely.
  final String? fontFamily;

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async {
    final family = fontFamily == null ? '' : ', iconFontFamily: "$fontFamily"';
    final source = '''
      import restage.core;
      import restage.material;
      widget Paywall = Icon(iconCodepoint: $_sharedCodePoint$family);
    ''';
    return ResolvedVariant(
      bytes: Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source))),
      surfaceVersion: 'test',
      paywallId: id,
    );
  }
}

Future<void> _pumpPaywall(WidgetTester tester, String? fontFamily) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: RestagePaywall(
        id: 'icon-family',
        resolver: _IconFamilyResolver(fontFamily),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    Restage.debugReset();
    InstalledWidgetLibraries.install(RestageWidgetLibraries.builtIn());
    InstalledIconTable.install(
      const RestageIconTable.fromFamilies(
          families: <String, Map<int, IconData>>{
            RestageIconTable.materialIconsFamily: <int, IconData>{
              _sharedCodePoint: Icons.check,
            },
            RestageIconTable.cupertinoIconsFamily: <int, IconData>{
              _sharedCodePoint: CupertinoIcons.heart,
            },
          }),
    );
  });

  tearDown(() {
    InstalledIconTable.reset();
    InstalledWidgetLibraries.reset();
  });

  testWidgets('a surface naming the Cupertino family renders its glyph',
      (tester) async {
    await _pumpPaywall(tester, RestageIconTable.cupertinoIconsFamily);

    expect(tester.takeException(), isNull);
    expect(find.byIcon(CupertinoIcons.heart), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('the same code point without a family stays Material',
      (tester) async {
    await _pumpPaywall(tester, null);

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.heart), findsNothing);
  });

  testWidgets('a family the installed table omits renders no glyph',
      (tester) async {
    InstalledIconTable.install(
      const RestageIconTable.fromFamilies(
          families: <String, Map<int, IconData>>{
            RestageIconTable.materialIconsFamily: <int, IconData>{
              _sharedCodePoint: Icons.check,
            },
          }),
    );

    await _pumpPaywall(tester, RestageIconTable.cupertinoIconsFamily);

    expect(tester.takeException(), isNull);
    expect(find.byType(Icon), findsNothing);
  });

  test('the whole built-in table carries both families', () {
    final table = builtInIconTable();

    expect(
      table.families.keys.toList()..sort(),
      <String>[
        RestageIconTable.cupertinoIconsFamily,
        RestageIconTable.materialIconsFamily,
      ],
    );
    expect(
      table.lookUp(
        RestageIconTable.cupertinoIconsFamily,
        CupertinoIcons.heart.codePoint,
      ),
      equals(CupertinoIcons.heart),
    );
    expect(
      table.lookUp(RestageIconTable.materialIconsFamily, 0xe156),
      equals(Icons.check),
    );
  });
}
