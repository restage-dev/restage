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

    test('does not register withdrawn commerce helpers', () {
      for (final name in const ['paywallPurchase', 'paywallPriceFor']) {
        expect(registry.find(name, 'package:restage'), isNull, reason: name);
      }
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
          positional: ['"continue"'],
          named: {},
        ),
      );
      expect(out, 'event "continue" {}');
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
