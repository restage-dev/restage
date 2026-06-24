// Value-proof for the two newly-surfaced concrete-`Offset` widget slots:
// `TransformRotate.origin` (was `Transform.rotate.origin`) and `Badge.offset`.
//
// Both surface as optional `PropertyType.offset` slots decoded by
// `RestageDecoders.offset` from a `{x, y}` map. A Dart-source `Offset(x, y)` at
// either slot lowers to that map through the SAME element-gated `_offset`
// translator arm that already serves `AnimatedSlide.offset` — no translator
// change; the only new fact is the catalog now carries these two slots (see the
// `restage_core` / `restage_material` registry tests for the catalog side, and
// the real `Transform.rotate` -> `TransformRotate` named-constructor mapping is
// pre-existing, exercised by the other surfaced props).
//
// The positives are VALUE-asserted. The negative reuses the production
// strict-framework predicate: a resolved customer `Offset` look-alike DEFERS at
// the slot (no `{x, y}` substitution) rather than silently lowering — the
// governing invariant (lower-correctly OR diagnose, never silent-wrong).

import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final catalog = catalogWith([
    entry(
      name: 'TransformRotate',
      category: WidgetCategory.decoration,
      childrenSlot: ChildrenSlot.single,
      properties: [
        prop('angle', PropertyType.real, required: true),
        prop('origin', PropertyType.offset),
        prop('child', PropertyType.widget),
      ],
    ),
    entry(
      name: 'Badge',
      category: WidgetCategory.decoration,
      childrenSlot: ChildrenSlot.single,
      properties: [
        prop('offset', PropertyType.offset),
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

  group('offset-field slots lower a framework Offset value (value-asserted)',
      () {
    test('TransformRotate.origin: Offset(x, y) -> {x: 0.3, y: -0.4}', () async {
      final r = await translateUnresolved(
        'TransformRotate(angle: 0.0, origin: Offset(0.3, -0.4), '
        'child: SizedBox())',
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, contains('origin: {x: 0.3, y: -0.4}'));
    });

    test('Badge.offset: Offset(x, y) -> {x: 2.0, y: -3.0}', () async {
      final r = await translateUnresolved(
        'Badge(offset: Offset(2.0, -3.0), child: SizedBox())',
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, contains('offset: {x: 2.0, y: -3.0}'));
    });

    test('a fully-resolved real-Flutter Badge.offset lowers when resolved',
        () async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/material.dart' show Badge, SizedBox;
        import 'dart:ui' show Offset;
        Object x() => Badge(
          offset: Offset(0.0, 4.0),
          child: SizedBox(),
        );
        ''',
        rootPackage: 'apps_examples',
      );
      final r = translator.translate(expr);
      expect(r.issues, isEmpty);
      expect(r.dsl, contains('offset: {x: 0.0, y: 4.0}'));
    });
  });

  group('offset-field slots diagnose what they cannot provably lower', () {
    test(
        'a resolved customer Offset look-alike at Badge.offset DEFERS — '
        'no {x, y} substitution', () async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/material.dart' show Badge, SizedBox;
        class Offset {
          const Offset(this.dx, this.dy);
          final double dx;
          final double dy;
        }
        Object x() => Badge(
          offset: Offset(0.5, 0.5),
          child: SizedBox(),
        );
        ''',
        rootPackage: 'apps_examples',
      );
      final r = translator.translate(expr);
      expect(r.issues, isNotEmpty);
      // The outer value-substitution gate routes a resolved non-framework ctor
      // to widget construction (defer), never the `_offset` lowering.
      expect(r.dsl, isNot(contains('x: 0.5')));
    });
  });
}
