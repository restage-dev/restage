import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// An `Icon` entry shaped like the built-in one: a positional codepoint that
/// resolves through the installed icon table, and the font family and
/// mirroring that travel beside it.
final Catalog _iconCatalog = catalogWith([
  entry(
    name: 'Icon',
    category: WidgetCategory.decoration,
    properties: const [
      PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: 'iconCodepoint',
        type: PropertyType.integer,
        description: '',
        required: true,
        synthetic: 'iconData',
        positional: true,
      ),
      PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: 'iconFontFamily',
        type: PropertyType.string,
        description: '',
        synthetic: 'iconFontFamily',
      ),
      PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: 'iconMatchTextDirection',
        type: PropertyType.boolean,
        description: '',
        synthetic: 'iconMatchTextDirection',
      ),
    ],
  ),
]);

ExpressionTranslator _translator() => ExpressionTranslator(
      catalog: _iconCatalog,
      helpers: HelperRegistry(),
    );

void main() {
  group('icon font family lowering', () {
    test('a Material icon lowers to a bare codepoint', () async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/material.dart';
        Object x() => Icon(Icons.star);
        ''',
        rootPackage: 'apps_examples',
      );

      final r = _translator().translate(expr);

      expect(r.issues, isEmpty);
      expect(r.dsl, matches(RegExp(r'^Icon\(iconCodepoint: \d+\)$')));
      expect(r.dsl, isNot(contains('iconFontFamily')));
      expect(r.dsl, isNot(contains('iconMatchTextDirection')));
    });

    test('a mirroring icon carries its direction', () async {
      // Icons.arrow_back shares 0xe092 with nothing here, but the pairs that
      // do share a code point are told apart by exactly this slot.
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/material.dart';
        Object x() => Icon(Icons.arrow_back);
        ''',
        rootPackage: 'apps_examples',
      );

      final r = _translator().translate(expr);

      expect(r.issues, isEmpty);
      expect(r.dsl, 'Icon(iconCodepoint: 57490, iconMatchTextDirection: true)');
    });

    test('a mirroring Cupertino icon carries both slots, family first',
        () async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/cupertino.dart';
        Object x() => Icon(CupertinoIcons.back);
        ''',
        rootPackage: 'apps_examples',
      );

      final r = _translator().translate(expr);

      expect(r.issues, isEmpty);
      expect(
        r.dsl,
        'Icon(iconCodepoint: 62415, iconFontFamily: "CupertinoIcons", '
        'iconMatchTextDirection: true)',
      );
    });

    test('a mirroring icon does not leak into the next icon', () async {
      // The slot is cleared before each codepoint translates, so a mirroring
      // icon cannot mark an ordinary one that follows it.
      final mirroring = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/material.dart';
        Object x() => Icon(Icons.arrow_back);
        ''',
        rootPackage: 'apps_examples',
      );
      final ordinary = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/material.dart';
        Object x() => Icon(Icons.star);
        ''',
        rootPackage: 'apps_examples',
      );

      final translator = _translator()..translate(mirroring);
      final r = translator.translate(ordinary);

      expect(r.issues, isEmpty);
      expect(r.dsl, 'Icon(iconCodepoint: 58873)');
    });

    test('a Cupertino icon carries its font family', () async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/cupertino.dart';
        Object x() => Icon(CupertinoIcons.heart);
        ''',
        rootPackage: 'apps_examples',
      );

      final r = _translator().translate(expr);

      expect(r.issues, isEmpty);
      expect(
        r.dsl,
        matches(
          RegExp(r'^Icon\(iconCodepoint: \d+, '
              r'iconFontFamily: "CupertinoIcons"\)$'),
        ),
      );
      expect(r.dsl, isNot(contains('iconMatchTextDirection')));
    });

    test('an unresolvable icon still refuses', () async {
      final r = _translator().translate(
        await parseExpressionForTest('Icon(Icons.bolt_rounded)'),
      );

      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.unresolvedIdentifier),
      );
      expect(r.dsl, isEmpty);
    });
  });
}
