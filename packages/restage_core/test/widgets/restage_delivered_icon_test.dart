import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/src/runtime/icon_table.dart';
import 'package:restage_core/src/widgets/delivered_icon_fonts.dart';
import 'package:restage_core/src/widgets/restage_delivered_icon.dart';
import 'package:restage_shared/restage_shared.dart'
    show readSfntCoveredCodePoints;

const String _material = RestageIconTable.materialIconsFamily;
const String _loadedFamily = 'restage-icons-testsubset01';

late Set<int> _covered;
late int _codePoint;

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final bytes = File(
      '../restage_shared/test/fonts/fixtures/material_icons_subset.otf',
    ).readAsBytesSync();
    _covered = readSfntCoveredCodePoints(bytes);
    _codePoint = (_covered.toList()..sort()).first;
    final loader = FontLoader(_loadedFamily)
      ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    await loader.load();
  });

  setUp(InstalledIconTable.reset);
  tearDown(InstalledIconTable.reset);

  Widget host({
    required WidgetBuilder builder,
    TextDirection direction = TextDirection.ltr,
    Map<String, LoadedIconFont>? fonts,
  }) {
    Widget child = Builder(builder: builder);
    if (fonts != null) child = DeliveredIconFonts(fonts: fonts, child: child);
    return Directionality(
      textDirection: direction,
      child: IconTheme(
        data: const IconThemeData(size: 30, color: Color(0xFF112233)),
        child: Center(child: child),
      ),
    );
  }

  Map<String, LoadedIconFont> deliveredMaterial() => <String, LoadedIconFont>{
        _material: LoadedIconFont(
          loadedFamily: _loadedFamily,
          codePoints: _covered,
        ),
      };

  testWidgets('the installed table wins over a delivered font', (tester) async {
    InstalledIconTable.install(
      RestageIconTable.fromFamilies(
        families: <String, Map<int, IconData>>{
          _material: <int, IconData>{_codePoint: Icons.check},
        },
      ),
    );

    await tester.pumpWidget(
      host(
        fonts: deliveredMaterial(),
        builder: (context) => restageIcon(context, codePoint: _codePoint),
      ),
    );

    expect(tester.widget<Icon>(find.byType(Icon)).icon, Icons.check);
    expect(find.byType(RestageDeliveredIcon), findsNothing);
  });

  testWidgets('a delivered font draws a covered code point', (tester) async {
    await tester.pumpWidget(
      host(
        fonts: deliveredMaterial(),
        builder: (context) => restageIcon(
          context,
          codePoint: _codePoint,
          fontFamily: _material,
          semanticLabel: 'Done',
        ),
      ),
    );

    expect(find.byType(RestageDeliveredIcon), findsOneWidget);
    final text =
        tester.widget<RichText>(find.byType(RichText)).text as TextSpan;
    expect(text.text, String.fromCharCode(_codePoint));
    expect(text.style!.fontFamily, _loadedFamily);
    expect(text.style!.fontSize, 30);
    expect(text.style!.color, const Color(0xFF112233));
    expect(
        tester.getSize(find.byType(RestageDeliveredIcon)), const Size(30, 30));
    expect(find.bySemanticsLabel('Done'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the delivered path holds no icon value anywhere in the tree',
      (tester) async {
    await tester.pumpWidget(
      host(
        fonts: deliveredMaterial(),
        builder: (context) => restageIcon(context, codePoint: _codePoint),
      ),
    );

    expect(find.byType(Icon), findsNothing);
    for (final widget in tester.allWidgets) {
      final values = widget
          .toDiagnosticsNode()
          .getProperties()
          .map((property) => property.value);
      expect(values.whereType<IconData>(), isEmpty, reason: '$widget');
    }
  });

  testWidgets('a mirroring glyph flips in a right-to-left context',
      (tester) async {
    await tester.pumpWidget(
      host(
        direction: TextDirection.rtl,
        fonts: deliveredMaterial(),
        builder: (context) => restageIcon(
          context,
          codePoint: _codePoint,
          matchTextDirection: true,
        ),
      ),
    );

    final flip = tester.widget<Transform>(
      find.descendant(
        of: find.byType(RestageDeliveredIcon),
        matching: find.byType(Transform),
      ),
    );
    expect(flip.transform.entry(0, 0), -1);

    await tester.pumpWidget(
      host(
        fonts: deliveredMaterial(),
        builder: (context) => restageIcon(
          context,
          codePoint: _codePoint,
          matchTextDirection: true,
        ),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(RestageDeliveredIcon),
        matching: find.byType(Transform),
      ),
      findsNothing,
    );
  });

  testWidgets('a code point neither source carries misses', (tester) async {
    final uncovered = List<int>.generate(0x100, (i) => 0xf000 + i).firstWhere(
      (codePoint) => !_covered.contains(codePoint),
    );
    late BuildContext scoped;
    late BuildContext unscoped;
    await tester.pumpWidget(
      Column(
        children: <Widget>[
          host(
            fonts: deliveredMaterial(),
            builder: (context) {
              scoped = context;
              return const SizedBox();
            },
          ),
          host(
            builder: (context) {
              unscoped = context;
              return const SizedBox();
            },
          ),
        ],
      ),
    );

    expect(
      () => restageIcon(scoped, codePoint: uncovered),
      throwsA(
        isA<RestageIconUnavailableError>()
            .having((error) => error.codePoint, 'codePoint', uncovered)
            .having((error) => error.fontFamily, 'fontFamily', _material),
      ),
    );
    expect(
      () => restageIcon(unscoped, codePoint: _codePoint),
      throwsA(isA<RestageIconUnavailableError>()),
    );
    expect(
      () => restageIcon(
        scoped,
        codePoint: _codePoint,
        fontFamily: RestageIconTable.cupertinoIconsFamily,
      ),
      throwsA(isA<RestageIconUnavailableError>()),
    );
  });
}
