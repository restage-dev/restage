import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

void main() {
  group('RestageCatalogGenAdapter', () {
    test('round-trips reflected widget entries through compiler IR', () {
      final widget = WidgetEntry(
        wireId: WireId.unallocatedWidget,
        name: 'DecoratedBox',
        library: WidgetLibrary.core,
        category: WidgetCategory.decoration,
        description: 'Paints a decoration behind its child.',
        flutterType: 'package:flutter/widgets.dart#DecoratedBox',
        childrenSlot: ChildrenSlot.single,
        fires: const [WidgetEventName.onTap],
        properties: const [
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'child',
            type: PropertyType.widget,
            description: 'Child widget.',
            widgetType: 'PreferredSizeWidget',
          ),
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'url',
            type: PropertyType.string,
            description: 'Image URL.',
            positional: true,
          ),
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'color',
            type: PropertyType.color,
            description: 'Fill color.',
            defaultSource: LiteralDefault(0xFF000000),
            category: PropertyCategory.style,
            priority: PropertyPriority.primary,
            requiresAncestor: 'Material',
            validationRule: ValidationExpr(
              expression: r'matches("^#?[0-9a-fA-F]{6}$")',
              message: 'Color must be a 6-digit RGB value.',
            ),
          ),
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'gradient',
            type: PropertyType.gradient,
            description: 'Fill gradient.',
            defaultBrandToken: 'surfaceGradient',
          ),
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'foregroundColor',
            type: PropertyType.color,
            description: 'Foreground color.',
            defaultSource: ThemeBindingDefault(
              ThemeBindingPath.path('colorScheme.primary'),
            ),
          ),
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'mode',
            type: PropertyType.enumValue,
            description: 'Layout mode.',
            defaultSource: LiteralDefault('start'),
            enumType: 'MainAxisAlignment',
          ),
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'enabled',
            type: PropertyType.boolean,
            description: 'Whether the control is enabled.',
            synthetic: 'gateOnPressed',
            mutuallyExclusiveWith: [WireId.unallocatedProperty],
            deprecated: DeprecationInfo(
              source: SourceDeprecationInfo(
                message: 'Use `interactive` instead.',
                since: '3.1.0',
              ),
              catalog: CatalogDeprecationInfo(
                reason: 'Consolidated into the interactive gate.',
                at: '2026-05-01T00:00:00.000Z',
              ),
            ),
          ),
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'onTap',
            type: PropertyType.event,
            description: 'Tap handler.',
            callbackSignature: 'ValueChanged<bool>',
            firesAs: 'onTap',
          ),
        ],
        decomposes: [
          DecompositionRecipe(
            structuredRef: const WireIdRef(
              library: 'restage.core',
              wireId: WireId.unallocatedStructured,
            ),
            flatProperties: <WireId, WireId>{
              WireId.unallocatedProperty: WireId.unallocatedProperty,
            },
          ),
        ],
        deprecatedSince: '0.9.0',
        deprecated: const DeprecationInfo(
          source: SourceDeprecationInfo(
            message: 'Use `Surface` instead.',
            since: '0.9.0',
          ),
          catalog: CatalogDeprecationInfo(
            reason: 'Replaced by the Surface family.',
            at: '2026-05-01T00:00:00.000Z',
            replaceWith: WireIdRef(
              library: 'restage.core',
              wireId: WireId.unallocatedWidget,
            ),
          ),
        ),
      );

      final catalog = const RestageCatalogGenAdapter().lowerCatalog(
        library: WidgetLibrary.core,
        version: '1.2.3',
        generatedAt: '2026-05-12T00:00:00.000Z',
        widgets: [widget],
      );

      expect(catalog.generatedAt, '2026-05-12T00:00:00.000Z');
      expect(catalog.libraries[WidgetLibrary.core]?.version, '1.2.3');
      expect(catalog.widgetsIn(WidgetLibrary.core).length, 1);

      final lowered = catalog.widgets.single;
      expect(lowered.wireId, WireId.unallocatedWidget);
      expect(lowered.name, widget.name);
      expect(lowered.library, WidgetLibrary.core);
      expect(lowered.category, widget.category);
      expect(lowered.description, widget.description);
      expect(lowered.flutterType, widget.flutterType);
      expect(lowered.childrenSlot, widget.childrenSlot);
      expect(lowered.fires, widget.fires);
      expect(lowered.deprecatedSince, '0.9.0');
      expect(lowered.deprecated, widget.deprecated);

      expect(lowered.properties, hasLength(8));
      expect(
        lowered.properties.map((property) => property.wireId),
        everyElement(WireId.unallocatedProperty),
      );
      final byName = {
        for (final property in lowered.properties) property.name: property,
      };
      expect(byName['child']!.widgetType, 'PreferredSizeWidget');
      expect(byName['url']!.positional, isTrue);
      expect(byName['color']!.defaultValue, 0xFF000000);
      expect(
        byName['color']!.defaultSource,
        const LiteralDefault(0xFF000000),
      );
      expect(byName['color']!.category, PropertyCategory.style);
      expect(byName['color']!.priority, PropertyPriority.primary);
      expect(byName['color']!.requiresAncestor, 'Material');
      expect(
        byName['color']!.validationRule,
        const ValidationExpr(
          expression: r'matches("^#?[0-9a-fA-F]{6}$")',
          message: 'Color must be a 6-digit RGB value.',
        ),
      );
      expect(byName['gradient']!.type, PropertyType.gradient);
      expect(byName['gradient']!.defaultBrandToken, 'surfaceGradient');
      expect(byName['gradient']!.defaultSource, isNull);
      expect(
        byName['foregroundColor']!.defaultSource,
        const ThemeBindingDefault(
          ThemeBindingPath.path('colorScheme.primary'),
        ),
      );
      expect(byName['mode']!.enumType, 'MainAxisAlignment');
      expect(byName['mode']!.defaultValue, 'start');
      expect(
        byName['mode']!.defaultSource,
        const LiteralDefault('start'),
      );
      expect(byName['enabled']!.synthetic, 'gateOnPressed');
      expect(
        byName['enabled']!.mutuallyExclusiveWith,
        const [WireId.unallocatedProperty],
      );
      expect(
        byName['enabled']!.deprecated,
        const DeprecationInfo(
          source: SourceDeprecationInfo(
            message: 'Use `interactive` instead.',
            since: '3.1.0',
          ),
          catalog: CatalogDeprecationInfo(
            reason: 'Consolidated into the interactive gate.',
            at: '2026-05-01T00:00:00.000Z',
          ),
        ),
      );
      expect(byName['onTap']!.callbackSignature, 'ValueChanged<bool>');
      expect(byName['onTap']!.firesAs, 'onTap');

      final recipe = lowered.decomposes.single;
      expect(recipe.structuredRef.wireId, WireId.unallocatedStructured);
      expect(recipe.flatProperties, {
        WireId.unallocatedProperty: WireId.unallocatedProperty,
      });
    });

    test(
        'preserves an above-baseline content version through the production '
        'lowerCatalog entrypoint', () {
      // Regression guard for a silent content-version reset: the adapter's
      // WidgetEntry -> IR projection used to drop sinceVersion, so any entry
      // above the baseline was reset to the baseline as it passed through
      // lowerCatalog (the sole production entrypoint for both built-in and
      // customer catalogs). This drives the real function — not a
      // hand-assembled stage sequence — and asserts the content version
      // survives end to end.
      const widget = WidgetEntry(
        wireId: WireId.unallocatedWidget,
        name: 'NewSurface',
        library: WidgetLibrary.core,
        category: WidgetCategory.layout,
        description: 'A widget introduced after the baseline.',
        flutterType: 'package:flutter/widgets.dart#NewSurface',
        childrenSlot: ChildrenSlot.none,
        fires: [],
        properties: [],
        sinceVersion: 2,
      );

      final catalog = const RestageCatalogGenAdapter().lowerCatalog(
        library: WidgetLibrary.core,
        version: '1.2.3',
        generatedAt: '2026-05-12T00:00:00.000Z',
        widgets: [widget],
      );

      expect(
        catalog.widgets.single.sinceVersion,
        2,
        reason: 'lowerCatalog must preserve a widget sinceVersion above the '
            'baseline',
      );
      expect(
        catalog.contentVersion,
        2,
        reason: 'the catalog content version is the max widget sinceVersion',
      );
    });

    test('wire ID hooks can supply real IDs without fabricating defaults', () {
      const widget = WidgetEntry(
        wireId: WireId.unallocatedWidget,
        name: 'Text',
        library: WidgetLibrary.core,
        category: WidgetCategory.decoration,
        description: 'Displays text.',
        flutterType: 'package:flutter/widgets.dart#Text',
        childrenSlot: ChildrenSlot.none,
        fires: [],
        properties: [
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'text',
            type: PropertyType.string,
            description: 'Text data.',
            required: true,
          ),
        ],
      );

      final catalog = RestageCatalogGenAdapter(
        wireIds: RestageCatalogGenWireIdHooks(
          widget: (_) => WireId('w0001'),
          property: (_, __) => WireId('p0001'),
        ),
      ).lowerCatalog(
        library: WidgetLibrary.core,
        version: '1.2.3',
        generatedAt: '2026-05-12T00:00:00.000Z',
        widgets: [widget],
      );

      expect(catalog.widgets.single.wireId, WireId('w0001'));
      expect(
        catalog.widgets.single.properties.single.wireId,
        WireId('p0001'),
      );
    });

    test('event-log hooks resolve widgets and properties', () {
      final sourceCatalog = Catalog(
        schemaVersion: 3,
        generatedAt: '1970-01-01T00:00:00Z',
        libraries: {
          WidgetLibrary.core: const LibraryInfo(version: '1.2.3'),
        },
        widgets: [
          _textWidget(),
        ],
      );
      final events = backfillRestageCatalogWireIds(
        catalog: sourceCatalog,
        library: WidgetLibrary.core,
      );
      final state = replayWireIdEvents(
        library: WidgetLibrary.core.namespace,
        events: events,
      );
      expect(
        state.structuredTypes.values.map((entry) => entry.name),
        containsAll([
          'TextStyle',
          'BoxDecoration',
          'BorderRadius',
          'EdgeInsets',
          'Border',
          'BorderSide',
          'BoxShadow',
          'LinearGradient',
        ]),
      );
      expect(state.variants, isNotEmpty);
      expect(
        state.variants.values.map((entry) => entry.owner).toSet(),
        everyElement(isIn(state.structuredTypes.keys)),
      );
      expect(
        state.variants.values.where(
          (entry) => entry.sourceKind == VariantSourceKind.staticMethod,
        ),
        isEmpty,
      );
      expect(
        state.variants.values.map((entry) => entry.namedConstructor).toSet(),
        containsAll({
          null,
          'circular',
          'fromLTRB',
          'all',
          'symmetric',
          'only',
        }),
      );
      expect(state.unions, isEmpty);
      expect(state.designTokens, isEmpty);

      final catalog = RestageCatalogGenAdapter(
        wireIds: RestageCatalogGenEventLogWireIdResolver(
          library: WidgetLibrary.core.namespace,
          events: events,
        ).hooks,
      ).lowerCatalog(
        library: WidgetLibrary.core,
        version: '1.2.3',
        generatedAt: '2026-05-12T00:00:00.000Z',
        widgets: sourceCatalog.widgets,
      );

      final text = catalog.widgets.single;
      expect(text.wireId, WireId('w0001'));
      expect(
        text.properties.map((property) => property.wireId),
        [WireId('p0001'), WireId('p0002'), WireId('p0003')],
      );

      final recipe = text.decomposes.single;
      expect(
        recipe.structuredRef,
        const WireIdRef(
          library: 'restage.core',
          wireId: WireId.unallocatedStructured,
        ),
      );
      expect(recipe.flatProperties, isEmpty);
    });

    test('event-log hooks reject preallocated parameters owned elsewhere', () {
      const at = '2026-05-12T00:00:00.000Z';
      const by = 'test';
      final events = [
        AllocWireIdEvent(
          type: WireIdKind.structured,
          id: WireId('s0001'),
          name: 'Shape',
          source: 'src#Shape',
          at: at,
          by: by,
        ),
        AllocWireIdEvent(
          type: WireIdKind.variant,
          id: WireId('v0001'),
          owner: WireId('s0001'),
          sourceKind: VariantSourceKind.constructor,
          source: 'src#Shape.',
          at: at,
          by: by,
        ),
        AllocWireIdEvent(
          type: WireIdKind.variant,
          id: WireId('v0002'),
          owner: WireId('s0001'),
          sourceKind: VariantSourceKind.constructor,
          namedConstructor: 'other',
          source: 'src#Shape.other',
          at: at,
          by: by,
        ),
        AllocWireIdEvent(
          type: WireIdKind.parameter,
          id: WireId('a0001'),
          owner: WireId('v0002'),
          name: 'radius',
          source: 'src#Shape.other.radius',
          at: at,
          by: by,
        ),
      ];
      final resolver = RestageCatalogGenEventLogWireIdResolver(
        library: WidgetLibrary.core.namespace,
        events: events,
      );
      final entry = StructuredEntry(
        wireId: WireId.unallocatedStructured,
        name: 'Shape',
        library: WidgetLibrary.core,
        description: '',
        sourceType: 'src#Shape',
        fields: const [],
        variants: [
          ConstructorVariant(
            wireId: WireId('v0001'),
            parameters: [
              FactoryParameter(
                wireId: WireId('a0001'),
                name: 'radius',
                kind: FactoryParameterKind.named,
                required: true,
                nullable: false,
                defaultPolicy: FactoryParameterDefaultPolicy.requiredValue,
                valueShape: const ScalarShape(
                  propertyType: PropertyType.real,
                ),
              ),
            ],
          ),
        ],
      );

      expect(
        () => resolver.resolveStructured(entry),
        throwsA(
          isA<WireIdReplayException>().having(
            (error) => error.message,
            'message',
            allOf(contains('a0001'), contains('v0002'), contains('v0001')),
          ),
        ),
      );
    });

    test(
        'resolveStructured backfills an unallocated parameter wire ID while '
        'retaining its typed defaultValue', () {
      const at = '2026-05-12T00:00:00.000Z';
      const by = 'test';
      final events = [
        AllocWireIdEvent(
          type: WireIdKind.structured,
          id: WireId('s0001'),
          name: 'Shape',
          source: 'src#Shape',
          at: at,
          by: by,
        ),
        AllocWireIdEvent(
          type: WireIdKind.variant,
          id: WireId('v0001'),
          owner: WireId('s0001'),
          sourceKind: VariantSourceKind.constructor,
          source: 'src#Shape.',
          at: at,
          by: by,
        ),
        AllocWireIdEvent(
          type: WireIdKind.parameter,
          id: WireId('a0001'),
          owner: WireId('v0001'),
          name: 'radius',
          source: 'src#Shape.radius',
          at: at,
          by: by,
        ),
      ];
      final resolver = RestageCatalogGenEventLogWireIdResolver(
        library: WidgetLibrary.core.namespace,
        events: events,
      );
      const defaultValue = LiteralParameterDefault(8.0);
      const entry = StructuredEntry(
        wireId: WireId.unallocatedStructured,
        name: 'Shape',
        library: WidgetLibrary.core,
        description: '',
        sourceType: 'src#Shape',
        fields: [],
        variants: [
          ConstructorVariant(
            wireId: WireId.unallocatedVariant,
            parameters: [
              FactoryParameter(
                wireId: WireId.unallocatedParameter,
                name: 'radius',
                kind: FactoryParameterKind.named,
                required: false,
                nullable: false,
                defaultPolicy: FactoryParameterDefaultPolicy.useFlutterDefault,
                defaultValue: defaultValue,
                valueShape: ScalarShape(
                  propertyType: PropertyType.real,
                ),
              ),
            ],
          ),
        ],
      );

      final resolved = resolver.resolveStructured(entry);
      final parameter =
          (resolved.variants.single as ConstructorVariant).parameters.single;

      expect(parameter.wireId, WireId('a0001'));
      expect(parameter.defaultValue, defaultValue);
    });

    test('built-in backfill is idempotent and skips unions and tokens', () {
      final catalog = Catalog(
        schemaVersion: 3,
        generatedAt: '1970-01-01T00:00:00Z',
        libraries: {
          WidgetLibrary.material: const LibraryInfo(version: '1.2.3'),
        },
        widgets: [
          _materialButton(),
        ],
        unions: const [
          UnionEntry(
            wireId: WireId.unallocatedUnion,
            name: 'IgnoredUnion',
            library: WidgetLibrary.material,
            description: 'Not yet wire-allocated.',
            sourceType: 'package:test/test.dart#IgnoredUnion',
            memberSourceTypes: [],
            discriminator: DiscriminatorSpec(
              field: 'type',
              values: [],
            ),
            members: [],
          ),
        ],
        designTokens: const [
          DesignTokenEntry(
            wireId: WireId.unallocatedDesignToken,
            name: 'ignored',
            library: WidgetLibrary.material,
            type: DesignTokenType.color,
            description: 'Not yet wire-allocated.',
            literalFallback: 0xFF000000,
          ),
        ],
      );

      final first = backfillRestageCatalogWireIds(
        catalog: catalog,
        library: WidgetLibrary.material,
      );
      final second = backfillRestageCatalogWireIds(
        catalog: catalog,
        library: WidgetLibrary.material,
        existingEvents: first,
      );

      expect(encodeWireIdEventsJsonl(second), encodeWireIdEventsJsonl(first));
      final state = replayWireIdEvents(
        library: WidgetLibrary.material.namespace,
        events: first,
      );
      expect(state.widgets.keys, [WireId('w0001')]);
      expect(
        state.structuredTypes.values.map((entry) => entry.name),
        ['ButtonStyle'],
      );
      expect(state.variants, isNotEmpty);
      expect(
        state.variants.values.map((entry) => entry.owner).toSet(),
        everyElement(isIn(state.structuredTypes.keys)),
      );
      final variant = state.variants.values.single;
      expect(variant.sourceKind, VariantSourceKind.staticMethod);
      expect(variant.staticAccessor, 'styleFrom');
      expect(variant.namedConstructor, isNull);
      expect(state.unions, isEmpty);
      expect(state.designTokens, isEmpty);

      final resolvedCatalog = RestageCatalogGenAdapter(
        wireIds: RestageCatalogGenEventLogWireIdResolver(
          library: WidgetLibrary.material.namespace,
          events: first,
        ).hooks,
      ).lowerCatalog(
        library: WidgetLibrary.material,
        version: '1.2.3',
        generatedAt: '2026-05-12T00:00:00.000Z',
        widgets: catalog.widgets,
      );
      final recipe = resolvedCatalog.widgets.single.decomposes.single;
      expect(
        recipe.structuredRef,
        const WireIdRef(
          library: 'restage.material',
          wireId: WireId.unallocatedStructured,
        ),
      );
      expect(recipe.flatProperties, isEmpty);
    });

    test('event-log hooks leave BoxDecoration recipes unchanged', () {
      final sourceCatalog = Catalog(
        schemaVersion: 3,
        generatedAt: '1970-01-01T00:00:00Z',
        libraries: {
          WidgetLibrary.core: const LibraryInfo(version: '1.2.3'),
        },
        widgets: [
          _decoratedBoxWidget(),
        ],
      );
      final events = backfillRestageCatalogWireIds(
        catalog: sourceCatalog,
        library: WidgetLibrary.core,
      );

      final catalog = RestageCatalogGenAdapter(
        wireIds: RestageCatalogGenEventLogWireIdResolver(
          library: WidgetLibrary.core.namespace,
          events: events,
        ).hooks,
      ).lowerCatalog(
        library: WidgetLibrary.core,
        version: '1.2.3',
        generatedAt: '2026-05-12T00:00:00.000Z',
        widgets: sourceCatalog.widgets,
      );

      final recipe = catalog.widgets.single.decomposes.single;
      expect(
        recipe.structuredRef,
        const WireIdRef(
          library: 'restage.core',
          wireId: WireId.unallocatedStructured,
        ),
      );
      expect(recipe.flatProperties, isEmpty);
    });

    test('routes structured entries through compiler IR and back to schema',
        () {
      const innerEntry = StructuredEntry(
        wireId: WireId.unallocatedStructured,
        name: 'BorderRadius',
        library: WidgetLibrary.core,
        description: 'Corner radii.',
        sourceType: 'package:flutter/src/painting/border_radius.dart'
            '#BorderRadius',
        fields: [],
        variants: [],
      );
      const outerEntry = StructuredEntry(
        wireId: WireId.unallocatedStructured,
        name: 'BoxDecoration',
        library: WidgetLibrary.core,
        description: 'Paints a box decoration.',
        sourceType: 'package:flutter/src/painting/box_decoration.dart'
            '#BoxDecoration',
        fields: [
          StructuredField(
            wireId: WireId.unallocatedProperty,
            name: 'color',
            type: PropertyType.color,
            description: 'Fill color.',
          ),
          StructuredField(
            wireId: WireId.unallocatedProperty,
            name: 'borderRadius',
            type: PropertyType.structured,
            description: 'Corner radii.',
            structuredRef: WireIdRef(
              library: 'restage.core',
              wireId: WireId.unallocatedStructured,
            ),
          ),
        ],
        variants: [],
      );

      final catalog = const RestageCatalogGenAdapter().lowerCatalog(
        library: WidgetLibrary.core,
        version: '1.2.3',
        generatedAt: '2026-05-13T00:00:00.000Z',
        widgets: const [],
        structuredEntries: const [outerEntry, innerEntry],
      );

      expect(catalog.structuredTypes, hasLength(2));
      expect(catalog.structuredTypesIn(WidgetLibrary.core).length, 2);

      final lowered = catalog.structuredTypes.first;
      expect(lowered.name, 'BoxDecoration');
      expect(lowered.sourceType, outerEntry.sourceType);
      expect(lowered.fields, hasLength(2));

      final structuredField = lowered.fields[1];
      expect(structuredField.type, PropertyType.structured);
      expect(structuredField.structuredRef, isNotNull);
      expect(structuredField.structuredRef!.library, 'restage.core');
      expect(
        structuredField.structuredRef!.wireId,
        WireId.unallocatedStructured,
      );
    });

    test(
        'resolveProperty is lenient: matched names get seeded IDs, '
        'unmatched names pass through unallocated for the allocator to mint',
        () {
      // Seed an event log from a small catalog.
      final seededCatalog = Catalog(
        schemaVersion: 3,
        generatedAt: '1970-01-01T00:00:00Z',
        libraries: {
          WidgetLibrary.core: const LibraryInfo(version: '1.2.3'),
        },
        widgets: [_textWidget()],
      );
      final seededEvents = backfillRestageCatalogWireIds(
        catalog: seededCatalog,
        library: WidgetLibrary.core,
      );

      final resolver = RestageCatalogGenEventLogWireIdResolver(
        library: WidgetLibrary.core.namespace,
        events: seededEvents,
      );

      // Matched property: the seeded log carries it; resolver returns
      // the recorded wire ID.
      final matchedProperty = _textWidget().properties.firstWhere(
            (p) => p.name == 'fontSize',
          );
      final matchedId =
          resolver.resolveProperty(_textWidget(), matchedProperty);
      expect(matchedId.isUnallocated, isFalse);

      // Unmatched property on a seeded widget: pass through unallocated
      // so the downstream allocator mints a fresh ID monotonically.
      const unmatchedOnSeededWidget = PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: 'brandNewLeaf',
        type: PropertyType.string,
        description: 'A new flat property the seeded log does not have.',
      );
      expect(
        resolver.resolveProperty(_textWidget(), unmatchedOnSeededWidget),
        WireId.unallocatedProperty,
      );

      // Property on a widget that is not in the seeded log at all:
      // pass through unallocated so the allocator can mint widget +
      // property in lockstep.
      const brandNewWidget = WidgetEntry(
        wireId: WireId.unallocatedWidget,
        name: 'BrandNewWidget',
        library: WidgetLibrary.core,
        category: WidgetCategory.decoration,
        description: 'A new widget the seeded log does not have.',
        flutterType: 'package:flutter/widgets.dart#BrandNewWidget',
        childrenSlot: ChildrenSlot.none,
        fires: [],
        properties: [
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'novel',
            type: PropertyType.string,
            description: 'A novel property.',
          ),
        ],
      );
      final newProperty = brandNewWidget.properties.single;
      expect(
        resolver.resolveProperty(brandNewWidget, newProperty),
        WireId.unallocatedProperty,
      );

      // Determinism: replaying the same catalog through the resolver and
      // then the allocator produces zero new events (every property finds
      // its seeded match).
      final replayed = const RestageCatalogGenAdapter().lowerCatalog(
        library: WidgetLibrary.core,
        version: '1.2.3',
        generatedAt: '2026-05-12T00:00:00.000Z',
        widgets: seededCatalog.widgets,
      );
      final allocator = WireIdAllocator(
        library: WidgetLibrary.core.namespace,
        at: '2026-05-12T00:00:00.000Z',
        by: 'determinism-test',
        existingEvents: seededEvents,
      );
      final newEventsWithoutResolver = allocator.allocateCatalog(
        replayed,
        WidgetLibrary.core,
      );
      // No resolver: every property is unallocated, so the allocator
      // SHOULD mint fresh IDs and emit new events.
      expect(newEventsWithoutResolver, isNotEmpty);

      // With resolver: every property has been patched to its seeded
      // ID, so the allocator emits zero new events.
      final resolvedCatalog = RestageCatalogGenAdapter(
        wireIds: resolver.hooks,
      ).lowerCatalog(
        library: WidgetLibrary.core,
        version: '1.2.3',
        generatedAt: '2026-05-12T00:00:00.000Z',
        widgets: seededCatalog.widgets,
      );
      final allocator2 = WireIdAllocator(
        library: WidgetLibrary.core.namespace,
        at: '2026-05-12T00:00:00.000Z',
        by: 'determinism-test',
        existingEvents: seededEvents,
      );
      final newEventsWithResolver = allocator2.allocateCatalog(
        resolvedCatalog,
        WidgetLibrary.core,
      );
      expect(newEventsWithResolver, isEmpty);
    });

    test(
        'union resolution is replay-idempotent across a clean rebuild: '
        'a fresh unallocated union reaches the allocator carrying its '
        'seeded wire ID and emits zero new events', () {
      // The real build feeds the allocator a freshly reflected catalog
      // every run — the union arrives with WireId.unallocatedUnion and
      // structured-sentinel member refs, NOT the post-allocation catalog.
      // A clean rebuild must re-derive the same union wire ID from the
      // event log and emit no second `alloc` / `addMember` events.
      Catalog freshCatalog() => Catalog(
            schemaVersion: 3,
            generatedAt: '1970-01-01T00:00:00Z',
            libraries: {
              WidgetLibrary.core: const LibraryInfo(version: '1.2.3'),
            },
            widgets: const [],
            structuredTypes: const [
              StructuredEntry(
                wireId: WireId.unallocatedStructured,
                name: 'Circle',
                library: WidgetLibrary.core,
                description: 'A circle.',
                sourceType: 'package:test/shapes.dart#Circle',
                fields: [],
                variants: [],
              ),
              StructuredEntry(
                wireId: WireId.unallocatedStructured,
                name: 'Square',
                library: WidgetLibrary.core,
                description: 'A square.',
                sourceType: 'package:test/shapes.dart#Square',
                fields: [],
                variants: [],
              ),
            ],
            unions: const [
              UnionEntry(
                wireId: WireId.unallocatedUnion,
                name: 'Shape',
                library: WidgetLibrary.core,
                description: 'A shape union.',
                sourceType: 'package:test/shapes.dart#Shape',
                memberSourceTypes: [
                  'package:test/shapes.dart#Circle',
                  'package:test/shapes.dart#Square',
                ],
                discriminator: DiscriminatorSpec(
                  field: '_s',
                  values: [
                    WireIdRef(
                      library: 'restage.core',
                      wireId: WireId.unallocatedStructured,
                    ),
                    WireIdRef(
                      library: 'restage.core',
                      wireId: WireId.unallocatedStructured,
                    ),
                  ],
                ),
                members: [
                  WireIdRef(
                    library: 'restage.core',
                    wireId: WireId.unallocatedStructured,
                  ),
                  WireIdRef(
                    library: 'restage.core',
                    wireId: WireId.unallocatedStructured,
                  ),
                ],
              ),
            ],
          );

      // First build: no seeded events. The allocator mints the structured
      // types, the union, and its memberships.
      final firstAllocator = WireIdAllocator(
        library: WidgetLibrary.core.namespace,
        at: '2026-05-12T00:00:00.000Z',
        by: 'clean-rebuild-test',
      );
      final firstEvents = firstAllocator.allocateCatalog(
        freshCatalog(),
        WidgetLibrary.core,
      );
      final firstUnionAlloc = firstEvents
          .whereType<AllocWireIdEvent>()
          .singleWhere((event) => event.type == WireIdKind.union);
      expect(firstUnionAlloc.id.kind, WireIdKind.union);
      expect(
        firstEvents.whereType<AddMemberWireIdEvent>(),
        hasLength(2),
      );

      // Second build (clean rebuild): a brand-new fresh catalog — the
      // union and its members are unallocated sentinels again, NOT the
      // post-allocation catalog. The resolver patches the union's wire ID
      // from the event log before the allocator runs.
      final resolverHooks = RestageCatalogGenEventLogWireIdResolver(
        library: WidgetLibrary.core.namespace,
        events: firstAllocator.events,
      ).hooks;
      final rebuiltCatalog = RestageCatalogGenAdapter(
        wireIds: resolverHooks,
      ).lowerCatalog(
        library: WidgetLibrary.core,
        version: '1.2.3',
        generatedAt: '2026-05-12T00:00:00.000Z',
        widgets: const [],
        structuredEntries: freshCatalog().structuredTypes,
        unions: freshCatalog().unions,
      );

      // The resolver must have patched the union to its real wire ID.
      expect(rebuiltCatalog.unions.single.wireId, firstUnionAlloc.id);

      final secondAllocator = WireIdAllocator(
        library: WidgetLibrary.core.namespace,
        at: '2026-05-12T00:00:00.000Z',
        by: 'clean-rebuild-test',
        existingEvents: firstAllocator.events,
      );
      final secondEvents = secondAllocator.allocateCatalog(
        rebuiltCatalog,
        WidgetLibrary.core,
      );

      expect(
        secondEvents.whereType<AllocWireIdEvent>().where(
              (event) => event.type == WireIdKind.union,
            ),
        isEmpty,
        reason: 'a clean rebuild must not re-allocate an existing union',
      );
      expect(
        secondEvents.whereType<AddMemberWireIdEvent>(),
        isEmpty,
        reason: 'a clean rebuild must not duplicate union memberships',
      );
      expect(secondEvents, isEmpty);
    });

    test(
        'resolveUnion returns a brand-new union unchanged so the allocator '
        'mints a fresh wire ID', () {
      // Seed an event log carrying one union.
      final seedAllocator = WireIdAllocator(
        library: WidgetLibrary.core.namespace,
        at: '2026-05-12T00:00:00.000Z',
        by: 'resolve-union-test',
      )..allocate(
          // The seed source key matches the form unionSourceKey() builds:
          // '<library>#<abstract-base FQN>'. Keying on the stable FQN — not
          // the mutable display name — is what survives a union rename.
          const WireIdAllocationCandidate.union(
            name: 'Shape',
            source: 'restage.core#package:test/shapes.dart#Shape',
          ),
        );

      final resolver = RestageCatalogGenEventLogWireIdResolver(
        library: WidgetLibrary.core.namespace,
        events: seedAllocator.events,
      );

      // A union the seeded log already records: resolver patches the ID.
      const seededUnion = UnionEntry(
        wireId: WireId.unallocatedUnion,
        name: 'Shape',
        library: WidgetLibrary.core,
        description: 'A shape union.',
        sourceType: 'package:test/shapes.dart#Shape',
        memberSourceTypes: [],
        discriminator: DiscriminatorSpec(field: '_s', values: []),
        members: [],
      );
      expect(
        resolver.resolveUnion(seededUnion).wireId.isUnallocated,
        isFalse,
      );

      // A union the seeded log does not have: pass through unallocated so
      // the downstream allocator can mint a fresh ID.
      const brandNewUnion = UnionEntry(
        wireId: WireId.unallocatedUnion,
        name: 'Brush',
        library: WidgetLibrary.core,
        description: 'A brush union the seeded log does not have.',
        sourceType: 'package:test/brushes.dart#Brush',
        memberSourceTypes: [],
        discriminator: DiscriminatorSpec(field: '_s', values: []),
        members: [],
      );
      expect(
        resolver.resolveUnion(brandNewUnion).wireId,
        WireId.unallocatedUnion,
      );
    });

    test(
        'union source identity survives a rename: a renamed union still '
        'resolves to its seeded wire ID', () {
      // Seed an event log with a union allocated under one display name.
      final seedAllocator = WireIdAllocator(
        library: WidgetLibrary.core.namespace,
        at: '2026-05-12T00:00:00.000Z',
        by: 'rename-test',
      )..allocate(
          const WireIdAllocationCandidate.union(
            name: 'Shape',
            source: 'restage.core#package:test/shapes.dart#Shape',
          ),
        );
      final seededId =
          seedAllocator.events.whereType<AllocWireIdEvent>().single.id;

      final resolver = RestageCatalogGenEventLogWireIdResolver(
        library: WidgetLibrary.core.namespace,
        events: seedAllocator.events,
      );

      // A later catalog renames the union (e.g. 'Shape' -> 'Figure') but the
      // abstract base type — its stable identity — is unchanged. Keying on
      // the FQN means the renamed union still resolves to the seeded ID.
      const renamedUnion = UnionEntry(
        wireId: WireId.unallocatedUnion,
        name: 'Figure',
        library: WidgetLibrary.core,
        description: 'The Shape union, renamed to Figure.',
        sourceType: 'package:test/shapes.dart#Shape',
        memberSourceTypes: [],
        discriminator: DiscriminatorSpec(field: '_s', values: []),
        members: [],
      );
      expect(
        resolver.resolveUnion(renamedUnion).wireId,
        seededId,
        reason: 'a rename must not re-allocate; identity is the source FQN',
      );
    });

    test('deprecation hook adds catalog layer and preserves source layer', () {
      // An input widget that already carries a source-layer deprecation.
      const sourceDeprecation = DeprecationInfo(
        source: SourceDeprecationInfo(
          message: 'Use `Surface` instead.',
          since: '0.9.0',
        ),
      );
      const widget = WidgetEntry(
        wireId: WireId.unallocatedWidget,
        name: 'OldBox',
        library: WidgetLibrary.core,
        category: WidgetCategory.decoration,
        description: 'A deprecated widget.',
        flutterType: 'package:flutter/widgets.dart#OldBox',
        childrenSlot: ChildrenSlot.none,
        fires: [],
        properties: [],
        deprecated: sourceDeprecation,
      );

      // A catalog-layer deprecation that the hook will inject for this widget.
      const catalogDeprecation = CatalogDeprecationInfo(
        reason: 'Replaced by the Surface family.',
        at: '2026-05-15T00:00:00.000Z',
      );

      final resolvedId = WireId('w9999');

      // The hook receives the resolved wire ID and the existing deprecation,
      // and must merge them: keep source, add catalog.
      final catalog = RestageCatalogGenAdapter(
        wireIds: RestageCatalogGenWireIdHooks(
          widget: (_) => resolvedId,
          deprecation: (id, existing) {
            if (id != resolvedId) return existing;
            return DeprecationInfo(
              source: existing?.source,
              catalog: catalogDeprecation,
            );
          },
        ),
      ).lowerCatalog(
        library: WidgetLibrary.core,
        version: '1.0.0',
        generatedAt: '2026-05-15T00:00:00.000Z',
        widgets: [widget],
      );

      final lowered = catalog.widgets.single;
      // catalog layer was injected
      expect(lowered.deprecated?.catalog, catalogDeprecation);
      // source layer from the original entry was preserved
      expect(lowered.deprecated?.source, sourceDeprecation.source);
    });

    test('no deprecation hook passes deprecated through unchanged', () {
      const sourceDeprecation = DeprecationInfo(
        source: SourceDeprecationInfo(
          message: 'Legacy widget.',
          since: '1.0.0',
        ),
      );
      const widget = WidgetEntry(
        wireId: WireId.unallocatedWidget,
        name: 'LegacyBox',
        library: WidgetLibrary.core,
        category: WidgetCategory.decoration,
        description: 'A legacy widget.',
        flutterType: 'package:flutter/widgets.dart#LegacyBox',
        childrenSlot: ChildrenSlot.none,
        fires: [],
        properties: [],
        deprecated: sourceDeprecation,
      );

      // No deprecation hook — behavior identical to today.
      final catalog = const RestageCatalogGenAdapter().lowerCatalog(
        library: WidgetLibrary.core,
        version: '1.0.0',
        generatedAt: '2026-05-15T00:00:00.000Z',
        widgets: [widget],
      );

      expect(catalog.widgets.single.deprecated, sourceDeprecation);
    });

    test('deprecation hook that returns existing leaves deprecated unchanged',
        () {
      // The common case: a deprecation hook IS supplied but finds no matching
      // deprecate event for the resolved ID, so it returns `existing`. The
      // entry's deprecated value must pass through untouched.
      const sourceDeprecation = DeprecationInfo(
        source: SourceDeprecationInfo(
          message: 'Use `Surface` instead.',
          since: '1.0.0',
        ),
      );
      const widget = WidgetEntry(
        wireId: WireId.unallocatedWidget,
        name: 'PlainBox',
        library: WidgetLibrary.core,
        category: WidgetCategory.decoration,
        description: 'A widget with no catalog-lifecycle deprecation.',
        flutterType: 'package:flutter/widgets.dart#PlainBox',
        childrenSlot: ChildrenSlot.none,
        fires: [],
        properties: [],
        deprecated: sourceDeprecation,
      );

      // The hook is supplied but always returns `existing` — modelling the
      // `catalog == null` branch where no deprecate event matched.
      final catalog = RestageCatalogGenAdapter(
        wireIds: RestageCatalogGenWireIdHooks(
          deprecation: (_, existing) => existing,
        ),
      ).lowerCatalog(
        library: WidgetLibrary.core,
        version: '1.0.0',
        generatedAt: '2026-05-15T00:00:00.000Z',
        widgets: [widget],
      );

      expect(catalog.widgets.single.deprecated, sourceDeprecation);
    });

    test(
        'unions with the same abstract base in different libraries get '
        'distinct wire IDs', () {
      // restage_core's Gradient and restage_material's Gradient share an
      // abstract base FQN but curate different member sets. The library
      // qualifier in the source key keeps them distinct: a resolver seeded
      // from one library must not patch the other library's union.
      const gradientFqn = 'package:flutter/src/painting/gradient.dart#Gradient';

      UnionEntry gradientUnion(WidgetLibrary library) => UnionEntry(
            wireId: WireId.unallocatedUnion,
            name: 'Gradient',
            library: library,
            description: 'The Gradient union.',
            sourceType: gradientFqn,
            memberSourceTypes: const [],
            discriminator: const DiscriminatorSpec(field: '_s', values: []),
            members: const [],
          );

      // Seed an event log for the core library only.
      final coreAllocator = WireIdAllocator(
        library: WidgetLibrary.core.namespace,
        at: '2026-05-12T00:00:00.000Z',
        by: 'per-library-distinctness-test',
      )..allocate(
          const WireIdAllocationCandidate.union(
            name: 'Gradient',
            source: 'restage.core#$gradientFqn',
          ),
        );

      final coreResolver = RestageCatalogGenEventLogWireIdResolver(
        library: WidgetLibrary.core.namespace,
        events: coreAllocator.events,
      );

      // The core union resolves to the seeded ID.
      expect(
        coreResolver
            .resolveUnion(gradientUnion(WidgetLibrary.core))
            .wireId
            .isUnallocated,
        isFalse,
        reason: 'the core Gradient is in the seeded core event log',
      );

      // The material union — same abstract base FQN, different library —
      // must NOT match the core seed; it passes through unallocated so the
      // allocator mints a distinct wire ID for it.
      expect(
        coreResolver.resolveUnion(gradientUnion(WidgetLibrary.material)).wireId,
        WireId.unallocatedUnion,
        reason: 'the material Gradient must not collide with the core one',
      );
    });
  });
}

