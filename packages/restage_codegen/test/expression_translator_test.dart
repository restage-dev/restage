import 'dart:io';
import 'dart:typed_data';

import 'package:analyzer/source/line_info.dart';
import 'package:restage_codegen/src/catalog_validator.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/paywall_helpers.dart';
import 'package:restage_codegen/src/rfw_emitter.dart';
import 'package:restage_codegen/src/setstate_recognition.dart';
import 'package:restage_codegen/src/widget_catalog/translator_tables.g.dart';
import 'package:restage_shared/restage_shared.dart' show kSupportedCurveNames;
import 'package:restage_shared/rfw_formats.dart' as fmt;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

// ---------------------------------------------------------------------------
// Test-local helper definitions whose libraryOrigin matches the synthetic
// source URI produced by parseExpressionFromSourceForTest. The synthetic
// file is mounted under `package:restage_codegen/lib/...`, so using the
// prefix `package:restage_codegen` ensures the registry lookup succeeds.
// ---------------------------------------------------------------------------

const String _kTestLibraryOrigin = 'package:restage_codegen';

final List<HelperDefinition> _testHelpers = [
  HelperDefinition(
    name: 'paywallEvent',
    libraryOrigin: _kTestLibraryOrigin,
    returnCategory: HelperReturnCategory.voidCallback,
    translate: (args) {
      if (args.positional.isEmpty) {
        throw ArgumentError('paywallEvent requires a positional name argument');
      }
      final name = _stripTestQuotes(args.positional.first);
      final body = args.named['args'] ?? '{}';
      return 'event "$name" $body';
    },
  ),
  HelperDefinition(
    name: 'paywallPurchase',
    libraryOrigin: _kTestLibraryOrigin,
    returnCategory: HelperReturnCategory.voidCallback,
    translate: (args) {
      final slot = args.named['slot'];
      final productId = args.named['productId'];
      if ((slot == null) == (productId == null)) {
        throw ArgumentError(
          'paywallPurchase requires exactly one of slot: or productId:',
        );
      }
      final body =
          slot != null ? '{ slot: $slot }' : '{ productId: $productId }';
      return 'event "restage.purchase" $body';
    },
  ),
  HelperDefinition(
    name: 'paywallPriceFor',
    libraryOrigin: _kTestLibraryOrigin,
    returnCategory: HelperReturnCategory.string,
    translate: (args) {
      final slot = args.named['slot'];
      final productId = args.named['productId'];
      if ((slot == null) == (productId == null)) {
        throw ArgumentError(
          'paywallPriceFor requires exactly one of slot: or productId:',
        );
      }
      final id = _stripTestQuotes(slot ?? productId!);
      return 'data.products.$id.localizedPrice';
    },
  ),
];

String _stripTestQuotes(String s) {
  if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
    return s.substring(1, s.length - 1);
  }
  return s;
}

void main() {
  late ExpressionTranslator translator;

  setUp(() {
    translator = ExpressionTranslator(
      catalog: kEmptyCatalog,
      helpers: HelperRegistry(),
    );
  });

  group('literal translation', () {
    test('string literal', () async {
      final r = translator.translate(await parseExpressionForTest("'hello'"));
      expect(r.dsl, '"hello"');
      expect(r.issues, isEmpty);
    });

    test('escapes backslash, double-quote, and newline', () async {
      // r"a\nb" is the string `a\nb` (literal backslash-n, not newline).
      // We test escaping of: backslash, double-quote, and actual newline.
      final r = translator.translate(
        await parseExpressionForTest(r'"a\\b\"c"'),
      );
      expect(r.dsl, r'"a\\b\"c"');
    });

    test('int literal', () async {
      final r = translator.translate(await parseExpressionForTest('42'));
      expect(r.dsl, '42');
    });

    test('double literal preserves .0', () async {
      final r = translator.translate(await parseExpressionForTest('3.14'));
      expect(r.dsl, '3.14');
      final r2 = translator.translate(await parseExpressionForTest('1.0'));
      expect(r2.dsl, '1.0');
    });

    test('bool literals', () async {
      expect(
        translator.translate(await parseExpressionForTest('true')).dsl,
        'true',
      );
      expect(
        translator.translate(await parseExpressionForTest('false')).dsl,
        'false',
      );
    });

    test('null literal', () async {
      final r = translator.translate(await parseExpressionForTest('null'));
      expect(r.dsl, 'null');
    });

    test('escapes actual newline character in string literal', () async {
      // "'line1\\nline2'" as a Dart source string contains a real newline byte
      // (the \n is parsed by the Dart parser, not by our translator). The
      // translator's _stringLiteral must escape it to \n in DSL output.
      final r = translator.translate(
        await parseExpressionForTest(r"'line1\nline2'"),
      );
      // DSL output: the real newline byte should be represented as \\n.
      expect(r.dsl, r'"line1\nline2"');
      expect(r.issues, isEmpty);
    });

    test('adjacent string literals lower to a single concatenated string',
        () async {
      final r = translator.translate(await parseExpressionForTest("'a' 'b'"));
      expect(r.dsl, '"ab"');
      expect(r.issues, isEmpty);
    });

    test('three adjacent string literals concatenate in order', () async {
      final r = translator.translate(
        await parseExpressionForTest("'a' 'b' 'c'"),
      );
      expect(r.dsl, '"abc"');
      expect(r.issues, isEmpty);
    });
  });

  group('list literal translation', () {
    test('empty list', () async {
      final r = translator.translate(await parseExpressionForTest('[]'));
      expect(r.dsl, '[]');
      expect(r.issues, isEmpty);
    });

    test('list of literals', () async {
      final r = translator.translate(
        await parseExpressionForTest('[1, 2, 3]'),
      );
      expect(r.dsl, '[1, 2, 3]');
      expect(r.issues, isEmpty);
    });

    test('list of mixed literals', () async {
      final r = translator.translate(
        await parseExpressionForTest("[1, 'a', true, null]"),
      );
      expect(r.dsl, '[1, "a", true, null]');
      expect(r.issues, isEmpty);
    });

    test('rejects spread element', () async {
      final r = translator.translate(
        await parseExpressionForTest('[...const [1, 2]]'),
      );
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.unsupportedCollectionFlow),
      );
    });

    test('rejects collection-if', () async {
      final r = translator.translate(
        await parseExpressionForTest('[if (true) 1]'),
      );
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.unsupportedCollectionFlow),
      );
    });

    test('rejects collection-for', () async {
      final r = translator.translate(
        await parseExpressionForTest('[for (var i in const [1, 2, 3]) i]'),
      );
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.unsupportedCollectionFlow),
      );
    });
  });

  group('enum + Colors translation', () {
    test('enum value reference → string-encoded', () async {
      final r = translator.translate(
        await parseExpressionForTest('MainAxisAlignment.center'),
      );
      expect(r.dsl, '"center"');
      expect(r.issues, isEmpty);
    });

    test('FontWeight.w700', () async {
      final r = translator.translate(
        await parseExpressionForTest('FontWeight.w700'),
      );
      expect(r.dsl, '"w700"');
    });

    test('resolved FontWeight.w600 → canonical "w600"', () async {
      final r = translator.translate(
        await parseExpressionFromSourceForTest(
          '''
          import 'package:flutter/material.dart';
          Object x() => FontWeight.w600;
          ''',
          rootPackage: 'apps_examples',
        ),
      );
      expect(r.dsl, '"w600"');
      expect(r.issues, isEmpty);
    });

    test('resolved FontWeight.normal alias → canonical "w400"', () async {
      // `FontWeight.normal` aliases `w400`; the bare member name `"normal"` is
      // NOT in `FontWeight.values[].name`, so it would null the
      // `enumValue<FontWeight>` decoder (a silent drop). Canonicalise → `w400`.
      final r = translator.translate(
        await parseExpressionFromSourceForTest(
          '''
          import 'package:flutter/material.dart';
          Object x() => FontWeight.normal;
          ''',
          rootPackage: 'apps_examples',
        ),
      );
      expect(r.dsl, '"w400"');
      expect(r.issues, isEmpty);
    });

    test('resolved FontWeight.bold alias → canonical "w700"', () async {
      final r = translator.translate(
        await parseExpressionFromSourceForTest(
          '''
          import 'package:flutter/material.dart';
          Object x() => FontWeight.bold;
          ''',
          rootPackage: 'apps_examples',
        ),
      );
      expect(r.dsl, '"w700"');
      expect(r.issues, isEmpty);
    });

    test('TextAlign.center', () async {
      final r = translator.translate(
        await parseExpressionForTest('TextAlign.center'),
      );
      expect(r.dsl, '"center"');
    });

    test('every TextDecoration member lowers to its decoder name', () async {
      // The textDecoration decoder (rfw's `ArgumentDecoders`) decodes each of
      // the four static-const members by its bare name.
      for (final member in ['none', 'underline', 'overline', 'lineThrough']) {
        final r = translator.translate(
          await parseExpressionForTest('TextDecoration.$member'),
        );
        expect(r.dsl, '"$member"', reason: 'TextDecoration.$member');
      }
    });

    test('every supported curve member lowers to its decoder name', () async {
      // The per-member round-trip leg for `Curves`: the translator echoes each
      // supported curve name; combined with the curve-floor triangle
      // (validator-accept-set == kSupportedCurveNames == decoder-decode-set),
      // every supported curve round-trips. The one real-but-unsupported member
      // (`fastEaseInToSlowEaseOut`) is absent from this set — the classifier
      // crux e2e proves the custom-widget body path defers it.
      for (final member in kSupportedCurveNames) {
        final r = translator.translate(
          await parseExpressionForTest('Curves.$member'),
        );
        expect(r.dsl, '"$member"', reason: 'Curves.$member');
      }
    });

    test('real-flutter Colors.red → curated 0xAARRGGBB integer', () async {
      // Element-resolved to package:flutter → the curated table lowers it.
      final r = translator.translate(
        await parseExpressionFromSourceForTest(
          '''
          import 'package:flutter/material.dart';
          Object x() => Colors.red;
          ''',
          rootPackage: 'apps_examples',
        ),
      );
      expect(r.dsl, '0xFFF44336');
      expect(r.issues, isEmpty);
    });

    test('real-flutter Colors.transparent → 0x00000000', () async {
      final r = translator.translate(
        await parseExpressionFromSourceForTest(
          '''
          import 'package:flutter/material.dart';
          Object x() => Colors.transparent;
          ''',
          rootPackage: 'apps_examples',
        ),
      );
      expect(r.dsl, '0x00000000');
      expect(r.issues, isEmpty);
    });

    test(
        'real-flutter Colors.X outside the curated subset → diagnostic '
        '(expansion deferred, never silent-wrong)', () async {
      // `teal` is a real Material colour but not in the curated table; it
      // surfaces the supported-list diagnostic rather than silently lowering
      // (the broad-expansion is a named follow-up).
      final r = translator.translate(
        await parseExpressionFromSourceForTest(
          '''
          import 'package:flutter/material.dart';
          Object x() => Colors.teal;
          ''',
          rootPackage: 'apps_examples',
        ),
      );
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.unresolvedIdentifier),
      );
    });

    test(
        'a customer Colors lookalike (scalar int member) defers — never the '
        'material int (#2 silent-wrong closed)', () async {
      // `red` matches a curated Material name, but this is a CUSTOMER class
      // named `Colors`, not package:flutter's. The classifier's scalar-fold
      // promotes `Colors.red` to composable (the int const folds), so it
      // reaches the translator — which must NOT lower it against the hard-coded
      // Material table (that would emit 0xFFF44336 instead of the author's
      // 0xFF112233, a value-wrong blob the colour floor cannot catch). The
      // element-resolved arm defers a non-package:flutter prefix.
      final r = translator.translate(
        await parseExpressionFromSourceForTest('''
          class Colors {
            Colors._();
            static const int red = 0xFF112233;
          }
          Object x() => Colors.red;
        '''),
      );
      expect(r.dsl, isNot('0xFFF44336'));
      expect(r.issues, isNotEmpty);
    });

    test(
        'a customer Colors lookalike (Color-object member) defers — the '
        'translator-direct object-path negative', () async {
      final r = translator.translate(
        await parseExpressionFromSourceForTest('''
          class Color { const Color(this.value); final int value; }
          class Colors {
            Colors._();
            static const Color brand = Color(0xFF112233);
          }
          Object x() => Colors.brand;
        '''),
      );
      expect(r.issues, isNotEmpty);
      expect(r.dsl, isEmpty);
    });

    test('an unresolved Colors.X prefix defers (never name-match on null)',
        () async {
      // parseExpressionForTest produces an unresolved AST; the element-resolved
      // arm must defer rather than name-match against the Material table.
      final r = translator.translate(
        await parseExpressionForTest('Colors.red'),
      );
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.unresolvedIdentifier),
      );
      expect(r.dsl, isEmpty);
    });

    test('method call on unknown target emits unrecognizedMethodCall',
        () async {
      final r = translator.translate(
        await parseExpressionForTest('someVar.toUpper()'),
      );
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.unrecognizedMethodCall),
      );
    });
  });

  group('enumValue slot fallback', () {
    final enumSlotTranslator = ExpressionTranslator(
      catalog: _textAlignCatalog(),
      helpers: HelperRegistry(),
    );

    test('valid framework enum member lowers by name for an enumValue slot',
        () async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/widgets.dart';

        Object x() => Text('hi', textAlign: TextAlign.center);
        ''',
        rootPackage: 'apps_examples',
      );

      final r = enumSlotTranslator.translate(expr);

      expect(r.issues, isEmpty);
      expect(r.dsl, 'Text(text: "hi", textAlign: "center")');
    });

    test('absent enum member defers at the enumValue slot', () async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/widgets.dart';

        Object x() => Text('hi', textAlign: TextAlign.sideways);
        ''',
        rootPackage: 'apps_examples',
      );

      final r = enumSlotTranslator.translate(expr);

      expect(r.dsl, isEmpty);
      expect(
        r.issues.map((issue) => issue.code),
        contains(IssueCode.unresolvedIdentifier),
      );
      expect(
        r.issues.map((issue) => issue.message).join('\n'),
        allOf(contains('TextAlign.sideways'), contains('textAlign')),
      );
    });

    test('user-defined enum look-alike defers at the enumValue slot', () async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/widgets.dart' hide TextAlign;

        enum TextAlign { center }

        Object x() => Text('hi', textAlign: TextAlign.center);
        ''',
        rootPackage: 'apps_examples',
      );

      final r = enumSlotTranslator.translate(expr);

      expect(r.dsl, isEmpty);
      expect(
        r.issues.map((issue) => issue.code),
        contains(IssueCode.unresolvedIdentifier),
      );
      expect(
        r.issues.map((issue) => issue.message).join('\n'),
        allOf(contains('TextAlign.center'), contains('textAlign')),
      );
    });
  });

  group('PageView -> RestagePager alias', () {
    final pagerTranslator = ExpressionTranslator(
      catalog: _pagerCatalog(),
      helpers: HelperRegistry(),
    );

    Future<TranslationResult> alias(String body) async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/material.dart';

        int get dynamicPage => 2;
        PageController makeController() => PageController();

        Object x() => $body;
        ''',
        rootPackage: 'apps_examples',
      );
      return pagerTranslator.translate(expr);
    }

    test('children-only PageView lowers to a RestagePager node', () async {
      final r = await alias('PageView(children: const [SizedBox()])');
      expect(r.issues.where((i) => !i.code.isInformational), isEmpty);
      expect(r.dsl, 'RestagePager(children: [SizedBox()])');
    });

    test('scrollDirection / pageSnapping carry by name', () async {
      final r = await alias(
        'PageView(children: const [SizedBox()], '
        'scrollDirection: Axis.vertical, pageSnapping: false)',
      );
      expect(r.issues.where((i) => !i.code.isInformational), isEmpty);
      expect(r.dsl, contains('scrollDirection: "vertical"'));
      expect(r.dsl, contains('pageSnapping: false'));
    });

    test('a key argument is ignored, not a defer trigger', () async {
      final r = await alias(
        "PageView(key: const ValueKey('p'), children: const [SizedBox()])",
      );
      expect(r.issues.where((i) => !i.code.isInformational), isEmpty);
      expect(r.dsl, 'RestagePager(children: [SizedBox()])');
      expect(r.dsl, isNot(contains('key')));
    });

    test('PageController(initialPage:, viewportFraction:) flattens onto props',
        () async {
      final r = await alias(
        'PageView('
        'controller: PageController(initialPage: 2, viewportFraction: 0.9), '
        'children: const [SizedBox()])',
      );
      expect(r.issues.where((i) => !i.code.isInformational), isEmpty);
      expect(r.dsl, contains('initialPage: 2'));
      expect(r.dsl, contains('viewportFraction: 0.9'));
    });

    test('PageController() with no args flattens to RestagePager defaults',
        () async {
      final r = await alias(
        'PageView(controller: PageController(), children: const [SizedBox()])',
      );
      expect(r.issues.where((i) => !i.code.isInformational), isEmpty);
      // No initialPage/viewportFraction emitted — RestagePager's defaults
      // equal PageController's, so the lowering is faithful.
      expect(r.dsl, 'RestagePager(children: [SizedBox()])');
    });

    test('an unmapped argument defers the whole widget, named', () async {
      final r = await alias(
        'PageView(physics: const NeverScrollableScrollPhysics(), '
        'children: const [SizedBox()])',
      );
      expect(r.dsl, isEmpty);
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.pageViewFormUnsupported),
      );
      expect(
        r.issues.map((i) => i.message).join('\n'),
        contains('physics'),
      );
    });

    test('PageView.builder defers (children-list form only)', () async {
      final r = await alias(
        'PageView.builder(itemCount: 3, '
        'itemBuilder: (context, index) => const SizedBox())',
      );
      expect(r.dsl, isEmpty);
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.pageViewFormUnsupported),
      );
    });

    test('a PageController arg outside {initialPage, viewportFraction} defers',
        () async {
      final r = await alias(
        'PageView('
        'controller: PageController(initialPage: 2, keepPage: false), '
        'children: const [SizedBox()])',
      );
      expect(r.dsl, isEmpty);
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.pageViewFormUnsupported),
      );
      expect(
        r.issues.map((i) => i.message).join('\n'),
        contains('controller'),
      );
    });

    test('a controller that is not a literal PageController defers', () async {
      final r = await alias(
        'PageView(controller: makeController(), children: const [SizedBox()])',
      );
      expect(r.dsl, isEmpty);
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.pageViewFormUnsupported),
      );
    });

    test('a non-statically-extractable flatten value defers the whole widget',
        () async {
      // The flatten arg routes through the integer slot translation; a value
      // that looks extractable but is a runtime reference defers — never a
      // RestagePager with a degraded initialPage.
      final r = await alias(
        'PageView('
        'controller: PageController(initialPage: dynamicPage), '
        'children: const [SizedBox()])',
      );
      expect(r.dsl, isEmpty);
      expect(r.issues.where((i) => !i.code.isInformational), isNotEmpty);
      expect(r.dsl, isNot(contains('RestagePager')));
    });

    test('an empty children list defers (RestagePager requires non-empty)',
        () async {
      final r = await alias('PageView(children: const [])');
      expect(r.dsl, isEmpty);
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.pageViewFormUnsupported),
      );
    });

    test('an absent children list defers', () async {
      final r = await alias('PageView(scrollDirection: Axis.horizontal)');
      expect(r.dsl, isEmpty);
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.pageViewFormUnsupported),
      );
    });

    test('a customer PageView look-alike does NOT alias (unknownWidget)',
        () async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        class PageView {
          const PageView({this.children});
          final List<Object>? children;
        }
        Object x() => const PageView(children: []);
        ''',
      );
      final r = pagerTranslator.translate(expr);
      expect(r.dsl, isEmpty);
      expect(r.issues.map((i) => i.code), contains(IssueCode.unknownWidget));
      expect(
        r.issues.map((i) => i.code),
        isNot(contains(IssueCode.pageViewFormUnsupported)),
      );
    });
  });

  group('DraggableScrollableSheet -> RestageDraggableSheet alias', () {
    final sheetTranslator = ExpressionTranslator(
      catalog: _draggableSheetCatalog(),
      helpers: HelperRegistry(),
    );

    Future<TranslationResult> alias(String body) async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/material.dart';

        ScrollController makeController() => ScrollController();

        Object x() => $body;
        ''',
        rootPackage: 'apps_examples',
      );
      return sheetTranslator.translate(expr);
    }

    test('the canonical builder lowers to a RestageDraggableSheet node',
        timeout: const Timeout(Duration(minutes: 3)), () async {
      // The first Flutter-resolution build in this group is slow on a cold
      // cache; the rest run warm under the default per-test timeout.
      final r = await alias(
        'DraggableScrollableSheet(builder: (context, sc) => '
        'SingleChildScrollView(controller: sc, child: const SizedBox()))',
      );
      expect(r.issues.where((i) => !i.code.isInformational), isEmpty);
      expect(r.dsl, 'RestageDraggableSheet(child: SizedBox())');
    });

    test('detents map by name onto the catalog slots in catalog order',
        () async {
      final r = await alias(
        'DraggableScrollableSheet(initialChildSize: 0.3, minChildSize: 0.1, '
        'maxChildSize: 0.9, expand: false, snap: true, '
        'builder: (context, sc) => '
        'SingleChildScrollView(controller: sc, child: const SizedBox()))',
      );
      expect(r.issues.where((i) => !i.code.isInformational), isEmpty);
      expect(
        r.dsl,
        'RestageDraggableSheet(child: SizedBox(), initialChildSize: 0.3, '
        'minChildSize: 0.1, maxChildSize: 0.9, expand: false, snap: true)',
      );
    });

    test('a customer DraggableScrollableSheet look-alike does NOT alias',
        () async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        class DraggableScrollableSheet {
          const DraggableScrollableSheet({this.builder});
          final Object? builder;
        }
        Object x() => const DraggableScrollableSheet();
        ''',
      );
      final r = sheetTranslator.translate(expr);
      expect(r.dsl, isEmpty);
      expect(r.issues.map((i) => i.code), contains(IssueCode.unknownWidget));
      expect(
        r.issues.map((i) => i.code),
        isNot(contains(IssueCode.draggableSheetFormUnsupported)),
      );
    });

    test('a non-empty snapSizes fatal-defers the whole widget', () async {
      final r = await alias(
        'DraggableScrollableSheet(snapSizes: const [0.5], '
        'builder: (context, sc) => '
        'SingleChildScrollView(controller: sc, child: const SizedBox()))',
      );
      expect(r.dsl, isEmpty);
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.draggableSheetFormUnsupported),
      );
    });

    test('an empty snapSizes is dropped (the widget still lowers)', () async {
      final r = await alias(
        'DraggableScrollableSheet(snapSizes: const [], '
        'builder: (context, sc) => '
        'SingleChildScrollView(controller: sc, child: const SizedBox()))',
      );
      expect(r.issues.where((i) => !i.code.isInformational), isEmpty);
      expect(r.dsl, 'RestageDraggableSheet(child: SizedBox())');
    });

    test('an author-supplied controller fatal-defers', () async {
      final r = await alias(
        'DraggableScrollableSheet(controller: makeController(), '
        'builder: (context, sc) => '
        'SingleChildScrollView(controller: sc, child: const SizedBox()))',
      );
      expect(r.dsl, isEmpty);
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.draggableSheetFormUnsupported),
      );
    });

    test('shouldCloseOnMinExtent: true fatal-defers (a closeable sheet)',
        () async {
      final r = await alias(
        'DraggableScrollableSheet(shouldCloseOnMinExtent: true, '
        'builder: (context, sc) => '
        'SingleChildScrollView(controller: sc, child: const SizedBox()))',
      );
      expect(r.dsl, isEmpty);
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.draggableSheetFormUnsupported),
      );
    });

    test('shouldCloseOnMinExtent: false is dropped (the widget lowers)',
        () async {
      final r = await alias(
        'DraggableScrollableSheet(shouldCloseOnMinExtent: false, '
        'builder: (context, sc) => '
        'SingleChildScrollView(controller: sc, child: const SizedBox()))',
      );
      expect(r.issues.where((i) => !i.code.isInformational), isEmpty);
      expect(r.dsl, 'RestageDraggableSheet(child: SizedBox())');
    });

    test(
        'a scrollable builder body fatal-defers (the silent-wrong-render '
        'tripwire — never a bare Column)', () async {
      final r = await alias(
        'DraggableScrollableSheet(builder: (context, sc) => '
        'ListView(controller: sc, children: const [SizedBox()]))',
      );
      expect(r.dsl, isEmpty);
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.draggableSheetFormUnsupported),
      );
    });

    test(
        'a scroll view carrying an extra argument fatal-defers (the strict '
        'subset tripwire)', () async {
      final r = await alias(
        'DraggableScrollableSheet(builder: (context, sc) => '
        'SingleChildScrollView(controller: sc, '
        'padding: EdgeInsets.zero, child: const SizedBox()))',
      );
      expect(r.dsl, isEmpty);
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.draggableSheetFormUnsupported),
      );
    });

    test('the .builder named constructor fatal-defers', () async {
      final r = await alias(
        'DraggableScrollableSheet(builder: (context, sc) => '
        'const SizedBox())',
      );
      expect(r.dsl, isEmpty);
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.draggableSheetFormUnsupported),
      );
    });

    test(
        'a resolved customer SingleChildScrollView function does NOT alias '
        'as the canonical scroll view (fatal-defers)', () async {
      // A paywall that hides Flutter's SingleChildScrollView and defines its
      // own same-named function must not be mis-recognised as the canonical
      // scroll view — its body renders differently (the controller-thread
      // proof is only faithful for the REAL Flutter scroll view).
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/material.dart' hide SingleChildScrollView;

        Widget SingleChildScrollView({
          Key? key,
          ScrollController? controller,
          Widget? child,
        }) =>
            Padding(padding: EdgeInsets.zero, child: child);

        Object x() => DraggableScrollableSheet(
          builder: (context, sc) =>
              SingleChildScrollView(controller: sc, child: const SizedBox()),
        );
        ''',
        rootPackage: 'apps_examples',
      );
      final r = sheetTranslator.translate(expr);
      expect(r.dsl, isEmpty);
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.draggableSheetFormUnsupported),
      );
    });
  });

  group('DraggableScrollableSheet alias catalog-shape skew guard', () {
    Future<TranslationResult> aliasWith(Catalog catalog) async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/material.dart';

        Object x() => DraggableScrollableSheet(builder: (context, sc) =>
          SingleChildScrollView(controller: sc, child: const SizedBox()));
        ''',
        rootPackage: 'apps_examples',
      );
      return ExpressionTranslator(catalog: catalog, helpers: HelperRegistry())
          .translate(expr);
    }

    test('a catalog whose RestageDraggableSheet lacks the child slot is fatal',
        () async {
      final r = await aliasWith(_draggableSheetCatalog(includeChild: false));
      expect(r.dsl, isEmpty);
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.draggableSheetFormUnsupported),
      );
    });

    test('a catalog exposing an author-bindable controller slot is fatal',
        () async {
      final r =
          await aliasWith(_draggableSheetCatalog(includeController: true));
      expect(r.dsl, isEmpty);
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.draggableSheetFormUnsupported),
      );
    });

    test(
        'a catalog missing a mapped slot fatal-defers rather than silently '
        'drop the authored value', () async {
      // A skewed catalog without `initialChildSize`: the authored 0.3 has no
      // slot to emit onto, so the lowering must fatal-defer rather than emit a
      // sheet that decodes to the runtime default.
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/material.dart';

        Object x() => DraggableScrollableSheet(
          initialChildSize: 0.3,
          builder: (context, sc) =>
              SingleChildScrollView(controller: sc, child: const SizedBox()),
        );
        ''',
        rootPackage: 'apps_examples',
      );
      final r = ExpressionTranslator(
        catalog: _draggableSheetCatalog(includeInitialChildSize: false),
        helpers: HelperRegistry(),
      ).translate(expr);
      expect(r.dsl, isEmpty);
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.draggableSheetFormUnsupported),
      );
    });
  });

  group('RadioGroup / DropdownButton -> single-select alias', () {
    final selectTranslator = ExpressionTranslator(
      catalog: _singleSelectCatalog(),
      helpers: HelperRegistry(),
    );

    Future<TranslationResult> alias(String body) async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/material.dart';

        const String? sel = 'a';
        Object x() => $body;
        ''',
        rootPackage: 'apps_examples',
      );
      return selectTranslator.translate(expr);
    }

    test(
        'a RadioGroup lowers to a RestageRadioGroupString node with its '
        'option list in order + the flattened selected', () async {
      final r = await alias('''
RadioGroup<String>(
  groupValue: 'b',
  child: Column(children: const [
    RadioListTile<String>(value: 'a', title: Text('First')),
    RadioListTile<String>(value: 'b', title: Text('Second')),
  ]),
)
''');
      expect(r.issues.where((i) => !i.code.isInformational), isEmpty);
      // Exact equality (not `contains`): the option list must carry both
      // options in source order with no reorder/drop, and `selected` flattens.
      final items = _optionListDsl([('a', 'First'), ('b', 'Second')]);
      expect(
        r.dsl,
        'RestageRadioGroupString(items: $items, selected: "b")',
      );
    });

    test(
        'a DropdownButton lowers to a RestageDropdownString node with its '
        'option list', () async {
      final r = await alias('''
DropdownButton<String>(
  value: 'usd',
  items: const [
    DropdownMenuItem<String>(value: 'usd', child: Text('US Dollar')),
    DropdownMenuItem<String>(value: 'eur', child: Text('Euro')),
  ],
)
''');
      expect(r.issues.where((i) => !i.code.isInformational), isEmpty);
      final items = _optionListDsl([('usd', 'US Dollar'), ('eur', 'Euro')]);
      expect(
        r.dsl,
        'RestageDropdownString(items: $items, selected: "usd")',
      );
    });

    test('an unselected group (no groupValue) omits the selected slot',
        () async {
      final r = await alias('''
RadioGroup<String>(
  child: Column(children: const [
    RadioListTile<String>(value: 'a', title: Text('A')),
  ]),
)
''');
      expect(r.issues.where((i) => !i.code.isInformational), isEmpty);
      expect(
        r.dsl,
        'RestageRadioGroupString(items: [{ value: "a", label: "A" }])',
      );
      expect(r.dsl, isNot(contains('selected')));
    });

    test('a non-carrier leaf defers the whole widget, named', () async {
      final r = await alias('''
RadioGroup<String>(
  groupValue: 'a',
  child: Column(children: const [
    RadioListTile<String>(value: 'a', title: Text('A')),
    Radio<String>(value: 'b'),
  ]),
)
''');
      expect(r.dsl, isEmpty);
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.singleSelectFormUnsupported),
      );
      expect(
        r.issues.map((i) => i.message).join('\n'),
        contains('RadioListTile'),
      );
    });

    test('a duplicate static option value defers, named', () async {
      final r = await alias('''
DropdownButton<String>(
  value: 'a',
  items: const [
    DropdownMenuItem<String>(value: 'a', child: Text('A')),
    DropdownMenuItem<String>(value: 'a', child: Text('A2')),
  ],
)
''');
      expect(r.dsl, isEmpty);
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.singleSelectFormUnsupported),
      );
      expect(
        r.issues.map((i) => i.message).join('\n'),
        contains('duplicate'),
      );
    });

    test(
        'two const refs folding to the same value defer (post-fold dup), named',
        () async {
      // `proKey` and `alsoPro` are distinct identifiers that const-fold to the
      // same string. The recogniser's raw-literal dup check does not catch them
      // (they are not SimpleStringLiterals), but the emitter re-checks the
      // FOLDED value and defers loud — otherwise the compiled widget would
      // silently de-dupe (drop) the second option, shipping a wrong group.
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/material.dart';

        const String proKey = 'pro';
        const String alsoPro = 'pro';
        Object x() => DropdownButton<String>(
          value: 'pro',
          items: const [
            DropdownMenuItem<String>(value: proKey, child: Text('Pro')),
            DropdownMenuItem<String>(value: alsoPro, child: Text('Pro 2')),
          ],
        );
        ''',
        rootPackage: 'apps_examples',
      );
      final r = selectTranslator.translate(expr);
      expect(r.dsl, isEmpty);
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.singleSelectFormUnsupported),
      );
      expect(
        r.issues.map((i) => i.message).join('\n'),
        contains('same value'),
      );
    });

    // A single-select translator that ALSO knows a host-data helper, so an
    // option `value:` can lower to a runtime reference (`paywallPriceFor(...)`
    // → `data.products.<id>.localizedPrice`) rather than a folded string
    // literal. The duplicate-value gate must catch two IDENTICAL runtime refs
    // (not only string literals); two DISTINCT runtime refs are left to the
    // runtime de-dupe. The helper is registered under the `apps_examples`
    // origin — the package the single-select fixtures mount under (they need
    // real `package:flutter` resolution), so its call resolves to that origin.
    final selectWithHelpers = ExpressionTranslator(
      catalog: _singleSelectCatalog(),
      helpers: HelperRegistry()
        ..registerAll([
          HelperDefinition(
            name: 'paywallPriceFor',
            libraryOrigin: 'package:apps_examples',
            returnCategory: HelperReturnCategory.string,
            translate: (args) {
              final slot = _stripTestQuotes(args.named['slot']!);
              return 'data.products.$slot.localizedPrice';
            },
          ),
        ]),
    );

    Future<TranslationResult> aliasWithHelpers(String body) async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/material.dart';

        String paywallPriceFor({String? slot, String? productId}) => "";
        Object x() => $body;
        ''',
        rootPackage: 'apps_examples',
      );
      return selectWithHelpers.translate(expr);
    }

    test(
        'two options with the SAME runtime-ref value defer (post-lower dup), '
        'named', () async {
      // Both options' `value:` lower to the IDENTICAL runtime ref
      // `data.products.pro.localizedPrice`. The recogniser's raw-literal dup
      // check does not see them (they are not SimpleStringLiterals), and the
      // OLD emitter gate only deduped string literals — leaving this exact
      // duplicate to the compiled widget, which would silently de-dupe (drop)
      // the second option. The emitter must defer the WHOLE group loud.
      final r = await aliasWithHelpers('''
