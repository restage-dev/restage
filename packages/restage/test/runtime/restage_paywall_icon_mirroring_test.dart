import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:rfw/formats.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One code point Flutter gives two Material glyphs — `Icons.trending_flat`
/// mirrors in a right-to-left locale and `Icons.trending_neutral` does not —
/// so only the variant the surface names can select correctly.
const int _sharedCodePoint = 0xe67e;

class _IconMirroringResolver implements VariantResolver {
  _IconMirroringResolver(this.matchTextDirection);

  /// The variant the surface names, or null to omit the property entirely.
  final bool? matchTextDirection;

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async {
    final variant = matchTextDirection == null
        ? ''
        : ', iconMatchTextDirection: $matchTextDirection';
    final source = '''
      import restage.core;
      import restage.material;
      widget Paywall = Icon(iconCodepoint: $_sharedCodePoint$variant);
    ''';
    return ResolvedVariant(
      bytes: Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source))),
      surfaceVersion: 'test',
      paywallId: id,
    );
  }
}

Future<void> _pumpPaywall(WidgetTester tester, bool? matchTextDirection) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: RestagePaywall(
        id: 'icon-mirroring',
        resolver: _IconMirroringResolver(matchTextDirection),
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
            _sharedCodePoint: Icons.trending_neutral,
          },
        },
        mirrored: <String, Map<int, IconData>>{
          RestageIconTable.materialIconsFamily: <int, IconData>{
            _sharedCodePoint: Icons.trending_flat,
          },
        },
      ),
    );
  });

  tearDown(() {
    InstalledIconTable.reset();
    InstalledWidgetLibraries.reset();
  });

  testWidgets('a surface naming the mirroring variant renders its glyph',
      (tester) async {
    await _pumpPaywall(tester, true);

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.trending_flat), findsOneWidget);
    expect(find.byIcon(Icons.trending_neutral), findsNothing);
  });

  testWidgets('the same code point without the property stays non-mirroring',
      (tester) async {
    await _pumpPaywall(tester, null);

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.trending_neutral), findsOneWidget);
    expect(find.byIcon(Icons.trending_flat), findsNothing);
  });

  testWidgets('naming it false renders the non-mirroring glyph',
      (tester) async {
    await _pumpPaywall(tester, false);

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.trending_neutral), findsOneWidget);
    expect(find.byIcon(Icons.trending_flat), findsNothing);
  });

  testWidgets('a variant the installed table omits renders no glyph',
      (tester) async {
    InstalledIconTable.install(
      const RestageIconTable.fromFamilies(
          families: <String, Map<int, IconData>>{
            RestageIconTable.materialIconsFamily: <int, IconData>{
              _sharedCodePoint: Icons.trending_neutral,
            },
          }),
    );

    await _pumpPaywall(tester, true);

    expect(tester.takeException(), isNull);
    expect(find.byType(Icon), findsNothing);
  });

  test('the whole built-in table carries both variants of a shared point', () {
    final table = builtInIconTable();

    expect(
      table.lookUp(RestageIconTable.materialIconsFamily, _sharedCodePoint),
      equals(Icons.trending_neutral),
    );
    expect(
      table.lookUp(
        RestageIconTable.materialIconsFamily,
        _sharedCodePoint,
        matchTextDirection: true,
      ),
      equals(Icons.trending_flat),
    );
  });
}