WidgetEntry _textWidget() {
  return const WidgetEntry(
    wireId: WireId.unallocatedWidget,
    name: 'Text',
    library: WidgetLibrary.core,
    category: WidgetCategory.decoration,
    description: 'Displays text.',
    flutterType: 'package:flutter/src/widgets/text.dart#Text',
    childrenSlot: ChildrenSlot.none,
    fires: [],
    properties: [
      PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: 'fontSize',
        type: PropertyType.length,
        description: 'Font size.',
      ),
      PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: 'fontWeight',
        type: PropertyType.fontWeight,
        description: 'Font weight.',
      ),
      PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: 'color',
        type: PropertyType.color,
        description: 'Text color.',
        defaultBrandToken: 'onBackground',
      ),
    ],
    decomposes: [
      DecompositionRecipe(
        structuredRef: WireIdRef(
          library: 'restage.core',
          wireId: WireId.unallocatedStructured,
        ),
        flatProperties: <WireId, WireId>{},
      ),
    ],
  );
}

WidgetEntry _materialButton() {
  return const WidgetEntry(
    wireId: WireId.unallocatedWidget,
    name: 'FilledButton',
    library: WidgetLibrary.material,
    category: WidgetCategory.input,
    description: 'A Material button.',
    flutterType: 'package:flutter/src/material/filled_button.dart#FilledButton',
    childrenSlot: ChildrenSlot.single,
    fires: [WidgetEventName.onPressed],
    properties: [
      PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: 'backgroundColor',
        type: PropertyType.color,
        description: 'Background color.',
      ),
      PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: 'foregroundColor',
        type: PropertyType.color,
        description: 'Foreground color.',
      ),
      PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: 'padding',
        type: PropertyType.edgeInsets,
        description: 'Padding.',
      ),
      PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: 'elevation',
        type: PropertyType.real,
        description: 'Elevation.',
      ),
    ],
    decomposes: [
      DecompositionRecipe(
        structuredRef: WireIdRef(
          library: 'restage.material',
          wireId: WireId.unallocatedStructured,
        ),
        flatProperties: <WireId, WireId>{},
      ),
    ],
  );
}

