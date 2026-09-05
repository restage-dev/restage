import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_shared/restage_shared.dart'
    show kDeviceContractPaths, kThemeContractPaths;
import 'package:rfw/rfw.dart';

/// Reads a top-level key from [DynamicContent] using its public `subscribe`
/// API. `DynamicContent` doesn't expose a `toJson` in rfw 1.1.3, so we
/// subscribe (which returns the current value) and immediately unsubscribe.
Object _readKey(DynamicContent dc, String key) {
  void noop(Object _) {}
  final value = dc.subscribe(<Object>[key], noop);
  dc.unsubscribe(<Object>[key], noop);
  return value;
}

void main() {
  group('populateDeviceData', () {
    test('includes locale, platform, screen dimensions, safe-area insets', () {
      final dc = DynamicContent();
      populateDeviceData(
        dc,
        locale: const Locale('en', 'US'),
        mediaQuery: const MediaQueryData(
          size: Size(390, 844),
          devicePixelRatio: 3.0,
          padding: EdgeInsets.only(top: 47, bottom: 34),
          viewPadding: EdgeInsets.only(top: 47, bottom: 34),
        ),
        platform: 'ios',
      );

      final device = _readKey(dc, 'device') as Map;
      expect(device['locale'], 'en_US');
      expect(device['languageCode'], 'en');
      expect(device['countryCode'], 'US');
      expect(device['platform'], 'ios');
      expect(device['screenWidth'], 390.0);
      expect(device['screenHeight'], 844.0);
      expect(device['shortestSide'], 390.0);
      expect(device['longestSide'], 844.0);
      expect(device['orientation'], 'portrait');
      expect(device['pixelRatio'], 3.0);
      expect(device['safeAreaTop'], 47.0);
      expect(device['safeAreaBottom'], 34.0);
      expect(device['safeAreaLeft'], 0.0);
      expect(device['safeAreaRight'], 0.0);
      expect(device['viewPaddingTop'], 47.0);
      expect(device['viewPaddingBottom'], 34.0);
      expect(device['viewPaddingLeft'], 0.0);
      expect(device['viewPaddingRight'], 0.0);
    });

    test('view padding is published apart from the padding it survives', () {
      final dc = DynamicContent();
      populateDeviceData(
        dc,
        locale: const Locale('en'),
        // A keyboard consumes the bottom padding and leaves the view padding.
        mediaQuery: const MediaQueryData(
          padding: EdgeInsets.only(top: 47),
          viewPadding: EdgeInsets.only(top: 47, bottom: 34),
          viewInsets: EdgeInsets.only(bottom: 300),
        ),
      );

      final device = _readKey(dc, 'device') as Map;
      expect(device['safeAreaBottom'], 0.0);
      expect(device['viewPaddingBottom'], 34.0);
    });

    test('defaults platform to "unknown" when not specified', () {
      final dc = DynamicContent();
      populateDeviceData(
        dc,
        locale: const Locale('fr'),
        mediaQuery: const MediaQueryData(),
      );

      final device = _readKey(dc, 'device') as Map;
      expect(device['platform'], 'unknown');
      expect(device['locale'], 'fr');
      expect(device['languageCode'], 'fr');
      expect(device.containsKey('countryCode'), isFalse);
    });

    test('reports landscape when the width exceeds the height', () {
      final dc = DynamicContent();
      populateDeviceData(
        dc,
        locale: const Locale('en'),
        mediaQuery: const MediaQueryData(size: Size(1024, 768)),
      );

      final device = _readKey(dc, 'device') as Map;
      expect(device['orientation'], 'landscape');
      expect(device['shortestSide'], 768.0);
      expect(device['longestSide'], 1024.0);
    });

    test(
        'a country-bearing locale publishes exactly the kDeviceContractPaths '
        'set — drift gate against the codegen-side contract validation', () {
      final dc = DynamicContent();
      populateDeviceData(
        dc,
        locale: const Locale('en', 'US'),
        mediaQuery: const MediaQueryData(),
        platform: 'iOS',
      );

      final device = _readKey(dc, 'device') as Map;
      expect(device.keys.cast<String>().toSet(), kDeviceContractPaths);
    });
  });

  group('populateThemeData', () {
    test('writes all 46 ColorScheme roles as ARGB ints', () {
      final dc = DynamicContent();
      final cs = const ColorScheme.light().copyWith(
        primary: const Color(0xFF010203),
        onSurfaceVariant: const Color(0xFF0A0B0C),
        surfaceContainerHighest: const Color(0xFF111213),
        inversePrimary: const Color(0xFF212223),
        scrim: const Color(0xFF313233),
      );
      populateThemeData(
        dc,
        colorScheme: cs,
        iconTheme: const IconThemeData(),
        defaultTextStyle: const TextStyle(),
        textTheme: const TextTheme(),
      );

      final theme = _readKey(dc, 'theme') as Map;
      final colorScheme = theme['colorScheme'] as Map;
      // Pins the shipped data.theme.colorScheme.* key set against the
      // shared contract constant — the same source the codegen-side
      // translator validates against. Drift between the two fails here.
      final expectedRoles = kThemeContractPaths
          .where((p) => p.startsWith('colorScheme.'))
          .map((p) => p.substring('colorScheme.'.length))
          .toSet();
      expect(colorScheme.keys.toSet(), expectedRoles);
      expect(colorScheme.length, 46);
      expect(colorScheme.values.every((v) => v is int), isTrue);
      // Spot-check the mapping is not cross-wired (incl. derived getters).
      expect(colorScheme['primary'], 0xFF010203);
      expect(colorScheme['onSurfaceVariant'], 0xFF0A0B0C);
      expect(colorScheme['surfaceContainerHighest'], 0xFF111213);
      expect(colorScheme['inversePrimary'], 0xFF212223);
      expect(colorScheme['scrim'], 0xFF313233);
    });

    test('writes iconTheme color (ARGB int) and size when set', () {
      final dc = DynamicContent();
      populateThemeData(
        dc,
        colorScheme: const ColorScheme.light(),
        iconTheme: const IconThemeData(color: Color(0xFF445566), size: 28),
        defaultTextStyle: const TextStyle(),
        textTheme: const TextTheme(),
      );
      final iconTheme = (_readKey(dc, 'theme') as Map)['iconTheme'] as Map;
      expect(iconTheme['color'], 0xFF445566);
      expect(iconTheme['size'], 28.0);
    });

    test('omits iconTheme keys that are null', () {
      final dc = DynamicContent();
      populateThemeData(
        dc,
        colorScheme: const ColorScheme.light(),
        iconTheme: const IconThemeData(),
        defaultTextStyle: const TextStyle(),
        textTheme: const TextTheme(),
      );
      final iconTheme = (_readKey(dc, 'theme') as Map)['iconTheme'] as Map;
      expect(iconTheme.containsKey('color'), isFalse);
      expect(iconTheme.containsKey('size'), isFalse);
    });

    test('writes defaultTextStyle color, family, size, weight, style', () {
      final dc = DynamicContent();
      populateThemeData(
        dc,
        colorScheme: const ColorScheme.light(),
        iconTheme: const IconThemeData(),
        defaultTextStyle: const TextStyle(
          color: Color(0xFF778899),
          fontFamily: 'Charter',
          fontSize: 17,
          fontWeight: FontWeight.w600,
          fontStyle: FontStyle.italic,
        ),
        textTheme: const TextTheme(),
      );
      final style = (_readKey(dc, 'theme') as Map)['defaultTextStyle'] as Map;
      expect(style['color'], 0xFF778899);
      expect(style['fontFamily'], 'Charter');
      expect(style['fontSize'], 17.0);
      expect(style['fontWeight'], 'w600');
      expect(style['fontStyle'], 'italic');
    });

    test('writes every published field of the style it is given', () {
      final dc = DynamicContent();
      populateThemeData(
        dc,
        colorScheme: const ColorScheme.light(),
        iconTheme: const IconThemeData(),
        defaultTextStyle: _style(3),
        textTheme: const TextTheme(),
      );
      final style = (_readKey(dc, 'theme') as Map)['defaultTextStyle'] as Map;
      expect(style['color'], 0xFF000003);
      expect(style['backgroundColor'], 0xFF100003);
      expect(style['fontFamily'], 'Face3');
      expect(style['fontFamilyFallback'], ['Fallback3', 'Serif']);
      expect(style['fontSize'], 13.0);
      expect(style['fontWeight'], 'w400');
      expect(style['fontStyle'], 'italic');
      expect(style['letterSpacing'], closeTo(3.1, 1e-9));
      expect(style['wordSpacing'], closeTo(3.2, 1e-9));
      expect(style['height'], closeTo(4.1, 1e-9));
      // Each enum-valued field publishes the member name its decoder reads.
      expect(style['leadingDistribution'], 'even');
      expect(style['textBaseline'], 'ideographic');
      expect(style['overflow'], 'ellipsis');
      expect(style['decoration'], 'underline');
      expect(style['decorationColor'], 0xFF200003);
      expect(style['decorationStyle'], 'dashed');
      expect(style['decorationThickness'], 5.0);
    });

    test('publishes a token for each named decoration', () {
      String? decorationFor(TextDecoration decoration) {
        final dc = DynamicContent();
        populateThemeData(
          dc,
          colorScheme: const ColorScheme.light(),
          iconTheme: const IconThemeData(),
          defaultTextStyle: TextStyle(decoration: decoration),
          textTheme: const TextTheme(),
        );
        final style = (_readKey(dc, 'theme') as Map)['defaultTextStyle'] as Map;
        return style['decoration'] as String?;
      }

      expect(decorationFor(TextDecoration.none), 'none');
      expect(decorationFor(TextDecoration.underline), 'underline');
      expect(decorationFor(TextDecoration.overline), 'overline');
      expect(decorationFor(TextDecoration.lineThrough), 'lineThrough');
      // A combined decoration has no token, so the key is omitted and the
      // consumer keeps its own default.
      expect(
        decorationFor(
          TextDecoration.combine([
            TextDecoration.underline,
            TextDecoration.overline,
          ]),
        ),
        isNull,
      );
    });

    test('omits defaultTextStyle keys that are null', () {
      final dc = DynamicContent();
      populateThemeData(
        dc,
        colorScheme: const ColorScheme.light(),
        iconTheme: const IconThemeData(),
        defaultTextStyle: const TextStyle(),
        textTheme: const TextTheme(),
      );
      final style = (_readKey(dc, 'theme') as Map)['defaultTextStyle'] as Map;
      expect(style, isEmpty);
    });

    test('writes each text-theme style as its own field sub-map', () {
      final dc = DynamicContent();
      populateThemeData(
        dc,
        colorScheme: const ColorScheme.light(),
        iconTheme: const IconThemeData(),
        defaultTextStyle: const TextStyle(),
        textTheme: const TextTheme(
          titleLarge: TextStyle(
            color: Color(0xFF223344),
            fontFamily: 'Charter',
            fontSize: 22,
            fontWeight: FontWeight.w500,
            fontStyle: FontStyle.italic,
            letterSpacing: 0.15,
            height: 1.25,
          ),
        ),
      );
      final textTheme = (_readKey(dc, 'theme') as Map)['textTheme'] as Map;
      final titleLarge = textTheme['titleLarge'] as Map;
      expect(titleLarge['color'], 0xFF223344);
      expect(titleLarge['fontFamily'], 'Charter');
      expect(titleLarge['fontSize'], 22.0);
      expect(titleLarge['fontWeight'], 'w500');
      // The member name an enum-by-name decoder reads.
      expect(titleLarge['fontStyle'], 'italic');
      expect(titleLarge['letterSpacing'], 0.15);
      expect(titleLarge['height'], 1.25);
    });

    test('omits text-theme fields that are null, and null styles entirely', () {
      final dc = DynamicContent();
      populateThemeData(
        dc,
        colorScheme: const ColorScheme.light(),
        iconTheme: const IconThemeData(),
        defaultTextStyle: const TextStyle(),
        textTheme: const TextTheme(bodyMedium: TextStyle(fontSize: 14)),
      );
      final textTheme = (_readKey(dc, 'theme') as Map)['textTheme'] as Map;
      final bodyMedium = textTheme['bodyMedium'] as Map;
      expect(bodyMedium['fontSize'], 14.0);
      expect(bodyMedium.containsKey('color'), isFalse);
      expect(bodyMedium.containsKey('fontFamily'), isFalse);
      expect(bodyMedium.containsKey('fontWeight'), isFalse);
      expect(bodyMedium.containsKey('fontStyle'), isFalse);
      expect(bodyMedium.containsKey('letterSpacing'), isFalse);
      expect(bodyMedium.containsKey('height'), isFalse);
      // A null style publishes an empty map, so every field reads back null.
      expect(textTheme['titleLarge'], isEmpty);
    });

    test(
        'a fully-populated theme publishes exactly the kThemeContractPaths '
        'set — drift gate against the codegen-side contract validation', () {
      // The single drift gate between the SDK publisher and the
      // codegen-side translator's contract validation: anything
      // populateThemeData writes that's not in kThemeContractPaths (or
      // vice-versa) breaks here.
      final dc = DynamicContent();
      populateThemeData(
        dc,
        colorScheme: const ColorScheme.light(),
        iconTheme: const IconThemeData(color: Color(0xFF000000), size: 24),
        defaultTextStyle: _style(0),
        textTheme: _fullTextTheme,
      );

      Set<String> flatten(Map<dynamic, dynamic> tree, [String prefix = '']) {
        final out = <String>{};
        tree.forEach((key, value) {
          final path = prefix.isEmpty ? '$key' : '$prefix.$key';
          if (value is Map) {
            out.addAll(flatten(value, path));
          } else {
            out.add(path);
          }
        });
        return out;
      }

      final published = flatten(_readKey(dc, 'theme') as Map);
      expect(published, kThemeContractPaths);
    });

    test('publishes the brightness of the theme it is given', () {
      String brightnessFor(ColorScheme colorScheme) {
        final dc = DynamicContent();
        populateThemeData(
          dc,
          colorScheme: colorScheme,
          iconTheme: const IconThemeData(),
          defaultTextStyle: const TextStyle(),
          textTheme: const TextTheme(),
        );
        return (_readKey(dc, 'theme') as Map)['brightness'] as String;
      }

      expect(brightnessFor(const ColorScheme.dark()), 'dark');
      expect(brightnessFor(const ColorScheme.light()), 'light');
    });

    test('snaps a non-standard fontWeight to the nearest standard weight', () {
      // FontWeight's public ctor accepts any 1-1000 value (variable fonts),
      // but the contract and RFW's enumValue<FontWeight> only know w100-w900.
      String fontWeightFor(FontWeight weight) {
        final dc = DynamicContent();
        populateThemeData(
          dc,
          colorScheme: const ColorScheme.light(),
          iconTheme: const IconThemeData(),
          defaultTextStyle: TextStyle(fontWeight: weight),
          textTheme: const TextTheme(),
        );
        return ((_readKey(dc, 'theme') as Map)['defaultTextStyle']
            as Map)['fontWeight'] as String;
      }

      expect(fontWeightFor(const FontWeight(350)), 'w400');
      expect(fontWeightFor(const FontWeight(1000)), 'w900');
    });
  });
}

