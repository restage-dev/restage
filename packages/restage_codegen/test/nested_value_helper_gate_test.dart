// The nested name-only value-helper gate.
//
// The outermost value-substitution gate (in `_instanceCreation` /
// `_methodInvocation`) defers a TOP-LEVEL customer value-type look-alike. But a
// value-type argument NESTED inside a REAL framework constructor is lowered by
// hand-authored helpers (and the recipe member-table) that dispatch by NAME
// ONLY — no element check. So a real-framework `LinearGradient` / `RadialGradient`
// / `RoundedRectangleBorder` passes the outer gate, then its inner value-type
// argument (a customer `Alignment.topLeft` / `BorderSide.none` look-alike) would
// silently emit the framework value with no diagnostic.
//
// These tests pin the closure: every nested helper element-gates its name
// dispatch on the shared framework-library predicate (defer-on-resolved-non-
// framework, name-fallback-on-unresolved). A resolved customer look-alike
// DEFERS WITH A DIAGNOSTIC — emitting NO framework value AND NO bare member
// string (the diagnosed defer, never the bare-string fallback = the silent-loss
// vector). Real-framework members still lower correctly (the positive guards).
//
// Negatives use the PRODUCTION constructor (strict framework predicate) with
// real-Flutter resolution (`rootPackage: 'apps_examples'`): the real outer
// constructor is recognised, the LOCAL customer value class (mounted under
// `package:apps_examples/`) is not — so the inner gate fires. Positives assert
// the lowered value byte-for-byte (mirroring the `.zero` value-assertion
// discipline).

import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:test/test.dart';

import 'helpers.dart';

ExpressionTranslator _prodTranslator() => ExpressionTranslator(
      catalog: kEmptyCatalog,
      helpers: HelperRegistry(),
    );