WidgetEntry _decoratedBoxWidget() {
  return const WidgetEntry(
    wireId: WireId.unallocatedWidget,
    name: 'DecoratedBox',
    library: WidgetLibrary.core,
    category: WidgetCategory.decoration,
    description: 'Paints a decoration behind its child.',
    flutterType: 'package:flutter/src/widgets/container.dart#DecoratedBox',
    childrenSlot: ChildrenSlot.single,
    fires: [],
    properties: [
      PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: 'color',
        type: PropertyType.color,
        description: 'Fill color.',
      ),
      PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: 'borderRadius',
        type: PropertyType.real,
        description: 'Uniform corner radius.',
      ),
      PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: 'gradient',
        type: PropertyType.gradient,
        description: 'Fill gradient.',
      ),
      PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: 'border',
        type: PropertyType.border,
        description: 'Border.',
      ),
      PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: 'boxShadow',
        type: PropertyType.boxShadowList,
        description: 'Box shadows.',
      ),
      PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: 'shape',
        type: PropertyType.enumValue,
        description: 'Box shape.',
        enumType: 'BoxShape',
      ),
    ],
    decomposes: [
      DecompositionRecipe(
        structuredRef: WireIdRef(
          library: 'restage.core',
          wireId: WireId.unallocatedStructured,
        ),
        flatProperties: <WireId, WireId>{},
      ),
    ],
  );
}