DropdownButton<String>(
  value: 'pro',
  items: [
    DropdownMenuItem<String>(
      value: paywallPriceFor(slot: "pro"), child: Text('Pro')),
    DropdownMenuItem<String>(
      value: paywallPriceFor(slot: "pro"), child: Text('Pro 2')),
  ],
)
''');
      expect(r.dsl, isEmpty);
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.singleSelectFormUnsupported),
      );
      expect(
        r.issues.map((i) => i.message).join('\n'),
        contains('same value'),
      );
    });

    test(
        'two options with DISTINCT runtime-ref values still emit (not '
        'over-deferred)', () async {
      // The two `value:` expressions lower to DIFFERENT runtime refs
      // (`data.products.pro...` vs `data.products.plus...`). Distinct DSL is
      // not a duplicate — the group emits both options; a genuine runtime
      // collision (if any) is the runtime's job, not a build-time defer.
      final r = await aliasWithHelpers('''
DropdownButton<String>(
  items: [
    DropdownMenuItem<String>(
      value: paywallPriceFor(slot: "pro"), child: Text('Pro')),
    DropdownMenuItem<String>(
      value: paywallPriceFor(slot: "plus"), child: Text('Plus')),
  ],
)
''');
      expect(r.issues.where((i) => !i.code.isInformational), isEmpty);
      const proItem =
          '{ value: data.products.pro.localizedPrice, label: "Pro" }';
      const plusItem =
          '{ value: data.products.plus.localizedPrice, label: "Plus" }';
      expect(
        r.dsl,
        'RestageDropdownString(items: [$proItem, $plusItem])',
      );
    });

    test('an unmapped RadioGroup argument defers the whole widget, named',
        () async {
      final r = await alias('''
