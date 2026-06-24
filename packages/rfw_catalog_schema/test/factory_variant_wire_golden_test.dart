import 'dart:io';

import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

/// Per-variant **byte-goldens** for [FactoryVariant] — the structured-type
/// factory variant (one wire ID per way a value can be authored: constructor,
/// static method, static getter, static const field).
///
/// Each fixture embeds one variant in the smallest valid catalog and asserts
/// two things through the production codec:
///
///  1. **Byte-golden:** `encodeCatalog(fixture)` equals an exact committed
///     golden file (`test/fixtures/factory_variant/<name>.json`) captured from
///     today's encoder. This pins every byte — the `sourceKind` discriminator
///     string, every field key, key *order*, and the present-only emission of
///     the optional fields — for that variant, independent of whether any
///     built-in catalog happens to exercise it.
///  2. **Round-trip:** `encodeCatalog(decodeCatalog(encodeCatalog(fixture)))`
///     equals `encodeCatalog(fixture)`. Catches an asymmetric decode that drops
///     a field.
///
/// Why a full byte-golden and not just a discriminator substring: a future
/// per-subclass encode rewrite (the sealed-types swap) can move the wire in
/// ways self-consistency and a discriminator-substring both miss — a field-key
/// rename, or a key *reorder* (decode reads keys order-independently, so both
/// sides still agree). The frozen golden file is the only thing that makes "the
/// wire didn't move" falsifiable for shapes absent from the committed catalogs
/// (e.g. a deprecated variant). The goldens live in a separate, frozen
/// directory precisely so a representation change to the builders below cannot
/// silently relax them.
///
/// The fixtures span the full shape space the producers emit (verified by a
/// census of the three committed catalogs + the variant enumerator + the
/// reflector): constructor with/without a named constructor, one-to-one and
/// splatting arg mappings, callable parameters present/absent, a description
/// present/absent, and a deprecated variant (producible from an upstream
/// `@Deprecated` or a `deprecate` event even though no committed catalog
/// carries one today).
///
/// Regenerate goldens (only when the wire is *intended* to change) with:
///   `REGEN_GOLDENS=1 dart test test/factory_variant_wire_golden_test.dart`
void main() {
  group('constructor variant byte-goldens', () {
    test('unnamed canonical constructor (no name, no arg mappings)', () {
      _expectVariantWireGolden(
        _variantCatalog(
          ConstructorVariant(
            wireId: WireId('v0001'),
            description: 'Default constructor.',
          ),
        ),
        'ctor_unnamed_minimal',
      );
    });

    test('named constructor with one-to-one arg mappings', () {
      _expectVariantWireGolden(
        _variantCatalog(
          ConstructorVariant(
            wireId: WireId('v0001'),
            namedConstructor: 'only',
            argMappings: {
              'left': ArgMapping(targetFields: [WireId('p0501')]),
              'top': ArgMapping(targetFields: [WireId('p0502')]),
            },
            description: 'Constructs from individual edges.',
          ),
        ),
        'ctor_named_argmappings',
      );
    });

    test(
        'named constructor with a splatting arg mapping (one arg, many '
        'target fields)', () {
      _expectVariantWireGolden(
        _variantCatalog(
          ConstructorVariant(
            wireId: WireId('v0001'),
            namedConstructor: 'circular',
            argMappings: {
              'radius': ArgMapping(
                targetFields: [
                  WireId('p0501'),
                  WireId('p0502'),
                  WireId('p0503'),
                  WireId('p0504'),
                ],
              ),
            },
            description: 'Splats one radius onto all four corners.',
          ),
        ),
        'ctor_named_splat_argmappings',
      );
    });

    test('constructor carrying callable parameter metadata', () {
      _expectVariantWireGolden(
        _variantCatalog(
          ConstructorVariant(
            wireId: WireId('v0001'),
            parameters: [
              FactoryParameter(
                wireId: WireId('a0001'),
                name: 'value',
                kind: FactoryParameterKind.named,
                required: false,
                nullable: false,
                defaultPolicy: FactoryParameterDefaultPolicy.useFlutterDefault,
                valueShape:
                    const ScalarShape(propertyType: PropertyType.boolean),
              ),
            ],
            description: 'Constructor with one named parameter.',
          ),
        ),
        'ctor_with_parameters',
      );
    });

    test('deprecated constructor (source + catalog deprecation)', () {
      _expectVariantWireGolden(
        _variantCatalog(
          ConstructorVariant(
            wireId: WireId('v0001'),
            description: 'A deprecated constructor.',
            deprecated: const DeprecationInfo(
              source: SourceDeprecationInfo(
                message: 'Use the replacement constructor.',
                since: '3.0.0',
              ),
              catalog: CatalogDeprecationInfo(
                reason: 'Superseded by a clearer factory.',
                at: '2026-05-27T00:00:00Z',
              ),
            ),
          ),
        ),
        'ctor_deprecated',
      );
    });
  });

  group('staticMethod variant byte-goldens', () {
    test('static method with arg mappings + callable parameters', () {
      _expectVariantWireGolden(
        _variantCatalog(
          StaticMethodVariant(
            wireId: WireId('v0001'),
            staticAccessor: 'styleFrom',
            argMappings: {
              'backgroundColor': ArgMapping(targetFields: [WireId('p0501')]),
            },
            parameters: [
              FactoryParameter(
                wireId: WireId('a0001'),
                name: 'backgroundColor',
                kind: FactoryParameterKind.named,
                required: false,
                nullable: true,
                defaultPolicy: FactoryParameterDefaultPolicy.omitWhenNull,
                valueShape: const ScalarShape(propertyType: PropertyType.color),
              ),
            ],
            description: 'Builds a style from individual properties.',
          ),
        ),
        'static_method_argmappings',
      );
    });

    test('static method, no arg mappings, no parameters', () {
      _expectVariantWireGolden(
        _variantCatalog(
          StaticMethodVariant(
            wireId: WireId('v0001'),
            staticAccessor: 'lerp',
            description: 'Linearly interpolates between two values.',
          ),
        ),
        'static_method_minimal',
      );
    });
  });

  group('staticGetter variant byte-goldens', () {
    test('static getter (accessor only, no description)', () {
      _expectVariantWireGolden(
        _variantCatalog(
          StaticGetterVariant(
            wireId: WireId('v0001'),
            staticAccessor: 'instance',
          ),
        ),
        'static_getter',
      );
    });
  });

  group('constValue variant byte-goldens', () {
    test('static const field (accessor + description)', () {
      _expectVariantWireGolden(
        _variantCatalog(
          ConstValueVariant(
            wireId: WireId('v0001'),
            staticAccessor: 'zero',
            description: 'The zero value.',
          ),
        ),
        'const_value',
      );
    });
  });
}

