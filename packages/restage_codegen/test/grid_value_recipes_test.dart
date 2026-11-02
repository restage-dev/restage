import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:restage_codegen/src/emit_utils.dart';
import 'package:restage_codegen/src/grid_value_recipes.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/recipe_dispatcher.dart';
import 'package:restage_codegen/src/translator_recipe.dart';
import 'package:test/test.dart';

import 'helpers.dart' show parseExpressionFromSourceForTest;

void main() {
  late RecipeDispatcher dispatcher;
  String translate(Expression expression, List<Issue> issues) {
    if (expression is IntegerLiteral ||
        expression is DoubleLiteral ||
        expression is NullLiteral) {
      return expression.toSource();
    }
    if (expression is PrefixedIdentifier) {
      return '"${expression.identifier.name}"';
    }
    if (expression is InstanceCreationExpression) {
      final type = expression.constructorName.type;
      final name = type.name.lexeme;
      final prefix = type.importPrefix?.name.lexeme;
      final shifted = prefix == 'ScrollCacheExtent';
      return dispatcher.tryTranslate(
        recipeKey(
          library: null,
          typeName: shifted ? prefix! : name,
          variant: shifted ? name : expression.constructorName.name?.name,
        ),
        expression.argumentList.arguments.toList(),
        issues,
        'test.dart',
      )!;
    }
    throw StateError('Unexpected test expression ${expression.toSource()}');
  }

  setUp(() {
    dispatcher = RecipeDispatcher(
      recipes: {for (final recipe in kGridValueRecipes) recipe.key: recipe},
      translate: translate,
      translateDouble: (expression, issues) =>
          asDoubleLiteral(translate(expression, issues)),
    );
  });

  String emit(String source, [List<Issue>? issues]) {
    final unit = parseString(content: 'final value = $source;').unit;
    final expression = (unit.declarations.single as TopLevelVariableDeclaration)
        .variables
        .variables
        .single
        .initializer!;
    return translate(expression, issues ?? []);
  }

  test('grid dimensions coerce numeric values and retain nullable defaults', () {
    expect(
      emit(
        'const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3)',
      ),
      '{_s: "SliverGridDelegateWithFixedCrossAxisCount", crossAxisCount: 3}',
    );
    expect(
      emit(
        'const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 140, mainAxisSpacing: 5, crossAxisSpacing: 9, childAspectRatio: 2, mainAxisExtent: null)',
      ),
      '{_s: "SliverGridDelegateWithMaxCrossAxisExtent", maxCrossAxisExtent: 140.0, mainAxisSpacing: 5.0, crossAxisSpacing: 9.0, childAspectRatio: 2.0, mainAxisExtent: null}',
    );
    expect(
      emit(
        'const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisExtent: 53)',
      ),
      contains('mainAxisExtent: 53.0'),
    );
  });

  test('all standard physics have closed recipes preserving nested parent', () {
    for (final name in [
      'ScrollPhysics',
      'RangeMaintainingScrollPhysics',
      'BouncingScrollPhysics',
      'ClampingScrollPhysics',
      'AlwaysScrollableScrollPhysics',
      'NeverScrollableScrollPhysics',
      'PageScrollPhysics',
      'FixedExtentScrollPhysics',
    ]) {
      expect(emit('const $name()'), '{_s: "$name"}');
    }
    expect(
      emit(
        'const BouncingScrollPhysics(decelerationRate: ScrollDecelerationRate.fast, parent: const RangeMaintainingScrollPhysics(parent: const AlwaysScrollableScrollPhysics()))',
      ),
      '{_s: "BouncingScrollPhysics", parent: {_s: "RangeMaintainingScrollPhysics", parent: {_s: "AlwaysScrollableScrollPhysics"}}, decelerationRate: "fast"}',
    );
    expect(
      emit('const ScrollPhysics(parent: null)'),
      '{_s: "ScrollPhysics", parent: null}',
    );
  });

  test('cache extent units and positional double coercion', () {
    for (final variant in ['pixels', 'viewport']) {
      expect(
        emit('const ScrollCacheExtent.$variant(2)'),
        '{_s: "$variant", value: 2.0}',
      );
    }
  });

  test(
    'unknown constructors are absent and cache arity refuses explicitly',
    () {
      expect(dispatcher.hasRecipe('#CustomScrollPhysics'), isFalse);
      expect(dispatcher.hasRecipe('#ScrollCacheExtent'), isFalse);
      final issues = <Issue>[];
      expect(emit('const ScrollCacheExtent.pixels()', issues), '{}');
      expect(issues, hasLength(1));
      expect(issues.single.code, IssueCode.unrecognizedMethodCall);
    },
  );

  test(
    'resolved native identities survive aliases and reexports; lookalikes refuse',
    () async {
      final expression = await parseExpressionFromSourceForTest(
        '''
import 'package:flutter/widgets.dart' as native;
import 'package:flutter/rendering.dart' as rendering;
import 'native_exports.dart' as exported;
import 'package:flutter/src/widgets/other_physics.dart' as impostor;
class ScrollPhysics { const ScrollPhysics(); }
Object x() => [
  const native.ScrollPhysics(),
  const native.RangeMaintainingScrollPhysics(),
  const native.BouncingScrollPhysics(),
  const native.ClampingScrollPhysics(),
  const native.AlwaysScrollableScrollPhysics(),
  const native.NeverScrollableScrollPhysics(),
  const native.PageScrollPhysics(),
  const native.FixedExtentScrollPhysics(),
  const native.SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2),
  const native.SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 100),
  const rendering.ScrollCacheExtent.pixels(200),
  const rendering.ScrollCacheExtent.viewport(1),
  const exported.ScrollPhysics(),
  const ScrollPhysics(),
  const impostor.ScrollPhysics(),
  const native.SizedBox(),
];
''',
        rootPackage: 'apps_examples',
        otherFiles: {
          'lib/native_exports.dart':
              "export 'package:flutter/widgets.dart' show ScrollPhysics;",
          'flutter|lib/src/widgets/other_physics.dart':
              'class ScrollPhysics { const ScrollPhysics(); }',
        },
      );
      final calls = (expression as ListLiteral).elements
          .cast<InstanceCreationExpression>();
      final constructors = calls
          .map((call) => call.constructorName.element)
          .toList();
      expect(constructors, everyElement(isNotNull));
      expect(
        constructors.take(13).map(isGridValueConstructor),
        everyElement(isTrue),
      );
      expect(
        constructors.skip(13).map(isGridValueConstructor),
        everyElement(isFalse),
      );
      expect(isGridValueConstructor(null), isFalse);
    },
  );
}
