import 'dart:io';

import 'package:a2ui_core/a2ui_core.dart' show CommonSchemas;

import 'package:restage_codegen/src/a2ui/a2ui_catalog_adapter.dart';
import 'package:restage_codegen/src/a2ui/a2ui_dart_emitter.dart';
import 'package:restage_codegen/src/a2ui/a2ui_schema_node.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import '../helpers.dart';

PropertyEntry a2uiProp(
  String name,
  PropertyType type, {
  WireId wireId = WireId.unallocatedProperty,
  bool required = false,
  bool positional = false,
  Object? literalDefault,
  bool constructorNullable = false,
  DartConstValue? constructorDefault,
  String? enumType,
  String? synthetic,
  CatalogValueShape? valueShape,
}) {
  return PropertyEntry(
    wireId: wireId,
    name: name,
    type: type,
    description: '',
    required: required,
    positional: positional,
    enumType: enumType,
    synthetic: synthetic,
    valueShape: valueShape,
    defaultSource: literalDefault == null
        ? null
        : LiteralDefault(literalDefault),
    constructorNullable: constructorNullable,
    constructorDefault: constructorDefault,
  );
}

WidgetEntry a2uiEntry({
  required String name,
  required List<PropertyEntry> properties,
  ChildrenSlot childrenSlot = ChildrenSlot.none,
  List<DecompositionRecipe> decomposes = const [],
}) {
  return entry(
    name: name,
    flutterType: 'package:flutter/widgets.dart#$name',
    childrenSlot: childrenSlot,
    properties: properties,
    decomposes: decomposes,
  );
}

String emitSource(List<WidgetEntry> widgets) =>
    emitA2uiCatalogDart(catalogWith(widgets));