/// Every published style carrying every published field — the fully-populated
/// input the contract drift gate needs.
final TextTheme _fullTextTheme = TextTheme(
  displayLarge: _style(0),
  displayMedium: _style(1),
  displaySmall: _style(2),
  headlineLarge: _style(3),
  headlineMedium: _style(4),
  headlineSmall: _style(5),
  titleLarge: _style(6),
  titleMedium: _style(7),
  titleSmall: _style(8),
  bodyLarge: _style(9),
  bodyMedium: _style(10),
  bodySmall: _style(11),
  labelLarge: _style(12),
  labelMedium: _style(13),
  labelSmall: _style(14),
);

/// A distinct [TextStyle] per index, so a cross-wired style reads as a wrong
/// value rather than a coincidental match. Carries every published field, so
/// the contract drift gate sees a fully-populated style.
TextStyle _style(int index) => TextStyle(
      color: Color(0xFF000000 + index),
      backgroundColor: Color(0xFF100000 + index),
      fontFamily: 'Face$index',
      fontFamilyFallback: ['Fallback$index', 'Serif'],
      fontSize: 10.0 + index,
      fontWeight: FontWeight.w400,
      fontStyle: FontStyle.italic,
      letterSpacing: 0.1 + index,
      wordSpacing: 0.2 + index,
      height: 1.1 + index,
      leadingDistribution: TextLeadingDistribution.even,
      textBaseline: TextBaseline.ideographic,
      overflow: TextOverflow.ellipsis,
      decoration: TextDecoration.underline,
      decorationColor: Color(0xFF200000 + index),
      decorationStyle: TextDecorationStyle.dashed,
      decorationThickness: 2.0 + index,
    );
