// Product keys that are not identifier-shaped must reach the widget-text
// format as QUOTED reference parts.
//
// A reference part may be an identifier, an integer, or a quoted string, and
// the identifier production is `letter ( letter | digit )*` with `letter`
// covering `A-Z`, `a-z` and `_`. A real store id (`com.example.pro.annual`)
// emitted bare therefore splits across its dots into one part per segment; an
// all-digit id decodes as an *integer* part; a hyphenated or digit-leading id
// does not tokenize at all. The runtime keys products by the whole id as a
// single map key, so every one of those is unresolvable.
//
// Each case is asserted twice: on the emitted text, and on what the vendored
// parser actually makes of that text — the emitter's own output is not
// evidence about the grammar.
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/paywall_helpers.dart';
import 'package:restage_shared/rfw_formats.dart';
import 'package:test/test.dart';

/// Runs the `paywallPriceFor` lowering over a single named argument.
///
/// Each argument is given as the expression translator hands it over: the body
/// of a double-quoted string, already escaped for the widget-text format
/// (backslash, double quote and newline).
String lower({String? slot, String? productId}) {
  final h = paywallHelpers.firstWhere((d) => d.name == 'paywallPriceFor');
  return h.translate(
    HelperCallArgs(
      positional: const [],
      named: {
        if (slot != null) 'slot': '"$slot"',
        if (productId != null) 'productId': '"$productId"',
      },
    ),
  );
}

/// The reference parts the vendored parser produces for [lowered], used as the
/// `text:` argument of a widget — the same grammar the build output is fed to.
List<Object> partsOf(String lowered) {
  final library = parseLibraryFile('widget root = Text(text: $lowered);');
  final root = library.widgets.single.root as ConstructorCall;
  return (root.arguments['text']! as DataReference).parts;
}

void main() {
  group('paywallPriceFor emits a resolvable reference part', () {
    test('a reverse-DNS store id is quoted and stays ONE part', () {
      final out = lower(productId: 'com.example.pro.annual');
      expect(out, 'data.products."com.example.pro.annual".localizedPrice');
      expect(
        partsOf(out),
        ['products', 'com.example.pro.annual', 'localizedPrice'],
      );
    });

    test('an all-digit id is quoted, so its part stays a STRING not an int',
        () {
      final out = lower(productId: '12345');
      expect(out, 'data.products."12345".localizedPrice');
      // The element match is by `==`, so this also pins the part's TYPE — the
      // distinction the runtime's String-keyed product map turns on. Unquoted,
      // `12345` decodes as `int` 12345, which no string key can equal.
      expect(partsOf(out), ['products', '12345', 'localizedPrice']);
    });

    test('a hyphenated id is quoted (bare, it does not tokenize at all)', () {
      final out = lower(productId: 'pro-annual');
      expect(out, 'data.products."pro-annual".localizedPrice');
      expect(partsOf(out), ['products', 'pro-annual', 'localizedPrice']);
    });

    test('a digit-leading id is quoted', () {
      final out = lower(productId: '1annual');
      expect(out, 'data.products."1annual".localizedPrice');
      expect(partsOf(out), ['products', '1annual', 'localizedPrice']);
    });

    test('an id with a space is quoted', () {
      final out = lower(productId: 'pro annual');
      expect(out, 'data.products."pro annual".localizedPrice');
      expect(partsOf(out), ['products', 'pro annual', 'localizedPrice']);
    });
  });

  group('identifier-shaped keys stay bare (no emitted output moves)', () {
    test('a slot is unquoted', () {
      final out = lower(slot: 'primary');
      expect(out, 'data.products.primary.localizedPrice');
      expect(partsOf(out), ['products', 'primary', 'localizedPrice']);
    });

    test('an identifier-shaped productId is unquoted', () {
      final out = lower(productId: 'pro_annual2');
      expect(out, 'data.products.pro_annual2.localizedPrice');
      expect(partsOf(out), ['products', 'pro_annual2', 'localizedPrice']);
    });

    test('a leading-underscore key is an identifier and stays unquoted', () {
      final out = lower(slot: '_internal');
      expect(out, 'data.products._internal.localizedPrice');
      expect(partsOf(out), ['products', '_internal', 'localizedPrice']);
    });

    test('a key that collides with a reserved word stays unquoted', () {
      // Reference parts are not reserved-word checked, so `data` needs no
      // carve-out — quoting it would move output for no reason.
      final out = lower(slot: 'data');
      expect(out, 'data.products.data.localizedPrice');
      expect(partsOf(out), ['products', 'data', 'localizedPrice']);
    });
  });

  group('escapes already applied at the literal boundary are not doubled', () {
    test('an id containing a double quote survives the round trip', () {
      // The translator hands over `"a\"b.c"`; re-escaping here would emit
      // `a\\\"b.c` and decode to a DIFFERENT key.
      final out = lower(productId: r'a\"b.c');
      expect(out, r'data.products."a\"b.c".localizedPrice');
      expect(partsOf(out), ['products', 'a"b.c', 'localizedPrice']);
    });

    test('an id containing a backslash survives the round trip', () {
      final out = lower(productId: r'a\\b.c');
      expect(out, r'data.products."a\\b.c".localizedPrice');
      expect(partsOf(out), ['products', r'a\b.c', 'localizedPrice']);
    });

    test('an id containing both a quote and a backslash survives', () {
      final out = lower(productId: r'a\"b\\c.d');
      expect(out, r'data.products."a\"b\\c.d".localizedPrice');
      expect(partsOf(out), ['products', r'a"b\c.d', 'localizedPrice']);
    });
  });

  group('a blank key stays a build failure rather than becoming silent', () {
    // Quoting turns keys that used to fail the build into working references.
    // A blank key must NOT come along for the ride: bare, it failed to parse
    // and stopped the build; quoted, `data.products."".localizedPrice` parses
    // cleanly and then never resolves anything, for the whole life of the
    // surface. Loud beats silent, so it is rejected here instead.
    test('an empty productId is rejected', () {
      expect(() => lower(productId: ''), throwsArgumentError);
    });

    test('a whitespace-only productId is rejected', () {
      expect(() => lower(productId: '   '), throwsArgumentError);
    });

    test('an empty slot is rejected', () {
      expect(() => lower(slot: ''), throwsArgumentError);
    });
  });

  group('argument validation is unchanged', () {
    test('neither slot nor productId throws', () {
      final h = paywallHelpers.firstWhere((d) => d.name == 'paywallPriceFor');
      expect(
        () => h.translate(
          const HelperCallArgs(positional: [], named: {}),
        ),
        throwsArgumentError,
      );
    });

    test('both slot and productId throws', () {
      expect(
        () => lower(slot: 'a', productId: 'b'),
        throwsArgumentError,
      );
    });
  });
}
