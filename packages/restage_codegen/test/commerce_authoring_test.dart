import 'package:restage_codegen/src/catalog_validator.dart';
import 'package:restage_codegen/src/commerce_authoring.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/onboarding/onboarding_helpers.dart';
import 'package:restage_codegen/src/paywall_helpers.dart';
import 'package:restage_shared/rfw_formats.dart' show parseLibraryFile;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final translator = ExpressionTranslator(
    catalog: kEmptyCatalog,
    helpers: HelperRegistry()..registerAll(paywallHelpers),
  );

  group('commerce authoring', () {
    test('rejects withdrawn helper calls', () async {
      for (final entry in const <(String, String)>[
        ('paywallPurchase', 'paywallPurchase(slot: "primary")'),
        ('paywallPriceFor', 'paywallPriceFor(slot: "primary")'),
      ]) {
        final result = translator.translate(
          await parseExpressionForTest(entry.$2),
        );

        expect(result.dsl, isEmpty, reason: entry.$1);
        expect(
          result.issues.map((issue) => issue.code.name),
          ['unsupportedCommerceAuthoring'],
          reason: entry.$1,
        );
        expect(
          result.issues.single.message,
          allOf(
            contains(entry.$1),
            contains(
              'Authored surfaces cannot initiate purchases or restores.',
            ),
            contains(
              'Applications invoke the typed commerce boundary from explicit '
              'host-controlled code.',
            ),
            contains('The current facade is unavailable until activated.'),
          ),
          reason: entry.$1,
        );
      }
    });

    test('rejects reserved SDK event names', () async {
      for (final name in unsupportedCommerceEventNames) {
        final result = translator.translate(
          await parseExpressionForTest("paywallEvent('$name')"),
        );

        expect(result.dsl, isEmpty, reason: name);
        expect(
          result.issues.map((issue) => issue.code.name),
          ['unsupportedCommerceAuthoring'],
          reason: name,
        );
        expect(result.issues.single.message, contains(name), reason: name);
      }
    });

    test('rejects reserved names in conditional event arguments', () async {
      final result = translator.translate(
        await parseExpressionForTest(
          "paywallEvent(enabled ? 'continue' : 'restage.purchase.pending')",
        ),
      );

      expect(
        result.issues.map((issue) => issue.code.name),
        ['unsupportedCommerceAuthoring'],
      );
      expect(result.dsl, isNot(contains('restage.purchase.pending')));
    });

    test('rejects a prefixed SDK event helper', () async {
      final result = translator.translate(
        await parseExpressionFromSourceForTest(
          '''
import 'package:restage/restage.dart' as sdk;

Object x() => sdk.paywallEvent('restage.purchase');
''',
          rootPackage: 'apps_examples',
        ),
      );

      expect(
        result.issues.map((issue) => issue.code.name),
        ['unsupportedCommerceAuthoring'],
      );
    });

    test('rejects a reserved named event descriptor', () async {
      final eventTranslator = ExpressionTranslator(
        catalog: kEmptyCatalog,
        helpers: HelperRegistry()..registerAll(onboardingHelpers),
      );
      final result = eventTranslator.translate(
        await parseExpressionFromSourceForTest(
          '''
import 'package:restage/restage.dart';

abstract final class Probe {
  static const blocked = SurfaceEvent<void>('restage.purchase');
}

Object x() => surfaceEvent(Probe.blocked);
''',
          rootPackage: 'apps_examples',
        ),
      );

      expect(
        result.issues.map((issue) => issue.code.name),
        ['unsupportedCommerceAuthoring'],
      );
    });

    test('does not flag a resolved same-name function', () async {
      final result = translator.translate(
        await parseExpressionFromSourceForTest('''
          Object paywallPurchase({String? slot}) => Object();
          Object x() => paywallPurchase(slot: 'primary');
        '''),
      );

      expect(
        result.issues.map((issue) => issue.code.name),
        isNot(contains('unsupportedCommerceAuthoring')),
      );
    });

    test('rejects reserved output events and product data', () {
      const source = '''
        import restage.core;
        widget Paywall = GestureDetector(
          onTap: event "restage.purchase" {},
          onLongPress: event "restore" {},
          child: Text(text: data.products.primary.localizedPrice),
        );
      ''';
      final library = parseLibraryFile(source, sourceIdentifier: 'test');
      final issues = validateModelAgainstCatalog(
        library,
        catalogWith([
          entry(
            name: 'GestureDetector',
            properties: [
              prop('onTap', PropertyType.event),
              prop('onLongPress', PropertyType.event),
              prop('child', PropertyType.widget),
            ],
          ),
          entry(
            name: 'Text',
            properties: [prop('text', PropertyType.string)],
          ),
        ]),
      );

      expect(issues, hasLength(3));
      expect(
        issues.map((issue) => issue.code.name),
        everyElement('unsupportedCommerceAuthoring'),
      );
      expect(
        issues.map((issue) => issue.message).join('\n'),
        allOf(contains('data.products'), contains("event 'restore'")),
      );
    });

    test('rejects product data in a list loop output', () {
      const source = '''
        import restage.core;
        widget Paywall = Column(children: [
          ...for row in data.context.rows:
            Text(text: data.products.primary.localizedPrice)
        ]);
      ''';
      final library = parseLibraryFile(source, sourceIdentifier: 'test');
      final issues = validateCommerceAuthoring(library);

      expect(issues, hasLength(1));
      expect(issues.single.code.name, 'unsupportedCommerceAuthoring');
      expect(issues.single.message, contains('data.products'));
    });
  });
}
