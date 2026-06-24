import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_shared/restage_shared.dart' show kThemeContractPaths;
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
  group('populateProductData', () {
    test('merges product info into DynamicContent (addressable by id and slot)',
        () {
      final dc = DynamicContent();
      populateProductData(
        dc,
        products: const [
          RestageProduct(
            id: 'pro_monthly',
            slot: 'primary',
            entitlement: 'pro',
          ),
        ],
        priceQueries: const {
          'pro_monthly': PriceInfo(
            localizedPrice: r'$9.99',
            priceMicros: 9990000,
            currency: 'USD',
            title: 'Pro Monthly',
            description: 'Unlock Pro features',
          ),
        },
      );

      final products = _readKey(dc, 'products') as Map;
      // Addressable by slot.
      final bySlot = products['primary'] as Map;
      expect(bySlot['localizedPrice'], r'$9.99');
      expect(bySlot['priceMicros'], 9990000);
      expect(bySlot['currency'], 'USD');
      expect(bySlot['title'], 'Pro Monthly');
      expect(bySlot['description'], 'Unlock Pro features');
      expect(bySlot['isTrial'], false);
      expect(bySlot.containsKey('trialDurationDays'), isFalse);

      // Addressable by productId.
      final byId = products['pro_monthly'] as Map;
      expect(byId['localizedPrice'], r'$9.99');
      expect(byId['currency'], 'USD');
    });

    test('includes trialDurationDays only when set', () {
      final dc = DynamicContent();
      populateProductData(
        dc,
        products: const [
          RestageProduct(id: 'pro_trial', slot: 'primary', entitlement: 'pro'),
        ],
        priceQueries: const {
          'pro_trial': PriceInfo(
            localizedPrice: r'$0.00',
            priceMicros: 0,
            currency: 'USD',
            title: 'Free Trial',
            description: '7 days free',
            isTrial: true,
            trialDurationDays: 7,
          ),
        },
      );

      final products = _readKey(dc, 'products') as Map;
      final entry = products['primary'] as Map;
      expect(entry['isTrial'], true);
      expect(entry['trialDurationDays'], 7);
    });

    test('skips products without a price entry', () {
      final dc = DynamicContent();
      populateProductData(
        dc,
        products: const [
          RestageProduct(id: 'no_price', slot: 'primary', entitlement: 'pro'),
        ],
        priceQueries: const {},
      );

      final products = _readKey(dc, 'products') as Map;
      expect(products, isEmpty);
    });
  });

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
        ),
        platform: 'ios',
      );

      final device = _readKey(dc, 'device') as Map;
      expect(device['locale'], 'en_US');
      expect(device['platform'], 'ios');
      expect(device['screenWidth'], 390.0);
      expect(device['screenHeight'], 844.0);
      expect(device['pixelRatio'], 3.0);
      expect(device['safeAreaTop'], 47.0);
      expect(device['safeAreaBottom'], 34.0);
      expect(device['safeAreaLeft'], 0.0);
      expect(device['safeAreaRight'], 0.0);
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
      );
      final iconTheme = (_readKey(dc, 'theme') as Map)['iconTheme'] as Map;
      expect(iconTheme.containsKey('color'), isFalse);
      expect(iconTheme.containsKey('size'), isFalse);
    });

    test('writes defaultTextStyle color, fontSize, fontWeight (w-string)', () {
      final dc = DynamicContent();
      populateThemeData(
        dc,
        colorScheme: const ColorScheme.light(),
        iconTheme: const IconThemeData(),
        defaultTextStyle: const TextStyle(
          color: Color(0xFF778899),
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      );
      final style = (_readKey(dc, 'theme') as Map)['defaultTextStyle'] as Map;
      expect(style['color'], 0xFF778899);
      expect(style['fontSize'], 17.0);
      expect(style['fontWeight'], 'w600');
    });

    test('omits defaultTextStyle keys that are null', () {
      final dc = DynamicContent();
      populateThemeData(
        dc,
        colorScheme: const ColorScheme.light(),
        iconTheme: const IconThemeData(),
        defaultTextStyle: const TextStyle(),
      );
      final style = (_readKey(dc, 'theme') as Map)['defaultTextStyle'] as Map;
      expect(style.containsKey('color'), isFalse);
      expect(style.containsKey('fontSize'), isFalse);
      expect(style.containsKey('fontWeight'), isFalse);
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
        defaultTextStyle: const TextStyle(
          color: Color(0xFF000000),
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
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
        );
        return ((_readKey(dc, 'theme') as Map)['defaultTextStyle']
            as Map)['fontWeight'] as String;
      }

      expect(fontWeightFor(const FontWeight(350)), 'w400');
      expect(fontWeightFor(const FontWeight(1000)), 'w900');
    });
  });

  group('PriceInfo value equality', () {
    PriceInfo make({
      String localizedPrice = r'$9.99',
      int priceMicros = 9990000,
      String currency = 'USD',
      String title = 'Pro Monthly',
      String description = 'Unlock Pro',
      bool isTrial = false,
      int? trialDurationDays,
    }) =>
        PriceInfo(
          localizedPrice: localizedPrice,
          priceMicros: priceMicros,
          currency: currency,
          title: title,
          description: description,
          isTrial: isTrial,
          trialDurationDays: trialDurationDays,
        );

    test('two instances with identical fields are equal and share a hashCode',
        () {
      expect(make(), equals(make()));
      expect(make().hashCode, make().hashCode);
    });

    test('differs when any scalar field differs', () {
      expect(make(currency: 'USD'), isNot(equals(make(currency: 'EUR'))));
      expect(make(priceMicros: 100), isNot(equals(make(priceMicros: 200))));
      expect(make(title: 'A'), isNot(equals(make(title: 'B'))));
      expect(
        make(isTrial: true, trialDurationDays: 7),
        isNot(equals(make(isTrial: true, trialDurationDays: 14))),
      );
    });

    test('dedups in a Set when fields match (host caching use case)', () {
      expect({make(), make()}, hasLength(1));
    });
  });
}
