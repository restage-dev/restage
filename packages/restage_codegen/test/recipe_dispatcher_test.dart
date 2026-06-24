import 'package:analyzer/dart/ast/ast.dart';
import 'package:restage_codegen/src/emit_utils.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/recipe_dispatcher.dart';
import 'package:restage_codegen/src/translator_recipe.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  // A fake recursion hook: renders an expression to its source text. Enough
  // to assert the dispatcher's structural assembly without the full
  // ExpressionTranslator — integer/double literals render to their value.
  String fakeTranslate(Expression e, List<Issue> issues) => e.toSource();

  // The double-coercing analogue (mirrors the production helper's non-
  // conditional path): coerce the rendered source to a double literal.
  String fakeTranslateDouble(Expression e, List<Issue> issues) =>
      asDoubleLiteral(fakeTranslate(e, issues));

  RecipeDispatcher dispatcherWith(List<TranslatorRecipe> recipes) =>
      RecipeDispatcher(
        recipes: {for (final r in recipes) r.key: r},
        translate: fakeTranslate,
        translateDouble: fakeTranslateDouble,
      );

  // Parses a call expression and returns its argument list.
  Future<List<Expression>> argsOf(String callSource) async {
    final expr = await parseExpressionForTest(callSource);
    final argList = switch (expr) {
      MethodInvocation(:final argumentList) => argumentList,
      InstanceCreationExpression(:final argumentList) => argumentList,
      _ => throw ArgumentError('not a call: $callSource'),
    };
    return argList.arguments.toList();
  }

  group('lookup + fallback seam', () {
    test('returns null for an unregistered key — the fall-through signal',
        () async {
      final d = dispatcherWith([]);
      final out =
          d.tryTranslate('#Foo', await argsOf('Foo(1)'), <Issue>[], 'l');
      expect(out, isNull);
    });

    test('hasRecipe reflects registration', () {
      final d = dispatcherWith([
        const TranslatorRecipe(
          typeName: 'Offset',
          emit: EmitFragmentLiteral('{}'),
          failureDsl: '',
        ),
      ]);
      expect(d.hasRecipe('#Offset'), isTrue);
      expect(d.hasRecipe('#Color'), isFalse);
    });
  });

  group('emit — structural fragments', () {
    test('EmitFragmentMap assembles a map, recursing into args', () async {
      final d = dispatcherWith([
        const TranslatorRecipe(
          typeName: 'Pt',
          emit: EmitFragmentMap([
            EmitMapEntry('x', EmitFragmentArg(ArgRef.positional(0))),
            EmitMapEntry('y', EmitFragmentArg(ArgRef.positional(1))),
          ]),
          failureDsl: '{}',
        ),
      ]);
      final out =
          d.tryTranslate('#Pt', await argsOf('Pt(1, 2)'), <Issue>[], 'l');
      expect(out, '{x: 1, y: 2}');
    });

    test('EmitFragmentList broadcasts one ArgRef across slots', () async {
      final d = dispatcherWith([
        const TranslatorRecipe(
          typeName: 'Quad',
          emit: EmitFragmentList([
            EmitFragmentArg(ArgRef.positional(0)),
            EmitFragmentArg(ArgRef.positional(0)),
            EmitFragmentArg(ArgRef.positional(0)),
            EmitFragmentArg(ArgRef.positional(0)),
          ]),
          failureDsl: '[]',
        ),
      ]);
      final out =
          d.tryTranslate('#Quad', await argsOf('Quad(7)'), <Issue>[], 'l');
      expect(out, '[7, 7, 7, 7]');
    });

    test('EmitFragmentList reorders named args into positional slots',
        () async {
      final d = dispatcherWith([
        const TranslatorRecipe(
          typeName: 'Box',
          emit: EmitFragmentList([
            EmitFragmentArg(ArgRef.named('left')),
            EmitFragmentArg(ArgRef.named('top')),
          ]),
          failureDsl: '[]',
        ),
      ]);
      final out = d.tryTranslate(
        '#Box',
        await argsOf('Box(top: 1, left: 2)'),
        <Issue>[],
        'l',
      );
      expect(out, '[2, 1]');
    });

    test('EmitFragmentLiteral injects a constant; omit-unset drops absent keys',
        () async {
      final d = dispatcherWith([
        const TranslatorRecipe(
          typeName: 'Grad',
          emit: EmitFragmentMap([
            EmitMapEntry('type', EmitFragmentLiteral('"linear"')),
            EmitMapEntry(
              'colors',
              EmitFragmentArg(ArgRef.named('colors')),
              omitWhenArgUnset: true,
            ),
          ]),
          failureDsl: '{}',
        ),
      ]);
      final out =
          d.tryTranslate('#Grad', await argsOf('Grad()'), <Issue>[], 'l');
      expect(out, '{type: "linear"}');
    });

    test('EmitFragmentArg.ifUnset supplies a sentinel for an absent named arg',
        () async {
      final d = dispatcherWith([
        const TranslatorRecipe(
          typeName: 'Side',
          emit: EmitFragmentArg(
            ArgRef.named('w'),
            ifUnset: EmitFragmentLiteral('0.0'),
          ),
          failureDsl: '',
        ),
      ]);
      final out =
          d.tryTranslate('#Side', await argsOf('Side()'), <Issue>[], 'l');
      expect(out, '0.0');
    });

    test('EmitFragmentMemberTable looks a member up by name', () async {
      final d = dispatcherWith([
        const TranslatorRecipe(
          typeName: 'Align',
          emit: EmitFragmentMemberTable(ArgRef.positional(0), {
            'center': EmitFragmentLiteral('{x: 0.0, y: 0.0}'),
          }),
          failureDsl: '{}',
        ),
      ]);
      final out = d.tryTranslate(
        '#Align',
        await argsOf('Align(Alignment.center)'),
        <Issue>[],
        'l',
      );
      expect(out, '{x: 0.0, y: 0.0}');
    });
  });

  group('emit — kernels', () {
    test('EmitFragmentKernel composes value kernels (the fromRGBO shape)',
        () async {
      final d = dispatcherWith([
        const TranslatorRecipe(
          typeName: 'C',
          emit: EmitFragmentKernel(TranslatorKernel.formatColorHex, [
            EmitValueKernel(TranslatorKernel.packArgb, [
              EmitValueKernel(
                TranslatorKernel.quantizeUnitToByte,
                [EmitValueArg(ArgRef.positional(3))],
              ),
              EmitValueArg(ArgRef.positional(0)),
              EmitValueArg(ArgRef.positional(1)),
              EmitValueArg(ArgRef.positional(2)),
            ]),
          ]),
          failureDsl: '',
        ),
      ]);
      final out = d.tryTranslate(
        '#C',
        await argsOf('C(0x12, 0x34, 0x56, 0.5)'),
        <Issue>[],
        'l',
      );
      // opacity 0.5 -> alpha 128 (0x80); packed 0x80123456.
      expect(out, '0x80123456');
    });
  });

  group('validations', () {
    TranslatorRecipe recipeWithChecks(List<RecipeValidation> v) =>
        TranslatorRecipe(
          typeName: 'V',
          validations: v,
          emit: const EmitFragmentLiteral('OK'),
          failureDsl: 'FAIL',
        );

    test('ArityExact passes the exact count, fails otherwise', () async {
      final d = dispatcherWith([
        recipeWithChecks(const [
          RecipeValidation(
            check: ArityExact(2),
            issueCode: 'unrecognizedMethodCall',
            message: 'needs two',
          ),
        ]),
      ]);
      expect(
        d.tryTranslate('#V', await argsOf('V(1, 2)'), <Issue>[], 'l'),
        'OK',
      );
      final issues = <Issue>[];
      expect(d.tryTranslate('#V', await argsOf('V(1)'), issues, 'l'), 'FAIL');
      expect(issues.single.code, IssueCode.unrecognizedMethodCall);
      expect(issues.single.message, 'needs two');
    });

    test('PositionalIntsInRange substitutes {value} with the offender',
        () async {
      final d = dispatcherWith([
        recipeWithChecks(const [
          RecipeValidation(
            check: PositionalIntsInRange(0, 1, 0, 255),
            issueCode: 'unrecognizedMethodCall',
            message: 'value {value} out of range',
          ),
        ]),
      ]);
      final issues = <Issue>[];
      d.tryTranslate('#V', await argsOf('V(300)'), issues, 'l');
      expect(issues.single.message, 'value 300 out of range');
    });

    test('the first failing validation wins; later checks do not run',
        () async {
      final d = dispatcherWith([
        recipeWithChecks(const [
          RecipeValidation(
            check: ArityExact(1),
            issueCode: 'unrecognizedMethodCall',
            message: 'first',
          ),
          RecipeValidation(
            check: ArityExact(1),
            issueCode: 'integerLiteralOverflow',
            message: 'second',
          ),
        ]),
      ]);
      final issues = <Issue>[];
      d.tryTranslate('#V', await argsOf('V(1, 2)'), issues, 'l');
      expect(issues, hasLength(1));
      expect(issues.single.message, 'first');
    });

    test('PositionalsAreIntLiterals rejects a non-int-literal arg', () async {
      final d = dispatcherWith([
        recipeWithChecks(const [
          RecipeValidation(
            check: PositionalsAreIntLiterals(0, 1),
            issueCode: 'unrecognizedMethodCall',
            message: 'must be int literal',
          ),
        ]),
      ]);
      expect(
        d.tryTranslate('#V', await argsOf("V('x')"), <Issue>[], 'l'),
        'FAIL',
      );
      expect(d.tryTranslate('#V', await argsOf('V(5)'), <Issue>[], 'l'), 'OK');
    });

    test('PositionalNumLiteralInRange accepts an int or double in range',
        () async {
      final d = dispatcherWith([
        recipeWithChecks(const [
          RecipeValidation(
            check: PositionalNumLiteralInRange(0, 0, 1),
            issueCode: 'unrecognizedMethodCall',
            message: 'opacity out of range',
          ),
        ]),
      ]);
      expect(
        d.tryTranslate('#V', await argsOf('V(0.5)'), <Issue>[], 'l'),
        'OK',
      );
      expect(d.tryTranslate('#V', await argsOf('V(1)'), <Issue>[], 'l'), 'OK');
      expect(
        d.tryTranslate('#V', await argsOf('V(2.0)'), <Issue>[], 'l'),
        'FAIL',
      );
    });
  });
}
