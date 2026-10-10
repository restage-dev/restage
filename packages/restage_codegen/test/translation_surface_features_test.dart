import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:restage_codegen/src/collection_unroll.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/measurement/measurement_event_occurrence.dart';
import 'package:restage_codegen/src/measurement/measurement_route_emission.dart';
import 'package:restage_codegen/src/paywall_helpers.dart';
import 'package:restage_codegen/src/setstate_recognition.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  ExpressionTranslator translator() => ExpressionTranslator(
        catalog: catalogWith([
          entry(name: 'Text', properties: [prop('text', PropertyType.string)]),
        ]),
        helpers: HelperRegistry()..registerAll(paywallHelpers),
      );

  test('a surface without local values or items needs no feature floor',
      () async {
    final expr = await parseExpressionForTest("Text(text: 'Hi')");
    final result = translator().translate(expr);
    expect(result.issues, isEmpty);
    expect(result.localSeeds, isEmpty);
    expect(result.usesLocalValues, isFalse);
    expect(result.emitsInteractionItems, isFalse);
    expect(result.requiresSurfaceFeatureFloor, isFalse);
  });

  test('either feature requires the surface feature floor', () {
    expect(
      TranslationResult(dsl: 'x', issues: const [], usesLocalValues: true)
          .requiresSurfaceFeatureFloor,
      isTrue,
    );
    expect(
      TranslationResult(dsl: 'x', issues: const [], emitsInteractionItems: true)
          .requiresSurfaceFeatureFloor,
      isTrue,
    );
  });

  test('a measured tap in a static loop records each element as an item',
      () async {
    final root = await parseExpressionFromSourceForTest('''
      class Probe {
        const Probe({this.onPressed});
        final void Function()? onPressed;
      }

      class Column {
        const Column({required this.children});
        final List<Object> children;
      }

      void Function() paywallEvent(String name) => throw UnimplementedError();

      Object x() => Column(children: [
            for (final name in const ['annual', 'monthly'])
              Probe(onPressed: paywallEvent(name)),
          ]);
    ''');
    final column = root as InstanceCreationExpression;
    final childrenArgument =
        column.argumentList.arguments.whereType<NamedArgument>().single;
    final list = childrenArgument.argumentExpression as ListLiteral;
    final occurrence =
        (traverseCollectionList(list).entries.first as CollectionListElement)
            .occurrence;
    final probe = occurrence.terminalExpression as InstanceCreationExpression;
    final eventOccurrence = MeasurementOccurrenceScope.root('test#Source')
        .widget(column.constructorName.type.element! as InterfaceElement)
        .widgetList(childrenArgument.correspondingParameter!)
        .element(0, collectionOccurrence: occurrence)
        .widget(probe.constructorName.type.element! as InterfaceElement)
        .event(
          probe.argumentList.arguments
              .whereType<NamedArgument>()
              .single
              .correspondingParameter!,
        );
    final translator = ExpressionTranslator(
      catalog: catalogWith([
        entry(
          name: 'Column',
          flutterType: '$kSyntheticProbeLibraryUri#Column',
          properties: [prop('children', PropertyType.widgetList)],
        ),
        entry(
          name: 'Probe',
          flutterType: '$kSyntheticProbeLibraryUri#Probe',
          properties: [prop('onPressed', PropertyType.event)],
        ),
      ]),
      helpers: HelperRegistry()
        ..registerAll([
          HelperDefinition(
            name: 'paywallEvent',
            libraryOrigin: 'package:restage_codegen',
            returnCategory: HelperReturnCategory.voidCallback,
            translate: (args) => 'event ${args.positional.single} {}',
          ),
        ]),
      measurementRouteEmissionPlan: MeasurementRouteEmissionPlan([
        MeasurementRouteEmissionBinding(
          occurrence: eventOccurrence,
          generatedReferenceId: GeneratedReferenceId('reference.items'),
        ),
      ]),
    );

    final result = translator.translate(root);

    expect(result.issues, isEmpty);
    expect(result.emitsInteractionItems, isTrue);
    expect(result.requiresSurfaceFeatureFloor, isTrue);
    expect(
      result.dsl,
      allOf(
        contains('$kMeasurementPublicationItemArgumentKeyV1: "1"'),
        contains('$kMeasurementPublicationItemArgumentKeyV1: "2"'),
      ),
    );
  });

  group('value callbacks write screen-local values', () {
    ExpressionTranslator localTranslator() => ExpressionTranslator(
          catalog: catalogWith([
            entry(
              name: 'Text',
              properties: [prop('text', PropertyType.string)],
            ),
            entry(
              name: 'Toggle',
              properties: [
                prop('value', PropertyType.boolean),
                prop('onChanged', PropertyType.event),
              ],
            ),
            entry(
              name: 'Column',
              properties: [prop('children', PropertyType.widgetList)],
            ),
          ]),
          helpers: HelperRegistry()..registerAll(paywallHelpers),
        );

    const reminders = CustomWidgetStateField(
      name: 'reminders',
      isNumeric: false,
      initialValue: true,
    );

    Future<Expression> toggleSource() => parseExpressionFromSourceForTest('''
      class Text { const Text({required this.text}); final String text; }
      class Toggle {
        const Toggle({required this.value, this.onChanged});
        final bool value;
        final void Function(bool)? onChanged;
      }
      class Column {
        const Column({required this.children});
        final List<Object> children;
      }
      bool reminders = true;
      void setState(void Function() update) {}

      Object x() => Column(children: [
            Toggle(
              value: reminders,
              onChanged: (on) => setState(() => reminders = on),
            ),
          ]);
    ''');

    test('the write, the read and the seed', () async {
      final result = localTranslator().translate(
        await toggleSource(),
        rootState: [reminders],
      );
      expect(result.issues, isEmpty);
      expect(
        result.dsl,
        allOf(
          contains('event "restage.local.set" { key: "reminders" }'),
          contains('value: data.local.reminders'),
        ),
      );
      expect(result.rootWidgetState, isEmpty);
      expect(result.localSeeds, {'reminders': true});
      expect(result.usesLocalValues, isTrue);
      expect(result.requiresSurfaceFeatureFloor, isTrue);
    });

    test('a field also flipped by a State method is refused', () async {
      final result = localTranslator().translate(
        await toggleSource(),
        rootState: [reminders],
        rootEventHandlers: const {
          'flip': SetStateBoolFlip(fieldName: 'reminders'),
        },
      );
      expect(
        result.issues.map((issue) => issue.message),
        contains(contains("'reminders' is set by a value callback and by")),
      );
    });

    test('a literal write by a State method is a local set', () async {
      final source = await parseExpressionFromSourceForTest('''
        class Toggle {
          const Toggle({required this.value, this.onChanged});
          final bool value;
          final void Function(bool)? onChanged;
        }
        class Column {
          const Column({required this.children});
          final List<Object> children;
        }
        bool reminders = true;
        void setState(void Function() update) {}
        void mute() {}

        Object x() => Column(children: [
              Toggle(
                value: reminders,
                onChanged: (on) => setState(() => reminders = on),
              ),
              Toggle(value: false, onChanged: mute),
            ]);
      ''');
      final result = localTranslator().translate(
        source,
        rootState: [reminders],
        rootEventHandlers: const {
          'mute': SetStateLiteral(fieldName: 'reminders', value: false),
        },
      );
      expect(result.issues, isEmpty);
      expect(
        result.dsl,
        contains(
          'event "restage.local.set" { key: "reminders", value: false }',
        ),
      );
    });

    test('a field without a scalar initial value is refused', () async {
      final result = localTranslator().translate(
        await toggleSource(),
        rootState: [
          const CustomWidgetStateField(
            name: 'reminders',
            isNumeric: false,
            initialValue: null,
          ),
        ],
      );
      expect(result.issues, isNotEmpty);
    });
  });
}
