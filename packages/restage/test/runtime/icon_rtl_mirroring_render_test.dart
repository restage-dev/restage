import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:rfw/formats.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ChevronResolver implements VariantResolver {
  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async {
    final source = '''
      import restage.core;
      import restage.material;
      widget Paywall = Icon(
        iconCodepoint: ${Icons.chevron_left_rounded.codePoint},
        iconMatchTextDirection: true,
      );
    ''';
    return ResolvedVariant(
      bytes: Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source))),
      surfaceVersion: 'test',
      paywallId: id,
    );
  }
}

Future<void> _pump(WidgetTester tester, TextDirection direction) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: direction,
        child: Scaffold(
          body: RestagePaywall(
            id: 'chevron',
            resolver: _ChevronResolver(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The x scale of the transform `Icon` paints its glyph through, or null.
double? _glyphScaleX(WidgetTester tester) {
  final transforms = find.descendant(
    of: find.byType(Icon),
    matching: find.byType(Transform),
  );
  if (transforms.evaluate().isEmpty) return null;
  return tester.widget<Transform>(transforms.first).transform.storage[0];
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    Restage.debugReset();
    InstalledWidgetLibraries.install(RestageWidgetLibraries.builtIn());
    InstalledIconTable.install(builtInIconTable());
  });

  tearDown(() {
    InstalledIconTable.reset();
    InstalledWidgetLibraries.reset();
  });

  testWidgets('a mirroring chevron flips under a right-to-left direction',
      (tester) async {
    await _pump(tester, TextDirection.rtl);

    expect(tester.takeException(), isNull);
    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.icon, Icons.chevron_left_rounded);
    expect(icon.icon!.matchTextDirection, isTrue);
    expect(_glyphScaleX(tester), -1.0);
  });

  testWidgets('the same chevron is not flipped left-to-right', (tester) async {
    await _pump(tester, TextDirection.ltr);

    expect(tester.takeException(), isNull);
    expect(
      tester.widget<Icon>(find.byType(Icon)).icon,
      Icons.chevron_left_rounded,
    );
    expect(_glyphScaleX(tester), isNull);
  });
}
