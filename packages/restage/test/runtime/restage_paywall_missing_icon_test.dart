import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:rfw/formats.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Present in the installed table, and not what the surface asks for.
const int _installedIconCodePoint = 0xe156; // Icons.check

/// A real Material code point the installed table deliberately omits.
const int _missingIconCodePoint = 0xe5f9; // Icons.star

/// The first code point of the Unicode Private Use Area, where an icon font
/// keeps its glyphs. Rendered text below this carries no glyph.
const int _privateUseAreaStart = 0xe000;

class _IconPaywallResolver implements VariantResolver {
  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async {
    const source = '''
      import restage.core;
      import restage.material;
      widget Paywall = Icon(iconCodepoint: $_missingIconCodePoint);
    ''';
    return ResolvedVariant(
      bytes: Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source))),
      surfaceVersion: 'test',
      paywallId: id,
    );
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    Restage.debugReset();
    // One unrelated icon, so a miss proves the lookup failed rather than that
    // the table was empty.
    InstalledIconTable.install(
      const RestageIconTable.fromFamilies(
          families: <String, Map<int, IconData>>{
            RestageIconTable.materialIconsFamily: <int, IconData>{
              _installedIconCodePoint: Icons.check,
            },
          }),
    );
  });

  tearDown(InstalledIconTable.reset);

  testWidgets(
    'a paywall naming an icon the installed table omits renders the fallback '
    'instead of a wrong glyph',
    (tester) async {
      final received = <RestageEvent>[];
      RestagePaywallError? captured;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RestagePaywall(
            id: 'missing-icon',
            resolver: _IconPaywallResolver(),
            onEvent: received.add,
            errorBuilder: (context, error) {
              captured = error;
              return const Text('Unavailable');
            },
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // The failure is contained: nothing escapes to the host.
      expect(tester.takeException(), isNull);

      // The caller's fallback is what the user sees.
      expect(find.text('Unavailable'), findsOneWidget);
      expect(captured?.code, RestageErrorCodes.renderError);

      // The miss reaches the caller as its own type, not just as text.
      final cause = captured?.cause;
      expect(cause, isA<RestageIconUnavailableError>());
      expect(
        (cause! as RestageIconUnavailableError).codePoint,
        _missingIconCodePoint,
      );
      expect(
        (cause as RestageIconUnavailableError).fontFamily,
        RestageIconTable.materialIconsFamily,
      );

      // The reported failure is the icon miss, rendered by its own type.
      final failures = received.whereType<PaywallLoadFailed>();
      expect(failures, hasLength(1));
      expect(failures.first.errorCode, RestageErrorCodes.renderError);
      expect(
        failures.first.message,
        RestageIconUnavailableError(
          fontFamily: RestageIconTable.materialIconsFamily,
          codePoint: _missingIconCodePoint,
        ).toString(),
      );

      // No icon at all: neither the missing one nor the installed one stands in
      // for it, and no glyph is painted in its place.
      expect(find.byType(Icon), findsNothing);
      expect(find.byIcon(Icons.check), findsNothing);
      expect(find.byIcon(Icons.star), findsNothing);
      final glyphs = tester
          .widgetList<RichText>(find.descendant(
            of: find.byType(RestagePaywall),
            matching: find.byType(RichText),
          ))
          .map((text) => text.text.toPlainText())
          .where((text) => text.runes.any((r) => r >= _privateUseAreaStart));
      expect(glyphs, isEmpty);
    },
  );
}
