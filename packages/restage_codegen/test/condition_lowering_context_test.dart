// The same lowerings over host-supplied render context, and through a
// `build()` prelude local bound to a composed condition.
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/host_data_shape.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/rfw_emitter.dart';
import 'package:restage_shared/rfw_formats.dart' as fmt;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const String _stubs = '''
  class Widget { const Widget(); }
  class BuildContext {}
  abstract class StatelessWidget extends Widget { const StatelessWidget(); }
  class Text extends Widget {
    const Text({this.text});
    final String? text;
  }
  class Column extends Widget {
    const Column({required this.children});
    final List<Widget> children;
  }
''';

RootContextParam _rootParam(
  ResolvedMethodExpressionForTest probe,
  String name,
) {
  final parameter = probe.classes['P']!.unnamedConstructor!.formalParameters
      .firstWhere((element) => element.name == name);
  final hostData = deriveHostDataShape(parameter.type, root: name);
  return RootContextParam(
    name: name,
    type: parameter.type,
    typeCode: parameter.type.getDisplayString(),
    kind: RootContextParamKind.named,
    hostDataShape: hostData.shape,
    hostDataProblem: hostData.problem,
    field: parameter is FieldFormalParameterElement ? parameter.field : null,
    isRequired: parameter.isRequired,
    defaultValueCode: parameter.defaultValueCode,
    hasNullDefault: false,
  );
}

