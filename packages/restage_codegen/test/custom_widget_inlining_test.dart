import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/host_data_shape.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/widget_classification.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// The classKey `parseExpressionFromSourceForTest` produces for a class named
/// `AcmeCard` — the synthetic probe file is mounted at
/// `package:restage_codegen/_expr_probe.dart`.
const String _cardKey = 'package:restage_codegen/_expr_probe.dart#AcmeCard';

RootContextParam _rootParamFrom(
  ResolvedMethodExpressionForTest probe, {
  String className = 'P',
  String name = 'label',
}) {
  final parameter = probe
      .classes[className]!.unnamedConstructor!.formalParameters
      .firstWhere((element) => element.name == name);
  final hostData = deriveHostDataShape(parameter.type, root: name);
  return RootContextParam(
    name: parameter.name!,
    type: parameter.type,
    typeCode: parameter.type.getDisplayString(),
    kind: parameter.isOptionalPositional
        ? RootContextParamKind.optionalPositional
        : parameter.isNamed
            ? RootContextParamKind.named
            : RootContextParamKind.requiredPositional,
    hostDataShape: hostData.shape,
    hostDataProblem: hostData.problem,
    field: parameter is FieldFormalParameterElement ? parameter.field : null,
    isRequired: parameter.isRequired,
    defaultValueCode: parameter.defaultValueCode,
    hasNullDefault: false,
  );
}

/// The callback parameter [name] of [className], carrying its resolved type.
CustomWidgetParam _callbackParamFrom(
  ResolvedMethodExpressionForTest probe, {
  String className = 'AcmeCard',
  String name = 'onTap',
}) {
  final parameter = probe
      .classes[className]!.unnamedConstructor!.formalParameters
      .firstWhere((element) => element.name == name);
  return CustomWidgetParam(
    name: name,
    isNumeric: false,
    defaultValue: null,
    type: parameter.type,
  );
}

/// Source declaring an `AcmeCard` whose `onTap` has the given callback type,
/// constructed from a host class with a closure firing the event helper.
String _callbackCardSource(String callbackType) => '''
  class AcmeCard {
    const AcmeCard({required this.onTap});
    final $callbackType onTap;
  }
  void cardEvent(String name) {}
  class P {
    const P();
    Object build() => AcmeCard(onTap: () => cardEvent("tapped"));
  }
''';

final List<HelperDefinition> _eventHelpers = [
  HelperDefinition(
    name: 'cardEvent',
    libraryOrigin: 'package:restage_codegen',
    returnCategory: HelperReturnCategory.voidCallback,
    translate: (args) {
      final name = args.positional.first;
      return 'event ${name.startsWith('"') ? name : '"$name"'} {}';
    },
  ),
];