RadioGroup<String>(
  groupValue: 'a',
  mouseCursor: SystemMouseCursors.click,
  child: Column(children: const [
    RadioListTile<String>(value: 'a', title: Text('A')),
  ]),
)
''');
      expect(r.dsl, isEmpty);
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.singleSelectFormUnsupported),
      );
      expect(
        r.issues.map((i) => i.message).join('\n'),
        contains('mouseCursor'),
      );
    });

    test('a customer RadioGroup look-alike does NOT alias (unknownWidget)',
        () async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        class RadioGroup<T> {
          const RadioGroup({this.groupValue, this.child});
          final T? groupValue;
          final Object? child;
        }
        Object x() => const RadioGroup<String>(groupValue: 'a', child: null);
        ''',
      );
      final r = selectTranslator.translate(expr);
      expect(r.dsl, isEmpty);
      expect(r.issues.map((i) => i.code), contains(IssueCode.unknownWidget));
      expect(
        r.issues.map((i) => i.code),
        isNot(contains(IssueCode.singleSelectFormUnsupported)),
      );
    });
  });

  group('ToggleButtons -> RestageToggleButtons alias', () {
    final toggleTranslator = ExpressionTranslator(
      catalog: _toggleButtonsCatalog(),
      helpers: HelperRegistry(),
    );

    Future<TranslationResult> alias(String body) async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/material.dart';

        final List<bool> flags = const [true, false];
        Object x() => $body;
        ''',
        rootPackage: 'apps_examples',
      );
      return toggleTranslator.translate(expr);
    }

    test(
        'a ToggleButtons lowers to a RestageToggleButtons node with its '
        'children + isSelected in order', () async {
      final r = await alias('''
ToggleButtons(
  isSelected: const [true, false, true],
  children: const [Text('Bold'), Text('Italic'), Text('Underline')],
)
''');
      expect(r.issues.where((i) => !i.code.isInformational), isEmpty);
      // Exact equality (not `contains`): the children and the parallel
      // isSelected flags must carry in source order with no reorder/drop, and
      // the per-index pairing between the two lists must be preserved.
      expect(
        r.dsl,
        'RestageToggleButtons(children: '
        '[Text(text: "Bold"), Text(text: "Italic"), Text(text: "Underline")], '
        'isSelected: [true, false, true])',
      );
    });

    test('a display-only ToggleButtons (no onPressed) lowers cleanly',
        () async {
      final r = await alias('''
ToggleButtons(
  isSelected: const [true, false],
  children: const [Text('A'), Text('B')],
)
''');
      expect(r.issues.where((i) => !i.code.isInformational), isEmpty);
      expect(
        r.dsl,
        'RestageToggleButtons(children: [Text(text: "A"), Text(text: "B")], '
        'isSelected: [true, false])',
      );
      // No onPressed authored → no onPressed part emitted (not a defer).
      expect(r.dsl, isNot(contains('onPressed')));
    });

    test('a literal children/isSelected length mismatch defers loud', () async {
      final r = await alias('''
ToggleButtons(
  isSelected: const [true, false],
  children: const [Text('A'), Text('B'), Text('C')],
)
''');
      expect(r.dsl, isEmpty);
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.toggleButtonsFormUnsupported),
      );
    });

    test('a dynamic isSelected defers loud (never a partial set)', () async {
      final r = await alias('''
ToggleButtons(
  isSelected: flags,
  children: const [Text('A'), Text('B')],
)
''');
      expect(r.dsl, isEmpty);
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.toggleButtonsFormUnsupported),
      );
    });
  });

  group('SegmentedButton -> RestageSegmentedButton alias', () {
    // The paywall helpers are registered so a declarative `paywallEvent(...)`
    // in the onSelectionChanged closure lowers exactly as the production build
    // recognises it (a host-imperative closure cannot lower — only the
    // declarative event form does, the same contract as every catalog event).
    final segmentedTranslator = ExpressionTranslator(
      catalog: _segmentedButtonCatalog(),
      helpers: HelperRegistry()..registerAll(paywallHelpers),
    );

    Future<TranslationResult> alias(String body) async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/material.dart';

        final Set<String> sel = const {'a'};
        void someHostCall(Set<String> s) {}
        Object x() => $body;
        ''',
        rootPackage: 'apps_examples',
      );
      return segmentedTranslator.translate(expr);
    }

    test(
        'a SegmentedButton lowers to a RestageSegmentedButtonString node with '
        'its segment list in order + the selected list', () async {
      final r = await alias('''
SegmentedButton<String>(
  segments: const [
    ButtonSegment<String>(value: 'day', label: Text('Day')),
    ButtonSegment<String>(value: 'week', label: Text('Week')),
  ],
  selected: const {'week'},
)
''');
      expect(r.issues.where((i) => !i.code.isInformational), isEmpty);
      // Exact equality (not `contains`): the segments must carry in source
      // order with no reorder/drop, and `selected` is a string list.
      final items = _optionListDsl([('day', 'Day'), ('week', 'Week')]);
      expect(
        r.dsl,
        'RestageSegmentedButtonString(items: $items, selected: ["week"])',
      );
    });

    test(
        'a declarative onSelectionChanged lowers through the event slot to an '
        'event reference', () async {
      // The host callback shape (`(Set<String> s)`) is irrelevant to the blob —
      // only the declarative body lowers, to an `event "…"` reference the host
      // wires its real `ValueChanged<Set<String>>` to. An arbitrary host
      // closure defers, exactly like every other catalog event.
      final r = await alias('''
SegmentedButton<String>(
  segments: const [
    ButtonSegment<String>(value: 'a', label: Text('A')),
  ],
  selected: const {'a'},
  onSelectionChanged: (Set<String> s) => paywallEvent('tierChanged'),
)
''');
      expect(r.issues.where((i) => !i.code.isInformational), isEmpty);
      expect(r.dsl, contains('onChanged: event "tierChanged"'));
    });

    test('the declarative bools lower into the blob', () async {
      final r = await alias('''
SegmentedButton<String>(
  segments: const [
    ButtonSegment<String>(value: 'a', label: Text('A')),
    ButtonSegment<String>(value: 'b', label: Text('B')),
  ],
  selected: const {'a', 'b'},
  multiSelectionEnabled: true,
  emptySelectionAllowed: true,
)
''');
      expect(r.issues.where((i) => !i.code.isInformational), isEmpty);
      expect(r.dsl, contains('multiSelectionEnabled: true'));
      expect(r.dsl, contains('emptySelectionAllowed: true'));
    });

    test(
        'a display-only SegmentedButton (no selected/onSelectionChanged) '
        'lowers cleanly', () async {
      final r = await alias('''
SegmentedButton<String>(
  segments: const [
    ButtonSegment<String>(value: 'a', label: Text('A')),
  ],
)
''');
      expect(r.issues.where((i) => !i.code.isInformational), isEmpty);
      final items = _optionListDsl([('a', 'A')]);
      expect(r.dsl, 'RestageSegmentedButtonString(items: $items)');
    });

    test('a non-String generic defers loud', () async {
      final r = await alias('''
SegmentedButton<int>(
  segments: const [
    ButtonSegment<int>(value: 1, label: Text('One')),
  ],
  selected: const {1},
)
''');
      expect(r.dsl, isEmpty);
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.segmentedButtonFormUnsupported),
      );
    });

    test('a duplicate segment value defers loud (never a dropped segment)',
        () async {
      final r = await alias('''
SegmentedButton<String>(
  segments: const [
    ButtonSegment<String>(value: 'a', label: Text('A')),
    ButtonSegment<String>(value: 'a', label: Text('Again')),
  ],
  selected: const {'a'},
)
''');
      expect(r.dsl, isEmpty);
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.segmentedButtonFormUnsupported),
      );
    });

    test(
        'a host-imperative onSelectionChanged body defers loud at the event '
        'slot (never silently dropped)', () async {
      // `someHostCall(s)` is not a declarative event — the unwrapped body
      // reaches the event slot and defers loud, so the WHOLE widget aborts
      // rather than ship a segmented button with a silently-dropped callback.
      final r = await alias('''
SegmentedButton<String>(
  segments: const [
    ButtonSegment<String>(value: 'a', label: Text('A')),
  ],
  selected: const {'a'},
  onSelectionChanged: (Set<String> s) => someHostCall(s),
)
''');
      expect(r.dsl, isEmpty);
      expect(r.issues, isNotEmpty);
    });
  });

  group('const icon resolution', () {
    test('real-flutter Icons.X resolves to its integer codepoint', () async {
      // Element-resolved to package:flutter → the icon arm reads the real
      // const codepoint. The exact value is version-stable but not asserted
      // (avoids brittleness); only that it resolves to a bare integer.
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/material.dart';
        Object x() => Icons.star;
        ''',
        rootPackage: 'apps_examples',
      );
      final r = translator.translate(expr);
      expect(r.issues, isEmpty);
      expect(r.dsl, matches(RegExp(r'^\d+$')));
    });

    test('real-flutter CupertinoIcons.X resolves to its integer codepoint',
        () async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/cupertino.dart';
        Object x() => CupertinoIcons.heart_fill;
        ''',
        rootPackage: 'apps_examples',
      );
      final r = translator.translate(expr);
      expect(r.issues, isEmpty);
      expect(r.dsl, matches(RegExp(r'^\d+$')));
    });

    test('a customer Icons lookalike (not package:flutter) defers', () async {
      // The icon arm reads the real codepoint, so a customer `Icons` is not a
      // silent-wrong vector — but the arm is still gated to package:flutter for
      // uniformity (no name-only Colors/Icons path survives anywhere).
      final r = translator.translate(
        await parseExpressionFromSourceForTest('''
          class IconData {
            const IconData(this.codePoint);
            final int codePoint;
          }
          class Icons {
            Icons._();
            static const IconData star = IconData(99999);
          }
          Object x() => Icons.star;
        '''),
      );
      expect(r.issues, isNotEmpty);
      expect(r.dsl, isEmpty);
    });

    test('unresolved Icons.X surfaces unresolvedIdentifier with empty dsl',
        () async {
      // parseExpressionForTest produces an unresolved AST, so the
      // analyzer never populates the identifier's element and the
      // translator must surface a diagnostic rather than fall through.
      // The empty-string sentinel matches the translator's convention
      // for issue-emitting paths — callers gate on `issues.isNotEmpty`
      // and never read the dsl, and a future caller that does will fail
      // the downstream `parseLibraryFile` step loudly instead of
      // emitting a zero codepoint that the rfw decoder would accept.
      final r = translator.translate(
        await parseExpressionForTest('Icons.bolt_rounded'),
      );
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.unresolvedIdentifier),
      );
      expect(r.dsl, isEmpty);
    });
  });

  // The translator's name-based structured-value recognition (EdgeInsets /
  // BorderRadius / Color / Locale / Alignment / Duration / Offset / gradients
  // …) must lower ONLY the real framework type. A resolved CUSTOMER class whose
  // name collides with a framework value type would otherwise be lowered as the
  // framework value — a value-wrong blob the type-aware floor cannot catch (any
  // structurally-valid value passes). Each negative proves the resolved
  // production hole is closed (defers, no mis-emit); each positive proves the
  // real framework type still lowers. The framework value types span three
  // origin libraries — `package:flutter/` (EdgeInsets / BorderRadius /
  // Alignment), `dart:ui` (Color / Locale / Offset), and `dart:core`
  // (Duration) — so the gate accepts `dart:` and `package:flutter/`.
  group('framework value-type look-alike defers (value-substitution sweep)',
      () {
    // -- EdgeInsets (package:flutter/) — InstanceCreation factory --
    test('a customer EdgeInsets.all look-alike defers (no [8,8,8,8])',
        () async {
      final r = translator.translate(
        await parseExpressionFromSourceForTest('''
        class EdgeInsets {
          const EdgeInsets.all(this.value);
          final double value;
        }
        Object x() => const EdgeInsets.all(8);
      '''),
      );
      // A clean defer — nothing emitted, routed to widget construction which
      // reports the resolved customer class is not a known widget. NOT the
      // framework value `[8,8,8,8]` (which `isEmpty` also rules out).
      expect(r.dsl, isEmpty);
      expect(r.issues.map((i) => i.code), contains(IssueCode.unknownWidget));
    });
    test('real-flutter EdgeInsets.all still lowers', () async {
      final r = translator.translate(
        await parseExpressionFromSourceForTest(
          '''
          import 'package:flutter/widgets.dart';
          Object x() => const EdgeInsets.all(8);
          ''',
          rootPackage: 'apps_examples',
        ),
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, '[8.0, 8.0, 8.0, 8.0]');
    });

    // -- BorderRadius (package:flutter/) — InstanceCreation factory --
    test('a customer BorderRadius.circular look-alike defers', () async {
      final r = translator.translate(
        await parseExpressionFromSourceForTest('''
        class BorderRadius {
          const BorderRadius.circular(this.radius);
          final double radius;
        }
        Object x() => const BorderRadius.circular(8);
      '''),
      );
      expect(r.dsl, isEmpty);
      expect(r.issues.map((i) => i.code), contains(IssueCode.unknownWidget));
    });

    // -- Color (dart:ui) — InstanceCreation + recipe-dispatched --
    test('a customer Color look-alike defers (no packed int)', () async {
      final r = translator.translate(
        await parseExpressionFromSourceForTest('''
        class Color {
          const Color(this.value);
          final int value;
        }
        Object x() => const Color(0xFF112233);
      '''),
      );
      expect(r.dsl, isEmpty);
      expect(r.issues.map((i) => i.code), contains(IssueCode.unknownWidget));
    });
    test('real-flutter Color still lowers', () async {
      final r = translator.translate(
        await parseExpressionFromSourceForTest(
          '''
          import 'package:flutter/material.dart';
          Object x() => const Color(0xFF112233);
          ''',
          rootPackage: 'apps_examples',
        ),
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, '0xFF112233');
    });

    // -- FontWeight (dart:ui) — PrefixedIdentifier enum-like-const --
    test(
        'a customer FontWeight look-alike defers — never the framework weight '
        'name (the coincidental-canonical value-substitution)', () async {
      // `w600` matches a canonical framework weight, so the validator backstop
      // cannot catch it — only the element gate can. A customer class named
      // `FontWeight` must defer, not lower to `"w600"` (which the
      // `enumValue<FontWeight>` decoder would resolve to the REAL framework
      // weight — a value-substitution silent-wrong for the author's own type).
      final r = translator.translate(
        await parseExpressionFromSourceForTest('''
        class FontWeight {
          const FontWeight._();
          static const FontWeight w600 = FontWeight._();
        }
        Object x() => FontWeight.w600;
      '''),
      );
      expect(r.dsl, isNot(contains('w600')));
      expect(r.issues, isNotEmpty);
    });

    // -- TextDecoration (dart:ui) — PrefixedIdentifier enum-like-const --
    test(
        'a customer TextDecoration look-alike defers — never the bare member '
        'name (the runtime defaults an unknown decoration to none)', () async {
      final r = translator.translate(
        await parseExpressionFromSourceForTest('''
        class TextDecoration {
          const TextDecoration._();
          static const TextDecoration squiggle = TextDecoration._();
        }
        Object x() => TextDecoration.squiggle;
      '''),
      );
      expect(r.dsl, isNot(contains('squiggle')));
      expect(r.issues, isNotEmpty);
    });

    test('real-flutter TextDecoration.underline still lowers', () async {
      final r = translator.translate(
        await parseExpressionFromSourceForTest(
          '''
          import 'package:flutter/material.dart';
          Object x() => TextDecoration.underline;
          ''',
          rootPackage: 'apps_examples',
        ),
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, '"underline"');
    });

    // -- Curves (package:flutter/animation) — PrefixedIdentifier
    //    enum-like-const --
    test(
        'a customer Curves look-alike defers — never the framework curve name '
        '(coincidental-supported value-substitution)', () async {
      // `easeIn` IS a supported curve name, so the catalog validator's curve
      // backstop cannot catch it — it only rejects names OUTSIDE the supported
      // set. A customer class named `Curves` must defer, not lower to
      // `"easeIn"` (which the curve decoder resolves to the REAL framework
      // `Curves.easeIn` — a value-substitution silent-wrong for the author's
      // own type). Only the element gate distinguishes them.
      final r = translator.translate(
        await parseExpressionFromSourceForTest('''
        class Curves {
          const Curves._();
          static const Curves easeIn = Curves._();
        }
        Object x() => Curves.easeIn;
      '''),
      );
      expect(r.dsl, isNot(contains('easeIn')));
      expect(r.issues, isNotEmpty);
    });

    test('real-flutter Curves.easeInOut still lowers to its name', () async {
      final r = translator.translate(
        await parseExpressionFromSourceForTest(
          '''
          import 'package:flutter/material.dart';
          Object x() => Curves.easeInOut;
          ''',
          rootPackage: 'apps_examples',
        ),
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, '"easeInOut"');
    });

    // `TextDecoration.combine([...])` reached as a standalone expression parses
    // as an InstanceCreationExpression (not a MethodInvocation); the value-type
    // routing must NOT lower it on the constructor shape — it is a static method
    // and is only lowered when it reaches the static-call shape (as it does
    // nested inside a `TextStyle(decoration:)`). The constructor shape defers
    // (unknownWidget), matching the pre-normalization behavior.
    test('TextDecoration.combine on the constructor shape defers (not lowered)',
        () async {
      final r = translator.translate(
        await parseExpressionFromSourceForTest('''
        import 'package:flutter/material.dart';
        Object x() => TextDecoration.combine(
          [TextDecoration.underline, TextDecoration.overline],
        );
      '''),
      );
      expect(r.dsl, isEmpty);
      expect(r.issues.map((i) => i.code), contains(IssueCode.unknownWidget));
    });

    // An import alias on a value-type DEFAULT constructor (`ui.Locale('en')`)
    // must lower identically to the unprefixed form: the prefix is the import
    // alias, not the class, so the value-type routing keys on the type name
    // exactly as it does without the alias. Covers both a hand-authored row
    // (Locale) and recipe-backed rows (Color / Offset).
    test('import-prefixed default ctors lower like their unprefixed form',
        () async {
      Future<String> dslOf(String expr, {String extraImport = ''}) async {
        final r = translator.translate(
          await parseExpressionFromSourceForTest('''
          import 'package:flutter/material.dart';
          $extraImport
          Object x() => $expr;
        '''),
        );
        expect(r.issues, isEmpty, reason: '$expr should lower cleanly');
        return r.dsl;
      }

      expect(
        await dslOf("const ui.Locale('en')",
            extraImport: "import 'dart:ui' as ui;"),
        await dslOf("const Locale('en')"),
      );
      expect(
        await dslOf('const ui.Color(0xFF112233)',
            extraImport: "import 'dart:ui' as ui;"),
        await dslOf('const Color(0xFF112233)'),
      );
      expect(
        await dslOf('const ui.Offset(1.0, 2.0)',
            extraImport: "import 'dart:ui' as ui;"),
        await dslOf('const Offset(1.0, 2.0)'),
      );
    });

    // -- Locale (dart:ui) — InstanceCreation --
    test('a customer Locale look-alike defers', () async {
      final r = translator.translate(
        await parseExpressionFromSourceForTest('''
        class Locale {
          const Locale(this.languageCode);
          final String languageCode;
        }
        Object x() => const Locale('en');
      '''),
      );
      expect(r.dsl, isEmpty);
      expect(r.issues.map((i) => i.code), contains(IssueCode.unknownWidget));
    });

    // -- Duration (dart:core) — InstanceCreation --
    test('a customer Duration look-alike defers (no ms total)', () async {
      final r = translator.translate(
        await parseExpressionFromSourceForTest('''
        class Duration {
          const Duration({this.seconds = 0});
          final int seconds;
        }
        Object x() => const Duration(seconds: 1);
      '''),
      );
      expect(r.dsl, isEmpty);
      expect(r.issues.map((i) => i.code), contains(IssueCode.unknownWidget));
    });
    test('real dart:core Duration still lowers to ms', () async {
      final r = translator.translate(
        await parseExpressionFromSourceForTest(
          'Object x() => const Duration(seconds: 1);',
        ),
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, '1000');
    });

    // -- the `.zero` const-factory arm (PrefixedIdentifier) --
    test('a customer EdgeInsets.zero look-alike defers (no zero list)',
        () async {
      final r = translator.translate(
        await parseExpressionFromSourceForTest('''
        class EdgeInsets {
          const EdgeInsets._();
          static const EdgeInsets zero = EdgeInsets._();
        }
        Object x() => EdgeInsets.zero;
      '''),
      );
      // The `.zero` arm defers via `_deferFrameworkConstLookalike`, so the
      // issue code is `unresolvedIdentifier` (not `unknownWidget` — this is a
      // PrefixedIdentifier, not a construction).
      expect(r.dsl, isEmpty);
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.unresolvedIdentifier),
      );
    });
    test('real-flutter EdgeInsets.zero still lowers', () async {
      final r = translator.translate(
        await parseExpressionFromSourceForTest(
          '''
          import 'package:flutter/widgets.dart';
          Object x() => EdgeInsets.zero;
          ''',
          rootPackage: 'apps_examples',
        ),
      );
      expect(r.dsl, '[0.0, 0.0, 0.0, 0.0]');
      expect(r.issues, isEmpty);
    });
    test('real-flutter BorderRadius.zero still lowers to its zero value',
        () async {
      // `.zero` is the value-wrong class the chapter protects — assert the
      // emitted WIRE VALUE (uniform-corner 0), not merely non-deferral, so the
      // const-folded value-correctness stays covered.
      final r = translator.translate(
        await parseExpressionFromSourceForTest(
          '''
          import 'package:flutter/widgets.dart';
          Object x() => BorderRadius.zero;
          ''',
          rootPackage: 'apps_examples',
        ),
      );
      expect(r.dsl, '0');
      expect(r.issues, isEmpty);
    });

    // -- Option B: the unresolved affordance is preserved (name-fallback) --
    test(
        'an UNRESOLVED EdgeInsets.all still lowers (synthetic-test affordance)',
        () async {
      // parseExpressionForTest yields an unresolved AST (null element); the
      // name-based recognition still fires (no resolved customer lookalike to
      // disambiguate from). Production always resolves, so this path is the
      // synthetic-test affordance, not a production silent-wrong vector.
      final r = translator.translate(
        await parseExpressionForTest('EdgeInsets.all(12)'),
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, '[12.0, 12.0, 12.0, 12.0]');
    });
  });

  // Pins how each commonly-used const namespace currently translates
  // under resolved AST. Each `falls through (gap)` case documents a
  // known limitation; flipping its expectation signals a regression
  // (or a deliberate extension landing).
  group('const namespace survey', () {
    // `Colors.*` / `Icons.*` recognition (curated positive, outside-curated
    // diagnostic, and the customer-lookalike + unresolved-prefix defers) is
    // covered by the dedicated 'enum + Colors translation' / 'const icon
    // resolution' groups above, which exercise real-flutter vs lookalike
    // resolution. This group covers the other const namespaces.

    test('Alignment.X falls through to enum-string for catalog props',
        () async {
      // Outside LinearGradient `begin:` / `end:` the catalog's
      // `alignment` property type accepts the bare member name.
      const source = '''
        class Alignment {
          const Alignment(this.x, this.y);
          final double x;
          final double y;
          static const Alignment topLeft = Alignment(-1.0, -1.0);
        }
        Object x() => Alignment.topLeft;
      ''';
      final r = translator.translate(
        await parseExpressionFromSourceForTest(source),
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, '"topLeft"');
    });

    // The `EdgeInsets.zero` / `BorderRadius.zero` positives + their customer
    // look-alike defers now live in the 'value-substitution sweep' group above
    // (real-flutter resolution vs a resolved customer stub) — the const-factory
    // `.zero` arms are gated to the real framework type, so a customer-stub
    // `.zero` here would (correctly) defer rather than lower.
  });

  group('Duration translation', () {
    // The `duration` property type decodes from a flat integer count of
    // milliseconds (the runtime decoder is `Duration(milliseconds: ms)`), so a
    // const `Duration(...)` lowers to its total milliseconds. These exercise
    // the named-argument arithmetic against the REAL `dart:core` Duration (the
    // value-substitution gate accepts `dart:` — no stub needed; a customer
    // Duration look-alike defers, covered by the sweep group above).

    test('Duration(seconds: 1) lowers to 1000 (milliseconds)', () async {
      final r = translator.translate(
        await parseExpressionFromSourceForTest('''
          Object x() => const Duration(seconds: 1);
        '''),
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, '1000');
    });

    test('Duration(milliseconds: 250) lowers to 250', () async {
      final r = translator.translate(
        await parseExpressionFromSourceForTest('''
          Object x() => const Duration(milliseconds: 250);
        '''),
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, '250');
    });

    test('Duration with mixed units sums to total milliseconds', () async {
      // 1 minute + 30 seconds + 500 ms = 90500 ms.
      final r = translator.translate(
        await parseExpressionFromSourceForTest('''
          Object x() =>
              const Duration(minutes: 1, seconds: 30, milliseconds: 500);
        '''),
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, '90500');
    });

    test('sub-millisecond Duration defers (cannot represent in ms)', () async {
      final r = translator.translate(
        await parseExpressionFromSourceForTest('''
          Object x() => const Duration(microseconds: 500);
        '''),
      );
      expect(r.issues, isNotEmpty);
      expect(r.dsl, isEmpty);
    });

    test('an overflowing Duration defers (never a wrapped value)', () async {
      // days * microsecondsPerDay overflows int64; the total must not silently
      // wrap to a (negative) millisecond value — it defers with a diagnostic.
      final r = translator.translate(
        await parseExpressionFromSourceForTest('''
          Object x() => const Duration(days: 9223372036854775807);
        '''),
      );
      expect(r.issues, isNotEmpty);
      expect(r.dsl, isEmpty);
    });
  });

  group('EdgeInsets translation', () {
    // Integer literals are normalised to double literals so rfw's
    // `source.v<double>(...)` strict cast accepts them — the rfw runtime
    // would silently null a bare integer at an edge-insets slot.
    test('EdgeInsets.all(12)', () async {
      final r = translator.translate(
        await parseExpressionForTest('EdgeInsets.all(12)'),
      );
      expect(r.dsl, '[12.0, 12.0, 12.0, 12.0]');
      expect(r.issues, isEmpty);
    });

    test('EdgeInsets.symmetric(horizontal: 8, vertical: 4)', () async {
      final r = translator.translate(
        await parseExpressionForTest(
          'EdgeInsets.symmetric(horizontal: 8, vertical: 4)',
        ),
      );
      expect(r.dsl, '[8.0, 4.0, 8.0, 4.0]');
    });

    test('EdgeInsets.symmetric(horizontal: 8) defaults vertical to 0',
        () async {
      final r = translator.translate(
        await parseExpressionForTest('EdgeInsets.symmetric(horizontal: 8)'),
      );
      expect(r.dsl, '[8.0, 0.0, 8.0, 0.0]');
    });

    test('EdgeInsets.fromLTRB(1, 2, 3, 4)', () async {
      final r = translator.translate(
        await parseExpressionForTest('EdgeInsets.fromLTRB(1, 2, 3, 4)'),
      );
      expect(r.dsl, '[1.0, 2.0, 3.0, 4.0]');
    });

    test('EdgeInsets.only(left: 5)', () async {
      final r = translator.translate(
        await parseExpressionForTest('EdgeInsets.only(left: 5)'),
      );
      expect(r.dsl, '[5.0, 0.0, 0.0, 0.0]');
    });

    test('EdgeInsets.only(top: 1, right: 2)', () async {
      final r = translator.translate(
        await parseExpressionForTest('EdgeInsets.only(top: 1, right: 2)'),
      );
      expect(r.dsl, '[0.0, 1.0, 2.0, 0.0]');
    });

    test('unknown EdgeInsets factory emits unrecognizedMethodCall', () async {
      final r = translator.translate(
        await parseExpressionForTest('EdgeInsets.lerp(null, null, 0.5)'),
      );
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.unrecognizedMethodCall),
      );
    });

    test('EdgeInsets.all() with no args emits unrecognizedMethodCall',
        () async {
      final r = translator.translate(
        await parseExpressionForTest('EdgeInsets.all()'),
      );
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.unrecognizedMethodCall),
      );
    });

    test(
        'EdgeInsets.fromLTRB with wrong arg count emits unrecognizedMethodCall',
        () async {
      final r = translator.translate(
        await parseExpressionForTest('EdgeInsets.fromLTRB(1, 2)'),
      );
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.unrecognizedMethodCall),
      );
    });
  });

  group('const-factory zero lowering', () {
    test('EdgeInsets.zero lowers to the same value as EdgeInsets.all(0)',
        () async {
      final zero =
          translator.translate(await parseExpressionForTest('EdgeInsets.zero'));
      final explicit = translator
          .translate(await parseExpressionForTest('EdgeInsets.all(0)'));
      expect(zero.issues, isEmpty);
      expect(zero.dsl, explicit.dsl);
    });

    test(
        'EdgeInsetsDirectional.zero lowers to the same value as '
        'EdgeInsets.all(0)', () async {
      final zero = translator.translate(
        await parseExpressionForTest('EdgeInsetsDirectional.zero'),
      );
      final explicit = translator
          .translate(await parseExpressionForTest('EdgeInsets.all(0)'));
      expect(zero.issues, isEmpty);
      expect(zero.dsl, explicit.dsl);
    });

    test(
        'BorderRadius.zero lowers to the same value as '
        'BorderRadius.circular(0)', () async {
      final zero = translator
          .translate(await parseExpressionForTest('BorderRadius.zero'));
      final explicit = translator.translate(
        await parseExpressionForTest('BorderRadius.circular(0)'),
      );
      expect(zero.issues, isEmpty);
      expect(zero.dsl, explicit.dsl);
    });
  });

  group('Color constructor translation', () {
    test('Color(0xFF112233) → 0xFF112233', () async {
      final r = translator.translate(
        await parseExpressionForTest('Color(0xFF112233)'),
      );
      expect(r.dsl, '0xFF112233');
      expect(r.issues, isEmpty);
    });

    test('Color preserves uppercase hex', () async {
      final r = translator.translate(
        await parseExpressionForTest('Color(0xabcdef01)'),
      );
      expect(r.dsl, '0xABCDEF01');
    });

    test('Color.fromARGB packs four channels into AARRGGBB', () async {
      final r = translator.translate(
        await parseExpressionForTest('Color.fromARGB(255, 0x12, 0x34, 0x56)'),
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, '0xFF123456');
    });

    test('Color.fromARGB out-of-range channel emits a diagnostic', () async {
      final r = translator.translate(
        await parseExpressionForTest('Color.fromARGB(255, 256, 0, 0)'),
      );
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.unrecognizedMethodCall),
      );
    });

    test('Color.fromRGBO maps opacity to alpha via round(255*opacity)',
        () async {
      final r = translator.translate(
        await parseExpressionForTest('Color.fromRGBO(0x12, 0x34, 0x56, 0.5)'),
      );
      expect(r.issues, isEmpty);
      // 0.5 * 255 = 127.5 → 128 → 0x80 alpha
      expect(r.dsl, '0x80123456');
    });

    test('Color.fromRGBO opacity out of 0..1 emits a diagnostic', () async {
      final r = translator.translate(
        await parseExpressionForTest('Color.fromRGBO(0, 0, 0, 1.5)'),
      );
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.unrecognizedMethodCall),
      );
    });

    test('unsupported Color factory emits a clear diagnostic', () async {
      final r = translator.translate(
        await parseExpressionForTest('Color.lerp(null, null, 0.5)'),
      );
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.unrecognizedMethodCall),
      );
    });
  });

  group('BorderRadius factory translation', () {
    test('BorderRadius.circular(r) flattens to the inner radius', () async {
      final r = translator.translate(
        await parseExpressionForTest('BorderRadius.circular(16)'),
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, '16');
    });

    test('BorderRadius.circular accepts double literal', () async {
      final r = translator.translate(
        await parseExpressionForTest('BorderRadius.circular(8.5)'),
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, '8.5');
    });

    test('BorderRadius.all(Radius.circular(r)) flattens to the uniform radius',
        () async {
      final r = translator.translate(
        await parseExpressionForTest('BorderRadius.all(Radius.circular(8))'),
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, '8');
    });

    test('BorderRadius.only emits a per-corner sentinel for the SET corners',
        () async {
      final r = translator.translate(
        await parseExpressionForTest(
          'BorderRadius.only(topLeft: Radius.circular(1), '
          'bottomRight: Radius.circular(4))',
        ),
      );
      expect(r.issues, isEmpty);
      // Only the two specified corners; omitted corners absent (reconstruct to
      // Radius.zero on the catalog side). Coerced to double literals.
      expect(
        r.dsl,
        '__rfw_border_radius_corners(topLeft: 1.0, bottomRight: 4.0)',
      );
    });

    test('BorderRadius.vertical mirrors top->TL/TR and bottom->BL/BR',
        () async {
      final r = translator.translate(
        await parseExpressionForTest(
          'BorderRadius.vertical(top: Radius.circular(4), '
          'bottom: Radius.circular(8))',
        ),
      );
      expect(r.issues, isEmpty);
      expect(
        r.dsl,
        '__rfw_border_radius_corners(topLeft: 4.0, topRight: 4.0, '
        'bottomLeft: 8.0, bottomRight: 8.0)',
      );
    });

    test('BorderRadius.vertical emits only the specified side', () async {
      final r = translator.translate(
        await parseExpressionForTest(
          'BorderRadius.vertical(top: Radius.circular(4))',
        ),
      );
      expect(r.issues, isEmpty);
      expect(
        r.dsl,
        '__rfw_border_radius_corners(topLeft: 4.0, topRight: 4.0)',
      );
    });

    test('BorderRadius.horizontal mirrors left->TL/BL and right->TR/BR',
        () async {
      final r = translator.translate(
        await parseExpressionForTest(
          'BorderRadius.horizontal(left: Radius.circular(4))',
        ),
      );
      expect(r.issues, isEmpty);
      expect(
        r.dsl,
        '__rfw_border_radius_corners(topLeft: 4.0, bottomLeft: 4.0)',
      );
    });

    test('an elliptical corner defers the WHOLE borderRadius loudly', () async {
      final r = translator.translate(
        await parseExpressionForTest(
          'BorderRadius.only(topLeft: Radius.elliptical(4, 8), '
          'topRight: Radius.circular(2))',
        ),
      );
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.unrecognizedMethodCall),
      );
      // Carry-all-or-defer: NOT a partial emit of the circular corner.
      expect(r.dsl, isNot(contains('__rfw_border_radius_corners')));
    });

    test('BorderRadius.all with an elliptical radius defers loudly', () async {
      final r = translator.translate(
        await parseExpressionForTest(
          'BorderRadius.all(Radius.elliptical(4, 8))',
        ),
      );
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.unrecognizedMethodCall),
      );
    });

    test('a non-circular corner Radius (Radius.zero) defers loudly', () async {
      // This phase recognises Radius.circular corners only; the explicit
      // Radius.zero form defers (the omit-form covers a zero corner).
      final r = translator.translate(
        await parseExpressionForTest(
          'BorderRadius.only(topLeft: Radius.zero)',
        ),
      );
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.unrecognizedMethodCall),
      );
    });
  });

  // Splice — the per-corner sentinel fans out onto the landed per-corner
  // catalog slots. Exercised against the REAL core catalog so the per-corner
  // slots (ClipRRect w0007, Container w0010, AnimatedContainer w0002) and the
  // BoxDecoration decompose are the committed ones, not a synthetic mirror.
  group('asymmetric BorderRadius per-corner splice (real core catalog)', () {
    late ExpressionTranslator real;

    setUp(() {
      final coreJson = File(
        '../restage_core/lib/src/widget_catalog/catalog.json',
      ).readAsStringSync();
      real = ExpressionTranslator(
        catalog: decodeCatalog(coreJson),
        helpers: HelperRegistry(),
      );
    });

    Future<TranslationResult> run(String body) async {
      return real.translate(
        await parseExpressionFromSourceForTest(
          '''
          import 'package:flutter/widgets.dart';
          Object x() => $body;
          ''',
          rootPackage: 'apps_examples',
        ),
      );
    }

    // -- direct path (ClipRRect.borderRadius) --
    test('ClipRRect .circular stays the uniform slot (byte parity)', () async {
      final r = await run('ClipRRect(borderRadius: BorderRadius.circular(8))');
      expect(r.issues, isEmpty);
      expect(r.dsl, 'ClipRRect(borderRadius: 8.0)');
    });

    test('ClipRRect .only splices onto per-corner slots, no uniform slot',
        () async {
      final r = await run(
        'ClipRRect(borderRadius: '
        'BorderRadius.only(topLeft: Radius.circular(8), '
        'bottomRight: Radius.circular(4)))',
      );
      expect(r.issues, isEmpty);
      expect(
        r.dsl,
        'ClipRRect(borderRadiusTopLeft: 8.0, borderRadiusBottomRight: 4.0)',
      );
      expect(r.dsl, isNot(contains('borderRadius:')));
      expect(r.dsl, isNot(contains('__rfw_border_radius_corners')));
    });

    // -- decompose path (Container.decoration -> BoxDecoration.borderRadius) --
    test('Container .circular stays the uniform slot (byte parity)', () async {
      final r = await run(
        'Container(decoration: '
        'BoxDecoration(borderRadius: BorderRadius.circular(8)))',
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, 'Container(borderRadius: 8.0)');
    });

    test('Container .vertical splices onto per-corner slots', () async {
      final r = await run(
        'Container(decoration: '
        'BoxDecoration(borderRadius: '
        'BorderRadius.vertical(top: Radius.circular(20))))',
      );
      expect(r.issues, isEmpty);
      expect(
        r.dsl,
        'Container(borderRadiusTopLeft: 20.0, borderRadiusTopRight: 20.0)',
      );
      expect(r.dsl, isNot(contains('__rfw_border_radius_corners')));
    });

    test('Container .all(Radius.circular) collapses to the uniform slot',
        () async {
      final r = await run(
        'Container(decoration: '
        'BoxDecoration(borderRadius: '
        'BorderRadius.all(Radius.circular(12))))',
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, 'Container(borderRadius: 12.0)');
    });

    test('Container .only emits only the set corners', () async {
      final r = await run(
        'Container(decoration: '
        'BoxDecoration(borderRadius: '
        'BorderRadius.only(bottomLeft: Radius.circular(6))))',
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, 'Container(borderRadiusBottomLeft: 6.0)');
    });

    test('Container with an elliptical corner defers loudly, no partial emit',
        () async {
      final r = await run(
        'Container(decoration: '
        'BoxDecoration(borderRadius: BorderRadius.only(topLeft: '
        'Radius.elliptical(4, 8), topRight: Radius.circular(2))))',
      );
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.unrecognizedMethodCall),
      );
      expect(r.dsl, isNot(contains('borderRadiusTopRight')));
    });

    test(
        'a conditional wrapping an asymmetric BorderRadius defers loudly, '
        'no sentinel leak (direct slot)', () async {
      // The conditional lowers each branch through the slot translator; the
      // asymmetric branch would otherwise embed the per-corner sentinel inside
      // the `switch {...}`, which the splice cannot fan out. Carry-all-or-defer:
      // it must defer LOUD, never leak the sentinel into the blob.
      final r = await run(
        'ClipRRect(borderRadius: true '
        '? BorderRadius.only(topLeft: Radius.circular(8)) '
        ': BorderRadius.circular(4))',
      );
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.unrecognizedMethodCall),
      );
      expect(r.dsl, isNot(contains('__rfw_border_radius_corners')));
    });

    test('AnimatedContainer .horizontal splices onto per-corner slots',
        () async {
      final r = await run(
        'AnimatedContainer(duration: Duration(milliseconds: 200), '
        'decoration: '
        'BoxDecoration(borderRadius: '
        'BorderRadius.horizontal(left: Radius.circular(10))))',
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, contains('borderRadiusTopLeft: 10.0'));
      expect(r.dsl, contains('borderRadiusBottomLeft: 10.0'));
      expect(r.dsl, isNot(contains('__rfw_border_radius_corners')));
    });

    // End-to-end: translate -> emit library -> validate against the real
    // catalog -> encode -> decode, then assert the decoded blob carries the
    // per-corner keys. Proves the spliced slots are real, correctly-typed
    // catalog properties that survive the full wire round-trip.
    Future<fmt.ConstructorCall> roundTrip(String body) async {
      final coreCatalog = decodeCatalog(
        File('../restage_core/lib/src/widget_catalog/catalog.json')
            .readAsStringSync(),
      );
      final r = await run(body);
      expect(r.issues, isEmpty);
      final library = emitPaywallLibrary(r.dsl);
      final parsed = fmt.parseLibraryFile(library, sourceIdentifier: 'e2e');
      // The spliced per-corner keys must be real, typed catalog slots.
      expect(validateModelAgainstCatalog(parsed, coreCatalog), isEmpty);
      final bytes = fmt.encodeLibraryBlob(parsed);
      final decoded = fmt.decodeLibraryBlob(Uint8List.fromList(bytes));
      return decoded.widgets
          .firstWhere((w) => w.name == paywallRootWidgetName)
          .root as fmt.ConstructorCall;
    }

    test('direct path: the decoded ClipRRect blob carries the per-corner keys',
        () async {
      final root = await roundTrip(
        'ClipRRect(borderRadius: '
        'BorderRadius.only(topLeft: Radius.circular(8), '
        'bottomRight: Radius.circular(4)))',
      );
      expect(root.name, 'ClipRRect');
      expect(root.arguments['borderRadiusTopLeft'], 8.0);
      expect(root.arguments['borderRadiusBottomRight'], 4.0);
      expect(root.arguments.containsKey('borderRadiusTopRight'), isFalse);
      expect(root.arguments.containsKey('borderRadius'), isFalse);
    });

    test('decompose path: the decoded Container blob carries per-corner keys',
        () async {
      final root = await roundTrip(
        'Container(decoration: '
        'BoxDecoration(borderRadius: '
        'BorderRadius.vertical(top: Radius.circular(20))))',
      );
      expect(root.name, 'Container');
      expect(root.arguments['borderRadiusTopLeft'], 20.0);
      expect(root.arguments['borderRadiusTopRight'], 20.0);
      expect(root.arguments.containsKey('borderRadius'), isFalse);
    });
  });

  group('unary minus on numeric literals', () {
    test('-1.5 translates to a negative double literal', () async {
      final r = translator.translate(
        await parseExpressionForTest('-1.5'),
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, '-1.5');
    });

    test('-2 translates to a negative integer literal', () async {
      final r = translator.translate(
        await parseExpressionForTest('-2'),
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, '-2');
    });

    test('negative offsets in BoxShadow round-trip', () async {
      // Drop-shadow patterns commonly use a negative `y` for top-edge
      // shadows; without unary-minus handling the offset map would
      // emit `{x: 0.0, y: }` (malformed) plus an unsupported-expression
      // diagnostic.
      final r = translator.translate(
        await parseExpressionForTest(
          'BoxShadow(offset: Offset(0.0, -8.0), blurRadius: 4.0)',
        ),
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, '{offset: {x: 0.0, y: -8.0}, blurRadius: 4.0}');
    });

    test('BoxShadow coerces int blurRadius/spreadRadius to double', () async {
      // rfw's `boxShadow` decoder reads `blurRadius` and `spreadRadius`
      // with `source.v<double>(...)`. Author-written int literals (which
      // Flutter accepts via implicit int→double conversion) must emit as
      // double on the wire so the decoder doesn't silently null the
      // slot and fall back to its default.
      final r = translator.translate(
        await parseExpressionForTest(
          'BoxShadow(offset: Offset(0.0, 8.0), '
          'blurRadius: 24, spreadRadius: 4)',
        ),
      );
      expect(r.issues, isEmpty);
      expect(
        r.dsl,
        '{offset: {x: 0.0, y: 8.0}, blurRadius: 24.0, spreadRadius: 4.0}',
      );
    });

    test('Offset(x, y) coerces int positional literals to double', () async {
      // rfw's `offset` decoder reads `x` and `y` with `source.v<double>`.
      // `Offset(0, 8)` is valid Dart (int → double parameter conversion)
      // and must emit `{x: 0.0, y: 8.0}` so both slots decode.
      final r = translator.translate(
        await parseExpressionForTest('Offset(0, 8)'),
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, '{x: 0.0, y: 8.0}');
    });
  });

  group('LinearGradient translation', () {
    test('emits the rfw gradient map shape for member alignments', () async {
      final r = translator.translate(
        await parseExpressionForTest(
          'LinearGradient(begin: Alignment.topLeft, '
          'end: Alignment.bottomRight, '
          'colors: [Color(0xFF112233), Color(0xFF445566)])',
        ),
      );
      expect(r.issues, isEmpty);
      expect(
        r.dsl,
        '{type: "linear", begin: {x: -1.0, y: -1.0}, '
        'end: {x: 1.0, y: 1.0}, colors: [0xFF112233, 0xFF445566]}',
      );
    });

    test('omits begin/end when unset — rfw decoder applies defaults', () async {
      // Flutter's LinearGradient ctor defaults begin to centerLeft and
      // end to centerRight. The rfw `gradient` decoder reapplies the
      // same defaults via its `?? Alignment.centerLeft` / `??
      // Alignment.centerRight` fallbacks, so the translator emits a
      // compact map that omits the unset keys.
      final r = translator.translate(
        await parseExpressionForTest(
          'LinearGradient(colors: [Color(0xFF000000), Color(0xFFFFFFFF)])',
        ),
      );
      expect(r.issues, isEmpty);
      expect(
        r.dsl,
        '{type: "linear", colors: [0xFF000000, 0xFFFFFFFF]}',
      );
    });

    test('passes stops through as a DSL list', () async {
      final r = translator.translate(
        await parseExpressionForTest(
          'LinearGradient(begin: Alignment.topLeft, '
          'end: Alignment.bottomRight, '
          'colors: [Color(0xFF112233), Color(0xFF445566)], '
          'stops: [0.0, 1.0])',
        ),
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, contains('stops: [0.0, 1.0]'));
    });

    test('Alignment(x, y) literal threads the explicit coordinates', () async {
      final r = translator.translate(
        await parseExpressionForTest(
          'LinearGradient(begin: Alignment(0.25, -0.5), '
          'end: Alignment(1.0, 1.0), '
          'colors: [Color(0xFF000000), Color(0xFFFFFFFF)])',
        ),
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, contains('begin: {x: 0.25, y: -0.5}'));
      expect(r.dsl, contains('end: {x: 1.0, y: 1.0}'));
    });

    test('unsupported tileMode argument surfaces a diagnostic', () async {
      final r = translator.translate(
        await parseExpressionForTest(
          'LinearGradient(begin: Alignment.topLeft, '
          'end: Alignment.bottomRight, '
          'colors: [Color(0xFF000000), Color(0xFFFFFFFF)], '
          'tileMode: TileMode.mirror)',
        ),
      );
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.unrecognizedMethodCall),
      );
    });

    test('unknown Alignment member surfaces a diagnostic', () async {
      final r = translator.translate(
        await parseExpressionForTest(
          'LinearGradient(begin: Alignment.bogus, '
          'end: Alignment.bottomRight, '
          'colors: [Color(0xFF000000), Color(0xFFFFFFFF)])',
        ),
      );
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.unresolvedIdentifier),
      );
    });
  });

  group('RadialGradient translation', () {
    test('emits the rfw radial gradient map shape', () async {
      final r = translator.translate(
        await parseExpressionForTest(
          'RadialGradient('
          'colors: [Color(0xFF112233), Color(0xFF445566)], '
          'center: Alignment.topLeft, radius: 0.75)',
        ),
      );
      expect(r.issues, isEmpty);
      expect(
        r.dsl,
        '{type: "radial", colors: [0xFF112233, 0xFF445566], '
        'center: {x: -1.0, y: -1.0}, radius: 0.75}',
      );
    });

    test('omits center/radius when unset — rfw decoder applies defaults',
        () async {
      final r = translator.translate(
        await parseExpressionForTest(
          'RadialGradient(colors: [Color(0xFF000000), Color(0xFFFFFFFF)])',
        ),
      );
      expect(r.issues, isEmpty);
      expect(
        r.dsl,
        '{type: "radial", colors: [0xFF000000, 0xFFFFFFFF]}',
      );
    });

    test('threads focal/focalRadius and an Alignment(x, y) center', () async {
      final r = translator.translate(
        await parseExpressionForTest(
          'RadialGradient('
          'colors: [Color(0xFF000000), Color(0xFFFFFFFF)], '
          'center: Alignment(0.25, -0.5), '
          'focal: Alignment.bottomRight, focalRadius: 0.1)',
        ),
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, contains('center: {x: 0.25, y: -0.5}'));
      expect(r.dsl, contains('focal: {x: 1.0, y: 1.0}'));
      expect(r.dsl, contains('focalRadius: 0.1'));
    });
  });

  group('SweepGradient translation', () {
    test('emits the rfw sweep gradient map shape', () async {
      final r = translator.translate(
        await parseExpressionForTest(
          'SweepGradient(colors: [Color(0xFF112233), Color(0xFF445566)])',
        ),
      );
      expect(r.issues, isEmpty);
      expect(
        r.dsl,
        '{type: "sweep", colors: [0xFF112233, 0xFF445566]}',
      );
    });

    test('threads center/startAngle/endAngle and stops', () async {
      final r = translator.translate(
        await parseExpressionForTest(
          'SweepGradient('
          'colors: [Color(0xFF000000), Color(0xFFFFFFFF)], '
          'center: Alignment.center, startAngle: 0.0, endAngle: 3.14, '
          'stops: [0.0, 1.0])',
        ),
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, contains('center: {x: 0.0, y: 0.0}'));
      expect(r.dsl, contains('startAngle: 0.0'));
      expect(r.dsl, contains('endAngle: 3.14'));
      expect(r.dsl, contains('stops: [0.0, 1.0]'));
    });
  });

  group('gradient stops int->double coercion', () {
    // The rfw gradient decoder reads `stops` as `list<double>` via an exact
    // `v<double> ?? 0.0` cast, so an author-written int element (`stops:
    // [0, 1]`) is silently nulled to 0.0 unless the translator coerces each
    // element to a double literal — the same int->double coercion the sibling
    // (width/blurRadius/radius) already apply.
    test('LinearGradient coerces int stops to double literals', () async {
      final r = translator.translate(
        await parseExpressionForTest(
          'LinearGradient(begin: Alignment.topLeft, '
          'end: Alignment.bottomRight, '
          'colors: [Color(0xFF112233), Color(0xFF445566)], '
          'stops: [0, 1])',
        ),
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, contains('stops: [0.0, 1.0]'));
    });

    test('RadialGradient coerces int stops to double literals', () async {
      final r = translator.translate(
        await parseExpressionForTest(
          'RadialGradient('
          'colors: [Color(0xFF112233), Color(0xFF445566)], '
          'stops: [0, 1])',
        ),
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, contains('stops: [0.0, 1.0]'));
    });

    test('SweepGradient coerces int stops to double literals', () async {
      final r = translator.translate(
        await parseExpressionForTest(
          'SweepGradient('
          'colors: [Color(0xFF112233), Color(0xFF445566)], '
          'stops: [0, 1])',
        ),
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, contains('stops: [0.0, 1.0]'));
    });
  });

  group('Border translation', () {
    test('Border.all(color, width) emits a single-side list', () async {
      final r = translator.translate(
        await parseExpressionForTest(
          'Border.all(color: Color(0xFF8B5CF6), width: 2)',
        ),
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, '[{color: 0xFF8B5CF6, width: 2.0}]');
    });

    test('resolved Flutter Border.all stays on border path', () async {
      final r = translator.translate(
        await parseExpressionFromSourceForTest(
          '''
          import 'package:flutter/painting.dart';

          Object x() => Border.all(
                color: const Color(0xFF8B5CF6),
                width: 2,
              );
          ''',
          rootPackage: 'apps_examples',
        ),
      );

      expect(r.issues, isEmpty);
      expect(r.dsl, '[{color: 0xFF8B5CF6, width: 2.0}]');
    });

    test('Border.all(color) omits width — rfw defaults to 1.0', () async {
      final r = translator.translate(
        await parseExpressionForTest('Border.all(color: Color(0xFF2A2148))'),
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, '[{color: 0xFF2A2148}]');
    });

    test(
      'Border(bottom: BorderSide(...)) fills unset sides with BorderSide.none',
      () async {
        // The default-ctor variant lands in the per-side list shape; unset
        // sides serialise as `BorderStyle.none` width-zero maps so rfw's
        // border decoder doesn't fall back to the start-side value.
        final r = translator.translate(
          await parseExpressionForTest(
            'Border(bottom: BorderSide(color: Color(0xFFE5E5EA)))',
          ),
        );
        expect(r.issues, isEmpty);
        expect(
          r.dsl,
          '[{width: 0.0, style: "none"}, {width: 0.0, style: "none"}, '
          '{width: 0.0, style: "none"}, {color: 0xFFE5E5EA}]',
        );
      },
    );

    test('resolved Flutter Border default ctor stays on border path', () async {
      final r = translator.translate(
        await parseExpressionFromSourceForTest(
          '''
          import 'package:flutter/painting.dart';

          Object x() => const Border(
                bottom: BorderSide(color: Color(0xFFE5E5EA)),
              );
          ''',
          rootPackage: 'apps_examples',
        ),
      );

      expect(r.issues, isEmpty);
      expect(
        r.dsl,
        '[{width: 0.0, style: "none"}, {width: 0.0, style: "none"}, '
        '{width: 0.0, style: "none"}, {color: 0xFFE5E5EA}]',
      );
    });

    test(
      'Border(top:, left:) maps top→position 1 and left→position 0',
      () async {
        // Per the LTR-mapping comment on `_borderDefault`: left == start
        // (position 0), top (position 1), right == end (position 2),
        // bottom (position 3).
        final r = translator.translate(
          await parseExpressionForTest(
            'Border(top: BorderSide(color: Color(0xFF000000), width: 2), '
            'left: BorderSide(color: Color(0xFFFFFFFF)))',
          ),
        );
        expect(r.issues, isEmpty);
        expect(
          r.dsl,
          '[{color: 0xFFFFFFFF}, {color: 0xFF000000, width: 2.0}, '
          '{width: 0.0, style: "none"}, {width: 0.0, style: "none"}]',
        );
      },
    );

    test('BorderSide emits its rfw map shape with explicit style', () async {
      final r = translator.translate(
        await parseExpressionForTest(
          'BorderSide(color: Color(0xFF112233), width: 1.5, '
          'style: BorderStyle.solid)',
        ),
      );
      expect(r.issues, isEmpty);
      expect(
        r.dsl,
        '{color: 0xFF112233, width: 1.5, style: "solid"}',
      );
    });

    test('BorderSide coerces int width literal to double', () async {
      // rfw's `borderSide` decoder reads `width` with `source.v<double>(...)`
      // which strict-casts and silently nulls an int slot. Author-written
      // `width: 2` (a natural Dart int literal accepted by Flutter's
      // `BorderSide(double width)`) must emit as `2.0` on the wire.
      final r = translator.translate(
        await parseExpressionForTest(
          'BorderSide(color: Color(0xFF112233), width: 2)',
        ),
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, '{color: 0xFF112233, width: 2.0}');
    });

    test('unsupported Border factory surfaces a diagnostic', () async {
      final r = translator.translate(
        await parseExpressionForTest(
          'Border.symmetric(vertical: BorderSide())',
        ),
      );
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.unrecognizedMethodCall),
      );
    });
  });

  group('BoxShadow / Offset translation', () {
    test('BoxShadow emits the rfw map shape with all four keys', () async {
      final r = translator.translate(
        await parseExpressionForTest(
          'BoxShadow(color: Color(0x668B5CF6), blurRadius: 24, '
          'spreadRadius: 2, offset: Offset(0, 8))',
        ),
      );
      expect(r.issues, isEmpty);
      expect(
        r.dsl,
        '{color: 0x668B5CF6, blurRadius: 24.0, spreadRadius: 2.0, '
        'offset: {x: 0.0, y: 8.0}}',
      );
    });

    test('BoxShadow omits unset keys (rfw decoder fills defaults)', () async {
      final r = translator.translate(
        await parseExpressionForTest('BoxShadow(color: Color(0xFF000000))'),
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, '{color: 0xFF000000}');
    });

    test('list of BoxShadows composes correctly', () async {
      // Each element of the list literal routes through `_boxShadow`
      // independently — this is the list-of-structured canary that
      // proves the existing list translator composes with the new
      // structured-type translators without a bespoke list helper.
      final r = translator.translate(
        await parseExpressionForTest(
          '[BoxShadow(color: Color(0x668B5CF6), blurRadius: 24, '
          'offset: Offset(0, 8)), '
          'BoxShadow(color: Color(0xFF000000))]',
        ),
      );
      expect(r.issues, isEmpty);
      expect(
        r.dsl,
        '[{color: 0x668B5CF6, blurRadius: 24.0, offset: {x: 0.0, y: 8.0}}, '
        '{color: 0xFF000000}]',
      );
    });

    test('Offset requires two positional doubles', () async {
      final r = translator.translate(
        await parseExpressionForTest('Offset(2.0, 4.0)'),
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, '{x: 2.0, y: 4.0}');
    });

    test('Offset with wrong arity surfaces a diagnostic', () async {
      final r = translator.translate(
        await parseExpressionForTest('Offset(1.0)'),
      );
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.unrecognizedMethodCall),
      );
    });

    test('unknown BoxShadow argument surfaces a diagnostic', () async {
      final r = translator.translate(
        await parseExpressionForTest('BoxShadow(elevation: 4)'),
      );
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.unrecognizedMethodCall),
      );
    });
  });

  group('non-finite numeric guard (E2 #1)', () {
    // A non-finite double — `double.infinity` / `.negativeInfinity` / `.nan`,
    // or an overflowing literal like `1e400` — has no representable RFW value.
    // Pre-guard it was emitted silently: the named consts fell through the
    // bare-name fallback to `"infinity"` (a string in a double slot, nulled by
    // the runtime decode), and an overflow literal emitted the bare token
    // `Infinity`. Both funnel through `_translate`, so the guard sits there and
    // fires for every slot — structured-value fields AND top-level scalars —
    // turning the silent drop into a loud build error.

    bool firesNonFinite(TranslationResult r) =>
        r.issues.any((i) => i.code == IssueCode.nonFiniteNumericValue);

    // ─── Funnel B: the named non-finite double consts (PrefixedIdentifier) ───
    test('BoxShadow.blurRadius = double.infinity fails loud', () async {
      final r = translator.translate(
        await parseExpressionForTest('BoxShadow(blurRadius: double.infinity)'),
      );
      expect(
        firesNonFinite(r),
        isTrue,
        reason: 'double.infinity in a structured field must diagnose',
      );
    });

    test('BoxShadow.blurRadius = double.nan fails loud', () async {
      final r = translator.translate(
        await parseExpressionForTest('BoxShadow(blurRadius: double.nan)'),
      );
      expect(firesNonFinite(r), isTrue);
    });

    test('BoxShadow.blurRadius = double.negativeInfinity fails loud', () async {
      final r = translator.translate(
        await parseExpressionForTest(
          'BoxShadow(blurRadius: double.negativeInfinity)',
        ),
      );
      expect(firesNonFinite(r), isTrue);
    });

    // ─── A SECOND structured field, proving the funnel (not just BoxShadow) ──
    test('Border.all(width: double.infinity) fails loud', () async {
      final r = translator.translate(
        await parseExpressionForTest('Border.all(width: double.infinity)'),
      );
      expect(
        firesNonFinite(r),
        isTrue,
        reason: 'the guard funnels through _translate, so every structured '
            'numeric field is covered, not only BoxShadow',
      );
    });

    test('EdgeInsets.all(double.infinity) fails loud', () async {
      final r = translator.translate(
        await parseExpressionForTest('EdgeInsets.all(double.infinity)'),
      );
      expect(firesNonFinite(r), isTrue);
    });

    test('Offset(0.0, double.infinity) fails loud (recipe path)', () async {
      final r = translator.translate(
        await parseExpressionForTest('Offset(0.0, double.infinity)'),
      );
      expect(firesNonFinite(r), isTrue);
    });

    // ─── Funnel A: an overflowing double literal (a non-finite VALUE) ───────
    test('BoxShadow.blurRadius = 1e400 (overflow literal) fails loud',
        () async {
      final r = translator.translate(
        await parseExpressionForTest('BoxShadow(blurRadius: 1e400)'),
      );
      expect(
        firesNonFinite(r),
        isTrue,
        reason: 'an overflow literal evaluates to a non-finite double and '
            'would otherwise emit the bare token `Infinity`',
      );
    });

    test('BoxShadow.blurRadius = -1e400 fails loud', () async {
      final r = translator.translate(
        await parseExpressionForTest('BoxShadow(blurRadius: -1e400)'),
      );
      expect(firesNonFinite(r), isTrue);
    });

    // ─── Top-level scalar — the same core funnel covers it ──────────────────
    test('a bare double.infinity scalar fails loud (core funnel)', () async {
      final r = translator.translate(
        await parseExpressionForTest('double.infinity'),
      );
      expect(firesNonFinite(r), isTrue);
    });

    test('a bare overflow literal scalar fails loud (core funnel)', () async {
      final r = translator.translate(await parseExpressionForTest('1e400'));
      expect(firesNonFinite(r), isTrue);
    });

    // ─── Positive controls: finite values are unaffected ────────────────────
    test('a finite blurRadius still emits correctly (no guard)', () async {
      final r = translator.translate(
        await parseExpressionForTest('BoxShadow(blurRadius: 24.0)'),
      );
      expect(firesNonFinite(r), isFalse);
      expect(r.issues, isEmpty);
      expect(r.dsl, '{blurRadius: 24.0}');
    });

    test('double.maxFinite is finite — the guard does NOT fire', () async {
      // maxFinite is a FINITE double, out of scope for the non-finite guard.
      // It carries a separate, pre-existing degradation (it emits the bare name
      // here in the unresolved test harness) that this guard deliberately does
      // not touch — the boundary is `!isFinite`, nothing else.
      final r = translator.translate(
        await parseExpressionForTest('BoxShadow(blurRadius: double.maxFinite)'),
      );
      expect(
        firesNonFinite(r),
        isFalse,
        reason: 'the guard must fire on !isFinite only, never on a finite '
            'value like double.maxFinite',
      );
    });
  });

  group('catalog widget construction', () {
    // Build a small test catalog with Text + Column entries.
    final testCatalog = catalogWith([
      entry(
        name: 'Text',
        category: WidgetCategory.decoration,
        properties: [
          prop('text', PropertyType.string, required: true, positional: true),
          prop('fontSize', PropertyType.real),
          prop('fontWeight', PropertyType.fontWeight),
        ],
      ),
      entry(
        name: 'Column',
        childrenSlot: ChildrenSlot.list,
        properties: [
          prop('children', PropertyType.widgetList),
          prop('mainAxisAlignment', PropertyType.enumValue),
        ],
      ),
    ]);
    final t = ExpressionTranslator(
      catalog: testCatalog,
      helpers: HelperRegistry(),
    );

    test('Text(text:"hi") with named arg', () async {
      final r = t.translate(
        await parseExpressionForTest("Text(text: 'hi')"),
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, 'Text(text: "hi")');
    });

    test('Text("hi") positional first arg maps to first declared property',
        () async {
      final r = t.translate(await parseExpressionForTest("Text('hi')"));
      expect(r.issues, isEmpty);
      expect(r.dsl, 'Text(text: "hi")');
    });

    test('Text with multiple named props', () async {
      final r = t.translate(
        await parseExpressionForTest("Text('hi', fontSize: 16.0)"),
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, 'Text(text: "hi", fontSize: 16.0)');
    });

    test('Column with children list — recurses', () async {
      final r = t.translate(
        await parseExpressionForTest(
          "Column(children: [Text('a'), Text('b')])",
        ),
      );
      expect(r.issues, isEmpty);
      expect(
        r.dsl,
        'Column(children: [Text(text: "a"), Text(text: "b")])',
      );
    });

    test('Column with enum mainAxisAlignment', () async {
      final r = t.translate(
        await parseExpressionForTest(
          'Column(mainAxisAlignment: MainAxisAlignment.center, children: [])',
        ),
      );
      expect(r.issues, isEmpty);
      expect(
        r.dsl,
        'Column(mainAxisAlignment: "center", children: [])',
      );
    });

    test('rejects unknown widget', () async {
      final r = t.translate(
        await parseExpressionForTest('NotAWidget()'),
      );
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.unknownWidget),
      );
    });

    test('rejects unknown property name', () async {
      final r = t.translate(
        await parseExpressionForTest("Text('hi', notARealProp: 1)"),
      );
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.unknownProperty),
      );
    });

    test('emits unknownProperty when too many positional args', () async {
      // Text has 1 positional-marked property (`text`); pass 2 positionals
      // to exceed it.
      final r = t.translate(
        await parseExpressionForTest("Text('hello', 'extra')"),
      );
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.unknownProperty),
      );
    });

    test(
        'positional args target positional-marked props, '
        'not declaration-order props', () async {
      // Icon-shape regression: a property declared before the positional-
      // marked one (e.g. `size` ahead of `iconCodepoint`) must not absorb
      // the positional slot, or the same `size:` named arg would emit a
      // duplicate key and fail rfwtxt parsing.
      final iconCatalog = catalogWith([
        entry(
          name: 'Icon',
          category: WidgetCategory.decoration,
          properties: [
            prop('size', PropertyType.real),
            prop('color', PropertyType.color),
            prop(
              'iconCodepoint',
              PropertyType.integer,
              required: true,
              positional: true,
            ),
          ],
        ),
      ]);
      final tr = ExpressionTranslator(
        catalog: iconCatalog,
        helpers: HelperRegistry(),
      );
      final r = tr.translate(
        await parseExpressionForTest(
          'Icon(0xe1d4, size: 38, color: 0xFFFFFFFF)',
        ),
      );
      expect(r.issues, isEmpty);
      expect(
        r.dsl,
        'Icon(iconCodepoint: 57812, size: 38.0, color: 4294967295)',
      );
    });

    test('coerces integer literals through ternary branches at numeric slots',
        () async {
      // A ternary's branches feed the same slot; a bare integer branch at a
      // `real` slot would be silently nulled by the runtime's strict double
      // decode if coercion only saw the assembled `switch` value.
      final iconCatalog = catalogWith([
        entry(
          name: 'Icon',
          category: WidgetCategory.decoration,
          properties: [prop('size', PropertyType.real)],
        ),
      ]);
      final tr = ExpressionTranslator(
        catalog: iconCatalog,
        helpers: HelperRegistry(),
      );
      final r = tr.translate(
        await parseExpressionForTest('Icon(size: true ? 38 : 24)'),
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, 'Icon(size: switch true { true: 38.0, false: 24.0 })');
    });

    test('coerces nested ternary branches at numeric slots', () async {
      final iconCatalog = catalogWith([
        entry(
          name: 'Icon',
          category: WidgetCategory.decoration,
          properties: [prop('size', PropertyType.real)],
        ),
      ]);
      final tr = ExpressionTranslator(
        catalog: iconCatalog,
        helpers: HelperRegistry(),
      );
      final r = tr.translate(
        await parseExpressionForTest('Icon(size: true ? 38 : false ? 24 : 16)'),
      );
      expect(r.issues, isEmpty);
      expect(
        r.dsl,
        'Icon(size: switch true { true: 38.0, '
        'false: switch false { true: 24.0, false: 16.0 } })',
      );
    });

    test('ignores key: argument (super.key)', () async {
      // Text('hi', key: ValueKey('k')) — key is implicit-Flutter; codegen
      // ignores it. The test catalog has no 'key' property declared, but key
      // should NOT trigger unknownProperty.
      final r = t.translate(
        await parseExpressionForTest("Text('hi', key: ValueKey('k'))"),
      );
      // The key arg is filtered out; emitted DSL has no 'key:' segment.
      expect(r.dsl, contains('Text(text: "hi"'));
      expect(r.dsl, isNot(contains('key:')));
    });
  });

  group('root source state translation', () {
    final stateTranslator = ExpressionTranslator(
      catalog: catalogWith([
        entry(
          name: 'Text',
          properties: [
            prop('text', PropertyType.string, required: true),
          ],
        ),
        entry(
          name: 'GestureDetector',
          properties: [
            prop('onTap', PropertyType.event),
            prop('child', PropertyType.widget),
          ],
        ),
      ]),
      helpers: HelperRegistry(),
    );

    // Same catalog as `stateTranslator`, but with the build's paywall helpers
    // registered — so a `paywallPurchase(...)` action helper is recognised
    // exactly as the production build recognises it.
    final purchaseTranslator = ExpressionTranslator(
      catalog: catalogWith([
        entry(
          name: 'GestureDetector',
          properties: [
            prop('onTap', PropertyType.event),
            prop('child', PropertyType.widget),
          ],
        ),
      ]),
      helpers: HelperRegistry()..registerAll(paywallHelpers),
    );

    test(
        'a state-conditional paywallPurchase slot lowers to a switch INSIDE '
        'the purchase event — the fired slot follows state, never a frozen '
        'literal', () async {
      final expr = await parseExpressionForTest(
        'GestureDetector(onTap: '
        "paywallPurchase(slot: annual ? 'annual' : 'monthly'))",
      );

      final result = purchaseTranslator.translate(
        expr,
        rootState: [
          const CustomWidgetStateField(
            name: 'annual',
            isNumeric: false,
            initialValue: true,
          ),
        ],
      );

      expect(result.issues, isEmpty);
      expect(
        result.dsl,
        contains(
          'onTap: event "restage.purchase" '
          '{ slot: switch state.annual { true: "annual", false: "monthly" } }',
        ),
      );
    });

    test('lowers root State field reads to state references', () async {
      final expr = await parseExpressionForTest(
        "Text(text: annual ? 'Annual' : 'Monthly')",
      );

      final result = stateTranslator.translate(
        expr,
        rootState: [
          const CustomWidgetStateField(
            name: 'annual',
            isNumeric: false,
            initialValue: false,
          ),
        ],
      );

      expect(result.issues, isEmpty);
      expect(
        result.dsl,
        contains(
          'switch state.annual { true: "Annual", false: "Monthly" }',
        ),
      );
      expect(result.rootWidgetState, {'annual': 'false'});
    });

    test('lowers root State method tear-offs to set state handlers', () async {
      final expr = await parseExpressionForTest(
        'GestureDetector(onTap: toggle)',
      );

      final result = stateTranslator.translate(
        expr,
        rootState: [
          const CustomWidgetStateField(
            name: 'annual',
            isNumeric: false,
            initialValue: false,
          ),
        ],
        rootEventHandlers: {
          'toggle': const SetStateBoolFlip(fieldName: 'annual'),
        },
      );

      expect(result.issues, isEmpty);
      expect(
        result.dsl,
        contains(
          'onTap: set state.annual = switch state.annual '
          '{ true: false, false: true }',
        ),
      );
    });

    test('rejects root widget field reads instead of lowering to args',
        () async {
      final expr = await parseExpressionForTest('Text(text: widget.label)');

      final result = stateTranslator.translate(
        expr,
        rootState: [
          const CustomWidgetStateField(
            name: 'annual',
            isNumeric: false,
            initialValue: false,
          ),
        ],
      );

      expect(result.dsl, isNot(contains('args.label')));
      expect(
        result.issues.map((issue) => issue.code),
        contains(IssueCode.stateShapeUnsupported),
      );
      expect(
        result.issues.single.message,
        allOf(
          contains('Root source State.build() cannot read widget.label'),
          contains('no args.label binding to emit'),
        ),
      );
    });

    test('does not leak root state or handlers between translations', () async {
      final stateful = await parseExpressionForTest(
        'GestureDetector(onTap: toggle, child: Text(text: annual))',
      );
      final stateless = await parseExpressionForTest(
        'GestureDetector(onTap: toggle, child: Text(text: annual))',
      );

      final withState = stateTranslator.translate(
        stateful,
        rootState: [
          const CustomWidgetStateField(
            name: 'annual',
            isNumeric: false,
            initialValue: false,
          ),
        ],
        rootEventHandlers: {
          'toggle': const SetStateBoolFlip(fieldName: 'annual'),
        },
      );
      final withoutState = stateTranslator.translate(stateless);

      expect(withState.issues, isEmpty);
      expect(withState.dsl, contains('state.annual'));
      expect(withoutState.dsl, isNot(contains('state.annual')));
      expect(withoutState.dsl, isNot(contains('set state.annual')));
      expect(withoutState.issues, isNotEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // Helper-call recognition tests.
  // These tests inline stub helper-function declarations so that the analyzer
  // resolves the calls to the `package:restage_codegen` library URI, which
  // the test-local HelperRegistry entries are registered under.
  // -------------------------------------------------------------------------

  group('helper call translation', () {
    final tHelpers = ExpressionTranslator(
      catalog: kEmptyCatalog,
      helpers: HelperRegistry()..registerAll(_testHelpers),
    );

    test('paywallEvent("restore") → event "restore" {}', () async {
      // The stub declaration ensures the analyzer resolves the call to
      // `package:restage_codegen/lib/_expr_probe.dart`.
      const source = '''
        void paywallEvent(String name, {Object? args}) {}
        Object x() => paywallEvent("restore");
      ''';
      final expr = await parseExpressionFromSourceForTest(source);
      final r = tHelpers.translate(expr);
      expect(r.issues, isEmpty);
      expect(r.dsl, 'event "restore" {}');
    });

    test(
        'paywallPurchase(slot: "pro") → event "restage.purchase" { slot: ... }',
        () async {
      const source = '''
        void paywallPurchase({String? slot, String? productId}) {}
        Object x() => paywallPurchase(slot: "pro");
      ''';
      final expr = await parseExpressionFromSourceForTest(source);
      final r = tHelpers.translate(expr);
      expect(r.issues, isEmpty);
      expect(r.dsl, 'event "restage.purchase" { slot: "pro" }');
    });

    test('paywallPriceFor(slot: "basic") → data.products.basic.localizedPrice',
        () async {
      const source = '''
        String paywallPriceFor({String? slot, String? productId}) => "";
        Object x() => paywallPriceFor(slot: "basic");
      ''';
      final expr = await parseExpressionFromSourceForTest(source);
      final r = tHelpers.translate(expr);
      expect(r.issues, isEmpty);
      expect(r.dsl, 'data.products.basic.localizedPrice');
    });

    test('unregistered free function falls through to catalog lookup',
        () async {
      // A call to a function not in the helper registry routes to catalog
      // construction and emits unknownWidget (no matching catalog entry).
      final r = tHelpers.translate(
        await parseExpressionForTest('NotAHelper()'),
      );
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.unknownWidget),
      );
    });

    test(
        'paywallPurchase with both slot: and productId: surfaces as '
        'unrecognizedMethodCall', () async {
      // Both slot and productId provided → translate() throws ArgumentError.
      // Confirm the catch path surfaces an Issue rather than propagating.
      const source = '''
        void paywallPurchase({String? slot, String? productId}) {}
        Object x() => paywallPurchase(slot: "a", productId: "b");
      ''';
      final expr = await parseExpressionFromSourceForTest(source);
      final r = tHelpers.translate(expr);
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.unrecognizedMethodCall),
      );
    });

    test('findByNameOnly fires when element is null (unresolved AST)',
        () async {
      // parseExpressionForTest returns an unresolved AST, so element on
      // method names is null and findByNameOnly fires.
      final r = tHelpers.translate(
        await parseExpressionForTest("paywallEvent('hello')"),
      );
      // The unresolved path hits findByNameOnly; paywallEvent is in the
      // registry → should translate without issues.
      expect(r.issues, isEmpty);
      expect(r.dsl, 'event "hello" {}');
    });
  });

  // -------------------------------------------------------------------------
  // String interpolation tests.
  // -------------------------------------------------------------------------

  group('string interpolation', () {
    final tInterp = ExpressionTranslator(
      catalog: _textRichCatalog(),
      helpers: HelperRegistry()..registerAll(_testHelpers),
    );
    const trialLabel = CustomWidgetStateField(
      name: 'trialLabel',
      isNumeric: false,
      initialValue: '7 days free',
    );

    // No-catalog translator for rejection-only tests.
    final tReject = ExpressionTranslator(
      catalog: kEmptyCatalog,
      helpers: HelperRegistry(),
    );

    test('rejects non-helper identifier in interpolation', () async {
      // The anonymous variable reference doesn't resolve to any helper.
      final r = tReject.translate(
        await parseExpressionForTest(r"'hello ${42}'"),
      );
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.unsupportedInterpolation),
      );
    });

    test('rejects unresolved call in interpolation', () async {
      // `unknownFn()` is not declared anywhere — resolves to null element.
      final r = tReject.translate(
        await parseExpressionForTest(r"'price: ${unknownFn()}'"),
      );
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.unsupportedInterpolation),
      );
    });

    test('rejects voidCallback helper inside interpolation', () async {
      // paywallEvent returns voidCallback, not a String — must be rejected.
      const source = r'''
        void paywallEvent(String name, {Object? args}) {}
        String paywallPriceFor({String? slot, String? productId}) => "";
        Object x() => Text(text: 'action: ${paywallEvent("restore")}');
      ''';
      final expr = await parseExpressionFromSourceForTest(source);
      final r = tInterp.translate(expr);
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.unsupportedHelperPosition),
      );
    });

    test('pure single paywallPriceFor in Text drops sentinel', () async {
      const source = r'''
        String paywallPriceFor({String? slot, String? productId}) => "";
        Object x() => Text(text: '${paywallPriceFor(slot: "pro")}');
      ''';
      final expr = await parseExpressionFromSourceForTest(source);
      final r = tInterp.translate(expr);
      expect(r.issues, isEmpty);
      expect(r.dsl, 'Text(text: data.products.pro.localizedPrice)');
    });

    test('interpolation with literal segments lowers to TextRich spans',
        () async {
      const source = r'''
        String paywallPriceFor({String? slot, String? productId}) => "";
        Object x() => Text(text: 'Only ${paywallPriceFor(slot: "pro")}/mo');
      ''';
      final expr = await parseExpressionFromSourceForTest(source);
      final r = tInterp.translate(expr);
      expect(r.issues, isEmpty);
      expect(
        r.dsl,
        'TextRich(textSpan: { children: [{ text: "Only " }, '
        '{ text: data.products.pro.localizedPrice }, { text: "/mo" }] })',
      );
    });

    test('styled interpolated price string carries Text props to TextRich',
        () async {
      const source = r'''
        String paywallPriceFor({String? slot, String? productId}) => "";
        Object x() => Text(
          text: 'Only ${paywallPriceFor(slot: "ent")}/month',
          color: Color(0xFF111111),
          fontSize: 18.0,
          fontWeight: FontWeight.w700,
        );
      ''';
      final expr = await parseExpressionFromSourceForTest(source);
      final r = tInterp.translate(expr);
      expect(r.issues, isEmpty);
      expect(
        r.dsl,
        'TextRich(textSpan: { children: [{ text: "Only " }, '
        '{ text: data.products.ent.localizedPrice }, { text: "/month" }] }, '
        'color: 0xFF111111, fontSize: 18.0, fontWeight: "w700")',
      );
    });

    test('interpolated state ref lowers to TextRich spans', () async {
      final expr = await parseExpressionForTest(
        r"Text(text: '${trialLabel} remaining')",
      );
      final r = tInterp.translate(expr, rootState: [trialLabel]);
      expect(r.issues, isEmpty);
      expect(
        r.dsl,
        'TextRich(textSpan: { children: [{ text: state.trialLabel }, '
        '{ text: " remaining" }] })',
      );
    });

    test('interpolated Text with uncarried prop defers whole rewrite',
        () async {
      const source = r'''
        String paywallPriceFor({String? slot, String? productId}) => "";
        Object x() => Text(
          text: 'Only ${paywallPriceFor(slot: "pro")}/mo',
          semanticsLabel: 'price',
        );
      ''';
      final expr = await parseExpressionFromSourceForTest(source);
      final r = tInterp.translate(expr);
      expect(r.dsl, isEmpty);
      expect(
        r.issues.map((issue) => issue.code),
        contains(IssueCode.unsupportedHelperPosition),
      );
      expect(
        r.issues.map((issue) => issue.message).join('\n'),
        contains('semanticsLabel'),
      );
    });

    test('single helper interpolation keeps plain Text fast path', () async {
      const source = r'''
        String paywallPriceFor({String? slot, String? productId}) => "";
        Object x() => Text(
          text: '${paywallPriceFor(slot: "ent")}',
          fontSize: 18.0,
        );
      ''';
      final expr = await parseExpressionFromSourceForTest(source);
      final r = tInterp.translate(expr);
      expect(r.issues, isEmpty);
      expect(
        r.dsl,
        'Text(text: data.products.ent.localizedPrice, fontSize: 18.0)',
      );
    });
  });

  group('Text.rich inline-span emission', () {
    final textRichTranslator = ExpressionTranslator(
      catalog: _textRichCatalog(),
      helpers: HelperRegistry()..registerAll(_testHelpers),
    );
    const annualBilling = CustomWidgetStateField(
      name: 'annualBilling',
      isNumeric: false,
      initialValue: true,
    );

    test('Notion price row emits a structured inlineSpan tree', () async {
      final expr = await parseExpressionForTest('''
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: paywallPriceFor(
                  slot: annualBilling ? 'plus_annual' : 'plus_monthly',
                ),
                style: const TextStyle(
                  color: Color(0xFF191918),
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const TextSpan(
                text: '  per member / month',
                style: TextStyle(
                  color: Color(0xFF787774),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        )
      ''');

      final r = textRichTranslator.translate(
        expr,
        rootState: [annualBilling],
      );

      expect(r.issues, isEmpty);
      expect(
        r.dsl,
        'TextRich(textSpan: { children: [{ text: switch state.annualBilling '
        '{ true: data.products.plus_annual.localizedPrice, '
        'false: data.products.plus_monthly.localizedPrice }, '
        'style: { color: 0xFF191918, fontSize: 24.0, '
        'fontWeight: "w700" } }, { text: "  per member / month", '
        'style: { color: 0xFF787774, fontSize: 13.0 } }] })',
      );
    });

    test('mixed-style legal paragraph emits nested span styles', () async {
      final expr = await parseExpressionForTest('''
        Text.rich(
          TextSpan(
            text: 'By continuing, you agree to ',
            children: [
              const TextSpan(
                text: 'Purchaser Terms',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                ),
              ),
              const TextSpan(text: ' and '),
              const TextSpan(
                text: 'Privacy Policy',
                style: TextStyle(decoration: TextDecoration.overline),
              ),
            ],
          ),
        )
      ''');

      final r = textRichTranslator.translate(expr);

      expect(r.issues, isEmpty);
      expect(
        r.dsl,
        'TextRich(textSpan: { text: "By continuing, you agree to ", '
        'children: [{ text: "Purchaser Terms", '
        'style: { fontWeight: "w600", decoration: "underline" } }, '
        '{ text: " and " }, { text: "Privacy Policy", '
        'style: { decoration: "overline" } }] })',
      );
    });

    test('TextSpan(recognizer:) defers loud instead of dropping the prop',
        () async {
      final expr = await parseExpressionForTest('''
        Text.rich(
          TextSpan(
            text: 'Purchaser Terms',
            recognizer: TapGestureRecognizer(),
          ),
        )
      ''');

      final r = textRichTranslator.translate(expr);

      expect(r.dsl, isEmpty);
      expect(
        r.issues.where((issue) => !issue.code.isInformational),
        isNotEmpty,
      );
      expect(
        r.issues.map((issue) => issue.message).join('\n'),
        contains('recognizer'),
      );
    });

    test('customer TextSpan look-alike defers instead of emitting', () async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/widgets.dart' hide TextSpan;

        class TextSpan {
          const TextSpan({this.text});
          final String? text;
        }

        Object x() => Text.rich(const TextSpan(text: 'customer span'));
        ''',
        rootPackage: 'apps_examples',
      );

      final r = textRichTranslator.translate(expr);

      expect(r.dsl, isEmpty);
      expect(
        r.issues.where((issue) => !issue.code.isInformational),
        isNotEmpty,
      );
      expect(
        r.issues.map((issue) => issue.message).join('\n'),
        contains('TextSpan'),
      );
      expect(
        r.issues.map((issue) => issue.message).join('\n'),
        contains('package:flutter'),
      );
    });

    test('over-deep span tree defers at build time', () async {
      final expr = await parseExpressionForTest(
        'Text.rich(${_nestedTextSpanSource(33)})',
      );

      final r = textRichTranslator.translate(expr);

      expect(r.dsl, isEmpty);
      expect(
        r.issues.where((issue) => !issue.code.isInformational),
        isNotEmpty,
      );
      expect(
        r.issues.map((issue) => issue.message).join('\n'),
        allOf(contains('TextSpan'), contains('kMaxInlineSpanDepth')),
      );
    });

    test('per-value conditional span text lowers to a switch', () async {
      final expr = await parseExpressionForTest('''
        Text.rich(
          TextSpan(text: annualBilling ? 'Annual' : 'Monthly'),
        )
      ''');

      final r = textRichTranslator.translate(
        expr,
        rootState: [annualBilling],
      );

      expect(r.issues, isEmpty);
      expect(
        r.dsl,
        'TextRich(textSpan: { text: switch state.annualBilling '
        '{ true: "Annual", false: "Monthly" } })',
      );
    });
  });

  // -------------------------------------------------------------------------
  // splitTopLevelCommas unit tests.
  // -------------------------------------------------------------------------

  group('splitTopLevelCommas', () {
    test('splits top-level commas', () {
      expect(
        ExpressionTranslator.splitTopLevelCommas('a, b, c'),
        ['a', 'b', 'c'],
      );
    });

    test('respects parentheses depth', () {
      expect(
        ExpressionTranslator.splitTopLevelCommas('a(1, 2), b'),
        ['a(1, 2)', 'b'],
      );
    });

    test('respects bracket depth', () {
      expect(
        ExpressionTranslator.splitTopLevelCommas('[1, 2, 3], x'),
        ['[1, 2, 3]', 'x'],
      );
    });

    test('respects quoted strings with commas', () {
      expect(
        ExpressionTranslator.splitTopLevelCommas('"a, b", "c, d"'),
        ['"a, b"', '"c, d"'],
      );
    });

    test('handles escaped quotes inside strings', () {
      expect(
        ExpressionTranslator.splitTopLevelCommas(r'"escaped \"quote\"", next'),
        [r'"escaped \"quote\""', 'next'],
      );
    });

    test('empty input returns empty list', () {
      expect(
        ExpressionTranslator.splitTopLevelCommas(''),
        <String>[],
      );
    });

    test('trailing comma is ignored (no empty trailing element)', () {
      expect(
        ExpressionTranslator.splitTopLevelCommas('a,'),
        ['a'],
      );
    });

    test('escaped backslash before closing quote is not an escape', () {
      // r'"a\\"' is the 4-char string `a\` followed by closing `"`.
      // The `\\` escapes the backslash; the `"` is a real string boundary.
      expect(
        ExpressionTranslator.splitTopLevelCommas(r'"a\\", next'),
        [r'"a\\"', 'next'],
      );
    });

    test('multiple consecutive backslashes', () {
      // r'"a\\\\"' is `a\\` (two real backslashes) and a closing `"`.
      // 4 backslashes = even = real boundary.
      expect(
        ExpressionTranslator.splitTopLevelCommas(r'"a\\\\", next'),
        [r'"a\\\\"', 'next'],
      );
    });
  });

  // -------------------------------------------------------------------------
  // Regression: locationOf format / int overflow.
  // -------------------------------------------------------------------------

  group('regression: _locationOf format', () {
    test('issue location starts with sourcePath when lineInfo is provided',
        () async {
      // Trigger any issue (unsupported expression type) while providing a
      // sourcePath and a minimal LineInfo. Assert that the location string
      // starts with the given path (file:line:column format) rather than
      // containing only a raw byte offset.
      final expr = await parseExpressionForTest('someVar.toUpper()');
      final r = translator.translate(
        expr,
        sourcePath: 'lib/paywalls/foo.dart',
        lineInfo: LineInfo([0]),
      );
      expect(r.issues, isNotEmpty);
      expect(r.issues.first.location, startsWith('lib/paywalls/foo.dart:'));
    });

    test('issue location falls back to offset when lineInfo is null', () async {
      final expr = await parseExpressionForTest('someVar.toUpper()');
      final r = translator.translate(expr, sourcePath: 'lib/paywalls/foo.dart');
      expect(r.issues, isNotEmpty);
      // Without lineInfo the fallback is `path (offset N)`.
      expect(
        r.issues.first.location,
        contains('lib/paywalls/foo.dart'),
      );
      expect(r.issues.first.location, isNot(contains(':')));
    });
  });

  group('regression: integer literal overflow', () {
    test('emits integerLiteralOverflow for out-of-range int literal', () async {
      // 9999999999999999999 exceeds int64 max (9223372036854775807), causing
      // IntegerLiteral.value to be null in the Dart analyzer.
      final r = translator.translate(
        await parseExpressionForTest('9999999999999999999'),
      );
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.integerLiteralOverflow),
      );
    });
  });

  group('native structured-type decomposition', () {
    // The synthetic catalog mounts its decompose-recipe identities AND its
    // value-type stubs (Container/BoxDecoration/Color/…) at the non-framework
    // probe URI, so this translator declares that URI as part of its framework
    // set via the `forTesting` seam — the production value-substitution gate
    // would otherwise (correctly) defer those resolved non-framework stubs.
    final t = ExpressionTranslator.forTesting(
      catalog: _nativeExpressionCatalog(),
      helpers: HelperRegistry(),
      frameworkLibraryPredicate: syntheticFrameworkLibrary,
    );

    test('production translator source has no bridge-field dependency', () {
      final source =
          File('lib/src/expression_translator.dart').readAsStringSync();
      expect(source, isNot(contains('toConsumerShape')));
      expect(source, isNot(contains('legacyStructuredType')));
      expect(source, isNot(contains('legacyFlatProperties')));
      expect(source, isNot(contains('factoryConvention')));
    });

    test('matches constructors by native identity and fieldMappings', () async {
      final r = t.translate(
        await parseExpressionFromSourceForTest('''
          $_nativeExpressionSourceStubs
          Object x() => Container(
            decoration: BoxDecoration(color: Color(0xFF112233)),
          );
        '''),
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, 'Container(backgroundColor: 0xFF112233)');
    });

    test('a compatible theme read through a decompose field passes clean',
        () async {
      final r = t.translate(
        await parseExpressionFromSourceForTest('''
          $_nativeExpressionSourceStubs
          Object x(context) => Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
            ),
          );
        '''),
      );
      expect(r.issues, isEmpty);
      expect(
        r.dsl,
        'Container(backgroundColor: data.theme.colorScheme.primary)',
      );
    });

    test('a mismatched theme read through a decompose parameter is caught',
        () async {
      // `borderRadius` lowers through a constructor-parameter mapping to a
      // length-typed flat property; a colour-kind theme read cannot feed it.
      final r = t.translate(
        await parseExpressionFromSourceForTest('''
          $_nativeExpressionSourceStubs
          Object x(context) => Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(
                Theme.of(context).colorScheme.primary,
              ),
            ),
          );
        '''),
      );
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.propertyValueTypeMismatch),
      );
    });

    test(
        'coerces ternary integer branches bound through a decompose '
        'parameter', () async {
      // The bound radius becomes the length-typed flat property's value, so
      // each ternary branch is coerced to a double literal like a direct
      // value would be.
      final r = t.translate(
        await parseExpressionFromSourceForTest('''
          $_nativeExpressionSourceStubs
          Object x() => Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(true ? 12 : 8),
            ),
          );
        '''),
      );
      expect(r.issues, isEmpty);
      expect(
        r.dsl,
        'Container(borderRadius: switch true { true: 12.0, false: 8.0 })',
      );
    });

    test(
      'reverses constructVariant through positional FactoryParameter metadata',
      () async {
        final r = t.translate(
          await parseExpressionFromSourceForTest('''
            $_nativeExpressionSourceStubs
            Object x() => Container(
              decoration: BoxDecoration(
                color: Color(0xFFAA0000),
                borderRadius: BorderRadius.circular(12),
              ),
            );
          '''),
        );
        expect(r.issues, isEmpty);
        expect(
          r.dsl,
          'Container(backgroundColor: 0xFFAA0000, borderRadius: 12.0)',
        );
      },
    );

    test('TransformNullPolicy.error diagnoses a null bound argument', () async {
      final errorTranslator = ExpressionTranslator.forTesting(
        catalog: _nativeExpressionCatalog(
          circularRadiusNullPolicy: TransformNullPolicy.error,
        ),
        helpers: HelperRegistry(),
        frameworkLibraryPredicate: syntheticFrameworkLibrary,
      );
      final r = errorTranslator.translate(
        await parseExpressionFromSourceForTest('''
          $_nativeExpressionSourceStubs
          Object x() => Container(
            decoration: BoxDecoration(
              color: Color(0xFFAA0000),
              borderRadius: BorderRadius.circular(null),
            ),
          );
        '''),
      );
      expect(
        r.issues.map((i) => i.message),
        contains(contains('does not allow null')),
      );
    });

    test('TransformNullPolicy.emitNull keeps a null bound argument', () async {
      final emitNullTranslator = ExpressionTranslator.forTesting(
        frameworkLibraryPredicate: syntheticFrameworkLibrary,
        catalog: _nativeExpressionCatalog(
          circularRadiusNullPolicy: TransformNullPolicy.emitNull,
        ),
        helpers: HelperRegistry(),
      );
      final r = emitNullTranslator.translate(
        await parseExpressionFromSourceForTest('''
          $_nativeExpressionSourceStubs
          Object x() => Container(
            decoration: BoxDecoration(
              color: Color(0xFFAA0000),
              borderRadius: BorderRadius.circular(null),
            ),
          );
        '''),
      );
      expect(
        r.issues.map((i) => i.message),
        isNot(contains(contains('does not allow null'))),
      );
      expect(r.dsl, contains('borderRadius: null'));
    });

    test('preserves projectList(identity) list values', () async {
      final r = t.translate(
        await parseExpressionFromSourceForTest('''
          $_nativeExpressionSourceStubs
          Object x() => Container(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Color(0x668B5CF6),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ],
            ),
          );
        '''),
      );
      expect(r.issues, isEmpty);
      expect(
        r.dsl,
        'Container(boxShadow: [{color: 0x668B5CF6, blurRadius: 24.0, '
        'offset: {x: 0.0, y: 8.0}}])',
      );
    });

    test('matches owning-widget static factories by native receiver metadata',
        () async {
      final r = t.translate(
        await parseExpressionFromSourceForTest('''
          $_nativeExpressionSourceStubs
          Object x() => FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Color(0xFF112233),
              padding: EdgeInsets.all(8),
            ),
          );
        '''),
      );
      expect(r.issues, isEmpty);
      expect(
        r.dsl,
        'FilledButton(backgroundColor: 0xFF112233, '
        'padding: [8.0, 8.0, 8.0, 8.0])',
      );
    });

    test('decomposes supported button ShapeBorder variants', () async {
      final cases = <String, String>{
        '''
          RoundedRectangleBorder(
            side: BorderSide(color: Color(0xFFAA0000), width: 2),
            borderRadius: BorderRadius.circular(14),
          )
        ''': 'FilledButton(shape: {type: "rounded", '
                'side: {color: 0xFFAA0000, width: 2.0}, borderRadius: 14.0})',
        '''
          RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(16),
          )
        ''': 'FilledButton(shape: {type: "roundedSuperellipse", '
                'borderRadius: 16.0})',
        'CircleBorder(eccentricity: 0.5)':
            'FilledButton(shape: {type: "circle", eccentricity: 0.5})',
        'StadiumBorder()': 'FilledButton(shape: {type: "stadium"})',
        '''
          ContinuousRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          )
        ''': 'FilledButton(shape: {type: "continuous", borderRadius: 4.0})',
        '''
          BeveledRectangleBorder(
            side: BorderSide(style: BorderStyle.none),
          )
        ''': 'FilledButton(shape: {type: "beveled", '
                'side: {style: "none"}})',
        '''
          LinearBorder(
            start: LinearBorderEdge(size: 0.5),
            end: LinearBorderEdge(alignment: -1),
          )
        ''': 'FilledButton(shape: {type: "linear", '
                'start: {size: 0.5}, end: {alignment: -1.0}})',
        'LinearBorder.bottom(size: 0.75, alignment: 1)':
            'FilledButton(shape: {type: "linear", '
                'bottom: {size: 0.75, alignment: 1.0}})',
        'StarBorder(points: 6, innerRadiusRatio: 0.5)':
            'FilledButton(shape: {type: "star", points: 6.0, '
                'innerRadiusRatio: 0.5})',
        'StarBorder.polygon(sides: 5, rotation: 15)':
            'FilledButton(shape: {type: "polygon", sides: 5.0, '
                'rotation: 15.0})',
      };

      for (final entry in cases.entries) {
        final r = t.translate(
          await parseExpressionFromSourceForTest('''
            $_nativeExpressionSourceStubs
            Object x() => FilledButton(
              style: FilledButton.styleFrom(shape: ${entry.key}),
            );
          '''),
        );
        expect(r.issues, isEmpty, reason: entry.key);
        expect(r.dsl, entry.value, reason: entry.key);
      }
    });

    test('decomposes TextStyle structured values and constructor parameters',
        () async {
      final r = t.translate(
        await parseExpressionFromSourceForTest('''
          $_nativeExpressionSourceStubs
          Object x() => Text(
            text: "Hi",
            style: TextStyle(
              inherit: false,
              fontStyle: FontStyle.italic,
              locale: Locale.fromSubtags(
                languageCode: 'zh',
                scriptCode: 'Hant',
                countryCode: 'TW',
              ),
              foreground: Paint()..color = Color(0xFF112233),
              shadows: [
                Shadow(
                  color: Color(0x55000000),
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
              fontFeatures: [
                FontFeature.enable('kern'),
                FontFeature('liga', 0),
              ],
              fontVariations: [FontVariation('wght', 700)],
              decoration: TextDecoration.combine([
                TextDecoration.underline,
                TextDecoration.overline,
              ]),
              fontFamilyFallback: ['Inter', 'SF Pro'],
              package: 'brand_fonts',
            ),
          );
        '''),
      );
      expect(r.issues, isEmpty);
      expect(
        r.dsl,
        'Text(text: "Hi", inherit: false, fontStyle: "italic", '
        'locale: "zh-Hant-TW", foreground: {color: 0xFF112233}, '
        'shadows: [{color: 0x55000000, blurRadius: 4.0, '
        'offset: {x: 0.0, y: 2.0}}], '
        'fontFeatures: [{feature: "kern", value: 1}, '
        '{feature: "liga", value: 0}], '
        'fontVariations: [{axis: "wght", value: 700.0}], '
        'decoration: ["underline", "overline"], '
        'fontFamilyFallback: ["Inter", "SF Pro"], '
        'fontPackage: "brand_fonts")',
      );
    });

    test('diagnoses unsupported Paint setters instead of dropping them',
        () async {
      final r = t.translate(
        await parseExpressionFromSourceForTest('''
          $_nativeExpressionSourceStubs
          Object x() => Text(
            text: "Hi",
            style: TextStyle(
              foreground: Paint()..style = PaintingStyle.stroke,
            ),
          );
        '''),
      );
      expect(r.dsl, 'Text(text: "Hi")');
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.unrecognizedMethodCall),
      );
      expect(
        r.issues.map((i) => i.message),
        contains(contains('Paint.style is not supported')),
      );
    });

    test('diagnoses unsupported custom button shapes instead of dropping them',
        () async {
      final r = t.translate(
        await parseExpressionFromSourceForTest('''
          $_nativeExpressionSourceStubs
          class CustomBorder extends OutlinedBorder {
            const CustomBorder();
          }

          Object x() => FilledButton(
            style: FilledButton.styleFrom(shape: CustomBorder()),
          );
        '''),
      );
      expect(r.dsl, 'FilledButton()');
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.unrecognizedMethodCall),
      );
      expect(
        r.issues.map((i) => i.message),
        contains(contains('Unsupported ShapeBorder/OutlinedBorder value')),
      );
    });

    test('diagnoses unmapped native fields instead of dropping them', () async {
      final r = t.translate(
        await parseExpressionFromSourceForTest('''
          $_nativeExpressionSourceStubs
          Object x() => Container(
            decoration: BoxDecoration(
              color: Color(0xFFAA0000),
              gradient: LinearGradient(colors: [Color(0xFF000000)]),
            ),
          );
        '''),
      );
      expect(r.dsl, 'Container(backgroundColor: 0xFFAA0000)');
      expect(r.issues.map((i) => i.code), contains(IssueCode.unknownProperty));
      expect(
        r.issues.map((i) => i.message),
        contains(contains("Native decomposition field 'gradient'")),
      );
    });

    test('diagnoses unknown native arguments instead of dropping them',
        () async {
      final r = t.translate(
        await parseExpressionFromSourceForTest('''
          $_nativeExpressionSourceStubs
          Object x() => Container(
            decoration: BoxDecoration(foo: 1),
          );
        '''),
      );
      expect(r.dsl, 'Container()');
      expect(r.issues.map((i) => i.code), contains(IssueCode.unknownProperty));
      expect(
        r.issues.map((i) => i.message),
        contains(contains("Native decomposition argument 'foo'")),
      );
    });

    test('diagnoses relevant recipes missing native construction metadata',
        () async {
      final translator = ExpressionTranslator.forTesting(
        catalog: _nativeExpressionCatalog(omitContainerConstruction: true),
        helpers: HelperRegistry(),
        frameworkLibraryPredicate: syntheticFrameworkLibrary,
      );
      final r = translator.translate(
        await parseExpressionFromSourceForTest('''
          $_nativeExpressionSourceStubs
          Object x() => Container(
            decoration: BoxDecoration(color: Color(0xFF112233)),
          );
        '''),
      );

      expect(r.dsl, 'Container()');
      expect(
        r.issues.map((i) => i.message),
        contains(contains('missing native construction metadata')),
      );
      expect(
        r.issues.map((i) => i.message),
        isNot(contains(contains("Property 'decoration' is not declared"))),
      );
    });

    test('non-recipe structured arg falls through to regular property lookup',
        () async {
      final r = t.translate(
        await parseExpressionFromSourceForTest('''
          $_nativeExpressionSourceStubs
          class Foo { const Foo(); }
          Object x() => Container(decoration: Foo());
        '''),
      );
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.unknownProperty),
      );
    });
  });

  group('resolved-type matching against flutterType', () {
    // Two catalog entries share the same name. With resolved-type
    // matching, the analyzer's resolved class identifier picks the
    // entry whose flutterType matches; without it (name-only), the
    // priority-ordered first entry would win and fail the test.
    final shadowingCatalog = catalogWith([
      entry(
        name: 'FilledButton',
        flutterType: 'package:other_pkg/foo.dart#FilledButton',
        properties: [
          prop('label', PropertyType.string, required: true, positional: true),
        ],
      ),
      entry(
        name: 'FilledButton',
        flutterType: 'package:restage_codegen/_expr_probe.dart#FilledButton',
        properties: [
          prop('text', PropertyType.string, required: true, positional: true),
        ],
      ),
    ]);
    final t = ExpressionTranslator(
      catalog: shadowingCatalog,
      helpers: HelperRegistry(),
    );

    test('picks the entry whose flutterType matches the resolved type',
        () async {
      // Inline class declaration so the analyzer resolves FilledButton
      // to a class element under package:restage_codegen/_expr_probe.dart
      // — which matches the second catalog entry.
      const source = '''
        class FilledButton {
          const FilledButton({this.text});
          final String? text;
        }
        Object x() => FilledButton(text: 'go');
      ''';
      final expr = await parseExpressionFromSourceForTest(source);
      final r = t.translate(expr);
      expect(r.issues, isEmpty);
      // The second entry declares `text:`; the first declares `label:`.
      // A successful translation against the second entry confirms the
      // resolved-type path picked the right one.
      expect(r.dsl, 'FilledButton(text: "go")');
    });

    test('preserves named-constructor suffix in flutterType lookup', () async {
      final namedCtorCatalog = catalogWith([
        entry(
          name: 'ImageAsset',
          flutterType: 'package:restage_codegen/_expr_probe.dart#Image.asset',
          properties: [
            prop(
              'source',
              PropertyType.string,
              required: true,
              positional: true,
            ),
          ],
        ),
      ]);
      final tr = ExpressionTranslator(
        catalog: namedCtorCatalog,
        helpers: HelperRegistry(),
      );
      const source = '''
        class Image {
          const Image.asset(this.source);
          final String source;
        }
        Object x() => Image.asset('hero.png');
      ''';
      final expr = await parseExpressionFromSourceForTest(source);
      final r = tr.translate(expr);
      expect(r.issues, isEmpty);
      expect(r.dsl, 'ImageAsset(source: "hero.png")');
    });

    test('falls back to name-based lookup when resolved type is unavailable',
        () async {
      // parseExpressionForTest uses an unresolved AST — the analyzer
      // can't tie FilledButton to a class element. The lookup falls
      // back to name and picks the first catalog entry by priority,
      // which expects `label:`.
      final r = t.translate(await parseExpressionForTest("FilledButton('go')"));
      expect(r.issues, isEmpty);
      expect(r.dsl, 'FilledButton(label: "go")');
    });
  });

  group('recipe-path proof (translator recipe infrastructure)', () {
    test('the proof types route through the recipe table', () {
      expect(kTranslatorRecipes.containsKey('#Offset'), isTrue);
      expect(kTranslatorRecipes.containsKey('#Color'), isTrue);
      expect(kTranslatorRecipes.containsKey('#Color.fromARGB'), isTrue);
      expect(kTranslatorRecipes.containsKey('#Color.fromRGBO'), isTrue);
    });

    test('non-migrated types have no recipe — still hand-authored', () {
      expect(kTranslatorRecipes.containsKey('#EdgeInsets'), isFalse);
      expect(kTranslatorRecipes.containsKey('#BoxShadow'), isFalse);
      expect(kTranslatorRecipes.containsKey('#Border'), isFalse);
    });

    test('Color.fromRGBO accepts an integer opacity literal', () async {
      // The quantize kernel must accept a bare int opacity
      // (Color.fromRGBO(0, 0, 0, 1)) — opacity 1 -> alpha 255.
      final r = translator.translate(
        await parseExpressionForTest('Color.fromRGBO(0, 0, 0, 1)'),
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, '0xFF000000');
    });
  });
}

Catalog _textRichCatalog() {
  final textRef = _nativeRef('restage.core', 'w9100');
  final textRichRef = _nativeRef('restage.core', 'w9101');
  final textStyleRef = _nativeRef('restage.core', 's9100');
  final textStyleCtorRef = _nativeRef('restage.core', 'v9100');

  final textSpanProp = WireId('p9100');
  final textProp = WireId('p9101');
  final colorProp = WireId('p9102');
  final fontSizeProp = WireId('p9103');
  final fontWeightProp = WireId('p9104');
  final fontStyleProp = WireId('p9105');
  final decorationProp = WireId('p9106');

  final colorField = WireId('p9202');
  final fontSizeField = WireId('p9203');
  final fontWeightField = WireId('p9204');
  final fontStyleField = WireId('p9205');
  final decorationField = WireId('p9206');

  final fontStyleShape = _enumShape('FontStyle');
  final decorationShape =
      _scalarShape(PropertyType.textDecoration, symbol: 'TextDecoration');

  return Catalog(
    schemaVersion: kSupportedSchemaVersion,
    generatedAt: '1970-01-01T00:00:00Z',
    libraries: {
      WidgetLibrary.core: const LibraryInfo(version: '0.1.0'),
    },
    widgets: [
      WidgetEntry(
        wireId: textRichRef.wireId,
        name: 'TextRich',
        library: WidgetLibrary.core,
        category: WidgetCategory.decoration,
        description: '',
        flutterType: 'package:flutter/src/widgets/text.dart#Text.rich',
        childrenSlot: ChildrenSlot.none,
        fires: const [],
        properties: [
          _nativeProperty(
            wireId: textSpanProp,
            name: 'textSpan',
            type: PropertyType.inlineSpan,
          ),
          _nativeProperty(
            wireId: WireId('p9107'),
            name: 'color',
            type: PropertyType.color,
          ),
          _nativeProperty(
            wireId: WireId('p9108'),
            name: 'fontSize',
            type: PropertyType.length,
          ),
          _nativeProperty(
            wireId: WireId('p9109'),
            name: 'fontWeight',
            type: PropertyType.fontWeight,
          ),
          _nativeProperty(
            wireId: WireId('p9110'),
            name: 'fontStyle',
            type: PropertyType.enumValue,
            valueShape: fontStyleShape,
          ),
          _nativeProperty(
            wireId: WireId('p9111'),
            name: 'decoration',
            type: PropertyType.textDecoration,
            valueShape: decorationShape,
          ),
        ],
      ),
      WidgetEntry(
        wireId: textRef.wireId,
        name: 'Text',
        library: WidgetLibrary.core,
        category: WidgetCategory.decoration,
        description: '',
        flutterType: 'package:flutter/src/widgets/text.dart#Text',
        childrenSlot: ChildrenSlot.none,
        fires: const [],
        properties: [
          _nativeProperty(
            wireId: textProp,
            name: 'text',
            type: PropertyType.string,
          ),
          _nativeProperty(
            wireId: colorProp,
            name: 'color',
            type: PropertyType.color,
          ),
          _nativeProperty(
            wireId: fontSizeProp,
            name: 'fontSize',
            type: PropertyType.length,
          ),
          _nativeProperty(
            wireId: fontWeightProp,
            name: 'fontWeight',
            type: PropertyType.fontWeight,
          ),
          _nativeProperty(
            wireId: fontStyleProp,
            name: 'fontStyle',
            type: PropertyType.enumValue,
            valueShape: fontStyleShape,
          ),
          _nativeProperty(
            wireId: decorationProp,
            name: 'decoration',
            type: PropertyType.textDecoration,
            valueShape: decorationShape,
          ),
          _nativeProperty(
            wireId: WireId('p9112'),
            name: 'semanticsLabel',
            type: PropertyType.string,
          ),
        ],
        decomposes: [
          DecompositionRecipe(
            structuredRef: textStyleRef,
            flatProperties: const {},
            targetArg: 'style',
            construction: FactoryInvocation(
              variantRef: textStyleCtorRef,
              receiver: const ResultStructuredTypeReceiver(),
            ),
            fieldMappings: [
              _nativeFieldMapping(colorField, colorProp),
              _nativeFieldMapping(fontSizeField, fontSizeProp),
              _nativeFieldMapping(fontWeightField, fontWeightProp),
              _nativeFieldMapping(fontStyleField, fontStyleProp),
              _nativeFieldMapping(decorationField, decorationProp),
            ],
          ),
        ],
      ),
    ],
    structuredTypes: [
      StructuredEntry(
        wireId: textStyleRef.wireId,
        name: 'TextStyle',
        library: WidgetLibrary.core,
        description: '',
        sourceType: 'package:flutter/src/painting/text_style.dart#TextStyle',
        fields: [
          _nativeField(
            wireId: colorField,
            name: 'color',
            type: PropertyType.color,
          ),
          _nativeField(
            wireId: fontSizeField,
            name: 'fontSize',
            type: PropertyType.length,
          ),
          _nativeField(
            wireId: fontWeightField,
            name: 'fontWeight',
            type: PropertyType.fontWeight,
          ),
          _nativeField(
            wireId: fontStyleField,
            name: 'fontStyle',
            type: PropertyType.enumValue,
            valueShape: fontStyleShape,
          ),
          _nativeField(
            wireId: decorationField,
            name: 'decoration',
            type: PropertyType.textDecoration,
            valueShape: decorationShape,
          ),
        ],
        variants: [
          ConstructorVariant(
            wireId: textStyleCtorRef.wireId,
            argMappings: {
              'color': ArgMapping(targetFields: [colorField]),
              'fontSize': ArgMapping(targetFields: [fontSizeField]),
              'fontWeight': ArgMapping(targetFields: [fontWeightField]),
              'fontStyle': ArgMapping(targetFields: [fontStyleField]),
              'decoration': ArgMapping(targetFields: [decorationField]),
            },
            parameters: [
              _namedNativeParam(
                wireId: WireId('a9101'),
                name: 'color',
                propertyType: PropertyType.color,
              ),
              _namedNativeParam(
                wireId: WireId('a9102'),
                name: 'fontSize',
                propertyType: PropertyType.length,
              ),
              _namedNativeParam(
                wireId: WireId('a9103'),
                name: 'fontWeight',
                propertyType: PropertyType.fontWeight,
              ),
              _namedNativeParam(
                wireId: WireId('a9104'),
                name: 'fontStyle',
                propertyType: PropertyType.enumValue,
                valueShape: fontStyleShape,
              ),
              _namedNativeParam(
                wireId: WireId('a9105'),
                name: 'decoration',
                propertyType: PropertyType.textDecoration,
                valueShape: decorationShape,
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

Catalog _textAlignCatalog() => catalogWith([
      WidgetEntry(
        wireId: WireId('w9300'),
        name: 'Text',
        library: WidgetLibrary.core,
        category: WidgetCategory.decoration,
        description: '',
        flutterType: 'package:flutter/src/widgets/text.dart#Text',
        childrenSlot: ChildrenSlot.none,
        fires: const [],
        properties: [
          PropertyEntry(
            wireId: WireId('p9300'),
            name: 'text',
            type: PropertyType.string,
            description: '',
            required: true,
            positional: true,
            valueShape: const ScalarShape(propertyType: PropertyType.string),
          ),
          PropertyEntry(
            wireId: WireId('p9301'),
            name: 'textAlign',
            type: PropertyType.enumValue,
            description: '',
            enumType: 'TextAlign',
            valueShape: const EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                libraryUri: 'dart:ui',
                symbolName: 'TextAlign',
              ),
            ),
          ),
        ],
      ),
    ]);

// RestagePager (alias target) + a minimal SizedBox child entry, so a
// `PageView(children: [SizedBox()])` aliases to a RestagePager node whose
// child list lowers. Mirrors the real catalog's RestagePager surface
// (children/initialPage/viewportFraction/scrollDirection/pageSnapping/
// onPageChanged) including the `scrollDirection` enumValue<Axis> slot.
Catalog _pagerCatalog() => catalogWith([
      WidgetEntry(
        wireId: WireId('w9400'),
        name: 'RestagePager',
        library: WidgetLibrary.core,
        category: WidgetCategory.action,
        description: '',
        flutterType:
            'package:restage_material/src/widgets/restage_pager.dart#RestagePager',
        childrenSlot: ChildrenSlot.list,
        fires: const [],
        properties: [
          prop('children', PropertyType.widgetList, required: true),
          prop('initialPage', PropertyType.integer),
          prop('viewportFraction', PropertyType.real),
          PropertyEntry(
            wireId: WireId('p9403'),
            name: 'scrollDirection',
            type: PropertyType.enumValue,
            description: '',
            enumType: 'Axis',
            valueShape: const EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                libraryUri: 'package:flutter/src/painting/basic_types.dart',
                symbolName: 'Axis',
              ),
            ),
          ),
          prop('pageSnapping', PropertyType.boolean),
          prop('onPageChanged', PropertyType.event),
        ],
      ),
      entry(
        name: 'SizedBox',
        properties: const [],
        flutterType: 'package:flutter/src/widgets/basic.dart#SizedBox',
      ),
    ]);

Catalog _draggableSheetCatalog({
  bool includeChild = true,
  bool includeController = false,
  bool includeInitialChildSize = true,
}) =>
    catalogWith([
      WidgetEntry(
        wireId: WireId('w9410'),
        name: 'RestageDraggableSheet',
        library: WidgetLibrary.material,
        category: WidgetCategory.action,
        description: '',
        flutterType: 'package:restage_material/src/widgets/'
            'restage_draggable_sheet.dart#RestageDraggableSheet',
        childrenSlot: ChildrenSlot.none,
        fires: const [],
        properties: [
          if (includeChild) prop('child', PropertyType.widget, required: true),
          if (includeController) prop('controller', PropertyType.string),
          if (includeInitialChildSize)
            prop('initialChildSize', PropertyType.real),
          prop('minChildSize', PropertyType.real),
          prop('maxChildSize', PropertyType.real),
          prop('expand', PropertyType.boolean),
          prop('snap', PropertyType.boolean),
          prop('snapAnimationDuration', PropertyType.duration),
          prop('expanded', PropertyType.boolean),
          prop('expandDuration', PropertyType.duration),
          prop('expandCurve', PropertyType.curve),
        ],
      ),
      entry(
        name: 'SizedBox',
        properties: const [],
        flutterType: 'package:flutter/src/widgets/basic.dart#SizedBox',
      ),
    ]);

// Builds the exact `items: [...]` DSL the single-select emitter produces from
// an ordered list of `(value, label)` pairs — `[{ value: "v", label: "l" }, …]`
// — so the alias tests assert the full byte string (order + every option) by
// construction rather than as a brittle hand-typed literal.
String _optionListDsl(List<(String value, String label)> options) {
  final entries = [
    for (final option in options)
      '{ value: "${option.$1}", label: "${option.$2}" }',
  ];
  return '[${entries.join(', ')}]';
}

// RestageRadioGroupString + RestageDropdownString (the alias targets) mirroring
// the real material catalog surface: a required `items` selectionOptionList, a
// `selected` string, and an `onChanged` event. A minimal SizedBox entry rounds
// out the catalog. The committed catalog stamps these `sinceVersion: 2`; the
// alias path does not read sinceVersion, so the default baseline is fine here.
Catalog _singleSelectCatalog() => catalogWith([
      WidgetEntry(
        wireId: WireId('w9420'),
        name: 'RestageRadioGroupString',
        library: WidgetLibrary.material,
        category: WidgetCategory.action,
        description: '',
        flutterType: 'package:restage_material/src/widgets/'
            'restage_radio_group.dart#RestageRadioGroup<String>',
        childrenSlot: ChildrenSlot.none,
        fires: const [],
        properties: [
          prop('items', PropertyType.selectionOptionList, required: true),
          prop('selected', PropertyType.string),
          prop('onChanged', PropertyType.event),
        ],
      ),
      WidgetEntry(
        wireId: WireId('w9421'),
        name: 'RestageDropdownString',
        library: WidgetLibrary.material,
        category: WidgetCategory.action,
        description: '',
        flutterType: 'package:restage_material/src/widgets/'
            'restage_dropdown.dart#RestageDropdown<String>',
        childrenSlot: ChildrenSlot.none,
        fires: const [],
        properties: [
          prop('items', PropertyType.selectionOptionList, required: true),
          prop('selected', PropertyType.string),
          prop('onChanged', PropertyType.event),
        ],
      ),
      entry(
        name: 'SizedBox',
        properties: const [],
        flutterType: 'package:flutter/src/widgets/basic.dart#SizedBox',
      ),
    ]);

Catalog _toggleButtonsCatalog() => catalogWith([
      WidgetEntry(
        wireId: WireId('w9430'),
        name: 'RestageToggleButtons',
        library: WidgetLibrary.material,
        category: WidgetCategory.input,
        description: '',
        flutterType: 'package:restage_material/src/widgets/'
            'restage_toggle_buttons.dart#RestageToggleButtons',
        childrenSlot: ChildrenSlot.list,
        fires: const [],
        properties: [
          prop('children', PropertyType.widgetList, required: true),
          prop('isSelected', PropertyType.booleanList, required: true),
          prop('onPressed', PropertyType.event),
        ],
      ),
      entry(
        name: 'Text',
        category: WidgetCategory.decoration,
        properties: [
          prop('text', PropertyType.string, required: true, positional: true),
        ],
      ),
    ]);

// RestageSegmentedButtonString (the alias target) mirroring the real material
// catalog surface: a required `items` selectionOptionList, a `selected` string
// list, an `onChanged` event, and the declarative bools. A minimal SizedBox
// entry rounds out the catalog. The alias path does not read sinceVersion, so
// the default baseline is fine here.
Catalog _segmentedButtonCatalog() => catalogWith([
      WidgetEntry(
        wireId: WireId('w9440'),
        name: 'RestageSegmentedButtonString',
        library: WidgetLibrary.material,
        category: WidgetCategory.input,
        description: '',
        flutterType: 'package:restage_material/src/widgets/'
            'restage_segmented_button.dart#RestageSegmentedButton<String>',
        childrenSlot: ChildrenSlot.none,
        fires: const [],
        properties: [
          prop('items', PropertyType.selectionOptionList, required: true),
          prop('selected', PropertyType.stringList),
          // The settled selection is the first list-valued event; the
          // callbackSignature carries the `ValueChanged<List<String>>` shape
          // the typed-handler path now accepts.
          const PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'onChanged',
            type: PropertyType.event,
            description: '',
            callbackSignature: 'ValueChanged<List<String>>',
          ),
          prop('multiSelectionEnabled', PropertyType.boolean),
          prop('emptySelectionAllowed', PropertyType.boolean),
        ],
      ),
      entry(
        name: 'SizedBox',
        properties: const [],
        flutterType: 'package:flutter/src/widgets/basic.dart#SizedBox',
      ),
    ]);

String _nestedTextSpanSource(int depth) {
  var source = "TextSpan(text: 'leaf')";
  for (var i = 0; i < depth; i++) {
    source = 'TextSpan(children: [$source])';
  }
  return source;
}

const String _nativeExpressionSourceStubs = '''
class Container {
  const Container({this.decoration});
  final Object? decoration;
}

class Text {
  const Text({this.text, this.style});
  final String? text;
  final TextStyle? style;
}

class TextStyle {
  const TextStyle({
    this.inherit = true,
    this.fontStyle,
    this.locale,
    this.foreground,
    this.shadows,
    this.fontFeatures,
    this.fontVariations,
    this.decoration,
    this.fontFamilyFallback,
    String? package,
  });

  final bool inherit;
  final FontStyle? fontStyle;
  final Locale? locale;
  final Paint? foreground;
  final List<Shadow>? shadows;
  final List<FontFeature>? fontFeatures;
  final List<FontVariation>? fontVariations;
  final TextDecoration? decoration;
  final List<String>? fontFamilyFallback;
}

enum FontStyle { normal, italic }

class Locale {
  const Locale(this.languageCode, [this.countryCode]);

  const Locale.fromSubtags({
    required this.languageCode,
    this.scriptCode,
    this.countryCode,
  });

  final String languageCode;
  final String? scriptCode;
  final String? countryCode;
}

class Paint {
  Object? color;
  Object? blendMode;
  Object? filterQuality;
  bool? isAntiAlias;
  Object? style;
}

enum BlendMode { srcOver, multiply }
enum FilterQuality { none, low, medium, high }
enum PaintingStyle { fill, stroke }

class Shadow {
  const Shadow({this.color, this.blurRadius, this.offset});
  final Object? color;
  final Object? blurRadius;
  final Object? offset;
}

class FontFeature {
  const FontFeature(this.feature, [this.value = 1]);
  const FontFeature.enable(String feature) : this(feature, 1);
  const FontFeature.disable(String feature) : this(feature, 0);

  final String feature;
  final int value;
}

class FontVariation {
  const FontVariation(this.axis, this.value);
  final String axis;
  final num value;
}

class TextDecoration {
  const TextDecoration._(this.name);

  final String name;

  static const underline = TextDecoration._('underline');
  static const overline = TextDecoration._('overline');
  static const lineThrough = TextDecoration._('lineThrough');
  static const none = TextDecoration._('none');

  static TextDecoration combine(List<TextDecoration> decorations) {
    return decorations.first;
  }
}

class FilledButton {
  const FilledButton({this.style});
  final ButtonStyle? style;

  static ButtonStyle styleFrom({
    Object? backgroundColor,
    Object? padding,
    Object? shape,
  }) =>
      const ButtonStyle();
}

class BoxDecoration {
  const BoxDecoration({
    this.color,
    this.borderRadius,
    this.boxShadow,
    this.gradient,
  });
  final Object? color;
  final Object? borderRadius;
  final Object? boxShadow;
  final Object? gradient;
}

class ButtonStyle {
  const ButtonStyle();
}

class BorderRadius {
  const BorderRadius.circular(num radius);
}

class BorderSide {
  const BorderSide({
    this.color,
    this.width = 1.0,
    this.style = BorderStyle.solid,
  });

  final Object? color;
  final num width;
  final BorderStyle style;

  static const none = BorderSide(width: 0.0, style: BorderStyle.none);
}

enum BorderStyle { none, solid }

abstract class ShapeBorder {
  const ShapeBorder();
}

abstract class OutlinedBorder extends ShapeBorder {
  const OutlinedBorder({this.side = BorderSide.none});
  final BorderSide side;
}

class RoundedRectangleBorder extends OutlinedBorder {
  const RoundedRectangleBorder({super.side, this.borderRadius});
  final Object? borderRadius;
}

class RoundedSuperellipseBorder extends OutlinedBorder {
  const RoundedSuperellipseBorder({super.side, this.borderRadius});
  final Object? borderRadius;
}

class CircleBorder extends OutlinedBorder {
  const CircleBorder({super.side, this.eccentricity = 0.0});
  final num eccentricity;
}

class StadiumBorder extends OutlinedBorder {
  const StadiumBorder({super.side});
}

class ContinuousRectangleBorder extends OutlinedBorder {
  const ContinuousRectangleBorder({super.side, this.borderRadius});
  final Object? borderRadius;
}

class BeveledRectangleBorder extends OutlinedBorder {
  const BeveledRectangleBorder({super.side, this.borderRadius});
  final Object? borderRadius;
}

class LinearBorderEdge {
  const LinearBorderEdge({this.size = 1.0, this.alignment = 0.0});
  final num size;
  final num alignment;
}

class LinearBorder extends OutlinedBorder {
  const LinearBorder({super.side, this.start, this.end, this.top, this.bottom});
  const LinearBorder.start({
    super.side,
    num alignment = 0.0,
    num size = 1.0,
  })  : start = const LinearBorderEdge(),
        end = null,
        top = null,
        bottom = null;
  const LinearBorder.end({
    super.side,
    num alignment = 0.0,
    num size = 1.0,
  })  : start = null,
        end = const LinearBorderEdge(),
        top = null,
        bottom = null;
  const LinearBorder.top({
    super.side,
    num alignment = 0.0,
    num size = 1.0,
  })  : start = null,
        end = null,
        top = const LinearBorderEdge(),
        bottom = null;
  const LinearBorder.bottom({
    super.side,
    num alignment = 0.0,
    num size = 1.0,
  })  : start = null,
        end = null,
        top = null,
        bottom = const LinearBorderEdge();
  final LinearBorderEdge? start;
  final LinearBorderEdge? end;
  final LinearBorderEdge? top;
  final LinearBorderEdge? bottom;
}

class StarBorder extends OutlinedBorder {
  const StarBorder({
    super.side,
    this.points = 5,
    this.innerRadiusRatio = 0.4,
    this.pointRounding = 0,
    this.valleyRounding = 0,
    this.rotation = 0,
    this.squash = 0,
  }) : sides = null;
  const StarBorder.polygon({
    super.side,
    this.sides = 5,
    this.pointRounding = 0,
    this.rotation = 0,
    this.squash = 0,
  })  : points = null,
        innerRadiusRatio = null,
        valleyRounding = 0;
  final num? points;
  final num? sides;
  final num? innerRadiusRatio;
  final num pointRounding;
  final num valleyRounding;
  final num rotation;
  final num squash;
}

class LinearGradient {
  const LinearGradient({this.colors});
  final Object? colors;
}

class Color {
  const Color(this.value);
  final int value;
}

class EdgeInsets {
  const EdgeInsets.all(num value);
}

class Offset {
  const Offset(num x, num y);
}

class BoxShadow {
  const BoxShadow({this.color, this.blurRadius, this.offset});
  final Object? color;
  final Object? blurRadius;
  final Object? offset;
}
''';

const String _nativeSourceUri = 'package:restage_codegen/_expr_probe.dart';

WireIdRef _nativeRef(String library, String wireId) =>
    WireIdRef(library: library, wireId: WireId(wireId));

CatalogValueShape _scalarShape(PropertyType propertyType, {String? symbol}) =>
    ScalarShape(
      propertyType: propertyType,
      dartTypeRef: symbol == null
          ? null
          : DartTypeRef(libraryUri: _nativeSourceUri, symbolName: symbol),
    );

CatalogValueShape _enumShape(String symbol) => EnumShape(
      propertyType: PropertyType.enumValue,
      enumRef: DartTypeRef(libraryUri: _nativeSourceUri, symbolName: symbol),
    );

CatalogValueShape _listShape(
  PropertyType propertyType,
  CatalogValueShape itemShape,
) =>
    ListShape(propertyType: propertyType, itemShape: itemShape);

Catalog _nativeExpressionCatalog({
  bool omitContainerConstruction = false,
  TransformNullPolicy circularRadiusNullPolicy = TransformNullPolicy.nullResult,
  TransformMissingPolicy circularRadiusMissingPolicy =
      TransformMissingPolicy.nullResult,
}) {
  final containerRef = _nativeRef('restage.core', 'w0001');
  final backgroundColorProp = WireId('p0001');
  final borderRadiusProp = WireId('p0002');
  final boxShadowProp = WireId('p0003');
  final gradientProp = WireId('p0004');
  final colorField = WireId('p0005');
  final borderRadiusField = WireId('p0006');
  final boxShadowField = WireId('p0007');
  final gradientField = WireId('p0008');
  final boxRef = _nativeRef('restage.core', 's0001');
  final borderRadiusRef = _nativeRef('restage.core', 's0002');
  final boxShadowRef = _nativeRef('restage.core', 's0003');
  final linearGradientRef = _nativeRef('restage.core', 's0004');
  final boxCtorRef = _nativeRef('restage.core', 'v0001');
  final circularCtorRef = _nativeRef('restage.core', 'v0002');
  final circularRadiusParam = WireId('a0001');

  final filledButtonRef = _nativeRef('restage.material', 'w0001');
  final buttonBackgroundColorProp = WireId('p0001');
  final buttonPaddingProp = WireId('p0002');
  final buttonShapeProp = WireId('p0005');
  final buttonBackgroundColorField = WireId('p0003');
  final buttonPaddingField = WireId('p0004');
  final buttonShapeField = WireId('p0006');
  final buttonStyleRef = _nativeRef('restage.material', 's0001');
  final buttonStyleFromRef = _nativeRef('restage.material', 'v0001');

  final textRef = _nativeRef('restage.core', 'w0002');
  final textStyleRef = _nativeRef('restage.core', 's0010');
  final textStyleCtorRef = _nativeRef('restage.core', 'v0010');
  final textProp = WireId('p0200');
  final inheritProp = WireId('p0201');
  final fontStyleProp = WireId('p0202');
  final localeProp = WireId('p0203');
  final foregroundProp = WireId('p0204');
  final shadowsProp = WireId('p0205');
  final fontFeaturesProp = WireId('p0206');
  final fontVariationsProp = WireId('p0207');
  final decorationProp = WireId('p0208');
  final fontFamilyFallbackProp = WireId('p0209');
  final fontPackageProp = WireId('p0210');
  final inheritField = WireId('p0301');
  final fontStyleField = WireId('p0302');
  final localeField = WireId('p0303');
  final foregroundField = WireId('p0304');
  final shadowsField = WireId('p0305');
  final fontFeaturesField = WireId('p0306');
  final fontVariationsField = WireId('p0307');
  final decorationField = WireId('p0308');
  final fontFamilyFallbackField = WireId('p0309');
  final packageParam = WireId('a0310');
  final fontStyleShape = _enumShape('FontStyle');
  final localeShape = _scalarShape(PropertyType.locale, symbol: 'Locale');
  final paintShape = _scalarShape(PropertyType.paint, symbol: 'Paint');
  // List item shapes mirror what `_listValueShapeForDartType` emits: the item
  // carries the same list-category propertyType as the outer list (a scalar
  // value identified by its dartTypeRef/symbol), not `structured`.
  final shadowListShape = _listShape(
    PropertyType.shadowList,
    _scalarShape(PropertyType.shadowList, symbol: 'Shadow'),
  );
  final fontFeatureListShape = _listShape(
    PropertyType.fontFeatureList,
    _scalarShape(PropertyType.fontFeatureList, symbol: 'FontFeature'),
  );
  final fontVariationListShape = _listShape(
    PropertyType.fontVariationList,
    _scalarShape(PropertyType.fontVariationList, symbol: 'FontVariation'),
  );
  final decorationShape =
      _scalarShape(PropertyType.textDecoration, symbol: 'TextDecoration');
  final fontFamilyFallbackShape = _listShape(
    PropertyType.stringList,
    _scalarShape(PropertyType.string),
  );

  return Catalog(
    schemaVersion: kSupportedSchemaVersion,
    generatedAt: '1970-01-01T00:00:00Z',
    libraries: {
      WidgetLibrary.core: const LibraryInfo(version: '1.0.0'),
      WidgetLibrary.material: const LibraryInfo(version: '1.0.0'),
    },
    widgets: [
      WidgetEntry(
        wireId: containerRef.wireId,
        name: 'Container',
        library: WidgetLibrary.core,
        category: WidgetCategory.layout,
        description: '',
        flutterType: '$_nativeSourceUri#Container',
        childrenSlot: ChildrenSlot.none,
        fires: const [],
        properties: [
          _nativeProperty(
            wireId: backgroundColorProp,
            name: 'backgroundColor',
            type: PropertyType.color,
          ),
          _nativeProperty(
            wireId: borderRadiusProp,
            name: 'borderRadius',
            type: PropertyType.real,
          ),
          _nativeProperty(
            wireId: boxShadowProp,
            name: 'boxShadow',
            type: PropertyType.boxShadowList,
            valueShape: ListShape(
              propertyType: PropertyType.boxShadowList,
              itemShape: StructuredShape(
                propertyType: PropertyType.structured,
                structuredRef: boxShadowRef,
              ),
              wireCodec: CatalogWireCodec.rfwBoxShadowList,
            ),
          ),
          _nativeProperty(
            wireId: gradientProp,
            name: 'gradient',
            type: PropertyType.gradient,
          ),
        ],
        decomposes: [
          DecompositionRecipe(
            structuredRef: boxRef,
            flatProperties: {
              colorField: backgroundColorProp,
              borderRadiusField: borderRadiusProp,
              boxShadowField: boxShadowProp,
              gradientField: gradientProp,
            },
            targetArg: 'decoration',
            construction: omitContainerConstruction
                ? null
                : FactoryInvocation(
                    variantRef: boxCtorRef,
                    receiver: const ResultStructuredTypeReceiver(),
                  ),
            fieldMappings: [
              DecompositionFieldMapping(
                fieldRef: WireId('p0005'),
                propertyRef: WireId('p0001'),
                transform: const IdentityTransform(),
              ),
              DecompositionFieldMapping(
                fieldRef: borderRadiusField,
                propertyRef: borderRadiusProp,
                transform: ConstructVariantTransform(
                  resultStructuredRef: borderRadiusRef,
                  invocation: FactoryInvocation(
                    variantRef: circularCtorRef,
                    receiver: const ResultStructuredTypeReceiver(),
                    memberName: 'circular',
                  ),
                  argumentBindings: [
                    PropertyValueArgumentBinding(
                      parameterRef: circularRadiusParam,
                      nullPolicy: circularRadiusNullPolicy,
                      missingPolicy: circularRadiusMissingPolicy,
                    ),
                  ],
                ),
              ),
              DecompositionFieldMapping(
                fieldRef: WireId('p0007'),
                propertyRef: WireId('p0003'),
                transform: const ProjectListTransform(
                  itemTransform: IdentityTransform(),
                ),
              ),
            ],
          ),
        ],
      ),
      WidgetEntry(
        wireId: textRef.wireId,
        name: 'Text',
        library: WidgetLibrary.core,
        category: WidgetCategory.decoration,
        description: '',
        flutterType: '$_nativeSourceUri#Text',
        childrenSlot: ChildrenSlot.none,
        fires: const [],
        properties: [
          _nativeProperty(
            wireId: textProp,
            name: 'text',
            type: PropertyType.string,
          ),
          _nativeProperty(
            wireId: inheritProp,
            name: 'inherit',
            type: PropertyType.boolean,
          ),
          _nativeProperty(
            wireId: fontStyleProp,
            name: 'fontStyle',
            type: PropertyType.enumValue,
            valueShape: fontStyleShape,
          ),
          _nativeProperty(
            wireId: localeProp,
            name: 'locale',
            type: PropertyType.locale,
            valueShape: localeShape,
          ),
          _nativeProperty(
            wireId: foregroundProp,
            name: 'foreground',
            type: PropertyType.paint,
            valueShape: paintShape,
          ),
          _nativeProperty(
            wireId: shadowsProp,
            name: 'shadows',
            type: PropertyType.shadowList,
            valueShape: shadowListShape,
          ),
          _nativeProperty(
            wireId: fontFeaturesProp,
            name: 'fontFeatures',
            type: PropertyType.fontFeatureList,
            valueShape: fontFeatureListShape,
          ),
          _nativeProperty(
            wireId: fontVariationsProp,
            name: 'fontVariations',
            type: PropertyType.fontVariationList,
            valueShape: fontVariationListShape,
          ),
          _nativeProperty(
            wireId: decorationProp,
            name: 'decoration',
            type: PropertyType.textDecoration,
            valueShape: decorationShape,
          ),
          _nativeProperty(
            wireId: fontFamilyFallbackProp,
            name: 'fontFamilyFallback',
            type: PropertyType.stringList,
            valueShape: fontFamilyFallbackShape,
          ),
          _nativeProperty(
            wireId: fontPackageProp,
            name: 'fontPackage',
            type: PropertyType.string,
          ),
        ],
        decomposes: [
          DecompositionRecipe(
            structuredRef: textStyleRef,
            flatProperties: {
              inheritField: inheritProp,
              fontStyleField: fontStyleProp,
              localeField: localeProp,
              foregroundField: foregroundProp,
              shadowsField: shadowsProp,
              fontFeaturesField: fontFeaturesProp,
              fontVariationsField: fontVariationsProp,
              decorationField: decorationProp,
              fontFamilyFallbackField: fontFamilyFallbackProp,
            },
            targetArg: 'style',
            construction: FactoryInvocation(
              variantRef: textStyleCtorRef,
              receiver: const ResultStructuredTypeReceiver(),
            ),
            fieldMappings: [
              _nativeFieldMapping(inheritField, inheritProp),
              _nativeFieldMapping(fontStyleField, fontStyleProp),
              _nativeFieldMapping(localeField, localeProp),
              _nativeFieldMapping(foregroundField, foregroundProp),
              _nativeFieldMapping(shadowsField, shadowsProp),
              _nativeFieldMapping(fontFeaturesField, fontFeaturesProp),
              _nativeFieldMapping(fontVariationsField, fontVariationsProp),
              _nativeFieldMapping(decorationField, decorationProp),
              _nativeFieldMapping(
                fontFamilyFallbackField,
                fontFamilyFallbackProp,
              ),
            ],
            parameterMappings: [
              DecompositionParameterMapping(
                parameterRef: packageParam,
                propertyRef: fontPackageProp,
                transform: const IdentityTransform(),
              ),
            ],
          ),
        ],
      ),
      WidgetEntry(
        wireId: filledButtonRef.wireId,
        name: 'FilledButton',
        library: WidgetLibrary.material,
        category: WidgetCategory.input,
        description: '',
        flutterType: '$_nativeSourceUri#FilledButton',
        childrenSlot: ChildrenSlot.none,
        fires: const [],
        properties: [
          _nativeProperty(
            wireId: buttonBackgroundColorProp,
            name: 'backgroundColor',
            type: PropertyType.color,
          ),
          _nativeProperty(
            wireId: buttonPaddingProp,
            name: 'padding',
            type: PropertyType.edgeInsets,
          ),
          _nativeProperty(
            wireId: buttonShapeProp,
            name: 'shape',
            type: PropertyType.shapeBorder,
          ),
        ],
        decomposes: [
          DecompositionRecipe(
            structuredRef: buttonStyleRef,
            flatProperties: {
              buttonBackgroundColorField: buttonBackgroundColorProp,
              buttonPaddingField: buttonPaddingProp,
              buttonShapeField: buttonShapeProp,
            },
            targetArg: 'style',
            construction: FactoryInvocation(
              variantRef: buttonStyleFromRef,
              receiver: const OwningWidgetTypeReceiver(),
              memberName: 'styleFrom',
            ),
            fieldMappings: [
              DecompositionFieldMapping(
                fieldRef: WireId('p0003'),
                propertyRef: WireId('p0001'),
                transform: const IdentityTransform(),
              ),
              DecompositionFieldMapping(
                fieldRef: WireId('p0004'),
                propertyRef: WireId('p0002'),
                transform: const IdentityTransform(),
              ),
              DecompositionFieldMapping(
                fieldRef: buttonShapeField,
                propertyRef: buttonShapeProp,
                transform: const IdentityTransform(),
              ),
            ],
          ),
        ],
      ),
    ],
    structuredTypes: [
      _boxDecorationStructured(
        boxRef: boxRef,
        boxCtorRef: boxCtorRef,
        borderRadiusRef: borderRadiusRef,
        boxShadowRef: boxShadowRef,
        linearGradientRef: linearGradientRef,
        colorField: colorField,
        borderRadiusField: borderRadiusField,
        boxShadowField: boxShadowField,
        gradientField: gradientField,
      ),
      _borderRadiusStructured(
        borderRadiusRef: borderRadiusRef,
        circularCtorRef: circularCtorRef,
        circularRadiusParam: circularRadiusParam,
      ),
      _emptyNativeStructured(
        ref: boxShadowRef,
        name: 'BoxShadow',
        sourceType: '$_nativeSourceUri#BoxShadow',
      ),
      _emptyNativeStructured(
        ref: linearGradientRef,
        name: 'LinearGradient',
        sourceType: '$_nativeSourceUri#LinearGradient',
      ),
      _textStyleStructured(
        textStyleRef: textStyleRef,
        textStyleCtorRef: textStyleCtorRef,
        inheritField: inheritField,
        fontStyleField: fontStyleField,
        localeField: localeField,
        foregroundField: foregroundField,
        shadowsField: shadowsField,
        fontFeaturesField: fontFeaturesField,
        fontVariationsField: fontVariationsField,
        decorationField: decorationField,
        fontFamilyFallbackField: fontFamilyFallbackField,
        packageParam: packageParam,
        fontStyleShape: fontStyleShape,
        localeShape: localeShape,
        paintShape: paintShape,
        shadowListShape: shadowListShape,
        fontFeatureListShape: fontFeatureListShape,
        fontVariationListShape: fontVariationListShape,
        decorationShape: decorationShape,
        fontFamilyFallbackShape: fontFamilyFallbackShape,
      ),
      _buttonStyleStructured(
        buttonStyleRef: buttonStyleRef,
        styleFromRef: buttonStyleFromRef,
        backgroundColorField: buttonBackgroundColorField,
        paddingField: buttonPaddingField,
        shapeField: buttonShapeField,
      ),
    ],
  );
}

PropertyEntry _nativeProperty({
  required WireId wireId,
  required String name,
  required PropertyType type,
  CatalogValueShape? valueShape,
}) =>
    PropertyEntry(
      wireId: wireId,
      name: name,
      type: type,
      description: '',
      valueShape: valueShape ?? ScalarShape(propertyType: type),
    );

DecompositionFieldMapping _nativeFieldMapping(
  WireId fieldRef,
  WireId propertyRef,
) =>
    DecompositionFieldMapping(
      fieldRef: fieldRef,
      propertyRef: propertyRef,
      transform: const IdentityTransform(),
    );

StructuredEntry _boxDecorationStructured({
  required WireIdRef boxRef,
  required WireIdRef boxCtorRef,
  required WireIdRef borderRadiusRef,
  required WireIdRef boxShadowRef,
  required WireIdRef linearGradientRef,
  required WireId colorField,
  required WireId borderRadiusField,
  required WireId boxShadowField,
  required WireId gradientField,
}) =>
    StructuredEntry(
      wireId: boxRef.wireId,
      name: 'NativeDecoration',
      library: WidgetLibrary.core,
      description: '',
      sourceType: '$_nativeSourceUri#BoxDecoration',
      fields: [
        _nativeField(
          wireId: colorField,
          name: 'color',
          type: PropertyType.color,
        ),
        _nativeField(
          wireId: borderRadiusField,
          name: 'borderRadius',
          type: PropertyType.structured,
          valueShape: StructuredShape(
            propertyType: PropertyType.structured,
            structuredRef: borderRadiusRef,
          ),
          structuredRef: borderRadiusRef,
        ),
        _nativeField(
          wireId: boxShadowField,
          name: 'boxShadow',
          type: PropertyType.boxShadowList,
          valueShape: ListShape(
            propertyType: PropertyType.boxShadowList,
            itemShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: boxShadowRef,
            ),
            wireCodec: CatalogWireCodec.rfwBoxShadowList,
          ),
        ),
        _nativeField(
          wireId: gradientField,
          name: 'gradient',
          type: PropertyType.gradient,
          valueShape: StructuredShape(
            propertyType: PropertyType.structured,
            structuredRef: linearGradientRef,
          ),
          structuredRef: linearGradientRef,
        ),
      ],
      variants: [
        ConstructorVariant(
          wireId: boxCtorRef.wireId,
          argMappings: {
            'color': ArgMapping(targetFields: [colorField]),
            'borderRadius': ArgMapping(targetFields: [borderRadiusField]),
            'boxShadow': ArgMapping(targetFields: [boxShadowField]),
            'gradient': ArgMapping(targetFields: [gradientField]),
          },
          parameters: [
            _namedNativeParam(
              wireId: WireId('a0002'),
              name: 'color',
              propertyType: PropertyType.color,
            ),
            _namedNativeParam(
              wireId: WireId('a0003'),
              name: 'borderRadius',
              propertyType: PropertyType.structured,
              valueShape: StructuredShape(
                propertyType: PropertyType.structured,
                structuredRef: borderRadiusRef,
              ),
            ),
            _namedNativeParam(
              wireId: WireId('a0004'),
              name: 'boxShadow',
              propertyType: PropertyType.boxShadowList,
              valueShape: ListShape(
                propertyType: PropertyType.boxShadowList,
                itemShape: StructuredShape(
                  propertyType: PropertyType.structured,
                  structuredRef: boxShadowRef,
                ),
                wireCodec: CatalogWireCodec.rfwBoxShadowList,
              ),
            ),
            _namedNativeParam(
              wireId: WireId('a0005'),
              name: 'gradient',
              propertyType: PropertyType.structured,
              valueShape: StructuredShape(
                propertyType: PropertyType.structured,
                structuredRef: linearGradientRef,
              ),
            ),
          ],
        ),
      ],
    );

StructuredField _nativeField({
  required WireId wireId,
  required String name,
  required PropertyType type,
  CatalogValueShape? valueShape,
  WireIdRef? structuredRef,
}) =>
    StructuredField(
      wireId: wireId,
      name: name,
      type: type,
      description: '',
      structuredRef: structuredRef,
      valueShape: valueShape ?? ScalarShape(propertyType: type),
    );

StructuredEntry _borderRadiusStructured({
  required WireIdRef borderRadiusRef,
  required WireIdRef circularCtorRef,
  required WireId circularRadiusParam,
}) =>
    StructuredEntry(
      wireId: borderRadiusRef.wireId,
      name: 'NativeRadius',
      library: WidgetLibrary.fromNamespace(borderRadiusRef.library),
      description: '',
      sourceType: '$_nativeSourceUri#BorderRadius',
      fields: [
        _nativeField(
          wireId: WireId('p0009'),
          name: 'radius',
          type: PropertyType.real,
        ),
      ],
      variants: [
        ConstructorVariant(
          wireId: circularCtorRef.wireId,
          namedConstructor: 'circular',
          argMappings: {
            '': ArgMapping(targetFields: [WireId('p0009')]),
          },
          parameters: [
            FactoryParameter(
              wireId: circularRadiusParam,
              position: 0,
              kind: FactoryParameterKind.positional,
              required: true,
              nullable: false,
              defaultPolicy: FactoryParameterDefaultPolicy.requiredValue,
              valueShape: const ScalarShape(propertyType: PropertyType.real),
            ),
          ],
        ),
      ],
    );

StructuredEntry _textStyleStructured({
  required WireIdRef textStyleRef,
  required WireIdRef textStyleCtorRef,
  required WireId inheritField,
  required WireId fontStyleField,
  required WireId localeField,
  required WireId foregroundField,
  required WireId shadowsField,
  required WireId fontFeaturesField,
  required WireId fontVariationsField,
  required WireId decorationField,
  required WireId fontFamilyFallbackField,
  required WireId packageParam,
  required CatalogValueShape fontStyleShape,
  required CatalogValueShape localeShape,
  required CatalogValueShape paintShape,
  required CatalogValueShape shadowListShape,
  required CatalogValueShape fontFeatureListShape,
  required CatalogValueShape fontVariationListShape,
  required CatalogValueShape decorationShape,
  required CatalogValueShape fontFamilyFallbackShape,
}) =>
    StructuredEntry(
      wireId: textStyleRef.wireId,
      name: 'NativeTextStyle',
      library: WidgetLibrary.core,
      description: '',
      sourceType: '$_nativeSourceUri#TextStyle',
      fields: [
        _nativeField(
          wireId: inheritField,
          name: 'inherit',
          type: PropertyType.boolean,
        ),
        _nativeField(
          wireId: fontStyleField,
          name: 'fontStyle',
          type: PropertyType.enumValue,
          valueShape: fontStyleShape,
        ),
        _nativeField(
          wireId: localeField,
          name: 'locale',
          type: PropertyType.locale,
          valueShape: localeShape,
        ),
        _nativeField(
          wireId: foregroundField,
          name: 'foreground',
          type: PropertyType.paint,
          valueShape: paintShape,
        ),
        _nativeField(
          wireId: shadowsField,
          name: 'shadows',
          type: PropertyType.shadowList,
          valueShape: shadowListShape,
        ),
        _nativeField(
          wireId: fontFeaturesField,
          name: 'fontFeatures',
          type: PropertyType.fontFeatureList,
          valueShape: fontFeatureListShape,
        ),
        _nativeField(
          wireId: fontVariationsField,
          name: 'fontVariations',
          type: PropertyType.fontVariationList,
          valueShape: fontVariationListShape,
        ),
        _nativeField(
          wireId: decorationField,
          name: 'decoration',
          type: PropertyType.textDecoration,
          valueShape: decorationShape,
        ),
        _nativeField(
          wireId: fontFamilyFallbackField,
          name: 'fontFamilyFallback',
          type: PropertyType.stringList,
          valueShape: fontFamilyFallbackShape,
        ),
      ],
      variants: [
        ConstructorVariant(
          wireId: textStyleCtorRef.wireId,
          argMappings: {
            'inherit': ArgMapping(targetFields: [inheritField]),
            'fontStyle': ArgMapping(targetFields: [fontStyleField]),
            'locale': ArgMapping(targetFields: [localeField]),
            'foreground': ArgMapping(targetFields: [foregroundField]),
            'shadows': ArgMapping(targetFields: [shadowsField]),
            'fontFeatures': ArgMapping(targetFields: [fontFeaturesField]),
            'fontVariations': ArgMapping(targetFields: [fontVariationsField]),
            'decoration': ArgMapping(targetFields: [decorationField]),
            'fontFamilyFallback': ArgMapping(
              targetFields: [fontFamilyFallbackField],
            ),
          },
          parameters: [
            FactoryParameter(
              wireId: WireId('a0301'),
              name: 'inherit',
              kind: FactoryParameterKind.named,
              required: false,
              nullable: false,
              defaultPolicy: FactoryParameterDefaultPolicy.useFlutterDefault,
              defaultValue: const LiteralParameterDefault(true),
              valueShape: _scalarShape(PropertyType.boolean),
            ),
            _namedNativeParam(
              wireId: WireId('a0302'),
              name: 'fontStyle',
              propertyType: PropertyType.enumValue,
              valueShape: fontStyleShape,
            ),
            _namedNativeParam(
              wireId: WireId('a0303'),
              name: 'locale',
              propertyType: PropertyType.locale,
              valueShape: localeShape,
            ),
            _namedNativeParam(
              wireId: WireId('a0304'),
              name: 'foreground',
              propertyType: PropertyType.paint,
              valueShape: paintShape,
            ),
            _namedNativeParam(
              wireId: WireId('a0305'),
              name: 'shadows',
              propertyType: PropertyType.shadowList,
              valueShape: shadowListShape,
            ),
            _namedNativeParam(
              wireId: WireId('a0306'),
              name: 'fontFeatures',
              propertyType: PropertyType.fontFeatureList,
              valueShape: fontFeatureListShape,
            ),
            _namedNativeParam(
              wireId: WireId('a0307'),
              name: 'fontVariations',
              propertyType: PropertyType.fontVariationList,
              valueShape: fontVariationListShape,
            ),
            _namedNativeParam(
              wireId: WireId('a0308'),
              name: 'decoration',
              propertyType: PropertyType.textDecoration,
              valueShape: decorationShape,
            ),
            _namedNativeParam(
              wireId: WireId('a0309'),
              name: 'fontFamilyFallback',
              propertyType: PropertyType.stringList,
              valueShape: fontFamilyFallbackShape,
            ),
            _namedNativeParam(
              wireId: packageParam,
              name: 'package',
              propertyType: PropertyType.string,
            ),
          ],
        ),
      ],
    );

StructuredEntry _buttonStyleStructured({
  required WireIdRef buttonStyleRef,
  required WireIdRef styleFromRef,
  required WireId backgroundColorField,
  required WireId paddingField,
  WireId? shapeField,
}) =>
    StructuredEntry(
      wireId: buttonStyleRef.wireId,
      name: 'NativeButtonStyle',
      library: WidgetLibrary.material,
      description: '',
      sourceType: '$_nativeSourceUri#ButtonStyle',
      fields: [
        _nativeField(
          wireId: backgroundColorField,
          name: 'backgroundColor',
          type: PropertyType.color,
        ),
        _nativeField(
          wireId: paddingField,
          name: 'padding',
          type: PropertyType.edgeInsets,
        ),
        if (shapeField != null)
          _nativeField(
            wireId: shapeField,
            name: 'shape',
            type: PropertyType.shapeBorder,
            valueShape:
                const ScalarShape(propertyType: PropertyType.shapeBorder),
          ),
      ],
      variants: [
        StaticMethodVariant(
          wireId: styleFromRef.wireId,
          staticAccessor: 'styleFrom',
          argMappings: {
            'backgroundColor': ArgMapping(targetFields: [backgroundColorField]),
            'padding': ArgMapping(targetFields: [paddingField]),
            if (shapeField != null)
              'shape': ArgMapping(targetFields: [shapeField]),
          },
          parameters: [
            _namedNativeParam(
              wireId: WireId('a0001'),
              name: 'backgroundColor',
              propertyType: PropertyType.color,
            ),
            _namedNativeParam(
              wireId: WireId('a0002'),
              name: 'padding',
              propertyType: PropertyType.edgeInsets,
            ),
            if (shapeField != null)
              _namedNativeParam(
                wireId: WireId('a0005'),
                name: 'shape',
                propertyType: PropertyType.shapeBorder,
                valueShape:
                    const ScalarShape(propertyType: PropertyType.shapeBorder),
              ),
          ],
        ),
      ],
    );

StructuredEntry _emptyNativeStructured({
  required WireIdRef ref,
  required String name,
  required String sourceType,
}) =>
    StructuredEntry(
      wireId: ref.wireId,
      name: name,
      library: WidgetLibrary.fromNamespace(ref.library),
      description: '',
      sourceType: sourceType,
      fields: const [],
      variants: [
        ConstructorVariant(
          wireId: WireId('v${ref.wireId.value.substring(1)}'),
        ),
      ],
    );

FactoryParameter _namedNativeParam({
  required WireId wireId,
  required String name,
  required PropertyType propertyType,
  CatalogValueShape? valueShape,
}) =>
    FactoryParameter(
      wireId: wireId,
      name: name,
      kind: FactoryParameterKind.named,
      required: false,
      nullable: true,
      defaultPolicy: FactoryParameterDefaultPolicy.omitWhenNull,
      valueShape: valueShape ?? ScalarShape(propertyType: propertyType),
    );
