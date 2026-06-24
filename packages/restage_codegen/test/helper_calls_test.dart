import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/onboarding/onboarding_helpers.dart';
import 'package:restage_codegen/src/paywall_helpers.dart';
import 'package:restage_codegen/src/production_helpers.dart';
import 'package:test/test.dart';

void main() {
  group('HelperRegistry', () {
    final registry = productionPaywallHelperRegistry();

    test('recognizes paywallEvent', () {
      final h = registry.find('paywallEvent', 'package:restage');
      expect(h, isNotNull);
      expect(h!.name, 'paywallEvent');
      expect(h.returnCategory, HelperReturnCategory.voidCallback);
    });

    test('recognizes paywallPurchase', () {
      final h = registry.find('paywallPurchase', 'package:restage');
      expect(h, isNotNull);
      expect(h!.returnCategory, HelperReturnCategory.voidCallback);
    });

    test('recognizes paywallPriceFor as String-returning', () {
      final h = registry.find('paywallPriceFor', 'package:restage');
      expect(h, isNotNull);
      expect(h!.returnCategory, HelperReturnCategory.string);
    });

    test('returns null for unrecognized name', () {
      final h = registry.find('frobnicate', 'package:restage');
      expect(h, isNull);
    });

    test('returns null for wrong library origin', () {
      final h = registry.find('paywallEvent', 'package:other_package');
      expect(h, isNull);
    });

    test('library origin matches by URI prefix', () {
      // The translator passes the resolved library URI from the analyzer,
      // which may be a sub-path like `package:restage/src/.../foo.dart`.
      // The match should still succeed because the prefix matches.
      final h = registry.find(
        'paywallEvent',
        'package:restage/src/authoring/paywall_event.dart',
      );
      expect(h, isNotNull);
    });

    test('library origin rejects package-name lookalikes', () {
      final h = registry.find(
        'paywallEvent',
        'package:restage_flutter_sdk_fake/src/paywall_event.dart',
      );
      expect(h, isNull);
    });

    test('definitions exposes the registered set in registration order', () {
      final r = HelperRegistry()..registerAll(paywallHelpers);
      expect(
        r.definitions.map((d) => d.name).toList(),
        paywallHelpers.map((d) => d.name).toList(),
      );
    });
  });

  group('paywallHelpers translations', () {
    test('paywallEvent("name") → event "name" {}', () {
      final h = paywallHelpers.firstWhere((d) => d.name == 'paywallEvent');
      final out = h.translate(
        const HelperCallArgs(
          positional: ['"restore"'],
          named: {},
        ),
      );
      expect(out, 'event "restore" {}');
    });

    test('paywallEvent with args', () {
      final h = paywallHelpers.firstWhere((d) => d.name == 'paywallEvent');
      final out = h.translate(
        const HelperCallArgs(
          positional: ['"foo"'],
          named: {'args': '{ k: 1 }'},
        ),
      );
      expect(out, 'event "foo" { k: 1 }');
    });

    test('paywallPurchase(slot:) → restage.purchase event', () {
      final h = paywallHelpers.firstWhere((d) => d.name == 'paywallPurchase');
      final out = h.translate(
        const HelperCallArgs(
          positional: [],
          named: {'slot': '"primary"'},
        ),
      );
      expect(out, 'event "restage.purchase" { slot: "primary" }');
    });

    test('paywallPurchase(productId:)', () {
      final h = paywallHelpers.firstWhere((d) => d.name == 'paywallPurchase');
      final out = h.translate(
        const HelperCallArgs(
          positional: [],
          named: {'productId': '"sku.foo"'},
        ),
      );
      expect(out, 'event "restage.purchase" { productId: "sku.foo" }');
    });

    test('paywallPurchase rejects neither/both slot+productId', () {
      final h = paywallHelpers.firstWhere((d) => d.name == 'paywallPurchase');
      expect(
        () => h.translate(const HelperCallArgs(positional: [], named: {})),
        throwsArgumentError,
      );
      expect(
        () => h.translate(
          const HelperCallArgs(
            positional: [],
            named: {'slot': '"a"', 'productId': '"b"'},
          ),
        ),
        throwsArgumentError,
      );
    });

    test('paywallPriceFor(slot:) → data.products.<slot>.localizedPrice', () {
      final h = paywallHelpers.firstWhere((d) => d.name == 'paywallPriceFor');
      final out = h.translate(
        const HelperCallArgs(
          positional: [],
          named: {'slot': '"primary"'},
        ),
      );
      expect(out, 'data.products.primary.localizedPrice');
    });

    test('paywallPriceFor(productId:) → data.products.<id>.localizedPrice', () {
      final h = paywallHelpers.firstWhere((d) => d.name == 'paywallPriceFor');
      final out = h.translate(
        const HelperCallArgs(
          positional: [],
          named: {'productId': '"sku.foo"'},
        ),
      );
      expect(out, 'data.products.sku.foo.localizedPrice');
    });
  });

  group('onboardingHelpers translations', () {
    test('onboardingEvent with payload', () {
      final h =
          onboardingHelpers.firstWhere((d) => d.name == 'onboardingEvent');
      final out = h.translate(
        const HelperCallArgs(
          positional: [
            '"analyticsTap"',
            '{ ctaId: "primary", secret: "internal" }',
          ],
          named: {},
        ),
      );
      expect(
        out,
        'event "analyticsTap" { ctaId: "primary", secret: "internal" }',
      );
    });
  });
}
