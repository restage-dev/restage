import 'dart:io';

import 'package:restage_codegen/src/a2ui/a2ui_dart_emitter.dart';
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
      expect(source, contains('builder: (context, count) => BoundNumber('));
      expect(source, contains("value: data['opacity'],"));
      expect(source, contains('builder: (context, opacity) => BoundNumber('));
      expect(source, contains("value: data['height'],"));
      expect(source, contains('builder: (context, height) => BoundString('));
      expect(source, contains("value: data['title'],"));
      expect(source, contains('builder: (context, title) => BoundList('));
      expect(source, contains("value: data['tags'],"));
      expect(source, contains('enabled: enabled ?? false,'));
      expect(source, contains('count: (count ?? 0).toInt(),'));
      expect(source, contains('opacity: (opacity ?? 0).toDouble(),'));
      expect(source, contains('height: (height ?? 0).toDouble(),'));
      expect(source, contains("title: title ?? '',"));
      expect(
        source,
        contains('tags: (tags ?? const <Object?>[])'),
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
      expect(source, contains("'maxLines': S.number()"));
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