// --- Byte-golden oracle -----------------------------------------------------

/// Assert that `encodeCatalog(catalog)` matches the frozen golden
/// `test/fixtures/factory_variant/<name>.json` byte-for-byte, and that the
/// encoding round-trips. Set `REGEN_GOLDENS=1` to (re)write the golden from the
/// current encoder output instead of asserting against it.
void _expectVariantWireGolden(Catalog catalog, String name) {
  final encoded = encodeCatalog(catalog);
  final file = File('test/fixtures/factory_variant/$name.json');
  if (Platform.environment['REGEN_GOLDENS'] == '1') {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(encoded);
  }
  expect(
    encoded,
    file.readAsStringSync(),
    reason: 'wire byte-golden "$name" — a difference means the wire moved; '
        'regenerate with REGEN_GOLDENS=1 only if the change is intended.',
  );
  expect(
    encodeCatalog(decodeCatalog(encoded)),
    encoded,
    reason: 'round-trip stability for "$name"',
  );
}

// --- Minimal scaffold -------------------------------------------------------

const _generatedAt = '2026-05-27T00:00:00Z';

/// A structured type whose single [variant] is the subject under test.
Catalog _variantCatalog(FactoryVariant variant) => Catalog(
      schemaVersion: kSupportedSchemaVersion,
      generatedAt: _generatedAt,
      libraries: {
        WidgetLibrary.core: const LibraryInfo(version: '0.1.0'),
      },
      widgets: const [],
      structuredTypes: [
        StructuredEntry(
          wireId: WireId('s0001'),
          name: 'Probe',
          library: WidgetLibrary.core,
          description: 'Probe structured type.',
          sourceType: 'package:flutter/painting.dart#Probe',
          fields: const [],
          variants: [variant],
        ),
      ],
    );
