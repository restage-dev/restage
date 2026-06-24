// Governing-invariant gate for the `offset` slot source-lowering.
//
// A concrete-`Offset` slot — e.g. `AnimatedSlide.offset`, typed
// `PropertyType.offset` and decoded by `RestageDecoders.offset` from a `{x, y}`
// map — lowers a Dart-source `Offset(x, y)` / `Offset.zero` to that map at the
// slot. Everything not provably a framework `Offset` value stays diagnosed:
//   * a resolved customer `Offset` ctor look-alike defers via the outer
//     value-substitution gate (`unknownWidget`, no `{x, y}` substitution);
//   * a resolved customer `Offset.zero` look-alike defers with a diagnostic
//     (no `{x, y}` substitution AND no bare member string).
//
// Positives are VALUE-asserted against the real Flutter constants. Negatives
// use the production constructor (strict framework predicate); the look-alike
// negatives resolve real Flutter (`rootPackage: 'apps_examples'`) so the gate
// fires on the LOCAL customer class.

import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final catalog = catalogWith([
    entry(
      name: 'AnimatedSlide',
      category: WidgetCategory.decoration,
      childrenSlot: ChildrenSlot.single,
      properties: [
        prop('offset', PropertyType.offset, required: true),
        prop('duration', PropertyType.duration, required: true),
        prop('child', PropertyType.widget),
      ],
    ),
    entry(name: 'SizedBox', properties: [prop('width', PropertyType.real)]),
  ]);

  final translator =
      ExpressionTranslator(catalog: catalog, helpers: HelperRegistry());

  Future<({String dsl, List<Issue> issues})> translateUnresolved(
    String source,
  ) async {
    final r = translator.translate(await parseExpressionForTest(source));
    return (dsl: r.dsl, issues: r.issues);
  }

  group('offset slot lowers a framework Offset value (value-asserted)', () {
    test('Offset(x, y) ctor -> {x: 0.2, y: -0.3}', () async {
      final r = await translateUnresolved(
        'AnimatedSlide(offset: Offset(0.2, -0.3), child: SizedBox())',
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, contains('offset: {x: 0.2, y: -0.3}'));
    });

    test('Offset.zero member -> {x: 0.0, y: 0.0}', () async {
      final r = await translateUnresolved(
        'AnimatedSlide(offset: Offset.zero, child: SizedBox())',
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, contains('offset: {x: 0.0, y: 0.0}'));
    });

    test('a real-Flutter Offset(x, y) at the slot lowers when fully resolved',
        () async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/material.dart' show AnimatedSlide, SizedBox;
        import 'dart:ui' show Offset;
        Object x() => AnimatedSlide(
          offset: Offset(0.0, 1.0),
          child: SizedBox(),
        );
        ''',
        rootPackage: 'apps_examples',
      );
      final r = translator.translate(expr);
      expect(r.issues, isEmpty);
      expect(r.dsl, contains('offset: {x: 0.0, y: 1.0}'));
    });
  });

  group('offset slot diagnoses what it cannot provably lower', () {
    test(
        'a resolved customer Offset ctor look-alike DEFERS at the slot — '
        'no {x, y} substitution', () async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/material.dart' show AnimatedSlide, SizedBox;
        class Offset {
          const Offset(this.dx, this.dy);
          final double dx;
          final double dy;
        }
        Object x() => AnimatedSlide(
          offset: Offset(0.5, 0.5),
          child: SizedBox(),
        );
        ''',
        rootPackage: 'apps_examples',
      );
      final r = translator.translate(expr);
      expect(r.issues, isNotEmpty);
      // The outer value-substitution gate routes a resolved non-framework
      // ctor to widget construction (defer), never the `_offset` lowering.
      expect(r.dsl, isNot(contains('x: 0.5')));
    });

    test(
        'a resolved customer Offset.zero look-alike DEFERS at the slot — '
        'no {x, y} substitution, no bare member string', () async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/material.dart' show AnimatedSlide, SizedBox;
        class Offset {
          const Offset(this.dx, this.dy);
          final double dx;
          final double dy;
          static const Offset zero = Offset(0, 0);
        }
        Object x() => AnimatedSlide(
          offset: Offset.zero,
          child: SizedBox(),
        );
        ''',
        rootPackage: 'apps_examples',
      );
      final r = translator.translate(expr);
      expect(r.issues, isNotEmpty);
      expect(r.issues.first.code, IssueCode.unresolvedIdentifier);
      expect(r.dsl, isNot(contains('{x: 0.0, y: 0.0}')));
      expect(r.dsl, isNot(contains('"zero"')));
    });
  });
}