void main() {
  group('_alignmentGeometry — nested gradient begin/end', () {
    test(
        'a customer Alignment nested in a real LinearGradient defers — '
        'no {x,y} substitution, no bare string', () async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/material.dart' show LinearGradient, Color;
        class Alignment {
          const Alignment(this.x, this.y);
          final double x;
          final double y;
          static const Alignment topLeft = Alignment(-1, -1);
        }
        Object x() => LinearGradient(
          begin: Alignment.topLeft,
          colors: <Color>[Color(0xFF000000), Color(0xFFFFFFFF)],
        );
        ''',
        rootPackage: 'apps_examples',
      );
      final r = _prodTranslator().translate(expr);
      expect(r.issues, isNotEmpty);
      expect(r.issues.first.code, IssueCode.unresolvedIdentifier);
      // No coordinate substitution (topLeft would be {x: -1.0, y: -1.0}).
      expect(r.dsl, isNot(contains('x: -1')));
      // No bare member-name silent-loss string.
      expect(r.dsl, isNot(contains('"topLeft"')));
    });

    test(
        'a real-Flutter Alignment.topLeft in a real LinearGradient still '
        'emits {x: -1.0, y: -1.0} (positive guard)', () async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/material.dart' show LinearGradient, Alignment, Color;
        Object x() => LinearGradient(
          begin: Alignment.topLeft,
          colors: <Color>[Color(0xFF000000), Color(0xFFFFFFFF)],
        );
        ''',
        rootPackage: 'apps_examples',
      );
      final r = _prodTranslator().translate(expr);
      expect(r.issues, isEmpty);
      expect(r.dsl, contains('begin: {x: -1.0, y: -1.0}'));
    });
  });

  group('_borderSideExpression — nested shape-border side', () {
    test(
        'a customer BorderSide.none nested in a real RoundedRectangleBorder '
        'defers — no framework map, no bare string', () async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/material.dart' show RoundedRectangleBorder;
        class BorderSide {
          const BorderSide();
          static const BorderSide none = BorderSide();
        }
        Object x() => RoundedRectangleBorder(side: BorderSide.none);
        ''',
        rootPackage: 'apps_examples',
      );
      final r = _prodTranslator().translate(expr);
      expect(r.issues, isNotEmpty);
      expect(r.issues.first.code, IssueCode.unresolvedIdentifier);
      // No framework BorderSide.none map substitution.
      expect(r.dsl, isNot(contains('style: "none"')));
      // No bare member-name silent-loss string.
      expect(r.dsl, isNot(contains('"none"')));
    });

    test(
        'a real-Flutter BorderSide.none in a real RoundedRectangleBorder still '
        'emits {width: 0.0, style: "none"} (positive guard)', () async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/material.dart' show RoundedRectangleBorder, BorderSide;
        Object x() => RoundedRectangleBorder(side: BorderSide.none);
        ''',
        rootPackage: 'apps_examples',
      );
      final r = _prodTranslator().translate(expr);
      expect(r.issues, isEmpty);
      expect(r.dsl, contains('side: {width: 0.0, style: "none"}'));
    });
  });

  group('_borderSide — nested BorderStyle style', () {
    test(
        'a customer BorderStyle.solid nested in a real BorderSide defers — '
        'no style substitution, no bare string', () async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/material.dart' show BorderSide;
        class BorderStyle {
          const BorderStyle();
          static const BorderStyle solid = BorderStyle();
        }
        Object x() => BorderSide(style: BorderStyle.solid);
        ''',
        rootPackage: 'apps_examples',
      );
      final r = _prodTranslator().translate(expr);
      expect(r.issues, isNotEmpty);
      expect(r.issues.first.code, IssueCode.unresolvedIdentifier);
      // No framework BorderStyle.solid enum-string substitution.
      expect(r.dsl, isNot(contains('style: "solid"')));
      // No bare member-name silent-loss string.
      expect(r.dsl, isNot(contains('"solid"')));
    });

    test(
        'a real-Flutter BorderStyle.solid in a real BorderSide still emits '
        'style: "solid" (positive guard)', () async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/material.dart' show BorderSide, BorderStyle;
        Object x() => BorderSide(style: BorderStyle.solid);
        ''',
        rootPackage: 'apps_examples',
      );
      final r = _prodTranslator().translate(expr);
      expect(r.issues, isEmpty);
      expect(r.dsl, contains('style: "solid"'));
    });
  });

  group('recipe member-table — nested gradient center/focal', () {
    test(
        'a customer Alignment.center nested in a real RadialGradient defers — '
        'no {x,y} substitution, no bare string', () async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/material.dart' show RadialGradient;
        class Alignment {
          const Alignment(this.x, this.y);
          final double x;
          final double y;
          static const Alignment topLeft = Alignment(-1, -1);
        }
        Object x() => RadialGradient(center: Alignment.topLeft);
        ''',
        rootPackage: 'apps_examples',
      );
      final r = _prodTranslator().translate(expr);
      expect(r.issues, isNotEmpty);
      expect(r.issues.first.code, IssueCode.unresolvedIdentifier);
      expect(r.dsl, isNot(contains('x: -1')));
      expect(r.dsl, isNot(contains('"topLeft"')));
    });

    test(
        'a real-Flutter Alignment.topLeft center still emits '
        '{x: -1.0, y: -1.0} (positive guard)', () async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/material.dart'
            show RadialGradient, Alignment, Color;
        Object x() => RadialGradient(
          center: Alignment.topLeft,
          colors: <Color>[Color(0xFF000000), Color(0xFFFFFFFF)],
        );
        ''',
        rootPackage: 'apps_examples',
      );
      final r = _prodTranslator().translate(expr);
      expect(r.issues, isEmpty);
      expect(r.dsl, contains('center: {x: -1.0, y: -1.0}'));
    });

    test(
        'a real-Flutter Alignment(x, y) center still falls through the '
        'member-table fallback (positive guard)', () async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/material.dart'
            show RadialGradient, Alignment, Color;
        Object x() => RadialGradient(
          center: Alignment(0.5, 0.3),
          colors: <Color>[Color(0xFF000000), Color(0xFFFFFFFF)],
        );
        ''',
        rootPackage: 'apps_examples',
      );
      final r = _prodTranslator().translate(expr);
      expect(r.issues, isEmpty);
      expect(r.dsl, contains('center: {x: 0.5, y: 0.3}'));
    });
  });

  group('_alignmentGeometry — nested Alignment(x, y) ctor', () {
    test(
        'a customer Alignment(x, y) nested in a real LinearGradient defers — '
        'no coordinate map', () async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/material.dart' show LinearGradient, Color;
        class Alignment {
          const Alignment(this.x, this.y);
          final double x;
          final double y;
        }
        Object x() => LinearGradient(
          begin: Alignment(0.5, 0.3),
          colors: <Color>[Color(0xFF000000), Color(0xFFFFFFFF)],
        );
        ''',
        rootPackage: 'apps_examples',
      );
      final r = _prodTranslator().translate(expr);
      expect(r.issues, isNotEmpty);
      expect(r.issues.first.code, IssueCode.unresolvedIdentifier);
      expect(r.dsl, isNot(contains('begin: {x: 0.5, y: 0.3}')));
    });

    test(
        'a real-Flutter Alignment(x, y) in a real LinearGradient still emits '
        '{x: 0.5, y: 0.3} (positive guard)', () async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/material.dart' show LinearGradient, Alignment, Color;
        Object x() => LinearGradient(
          begin: Alignment(0.5, 0.3),
          colors: <Color>[Color(0xFF000000), Color(0xFFFFFFFF)],
        );
        ''',
        rootPackage: 'apps_examples',
      );
      final r = _prodTranslator().translate(expr);
      expect(r.issues, isEmpty);
      expect(r.dsl, contains('begin: {x: 0.5, y: 0.3}'));
    });
  });

  group('_linearBorderEdge — nested LinearBorderEdge ctor', () {
    test(
        'a customer LinearBorderEdge nested in a real LinearBorder defers — '
        'no edge map', () async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/material.dart' show LinearBorder;
        class LinearBorderEdge {
          const LinearBorderEdge({this.size = 1.0, this.alignment = 0.0});
          final double size;
          final double alignment;
        }
        Object x() => LinearBorder(
          start: LinearBorderEdge(size: 0.5, alignment: -1),
        );
        ''',
        rootPackage: 'apps_examples',
      );
      final r = _prodTranslator().translate(expr);
      expect(r.issues, isNotEmpty);
      expect(r.issues.first.code, IssueCode.unresolvedIdentifier);
      expect(r.dsl, isNot(contains('start: {size: 0.5, alignment: -1.0}')));
    });

    test(
        'a real-Flutter LinearBorderEdge in a real LinearBorder still emits '
        '{size: 0.5, alignment: -1.0} (positive guard)', () async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/material.dart' show LinearBorder, LinearBorderEdge;
        Object x() => LinearBorder(
          start: LinearBorderEdge(size: 0.5, alignment: -1),
        );
        ''',
        rootPackage: 'apps_examples',
      );
      final r = _prodTranslator().translate(expr);
      expect(r.issues, isEmpty);
      expect(r.dsl, contains('start: {size: 0.5, alignment: -1.0}'));
    });
  });
}
