import 'package:analyzer/dart/ast/ast.dart';
import 'package:restage_codegen/src/collection_unroll.dart';
import 'package:restage_codegen/src/emit_utils.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/recipe_dispatcher.dart';
import 'package:restage_codegen/src/structured_value_emitter.dart';
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

  RecipeDispatcher dispatcherWith(
    List<TranslatorRecipe> recipes, {
    DoubleListSourceDisposition doubleListDisposition =
        DoubleListSourceDisposition.ordinary,
    TranslateCallback? translate,
    TranslateCallback? translateDouble,
    String Function(AstNode)? locationOf,
  }) =>
      RecipeDispatcher(
        recipes: {for (final r in recipes) r.key: r},
        translate: translate ?? fakeTranslate,
        translateDouble: translateDouble ?? fakeTranslateDouble,
        translateDoubleElement: (expression, bindings, issues) =>
            (translateDouble ?? fakeTranslateDouble)(expression, issues),
        resolveDoubleListSource: (source) => DoubleListSourceResolution(
          source: source,
          disposition: doubleListDisposition,
        ),
        locationOf: locationOf,
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
    const doubleListOwnerRecipes = [
      TranslatorRecipe(
        typeName: 'StopsList',
        emit: EmitFragmentList([
          EmitFragmentLiteral('"prefix"'),
          EmitFragmentArg(
            ArgRef.named('values'),
            asDoubleList: true,
          ),
        ]),
        failureDsl: '',
      ),
      TranslatorRecipe(
        typeName: 'StopsMap',
        emit: EmitFragmentMap([
          EmitMapEntry(
            'stops',
            EmitFragmentArg(
              ArgRef.named('values'),
              asDoubleList: true,
            ),
          ),
        ]),
        failureDsl: '',
      ),
    ];

    Future<
        ({
          IssueCode? directIssueCode,
          int directIssueCount,
          String list,
          IssueCode? listIssueCode,
          int listIssueCount,
          String map,
          IssueCode? mapIssueCode,
          int mapIssueCount,
          bool refused,
          String value,
        })> emitDoubleListFixture(
      String source, {
      required TranslateCallback translate,
      required TranslateCallback translateDouble,
    }) async {
      final expression = await parseExpressionForTest(source);
      final directIssues = <Issue>[];
      final emission = emitDoubleList(
        expression,
        translate,
        translateDouble,
        (source) => DoubleListSourceResolution(
          source: source,
          disposition: DoubleListSourceDisposition.ordinary,
        ),
        directIssues,
        'source.dart:1',
      );
      final dispatcher = dispatcherWith(
        doubleListOwnerRecipes,
        translate: translate,
        translateDouble: translateDouble,
      );
      final listIssues = <Issue>[];
      final list = dispatcher.tryTranslate(
        '#StopsList',
        await argsOf('StopsList(values: $source)'),
        listIssues,
        'source.dart:1',
      )!;
      final mapIssues = <Issue>[];
      final map = dispatcher.tryTranslate(
        '#StopsMap',
        await argsOf('StopsMap(values: $source)'),
        mapIssues,
        'source.dart:1',
      )!;
      return (
        directIssueCode:
            directIssues.length == 1 ? directIssues.single.code : null,
        directIssueCount: directIssues.length,
        list: list,
        listIssueCode: listIssues.length == 1 ? listIssues.single.code : null,
        listIssueCount: listIssues.length,
        map: map,
        mapIssueCode: mapIssues.length == 1 ? mapIssues.single.code : null,
        mapIssueCount: mapIssues.length,
        refused: emission.refused,
        value: emission.value,
      );
    }

    const completeRefusal = (
      directIssueCode: null,
      directIssueCount: 0,
      list: '',
      listIssueCode: null,
      listIssueCount: 0,
      map: '',
      mapIssueCode: null,
      mapIssueCount: 0,
      refused: true,
      value: '',
    );

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

    test('a refused double list suppresses its enclosing list', () async {
      final d = dispatcherWith(
        [
          const TranslatorRecipe(
            typeName: 'Stops',
            emit: EmitFragmentList([
              EmitFragmentLiteral('"prefix"'),
              EmitFragmentArg(
                ArgRef.named('values'),
                asDoubleList: true,
              ),
            ]),
            failureDsl: '',
          ),
        ],
        doubleListDisposition: DoubleListSourceDisposition.constant,
      );
      final issues = <Issue>[];
      final out = d.tryTranslate(
        '#Stops',
        await argsOf('Stops(values: const [0, 1])'),
        issues,
        'source.dart:1',
      );
      expect(out, isEmpty);
      expect(out, isNot(contains('["prefix", ]')));
      expect(issues, hasLength(1));
    });

    test('a refused double list suppresses its enclosing map', () async {
      final d = dispatcherWith(
        [
          const TranslatorRecipe(
            typeName: 'Stops',
            emit: EmitFragmentMap([
              EmitMapEntry('type', EmitFragmentLiteral('"linear"')),
              EmitMapEntry(
                'stops',
                EmitFragmentArg(
                  ArgRef.named('values'),
                  asDoubleList: true,
                ),
              ),
            ]),
            failureDsl: '',
          ),
        ],
        doubleListDisposition: DoubleListSourceDisposition.constant,
      );
      final issues = <Issue>[];
      final out = d.tryTranslate(
        '#Stops',
        await argsOf('Stops(values: const [0, 1])'),
        issues,
        'source.dart:1',
      );
      expect(out, isEmpty);
      expect(out, isNot(contains('stops: }')));
      expect(issues, hasLength(1));
    });

    test('a silent empty source refuses the list and map owners', () async {
      String silentSource(Expression source, List<Issue> issues) =>
          source.toSource() == 'unavailable'
              ? ''
              : fakeTranslate(source, issues);

      final result = await emitDoubleListFixture(
        'unavailable',
        translate: silentSource,
        translateDouble: fakeTranslateDouble,
      );

      expect(result, completeRefusal);
      expect(result.map, isNot(equals('{stops: }')));
    });

    test('a silent empty element refuses the list and map owners', () async {
      String silentElement(Expression source, List<Issue> issues) =>
          source.toSource() == '1' ? '' : fakeTranslateDouble(source, issues);

      final result = await emitDoubleListFixture(
        '[0, 1]',
        translate: fakeTranslate,
        translateDouble: silentElement,
      );

      expect(result, completeRefusal);
      expect(result.map, isNot(equals('{stops: [0.0, ]}')));
    });

    test('a deferred generic source refuses complete owners', () async {
      String deferredSource(Expression source, List<Issue> issues) {
        issues.add(
          const Issue(
            code: IssueCode.customWidgetInliningDeferred,
            message: 'The source cannot emit here.',
            location: 'source.dart:1',
          ),
        );
        return 'data.stops';
      }

      final result = await emitDoubleListFixture(
        'available',
        translate: deferredSource,
        translateDouble: fakeTranslateDouble,
      );

      expect(
        result,
        (
          directIssueCode: IssueCode.customWidgetInliningDeferred,
          directIssueCount: 1,
          list: '',
          listIssueCode: IssueCode.customWidgetInliningDeferred,
          listIssueCount: 1,
          map: '',
          mapIssueCode: IssueCode.customWidgetInliningDeferred,
          mapIssueCount: 1,
          refused: true,
          value: '',
        ),
      );
      expect(result.value, isNot(equals('data.stops')));
      expect(result.list, isNot(equals('["prefix", data.stops]')));
      expect(result.map, isNot(equals('{stops: data.stops}')));
    });

    test('a deferred list element refuses complete owners', () async {
      String deferredElement(Expression source, List<Issue> issues) {
        if (source.toSource() == '1') {
          issues.add(
            const Issue(
              code: IssueCode.customWidgetInliningDeferred,
              message: 'The element cannot emit here.',
              location: 'source.dart:1',
            ),
          );
        }
        return fakeTranslateDouble(source, issues);
      }

      final result = await emitDoubleListFixture(
        '[0, 1]',
        translate: fakeTranslate,
        translateDouble: deferredElement,
      );

      expect(
        result,
        (
          directIssueCode: IssueCode.customWidgetInliningDeferred,
          directIssueCount: 1,
          list: '',
          listIssueCode: IssueCode.customWidgetInliningDeferred,
          listIssueCount: 1,
          map: '',
          mapIssueCode: IssueCode.customWidgetInliningDeferred,
          mapIssueCount: 1,
          refused: true,
          value: '',
        ),
      );
      expect(result.value, isNot(equals('[0.0, 1.0]')));
      expect(result.list, isNot(equals('["prefix", [0.0, 1.0]]')));
      expect(result.map, isNot(equals('{stops: [0.0, 1.0]}')));
    });

    test('a diagnosed generic double-list source suppresses its map', () async {
      final d = dispatcherWith(
        [
          const TranslatorRecipe(
            typeName: 'Stops',
            emit: EmitFragmentMap([
              EmitMapEntry('type', EmitFragmentLiteral('"linear"')),
              EmitMapEntry(
                'stops',
                EmitFragmentArg(
                  ArgRef.named('values'),
                  asDoubleList: true,
                ),
              ),
            ]),
            failureDsl: '',
          ),
        ],
        translate: (source, issues) {
          issues.add(
            const Issue(
              code: IssueCode.unrecognizedMethodCall,
              message: 'The source cannot be translated.',
              location: 'source.dart:1',
            ),
          );
          return '';
        },
      );
      final issues = <Issue>[];
      final out = d.tryTranslate(
        '#Stops',
        await argsOf('Stops(values: unavailable)'),
        issues,
        'source.dart:1',
      );
      expect(out, isEmpty);
      expect(out, isNot(contains('stops: }')));
      expect(issues.map((issue) => issue.code), [
        IssueCode.unrecognizedMethodCall,
      ]);
    });

    test('a diagnosed double-list element suppresses its map', () async {
      final d = dispatcherWith(
        [
          const TranslatorRecipe(
            typeName: 'Stops',
            emit: EmitFragmentMap([
              EmitMapEntry('type', EmitFragmentLiteral('"linear"')),
              EmitMapEntry(
                'stops',
                EmitFragmentArg(
                  ArgRef.named('values'),
                  asDoubleList: true,
                ),
              ),
            ]),
            failureDsl: '',
          ),
        ],
        translateDouble: (source, issues) {
          if (source.toSource() == '1') {
            issues.add(
              const Issue(
                code: IssueCode.unrecognizedMethodCall,
                message: 'The element cannot be translated.',
                location: 'source.dart:1',
              ),
            );
            return '';
          }
          return fakeTranslateDouble(source, issues);
        },
      );
      final issues = <Issue>[];
      final out = d.tryTranslate(
        '#Stops',
        await argsOf('Stops(values: [0, 1])'),
        issues,
        'source.dart:1',
      );
      expect(out, isEmpty);
      expect(out, isNot(contains('stops: [0.0, ]')));
      expect(issues.map((issue) => issue.code), [
        IssueCode.unrecognizedMethodCall,
      ]);
    });

    test('a build notice preserves complete bytes and owners', () async {
      String noticedSource(Expression source, List<Issue> issues) {
        issues.add(
          const Issue(
            code: IssueCode.idiomAutoSubstituted,
            message: 'The source uses its canonical representation.',
            location: 'source.dart:1',
          ),
        );
        return 'data.stops';
      }

      final result = await emitDoubleListFixture(
        'available',
        translate: noticedSource,
        translateDouble: fakeTranslateDouble,
      );

      expect(
        result,
        (
          directIssueCode: IssueCode.idiomAutoSubstituted,
          directIssueCount: 1,
          list: '["prefix", data.stops]',
          listIssueCode: IssueCode.idiomAutoSubstituted,
          listIssueCount: 1,
          map: '{stops: data.stops}',
          mapIssueCode: IssueCode.idiomAutoSubstituted,
          mapIssueCount: 1,
          refused: false,
          value: 'data.stops',
        ),
      );
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

    test('typed recipe lists refuse collection elements', () async {
      final d = dispatcherWith(
        [
          const TranslatorRecipe(
            typeName: 'Grad',
            emit: EmitFragmentMap([
              EmitMapEntry('colors', EmitFragmentArg(ArgRef.named('colors'))),
            ]),
            failureDsl: '{}',
          ),
        ],
        locationOf: (_) => 'lib/recipe.dart:4:16',
      );
      final issues = <Issue>[];
      final out = d.tryTranslate(
        '#Grad',
        await argsOf(
          'Grad(colors: ([for (final color in const [1, 2]) color]))',
        ),
        issues,
        'lib/recipe.dart:4:3',
      );

      expect(out, isEmpty);
      expect(issues, hasLength(1));
      expect(issues.single.code, IssueCode.unsupportedCollectionFlow);
      expect(
        issues.single.message,
        'Collection elements in a typed list are unsupported; '
        'write the values out.',
      );
      expect(issues.single.location, 'lib/recipe.dart:4:16');
    });

    test('typed recipe lists inspect both conditional branches', () async {
      final d = dispatcherWith([
        const TranslatorRecipe(
          typeName: 'Grad',
          emit: EmitFragmentArg(ArgRef.named('colors')),
          failureDsl: '{}',
        ),
      ]);
      final issues = <Issue>[];
      final out = d.tryTranslate(
        '#Grad',
        await argsOf(
          'Grad(colors: true '
          '? [1] '
          ': [for (final color in const [2]) color])',
        ),
        issues,
        'lib/recipe_conditional.dart:2:3',
      );

      expect(out, isEmpty);
      expect(issues, hasLength(1));
      expect(issues.single.code, IssueCode.unsupportedCollectionFlow);
      expect(issues.single.location, 'lib/recipe_conditional.dart:2:3');
    });

    test('numeric recipe lists refuse wrapped collection elements', () async {
      final d = dispatcherWith([
        const TranslatorRecipe(
          typeName: 'Grad',
          emit: EmitFragmentArg(
            ArgRef.named('stops'),
            asDoubleList: true,
          ),
          failureDsl: '{}',
        ),
      ]);
      final issues = <Issue>[];
      final out = d.tryTranslate(
        '#Grad',
        await argsOf(
          'Grad(stops: ([for (final stop in const [0, 1]) stop]))',
        ),
        issues,
        'lib/recipe_numeric.dart:5:3',
      );

      expect(out, isEmpty);
      expect(issues, hasLength(1));
      expect(issues.single.code, IssueCode.unsupportedCollectionFlow);
      expect(
        issues.single.message,
        'Collection elements in a numeric list are unsupported; '
        'write the values out.',
      );
    });

    test('typed-list inspection follows an injected binding alias', () async {
      final alias = await parseExpressionForTest(
        '[for (final color in const [1, 2]) color]',
      );
      final reference = await parseExpressionForTest('colors');
      final issues = <Issue>[];
      final out = emitTypedList(
        reference,
        fakeTranslate,
        issues,
        'lib/recipe_alias.dart:3:5',
        resolveExpression: (expression) =>
            expression is SimpleIdentifier && expression.name == 'colors'
                ? alias
                : expression,
      );

      expect(out.refused, isTrue);
      expect(issues, hasLength(1));
      expect(issues.single.code, IssueCode.unsupportedCollectionFlow);
    });

    test('typed-list source resolution terminates through an alias cycle',
        () async {
      final first = await parseExpressionForTest('first');
      final second = await parseExpressionForTest('second');
      final semantics = CollectionSemanticProbe(
        sourceFor: (expression) => switch (expression.toSource()) {
          'first' => second,
          'second' => first,
          _ => null,
        },
      );

      final resolution = semantics.resolve(
        first,
        const {},
        CollectionUnrollBudget(workCeiling: 2),
      );

      expect(resolution.workLimitExceeded, isFalse);
      expect(resolution.expression, same(first));
    });

    test('typed-list source resolution has bounded traversal', () async {
      final first = await parseExpressionForTest('first');
      final second = await parseExpressionForTest('second');
      final third = await parseExpressionForTest('third');
      final semantics = CollectionSemanticProbe(
        sourceFor: (expression) => switch (expression.toSource()) {
          'first' => second,
          'second' => third,
          _ => null,
        },
      );

      final resolution = semantics.resolve(
        first,
        const {},
        CollectionUnrollBudget(workCeiling: 1),
      );

      expect(resolution.workLimitExceeded, isTrue);
      expect(resolution.expression, same(first));
    });

    test('typed-list inspection reports bounded plain-list exhaustion',
        () async {
      final first = await parseExpressionForTest('first');
      final second = await parseExpressionForTest('second');
      final plain = await parseExpressionForTest('[1]');
      final semantics = CollectionSemanticProbe(
        sourceFor: (expression) => switch (expression.toSource()) {
          'first' => second,
          'second' => plain,
          _ => null,
        },
      );
      final issues = <Issue>[];
      final out = emitTypedList(
        first,
        fakeTranslate,
        issues,
        'lib/typed_limit.dart:7:9',
        semanticProbe: semantics,
        semanticBudget: CollectionUnrollBudget(workCeiling: 1),
      );

      expect(out.refused, isTrue);
      expect(issues, hasLength(1));
      expect(issues.single.code, IssueCode.unsupportedCollectionFlow);
      expect(
        issues.single.message,
        'Static inspection of this typed list exceeded the supported limit. '
        'Simplify the list expression.',
      );
      expect(issues.single.message, isNot(contains('Collection elements')));
      expect(issues.single.location, 'lib/typed_limit.dart:7:9');
    });

    test('numeric-list inspection reports bounded plain-list exhaustion',
        () async {
      final first = await parseExpressionForTest('first');
      final second = await parseExpressionForTest('second');
      final plain = await parseExpressionForTest('[1]');
      final semantics = CollectionSemanticProbe(
        sourceFor: (expression) => switch (expression.toSource()) {
          'first' => second,
          'second' => plain,
          _ => null,
        },
      );
      final issues = <Issue>[];
      final out = emitDoubleList(
        first,
        fakeTranslate,
        fakeTranslateDouble,
        (source) => DoubleListSourceResolution(
          source: source,
          disposition: DoubleListSourceDisposition.ordinary,
        ),
        issues,
        'lib/numeric_limit.dart:8:11',
        semanticProbe: semantics,
        semanticBudget: CollectionUnrollBudget(workCeiling: 1),
      );

      expect(out.refused, isTrue);
      expect(issues, hasLength(1));
      expect(issues.single.code, IssueCode.unsupportedCollectionFlow);
      expect(
        issues.single.message,
        'Static inspection of this numeric list exceeded the supported limit. '
        'Simplify the list expression.',
      );
      expect(issues.single.message, isNot(contains('Collection elements')));
      expect(issues.single.location, 'lib/numeric_limit.dart:8:11');
    });

    test('low-limit typed inspection still identifies collection flow',
        () async {
      final collection = await parseExpressionForTest(
        '[for (final value in const [1]) value]',
      );
      final issues = <Issue>[];
      final out = emitTypedList(
        collection,
        fakeTranslate,
        issues,
        'lib/typed_flow.dart:4:7',
        semanticBudget: CollectionUnrollBudget(workCeiling: 1),
        locationOf: (_) => 'lib/typed_flow.dart:4:8',
      );

      expect(out.refused, isTrue);
      expect(issues, hasLength(1));
      expect(issues.single.code, IssueCode.unsupportedCollectionFlow);
      expect(
        issues.single.message,
        'Collection elements in a typed list are unsupported; '
        'write the values out.',
      );
      expect(issues.single.location, 'lib/typed_flow.dart:4:8');
    });

    test('typed-list elements consume inspection work before classification',
        () async {
      final collection = await parseExpressionForTest(
        '[for (final value in const [1]) value]',
      );
      final issues = <Issue>[];
      final out = emitTypedList(
        collection,
        fakeTranslate,
        issues,
        'lib/typed_element_limit.dart:5:7',
        semanticBudget: CollectionUnrollBudget(workCeiling: 0),
      );

      expect(out.refused, isTrue);
      expect(issues, hasLength(1));
      expect(
        issues.single.message,
        'Static inspection of this typed list exceeded the supported limit. '
        'Simplify the list expression.',
      );
      expect(issues.single.location, 'lib/typed_element_limit.dart:5:7');
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

  group('strict double-list child failures', () {
    Future<NodeList<Expression>> gradientArgs(String source) async {
      final expression = await parseExpressionForTest(source);
      return switch (expression) {
        MethodInvocation(:final argumentList) => argumentList.arguments,
        InstanceCreationExpression(:final argumentList) =>
          argumentList.arguments,
        _ => throw ArgumentError('not a gradient: $source'),
      };
    }

    StructuredValueEmitter structuredEmitter({
      required TranslateCallback translate,
      required TranslateCallback translateDouble,
    }) =>
        StructuredValueEmitter(
          translate: translate,
          translateDoubleScalar: translateDouble,
          translateDoubleElement: (expression, bindings, issues) =>
              translateDouble(expression, issues),
          resolveDoubleListSource: (source) => DoubleListSourceResolution(
            source: source,
            disposition: DoubleListSourceDisposition.ordinary,
          ),
          stripParens: (source) => source,
          stringLiteral: (value) => '"$value"',
          frameworkOrUnresolved: (_) => true,
          resolveBoundIdentifier: (source) => source,
          collectionSemanticProbe: () => CollectionSemanticProbe(),
          isResolvedNonFrameworkCtor: (_) => false,
          deferFrameworkConstLookalike: (expression, owner, member, issues) =>
              '',
          deferFrameworkCtorLookalike: (expression, owner, issues) => '',
          conditionalSwitch: (expression, issues, translateBranch) => '',
          validateThemeValueForSlot: (expression, type, issues) {},
          locationOf: (_) => 'source.dart:1',
        );

    test('a diagnosed generic source suppresses a structured gradient',
        () async {
      final emitter = structuredEmitter(
        translate: (source, issues) {
          if (source.toSource() == 'unavailable') {
            issues.add(
              const Issue(
                code: IssueCode.unrecognizedMethodCall,
                message: 'The source cannot be translated.',
                location: 'source.dart:1',
              ),
            );
            return 'wrong';
          }
          return source.toSource();
        },
        translateDouble: fakeTranslateDouble,
      );
      final issues = <Issue>[];
      final out = emitter.linearGradient(
        await gradientArgs(
          'LinearGradient(colors: [], stops: unavailable)',
        ),
        issues,
        'source.dart:1',
      );
      expect(out, isEmpty);
      expect(out, isNot(contains('stops: }')));
      expect(issues.map((issue) => issue.code), [
        IssueCode.unrecognizedMethodCall,
      ]);
    });

    test('a diagnosed list element suppresses a structured gradient', () async {
      final emitter = structuredEmitter(
        translate: fakeTranslate,
        translateDouble: (source, issues) {
          if (source.toSource() == '1') {
            issues.add(
              const Issue(
                code: IssueCode.unrecognizedMethodCall,
                message: 'The element cannot be translated.',
                location: 'source.dart:1',
              ),
            );
            return '';
          }
          return fakeTranslateDouble(source, issues);
        },
      );
      final issues = <Issue>[];
      final out = emitter.linearGradient(
        await gradientArgs(
          'LinearGradient(colors: [], stops: [0, 1])',
        ),
        issues,
        'source.dart:1',
      );
      expect(out, isEmpty);
      expect(out, isNot(contains('stops: [0.0, ]')));
      expect(issues.map((issue) => issue.code), [
        IssueCode.unrecognizedMethodCall,
      ]);
    });
  });
}