void main() {
  final translator = ExpressionTranslator.forTesting(
    catalog: catalogWith([
      entry(name: 'Text', properties: [prop('text', PropertyType.string)]),
      entry(name: 'SizedBox', properties: []),
      entry(
        name: 'Column',
        childrenSlot: ChildrenSlot.list,
        properties: [prop('children', PropertyType.widgetList)],
      ),
    ]),
    helpers: HelperRegistry(),
    frameworkLibraryPredicate: syntheticFrameworkLibrary,
  );

  test('a context string equality and a context collection-`if` lower',
      () async {
    final probe = await parseMethodExpressionFromSourceForTest(
      '''
      $_stubs
      class P extends StatelessWidget {
        const P({required this.plan, required this.isPro});
        final String plan;
        final bool isPro;
        Widget build(BuildContext context) => Column(
          children: [
            if (isPro) Text(text: plan == 'annual' ? 'A' : 'B'),
          ],
        );
      }
    ''',
      className: 'P',
    );
    final result = translator.translate(
      probe.expression,
      rootParams: [_rootParam(probe, 'plan'), _rootParam(probe, 'isPro')],
    );
    expect(result.issues, isEmpty, reason: result.issues.join('\n'));
    expect(
      result.dsl,
      'Column(children: [...for presence in switch data.context.isPro '
      '{ true: [0], false: [] }: Text(text: switch data.context.plan '
      '{ "annual": "A", default: "B" })])',
    );
    fmt.parseLibraryFile(emitPaywallLibrary(result.dsl));
  });

  test('a prelude local bound to a composed condition lowers', () async {
    final probe = await parseMethodExpressionFromSourceForTest(
      '''
      $_stubs
      class P extends StatelessWidget {
        const P({required this.trialUsed, required this.isEligible});
        final bool trialUsed;
        final bool isEligible;
        Widget build(BuildContext context) {
          final canBuy = !trialUsed && isEligible;
          return Text(text: canBuy ? 'A' : 'B');
        }
      }
    ''',
      className: 'P',
    );
    final body = probe.expression
        .thisOrAncestorOfType<MethodDeclaration>()!
        .body as BlockFunctionBody;
    final declaration = body.block.statements
        .whereType<VariableDeclarationStatement>()
        .single
        .variables
        .variables
        .single;
    final result = translator.translate(
      probe.expression,
      rootParams: [
        _rootParam(probe, 'trialUsed'),
        _rootParam(probe, 'isEligible'),
      ],
      rootInlined: InlinedDefinitions(
        localBindings: {
          declaration.declaredFragment!.element: declaration.initializer!,
        },
      ),
    );
    expect(result.issues, isEmpty, reason: result.issues.join('\n'));
    expect(
      result.dsl,
      'Text(text: switch data.context.trialUsed { true: "B", '
      'false: switch data.context.isEligible { true: "A", false: "B" } })',
    );
    fmt.parseLibraryFile(emitPaywallLibrary(result.dsl));
  });

  test('a conditional element inside a run-time loop keeps both bindings',
      () async {
    final probe = await parseMethodExpressionFromSourceForTest(
      '''
      $_stubs
      class P extends StatelessWidget {
        const P({required this.labels, required this.isPro});
        final List<String> labels;
        final bool isPro;
        Widget build(BuildContext context) => Column(
          children: [
            for (final label in labels)
              Column(children: [if (isPro) Text(text: label)]),
          ],
        );
      }
    ''',
      className: 'P',
    );
    final result = translator.translate(
      probe.expression,
      rootParams: [_rootParam(probe, 'labels'), _rootParam(probe, 'isPro')],
    );
    expect(result.issues, isEmpty, reason: result.issues.join('\n'));
    expect(
      result.dsl,
      'Column(children: [...for label in data.context.labels: '
      'Column(children: [...for presence in switch data.context.isPro '
      '{ true: [0], false: [] }: Text(text: label)])])',
    );

    // The conditional loop encloses the template, so the authored loop
    // reference must still resolve to the outer loop, not to it.
    final library = fmt.parseLibraryFile(emitPaywallLibrary(result.dsl));
    final root = library.widgets.single.root as fmt.ConstructorCall;
    final outer =
        (root.arguments['children']! as List<Object?>).single! as fmt.Loop;
    final wrapper = outer.output as fmt.ConstructorCall;
    final inner =
        (wrapper.arguments['children']! as List<Object?>).single! as fmt.Loop;
    final text = inner.output as fmt.ConstructorCall;
    expect((text.arguments['text']! as fmt.LoopReference).loop, 1);
  });

  test('a conditional element does not shadow a loop named `presence`',
      () async {
    final probe = await parseMethodExpressionFromSourceForTest(
      '''
      $_stubs
      class P extends StatelessWidget {
        const P({required this.presence, required this.isPro});
        final List<String> presence;
        final bool isPro;
        Widget build(BuildContext context) => Column(
          children: [
            for (final presence in presence)
              Column(children: [if (isPro) Text(text: presence)]),
          ],
        );
      }
    ''',
      className: 'P',
    );
    final result = translator.translate(
      probe.expression,
      rootParams: [_rootParam(probe, 'presence'), _rootParam(probe, 'isPro')],
    );
    expect(result.issues, isEmpty, reason: result.issues.join('\n'));
    expect(result.dsl, contains('...for presence1 in switch'));
    fmt.parseLibraryFile(emitPaywallLibrary(result.dsl));
  });

  Future<TranslationResult> lowerLoop(String body) async {
    final probe = await parseMethodExpressionFromSourceForTest(
      '''
      $_stubs
      class P extends StatelessWidget {
        const P({required this.labels, required this.isPro});
        final List<String> labels;
        final bool isPro;
        Widget build(BuildContext context) => Column(children: [
          Text(text: 'before'),
          for (final label in labels) $body,
          Text(text: 'after'),
        ]);
      }
    ''',
      className: 'P',
    );
    return translator.translate(
      probe.expression,
      rootParams: [_rootParam(probe, 'labels'), _rootParam(probe, 'isPro')],
    );
  }

  test('a conditional loop body contributes a widget list per item', () async {
    final result = await lowerLoop("if (label == 'annual') Text(text: label)");
    expect(result.issues, isEmpty, reason: result.issues.join('\n'));
    expect(
      result.dsl,
      'Column(children: [Text(text: "before"), '
      '...for label in data.context.labels: '
      '[...for presence in switch label { "annual": [0], default: [] }: '
      'Text(text: label)], Text(text: "after")])',
    );
    final library = fmt.parseLibraryFile(emitPaywallLibrary(result.dsl));
    final root = library.widgets.single.root as fmt.ConstructorCall;
    final loop = (root.arguments['children']! as List<Object?>)[1]! as fmt.Loop;
    final selector = (loop.output as List<Object?>).single! as fmt.Loop;
    final label = selector.output as fmt.ConstructorCall;
    expect((label.arguments['text']! as fmt.LoopReference).loop, 1);
  });

  test('a total conditional loop body keeps a single output per item',
      () async {
    final result = await lowerLoop(
      "if (label == 'annual') Text(text: label) else Text(text: 'monthly')",
    );
    expect(result.issues, isEmpty, reason: result.issues.join('\n'));
    final library = fmt.parseLibraryFile(emitPaywallLibrary(result.dsl));
    final root = library.widgets.single.root as fmt.ConstructorCall;
    final loop = (root.arguments['children']! as List<Object?>)[1]! as fmt.Loop;
    expect(loop.output, isA<fmt.Switch>());
    expect(result.dsl, isNot(contains('presence')));
  });

  for (final condition in [
    "isPro && label == 'annual'",
    "isPro || label == 'annual'",
    "!(isPro && label == 'annual')",
  ]) {
    test('a composed loop condition emits each branch once: $condition',
        () async {
      final result = await lowerLoop(
        "if ($condition) Text(text: 'yes') else Text(text: 'no')",
      );
      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      expect(
        RegExp(r'Text\(text: "yes"\)').allMatches(result.dsl),
        hasLength(1),
      );
      expect(
        RegExp(r'Text\(text: "no"\)').allMatches(result.dsl),
        hasLength(1),
      );
      fmt.parseLibraryFile(emitPaywallLibrary(result.dsl));
    });
  }

  test('a composed nested total condition emits each branch once', () async {
    final result = await lowerLoop(
      "if (isPro) if (isPro || label == 'annual') Text(text: 'yes') "
      "else Text(text: 'no') else Text(text: 'other')",
    );
    expect(result.issues, isEmpty, reason: result.issues.join('\n'));
    for (final label in ['yes', 'no', 'other']) {
      expect(
        RegExp('Text\\(text: "$label"\\)').allMatches(result.dsl),
        hasLength(1),
      );
    }
    fmt.parseLibraryFile(emitPaywallLibrary(result.dsl));
  });

  test('nested conditions and spreads preserve their branch order', () async {
    final result = await lowerLoop(
      "if (isPro) if (label == 'annual') ...[ "
      "Text(text: label), Text(text: 'extra')] else Text(text: 'monthly')",
    );
    expect(result.issues, isEmpty, reason: result.issues.join('\n'));
    final library = fmt.parseLibraryFile(emitPaywallLibrary(result.dsl));
    final root = library.widgets.single.root as fmt.ConstructorCall;
    final loop = (root.arguments['children']! as List<Object?>)[1]! as fmt.Loop;
    final outputs = loop.output as List<Object?>;
    expect(outputs, hasLength(3));
    expect(
      outputs.cast<fmt.Loop>().map(
            (item) => (item.output as fmt.ConstructorCall).arguments['text'],
          ),
      [isA<fmt.LoopReference>(), 'extra', 'monthly'],
    );
  });

  test('constant nested conditions select only the reachable branch', () async {
    final result = await lowerLoop(
      "if (isPro) if (false) Text(text: 'unreachable') else Text(text: label)",
    );
    expect(result.issues, isEmpty, reason: result.issues.join('\n'));
    expect(result.dsl, isNot(contains('unreachable')));
    expect(result.dsl, contains('Text(text: label)'));
    fmt.parseLibraryFile(emitPaywallLibrary(result.dsl));
  });

  test('a constant false loop body preserves an empty widget group', () async {
    final result = await lowerLoop("if (false) Text(text: 'unreachable')");
    expect(result.issues, isEmpty, reason: result.issues.join('\n'));
    expect(result.dsl, contains('...for label in data.context.labels: []'));
    expect(result.dsl, isNot(contains('unreachable')));
    fmt.parseLibraryFile(emitPaywallLibrary(result.dsl));
  });

  for (final body in [
    "if (label == 'annual') label",
    "if (isPro && label == 'annual') label else 'fallback'",
  ]) {
    test('a grouped data list refuses instead of nesting its values: $body',
        () async {
      final probe = await parseMethodExpressionFromSourceForTest(
        '''
      $_stubs
      class P extends StatelessWidget {
        const P({required this.labels, required this.isPro});
        final List<String> labels;
        final bool isPro;
        List<String> build(BuildContext context) => [
          for (final label in labels) $body,
        ];
      }
    ''',
        className: 'P',
      );
      final result = translator.translate(
        probe.expression,
        rootParams: [_rootParam(probe, 'labels'), _rootParam(probe, 'isPro')],
      );
      expect(result.issues.map((issue) => issue.code), [
        IssueCode.unsupportedCollectionFlow,
      ]);
      expect(result.dsl, '[]');
    });
  }
}