void main() {
  group('ExpressionTranslator — custom-widget inlining', () {
    test('translate() surfaces an empty widgetDefinitions map by default',
        () async {
      final translator = ExpressionTranslator(
        catalog: kEmptyCatalog,
        helpers: HelperRegistry(),
      );
      final expr = await parseExpressionForTest('"hello"');
      final result = translator.translate(expr);

      expect(result.dsl, '"hello"');
      expect(result.widgetDefinitions, isEmpty);
    });

    test('inlines an inlinable-now ComposableWidget as a widget definition',
        () async {
      final body =
          await parseExpressionForTest('Container(child: Text("Pro"))');
      final translator = ExpressionTranslator(
        catalog: catalogWith([
          entry(
            name: 'Container',
            properties: [prop('child', PropertyType.widget)],
          ),
          entry(
            name: 'Text',
            properties: [prop('text', PropertyType.string, positional: true)],
          ),
        ]),
        helpers: HelperRegistry(),
        customWidgetClassifications: {
          _cardKey: ComposableWidget(
            _cardKey,
            requiredMechanisms: const {},
            composedCustomWidgets: const [],
          ),
        },
        customWidgetBlueprints: {
          _cardKey: CustomWidgetBlueprint(
            classKey: _cardKey,
            rfwName: 'AcmeCard',
            buildExpression: body,
            params: const [],
          ),
        },
      );
      final expr = await parseExpressionFromSourceForTest('''
        class AcmeCard { const AcmeCard(); }
        Object x() => AcmeCard();
      ''');
      final result = translator.translate(expr);

      expect(result.issues, isEmpty);
      expect(result.dsl, 'AcmeCard()');
      expect(
        result.widgetDefinitions['AcmeCard'],
        'Container(child: Text(text: "Pro"))',
      );
    });

    test('attemptInlineEmit clears enclosing root parameters', () async {
      final probe = await parseMethodExpressionFromSourceForTest(
        '''
        class Text { const Text(this.text); final String text; }
        class AcmeCard {
          const AcmeCard({required this.label});
          final String label;
          Object build() => Text(label);
        }
      ''',
        className: 'AcmeCard',
      );
      final rootLabel = _rootParamFrom(probe, className: 'AcmeCard');
      final classification = ComposableWidget(
        _cardKey,
        requiredMechanisms: const {},
        composedCustomWidgets: const [],
      );
      final blueprint = CustomWidgetBlueprint(
        classKey: _cardKey,
        rfwName: 'AcmeCard',
        buildExpression: probe.expression,
        params: const [],
      );
      final translator = ExpressionTranslator(
        catalog: catalogWith([
          entry(
            name: 'Text',
            properties: [prop('text', PropertyType.string, positional: true)],
          ),
        ]),
        helpers: HelperRegistry(),
        customWidgetClassifications: {_cardKey: classification},
        customWidgetBlueprints: {_cardKey: blueprint},
      );

      final result = translator.attemptInlineEmit(
        classification,
        blueprint,
        rootParams: [rootLabel],
      );

      expect(result.issues, isNotEmpty);
      expect(
        result.widgetDefinitions['AcmeCard'],
        isNot(contains('data.context')),
      );
    });

    test('lowers constructor parameters to args. references in the definition',
        () async {
      final body = await parseExpressionForTest('Text(label)');
      final translator = ExpressionTranslator(
        catalog: catalogWith([
          entry(
            name: 'Text',
            properties: [prop('text', PropertyType.string, positional: true)],
          ),
        ]),
        helpers: HelperRegistry(),
        customWidgetClassifications: {
          _cardKey: ComposableWidget(
            _cardKey,
            requiredMechanisms: const {},
            composedCustomWidgets: const [],
          ),
        },
        customWidgetBlueprints: {
          _cardKey: CustomWidgetBlueprint(
            classKey: _cardKey,
            rfwName: 'AcmeCard',
            buildExpression: body,
            params: const [
              CustomWidgetParam(
                name: 'label',
                isNumeric: false,
                defaultValue: null,
              ),
            ],
          ),
        },
      );
      final expr = await parseExpressionFromSourceForTest('''
        class AcmeCard {
          const AcmeCard({this.label});
          final String? label;
        }
        Object x() => AcmeCard(label: "Pro");
      ''');
      final result = translator.translate(expr);

      expect(result.issues, isEmpty);
      // The call site passes the argument; the definition body reads it as
      // an `args.` reference.
      expect(result.dsl, 'AcmeCard(label: "Pro")');
      expect(result.widgetDefinitions['AcmeCard'], 'Text(text: args.label)');
    });

    test('does not leak root params into custom widget definitions', () async {
      final body = await parseExpressionForTest('Text(label)');
      final probe = await parseMethodExpressionFromSourceForTest(
        '''
        class AcmeCard {
          const AcmeCard({this.label});
          final String? label;
        }
        class P {
          const P({required this.label});
          final String label;
          Object build() => AcmeCard(label: label);
        }
      ''',
        className: 'P',
      );
      final rootLabel = _rootParamFrom(probe);
      final translator = ExpressionTranslator(
        catalog: catalogWith([
          entry(
            name: 'Text',
            properties: [prop('text', PropertyType.string, positional: true)],
          ),
        ]),
        helpers: HelperRegistry(),
        customWidgetClassifications: {
          _cardKey: ComposableWidget(
            _cardKey,
            requiredMechanisms: const {},
            composedCustomWidgets: const [],
          ),
        },
        customWidgetBlueprints: {
          _cardKey: CustomWidgetBlueprint(
            classKey: _cardKey,
            rfwName: 'AcmeCard',
            buildExpression: body,
            params: const [
              CustomWidgetParam(
                name: 'label',
                isNumeric: false,
                defaultValue: null,
              ),
            ],
          ),
        },
      );
      final result =
          translator.translate(probe.expression, rootParams: [rootLabel]);

      expect(result.issues, isEmpty);
      expect(result.dsl, 'AcmeCard(label: data.context.label)');
      expect(result.widgetDefinitions['AcmeCard'], 'Text(text: args.label)');
      expect(
        result.widgetDefinitions['AcmeCard'],
        isNot(contains('data.context')),
      );
    });

    test('a definition body cannot read a root param it does not declare',
        () async {
      final bodyProbe = await parseMethodExpressionFromSourceForTest(
        '''
        class Text { const Text(this.text); final String text; }
        class AcmeCard {
          const AcmeCard({required this.label});
          final String label;
          Object build() => Text(label);
        }
      ''',
        className: 'AcmeCard',
      );
      final body = bodyProbe.expression;
      final rootLabel = _rootParamFrom(bodyProbe, className: 'AcmeCard');
      final translator = ExpressionTranslator(
        catalog: catalogWith([
          entry(
            name: 'Text',
            properties: [prop('text', PropertyType.string, positional: true)],
          ),
        ]),
        helpers: HelperRegistry(),
        customWidgetClassifications: {
          _cardKey: ComposableWidget(
            _cardKey,
            requiredMechanisms: const {},
            composedCustomWidgets: const [],
          ),
        },
        customWidgetBlueprints: {
          _cardKey: CustomWidgetBlueprint(
            classKey: _cardKey,
            rfwName: 'AcmeCard',
            buildExpression: body,
            params: const [],
          ),
        },
      );
      final expr = await parseExpressionFromSourceForTest('''
        class AcmeCard {
          const AcmeCard();
        }

        String label = '';
        Object x() => AcmeCard();
      ''');
      final result = translator.translate(expr, rootParams: [rootLabel]);

      expect(
        result.widgetDefinitions['AcmeCard'],
        isNot(contains('data.context')),
      );
      expect(result.issues, isNotEmpty);
    });

    test(
        'coerces ternary integer branches bound to a numeric parameter at '
        'the call site', () async {
      // Each ternary branch becomes the numeric parameter's value, so a bare
      // integer branch must be normalised to a double literal — the
      // definition body's strict double decode would silently null it.
      final body = await parseExpressionForTest('Text(size)');
      final translator = ExpressionTranslator(
        catalog: catalogWith([
          entry(
            name: 'Text',
            properties: [prop('size', PropertyType.real, positional: true)],
          ),
        ]),
        helpers: HelperRegistry(),
        customWidgetClassifications: {
          _cardKey: ComposableWidget(
            _cardKey,
            requiredMechanisms: const {},
            composedCustomWidgets: const [],
          ),
        },
        customWidgetBlueprints: {
          _cardKey: CustomWidgetBlueprint(
            classKey: _cardKey,
            rfwName: 'AcmeCard',
            buildExpression: body,
            params: const [
              CustomWidgetParam(
                name: 'size',
                isNumeric: true,
                defaultValue: null,
              ),
            ],
          ),
        },
      );
      final expr = await parseExpressionFromSourceForTest('''
        class AcmeCard {
          const AcmeCard({this.size});
          final double? size;
        }
        Object x() => AcmeCard(size: true ? 24 : 16);
      ''');
      final result = translator.translate(expr);

      expect(result.issues, isEmpty);
      expect(
        result.dsl,
        'AcmeCard(size: switch true { true: 24.0, false: 16.0 })',
      );
    });

    test('rejects an integer root reference used as a double-decoded arg',
        () async {
      final body = await parseExpressionForTest('Text(size)');
      final blueprint = CustomWidgetBlueprint(
        classKey: _cardKey,
        rfwName: 'AcmeCard',
        buildExpression: body,
        params: const [
          CustomWidgetParam(
            name: 'size',
            isNumeric: true,
            defaultValue: null,
          ),
        ],
      );
      final translator = ExpressionTranslator(
        catalog: catalogWith([
          entry(
            name: 'Text',
            properties: [prop('size', PropertyType.real, positional: true)],
          ),
        ]),
        helpers: HelperRegistry(),
        customWidgetClassifications: {
          _cardKey: ComposableWidget(
            _cardKey,
            requiredMechanisms: const {},
            composedCustomWidgets: const [],
          ),
        },
        customWidgetBlueprints: {_cardKey: blueprint},
      );
      final probe = await parseMethodExpressionFromSourceForTest(
        '''
        class AcmeCard {
          const AcmeCard({required this.size});
          final num size;
        }
        class P {
          const P({required this.count, required this.size});
          final int count;
          final double size;
          Object build() => <AcmeCard>[
            AcmeCard(size: count),
            AcmeCard(size: size),
          ];
        }
      ''',
        className: 'P',
      );
      final params = [
        _rootParamFrom(
          probe,
          name: 'count',
        ),
        _rootParamFrom(
          probe,
          name: 'size',
        ),
      ];
      final expressions =
          (probe.expression as ListLiteral).elements.cast<Expression>();

      final integerResult =
          translator.translate(expressions[0], rootParams: params);
      final doubleResult =
          translator.translate(expressions[1], rootParams: params);

      expect(
        integerResult.issues.map((issue) => issue.code),
        contains(IssueCode.propertyValueTypeMismatch),
      );
      expect(integerResult.dsl, isEmpty);
      expect(doubleResult.issues, isEmpty);
      expect(doubleResult.dsl, contains('data.context.size'));
    });

    test('keeps static list traversal for inlined arguments', () async {
      final probe = await parseMethodExpressionFromSourceForTest(
        '''
        class Labels {
          const Labels({required this.values});
          final List<String> values;
        }
        class P {
          Object render() => Labels(
            values: [for (final value in const ['a', 'b']) value],
          );
        }
      ''',
        className: 'P',
        methodName: 'render',
      );
      final parameter =
          probe.classes['Labels']!.unnamedConstructor!.formalParameters.single;
      final labelsKey = _cardKey.replaceFirst('AcmeCard', 'Labels');
      final translator = ExpressionTranslator(
        catalog: kEmptyCatalog,
        helpers: HelperRegistry(),
        customWidgetClassifications: {
          labelsKey: ComposableWidget(
            labelsKey,
            requiredMechanisms: const {},
            composedCustomWidgets: const [],
          ),
        },
        customWidgetBlueprints: {
          labelsKey: CustomWidgetBlueprint(
            classKey: labelsKey,
            rfwName: 'Labels',
            buildExpression: await parseExpressionForTest('"labels"'),
            params: [
              CustomWidgetParam(
                name: 'values',
                isNumeric: false,
                defaultValue: null,
                type: parameter.type,
              ),
            ],
          ),
        },
      );

      final result = translator.translate(probe.expression);

      expect(result.dsl, 'Labels(values: ["a", "b"])');
      expect(result.issues, isEmpty);
    });

    test('validates root values against inlined parameter types', () async {
      final body = await parseExpressionForTest('Text(label)');
      final probe = await parseMethodExpressionFromSourceForTest(
        '''
        class AcmeCard {
          const AcmeCard({required this.label});
          final String label;
        }
        class P {
          const P({required this.title, required this.count});
          final String title;
          final int count;
          Object build() => <AcmeCard>[
            AcmeCard(label: title),
            AcmeCard(label: count),
          ];
        }
      ''',
        className: 'P',
      );
      final widgetParameter = probe
          .classes['AcmeCard']!.unnamedConstructor!.formalParameters.single;
      final blueprint = CustomWidgetBlueprint(
        classKey: _cardKey,
        rfwName: 'AcmeCard',
        buildExpression: body,
        params: [
          CustomWidgetParam(
            name: 'label',
            isNumeric: false,
            defaultValue: null,
            type: widgetParameter.type,
          ),
        ],
      );
      final translator = ExpressionTranslator(
        catalog: catalogWith([
          entry(
            name: 'Text',
            properties: [prop('text', PropertyType.string, positional: true)],
          ),
        ]),
        helpers: HelperRegistry(),
        customWidgetClassifications: {
          _cardKey: ComposableWidget(
            _cardKey,
            requiredMechanisms: const {},
            composedCustomWidgets: const [],
          ),
        },
        customWidgetBlueprints: {_cardKey: blueprint},
      );
      final params = [
        _rootParamFrom(probe, name: 'title'),
        _rootParamFrom(probe, name: 'count'),
      ];
      final expressions =
          (probe.expression as ListLiteral).elements.cast<Expression>();

      final valid = translator.translate(expressions[0], rootParams: params);
      expect(valid.issues, isEmpty);
      expect(valid.dsl, contains('data.context.title'));

      final invalid = translator.translate(expressions[1], rootParams: params);
      expect(invalid.dsl, isNot(contains('data.context.count')));
      expect(
        invalid.issues.map((issue) => issue.code),
        contains(IssueCode.propertyValueTypeMismatch),
      );
    });

    test('recurses into composed custom widgets, emitting each definition',
        () async {
      const pillKey = 'package:restage_codegen/_expr_probe.dart#AcmePill';
      // AcmeCard's body composes AcmePill — resolve it from a source that
      // declares both, so the nested AcmePill() reference carries a resolved
      // class element the translator can key the blueprint off.
      final cardBody = await parseExpressionFromSourceForTest('''
        class AcmePill { const AcmePill(); }
        class Container {
          const Container({this.child});
          final Object? child;
        }
        Object x() => Container(child: AcmePill());
      ''');
      final pillBody = await parseExpressionForTest('Text("pill")');
      final translator = ExpressionTranslator(
        catalog: catalogWith([
          entry(
            name: 'Container',
            properties: [prop('child', PropertyType.widget)],
          ),
          entry(
            name: 'Text',
            properties: [prop('text', PropertyType.string, positional: true)],
          ),
        ]),
        helpers: HelperRegistry(),
        customWidgetClassifications: {
          _cardKey: ComposableWidget(
            _cardKey,
            requiredMechanisms: const {},
            composedCustomWidgets: const [pillKey],
          ),
          pillKey: ComposableWidget(
            pillKey,
            requiredMechanisms: const {},
            composedCustomWidgets: const [],
          ),
        },
        customWidgetBlueprints: {
          _cardKey: CustomWidgetBlueprint(
            classKey: _cardKey,
            rfwName: 'AcmeCard',
            buildExpression: cardBody,
            params: const [],
          ),
          pillKey: CustomWidgetBlueprint(
            classKey: pillKey,
            rfwName: 'AcmePill',
            buildExpression: pillBody,
            params: const [],
          ),
        },
      );
      final expr = await parseExpressionFromSourceForTest('''
        class AcmeCard { const AcmeCard(); }
        Object x() => AcmeCard();
      ''');
      final result = translator.translate(expr);

      expect(result.issues, isEmpty);
      expect(result.dsl, 'AcmeCard()');
      expect(
        result.widgetDefinitions['AcmeCard'],
        'Container(child: AcmePill())',
      );
      expect(result.widgetDefinitions['AcmePill'], 'Text(text: "pill")');
    });

    test('diagnoses two custom widgets emitting under the same RFW name',
        () async {
      const keyA = 'package:restage_codegen/_expr_probe.dart#CardA';
      const keyB = 'package:restage_codegen/_expr_probe.dart#CardB';
      final bodyA = await parseExpressionForTest('Text("a")');
      final bodyB = await parseExpressionForTest('Text("b")');
      final translator = ExpressionTranslator(
        catalog: catalogWith([
          entry(
            name: 'Column',
            childrenSlot: ChildrenSlot.list,
            properties: [prop('children', PropertyType.widgetList)],
          ),
          entry(
            name: 'Text',
            properties: [prop('text', PropertyType.string, positional: true)],
          ),
        ]),
        helpers: HelperRegistry(),
        customWidgetClassifications: {
          keyA: ComposableWidget(
            keyA,
            requiredMechanisms: const {},
            composedCustomWidgets: const [],
          ),
          keyB: ComposableWidget(
            keyB,
            requiredMechanisms: const {},
            composedCustomWidgets: const [],
          ),
        },
        customWidgetBlueprints: {
          // Both blueprints claim the same RFW name — the collision.
          keyA: CustomWidgetBlueprint(
            classKey: keyA,
            rfwName: 'Shared',
            buildExpression: bodyA,
            params: const [],
          ),
          keyB: CustomWidgetBlueprint(
            classKey: keyB,
            rfwName: 'Shared',
            buildExpression: bodyB,
            params: const [],
          ),
        },
      );
      final expr = await parseExpressionFromSourceForTest('''
        class CardA { const CardA(); }
        class CardB { const CardB(); }
        class Column { const Column({this.children}); final Object? children; }
        Object x() => Column(children: [CardA(), CardB()]);
      ''');
      final result = translator.translate(expr);

      expect(
        result.issues.map((i) => i.code),
        contains(IssueCode.customWidgetNameCollision),
      );
    });

    test('diagnoses a custom widget whose name shadows a catalog widget',
        () async {
      final body = await parseExpressionForTest('Container()');
      final translator = ExpressionTranslator(
        catalog: catalogWith([
          entry(
            name: 'Text',
            properties: [prop('text', PropertyType.string, positional: true)],
          ),
          entry(name: 'Container', properties: const []),
        ]),
        helpers: HelperRegistry(),
        customWidgetClassifications: {
          _cardKey: ComposableWidget(
            _cardKey,
            requiredMechanisms: const {},
            composedCustomWidgets: const [],
          ),
        },
        customWidgetBlueprints: {
          // The custom widget would emit as `Text` — a catalog widget name.
          _cardKey: CustomWidgetBlueprint(
            classKey: _cardKey,
            rfwName: 'Text',
            buildExpression: body,
            params: const [],
          ),
        },
      );
      final expr = await parseExpressionFromSourceForTest('''
        class AcmeCard { const AcmeCard(); }
        Object x() => AcmeCard();
      ''');
      final result = translator.translate(expr);

      expect(
        result.issues.map((i) => i.code),
        contains(IssueCode.customWidgetNameCollision),
      );
    });

    test('diagnoses a custom widget whose name shadows the paywall root',
        () async {
      final body = await parseExpressionForTest('Text("hi")');
      final translator = ExpressionTranslator(
        catalog: catalogWith([
          entry(
            name: 'Text',
            properties: [prop('text', PropertyType.string, positional: true)],
          ),
        ]),
        helpers: HelperRegistry(),
        customWidgetClassifications: {
          _cardKey: ComposableWidget(
            _cardKey,
            requiredMechanisms: const {},
            composedCustomWidgets: const [],
          ),
        },
        customWidgetBlueprints: {
          // The custom widget would emit under the reserved root name.
          _cardKey: CustomWidgetBlueprint(
            classKey: _cardKey,
            rfwName: 'Paywall',
            buildExpression: body,
            params: const [],
          ),
        },
      );
      final expr = await parseExpressionFromSourceForTest('''
        class AcmeCard { const AcmeCard(); }
        Object x() => AcmeCard();
      ''');
      final result = translator.translate(expr);

      expect(
        result.issues.map((i) => i.code),
        contains(IssueCode.customWidgetNameCollision),
      );
    });

    test('folds const references and const arithmetic in the body', () async {
      final body = await parseExpressionFromSourceForTest('''
        const double kGap = 16;
        class Container {
          const Container({this.width, this.height});
          final double? width;
          final double? height;
        }
        Object x() => Container(width: kGap, height: kGap * 2);
      ''');
      final translator = ExpressionTranslator(
        catalog: catalogWith([
          entry(
            name: 'Container',
            properties: [
              prop('width', PropertyType.real),
              prop('height', PropertyType.real),
            ],
          ),
        ]),
        helpers: HelperRegistry(),
        customWidgetClassifications: {
          _cardKey: ComposableWidget(
            _cardKey,
            requiredMechanisms: const {InliningMechanism.constantFolding},
            composedCustomWidgets: const [],
          ),
        },
        customWidgetBlueprints: {
          _cardKey: CustomWidgetBlueprint(
            classKey: _cardKey,
            rfwName: 'AcmeCard',
            buildExpression: body,
            params: const [],
          ),
        },
      );
      final expr = await parseExpressionFromSourceForTest('''
        class AcmeCard { const AcmeCard(); }
        Object x() => AcmeCard();
      ''');
      final result = translator.translate(expr);

      expect(result.issues, isEmpty);
      expect(
        result.widgetDefinitions['AcmeCard'],
        'Container(width: 16.0, height: 32.0)',
      );
    });

    test(
        'inlines a themeAsData-only widget, lowering the theme read to a '
        'data.theme.* reference in the definition body', () async {
      // The themeAsData mechanism exists, so a widget whose
      // required mechanisms are a subset of {constantFolding, themeAsData}
      // is now inlinable — the classifier's tag is no longer a deferred
      // signal. The translator emits the body with the theme read lowered
      // through the new PropertyAccess case + contract validation.
      //
      // Uses the apps_examples root package so the body source resolves
      // real `package:flutter/material.dart` `Theme.of` — the strict
      // recognizer requires a Flutter library URI. The body uses a local
      // `Box` widget for the catalog match (decoupled from Flutter's
      // internal `Container` library path).
      const flutterCardKey = 'package:apps_examples/_expr_probe.dart#AcmeCard';
      final body = await parseExpressionFromSourceForTest(
        '''
$kFlutterClassifierStubs

class Box {
  const Box({this.color});
  final Color? color;
}
BuildContext get context => throw '';
Object x() => Box(color: Theme.of(context).colorScheme.primary);
        ''',
        rootPackage: 'apps_examples',
      );
      final translator = ExpressionTranslator(
        catalog: catalogWith([
          entry(
            name: 'Box',
            properties: [prop('color', PropertyType.color)],
          ),
        ]),
        helpers: HelperRegistry(),
        customWidgetClassifications: {
          flutterCardKey: ComposableWidget(
            flutterCardKey,
            requiredMechanisms: const {InliningMechanism.themeAsData},
            composedCustomWidgets: const [],
          ),
        },
        customWidgetBlueprints: {
          flutterCardKey: CustomWidgetBlueprint(
            classKey: flutterCardKey,
            rfwName: 'AcmeCard',
            buildExpression: body,
            params: const [],
          ),
        },
      );
      final expr = await parseExpressionFromSourceForTest(
        '''
class AcmeCard { const AcmeCard(); }
Object x() => AcmeCard();
        ''',
        rootPackage: 'apps_examples',
      );
      final result = translator.translate(expr);

      expect(result.issues, isEmpty);
      expect(result.dsl, 'AcmeCard()');
      expect(
        result.widgetDefinitions['AcmeCard'],
        'Box(color: data.theme.colorScheme.primary)',
      );
    });

    test('folds a const static-field reference in the body', () async {
      final body = await parseExpressionFromSourceForTest('''
        class Tokens { static const double gap = 12; }
        class Container {
          const Container({this.width});
          final double? width;
        }
        Object x() => Container(width: Tokens.gap);
      ''');
      final translator = ExpressionTranslator(
        catalog: catalogWith([
          entry(
            name: 'Container',
            properties: [prop('width', PropertyType.real)],
          ),
        ]),
        helpers: HelperRegistry(),
        customWidgetClassifications: {
          _cardKey: ComposableWidget(
            _cardKey,
            requiredMechanisms: const {InliningMechanism.constantFolding},
            composedCustomWidgets: const [],
          ),
        },
        customWidgetBlueprints: {
          _cardKey: CustomWidgetBlueprint(
            classKey: _cardKey,
            rfwName: 'AcmeCard',
            buildExpression: body,
            params: const [],
          ),
        },
      );
      final expr = await parseExpressionFromSourceForTest('''
        class AcmeCard { const AcmeCard(); }
        Object x() => AcmeCard();
      ''');
      final result = translator.translate(expr);

      expect(result.issues, isEmpty);
      expect(result.widgetDefinitions['AcmeCard'], 'Container(width: 12.0)');
    });

    Future<TranslationResult> translateCallbackCard(String callbackType) async {
      final body = await parseExpressionForTest('Tappable(onTap)');
      final probe = await parseMethodExpressionFromSourceForTest(
        _callbackCardSource(callbackType),
        className: 'P',
      );
      final translator = ExpressionTranslator(
        catalog: catalogWith([
          entry(
            name: 'Tappable',
            properties: [prop('onTap', PropertyType.event, positional: true)],
          ),
        ]),
        helpers: HelperRegistry()..registerAll(_eventHelpers),
        customWidgetClassifications: {
          _cardKey: ComposableWidget(
            _cardKey,
            requiredMechanisms: const {},
            composedCustomWidgets: const [],
          ),
        },
        customWidgetBlueprints: {
          _cardKey: CustomWidgetBlueprint(
            classKey: _cardKey,
            rfwName: 'AcmeCard',
            buildExpression: body,
            params: [_callbackParamFrom(probe)],
          ),
        },
      );
      return translator.translate(probe.expression);
    }

    test('unwraps a closure bound to a void-callback parameter', () async {
      final result = await translateCallbackCard('void Function()');

      expect(result.issues, isEmpty);
      expect(result.dsl, 'AcmeCard(onTap: event "tapped" {})');
    });

    test('unwraps a closure bound to a future-returning callback parameter',
        () async {
      final result = await translateCallbackCard('Future<void> Function()');

      expect(result.issues, isEmpty);
      expect(result.dsl, 'AcmeCard(onTap: event "tapped" {})');
    });
  });

  group(
      'ExpressionTranslator.attemptInlineEmit — standalone '
      'emit-confirmation seam (coverage harness + CLI)', () {
    test(
        'confirms an inlinable widget against a catalog that declares the '
        'properties its body uses (no call site needed)', () async {
      final body =
          await parseExpressionForTest('Container(child: Text("Pro"))');
      final classification = ComposableWidget(
        _cardKey,
        requiredMechanisms: const {},
        composedCustomWidgets: const [],
      );
      final blueprint = CustomWidgetBlueprint(
        classKey: _cardKey,
        rfwName: 'AcmeCard',
        buildExpression: body,
        params: const [],
      );
      final translator = ExpressionTranslator(
        catalog: catalogWith([
          entry(
            name: 'Container',
            properties: [prop('child', PropertyType.widget)],
          ),
          entry(
            name: 'Text',
            properties: [prop('text', PropertyType.string, positional: true)],
          ),
        ]),
        helpers: HelperRegistry(),
        customWidgetClassifications: {_cardKey: classification},
        customWidgetBlueprints: {_cardKey: blueprint},
      );

      final result = translator.attemptInlineEmit(classification, blueprint);

      expect(result.issues, isEmpty);
      expect(
        result.widgetDefinitions['AcmeCard'],
        'Container(child: Text(text: "Pro"))',
      );
    });

    test(
        'reports issues (emit-failed) when the catalog does not declare a '
        'property the body uses — confirms the metric measures real emit, '
        'not merely classifier recognition', () async {
      final body =
          await parseExpressionForTest('Container(child: Text("Pro"))');
      final classification = ComposableWidget(
        _cardKey,
        requiredMechanisms: const {},
        composedCustomWidgets: const [],
      );
      final blueprint = CustomWidgetBlueprint(
        classKey: _cardKey,
        rfwName: 'AcmeCard',
        buildExpression: body,
        params: const [],
      );
      final translator = ExpressionTranslator(
        // Container declares no `child` property — the body cannot emit.
        catalog: catalogWith([
          entry(name: 'Container', properties: const []),
          entry(name: 'Text', properties: const []),
        ]),
        helpers: HelperRegistry(),
        customWidgetClassifications: {_cardKey: classification},
        customWidgetBlueprints: {_cardKey: blueprint},
      );

      final result = translator.attemptInlineEmit(classification, blueprint);

      expect(result.issues, isNotEmpty);
    });
  });
}
