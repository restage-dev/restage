import 'dart:io';

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
    defaultSource:
        literalDefault == null ? null : LiteralDefault(literalDefault),
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

      expect(source, contains('return BoundBool('));
      expect(source, contains("value: data['enabled'],"));
      expect(source, contains('builder: (context, enabled) => BoundNumber('));
      expect(source, contains("value: data['count'],"));
      expect(source, contains("'count': S.integer()"));
      expect(source, contains("'opacity': S.number()"));
      expect(source, contains('builder: (context, count) => BoundNumber('));
      expect(source, contains("value: data['opacity'],"));
      expect(source, contains('builder: (context, opacity) => BoundNumber('));
      expect(source, contains("value: data['height'],"));
      expect(source, contains('builder: (context, height) => BoundString('));
      expect(source, contains("value: data['title'],"));
      expect(source, contains('builder: (context, title) => BoundObject('));
      expect(source, contains("value: data['tags'],"));
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

    test('a required nullable scalar keeps presence and nullability distinct',
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
        ('NullableInput', 'value'):
            ScalarNode(A2uiScalarType.string, nullable: true),
      };

      final source = emitA2uiCatalogDart(catalog, richShapes: shapes);
      expect(
        source,
        contains(
          "'value': S.combined(anyOf: [S.string(), S.nil()])",
        ),
      );
      expect(
        source,
        contains(
          "value: data['value'] == null ? null : (value ?? ''),",
        ),
      );
      expect(source, isNot(contains("data.containsKey('value')")));

      final component = emitA2uiCatalog(
        catalog,
        richShapes: shapes,
      ).components.single.dataSchema;
      expect(component['required'], ['component', 'value']);
      final properties = component['properties']! as Map<String, Object?>;
      expect(properties['value'], {
        'anyOf': [
          {'type': 'string'},
          {'type': 'null'},
        ],
      });
    });

    test('nullable leaf defaults preserve raw null and failed normalization',
        () {
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
        ('NullableDefaults', 'label'):
            const ScalarNode(A2uiScalarType.string, nullable: true),
        ('NullableDefaults', 'featured'):
            const ScalarNode(A2uiScalarType.boolean, nullable: true),
        ('NullableDefaults', 'count'):
            const ScalarNode(A2uiScalarType.integer, nullable: true),
        ('NullableDefaults', 'amount'):
            const ScalarNode(A2uiScalarType.number, nullable: true),
        ('NullableDefaults', 'timeout'):
            const ScalarNode(A2uiScalarType.number, nullable: true),
        ('NullableDefaults', 'weight'):
            const ScalarNode(A2uiScalarType.number, nullable: true),
        ('NullableDefaults', 'accent'):
            const ScalarNode(A2uiScalarType.string, nullable: true),
        ('NullableDefaults', 'fit'): EnumNode(
          dartTypeName: 'BoxFit',
          members: const ['fill', 'cover'],
          nullable: true,
        ),
        ('NullableDefaults', 'requiredValue'):
            const ScalarNode(A2uiScalarType.string, nullable: true),
        ('NullableDefaults', 'requiredFeatured'):
            const ScalarNode(A2uiScalarType.boolean, nullable: true),
        ('NullableDefaults', 'requiredAmount'):
            const ScalarNode(A2uiScalarType.number, nullable: true),
        ('NullableDefaults', 'requiredAccent'):
            const ScalarNode(A2uiScalarType.string, nullable: true),
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
          "label:data.containsKey('label')?(data['label']==null?null:"
          "(label??'Included')):'Included',",
        ),
      );
      expect(
        dense,
        contains(
          "featured:data.containsKey('featured')?"
          "(data['featured']==null?null:(featured??true)):true,",
        ),
      );
      expect(
        dense,
        contains(
          "count:data.containsKey('count')?(data['count']==null?null:"
          '(count?.toInt()??(count??7).toInt())):'
          '(count??7).toInt(),',
        ),
      );
      expect(dense, contains("data['amount']==null?null"));
      expect(dense, contains('amount?.toDouble()'));
      expect(dense, contains('(amount??12.5).toDouble()'));
      expect(dense, contains("data['timeout']==null?null"));
      expect(dense, contains('Duration(milliseconds:timeout.toInt())'));
      expect(
        dense,
        contains('Duration(milliseconds:(timeout??250).toInt())'),
      );
      expect(dense, contains("data['weight']==null?null"));
      expect(
        dense,
        contains('_restageA2uiFontWeight(weight,FontWeight.normal)'),
      );
      expect(
        dense,
        contains(
          "accent:data.containsKey('accent')?"
          "(data['accent']==null?null:(_restageA2uiColor(accent)??"
          "_restageA2uiColor('#FF00AA')??constColor(0x00000000))):",
        ),
      );
      expect(
        dense,
        contains(
          "fit:data.containsKey('fit')?(data['fit']==null?null:"
          '(BoxFit.values.asNameMap()[fit]??BoxFit.cover)):BoxFit.cover,',
        ),
      );
      expect(
        dense,
        contains(
          "requiredValue:data['requiredValue']==null?null:"
          "(requiredValue??''),",
        ),
      );
      expect(
        dense,
        isNot(contains("data.containsKey('requiredValue')")),
      );
      expect(
        dense,
        contains(
          "requiredFeatured:data['requiredFeatured']==null?null:"
          '(requiredFeatured??false),',
        ),
      );
      expect(
        dense,
        contains(
          "requiredAmount:data['requiredAmount']==null?null:"
          '(requiredAmount?.toDouble()??'
          '(requiredAmount??0).toDouble()),',
        ),
      );
      expect(
        dense,
        contains(
          "requiredAccent:data['requiredAccent']==null?null:"
          '(_restageA2uiColor(requiredAccent)??'
          'constColor(0x00000000)),',
        ),
      );
      expect(
        dense,
        contains(
          "requiredFit:data['requiredFit']==null?null:"
          '(BoxFit.values.asNameMap()[requiredFit]??'
          'BoxFit.values.first),',
        ),
      );
      expect(
        compact,
        isNot(contains("data.containsKey('requiredFeatured')")),
      );
      expect(
        compact,
        isNot(contains("data.containsKey('requiredAmount')")),
      );
      expect(
        compact,
        isNot(contains("data.containsKey('requiredAccent')")),
      );
      expect(
        compact,
        isNot(contains("data.containsKey('requiredFit')")),
      );
    });

    test(
        'constructor truth wins over annotation seed while native key presence '
        'preserves omission versus null', () {
      final catalog = catalogWith([
        a2uiEntry(
          name: 'ConstructorDefault',
          properties: [
            a2uiProp(
              'label',
              PropertyType.string,
              literalDefault: 'preview-seed',
              constructorNullable: true,
              constructorDefault: const DartConstScalar('constructor-default'),
            ),
          ],
        ),
      ]);
      const shapes = <(String, String), A2uiSchemaNode>{
        ('ConstructorDefault', 'label'):
            ScalarNode(A2uiScalarType.string, nullable: true),
      };

      final dense = emitA2uiCatalogDart(
        catalog,
        richShapes: shapes,
      ).replaceAll(RegExp(r'\s+'), '');

      expect(
        dense,
        contains(
          "label:data.containsKey('label')?"
          "(data['label']==null?null:(label??'constructor-default')):"
          "'constructor-default',",
        ),
      );
      expect(dense, isNot(contains('preview-seed')));
    });

    test('a required nullable child is schema-required without a null assert',
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
        ('NullableChild', 'child'):
            ScalarNode(A2uiScalarType.string, nullable: true),
      };

      final source = emitA2uiCatalogDart(catalog, richShapes: shapes);
      expect(
        source,
        contains("child: _restageA2uiBuildChild(itemContext, data['child']),"),
      );
      expect(
        source,
        isNot(
          contains(
            "child: _restageA2uiBuildChild(itemContext, data['child'])!,",
          ),
        ),
      );

      final component = emitA2uiCatalog(
        catalog,
        richShapes: shapes,
      ).components.single.dataSchema;
      expect(component['required'], ['component', 'child']);
      final properties = component['properties']! as Map<String, Object?>;
      expect(properties['child'], {
        'anyOf': [
          {'type': 'string'},
          {'type': 'null'},
        ],
      });
    });

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
          "child:_restageA2uiRequireChild(itemContext,data['child'],"
          "'RequiredChild.child'),",
        ),
      );
      expect(
        source,
        contains('itemContext.getComponent(childId) == null'),
      );
      expect(
        source,
        contains('child = itemContext.buildChild(childId);'),
      );
      expect(
        source,
        contains('child is FallbackWidget && child.error != null'),
      );
      expect(
        source,
        isNot(contains('if (child == null)')),
      );
      expect(
        source,
        isNot(
          contains(
            "_restageA2uiBuildChild(itemContext, data['child'])!",
          ),
        ),
      );
    });

    test('nullable child slots distinguish missing keys from explicit null',
        () {
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
        ('NullableChild', 'child'):
            ScalarNode(A2uiScalarType.string, nullable: true),
        (
          'NullableChildren',
          'children'
        ): ListNode(element: ScalarNode(A2uiScalarType.string), nullable: true),
      };

      final source = emitA2uiCatalogDart(catalog, richShapes: shapes);
      final compact = source.replaceAll(RegExp(r'\s+'), ' ');

      expect(
        compact,
        contains(
          "child: data.containsKey('child') ? "
          "_restageA2uiBuildChild(itemContext, data['child']) : null,",
        ),
      );
      expect(
        compact,
        contains("children: data.containsKey('children') ?"),
      );
      expect(
        compact,
        contains(
          "data['children'] == null ? null : "
          "_restageA2uiBuildChildren(itemContext, data['children'])",
        ),
      );
      expect(
        compact,
        contains(
          "_restageA2uiBuildChildren(itemContext, data['children'])) : null,",
        ),
      );
    });

    test('analyzer-fed scalar lists stay reactive and construct type-safely',
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
        ('ScalarLists', 'labels'):
            ListNode(element: ScalarNode(A2uiScalarType.string)),
        ('ScalarLists', 'counts'):
            ListNode(element: ScalarNode(A2uiScalarType.integer)),
        ('ScalarLists', 'weights'):
            ListNode(element: ScalarNode(A2uiScalarType.number)),
        ('ScalarLists', 'measurements'): ListNode(
          element: ScalarNode(
            A2uiScalarType.number,
            preserveNumericRuntimeType: true,
          ),
        ),
        ('ScalarLists', 'flags'):
            ListNode(element: ScalarNode(A2uiScalarType.boolean)),
        ('ScalarLists', 'maybeCounts'): ListNode(
          element: ScalarNode(A2uiScalarType.integer),
          nullable: true,
        ),
        ('ScalarLists', 'defaultCounts'):
            ListNode(element: ScalarNode(A2uiScalarType.integer)),
        ('ScalarLists', 'fallbackLabels'):
            ListNode(element: ScalarNode(A2uiScalarType.string)),
        ('ScalarLists', 'fallbackFlags'):
            ListNode(element: ScalarNode(A2uiScalarType.boolean)),
        ('ScalarLists', 'fallbackCounts'):
            ListNode(element: ScalarNode(A2uiScalarType.integer)),
        ('ScalarLists', 'fallbackWeights'):
            ListNode(element: ScalarNode(A2uiScalarType.number)),
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

      expect('BoundObject('.allMatches(source), hasLength(13));
      expect(source, contains("value: data['labels']"));
      expect(source, contains("value: data['counts']"));
      expect(source, contains("value: data['weights']"));
      expect(source, contains("value: data['measurements']"));
      expect(source, contains("value: data['flags']"));
      expect(source, isNot(contains("value: data['defaultCounts']")));
      expect(source, isNot(contains('defaultCounts:')));
      expect(source, contains('.whereType<String>()'));
      expect(source, contains('.whereType<bool>()'));
      expect(compactSource, contains('value is num ? value.toInt() : null'));
      expect(compactSource, contains('value is num ? value.toDouble() : null'));
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
          "data.containsKey('maybeCounts')?"
          "(data['maybeCounts']==null?null:"
          '(maybeCountsisList?maybeCounts.cast<Object?>():null)):null',
        ),
      );

      expect('S.combined(oneOf:'.allMatches(source), hasLength(13));
      expect(source, contains("'path': S.string()"));
      expect(source, contains("'call': S.string("));
      expect(source, contains('additionalProperties: true'));
      expect(
        compactSource,
        contains(
          "'maybeCounts': S.combined(oneOf: [ S.combined(anyOf: "
          '[S.list(items: S.integer()), S.nil()])',
        ),
      );

      final stamp = emitA2uiCatalog(catalog, richShapes: richShapes).toJson();
      final a2uiCatalog = stamp['a2uiCatalog']! as Map<String, Object?>;
      final components = a2uiCatalog['components']! as Map<String, Object?>;
      final scalarLists = components['ScalarLists']! as Map<String, Object?>;
      final properties = scalarLists['properties']! as Map<String, Object?>;

      final labels = properties['labels']! as Map<String, Object?>;
      final labelAlternatives = labels['oneOf']! as List<Object?>;
      expect(labelAlternatives, hasLength(3));
      expect(labelAlternatives[0], {
        'type': 'array',
        'items': {'type': 'string'},
      });
      expect(labelAlternatives[1], {
        'type': 'object',
        'properties': {
          'path': {'type': 'string'},
        },
        'required': ['path'],
      });
      expect(labelAlternatives[2], {
        'type': 'object',
        'properties': {
          'call': {'type': 'string'},
          'args': {'type': 'object', 'additionalProperties': true},
        },
        'required': ['call'],
      });

      final maybeCounts = properties['maybeCounts']! as Map<String, Object?>;
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
    });

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
          "data.containsKey('values')?(data['values']==null?null:",
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
          "data['requiredValues']==null?null:"
          '(requiredValuesisList?requiredValues.cast<Object?>():null)',
        ),
      );
      expect(
        compact,
        isNot(contains("data.containsKey('requiredValues')")),
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
            ('InvalidDefault', 'counts'):
                ListNode(element: ScalarNode(A2uiScalarType.integer)),
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

    test('catalog-fed booleanList remains outside the A2UI leaf vocabulary',
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
    });

    test('emits a color field as a string schema decoded through the helper',
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
      // hex decoder, falling back to the catalog default (or transparent).
      expect(source, contains("'tint': S.string()"));
      expect(source, contains('return BoundString('));
      expect(
        source,
        contains('tint: _restageA2uiColor(tint) ?? const Color(0x00000000),'),
      );
      // The defaulted color decodes the bound value, then the catalog default,
      // then transparent (the emitter wraps the long fallback chain).
      expect(source, contains('accent: _restageA2uiColor(accent) ??'));
      expect(source, contains("_restageA2uiColor('#FF00AA') ??"));
    });

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

      expect(source, contains("'fit': S.string()"));
      expect(source, contains('return BoundString('));
      expect(source, contains("value: data['fit'],"));
      expect(
        source,
        contains('fit: BoxFit.values.asNameMap()[fit] ?? BoxFit.cover,'),
      );
      expect(source, isNot(contains('.values.byName(')));
    });

    test('a required enum without a default fails closed to the first member',
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

      // A non-nullable required enum param must receive a valid member, never
      // null — fail closed to the first declared value, never `.byName`
      // (which throws).
      expect(
        source,
        contains('fit: BoxFit.values.asNameMap()[fit] ?? BoxFit.values.first,'),
      );
      expect(source, isNot(contains('.values.byName(')));
    });

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

      expect(source, contains("'child': S.string()"));
      expect(source, contains("'children': S.list(items: S.string())"));
      expect(source, contains('child: _restageA2uiBuildChild('));
      expect(source, contains("data['child']"));
      expect(source, contains('children: _restageA2uiBuildChildren('));
      expect(source, contains("data['children']"));
      expect(source, isNot(contains("value: data['child']")));
      expect(source, isNot(contains("value: data['children']")));
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
      expect(source, contains("'text': S.string()"));
      expect(source, contains("'maxLines': S.integer()"));
      expect(source, contains("value: data['text'],"));
      expect(source, contains("value: data['maxLines'],"));
      expect(source, isNot(contains("'fontSize':")));
      expect(source, isNot(contains("'fontPackage':")));
      expect(source, isNot(contains("value: data['fontSize']")));
      expect(source, isNot(contains("value: data['fontPackage']")));
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
        reason: 'run with REGEN_A2UI_DART_GOLDEN=1 to generate '
            '${file.path}',
      );
      expect(actual, file.readAsStringSync().trimRight());
    });
  });
}