void main() {
  group('emitA2uiCatalogDart', () {
    test('forbidden component names point to the annotation override', () {
      for (final name in ['Surface', 'bad-name', '@Component']) {
        expect(
          () => emitSource([a2uiEntry(name: name, properties: [])]),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.toString(),
              'diagnostic',
              contains('@RestageWidget(name: ...)'),
            ),
          ),
        );
      }
    });

    test('custom fields use one required props namespace without reserving '
        'envelope names', () {
      const customLibrary = WidgetLibrary.custom('acme.widgets');
      final custom = entry(
        name: 'CollisionCard',
        library: customLibrary,
        flutterType: 'package:acme/widgets.dart#CollisionCard',
        properties: [
          a2uiProp('id', PropertyType.string),
          a2uiProp('component', PropertyType.string),
          a2uiProp('catalogId', PropertyType.string),
          a2uiProp('props', PropertyType.string),
        ],
      );
      final catalog = catalogWith(
        [custom],
        library: customLibrary,
      );

      final plan = classifyA2uiCatalogDart(catalog);
      expect(plan.coverage.droppedWidgets, isEmpty);
      expect(
        plan.widgets.single.fields.map((field) => field.property.name),
        ['id', 'component', 'catalogId', 'props'],
      );

      final source = emitA2uiCatalogDart(catalog);
      for (final name in ['id', 'component', 'catalogId', 'props']) {
        expect(source, contains("'props_$name': S.combined("));
        expect(source, contains("data['props_$name']"));
      }
      expect(source, isNot(contains("data['props']")));
      expect(source, contains('restageProps.value(key)'));
    });

    test('maps core scalar property types to the blessed Bound widgets', () {
      final source = emitSource([
        a2uiEntry(
          name: 'ControlPanel',
          properties: [
            a2uiProp('enabled', PropertyType.boolean),
            a2uiProp('count', PropertyType.integer),
            a2uiProp('opacity', PropertyType.real),
            a2uiProp('height', PropertyType.length),
            a2uiProp('title', PropertyType.string),
            a2uiProp('tags', PropertyType.stringList),
          ],
        ),
      ]);

      expect(
        source,
        contains("ComponentProps.asBoolean(data['props_enabled'])"),
      );
      expect(source, contains("ComponentProps.asString(data['props_title'])"));
      for (final name in ['count', 'opacity', 'height', 'tags']) {
        expect(source, contains("data['props_$name']"));
        expect(source, contains("'props_$name': S.combined("));
      }
      expect(source, contains('S.integer()'));
      expect(source, contains('S.number()'));
      expect(source, isNot(contains('Bound')));
      expect(source, contains('enabled: enabled ?? false,'));
      expect(source, contains('count: (count ?? 0).toInt(),'));
      expect(source, contains('opacity: (opacity ?? 0).toDouble(),'));
      expect(source, contains('height: (height ?? 0).toDouble(),'));
      expect(source, contains("title: title ?? '',"));
      expect(
        source,
        contains('tags: ((tags is List ? tags.cast<Object?>() : null) ??'),
      );
      expect(
        source,
        contains('.whereType<String>()'),
      );
      expect(
        source,
        contains('.toList(growable: false),'),
      );
    });

    test('an omitted nullable scalar without a declared default is null', () {
      final catalog = catalogWith([
        a2uiEntry(
          name: 'Optional',
          properties: [
            a2uiProp('count', PropertyType.integer),
            a2uiProp('label', PropertyType.string),
            a2uiProp('featured', PropertyType.boolean),
            a2uiProp('accent', PropertyType.color),
          ],
        ),
      ]);
      const shapes = <(String, String), A2uiSchemaNode>{
        ('Optional', 'count'): ScalarNode(
          A2uiScalarType.integer,
          nullable: true,
        ),
        ('Optional', 'label'): ScalarNode(
          A2uiScalarType.string,
          nullable: true,
        ),
        ('Optional', 'featured'): ScalarNode(
          A2uiScalarType.boolean,
          nullable: true,
        ),
        ('Optional', 'accent'): ScalarNode(
          A2uiScalarType.string,
          nullable: true,
        ),
      };
      final dense = emitA2uiCatalogDart(
        catalog,
        richShapes: shapes,
      ).replaceAll(RegExp(r'\s+'), '');
      for (final name in ['count', 'label', 'featured', 'accent']) {
        expect(dense, contains("$name:data.containsKey('props_$name')?("));
        expect(dense, matches(RegExp('$name:[^,]*\\):null,')), reason: name);
      }
      expect(dense, isNot(contains('??0')));
      expect(dense, isNot(contains("??''")));
      expect(dense, isNot(contains('??false')));
      expect(dense, isNot(contains('constColor(0x00000000)')));
    });

    test(
      'a required nullable scalar keeps presence and nullability distinct',
      () {
        final catalog = catalogWith([
          a2uiEntry(
            name: 'NullableInput',
            properties: [
              a2uiProp('value', PropertyType.string, required: true),
            ],
          ),
        ]);
        const shapes = <(String, String), A2uiSchemaNode>{
          ('NullableInput', 'value'): ScalarNode(
            A2uiScalarType.string,
            nullable: true,
          ),
        };

        final source = emitA2uiCatalogDart(catalog, richShapes: shapes);
        expect(
          source,
          contains(
            'S.combined(anyOf: [S.string(), S.nil()])',
          ),
        );
        expect(
          source.replaceAll(RegExp(r'\s+'), ''),
          contains(
            "data['props_value']==null?null:value,",
          ),
        );
        expect(source, isNot(contains("data.containsKey('props_value')")));

        final component = emitA2uiCatalog(
          catalog,
          richShapes: shapes,
        ).components.single.dataSchema;
        expect(component['required'], ['props_value']);
        final properties = component['properties']! as Map<String, Object?>;
        expect((properties['props_value']! as Map)['oneOf'] is List, isTrue);
        expect(((properties['props_value']! as Map)['oneOf']! as List).first, {
          'anyOf': [
            {'type': 'string'},
            {'type': 'null'},
          ],
        });
      },
    );

    test('nullable defaults preserve null and failed normalization', () {
      final catalog = catalogWith([
        a2uiEntry(
          name: 'NullableDefaults',
          properties: [
            a2uiProp(
              'label',
              PropertyType.string,
              literalDefault: 'Included',
            ),
            a2uiProp(
              'featured',
              PropertyType.boolean,
              literalDefault: true,
            ),
            a2uiProp('count', PropertyType.integer, literalDefault: 7),
            a2uiProp('amount', PropertyType.real, literalDefault: 12.5),
            a2uiProp('timeout', PropertyType.duration, literalDefault: 250),
            a2uiProp('weight', PropertyType.fontWeight),
            a2uiProp(
              'accent',
              PropertyType.color,
              literalDefault: '#FF00AA',
            ),
            a2uiProp(
              'fit',
              PropertyType.enumValue,
              enumType: 'BoxFit',
              literalDefault: 'cover',
            ),
            a2uiProp(
              'requiredValue',
              PropertyType.string,
              required: true,
            ),
            a2uiProp(
              'requiredFeatured',
              PropertyType.boolean,
              required: true,
            ),
            a2uiProp(
              'requiredAmount',
              PropertyType.real,
              required: true,
            ),
            a2uiProp(
              'requiredAccent',
              PropertyType.color,
              required: true,
            ),
            a2uiProp(
              'requiredFit',
              PropertyType.enumValue,
              enumType: 'BoxFit',
              required: true,
            ),
          ],
        ),
      ]);
      final shapes = <(String, String), A2uiSchemaNode>{
        ('NullableDefaults', 'label'): const ScalarNode(
          A2uiScalarType.string,
          nullable: true,
        ),
        ('NullableDefaults', 'featured'): const ScalarNode(
          A2uiScalarType.boolean,
          nullable: true,
        ),
        ('NullableDefaults', 'count'): const ScalarNode(
          A2uiScalarType.integer,
          nullable: true,
        ),
        ('NullableDefaults', 'amount'): const ScalarNode(
          A2uiScalarType.number,
          nullable: true,
        ),
        ('NullableDefaults', 'timeout'): const ScalarNode(
          A2uiScalarType.number,
          nullable: true,
        ),
        ('NullableDefaults', 'weight'): const ScalarNode(
          A2uiScalarType.number,
          nullable: true,
        ),
        ('NullableDefaults', 'accent'): const ScalarNode(
          A2uiScalarType.string,
          nullable: true,
        ),
        ('NullableDefaults', 'fit'): EnumNode(
          dartTypeName: 'BoxFit',
          members: const ['fill', 'cover'],
          nullable: true,
        ),
        ('NullableDefaults', 'requiredValue'): const ScalarNode(
          A2uiScalarType.string,
          nullable: true,
        ),
        ('NullableDefaults', 'requiredFeatured'): const ScalarNode(
          A2uiScalarType.boolean,
          nullable: true,
        ),
        ('NullableDefaults', 'requiredAmount'): const ScalarNode(
          A2uiScalarType.number,
          nullable: true,
        ),
        ('NullableDefaults', 'requiredAccent'): const ScalarNode(
          A2uiScalarType.string,
          nullable: true,
        ),
        ('NullableDefaults', 'requiredFit'): EnumNode(
          dartTypeName: 'BoxFit',
          members: const ['fill', 'cover'],
          nullable: true,
        ),
      };

      final source = emitA2uiCatalogDart(catalog, richShapes: shapes);
      final compact = source.replaceAll(RegExp(r'\s+'), ' ');
      final dense = source.replaceAll(RegExp(r'\s+'), '');

      expect(
        dense,
        contains(
          [
            "label:data.containsKey('props_label')?(",
            "itemContext.componentModel.properties['props_label']==null?null:(label??'Included')):",
            "'Included',",
          ].join(),
        ),
      );
      expect(
        dense,
        contains(
          [
            "featured:data.containsKey('props_featured')?(",
            "itemContext.componentModel.properties['props_featured']==null?null:(featured??true)):",
            'true,',
          ].join(),
        ),
      );
      expect(
        dense,
        contains(
          [
            "count:data.containsKey('props_count')?(",
            "itemContext.componentModel.properties['props_count']==null?null:(count?.toInt()??(count?",
            '?7).toInt())):(count??7).toInt(),',
          ].join(),
        ),
      );
      expect(
        dense,
        contains(
          "itemContext.componentModel.properties['props_amount']==null?null",
        ),
      );
      expect(dense, contains('amount?.toDouble()'));
      expect(dense, contains('(amount??12.5).toDouble()'));
      expect(
        dense,
        contains(
          "itemContext.componentModel.properties['props_timeout']==null?null",
        ),
      );
      expect(dense, contains('Duration(milliseconds:timeout.toInt())'));
      expect(
        dense,
        contains('Duration(milliseconds:(timeout??250).toInt())'),
      );
      expect(dense, contains("data['props_weight']==null?null"));
      expect(
        dense,
        contains('_restageA2uiFontWeight(weight,FontWeight.normal)'),
      );
      expect(
        dense,
        contains(
          [
            "accent:data.containsKey('props_accent')?(",
            "itemContext.componentModel.properties['props_accent']==null?null:(_restageA2uiColor(",
            "accent)??_restageA2uiColor('#FF00AA')??constColor(",
            '0x00000000))):',
          ].join(),
        ),
      );
      expect(
        dense,
        contains(
          [
            "fit:data.containsKey('props_fit')?(itemContext.componentModel.properties['props_fit']",
            '==null?null:(BoxFit.values.asNameMap()[fit]??',
            'BoxFit.cover)):BoxFit.cover,',
          ].join(),
        ),
      );
      expect(
        dense,
        contains(
          [
            "requiredValue:data['props_requiredValue']==null?null:",
            'requiredValue,',
          ].join(),
        ),
      );
      expect(
        dense,
        isNot(contains("data.containsKey('props_requiredValue')")),
      );
      expect(
        dense,
        contains(
          [
            "requiredFeatured:data['props_requiredFeatured']==null?",
            'null:requiredFeatured,',
          ].join(),
        ),
      );
      expect(
        dense,
        contains(
          [
            "requiredAmount:data['props_requiredAmount']==null?null:",
            'requiredAmount?.toDouble(),',
          ].join(),
        ),
      );
      expect(
        dense,
        contains(
          [
            "requiredAccent:data['props_requiredAccent']==null?null:",
            '_restageA2uiColor(requiredAccent),',
          ].join(),
        ),
      );
      expect(
        dense,
        contains(
          [
            "requiredFit:data['props_requiredFit']==null?null:",
            'BoxFit.values.asNameMap()[requiredFit],',
          ].join(),
        ),
      );
      expect(
        compact,
        isNot(contains("data.containsKey('props_requiredFeatured')")),
      );
      expect(
        compact,
        isNot(contains("data.containsKey('props_requiredAmount')")),
      );
      expect(
        compact,
        isNot(contains("data.containsKey('props_requiredAccent')")),
      );
      expect(
        compact,
        isNot(contains("data.containsKey('props_requiredFit')")),
      );
    });

    test(
      'constructor truth wins over annotation seed while native key presence '
      'preserves omission versus null',
      () {
        final catalog = catalogWith([
          a2uiEntry(
            name: 'ConstructorDefault',
            properties: [
              a2uiProp(
                'label',
                PropertyType.string,
                literalDefault: 'preview-seed',
                constructorNullable: true,
                constructorDefault: const DartConstScalar(
                  'constructor-default',
                ),
              ),
            ],
          ),
        ]);
        const shapes = <(String, String), A2uiSchemaNode>{
          ('ConstructorDefault', 'label'): ScalarNode(
            A2uiScalarType.string,
            nullable: true,
          ),
        };

        final dense = emitA2uiCatalogDart(
          catalog,
          richShapes: shapes,
        ).replaceAll(RegExp(r'\s+'), '');

        expect(
          dense,
          contains(
            [
              "label:data.containsKey('props_label')?(",
              "itemContext.componentModel.properties['props_label']==null?null:(label??",
              "'constructor-default')):'constructor-default',",
            ].join(),
          ),
        );
        expect(dense, isNot(contains('preview-seed')));
      },
    );

    test(
      'a required nullable child is schema-required without a null assert',
      () {
        final catalog = catalogWith([
          a2uiEntry(
            name: 'NullableChild',
            childrenSlot: ChildrenSlot.single,
            properties: [
              a2uiProp('child', PropertyType.widget, required: true),
            ],
          ),
        ]);
        const shapes = <(String, String), A2uiSchemaNode>{
          ('NullableChild', 'child'): ScalarNode(
            A2uiScalarType.string,
            nullable: true,
          ),
        };

        final source = emitA2uiCatalogDart(catalog, richShapes: shapes);
        expect(
          source,
          contains(
            'child: _restageA2uiBuildChild(restageBuildChild, '
            "data['props_child']),",
          ),
        );
        expect(
          source,
          isNot(
            contains(
              'child: _restageA2uiBuildChild(restageBuildChild, '
              "data['props_child'])!,",
            ),
          ),
        );

        final component = emitA2uiCatalog(
          catalog,
          richShapes: shapes,
        ).components.single.dataSchema;
        expect(component['required'], ['props_child']);
        final properties = component['properties']! as Map<String, Object?>;
        expect(properties['props_child'], {
          'anyOf': [
            CommonSchemas.componentId.value,
            {'type': 'null'},
          ],
        });
      },
    );

    test('a required non-nullable child uses the checked resolver once', () {
      final source = emitSource([
        a2uiEntry(
          name: 'RequiredChild',
          childrenSlot: ChildrenSlot.single,
          properties: [
            a2uiProp('child', PropertyType.widget, required: true),
          ],
        ),
      ]);
      final dense = source.replaceAll(RegExp(r'\s+'), '');

      expect(
        dense,
        contains(
          [
            'child:_restageA2uiRequireChild(restageBuildChild,',
            "data['props_child'],'RequiredChild.child'),",
          ].join(),
        ),
      );
      expect(
        source,
        contains('child.isPlaceholder'),
      );
      expect(
        source,
        contains('return buildChild(child);'),
      );
      expect(
        source,
        contains('child is! ComponentNode<ComponentImplementation>'),
      );
      expect(
        source,
        isNot(contains('if (child == null)')),
      );
      expect(
        source,
        isNot(
          contains(
            "_restageA2uiBuildChild(restageBuildChild, data['props_child'])!",
          ),
        ),
      );
    });

    test('nullable children distinguish missing keys and null', () {
      final catalog = catalogWith([
        a2uiEntry(
          name: 'NullableChild',
          childrenSlot: ChildrenSlot.single,
          properties: [a2uiProp('child', PropertyType.widget)],
        ),
        a2uiEntry(
          name: 'NullableChildren',
          childrenSlot: ChildrenSlot.list,
          properties: [a2uiProp('children', PropertyType.widgetList)],
        ),
      ]);
      const shapes = <(String, String), A2uiSchemaNode>{
        ('NullableChild', 'child'): ScalarNode(
          A2uiScalarType.string,
          nullable: true,
        ),
        ('NullableChildren', 'children'): ListNode(
          element: ScalarNode(A2uiScalarType.string),
          nullable: true,
        ),
      };

      final source = emitA2uiCatalogDart(catalog, richShapes: shapes);
      final compact = source.replaceAll(RegExp(r'\s+'), ' ');

      expect(
        compact,
        contains(
          "child: data.containsKey('props_child') ? "
          '_restageA2uiBuildChild(restageBuildChild, '
          "data['props_child']) : null,",
        ),
      );
      expect(
        compact,
        contains("children: data.containsKey('props_children') ?"),
      );
      expect(
        compact,
        contains(
          "data['props_children'] == null ? null : _restageA2uiBuildChildren( "
          "restageBuildChild, data['props_children'])",
        ),
      );
      expect(
        compact,
        contains(
          '_restageA2uiBuildChildren( restageBuildChild, '
          "data['props_children'])) : null,",
        ),
      );
    });

    test(
      'analyzer-fed scalar lists stay reactive and construct type-safely',
      () {
        final catalog = catalogWith([
          a2uiEntry(
            name: 'ScalarLists',
            properties: [
              a2uiProp('labels', PropertyType.structured, required: true),
              a2uiProp('counts', PropertyType.structured, required: true),
              a2uiProp('weights', PropertyType.structured, required: true),
              a2uiProp('measurements', PropertyType.structured, required: true),
              a2uiProp('flags', PropertyType.structured, required: true),
              a2uiProp('maybeCounts', PropertyType.structured),
              a2uiProp('defaultCounts', PropertyType.structured),
              a2uiProp(
                'fallbackLabels',
                PropertyType.structured,
                required: true,
                literalDefault: ['a', "b's"],
              ),
              a2uiProp(
                'fallbackFlags',
                PropertyType.structured,
                required: true,
                literalDefault: [true, false],
              ),
              a2uiProp(
                'fallbackCounts',
                PropertyType.structured,
                required: true,
                literalDefault: [1, 2],
              ),
              a2uiProp(
                'fallbackWeights',
                PropertyType.structured,
                required: true,
                literalDefault: [1.5, 2.0],
              ),
              a2uiProp(
                'fallbackMeasurements',
                PropertyType.structured,
                required: true,
                literalDefault: [1, 2.5],
              ),
              a2uiProp(
                'fallbackMaybeCounts',
                PropertyType.structured,
                required: true,
                literalDefault: [1, null, 2],
              ),
              a2uiProp(
                'fallbackNullableList',
                PropertyType.structured,
                literalDefault: [3],
              ),
            ],
          ),
        ]);
        const richShapes = <(String, String), A2uiSchemaNode>{
          ('ScalarLists', 'labels'): ListNode(
            element: ScalarNode(A2uiScalarType.string),
          ),
          ('ScalarLists', 'counts'): ListNode(
            element: ScalarNode(A2uiScalarType.integer),
          ),
          ('ScalarLists', 'weights'): ListNode(
            element: ScalarNode(A2uiScalarType.number),
          ),
          ('ScalarLists', 'measurements'): ListNode(
            element: ScalarNode(
              A2uiScalarType.number,
              preserveNumericRuntimeType: true,
            ),
          ),
          ('ScalarLists', 'flags'): ListNode(
            element: ScalarNode(A2uiScalarType.boolean),
          ),
          ('ScalarLists', 'maybeCounts'): ListNode(
            element: ScalarNode(A2uiScalarType.integer),
            nullable: true,
          ),
          ('ScalarLists', 'defaultCounts'): ListNode(
            element: ScalarNode(A2uiScalarType.integer),
          ),
          ('ScalarLists', 'fallbackLabels'): ListNode(
            element: ScalarNode(A2uiScalarType.string),
          ),
          ('ScalarLists', 'fallbackFlags'): ListNode(
            element: ScalarNode(A2uiScalarType.boolean),
          ),
          ('ScalarLists', 'fallbackCounts'): ListNode(
            element: ScalarNode(A2uiScalarType.integer),
          ),
          ('ScalarLists', 'fallbackWeights'): ListNode(
            element: ScalarNode(A2uiScalarType.number),
          ),
          ('ScalarLists', 'fallbackMeasurements'): ListNode(
            element: ScalarNode(
              A2uiScalarType.number,
              preserveNumericRuntimeType: true,
            ),
          ),
          ('ScalarLists', 'fallbackMaybeCounts'): ListNode(
            element: ScalarNode(A2uiScalarType.integer, nullable: true),
          ),
          ('ScalarLists', 'fallbackNullableList'): ListNode(
            element: ScalarNode(A2uiScalarType.integer),
            nullable: true,
          ),
        };

        final source = emitA2uiCatalogDart(catalog, richShapes: richShapes);
        final compactSource = source.replaceAll(RegExp(r'\s+'), ' ');
        final denseSource = source.replaceAll(RegExp(r'\s+'), '');

        expect(
          r'common_types.json#/$defs/DataBinding'.allMatches(source),
          hasLength(13),
        );
        expect(source, contains("data['props_labels']"));
        expect(source, contains("data['props_counts']"));
        expect(source, contains("data['props_weights']"));
        expect(source, contains("data['props_measurements']"));
        expect(source, contains("data['props_flags']"));
        expect(source, isNot(contains("data['props_defaultCounts']")));
        expect(source, isNot(contains('defaultCounts:')));
        expect(source, contains('.whereType<String>()'));
        expect(source, contains('.whereType<bool>()'));
        expect(compactSource, contains('value is num ? value.toInt() : null'));
        expect(
          compactSource,
          contains('value is num ? value.toDouble() : null'),
        );
        expect(compactSource, contains('value is num ? value : null'));
        expect(source, contains('.whereType<num>()'));
        expect(source, contains('?.map((value)'));
        expect(
          compactSource,
          contains(
            'fallbackLabels is List ? '
            'fallbackLabels.cast<Object?>() : null',
          ),
        );
        expect(
          compactSource,
          contains(r"const <String>['a', 'b\'s']"),
        );
        expect(
          compactSource,
          contains('const <bool>[true, false]'),
        );
        expect(
          compactSource,
          contains('const <int>[1, 2]'),
        );
        expect(
          compactSource,
          contains('const <double>[1.5, 2.0]'),
        );
        expect(
          compactSource,
          contains('const <num>[1, 2.5]'),
        );
        expect(
          compactSource,
          contains('const <int?>[1, null, 2]'),
        );
        expect(compactSource, contains('const <int>[3]'));
        expect(
          compactSource,
          contains('counts is List ? counts.cast<Object?>() : null'),
        );
        expect(
          denseSource,
          contains(
            [
              "data.containsKey('props_maybeCounts')?(",
              "data['props_maybeCounts']==null?null:(",
              'maybeCountsisList?maybeCounts.cast<Object?>():null)):',
              'null',
            ].join(),
          ),
        );

        expect('S.combined(oneOf:'.allMatches(source), hasLength(13));
        expect(source, contains(r'common_types.json#/$defs/DataBinding'));
        expect(source, contains(r'common_types.json#/$defs/FunctionCall'));
        expect(source, contains(r'common_types.json#/$defs/FunctionCall'));
        expect(
          compactSource,
          contains(
            "'props_maybeCounts': S.combined(oneOf: [ "
            'S.combined(anyOf: [S.list(items: S.integer()), '
            'S.nil()])',
          ),
        );

        final stamp = emitA2uiCatalog(catalog, richShapes: richShapes).toJson();
        final a2uiCatalog = stamp['a2uiCatalog']! as Map<String, Object?>;
        final components = a2uiCatalog['components']! as Map<String, Object?>;
        final scalarLists = components['ScalarLists']! as Map<String, Object?>;
        final properties = scalarLists['properties']! as Map<String, Object?>;

        final labels = properties['props_labels']! as Map<String, Object?>;
        final labelAlternatives = labels['oneOf']! as List<Object?>;
        expect(labelAlternatives, hasLength(3));
        expect(labelAlternatives[0], {
          'type': 'array',
          'items': {'type': 'string'},
        });
        expect(labelAlternatives[1], {
          r'$ref': r'common_types.json#/$defs/DataBinding',
        });
        expect(labelAlternatives[2], {
          r'$ref': r'common_types.json#/$defs/FunctionCall',
        });

        final maybeCounts =
            properties['props_maybeCounts']! as Map<String, Object?>;
        final maybeAlternatives = maybeCounts['oneOf']! as List<Object?>;
        expect(maybeAlternatives[0], {
          'anyOf': [
            {
              'type': 'array',
              'items': {'type': 'integer'},
            },
            {'type': 'null'},
          ],
        });
      },
    );

    test('nullable scalar-list normalization preserves null and fallback', () {
      final catalog = catalogWith([
        a2uiEntry(
          name: 'NullableListDefault',
          properties: [
            a2uiProp(
              'values',
              PropertyType.structured,
              literalDefault: [4],
            ),
            a2uiProp(
              'requiredValues',
              PropertyType.structured,
              required: true,
            ),
          ],
        ),
      ]);
      const shapes = <(String, String), A2uiSchemaNode>{
        ('NullableListDefault', 'values'): ListNode(
          element: ScalarNode(A2uiScalarType.integer),
          nullable: true,
        ),
        ('NullableListDefault', 'requiredValues'): ListNode(
          element: ScalarNode(A2uiScalarType.integer),
          nullable: true,
        ),
      };

      final source = emitA2uiCatalogDart(catalog, richShapes: shapes);
      final compact = source.replaceAll(RegExp(r'\s+'), ' ');
      final dense = source.replaceAll(RegExp(r'\s+'), '');

      expect(
        dense,
        contains(
          "data.containsKey('props_values')?(itemContext.componentModel.properties['props_values']==null?null:",
        ),
      );
      expect(
        dense,
        contains(
          '(valuesisList?values.cast<Object?>():null)??const<int>[4]',
        ),
      );
      expect(
        dense,
        contains(':const<int>[4])?.map'),
      );
      expect(
        dense,
        contains(
          [
            "data['props_requiredValues']==null?null:(",
            'requiredValuesisList?requiredValues.cast<Object?>():',
            'null)',
          ].join(),
        ),
      );
      expect(
        compact,
        isNot(contains("data.containsKey('props_requiredValues')")),
      );
    });

    test('invalid scalar-list literal defaults fail generation loudly', () {
      final catalog = catalogWith([
        a2uiEntry(
          name: 'InvalidDefault',
          properties: [
            a2uiProp(
              'counts',
              PropertyType.structured,
              required: true,
              literalDefault: [1.5],
            ),
          ],
        ),
      ]);

      expect(
        () => emitA2uiCatalogDart(
          catalog,
          richShapes: const {
            ('InvalidDefault', 'counts'): ListNode(
              element: ScalarNode(A2uiScalarType.integer),
            ),
          },
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(contains('counts'), contains('index 0'), contains('int')),
          ),
        ),
      );
    });

    test(
      'catalog-fed booleanList remains outside the A2UI leaf vocabulary',
      () {
        final plan = classifyA2uiCatalogDart(
          catalogWith([
            a2uiEntry(
              name: 'BooleanSelections',
              properties: [
                a2uiProp(
                  'selected',
                  PropertyType.booleanList,
                  required: true,
                ),
              ],
            ),
          ]),
        );

        expect(plan.widgets, isEmpty);
        expect(plan.coverage.droppedWidgets, hasLength(1));
        expect(
          plan.coverage.droppedWidgets.single.reason,
          A2uiDartCoverageReason.requiredUnsupportedPropertyType,
        );
      },
    );

    test(
      'emits a color field as a string schema decoded through the helper',
      () {
        final source = emitSource([
          a2uiEntry(
            name: 'Swatch',
            properties: [
              a2uiProp('tint', PropertyType.color),
              a2uiProp(
                'accent',
                PropertyType.color,
                literalDefault: '#FF00AA',
              ),
            ],
          ),
        ]);

        // A color is a BoundString field whose value is run through the
        // hex decoder, falling back to the catalog default (or
        // transparent).
        expect(source, contains("'props_tint': S.combined("));
        expect(source, contains('ComponentProps.asString('));
        expect(
          source,
          contains('tint: _restageA2uiColor(tint) ?? const Color(0x00000000),'),
        );
        // The defaulted color decodes the bound value, then the catalog
        // default,
        // then transparent (the emitter wraps the long fallback chain).
        expect(source, contains('accent: _restageA2uiColor(accent) ??'));
        expect(source, contains("_restageA2uiColor('#FF00AA') ??"));
      },
    );

    test('emits enum fields as string schemas with fail-closed lookup', () {
      final source = emitSource([
        a2uiEntry(
          name: 'ImageLike',
          properties: [
            a2uiProp(
              'fit',
              PropertyType.enumValue,
              enumType: 'BoxFit',
              literalDefault: 'cover',
            ),
          ],
        ),
      ]);

      expect(source, contains("'props_fit': S.string()"));
      expect(source, contains('ComponentProps.asString('));
      expect(source, contains("data['props_fit']"));
      expect(
        source,
        contains('fit: BoxFit.values.asNameMap()[fit] ?? BoxFit.cover,'),
      );
      expect(source, isNot(contains('.values.byName(')));
    });

    test(
      'a required enum without a default fails closed to the first member',
      () {
        final source = emitSource([
          a2uiEntry(
            name: 'RequiredEnumWidget',
            properties: [
              a2uiProp(
                'fit',
                PropertyType.enumValue,
                enumType: 'BoxFit',
                required: true,
              ),
            ],
          ),
        ]);

        // A non-nullable required enum param must receive a valid member,
        // never
        // null — fail closed to the first declared value, never `.byName`
        // (which throws).
        expect(
          source,
          contains(
            'fit: BoxFit.values.asNameMap()[fit] ?? BoxFit.values.first,',
          ),
        );
        expect(source, isNot(contains('.values.byName(')));
      },
    );

    test('uses catalog-declared literal defaults as null fallbacks', () {
      final source = emitSource([
        a2uiEntry(
          name: 'PriceBadge',
          properties: [
            a2uiProp(
              'label',
              PropertyType.string,
              literalDefault: 'Included',
            ),
            a2uiProp('amount', PropertyType.real, literalDefault: 12.5),
            a2uiProp('featured', PropertyType.boolean, literalDefault: true),
          ],
        ),
      ]);

      expect(source, contains("label: label ?? 'Included',"));
      expect(source, contains('amount: (amount ?? 12.5).toDouble(),'));
      expect(source, contains('featured: featured ?? true,'));
      expect(source, isNot(contains("label: label ?? '',")));
      expect(source, isNot(contains('amount: (amount ?? 0).toDouble(),')));
      expect(source, isNot(contains('featured: featured ?? false,')));
    });

    test('omits optional structured fields and drops required ones', () {
      final optional = a2uiEntry(
        name: 'OptionalStyle',
        properties: [
          a2uiProp('label', PropertyType.string),
          a2uiProp('shape', PropertyType.shapeBorder),
        ],
      );
      final required = a2uiEntry(
        name: 'RequiredInset',
        properties: [
          a2uiProp('padding', PropertyType.edgeInsets, required: true),
        ],
      );

      final plan = classifyA2uiCatalogDart(catalogWith([optional, required]));
      final source = emitA2uiCatalogDart(catalogWith([optional, required]));

      expect(source, contains("name: 'OptionalStyle'"));
      expect(source, isNot(contains("'shape':")));
      expect(source, isNot(contains('shape: shape')));
      expect(source, isNot(contains("name: 'RequiredInset'")));
      expect(plan.coverage.emittableWidgetCount, 1);
      expect(plan.coverage.droppedWidgets, hasLength(1));
      expect(plan.coverage.droppedWidgets.single.widgetName, 'RequiredInset');
      expect(
        plan.coverage.droppedWidgets.single.reason,
        A2uiDartCoverageReason.requiredUnsupportedPropertyType,
      );
      expect(plan.coverage.omittedFields, hasLength(1));
      expect(plan.coverage.omittedFields.single.widgetName, 'OptionalStyle');
      expect(plan.coverage.omittedFields.single.fieldName, 'shape');
    });

    test('omits event fields from schema and construction', () {
      final pressable = a2uiEntry(
        name: 'Pressable',
        properties: [
          a2uiProp('label', PropertyType.string),
          a2uiProp('onPressed', PropertyType.event),
        ],
      );

      final plan = classifyA2uiCatalogDart(catalogWith([pressable]));
      final source = emitA2uiCatalogDart(catalogWith([pressable]));

      expect(source, contains("name: 'Pressable'"));
      expect(source, isNot(contains("'onPressed':")));
      expect(source, isNot(contains('onPressed:')));
      expect(
        plan.coverage.omittedFields.single.reason,
        A2uiDartCoverageReason.eventProperty,
      );
    });

    test('renders single and list children via child id fields', () {
      final source = emitSource([
        a2uiEntry(
          name: 'ChildFrame',
          childrenSlot: ChildrenSlot.single,
          properties: [
            a2uiProp('child', PropertyType.widget),
            a2uiProp('gap', PropertyType.real),
          ],
        ),
        a2uiEntry(
          name: 'ChildColumn',
          childrenSlot: ChildrenSlot.list,
          properties: [
            a2uiProp('children', PropertyType.widgetList),
          ],
        ),
      ]);

      expect(source, contains("'props_child': CommonSchemas.componentId"));
      expect(
        source,
        contains("'props_children': S.list(items: CommonSchemas.componentId)"),
      );
      expect(source, contains('_restageA2uiBuildChild(restageBuildChild'));
      expect(source, contains("data['props_child']"));
      expect(
        source.replaceAll(RegExp(r'\s+'), ''),
        contains('_restageA2uiBuildChildren(restageBuildChild'),
      );
      expect(source, contains("data['props_children']"));
      expect(
        source,
        isNot(contains("ComponentProps.asString(data['props_child'])")),
      );
      expect(
        source,
        isNot(contains("ComponentProps.asString(data['props_children'])")),
      );
    });

    test('lifts decompose widgets by omitting recipe-consumed fields', () {
      final textProp = WireId('p0001');
      final fontSizeProp = WireId('p0002');
      final fontPackageProp = WireId('p0003');
      final maxLinesProp = WireId('p0004');
      final styled = a2uiEntry(
        name: 'StyledText',
        properties: [
          a2uiProp(
            'text',
            PropertyType.string,
            wireId: textProp,
            required: true,
            positional: true,
          ),
          a2uiProp('fontSize', PropertyType.real, wireId: fontSizeProp),
          a2uiProp('fontPackage', PropertyType.string, wireId: fontPackageProp),
          a2uiProp('maxLines', PropertyType.integer, wireId: maxLinesProp),
        ],
        decomposes: [
          DecompositionRecipe(
            structuredRef: const WireIdRef(
              library: 'restage.core',
              wireId: WireId.unallocatedStructured,
            ),
            flatProperties: {
              WireId('p0501'): fontSizeProp,
            },
            fieldMappings: [
              DecompositionFieldMapping(
                fieldRef: WireId('p0501'),
                propertyRef: fontSizeProp,
                transform: const IdentityTransform(),
              ),
            ],
            parameterMappings: [
              DecompositionParameterMapping(
                parameterRef: WireId('a0001'),
                propertyRef: fontPackageProp,
                transform: const IdentityTransform(),
              ),
            ],
          ),
        ],
      );

      final plan = classifyA2uiCatalogDart(catalogWith([styled]));
      final source = emitA2uiCatalogDart(catalogWith([styled]));

      expect(source, contains("name: 'StyledText'"));
      expect(source, contains("'props_text': S.combined("));
      expect(source, contains("'props_maxLines': S.combined("));
      expect(source, contains("data['props_text']"));
      expect(source, contains("data['props_maxLines']"));
      expect(source, isNot(contains("'fontSize':")));
      expect(source, isNot(contains("'fontPackage':")));
      expect(source, isNot(contains("data['props_fontSize']")));
      expect(source, isNot(contains("data['props_fontPackage']")));
      expect(source, isNot(contains('style:')));
      expect(plan.coverage.droppedWidgets, isEmpty);
      expect(plan.coverage.emittableWidgetCount, 1);
      expect(
        {
          for (final omission in plan.coverage.omittedFields)
            omission.fieldName: omission.reason,
        },
        {
          'fontSize': A2uiDartCoverageReason.nativeDecomposeUnsupported,
          'fontPackage': A2uiDartCoverageReason.nativeDecomposeUnsupported,
        },
      );
    });

    test('drops widgets with required event fields', () {
      final pressable = a2uiEntry(
        name: 'Pressable',
        properties: [
          a2uiProp('label', PropertyType.string),
          a2uiProp('onPressed', PropertyType.event, required: true),
        ],
      );

      final plan = classifyA2uiCatalogDart(catalogWith([pressable]));
      final source = emitA2uiCatalogDart(catalogWith([pressable]));

      expect(source, isNot(contains("name: 'Pressable'")));
      expect(plan.coverage.omittedFields, isEmpty);
      expect(plan.coverage.droppedWidgets, hasLength(1));
      expect(plan.coverage.droppedWidgets.single.widgetName, 'Pressable');
      expect(plan.coverage.droppedWidgets.single.fieldName, 'onPressed');
      expect(
        plan.coverage.droppedWidgets.single.reason,
        A2uiDartCoverageReason.eventProperty,
      );
    });

    test('golden - generated CatalogItem Dart for a representative slice', () {
      final textProp = WireId('p0001');
      final fontSizeProp = WireId('p0002');
      final maxLinesProp = WireId('p0003');
      final catalog = catalogWith([
        a2uiEntry(
          name: 'PriceBadge',
          properties: [
            a2uiProp('label', PropertyType.string, required: true),
            a2uiProp(
              'tone',
              PropertyType.enumValue,
              enumType: 'Brightness',
              literalDefault: 'light',
            ),
          ],
        ),
        a2uiEntry(
          name: 'ChildColumn',
          childrenSlot: ChildrenSlot.list,
          properties: [
            a2uiProp('children', PropertyType.widgetList),
          ],
        ),
        a2uiEntry(
          name: 'Meter',
          properties: [
            a2uiProp('enabled', PropertyType.boolean, literalDefault: true),
            a2uiProp('value', PropertyType.real, literalDefault: 1.5),
          ],
        ),
        a2uiEntry(
          name: 'StyledText',
          properties: [
            a2uiProp(
              'text',
              PropertyType.string,
              wireId: textProp,
              required: true,
              positional: true,
            ),
            a2uiProp('fontSize', PropertyType.real, wireId: fontSizeProp),
            a2uiProp('maxLines', PropertyType.integer, wireId: maxLinesProp),
          ],
          decomposes: [
            DecompositionRecipe(
              structuredRef: const WireIdRef(
                library: 'restage.core',
                wireId: WireId.unallocatedStructured,
              ),
              flatProperties: {WireId('p0501'): fontSizeProp},
              fieldMappings: [
                DecompositionFieldMapping(
                  fieldRef: WireId('p0501'),
                  propertyRef: fontSizeProp,
                  transform: const IdentityTransform(),
                ),
              ],
            ),
          ],
        ),
        a2uiEntry(
          name: 'OptionalStyle',
          properties: [
            a2uiProp('label', PropertyType.string),
            a2uiProp('shape', PropertyType.shapeBorder),
          ],
        ),
        a2uiEntry(
          name: 'RequiredInset',
          properties: [
            a2uiProp('padding', PropertyType.edgeInsets, required: true),
          ],
        ),
      ]);
      final actual = emitA2uiCatalogDart(catalog);

      final file = File('test/a2ui/golden/sample_catalog.dart.txt');
      if (Platform.environment['REGEN_A2UI_DART_GOLDEN'] == '1') {
        file.parent.createSync(recursive: true);
        file.writeAsStringSync('$actual\n');
      }

      expect(
        file.existsSync(),
        isTrue,
        reason:
            'run with REGEN_A2UI_DART_GOLDEN=1 to generate '
            '${file.path}',
      );
      expect(actual, file.readAsStringSync().trimRight());
    });
  });
}
