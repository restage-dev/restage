// Governing-invariant gate for the `alignmentXY` slot source-lowering.
//
// The concrete-`Alignment` slot — `AnimatedScale.alignment` /
// `AnimatedRotation.alignment`, typed `PropertyType.alignmentXY` and decoded by
// `RestageDecoders.alignmentXY` from a `{x, y}` map — now LOWERS a Dart-source
// `Alignment.<member>` / `Alignment(x, y)` to that map AT THE SLOT, replacing
// the prior accidental floor-catch of a bare member string. Everything not
// provably a framework `Alignment` value stays diagnosed:
//   * a resolved customer `Alignment` look-alike DEFERS (no `{x, y}`
//     substitution AND no bare member string — the diagnosed defer);
//   * `AlignmentDirectional` and unsupported members diagnose;
//   * a genuinely-unknown property still diagnoses (the Phase-4 regression
//     condition: opening one known slot must not make unknown props vanish).
//
// Positives are VALUE-asserted against the real Flutter constants. Negatives
// use the production constructor (strict framework predicate); the look-alike
// negative resolves real Flutter (`rootPackage: 'apps_examples'`) so the gate
// fires on the LOCAL customer class.

import 'package:restage_codegen/src/catalog_validator.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_shared/rfw_formats.dart' show parseLibraryFile;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final catalog = catalogWith([
    entry(
      name: 'AnimatedScale',
      category: WidgetCategory.decoration,
      childrenSlot: ChildrenSlot.single,
      properties: [
        prop('scale', PropertyType.real, required: true),
        prop('alignment', PropertyType.alignmentXY),
        prop('child', PropertyType.widget),
      ],
    ),
    entry(
      name: 'AnimatedRotation',
      category: WidgetCategory.decoration,
      childrenSlot: ChildrenSlot.single,
      properties: [
        prop('turns', PropertyType.real, required: true),
        prop('alignment', PropertyType.alignmentXY),
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

  Future<Iterable<IssueCode>> issueCodesFor(String source) async {
    final result = await translateUnresolved(source);
    final library = parseLibraryFile(
      '''
      import restage.core;
      widget Paywall = ${result.dsl};
      ''',
      sourceIdentifier: 'test',
    );
    return [
      ...result.issues,
      ...validateModelAgainstCatalog(library, catalog),
    ].map((issue) => issue.code);
  }

  group('alignmentXY slot lowers a framework Alignment value (value-asserted)',
      () {
    test('Alignment.center member -> {x: 0.0, y: 0.0}', () async {
      final r = await translateUnresolved(
        'AnimatedScale(scale: 1.0, alignment: Alignment.center, '
        'child: SizedBox())',
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, contains('alignment: {x: 0.0, y: 0.0}'));
    });

    test('Alignment.topRight member -> {x: 1.0, y: -1.0}', () async {
      final r = await translateUnresolved(
        'AnimatedRotation(turns: 0.5, alignment: Alignment.topRight, '
        'child: SizedBox())',
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, contains('alignment: {x: 1.0, y: -1.0}'));
    });

    test('Alignment(x, y) ctor -> {x: 0.5, y: 0.3}', () async {
      final r = await translateUnresolved(
        'AnimatedScale(scale: 1.0, alignment: Alignment(0.5, 0.3), '
        'child: SizedBox())',
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, contains('alignment: {x: 0.5, y: 0.3}'));
    });

    test('a known alignmentXY slot no longer diagnoses a value-shape mismatch',
        () async {
      final codes = await issueCodesFor(
        'AnimatedScale(scale: 1.0, alignment: Alignment.center, '
        'child: SizedBox())',
      );
      expect(codes, isNot(contains(IssueCode.unknownProperty)));
      expect(codes, isNot(contains(IssueCode.propertyValueTypeMismatch)));
    });

    test(
        'a real-Flutter Alignment.bottomRight at the slot still lowers when '
        'fully resolved -> {x: 1.0, y: 1.0}', () async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/material.dart'
            show AnimatedScale, Alignment, SizedBox;
        Object x() => AnimatedScale(
          scale: 1.0,
          alignment: Alignment.bottomRight,
          child: SizedBox(),
        );
        ''',
        rootPackage: 'apps_examples',
      );
      final r = translator.translate(expr);
      expect(r.issues, isEmpty);
      expect(r.dsl, contains('alignment: {x: 1.0, y: 1.0}'));
    });
  });

  group('alignmentXY slot diagnoses what it cannot provably lower', () {
    test(
        'a resolved customer Alignment look-alike DEFERS at the slot — '
        'no {x, y} substitution, no bare member string', () async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/material.dart' show AnimatedScale, SizedBox;
        class Alignment {
          const Alignment(this.x, this.y);
          final double x;
          final double y;
          static const Alignment topRight = Alignment(1, -1);
        }
        Object x() => AnimatedScale(
          scale: 1.0,
          alignment: Alignment.topRight,
          child: SizedBox(),
        );
        ''',
        rootPackage: 'apps_examples',
      );
      final r = translator.translate(expr);
      expect(r.issues, isNotEmpty);
      expect(r.issues.first.code, IssueCode.unresolvedIdentifier);
      // No coordinate substitution (topRight would be {x: 1.0, y: -1.0}).
      expect(r.dsl, isNot(contains('x: 1.0')));
      // No bare member-name silent-loss string.
      expect(r.dsl, isNot(contains('"topRight"')));
    });

    test('AlignmentDirectional is not a concrete Alignment — diagnoses',
        () async {
      final r = await translateUnresolved(
        'AnimatedScale(scale: 1.0, '
        'alignment: AlignmentDirectional.centerStart, child: SizedBox())',
      );
      expect(r.issues, isNotEmpty);
      expect(r.issues.first.code, IssueCode.unrecognizedMethodCall);
      // Never lowers a directional member to a bare string the floor would
      // then have to catch.
      expect(r.dsl, isNot(contains('"centerStart"')));
    });

    test('an unsupported Alignment member diagnoses', () async {
      final r = await translateUnresolved(
        'AnimatedScale(scale: 1.0, alignment: Alignment.bogus, '
        'child: SizedBox())',
      );
      expect(r.issues, isNotEmpty);
      expect(r.issues.first.code, IssueCode.unresolvedIdentifier);
      expect(r.dsl, isNot(contains('"bogus"')));
    });

    test('a genuinely unknown property still diagnoses (regression guard)',
        () async {
      final codes = await issueCodesFor(
        'AnimatedScale(scale: 1.0, bogus: 1, child: SizedBox())',
      );
      expect(codes, contains(IssueCode.unknownProperty));
    });
  });
}
