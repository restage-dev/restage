import 'dart:convert';
import 'dart:io';

import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

/// The propertyType-compat invariant: a value shape's [PropertyType] must be
/// consistent with its subtype. The rule (signed off as BROAD-scalar):
///
/// - `EnumShape`        → only `enumValue`
/// - `StructuredShape`  → only `structured`
/// - `UnionShape`       → `border` / `gradient` / `shapeBorder`
/// - `ListShape`        → the list-category types (widgetList, stringList,
///                        booleanList, boxShadowList, shadowList,
///                        fontFeatureList, fontVariationList)
/// - `ScalarShape`      → anything EXCEPT `enumValue` / `structured`
///
/// `PropertyType.unknown` (the additive forward-compat sentinel) is exempt on
/// every subtype — an unrecognized wire propertyType name decodes to `unknown`
/// and must stay opaque rather than be rejected.
///
/// The codec enforces it at decode (`_valueShapeFromJson`, the path exercised
/// here) and on the encode / `requireNativeCatalog` paths
/// (`_validateValueShape`); the subtype constructors carry a debug-mode mirror
/// assert.
void main() {
  // A known-valid minimal single-property catalog skeleton; tests swap its
  // `widgets[0].properties[0].valueShape` to probe the compat invariant.
  Map<String, dynamic> skeleton() => jsonDecode(
        File('test/fixtures/native_decompose/shape_scalar.json')
            .readAsStringSync(),
      ) as Map<String, dynamic>;

  String catalogWithValueShape(Map<String, dynamic> valueShape) {
    final json = skeleton();
    ((json['widgets'] as List).first as Map<String, dynamic>)['properties'] = [
      {
        'wireId': 'p0001',
        'name': 'prop',
        'type': 'string',
        'description': 'Probe property.',
        'valueShape': valueShape,
      },
    ];
    return jsonEncode(json);
  }

  const enumRefJson = {
    'libraryUri': 'package:flutter/painting.dart',
    'symbolName': 'BoxShape',
  };
  const structuredRefJson = {'library': 'restage.core', 'wireId': 's0001'};
  const unionRefJson = {'library': 'restage.core', 'wireId': 'u0001'};

  group('propertyType-compat — codec decode rejects incompatible pairings', () {
    final incompatible = <String, Map<String, dynamic>>{
      'scalar carrying enumValue': {
        'kind': 'scalar',
        'propertyType': 'enumValue',
      },
      'scalar carrying structured': {
        'kind': 'scalar',
        'propertyType': 'structured',
      },
      'enumValue carrying color': {
        'kind': 'enumValue',
        'propertyType': 'color',
        'enumRef': enumRefJson,
      },
      'structured carrying color': {
        'kind': 'structured',
        'propertyType': 'color',
        'structuredRef': structuredRefJson,
      },
      'union carrying color': {
        'kind': 'union',
        'propertyType': 'color',
        'unionRef': unionRefJson,
      },
      'union carrying enumValue': {
        'kind': 'union',
        'propertyType': 'enumValue',
        'unionRef': unionRefJson,
      },
      'list carrying a scalar propertyType (color)': {
        'kind': 'list',
        'propertyType': 'color',
        'itemShape': {'kind': 'scalar', 'propertyType': 'color'},
      },
      'list carrying integer': {
        'kind': 'list',
        'propertyType': 'integer',
        'itemShape': {'kind': 'scalar', 'propertyType': 'integer'},
      },
    };

    for (final MapEntry(key: label, value: shape) in incompatible.entries) {
      test('decode rejects $label', () {
        expect(
          () => decodeCatalog(catalogWithValueShape(shape)),
          throwsA(isA<CatalogSchemaException>()),
        );
      });
    }

    test('decode rejects a nested itemShape with an incompatible pairing', () {
      // The outer list type is valid; the recursive item (scalar+enumValue) is
      // not — the compat check must descend into itemShape.
      expect(
        () => decodeCatalog(
          catalogWithValueShape({
            'kind': 'list',
            'propertyType': 'stringList',
            'itemShape': {'kind': 'scalar', 'propertyType': 'enumValue'},
          }),
        ),
        throwsA(isA<CatalogSchemaException>()),
      );
    });
  });

  group('wireCodec placement — codec decode rejects categorical', () {
    // wireCodec is meaningful only on scalar/union/list shapes. Decode rejects
    // it on enum/structured pre-construction (the same self-contained per-shape
    // class as propertyType-compat), consistent with the sibling malformed-wire
    // errors — not only at the encode guard.
    test('decode rejects an enumValue shape carrying a wireCodec', () {
      expect(
        () => decodeCatalog(
          catalogWithValueShape({
            'kind': 'enumValue',
            'propertyType': 'enumValue',
            'enumRef': enumRefJson,
            'wireCodec': 'rfwGradient',
          }),
        ),
        throwsA(
          isA<CatalogSchemaException>().having(
            (error) => error.message,
            'message',
            contains('wireCodec'),
          ),
        ),
      );
    });

    test('decode rejects a structured shape carrying a wireCodec', () {
      expect(
        () => decodeCatalog(
          catalogWithValueShape({
            'kind': 'structured',
            'propertyType': 'structured',
            'structuredRef': structuredRefJson,
            'wireCodec': 'rfwBorder',
          }),
        ),
        throwsA(
          isA<CatalogSchemaException>().having(
            (error) => error.message,
            'message',
            contains('wireCodec'),
          ),
        ),
      );
    });

    test('decode rejects a nested enum itemShape carrying a wireCodec', () {
      // The recursive descent must catch a wireCodec on a categorical item
      // shape too.
      expect(
        () => decodeCatalog(
          catalogWithValueShape({
            'kind': 'list',
            'propertyType': 'stringList',
            'itemShape': {
              'kind': 'enumValue',
              'propertyType': 'enumValue',
              'enumRef': enumRefJson,
              'wireCodec': 'rfwGradient',
            },
          }),
        ),
        throwsA(isA<CatalogSchemaException>()),
      );
    });

    test('decode still ACCEPTS a wireCodec on union/list/scalar', () {
      expect(
        () => decodeCatalog(
          catalogWithValueShape({
            'kind': 'union',
            'propertyType': 'gradient',
            'unionRef': unionRefJson,
            'wireCodec': 'rfwGradient',
          }),
        ),
        returnsNormally,
      );
    });
  });

  group('propertyType-compat — codec decode ACCEPTS all real shapes', () {
    final compatible = <String, Map<String, dynamic>>{
      'scalar+color': {'kind': 'scalar', 'propertyType': 'color'},
      // BROAD-scalar: a value reducible to one wire blob may be a scalar even
      // when its semantic type is union/list-category.
      'scalar+gradient': {'kind': 'scalar', 'propertyType': 'gradient'},
      'scalar+shapeBorder': {'kind': 'scalar', 'propertyType': 'shapeBorder'},
      'scalar+fontFeatureList': {
        'kind': 'scalar',
        'propertyType': 'fontFeatureList',
      },
      'enumValue+enumValue': {
        'kind': 'enumValue',
        'propertyType': 'enumValue',
        'enumRef': enumRefJson,
      },
      'structured+structured': {
        'kind': 'structured',
        'propertyType': 'structured',
        'structuredRef': structuredRefJson,
      },
      'union+gradient': {
        'kind': 'union',
        'propertyType': 'gradient',
        'unionRef': unionRefJson,
      },
      'union+border': {
        'kind': 'union',
        'propertyType': 'border',
        'unionRef': unionRefJson,
      },
      'union+shapeBorder': {
        'kind': 'union',
        'propertyType': 'shapeBorder',
        'unionRef': unionRefJson,
      },
      'list+stringList': {
        'kind': 'list',
        'propertyType': 'stringList',
        'itemShape': {'kind': 'scalar', 'propertyType': 'string'},
      },
      'list+booleanList': {
        'kind': 'list',
        'propertyType': 'booleanList',
        'itemShape': {'kind': 'scalar', 'propertyType': 'boolean'},
      },
    };

    for (final MapEntry(key: label, value: shape) in compatible.entries) {
      test('decode accepts $label', () {
        expect(
          () => decodeCatalog(catalogWithValueShape(shape)),
          returnsNormally,
        );
      });
    }

    test('an unrecognized propertyType (→ unknown) is exempt on every subtype',
        () {
      // Forward-compat: a future propertyType name decodes to `unknown` and
      // must stay opaque rather than be rejected by the compat check.
      for (final kind in [
        'scalar',
        'enumValue',
        'structured',
        'union',
        'list',
      ]) {
        final shape = <String, dynamic>{
          'kind': kind,
          'propertyType': 'someFuturePropertyTypeName',
          if (kind == 'enumValue') 'enumRef': enumRefJson,
          if (kind == 'structured') 'structuredRef': structuredRefJson,
          if (kind == 'union') 'unionRef': unionRefJson,
          if (kind == 'list')
            'itemShape': {'kind': 'scalar', 'propertyType': 'string'},
        };
        expect(
          () => decodeCatalog(catalogWithValueShape(shape)),
          returnsNormally,
          reason: '$kind + unknown propertyType must decode (forward-compat)',
        );
      }
    });
  });

  group('propertyType-compat — construction asserts (debug mirror)', () {
    const someEnumRef = DartTypeRef(
      libraryUri: 'package:flutter/painting.dart',
      symbolName: 'BoxShape',
    );
    final someStructuredRef =
        WireIdRef(library: 'restage.core', wireId: WireId('s0001'));
    final someUnionRef =
        WireIdRef(library: 'restage.core', wireId: WireId('u0001'));

    test('reject incompatible pairings at construction', () {
      expect(
        () => ScalarShape(propertyType: PropertyType.enumValue),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => ScalarShape(propertyType: PropertyType.structured),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => EnumShape(propertyType: PropertyType.color, enumRef: someEnumRef),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => StructuredShape(
          propertyType: PropertyType.color,
          structuredRef: someStructuredRef,
        ),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => UnionShape(
          propertyType: PropertyType.color,
          unionRef: someUnionRef,
        ),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => ListShape(
          propertyType: PropertyType.color,
          itemShape: const ScalarShape(propertyType: PropertyType.color),
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('accept compatible pairings at construction', () {
      expect(
        () => const ScalarShape(propertyType: PropertyType.gradient),
        returnsNormally,
      );
      expect(
        () => UnionShape(
          propertyType: PropertyType.shapeBorder,
          unionRef: someUnionRef,
        ),
        returnsNormally,
      );
      expect(
        () => const ListShape(
          propertyType: PropertyType.boxShadowList,
          itemShape: ScalarShape(propertyType: PropertyType.color),
        ),
        returnsNormally,
      );
      expect(
        () => const ListShape(
          propertyType: PropertyType.booleanList,
          itemShape: ScalarShape(propertyType: PropertyType.boolean),
        ),
        returnsNormally,
      );
    });
  });

  group('catalogValueShapeKindName', () {
    test('returns the exact wire discriminator string per subtype', () {
      final structuredRef =
          WireIdRef(library: 'restage.core', wireId: WireId('s0001'));
      final unionRef =
          WireIdRef(library: 'restage.core', wireId: WireId('u0001'));
      expect(
        catalogValueShapeKindName(
          const ScalarShape(propertyType: PropertyType.string),
        ),
        'scalar',
      );
      expect(
        catalogValueShapeKindName(
          const EnumShape(
            propertyType: PropertyType.enumValue,
            enumRef: DartTypeRef(libraryUri: 'a', symbolName: 'A'),
          ),
        ),
        'enumValue',
      );
      expect(
        catalogValueShapeKindName(
          StructuredShape(
            propertyType: PropertyType.structured,
            structuredRef: structuredRef,
          ),
        ),
        'structured',
      );
      expect(
        catalogValueShapeKindName(
          UnionShape(propertyType: PropertyType.gradient, unionRef: unionRef),
        ),
        'union',
      );
      expect(
        catalogValueShapeKindName(
          const ListShape(
            propertyType: PropertyType.stringList,
            itemShape: ScalarShape(propertyType: PropertyType.string),
          ),
        ),
        'list',
      );
    });
  });
}
