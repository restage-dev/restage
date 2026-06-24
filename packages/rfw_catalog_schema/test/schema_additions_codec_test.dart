import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

void main() {
  group('schema additions round-trip through the codec', () {
    test('catalog carrying structuredTypes / unions / designTokens', () {
      final input = Catalog(
        schemaVersion: kSupportedSchemaVersion,
        generatedAt: '2026-05-11T12:00:00Z',
        flutterVersion: '3.27.0',
        libraries: {
          WidgetLibrary.core: const LibraryInfo(version: '0.1.0'),
        },
        widgets: const [],
        structuredTypes: [
          StructuredEntry(
            wireId: WireId('s0001'),
            name: 'LinearGradient',
            library: WidgetLibrary.core,
            description: 'A 2D linear gradient.',
            sourceType: 'package:flutter/painting.dart#LinearGradient',
            fields: [
              StructuredField(
                wireId: WireId('p0500'),
                name: 'colors',
                type: PropertyType.color,
                description: 'Gradient color stops.',
                required: true,
                category: PropertyCategory.style,
                priority: PropertyPriority.primary,
              ),
              StructuredField(
                wireId: WireId('p0501'),
                name: 'begin',
                type: PropertyType.alignment,
                description: 'Gradient start alignment.',
                defaultSource: const LiteralDefault({'x': -1.0, 'y': 0.0}),
              ),
            ],
            variants: [
              ConstructorVariant(
                wireId: WireId('v0001'),
                argMappings: {
                  'colors': ArgMapping(targetFields: [WireId('p0500')]),
                  'begin': ArgMapping(targetFields: [WireId('p0501')]),
                },
                description: 'Canonical constructor.',
              ),
            ],
            stability: Stability.stable,
          ),
        ],
        unions: [
          UnionEntry(
            wireId: WireId('u0001'),
            name: 'Gradient',
            library: WidgetLibrary.core,
            description: 'An abstract gradient.',
            sourceType: 'package:flutter/painting.dart#Gradient',
            memberSourceTypes: const [
              'package:flutter/painting.dart#LinearGradient',
            ],
            discriminator: DiscriminatorSpec(
              field: '_s',
              values: [
                WireIdRef(
                  library: 'restage.core',
                  wireId: WireId('s0001'),
                ),
              ],
            ),
            members: [
              WireIdRef(library: 'restage.core', wireId: WireId('s0001')),
            ],
            stability: Stability.stable,
          ),
        ],
        designTokens: [
          DesignTokenEntry(
            wireId: WireId('t0001'),
            name: 'background',
            library: WidgetLibrary.core,
            type: DesignTokenType.color,
            description: 'Default background fill.',
            resolver: const ThemeBindingPath.path('colorScheme.background'),
            literalFallback: 0xFFFFFFFF,
            stability: Stability.stable,
          ),
        ],
        compatRules: [
          CompatRule(
            fromVersion: '0.1.0',
            toVersion: '0.2.0',
            kind: CompatKind.addition,
            affectedRef: WireIdRef(
              library: 'restage.core',
              wireId: WireId('w0042'),
            ),
          ),
        ],
      );

      final encoded = encodeCatalog(input);
      final decoded = decodeCatalog(encoded);

      expect(decoded.flutterVersion, '3.27.0');
      expect(decoded.structuredTypes, hasLength(1));
      final structured = decoded.structuredTypes.first;
      expect(structured.wireId, WireId('s0001'));
      expect(structured.fields.map((f) => f.name), ['colors', 'begin']);
      expect(structured.fields[1].defaultSource, isA<LiteralDefault>());
      expect(structured.variants, hasLength(1));
      expect(
        (structured.variants.first as ConstructorVariant)
            .argMappings['colors']
            ?.targetFields,
        [WireId('p0500')],
      );

      expect(decoded.unions, hasLength(1));
      expect(decoded.unions.first.discriminator.field, '_s');

      expect(decoded.designTokens, hasLength(1));
      final token = decoded.designTokens.first;
      expect(token.type, DesignTokenType.color);
      expect(token.resolver?.path, 'colorScheme.background');
      expect(token.literalFallback, 0xFFFFFFFF);

      expect(decoded.compatRules, hasLength(1));
      expect(decoded.compatRules!.first.kind, CompatKind.addition);
    });

    test('union-typed structured field round-trips its unionRef', () {
      final input = Catalog(
        schemaVersion: kSupportedSchemaVersion,
        generatedAt: '2026-05-11T12:00:00Z',
        libraries: {
          WidgetLibrary.core: const LibraryInfo(version: '0.1.0'),
        },
        widgets: const [],
        structuredTypes: [
          StructuredEntry(
            wireId: WireId('s0001'),
            name: 'ShapeDecoration',
            library: WidgetLibrary.core,
            description: 'A shape decoration.',
            sourceType: 'package:flutter/painting.dart#ShapeDecoration',
            fields: [
              // A `structured`-typed field with no structuredRef but a
              // unionRef: the field resolves to a discriminated union of
              // structured entries rather than a single concrete one.
              StructuredField(
                wireId: WireId('p0500'),
                name: 'shape',
                type: PropertyType.structured,
                description: 'The decoration shape border.',
                unionRef: WireIdRef(
                  library: 'restage.core',
                  wireId: WireId('u0007'),
                ),
              ),
            ],
            variants: const [],
          ),
        ],
      );

      // The decode must not reject a structured field whose only
      // reference is a unionRef, and the unionRef must survive the
      // round-trip intact.
      final decoded = decodeCatalog(encodeCatalog(input));
      final field = decoded.structuredTypes.single.fields.single;
      expect(field.type, PropertyType.structured);
      expect(field.structuredRef, isNull);
      expect(field.unionRef, isNotNull);
      expect(field.unionRef!.library, 'restage.core');
      expect(field.unionRef!.wireId, WireId('u0007'));
    });

    test('structured field rejects carrying both structuredRef and unionRef',
        () {
      final input = Catalog(
        schemaVersion: kSupportedSchemaVersion,
        generatedAt: '2026-05-11T12:00:00Z',
        libraries: {
          WidgetLibrary.core: const LibraryInfo(version: '0.1.0'),
        },
        widgets: const [],
        structuredTypes: [
          StructuredEntry(
            wireId: WireId('s0001'),
            name: 'ShapeDecoration',
            library: WidgetLibrary.core,
            description: 'A shape decoration.',
            sourceType: 'package:flutter/painting.dart#ShapeDecoration',
            fields: [
              StructuredField(
                wireId: WireId('p0500'),
                name: 'shape',
                type: PropertyType.structured,
                description: 'The decoration shape border.',
                structuredRef: WireIdRef(
                  library: 'restage.core',
                  wireId: WireId('s0002'),
                ),
                unionRef: WireIdRef(
                  library: 'restage.core',
                  wireId: WireId('u0007'),
                ),
              ),
            ],
            variants: const [],
          ),
        ],
      );

      expect(
        () => encodeCatalog(input),
        throwsA(isA<CatalogSchemaException>()),
      );
    });

    test('empty optional collections are omitted from the encoded JSON', () {
      final catalog = Catalog(
        schemaVersion: kSupportedSchemaVersion,
        generatedAt: '2026-05-11T12:00:00Z',
        libraries: {
          WidgetLibrary.core: const LibraryInfo(version: '0.1.0'),
        },
        widgets: const [],
      );

      final encoded = encodeCatalog(catalog);
      expect(encoded.contains('structuredTypes'), isFalse);
      expect(encoded.contains('unions'), isFalse);
      expect(encoded.contains('designTokens'), isFalse);
      expect(encoded.contains('compatRules'), isFalse);
      expect(encoded.contains('flutterVersion'), isFalse);
    });

    test('all DefaultValueSource shapes round-trip through StructuredField',
        () {
      final input = Catalog(
        schemaVersion: kSupportedSchemaVersion,
        generatedAt: '2026-05-11T12:00:00Z',
        libraries: {
          WidgetLibrary.core: const LibraryInfo(version: '0.1.0'),
        },
        widgets: const [],
        structuredTypes: [
          StructuredEntry(
            wireId: WireId('s0042'),
            name: 'AcmeShape',
            library: WidgetLibrary.core,
            description: 'Test.',
            sourceType: 'package:test/test.dart#AcmeShape',
            fields: [
              StructuredField(
                wireId: WireId('p0700'),
                name: 'literalField',
                type: PropertyType.real,
                description: 'Literal default.',
                defaultSource: const LiteralDefault(12.5),
              ),
              StructuredField(
                wireId: WireId('p0701'),
                name: 'tokenField',
                type: PropertyType.color,
                description: 'Token default.',
                defaultSource: TokenRefDefault(
                  WireIdRef(
                    library: 'restage.core',
                    wireId: WireId('t0005'),
                  ),
                ),
              ),
              StructuredField(
                wireId: WireId('p0702'),
                name: 'themeField',
                type: PropertyType.color,
                description: 'Theme binding default.',
                defaultSource: const ThemeBindingDefault(
                  ThemeBindingPath.path('colorScheme.surface'),
                ),
              ),
              StructuredField(
                wireId: WireId('p0703'),
                name: 'flutterDelegated',
                type: PropertyType.alignment,
                description: 'Explicit Flutter delegation.',
                defaultSource: const FlutterCtorDefault(),
              ),
              StructuredField(
                wireId: WireId('p0704'),
                name: 'unspecified',
                type: PropertyType.string,
                description: 'No default claim.',
              ),
            ],
            variants: [
              ConstValueVariant(
                wireId: WireId('v0040'),
                staticAccessor: 'sentinel',
              ),
            ],
          ),
        ],
      );

      final decoded = decodeCatalog(encodeCatalog(input));
      final fields = decoded.structuredTypes.first.fields;
      expect(fields[0].defaultSource, isA<LiteralDefault>());
      expect(fields[1].defaultSource, isA<TokenRefDefault>());
      expect(fields[2].defaultSource, isA<ThemeBindingDefault>());
      expect(fields[3].defaultSource, isA<FlutterCtorDefault>());
      expect(fields[4].defaultSource, isNull);
    });

    test('union source identity round-trips through the codec', () {
      const gradientFqn = 'package:flutter/src/painting/gradient.dart#Gradient';
      const memberFqns = <String>[
        'package:flutter/src/painting/gradient.dart#LinearGradient',
        'package:flutter/src/painting/gradient.dart#RadialGradient',
        'package:flutter/src/painting/gradient.dart#SweepGradient',
      ];
      final input = Catalog(
        schemaVersion: kSupportedSchemaVersion,
        generatedAt: '2026-05-11T12:00:00Z',
        libraries: {
          WidgetLibrary.core: const LibraryInfo(version: '0.1.0'),
        },
        widgets: const [],
        unions: [
          UnionEntry(
            wireId: WireId('u0001'),
            name: 'Gradient',
            library: WidgetLibrary.core,
            description: 'An abstract gradient.',
            sourceType: gradientFqn,
            memberSourceTypes: memberFqns,
            discriminator: DiscriminatorSpec(
              field: '_s',
              values: [
                WireIdRef(library: 'restage.core', wireId: WireId('s0001')),
                WireIdRef(library: 'restage.core', wireId: WireId('s0002')),
                WireIdRef(library: 'restage.core', wireId: WireId('s0003')),
              ],
            ),
            members: [
              WireIdRef(library: 'restage.core', wireId: WireId('s0001')),
              WireIdRef(library: 'restage.core', wireId: WireId('s0002')),
              WireIdRef(library: 'restage.core', wireId: WireId('s0003')),
            ],
            stability: Stability.stable,
          ),
        ],
      );

      final decoded = decodeCatalog(encodeCatalog(input));

      expect(decoded.unions, hasLength(1));
      final union = decoded.unions.first;
      expect(union.sourceType, gradientFqn);
      expect(union.memberSourceTypes, memberFqns);
    });

    test('deprecation info round-trips both layers', () {
      final input = Catalog(
        schemaVersion: kSupportedSchemaVersion,
        generatedAt: '2026-05-11T12:00:00Z',
        libraries: {
          WidgetLibrary.core: const LibraryInfo(version: '0.1.0'),
        },
        widgets: const [],
        designTokens: [
          DesignTokenEntry(
            wireId: WireId('t0099'),
            name: 'legacyTint',
            library: WidgetLibrary.core,
            type: DesignTokenType.color,
            literalFallback: 0xFF999999,
            deprecated: const CatalogDeprecationInfoEnvelope(
              source: SourceDeprecationInfo(
                message: 'Use restage.core.t0001 instead.',
                since: '0.3.0',
              ),
              catalog: CatalogDeprecationInfo(
                reason: 'Replaced by background token.',
                at: '2027-01-01T00:00:00Z',
              ),
            ),
          ),
        ],
      );

      final decoded = decodeCatalog(encodeCatalog(input));
      final dep = decoded.designTokens.first.deprecated!;
      expect(dep.source?.message, 'Use restage.core.t0001 instead.');
      expect(dep.source?.since, '0.3.0');
      expect(dep.catalog?.reason, 'Replaced by background token.');
    });
  });
}

// Small alias to avoid confusion between [CatalogDeprecationInfo] (the
// catalog-layer wrapper) and [DeprecationInfo] (the two-layer envelope) in
// the test body above. Keeps the test reader from misreading the nested
// shape.
typedef CatalogDeprecationInfoEnvelope = DeprecationInfo;
