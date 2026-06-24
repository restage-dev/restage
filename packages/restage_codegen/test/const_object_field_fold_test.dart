import 'package:analyzer/dart/ast/ast.dart';
import 'package:restage_codegen/src/const_folding.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/widget_classification.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Resolves [source] (which must define `Object x() => <expr>;`) to the
/// fully-resolved returned expression — element references populated, so the
/// const-object-field discriminator and resolver see real elements.
Future<Expression> _expr(String source) =>
    parseExpressionFromSourceForTest(source);

/// A minimal pure-Dart skin data class with named `this.field` formals, plus a
/// const instance and an unrelated enum / static-const namespace — the common
/// const-object-field-access shape the recreations use.
const String _namedSkin = '''
class Skin {
  const Skin({required this.headline, required this.primary, this.nested});
  final String headline;
  final int primary;
  final Inner? nested;
}

class Inner {
  const Inner({required this.v});
  final int v;
}

enum Align { start, center }

class Tokens {
  static const double gap = 16;
}

const _skin = Skin(headline: 'Hello', primary: 0xFF112233, nested: Inner(v: 7));
''';

void main() {
  group('isConstObjectFieldAccess (discriminator)', () {
    test('true for a const-object String instance field', () async {
      final e = await _expr('$_namedSkin Object x() => _skin.headline;');
      expect(isConstObjectFieldAccess(e), isTrue);
    });

    test('true for a const-object int instance field', () async {
      final e = await _expr('$_namedSkin Object x() => _skin.primary;');
      expect(isConstObjectFieldAccess(e), isTrue);
    });

    test('false for an enum reference (prefix is a TYPE)', () async {
      final e = await _expr('$_namedSkin Object x() => Align.center;');
      expect(isConstObjectFieldAccess(e), isFalse);
    });

    test('false for a static-const scalar reference (Tokens.gap)', () async {
      final e = await _expr('$_namedSkin Object x() => Tokens.gap;');
      expect(isConstObjectFieldAccess(e), isFalse);
    });

    test('false for a plain const var (not a field access)', () async {
      final e = await _expr('const double kGap = 8; Object x() => kGap;');
      expect(isConstObjectFieldAccess(e), isFalse);
    });

    test('false for a non-const (final) receiver field access', () async {
      final e = await _expr(
        'class S { const S(this.h); final String h; } '
        'final _s = const S("x"); Object x() => _s.h;',
      );
      expect(isConstObjectFieldAccess(e), isFalse);
    });
  });

  group('resolveConstObjectFieldInitializer (β — AST substitution)', () {
    test('named String field → the bound string-literal expression', () async {
      final e = await _expr('$_namedSkin Object x() => _skin.headline;');
      final init = resolveConstObjectFieldInitializer(e);
      expect(init, isNotNull);
      expect(init!.toSource(), "'Hello'");
    });

    test('named int field → the bound integer-literal expression', () async {
      final e = await _expr('$_namedSkin Object x() => _skin.primary;');
      final init = resolveConstObjectFieldInitializer(e);
      expect(init!.toSource(), '0xFF112233');
    });

    test('structured field → the bound InstanceCreationExpression', () async {
      final e = await _expr('$_namedSkin Object x() => _skin.nested;');
      final init = resolveConstObjectFieldInitializer(e);
      expect(init, isA<InstanceCreationExpression>());
      expect(init!.toSource(), 'Inner(v: 7)');
    });

    test('positional this.field formal → the bound positional arg', () async {
      final e = await _expr(
        'class S { const S(this.h, this.p); final String h; final int p; } '
        "const _s = S('Hi', 5); Object x() => _s.h;",
      );
      final init = resolveConstObjectFieldInitializer(e);
      expect(init!.toSource(), "'Hi'");
    });

    test('nested field access (_x.a.b) recurses to the deep literal', () async {
      final e = await _expr(
        'class Outer { const Outer({required this.a}); final Inner a; } '
        'class Inner { const Inner({required this.b}); final String b; } '
        "const _x = Outer(a: Inner(b: 'deep')); Object x() => _x.a.b;",
      );
      final init = resolveConstObjectFieldInitializer(e);
      expect(init!.toSource(), "'deep'");
    });

    test('returns null for a not-passed field with a default (β only)',
        () async {
      final e = await _expr(
        "class S { const S({this.h = 'def'}); final String h; } "
        'const _s = S(); Object x() => _s.h;',
      );
      // β substitutes only a bound argument expression; a defaulted field is
      // not bound in the constructor call, so β declines (α folds the scalar).
      expect(resolveConstObjectFieldInitializer(e), isNull);
    });

    test('returns null for an enum reference', () async {
      final e = await _expr('$_namedSkin Object x() => Align.center;');
      expect(resolveConstObjectFieldInitializer(e), isNull);
    });

    test('returns null for a static-const scalar reference', () async {
      final e = await _expr('$_namedSkin Object x() => Tokens.gap;');
      expect(resolveConstObjectFieldInitializer(e), isNull);
    });
  });

  group('tryScalarFoldConstObjectField (α — DartObject scalar fallback)', () {
    test('folds a String instance field to its scalar value', () async {
      final e = await _expr('$_namedSkin Object x() => _skin.headline;');
      expect(tryScalarFoldConstObjectField(e), 'Hello');
    });

    test('folds an int instance field to its scalar value', () async {
      final e = await _expr('$_namedSkin Object x() => _skin.primary;');
      expect(tryScalarFoldConstObjectField(e), 0xFF112233);
    });

    test('folds a defaulted field to its default scalar', () async {
      final e = await _expr(
        "class S { const S({this.h = 'def'}); final String h; } "
        'const _s = S(); Object x() => _s.h;',
      );
      expect(tryScalarFoldConstObjectField(e), 'def');
    });

    test('returns null for a structured (non-scalar) field', () async {
      final e = await _expr('$_namedSkin Object x() => _skin.nested;');
      expect(tryScalarFoldConstObjectField(e), isNull);
    });

    test('returns null for an enum reference (not a const-object field)',
        () async {
      final e = await _expr('$_namedSkin Object x() => Align.center;');
      expect(tryScalarFoldConstObjectField(e), isNull);
    });
  });

  group('tryFoldConstant stays scalar-only (unchanged contract)', () {
    test('does not fold a const-object instance field', () async {
      // The structured-reference sibling resolver folds this; tryFoldConstant
      // keeps its scalar-only contract and declines a const-object field.
      final e = await _expr('$_namedSkin Object x() => _skin.headline;');
      expect(tryFoldConstant(e), isNull);
    });
  });

  group('tryFoldScalarConstant (the unified scalar boundary)', () {
    // The shared scalar-extraction boundary for codegen sites that read a const
    // scalar directly (bypassing _translate / the const-object hook): a plain
    // const scalar OR a const-object scalar field. Used wherever a String / int
    // const is collected outside the translate dispatch (e.g. event-name scan,
    // map keys, Duration units) so those agree with what emission folds.
    test('folds a plain const scalar (via tryFoldConstant)', () async {
      final e = await _expr('Object x() => 42;');
      expect(tryFoldScalarConstant(e), 42);
    });

    test('folds a const-object String field (via the α sibling)', () async {
      final e = await _expr('$_namedSkin Object x() => _skin.headline;');
      expect(tryFoldScalarConstant(e), 'Hello');
    });

    test('folds a const-object int field (via the α sibling)', () async {
      final e = await _expr('$_namedSkin Object x() => _skin.primary;');
      expect(tryFoldScalarConstant(e), 0xFF112233);
    });

    test('returns null for a structured const-object field', () async {
      final e = await _expr('$_namedSkin Object x() => _skin.nested;');
      expect(tryFoldScalarConstant(e), isNull);
    });

    test('returns null for an enum reference', () async {
      final e = await _expr('$_namedSkin Object x() => Align.center;');
      expect(tryFoldScalarConstant(e), isNull);
    });
  });

  group('translator integration (emit-confirmation)', () {
    late ExpressionTranslator translator;

    setUp(() {
      translator = ExpressionTranslator(
        catalog: kEmptyCatalog,
        helpers: HelperRegistry(),
      );
    });

    test(
        'const-object String field folds to its literal — closes the silent '
        'wrong-render (was the bare field name)', () async {
      final r = translator
          .translate(await _expr('$_namedSkin Object x() => _skin.headline;'));
      expect(r.dsl, '"Hello"');
      expect(r.issues, isEmpty);
    });

    test('const-object Color field folds byte-identical to the inline Color',
        () async {
      const skinSource = '''
        import 'package:flutter/material.dart';
        class Skin { const Skin({required this.primary}); final Color primary; }
        const _skin = Skin(primary: Color(0xFF112233));
        Object x() => _skin.primary;
      ''';
      final folded = translator.translate(
        await parseExpressionFromSourceForTest(
          skinSource,
          rootPackage: 'apps_examples',
        ),
      );
      final inline = translator.translate(
        await parseExpressionFromSourceForTest(
          "import 'package:flutter/material.dart'; "
          'Object x() => const Color(0xFF112233);',
          rootPackage: 'apps_examples',
        ),
      );
      expect(folded.issues, isEmpty);
      expect(folded.dsl, '0xFF112233');
      // The fold re-runs the inline value recipe, so it is byte-identical to
      // the inline literal by construction (the chapter's structural goal).
      expect(folded.dsl, inline.dsl);
    });

    test(
        'an unresolvable const-object field defers LOUD — never the field name',
        () async {
      // The structured field is bound in the initializer list (not a
      // field-formal), so β cannot substitute its AST and α cannot scalar-fold
      // a Color — the recognised-but-unfoldable case. It must defer loud, never
      // fall through to the silent bare-name emit. (Cross-file structured const
      // objects hit the same path via β being same-unit only.)
      const source = '''
        import 'package:flutter/material.dart';
        class Skin {
          const Skin({Color? primary})
              : primary = primary ?? const Color(0xFF000000);
          final Color primary;
        }
        const _skin = Skin();
        Object x() => _skin.primary;
      ''';
      final r = translator.translate(
        await parseExpressionFromSourceForTest(
          source,
          rootPackage: 'apps_examples',
        ),
      );
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.constObjectFieldUnresolved),
      );
      expect(r.dsl, isEmpty);
      expect(r.dsl, isNot(contains('primary')));
    });

    test('an enum reference still lowers to its bare name (unchanged)',
        () async {
      final r = translator.translate(
        await parseExpressionFromSourceForTest(
          "import 'package:flutter/material.dart'; "
          'Object x() => MainAxisAlignment.center;',
          rootPackage: 'apps_examples',
        ),
      );
      expect(r.dsl, '"center"');
    });

    test('a static-const scalar reference still folds (unchanged)', () async {
      final r = translator.translate(
        await _expr(
          'class Tokens { static const double gap = 16; } '
          'Object x() => Tokens.gap;',
        ),
      );
      expect(r.dsl, '16.0');
    });
  });

  group('const-object field at a type-special slot (alignmentXY)', () {
    test(
        'folds at the alignmentXY slot — slot lowering applies to the folded '
        'value (classifier↔translator consistency at special slots)', () async {
      // The alignmentXY slot bypasses the generic _translate path (it calls
      // _structured.alignmentGeometry directly), so the const-object hook must
      // also run on the slot path. `_skin.align` → Alignment.center → the slot
      // lowering → {x: 0.0, y: 0.0}, NOT a loud-defer.
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
        entry(name: 'SizedBox', properties: [prop('width', PropertyType.real)]),
      ]);
      final translator =
          ExpressionTranslator(catalog: catalog, helpers: HelperRegistry());
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/material.dart'
            show AnimatedScale, Alignment, SizedBox;
        class Skin { const Skin({required this.align}); final Alignment align; }
        const _skin = Skin(align: Alignment.center);
        Object x() => AnimatedScale(
          scale: 1.0,
          alignment: _skin.align,
          child: SizedBox(),
        );
        ''',
        rootPackage: 'apps_examples',
      );
      final r = translator.translate(expr);
      expect(r.issues, isEmpty);
      expect(r.dsl, contains('alignment: {x: 0.0, y: 0.0}'));
    });
  });

  group('classifier consultation (classifier↔translator consistency)', () {
    Catalog skinCatalog(String file) => catalogWith([
          entry(
            name: 'Text',
            properties: [prop('data', PropertyType.string, positional: true)],
            flutterType: 'package:apps_examples/$file#Text',
          ),
        ]);

    test('a foldable const-object field marks constantFolding (transpilable)',
        () async {
      final result = await classifyFixture(
        {
          'lib/skin_widget.dart': '''
$kClassifierStubs

class Skin { const Skin({required this.label}); final String label; }
const _skin = Skin(label: 'Pro');

class Text extends StatelessWidget {
  const Text(this.data);
  final String? data;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeSkinned',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.display,
  description: 'skinned',
)
class AcmeSkinned extends StatelessWidget {
  const AcmeSkinned();
  Widget build(BuildContext context) => Text(_skin.label);
}
''',
        },
        inputPath: 'lib/skin_widget.dart',
        widgetName: 'AcmeSkinned',
        catalog: skinCatalog('skin_widget.dart'),
      );
      expect(result, isA<ComposableWidget>());
      expect(
        (result as ComposableWidget).requiredMechanisms,
        contains(InliningMechanism.constantFolding),
      );
    });

    test(
        'an unfoldable const-object field defers — same verdict as the '
        'translator loud-defer (no divergence)', () async {
      final result = await classifyFixture(
        {
          'lib/skin_widget2.dart': '''
$kClassifierStubs

class Inner { const Inner(this.v); final int v; }
class Skin {
  const Skin({Inner? nested}) : nested = nested ?? const Inner(0);
  final Inner nested;
}
const _skin = Skin();

class Text extends StatelessWidget {
  const Text(this.data);
  final Object? data;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeUnfoldable',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.display,
  description: 'unfoldable',
)
class AcmeUnfoldable extends StatelessWidget {
  const AcmeUnfoldable();
  Widget build(BuildContext context) => Text(_skin.nested);
}
''',
        },
        inputPath: 'lib/skin_widget2.dart',
        widgetName: 'AcmeUnfoldable',
        catalog: skinCatalog('skin_widget2.dart'),
      );
      expect(result, isA<UnclassifiableWidget>());
    });
  });
}
