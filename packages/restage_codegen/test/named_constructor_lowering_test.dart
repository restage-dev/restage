// Named-constructor lowering on catalog widgets.
//
// A RESOLVED named constructor whose `flutterType#Type.ctor` matches no
// dedicated catalog variant entry previously fell through to the base entry
// by name, SILENTLY dropping the constructor's implied semantics (the
// `Positioned.fill` fill-drop). The governing invariant: every input is
// either correctly lowered OR rejected with an explicit diagnostic — never a
// silent wrong/degraded blob. `Positioned.fill` lowers faithfully (zero
// edges, explicit overrides win); every other unmatched named constructor
// defers loud.
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/paywall_helpers.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  ExpressionTranslator translatorWith(List<WidgetEntry> widgets) =>
      ExpressionTranslator(
        catalog: catalogWith(widgets),
        helpers: HelperRegistry()..registerAll(paywallHelpers),
      );

  final positionedEntry = entry(
    name: 'Positioned',
    flutterType: 'package:flutter/src/widgets/basic.dart#Positioned',
    properties: [
      prop('left', PropertyType.length),
      prop('top', PropertyType.length),
      prop('right', PropertyType.length),
      prop('bottom', PropertyType.length),
      prop('child', PropertyType.widget),
    ],
  );
  final sizedBoxEntry = entry(
    name: 'SizedBox',
    flutterType: 'package:flutter/src/widgets/basic.dart#SizedBox',
    properties: [
      prop('width', PropertyType.length),
      prop('height', PropertyType.length),
      prop('child', PropertyType.widget),
    ],
  );

  group('Positioned.fill — faithful zero-edge lowering', () {
    test('Positioned.fill injects the four zero edges', () async {
      final t = translatorWith([positionedEntry, sizedBoxEntry]);
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/widgets.dart';
        Object x() => Positioned.fill(child: const SizedBox());
        ''',
        rootPackage: 'apps_examples',
      );
      final result = t.translate(expr);
      expect(result.issues, isEmpty);
      expect(
        result.dsl,
        contains(
          'Positioned(left: 0.0, top: 0.0, right: 0.0, bottom: 0.0, '
          'child: SizedBox())',
        ),
      );
    });

    test('Positioned.fill(left: 8) — the explicit edge wins, others stay 0',
        () async {
      final t = translatorWith([positionedEntry, sizedBoxEntry]);
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/widgets.dart';
        Object x() => Positioned.fill(left: 8, child: const SizedBox());
        ''',
        rootPackage: 'apps_examples',
      );
      final result = t.translate(expr);
      expect(result.issues, isEmpty);
      // left is the author's explicit value; the other three default to 0.
      expect(result.dsl, contains('left: 8.0'));
      expect(result.dsl, contains('top: 0.0'));
      expect(result.dsl, contains('right: 0.0'));
      expect(result.dsl, contains('bottom: 0.0'));
    });
  });

  group('every other unmatched named ctor defers loud (class closed)', () {
    test('SizedBox.shrink defers with a named diagnostic, never silent base',
        () async {
      final t = translatorWith([positionedEntry, sizedBoxEntry]);
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/widgets.dart';
        Object x() => const SizedBox.shrink();
        ''',
        rootPackage: 'apps_examples',
      );
      final result = t.translate(expr);
      // NOT a silent `SizedBox()` emission — a loud defer.
      expect(
        result.issues.map((i) => i.code),
        contains(IssueCode.namedConstructorUnsupported),
      );
      expect(result.dsl, isNot(contains('SizedBox(')));
    });
  });

  group('regression: matched-by-flutterType variants are untouched', () {
    test('a named ctor that matches a dedicated variant entry resolves to it',
        () async {
      // A synthetic widget with a `.compact` named ctor whose flutterType
      // matches a dedicated catalog entry: the named-ctor handling must be
      // SKIPPED (matched by flutterType), exactly as Card.filled -> CardFilled
      // resolves in the real catalog.
      final base = entry(
        name: 'Slab',
        flutterType: 'package:flutter/src/widgets/basic.dart#Slab',
        properties: [prop('child', PropertyType.widget)],
      );
      final variant = entry(
        name: 'SlabCompact',
        flutterType: 'package:flutter/src/widgets/basic.dart#Slab.compact',
        properties: [prop('child', PropertyType.widget)],
      );
      // Resolve `Slab.compact(...)` against a flutter-mounted stub by reusing
      // the real Positioned type's library: use SizedBox as the carrier so the
      // resolved flutterType is `...#SizedBox.fromSize` (a real named ctor),
      // and map a dedicated entry to it.
      final sizedFromSize = entry(
        name: 'SizedBoxFromSize',
        flutterType: 'package:flutter/src/widgets/basic.dart#SizedBox.fromSize',
        properties: [prop('child', PropertyType.widget)],
      );
      final t = translatorWith([sizedBoxEntry, sizedFromSize, base, variant]);
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/widgets.dart';
        Object x() => const SizedBox.fromSize(child: SizedBox());
        ''',
        rootPackage: 'apps_examples',
      );
      final result = t.translate(expr);
      // Resolves to the dedicated SizedBoxFromSize entry — no defer.
      expect(result.issues, isEmpty);
      expect(result.dsl, contains('SizedBoxFromSize('));
    });

    test('a default constructor (no named ctor) is unchanged', () async {
      final t = translatorWith([positionedEntry, sizedBoxEntry]);
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/widgets.dart';
        Object x() => Positioned(left: 1, top: 2, child: const SizedBox());
        ''',
        rootPackage: 'apps_examples',
      );
      final result = t.translate(expr);
      expect(result.issues, isEmpty);
      expect(
        result.dsl,
        contains('Positioned(left: 1.0, top: 2.0, child: SizedBox())'),
      );
    });
  });
}
