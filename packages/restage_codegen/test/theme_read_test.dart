// Translator-side coverage for the theme-as-data mechanism: recognising
// `Theme.of(context).<x>(.<y>)` reads and emitting `data.theme.<x>.<y>`
// references the SDK's data.theme.* channel resolves at render time.

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_shared/restage_shared.dart'
    show kThemeContractPathKinds, kThemeContractPaths;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('ExpressionTranslator — theme reads (recognition)', () {
    late ExpressionTranslator translator;

    setUp(() {
      translator = ExpressionTranslator(
        catalog: kEmptyCatalog,
        helpers: HelperRegistry(),
      );
    });

    test('Theme.of(c).colorScheme.primary → data.theme.colorScheme.primary',
        () async {
      final expr = await parseExpressionForTest(
        'Theme.of(context).colorScheme.primary',
      );
      final result = translator.translate(expr);

      expect(result.issues, isEmpty);
      expect(result.dsl, 'data.theme.colorScheme.primary');
    });

    test('a non-theme PropertyAccess falls through to the existing diagnostic',
        () async {
      // A PropertyAccess whose root is not Theme.of(...) is not a theme read
      // and must not be intercepted. The existing not-recognised diagnostic
      // (`unrecognizedMethodCall`) fires unchanged. `someFn().length` is a
      // PropertyAccess(MethodInvocation, 'length') — the simplest non-theme
      // shape; `x.length` would parse as a PrefixedIdentifier and miss the
      // PropertyAccess dispatch entirely.
      final expr = await parseExpressionForTest('someFn().length');
      final result = translator.translate(expr);

      expect(result.dsl, '');
      expect(result.issues, isNotEmpty);
      expect(
        result.issues.any((i) => i.code == IssueCode.unrecognizedMethodCall),
        isTrue,
      );
      expect(
        result.issues.any((i) => i.message.contains('data.theme')),
        isFalse,
      );
    });

    test('a Theme.of(...) chain with a non-identifier context falls through',
        () async {
      // The argument to Theme.of(...) must be a bare identifier — the
      // shape an author writes for the BuildContext. Anything else is not
      // a recognised theme read.
      final expr = await parseExpressionForTest(
        'Theme.of(buildContextOf(x)).colorScheme.primary',
      );
      final result = translator.translate(expr);

      // Falls through to the existing diagnostic (no theme-read emission).
      expect(result.dsl, '');
      expect(
        result.issues.any((i) => i.message.contains('data.theme')),
        isFalse,
      );
    });

    test('a chain rooted at a method other than Theme.of falls through',
        () async {
      // `Foo.bar(c).baz` is structurally similar but is not a theme read.
      final expr = await parseExpressionForTest('Foo.bar(c).colorScheme');
      final result = translator.translate(expr);

      expect(result.dsl, '');
      expect(
        result.issues.any((i) => i.message.contains('data.theme')),
        isFalse,
      );
    });
  });

  group('ExpressionTranslator — theme reads (resolved fixture guard)', () {
    test('real Flutter fixtures resolve Theme.of to Flutter Theme', () async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/material.dart';

        Object x(BuildContext context) =>
            Theme.of(context).colorScheme.primary;
      ''',
        rootPackage: 'apps_examples',
      );

      final invocation = _methodInvocationNamed(expr, 'of');
      final element = invocation.methodName.element;

      expect(element, isNotNull);
      expect(element!.library?.identifier, startsWith('package:flutter/'));
      expect(element.enclosingElement?.name, 'Theme');
    });
  });

  group('ExpressionTranslator — theme reads (contract validation)', () {
    late ExpressionTranslator translator;

    setUp(() {
      translator = ExpressionTranslator(
        catalog: kEmptyCatalog,
        helpers: HelperRegistry(),
      );
    });

    test('an in-contract path (colorScheme.primary) emits the data ref',
        () async {
      final expr = await parseExpressionForTest(
        'Theme.of(context).colorScheme.primary',
      );
      final result = translator.translate(expr);

      expect(result.issues, isEmpty);
      expect(result.dsl, 'data.theme.colorScheme.primary');
    });

    test('an in-contract path (iconTheme.size) emits the data ref', () async {
      final expr = await parseExpressionForTest(
        'Theme.of(context).iconTheme.size',
      );
      final result = translator.translate(expr);

      expect(result.issues, isEmpty);
      expect(result.dsl, 'data.theme.iconTheme.size');
    });

    test('an in-contract path (defaultTextStyle.fontWeight) emits the data ref',
        () async {
      final expr = await parseExpressionForTest(
        'Theme.of(context).defaultTextStyle.fontWeight',
      );
      final result = translator.translate(expr);

      expect(result.issues, isEmpty);
      expect(result.dsl, 'data.theme.defaultTextStyle.fontWeight');
    });

    test(
        'an out-of-contract path (textTheme.bodyLarge) emits the '
        'themeReadOutOfContract diagnostic, no data ref', () async {
      final expr = await parseExpressionForTest(
        'Theme.of(context).textTheme.bodyLarge',
      );
      final result = translator.translate(expr);

      expect(result.dsl, '');
      expect(result.issues, hasLength(1));
      expect(result.issues.single.code, IssueCode.themeReadOutOfContract);
      expect(result.issues.single.message, contains('textTheme.bodyLarge'));
    });

    test(
        'an out-of-contract path (colorScheme alone, no sub-key) emits the '
        'themeReadOutOfContract diagnostic', () async {
      // The contract publishes leaves only; a chain that bottoms out at a
      // namespace name (colorScheme without a role) cannot resolve.
      final expr = await parseExpressionForTest(
        'Theme.of(context).colorScheme',
      );
      final result = translator.translate(expr);

      expect(result.dsl, '');
      expect(result.issues, hasLength(1));
      expect(result.issues.single.code, IssueCode.themeReadOutOfContract);
    });

    test('a deprecated colorScheme role (background) is out of contract',
        () async {
      // The contract excludes the deprecated roles (background, onBackground,
      // surfaceVariant) so a paywall transpiled today cannot bake them in.
      final expr = await parseExpressionForTest(
        'Theme.of(context).colorScheme.background',
      );
      final result = translator.translate(expr);

      expect(result.dsl, '');
      expect(result.issues.single.code, IssueCode.themeReadOutOfContract);
    });
  });

  group('ExpressionTranslator — theme reads (extended shapes)', () {
    late ExpressionTranslator translator;

    setUp(() {
      translator = ExpressionTranslator(
        catalog: kEmptyCatalog,
        helpers: HelperRegistry(),
      );
    });

    test(
        'a prefixed import (material.Theme.of(c).colorScheme.primary) is '
        'recognised', () async {
      // A common Flutter idiom — `import 'package:flutter/material.dart' as
      // material;` then `material.Theme.of(context)`. The recognizer must
      // accept the PrefixedIdentifier-rooted shape so this transpiles.
      final expr = await parseExpressionForTest(
        'material.Theme.of(context).colorScheme.primary',
      );
      final result = translator.translate(expr);

      expect(result.issues, isEmpty);
      expect(result.dsl, 'data.theme.colorScheme.primary');
    });

    test('a parenthesized chain segment is recognised (L1)', () async {
      // `(Theme.of(c).colorScheme).primary` — the parens are syntactic
      // noise; the walker unwraps them so the chain still recognises.
      final expr = await parseExpressionForTest(
        '(Theme.of(context).colorScheme).primary',
      );
      final result = translator.translate(expr);

      expect(result.issues, isEmpty);
      expect(result.dsl, 'data.theme.colorScheme.primary');
    });

    test(
        'DefaultTextStyle.of(c).style.fontSize emits '
        'data.theme.defaultTextStyle.fontSize (M3)', () async {
      // The natural author syntax for an ambient text-style read is
      // DefaultTextStyle.of(c).style.<x>; the codegen normalizes the
      // `style.<x>` source shape to the `defaultTextStyle.<x>` contract path
      // the SDK publishes via populateThemeData.
      final expr = await parseExpressionForTest(
        'DefaultTextStyle.of(context).style.fontSize',
      );
      final result = translator.translate(expr);

      expect(result.issues, isEmpty);
      expect(result.dsl, 'data.theme.defaultTextStyle.fontSize');
    });

    test('DefaultTextStyle.of(c).style.color emits the contract path',
        () async {
      final expr = await parseExpressionForTest(
        'DefaultTextStyle.of(context).style.color',
      );
      final result = translator.translate(expr);

      expect(result.issues, isEmpty);
      expect(result.dsl, 'data.theme.defaultTextStyle.color');
    });

    test(
        'DefaultTextStyle.of(c).style.fontFamily is out of contract '
        '(only color/fontSize/fontWeight ship)', () async {
      final expr = await parseExpressionForTest(
        'DefaultTextStyle.of(context).style.fontFamily',
      );
      final result = translator.translate(expr);

      expect(result.dsl, '');
      expect(result.issues.single.code, IssueCode.themeReadOutOfContract);
    });

    test(
        'a DefaultTextStyle chain without the `.style.` infix falls through '
        '(e.g. DefaultTextStyle.of(c).maxLines)', () async {
      // The contract is anchored at `.style.<x>`; a top-level access on the
      // returned DefaultTextStyle object (e.g. `.maxLines`) is not part of
      // the published namespace.
      final expr = await parseExpressionForTest(
        'DefaultTextStyle.of(context).maxLines',
      );
      final result = translator.translate(expr);

      expect(result.dsl, '');
      // Falls through cleanly (no theme-data emission, no contract-specific
      // diagnostic).
      expect(
        result.issues.any((i) => i.message.contains('data.theme')),
        isFalse,
      );
    });
  });

  group('ExpressionTranslator — theme reads in widget property values', () {
    late ExpressionTranslator translator;

    setUp(() {
      translator = ExpressionTranslator(
        catalog: catalogWith([
          entry(
            name: 'Icon',
            flutterType: 'package:flutter/material.dart#Icon',
            properties: [
              prop('color', PropertyType.color),
              prop('size', PropertyType.length),
              prop('fontWeight', PropertyType.fontWeight),
            ],
          ),
          entry(
            name: 'Gap',
            properties: [
              prop('extent', PropertyType.length, positional: true),
            ],
          ),
        ]),
        helpers: HelperRegistry(),
      );
    });

    test('compatible Theme read in a color slot lowers to `data.theme`',
        () async {
      final expr = await parseExpressionForTest(
        'Icon(color: Theme.of(context).colorScheme.primary)',
      );
      final result = translator.translate(expr);

      expect(result.issues, isEmpty);
      expect(result.dsl, 'Icon(color: data.theme.colorScheme.primary)');
    });

    test('a length slot gets a property type mismatch for a color path',
        () async {
      final expr = await parseExpressionForTest(
        'Icon(size: Theme.of(context).colorScheme.primary)',
      );
      final result = translator.translate(expr);

      expect(result.issues.single.code, IssueCode.propertyValueTypeMismatch);
      expect(
        result.issues.single.message,
        contains("Theme value 'data.theme.colorScheme.primary'"),
      );
      expect(result.issues.single.message, contains('length'));
    });

    test('a positional length slot gets the same mismatch for a color path',
        () async {
      final expr = await parseExpressionForTest(
        'Gap(Theme.of(context).colorScheme.primary)',
      );
      final result = translator.translate(expr);

      expect(result.issues.single.code, IssueCode.propertyValueTypeMismatch);
      expect(
        result.issues.single.message,
        contains("Theme value 'data.theme.colorScheme.primary'"),
      );
    });

    test('a mismatched theme read inside a conditional branch is caught',
        () async {
      // Each branch of a ternary feeds the same slot, so a theme read in
      // either branch is validated against the slot's type.
      final expr = await parseExpressionForTest(
        'Icon(size: true ? Theme.of(context).colorScheme.primary : 4.0)',
      );
      final result = translator.translate(expr);

      expect(result.issues.single.code, IssueCode.propertyValueTypeMismatch);
      expect(
        result.issues.single.message,
        contains("Theme value 'data.theme.colorScheme.primary'"),
      );
    });

    test('compatible theme reads in both conditional branches pass clean',
        () async {
      final expr = await parseExpressionForTest(
        'Icon(color: true ? Theme.of(context).colorScheme.primary : '
        'Theme.of(context).colorScheme.secondary)',
      );
      final result = translator.translate(expr);

      expect(result.issues, isEmpty);
      expect(
        result.dsl,
        'Icon(color: switch true { true: data.theme.colorScheme.primary, '
        'false: data.theme.colorScheme.secondary })',
      );
    });

    test('a font-size-compatible path stays compatible with a length slot',
        () async {
      final expr = await parseExpressionForTest(
        'Icon(size: DefaultTextStyle.of(context).style.fontSize)',
      );
      final result = translator.translate(expr);

      expect(result.issues, isEmpty);
      expect(result.dsl, 'Icon(size: data.theme.defaultTextStyle.fontSize)');
    });

    test(
        'a font-weight-compatible path stays compatible with a fontWeight slot',
        () async {
      final expr = await parseExpressionForTest(
        'Icon(fontWeight: DefaultTextStyle.of(context).style.fontWeight)',
      );
      final result = translator.translate(expr);

      expect(result.issues, isEmpty);
      expect(
        result.dsl,
        'Icon(fontWeight: data.theme.defaultTextStyle.fontWeight)',
      );
    });

    test(
        'out-of-contract theme path at a value site emits only '
        'themeReadOutOfContract', () async {
      final expr = await parseExpressionForTest(
        'Icon(color: Theme.of(context).textTheme.bodyLarge)',
      );
      final result = translator.translate(expr);

      expect(result.issues.single.code, IssueCode.themeReadOutOfContract);
    });
  });

  group('ExpressionTranslator — theme value compatibility (resolved)', () {
    // A resolved fixture where the source is valid Dart (the parameter's own
    // Dart type accepts the theme read) but the catalog slot type diverges —
    // the case the contract validation exists for, on the production
    // (element-resolved) recognition path.
    const fixtureSource = '''
      import 'package:flutter/material.dart';

      class Chip2 extends StatelessWidget {
        const Chip2({super.key, this.tint});
        final Color? tint;
        @override
        Widget build(BuildContext context) => const SizedBox.shrink();
      }

      Object x(BuildContext context) =>
          Chip2(tint: Theme.of(context).colorScheme.primary);
    ''';

    test('a resolved theme read against a divergent slot type is caught',
        () async {
      final translator = ExpressionTranslator(
        catalog: catalogWith([
          entry(
            name: 'Chip2',
            properties: [prop('tint', PropertyType.length)],
          ),
        ]),
        helpers: HelperRegistry(),
      );
      final expr = await parseExpressionFromSourceForTest(
        fixtureSource,
        rootPackage: 'apps_examples',
      );
      final result = translator.translate(expr);

      expect(result.issues.single.code, IssueCode.propertyValueTypeMismatch);
      expect(
        result.issues.single.message,
        contains("Theme value 'data.theme.colorScheme.primary'"),
      );
    });

    test('a resolved theme read against a matching slot type passes clean',
        () async {
      final translator = ExpressionTranslator(
        catalog: catalogWith([
          entry(
            name: 'Chip2',
            properties: [prop('tint', PropertyType.color)],
          ),
        ]),
        helpers: HelperRegistry(),
      );
      final expr = await parseExpressionFromSourceForTest(
        fixtureSource,
        rootPackage: 'apps_examples',
      );
      final result = translator.translate(expr);

      expect(result.issues, isEmpty);
      expect(result.dsl, 'Chip2(tint: data.theme.colorScheme.primary)');
    });
  });

  group('theme contract path kinds', () {
    test('kThemeContractPathKinds keys exactly match kThemeContractPaths', () {
      expect(kThemeContractPathKinds.keys.toSet(), kThemeContractPaths);
    });

    test('every contract path kind is accepted by at least one property type',
        () {
      for (final pathKind in kThemeContractPathKinds.entries) {
        expect(
          PropertyType.values.any(
            (type) => propertyTypeAcceptsThemeKind(type, pathKind.value),
          ),
          isTrue,
          reason: 'No property type accepts ${pathKind.key} '
              '(${pathKind.value}); the kind table and '
              'propertyTypeAcceptsThemeKind have drifted apart.',
        );
      }
    });
  });

  group('blob-global theme invariant', () {
    // Build-time call-site completion hoists an optional property's
    // theme-derived default to the call site; that hoist is an identity
    // transform only because a `data.theme.*` path denotes the same value
    // anywhere in a blob (the namespace is published once, blob-global, with no
    // per-subtree / per-context dimension). This guards that invariant: a
    // future contract path scoped to a subtree/context would introduce a new
    // leading namespace and trip this, forcing a revisit of the completion
    // design before it ships.
    test(
        'every contract path is a flat global theme namespace '
        '(no subtree/context dimension)', () {
      const globalThemeRoots = {'colorScheme', 'iconTheme', 'defaultTextStyle'};
      for (final path in kThemeContractPaths) {
        final root = path.split('.').first;
        expect(
          globalThemeRoots.contains(root),
          isTrue,
          reason: "Contract path '$path' introduces a non-global theme root "
              "'$root'. If this is a subtree- or context-scoped theme read, "
              'the build-time call-site completion (which hoists theme '
              'defaults assuming a blob-global namespace) must be revisited '
              'before this ships.',
        );
      }
    });

    test(
        'a theme read lowers to the same blob-global reference regardless of '
        'slot position (the hoist-identity the completion relies on)',
        () async {
      final translator = ExpressionTranslator(
        catalog: kEmptyCatalog,
        helpers: HelperRegistry(),
      );
      // The same read, translated twice in unrelated positions, yields the
      // identical position-independent `data.theme.*` reference.
      final a = await parseExpressionForTest(
        'Theme.of(context).colorScheme.primary',
      );
      final b = await parseExpressionForTest(
        'Theme.of(ctx).colorScheme.primary',
      );
      expect(translator.translate(a).dsl, 'data.theme.colorScheme.primary');
      expect(translator.translate(b).dsl, 'data.theme.colorScheme.primary');
    });
  });
}

MethodInvocation _methodInvocationNamed(AstNode root, String name) {
  final visitor = _MethodInvocationFinder(name);
  root.accept(visitor);
  final result = visitor.result;
  if (result == null) {
    throw StateError('No MethodInvocation named $name found.');
  }
  return result;
}

class _MethodInvocationFinder extends RecursiveAstVisitor<void> {
  _MethodInvocationFinder(this.name);

  final String name;
  MethodInvocation? result;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    result ??= node.methodName.name == name ? node : null;
    super.visitMethodInvocation(node);
  }
}
