// The same lowerings over host-supplied render context, and through a
// `build()` prelude local bound to a composed condition.
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/host_data_shape.dart';
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
      rootLocalBindings: {
        declaration.declaredFragment!.element: declaration.initializer!,
      },
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
}
