import 'package:restage_codegen/src/factory_emitter.dart';
import 'package:restage_codegen/src/native_catalog_index.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

/// Locks the structured-ref emission substrate: a `structured`-typed widget
/// property is emittable only when its `structuredRef` resolves to a
/// structured type with a registered runtime decoder. A registered type
/// lowers to that decoder; an unregistered-but-authored structured slot fails
/// the build loudly (never a silent drop / silent default).

WireIdRef _ref(String library, String wireId) =>
    WireIdRef(library: library, wireId: WireId(wireId));

NativeCatalogIndex _index(WidgetEntry widget, StructuredEntry structured) {
  final catalog = Catalog(
    schemaVersion: kSupportedSchemaVersion,
    generatedAt: '1970-01-01T00:00:00Z',
    libraries: {
      WidgetLibrary.material: const LibraryInfo(version: '1.0.0'),
    },
    widgets: [widget],
    structuredTypes: [structured],
  );
  return NativeCatalogIndex(catalog);
}

/// A widget with a single DIRECT `structured` property whose `structuredRef`
/// points at the structured entry [structuredTypeName] (`Size` is registered;
/// anything else is not). No decompose — the property is a direct ctor arg, so
/// the eligibility gate (`_isEmittableProperty`) and the emit path
/// (`_decoderCallFor`) are both exercised against the structured-ref table.
///
/// When [shapeOnly] is true the ref is carried ONLY on the resolved
/// [StructuredShape] `valueShape` — the top-level `structuredRef` is omitted,
/// exercising the recipe-materialized-flat-property recovery path
/// (`_structuredRefOf` reading the shape ref, not the field). When false (the
/// default) BOTH the top-level ref and the shape ref are set.
///
/// When [noRef] is true NEITHER ref is present (no top-level `structuredRef`
/// and no [StructuredShape] `valueShape`) — a malformed structured slot that
/// must fail the build loudly rather than be silently excluded.
({WidgetEntry widget, StructuredEntry structured}) _fixture({
  required String structuredTypeName,
  bool shapeOnly = false,
  bool noRef = false,
}) {
  final structuredShape = StructuredShape(
    propertyType: PropertyType.structured,
    structuredRef: _ref('restage.material', 's0001'),
  );
  final widget = WidgetEntry(
    wireId: WireId('w0001'),
    name: 'Sized',
    library: WidgetLibrary.material,
    category: WidgetCategory.decoration,
    description: '',
    flutterType: 'package:flutter/material.dart#Sized',
    childrenSlot: ChildrenSlot.none,
    fires: const [],
    properties: [
      PropertyEntry(
        wireId: WireId('p0001'),
        name: 'extent',
        type: PropertyType.structured,
        description: '',
        structuredRef:
            (shapeOnly || noRef) ? null : _ref('restage.material', 's0001'),
        valueShape: noRef ? null : structuredShape,
      ),
    ],
  );
  final structured = StructuredEntry(
    wireId: WireId('s0001'),
    name: structuredTypeName,
    library: WidgetLibrary.material,
    description: '',
    sourceType: 'dart:ui#$structuredTypeName',
    fields: const [],
    variants: const [],
  );
  return (widget: widget, structured: structured);
}

void main() {
  group('structured-ref emission substrate', () {
    test(
        'a structured slot whose structuredRef resolves to a registered '
        'decoder (Size) lowers to that decoder', () {
      final f = _fixture(structuredTypeName: 'Size');
      final source = emitFactoryFunction(
        f.widget,
        nativeIndex: _index(f.widget, f.structured),
      );

      expect(source, isNotNull);
      // The registered decoder is emitted against the property slot path.
      expect(
        source,
        contains("RestageDecoders.size(source, <Object>['extent'])"),
      );
    });

    test(
        'an AUTHORED structured slot whose structuredRef has NO registered '
        'decoder FAILS the build loudly (no silent drop / default)', () {
      final f = _fixture(structuredTypeName: 'UnregisteredWidgetExtent');

      expect(
        () => emitFactoryFunction(
          f.widget,
          nativeIndex: _index(f.widget, f.structured),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('no registered decoder'),
          ),
        ),
      );
    });

    test(
        'a structured slot whose ref is carried ONLY on its StructuredShape '
        'valueShape (no top-level structuredRef) still recovers the registered '
        'Size decoder', () {
      // The recipe-materialized-flat-property shape: the ref lives on the
      // resolved `valueShape`, not the top-level field. `_structuredRefOf`
      // must read the shape ref to reach the registered decoder.
      final f = _fixture(structuredTypeName: 'Size', shapeOnly: true);
      final source = emitFactoryFunction(
        f.widget,
        nativeIndex: _index(f.widget, f.structured),
      );

      expect(source, isNotNull);
      expect(
        source,
        contains("RestageDecoders.size(source, <Object>['extent'])"),
      );
    });

    test(
        'a shape-only structured slot whose ref resolves to an UNREGISTERED '
        'decoder FAILS the build loudly (no silent drop / default)', () {
      final f = _fixture(
        structuredTypeName: 'UnregisteredWidgetExtent',
        shapeOnly: true,
      );

      expect(
        () => emitFactoryFunction(
          f.widget,
          nativeIndex: _index(f.widget, f.structured),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('no registered decoder'),
          ),
        ),
      );
    });

    test(
        'a malformed structured slot with NO resolvable ref (no top-level '
        'structuredRef AND no StructuredShape valueShape) FAILS the build '
        'loudly rather than being silently excluded', () {
      final f = _fixture(structuredTypeName: 'Size', noRef: true);

      expect(
        () => emitFactoryFunction(
          f.widget,
          nativeIndex: _index(f.widget, f.structured),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('no structuredRef'),
          ),
        ),
      );
    });
  });
}
