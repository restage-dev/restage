// Unit coverage for the canonical theme-read recognizer in
// theme_recognition.dart. `themeReadSegments` is the single binding-aware walk
// the classifier recognizer, the translator lowerer, and the slot validator
// all route through. These tests pin the NO-binding behaviour (byte-identical
// to the pre-rung-2 PropertyAccess-only recognition); the binding-aware cases
// are exercised end-to-end in custom_widget_e2e_test.dart where resolved
// element bindings exist.

import 'package:restage_codegen/src/theme_recognition.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('themeReadSegments — no bindings (backward compatible)', () {
    test('Theme.of(c).colorScheme.primary → [colorScheme, primary]', () async {
      final expr =
          await parseExpressionForTest('Theme.of(context).colorScheme.primary');
      expect(themeReadSegments(expr), ['colorScheme', 'primary']);
    });

    test('Theme.of(c).iconTheme.size → [iconTheme, size]', () async {
      final expr =
          await parseExpressionForTest('Theme.of(context).iconTheme.size');
      expect(themeReadSegments(expr), ['iconTheme', 'size']);
    });

    test('DefaultTextStyle.of(c).style.color → [defaultTextStyle, color]',
        () async {
      final expr = await parseExpressionForTest(
        'DefaultTextStyle.of(context).style.color',
      );
      expect(themeReadSegments(expr), ['defaultTextStyle', 'color']);
    });

    test('DefaultTextStyle.of(c).maxLines (no leading style) → null', () async {
      final expr =
          await parseExpressionForTest('DefaultTextStyle.of(context).maxLines');
      expect(themeReadSegments(expr), isNull);
    });

    test('a non-theme PropertyAccess → null', () async {
      final expr = await parseExpressionForTest('someFn().length');
      expect(themeReadSegments(expr), isNull);
    });

    test('a bound-local-shaped PrefixedIdentifier with NO bindings → null',
        () async {
      // `scheme.primary` is a PrefixedIdentifier; without a binding for the
      // `scheme` prefix it is not a theme read and must not be recognised.
      final expr = await parseExpressionForTest('scheme.primary');
      expect(themeReadSegments(expr), isNull);
    });

    test('isThemeReadChain agrees with themeReadSegments (no bindings)',
        () async {
      final themeExpr =
          await parseExpressionForTest('Theme.of(context).colorScheme.primary');
      final plainExpr = await parseExpressionForTest('someFn().length');
      expect(isThemeReadChain(themeExpr), isTrue);
      expect(isThemeReadChain(plainExpr), isFalse);
    });
  });
}
