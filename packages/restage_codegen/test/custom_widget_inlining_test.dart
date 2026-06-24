import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/widget_classification.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// The classKey `parseExpressionFromSourceForTest` produces for a class named
/// `AcmeCard` — the synthetic probe file is mounted at
/// `package:restage_codegen/_expr_probe.dart`.
const String _cardKey = 'package:restage_codegen/_expr_probe.dart#AcmeCard';

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
      // Phase 4 implements the themeAsData mechanism, so a widget whose
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
