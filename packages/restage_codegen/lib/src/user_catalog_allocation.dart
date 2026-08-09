import 'dart:io';
import 'dart:isolate';

import 'package:build/build.dart';
import 'package:package_config/package_config.dart';
import 'package:restage_codegen/src/customer_structured_admissibility.dart'
    show
        isCustomerStructuredFieldSlot,
        isCustomerStructuredPropertySlot,
        structuredSlotKey;
import 'package:restage_codegen/src/factory_variant_fields.dart';
import 'package:restage_codegen/src/user_catalog_emitter.dart';
import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

const String _kUserCatalogAllocationTimestamp = '2026-05-26T00:00:00.000Z';
const String _kUserCatalogAllocationActor =
    'restage-codegen-user-catalog-allocator';

/// The result of allocating stable wire IDs for a generated user catalog.
final class UserCatalogAllocation {
  /// Creates an allocation result.
  const UserCatalogAllocation({
    required this.catalog,
    required this.newEvents,
  });

  /// The catalog with real widget/property wire IDs.
  final Catalog catalog;

  /// Events minted during this allocation pass.
  final List<WireIdEvent> newEvents;
}

/// Allocates stable package-root wire IDs for generated customer widgets.
///
/// The package-root `wire_ids.events.jsonl` is treated as one append-only
/// source of truth for the generated `user_catalog.g.dart` surface. Entries
/// replay by exact source/name match; a rename or source move therefore mints
/// a new ID unless the log is explicitly edited with a rename event.
UserCatalogAllocation allocateUserCatalogFromWidgets({
  required String package,
  required List<WidgetEntry> widgets,
  List<StructuredEntry> structuredTypes = const [],
  List<UnionEntry> unions = const [],
  Map<String, String> slotTargets = const {},
  Map<String, int> stampedCapabilityVersions = const {},
  List<PropertyExclusion> exclusions = const [],
  Iterable<WireIdEvent> existingEvents = const [],
}) {
  // A structured type shared by multiple widget files is discovered once per
  // file (same `sourceType`, distinct entry objects); the cross-file
  // aggregation concatenates them. Dedup by `sourceType` so a shared type gets
  // exactly ONE wire ID — otherwise it mints one per referencing file (refs
  // collapse to the last) and the seed replay throws on the duplicate source
  // key on the next build.
  final dedupedStructured = _dedupeStructuredBySourceType(structuredTypes);
  final baseCatalog = userCatalogFromGraph(
    exclusions: exclusions,
    widgets: widgets,
    structuredTypes: dedupedStructured,
    unions: unions,
    stampedCapabilityVersions: stampedCapabilityVersions,
  );
  final allocator = WireIdAllocator(
    library: package,
    at: _kUserCatalogAllocationTimestamp,
    by: _kUserCatalogAllocationActor,
    existingEvents: existingEvents,
  );
  final seeded = allocator.currentState;
  final seededWidgets = _indexBy(
    seeded.widgets.values,
    (entry) => (entry.name!, entry.source!),
    (key) => 'widget name=${key.$1} source=${key.$2}',
  );
  final seededProperties = _indexBy(
    seeded.properties.values,
    (entry) => (entry.owner!, entry.name!, entry.source!),
    (key) => 'property owner=${key.$1.value} name=${key.$2} source=${key.$3}',
  );
  // Structured seed indices. The customer codegen path keys structured entries
  // SOURCE-INCLUSIVELY (by `sourceType`), consistent with its own
  // source-inclusive widget/property replay model — NOT the built-in backfill's
  // name-only key. Name-only would collide two same-name customer data classes
  // in different files onto one wire ID (a rebuild crash / mis-render); keying
  // by the unique sourceType gives them distinct IDs and both render, and a
  // source move forks a new ID exactly as a widget source move already does.
  // Fields/variants/parameters stay owner-keyed — their owning structured ID is
  // already source-disambiguated, so no collision reaches them.
  final seededStructured = _indexBy(
    seeded.structuredTypes.values,
    (entry) => entry.source!,
    (key) => 'structured source=$key',
  );
  final seededStructuredFields = _indexBy(
    seeded.properties.values.where(
      (e) => e.owner != null && e.owner!.kind == WireIdKind.structured,
    ),
    (entry) => (entry.owner!, entry.name!),
    (key) => 'structured field owner=${key.$1.value} name=${key.$2}',
  );
  final seededVariants = _indexBy(
    seeded.variants.values,
    (entry) => (
      entry.owner!,
      entry.sourceKind!,
      entry.namedConstructor,
      entry.staticAccessor,
    ),
    (key) => 'variant owner=${key.$1.value} kind=${key.$2.name} '
        'named=${key.$3} static=${key.$4}',
  );
  final seededParameters = _indexBy(
    seeded.parameters.values,
    (entry) => (entry.owner!, entry.name!),
    (key) => 'parameter owner=${key.$1.value} name=${key.$2}',
  );

  final newEvents = <WireIdEvent>[];
  final allocatedWidgets = <WidgetEntry>[];
  for (final widget in baseCatalog.widgets) {
    final widgetId = _resolveOrAllocateWidget(
      allocator: allocator,
      seededWidgets: seededWidgets,
      widget: widget,
      newEvents: newEvents,
    );
    allocatedWidgets.add(
      _copyWidget(
        widget,
        wireId: widgetId,
        properties: [
          for (final property in widget.properties)
            _copyProperty(
              property,
              wireId: _resolveOrAllocateProperty(
                allocator: allocator,
                seededProperties: seededProperties,
                widget: widget,
                property: property,
                owner: widgetId,
                newEvents: newEvents,
              ),
            ),
        ],
      ),
    );
  }

  // Structured allocation runs STRICTLY AFTER all widget/property allocation:
  // structured fields allocate as `WireIdKind.property` (the shared `p*`
  // counter), so appending them here continues past the existing widget
  // properties without shifting any existing `w*`/`p*` id (byte-neutral).
  final allocatedStructured = <StructuredEntry>[];
  for (final structured in baseCatalog.structuredTypes) {
    final structuredId = _resolveOrAllocateStructured(
      allocator: allocator,
      seededStructured: seededStructured,
      structured: structured,
      newEvents: newEvents,
    );
    final fields = [
      for (final field in structured.fields)
        _copyStructuredField(
          field,
          wireId: _resolveOrAllocateStructuredField(
            allocator: allocator,
            seededStructuredFields: seededStructuredFields,
            structured: structured,
            field: field,
            owner: structuredId,
            newEvents: newEvents,
          ),
        ),
    ];
    final variants = [
      for (final variant in structured.variants)
        _resolveOrAllocateVariant(
          allocator: allocator,
          seededVariants: seededVariants,
          seededParameters: seededParameters,
          structured: structured,
          variant: variant,
          owner: structuredId,
          newEvents: newEvents,
        ),
    ];
    allocatedStructured.add(
      _copyStructured(
        structured,
        wireId: structuredId,
        fields: fields,
        variants: variants,
      ),
    );
  }

  // Ref resolution runs after ALL structured entries have real IDs: each
  // structured slot's bare `unallocatedStructured` sentinel is rewritten to the
  // allocated ref of the type it targets (via `slotTargets`), and each
  // variant's `argMappings.targetFields` to the allocated field IDs. A target
  // is not in the allocated set is a dangling ref — resolve-or-exclude-loud —
  // and throws loud here rather than emitting an unresolved catalog.
  final refBySourceType = <String, WireIdRef>{
    for (final structured in allocatedStructured)
      structured.sourceType: WireIdRef(
        library: structured.library.namespace,
        wireId: structured.wireId,
      ),
  };
  final resolvedWidgets = [
    for (final widget in allocatedWidgets)
      _resolveWidgetRefs(
        widget,
        slotTargets: slotTargets,
        refBySourceType: refBySourceType,
      ),
  ];
  final resolvedStructured = [
    for (final structured in allocatedStructured)
      _resolveStructuredRefs(
        structured,
        slotTargets: slotTargets,
        refBySourceType: refBySourceType,
      ),
  ];

  return UserCatalogAllocation(
    catalog: Catalog(
      schemaVersion: baseCatalog.schemaVersion,
      generatedAt: baseCatalog.generatedAt,
      libraries: baseCatalog.libraries,
      widgets: resolvedWidgets,
      structuredTypes: resolvedStructured,
      unions: baseCatalog.unions,
      designTokens: baseCatalog.designTokens,
      flutterVersion: baseCatalog.flutterVersion,
      compatRules: baseCatalog.compatRules,
      exclusions: baseCatalog.exclusions,
    ),
    newEvents: List.unmodifiable(newEvents),
  );
}

/// Reads a package-root `wire_ids.events.jsonl` event log for [package].
Future<RootEventLogContents?> readRootEventLog(
  BuildStep buildStep,
  String package,
) async {
  final eventLog = AssetId(package, 'wire_ids.events.jsonl');
  if (await buildStep.canRead(eventLog)) {
    return RootEventLogContents(
      contents: await buildStep.readAsString(eventLog),
      sourceDescription: '${eventLog.package}|${eventLog.path}',
    );
  }

  final root = await _packageRoot(package);
  if (root == null) return null;
  final file = File.fromUri(root.resolve('wire_ids.events.jsonl'));
  if (!file.existsSync()) return null;
  return RootEventLogContents(
    contents: file.readAsStringSync(),
    sourceDescription: file.path,
  );
}

/// Appends generated customer catalog allocation [events] to the package root.
Future<void> appendEventsToRootEventLog({
  required String package,
  required Iterable<WireIdEvent> events,
  bool createIfMissing = false,
}) async {
  final root = await _packageRoot(package);
  if (root == null) return;
  final file = File.fromUri(root.resolve('wire_ids.events.jsonl'));
  if (file.existsSync()) {
    appendWireIdEventsSync(file, events);
    return;
  }
  if (createIfMissing) {
    writeWireIdEventLogSync(file, events);
  }
}

/// Holds the raw JSONL text and a human-readable parse source label.
final class RootEventLogContents {
  /// Creates root event-log contents.
  const RootEventLogContents({
    required this.contents,
    required this.sourceDescription,
  });

  /// Raw JSONL text.
  final String contents;

  /// Parse source label used in error messages.
  final String sourceDescription;
}

WireId _resolveOrAllocateWidget({
  required WireIdAllocator allocator,
  required Map<(String, String), WireIdEntryState> seededWidgets,
  required WidgetEntry widget,
  required List<WireIdEvent> newEvents,
}) {
  if (!widget.wireId.isUnallocated) {
    _requireSeeded(allocator, widget.wireId);
    return widget.wireId;
  }
  final seeded = seededWidgets[(widget.name, widget.flutterType)];
  if (seeded != null) return seeded.id;
  final event = allocator.allocate(
    WireIdAllocationCandidate.widget(
      name: widget.name,
      source: widget.flutterType,
    ),
  );
  newEvents.add(event);
  return event.id;
}

WireId _resolveOrAllocateProperty({
  required WireIdAllocator allocator,
  required Map<(WireId, String, String), WireIdEntryState> seededProperties,
  required WidgetEntry widget,
  required PropertyEntry property,
  required WireId owner,
  required List<WireIdEvent> newEvents,
}) {
  if (!property.wireId.isUnallocated) {
    _requireSeeded(allocator, property.wireId);
    return property.wireId;
  }
  final source = '${widget.flutterType}.${property.name}';
  final seeded = seededProperties[(owner, property.name, source)];
  if (seeded != null) return seeded.id;
  final event = allocator.allocate(
    WireIdAllocationCandidate.property(
      owner: owner,
      name: property.name,
      source: source,
    ),
  );
  newEvents.add(event);
  return event.id;
}

/// Keeps the first structured entry per `sourceType`. A shared customer data
/// class is discovered once per referencing widget file, so the aggregated
/// input can carry the same `sourceType` more than once; those entries are
/// identical (same class, same lowering), so first-wins is safe.
List<StructuredEntry> _dedupeStructuredBySourceType(
  List<StructuredEntry> structuredTypes,
) {
  final bySourceType = <String, StructuredEntry>{};
  for (final structured in structuredTypes) {
    bySourceType.putIfAbsent(structured.sourceType, () => structured);
  }
  return bySourceType.values.toList();
}

WireId _resolveOrAllocateStructured({
  required WireIdAllocator allocator,
  required Map<String, WireIdEntryState> seededStructured,
  required StructuredEntry structured,
  required List<WireIdEvent> newEvents,
}) {
  if (!structured.wireId.isUnallocated) {
    _requireSeeded(allocator, structured.wireId);
    return structured.wireId;
  }
  // Source-inclusive identity: reuse by the unique `sourceType`, so two
  // same-name customer data classes in different files get distinct IDs.
  final seeded = seededStructured[structured.sourceType];
  if (seeded != null) return seeded.id;
  final event = allocator.allocate(
    WireIdAllocationCandidate.structured(
      name: structured.name,
      source: structured.sourceType,
    ),
  );
  newEvents.add(event);
  return event.id;
}

WireId _resolveOrAllocateStructuredField({
  required WireIdAllocator allocator,
  required Map<(WireId, String), WireIdEntryState> seededStructuredFields,
  required StructuredEntry structured,
  required StructuredField field,
  required WireId owner,
  required List<WireIdEvent> newEvents,
}) {
  if (!field.wireId.isUnallocated) {
    _requireSeeded(allocator, field.wireId);
    return field.wireId;
  }
  final seeded = seededStructuredFields[(owner, field.name)];
  if (seeded != null) return seeded.id;
  // Structured fields draw from the same `property` counter as widget
  // properties (they share the `p*` namespace), owned by the structured entry.
  final event = allocator.allocate(
    WireIdAllocationCandidate.property(
      owner: owner,
      name: field.name,
      source: '${structured.sourceType}.${field.name}',
    ),
  );
  newEvents.add(event);
  return event.id;
}

FactoryVariant _resolveOrAllocateVariant({
  required WireIdAllocator allocator,
  required Map<(WireId, VariantSourceKind, String?, String?), WireIdEntryState>
      seededVariants,
  required Map<(WireId, String), WireIdEntryState> seededParameters,
  required StructuredEntry structured,
  required FactoryVariant variant,
  required WireId owner,
  required List<WireIdEvent> newEvents,
}) {
  final variantId = _resolveOrAllocateVariantId(
    allocator: allocator,
    seededVariants: seededVariants,
    structured: structured,
    variant: variant,
    owner: owner,
    newEvents: newEvents,
  );
  final parameters = [
    for (final parameter in factoryVariantCallableFields(variant).parameters)
      _copyParameter(
        parameter,
        wireId: _resolveOrAllocateParameter(
          allocator: allocator,
          seededParameters: seededParameters,
          structured: structured,
          variant: variant,
          parameter: parameter,
          owner: variantId,
          newEvents: newEvents,
        ),
      ),
  ];
  return _copyVariant(variant, wireId: variantId, parameters: parameters);
}

WireId _resolveOrAllocateVariantId({
  required WireIdAllocator allocator,
  required Map<(WireId, VariantSourceKind, String?, String?), WireIdEntryState>
      seededVariants,
  required StructuredEntry structured,
  required FactoryVariant variant,
  required WireId owner,
  required List<WireIdEvent> newEvents,
}) {
  if (!variant.wireId.isUnallocated) {
    _requireSeeded(allocator, variant.wireId);
    return variant.wireId;
  }
  final sourceKind = factoryVariantSourceKind(variant);
  final namedConstructor =
      variant is ConstructorVariant ? variant.namedConstructor : null;
  final staticAccessor = _staticAccessorOf(variant);
  final seeded =
      seededVariants[(owner, sourceKind, namedConstructor, staticAccessor)];
  if (seeded != null) return seeded.id;
  final event = allocator.allocate(
    WireIdAllocationCandidate.variant(
      owner: owner,
      sourceKind: sourceKind,
      namedConstructor: namedConstructor,
      staticAccessor: staticAccessor,
      source: _variantSource(structured, variant),
    ),
  );
  newEvents.add(event);
  return event.id;
}

WireId _resolveOrAllocateParameter({
  required WireIdAllocator allocator,
  required Map<(WireId, String), WireIdEntryState> seededParameters,
  required StructuredEntry structured,
  required FactoryVariant variant,
  required FactoryParameter parameter,
  required WireId owner,
  required List<WireIdEvent> newEvents,
}) {
  if (!parameter.wireId.isUnallocated) {
    _requireSeeded(allocator, parameter.wireId);
    return parameter.wireId;
  }
  final label = _parameterLabel(parameter);
  final seeded = seededParameters[(owner, label)];
  if (seeded != null) return seeded.id;
  final event = allocator.allocate(
    WireIdAllocationCandidate.parameter(
      owner: owner,
      name: label,
      source: _parameterSource(structured, variant, parameter),
    ),
  );
  newEvents.add(event);
  return event.id;
}

void _requireSeeded(WireIdAllocator allocator, WireId id) {
  if (!allocator.currentState.contains(id)) {
    throw WireIdReplayException(
      'catalog entry ${id.value} is already allocated but is missing from '
      'the seeded event log',
    );
  }
}

Map<K, WireIdEntryState> _indexBy<K>(
  Iterable<WireIdEntryState> entries,
  K Function(WireIdEntryState entry) keyOf,
  String Function(K key) describeDuplicate,
) {
  final result = <K, WireIdEntryState>{};
  for (final entry in entries) {
    final key = keyOf(entry);
    if (result.containsKey(key)) {
      throw WireIdReplayException(
        'event log contains multiple matches for ${describeDuplicate(key)}',
      );
    }
    result[key] = entry;
  }
  return result;
}

WidgetEntry _copyWidget(
  WidgetEntry widget, {
  required WireId wireId,
  required List<PropertyEntry> properties,
}) {
  return WidgetEntry(
    wireId: wireId,
    name: widget.name,
    library: widget.library,
    category: widget.category,
    description: widget.description,
    flutterType: widget.flutterType,
    childrenSlot: widget.childrenSlot,
    properties: properties,
    decomposes: widget.decomposes,
    sinceVersion: widget.sinceVersion,
    deprecatedSince: widget.deprecatedSince,
    stability: widget.stability,
    deprecated: widget.deprecated,
  );
}

/// Copies [property] with a new [wireId], optionally overriding the structured
/// reference / value shape (for the resolution pass). A `null` override keeps
/// the source value — the resolution helpers only ever pass a non-null override
/// (a resolved ref), or `null` precisely when the source itself is `null`, so a
/// `??` fallback is exact.
PropertyEntry _copyProperty(
  PropertyEntry property, {
  required WireId wireId,
  WireIdRef? structuredRef,
  CatalogValueShape? valueShape,
}) {
  return PropertyEntry(
    wireId: wireId,
    name: property.name,
    type: property.type,
    description: property.description,
    required: property.required,
    defaultBrandToken: property.defaultBrandToken,
    synthetic: property.synthetic,
    positional: property.positional,
    enumType: property.enumType,
    widgetType: property.widgetType,
    callbackSignature: property.callbackSignature,
    defaultSource: property.defaultSource,
    constructorNullable: property.constructorNullable,
    constructorDefault: property.constructorDefault,
    mutuallyExclusiveWith: property.mutuallyExclusiveWith,
    requiresAncestor: property.requiresAncestor,
    category: property.category,
    priority: property.priority,
    validationRule: property.validationRule,
    constraints: property.constraints,
    deprecated: property.deprecated,
    structuredRef: structuredRef ?? property.structuredRef,
    valueShape: valueShape ?? property.valueShape,
  );
}

/// Rewrites [widget]'s structured-property refs from their bare sentinels to
/// the allocated ref of the type each targets (via [slotTargets]).
WidgetEntry _resolveWidgetRefs(
  WidgetEntry widget, {
  required Map<String, String> slotTargets,
  required Map<String, WireIdRef> refBySourceType,
}) {
  final properties = [
    for (final property in widget.properties)
      if (isCustomerStructuredPropertySlot(property))
        _resolveStructuredSlot(
          property,
          slotKey: structuredSlotKey(widget.flutterType, property.name),
          slotTargets: slotTargets,
          refBySourceType: refBySourceType,
        )
      else
        property,
  ];
  return _copyWidget(widget, wireId: widget.wireId, properties: properties);
}

PropertyEntry _resolveStructuredSlot(
  PropertyEntry property, {
  required String slotKey,
  required Map<String, String> slotTargets,
  required Map<String, WireIdRef> refBySourceType,
}) {
  final ref = _resolveSlotRef(
    slotKey: slotKey,
    slotTargets: slotTargets,
    refBySourceType: refBySourceType,
  );
  return _copyProperty(
    property,
    wireId: property.wireId,
    structuredRef: _resolvedTopLevelRef(property.structuredRef, ref),
    valueShape: _resolveShapeRef(property.valueShape, ref),
  );
}

/// Rewrites [structured]'s nested-field refs + its variants' argMappings from
/// their bare sentinels to the allocated targets.
StructuredEntry _resolveStructuredRefs(
  StructuredEntry structured, {
  required Map<String, String> slotTargets,
  required Map<String, WireIdRef> refBySourceType,
}) {
  final fieldIdByName = {
    for (final field in structured.fields) field.name: field.wireId,
  };
  final fields = [
    for (final field in structured.fields)
      if (isCustomerStructuredFieldSlot(field))
        _resolveStructuredField(
          structured,
          field,
          slotTargets: slotTargets,
          refBySourceType: refBySourceType,
        )
      else
        field,
  ];
  final variants = [
    for (final variant in structured.variants)
      _resolveVariantArgMappings(variant, fieldIdByName),
  ];
  return _copyStructured(
    structured,
    wireId: structured.wireId,
    fields: fields,
    variants: variants,
  );
}

StructuredField _resolveStructuredField(
  StructuredEntry structured,
  StructuredField field, {
  required Map<String, String> slotTargets,
  required Map<String, WireIdRef> refBySourceType,
}) {
  final ref = _resolveSlotRef(
    slotKey: structuredSlotKey(structured.sourceType, field.name),
    slotTargets: slotTargets,
    refBySourceType: refBySourceType,
  );
  return _copyStructuredField(
    field,
    wireId: field.wireId,
    structuredRef: _resolvedTopLevelRef(field.structuredRef, ref),
    valueShape: _resolveShapeRef(field.valueShape, ref),
  );
}

/// The resolved ref for a top-level `structuredRef` slot: the target [ref] when
/// the current value is the bare sentinel (or absent-but-shaped), else the
/// current already-resolved ref unchanged.
WireIdRef? _resolvedTopLevelRef(WireIdRef? current, WireIdRef ref) {
  if (current == null) return null;
  return current.wireId.isUnallocated ? ref : current;
}

/// Rewrites a value shape's structured reference from the bare sentinel to
/// [ref]; recurses into a list shape's item. Scalar / enum / union shapes are
/// returned unchanged (unions are a later phase).
CatalogValueShape? _resolveShapeRef(CatalogValueShape? shape, WireIdRef ref) {
  if (shape == null) return null;
  return switch (shape) {
    ScalarShape() || EnumShape() || UnionShape() => shape,
    StructuredShape(:final structuredRef) => structuredRef.wireId.isUnallocated
        ? StructuredShape(
            propertyType: shape.propertyType,
            structuredRef: ref,
            wireCodec: shape.wireCodec,
          )
        : shape,
    ListShape(:final itemShape) => ListShape(
        propertyType: shape.propertyType,
        itemShape: _resolveShapeRef(itemShape, ref)!,
        wireCodec: shape.wireCodec,
      ),
  };
}

WireIdRef _resolveSlotRef({
  required String slotKey,
  required Map<String, String> slotTargets,
  required Map<String, WireIdRef> refBySourceType,
}) {
  final targetSourceType = slotTargets[slotKey];
  if (targetSourceType == null) {
    throw StateError(
      'Customer structured slot "$slotKey" has no recorded target; its '
      'structured reference cannot be resolved.',
    );
  }
  final ref = refBySourceType[targetSourceType];
  if (ref == null) {
    throw StateError(
      'Customer structured slot "$slotKey" targets "$targetSourceType", which '
      'is not in the allocated structured set (a dangling reference). The gate '
      'must exclude a widget whose closure reaches an unrenderable type.',
    );
  }
  return ref;
}

/// Rewrites a variant's `argMappings.targetFields` from bare sentinels to the
/// allocated field IDs. Canonical 1:1 mappings (param name == field name)
/// resolve to the same-named field; multi-field/splat or already-resolved
/// mappings pass through unchanged (the predicate excludes non-canonical
/// shapes, so an unmatched sentinel never reaches here for an admitted type).
FactoryVariant _resolveVariantArgMappings(
  FactoryVariant variant,
  Map<String, WireId> fieldIdByName,
) {
  final argMappings = factoryVariantCallableFields(variant).argMappings;
  if (argMappings.isEmpty) return variant;
  final resolved = <String, ArgMapping>{
    for (final entry in argMappings.entries)
      entry.key: _resolveArgMapping(entry.key, entry.value, fieldIdByName),
  };
  return _copyVariant(variant, argMappings: resolved);
}

ArgMapping _resolveArgMapping(
  String parameterName,
  ArgMapping mapping,
  Map<String, WireId> fieldIdByName,
) {
  if (mapping.targetFields.length == 1 &&
      mapping.targetFields.single.isUnallocated) {
    final fieldId = fieldIdByName[parameterName];
    if (fieldId != null) return ArgMapping(targetFields: [fieldId]);
  }
  return mapping;
}

StructuredEntry _copyStructured(
  StructuredEntry structured, {
  required WireId wireId,
  required List<StructuredField> fields,
  required List<FactoryVariant> variants,
}) {
  return StructuredEntry(
    wireId: wireId,
    name: structured.name,
    library: structured.library,
    description: structured.description,
    sourceType: structured.sourceType,
    fields: fields,
    variants: variants,
    stability: structured.stability,
    deprecated: structured.deprecated,
  );
}

StructuredField _copyStructuredField(
  StructuredField field, {
  required WireId wireId,
  WireIdRef? structuredRef,
  CatalogValueShape? valueShape,
}) {
  return StructuredField(
    wireId: wireId,
    name: field.name,
    type: field.type,
    description: field.description,
    required: field.required,
    defaultSource: field.defaultSource,
    category: field.category,
    priority: field.priority,
    deprecated: field.deprecated,
    structuredRef: structuredRef ?? field.structuredRef,
    unionRef: field.unionRef,
    valueShape: valueShape ?? field.valueShape,
  );
}

/// Reconstructs [variant] preserving its sealed subtype, overriding any of
/// [wireId] / [parameters] / [argMappings] that are provided (a `copyWith`
/// the schema value type lacks). The accessor kinds carry no parameters or
/// argMappings, so those overrides are ignored for them by construction.
FactoryVariant _copyVariant(
  FactoryVariant variant, {
  WireId? wireId,
  List<FactoryParameter>? parameters,
  Map<String, ArgMapping>? argMappings,
}) {
  final id = wireId ?? variant.wireId;
  switch (variant) {
    case ConstructorVariant(:final namedConstructor):
      return ConstructorVariant(
        wireId: id,
        namedConstructor: namedConstructor,
        argMappings: argMappings ?? variant.argMappings,
        parameters: parameters ?? variant.parameters,
        description: variant.description,
        deprecated: variant.deprecated,
      );
    case StaticMethodVariant(:final staticAccessor):
      return StaticMethodVariant(
        wireId: id,
        staticAccessor: staticAccessor,
        argMappings: argMappings ?? variant.argMappings,
        parameters: parameters ?? variant.parameters,
        description: variant.description,
        deprecated: variant.deprecated,
      );
    case StaticGetterVariant(:final staticAccessor):
      return StaticGetterVariant(
        wireId: id,
        staticAccessor: staticAccessor,
        description: variant.description,
        deprecated: variant.deprecated,
      );
    case ConstValueVariant(:final staticAccessor):
      return ConstValueVariant(
        wireId: id,
        staticAccessor: staticAccessor,
        description: variant.description,
        deprecated: variant.deprecated,
      );
  }
}

FactoryParameter _copyParameter(
  FactoryParameter parameter, {
  required WireId wireId,
}) {
  return FactoryParameter(
    wireId: wireId,
    name: parameter.name,
    position: parameter.position,
    kind: parameter.kind,
    required: parameter.required,
    nullable: parameter.nullable,
    defaultPolicy: parameter.defaultPolicy,
    defaultValue: parameter.defaultValue,
    valueShape: parameter.valueShape,
  );
}

String? _staticAccessorOf(FactoryVariant variant) => switch (variant) {
      ConstructorVariant() => null,
      StaticMethodVariant(:final staticAccessor) ||
      StaticGetterVariant(:final staticAccessor) ||
      ConstValueVariant(:final staticAccessor) =>
        staticAccessor,
    };

/// The advisory source string recorded on a variant's alloc event — the
/// structured type's sourceType plus the variant's accessor suffix (matching
/// the compiler allocator's convention). Advisory only; identity is the shape.
String _variantSource(StructuredEntry structured, FactoryVariant variant) {
  final suffix = switch (variant) {
    ConstructorVariant(:final namedConstructor) => namedConstructor ?? '',
    StaticMethodVariant(:final staticAccessor) => staticAccessor,
    StaticGetterVariant(:final staticAccessor) => staticAccessor,
    ConstValueVariant(:final staticAccessor) => staticAccessor,
  };
  return suffix.isEmpty
      ? '${structured.sourceType}.'
      : '${structured.sourceType}.$suffix';
}

/// The parameter's identity label — its name, else its positional index, else
/// a stable fallback (matching the compiler allocator's convention).
String _parameterLabel(FactoryParameter parameter) {
  final name = parameter.name;
  if (name != null && name.isNotEmpty) return name;
  final position = parameter.position;
  if (position != null) return position.toString();
  return 'parameter';
}

String _parameterSource(
  StructuredEntry structured,
  FactoryVariant variant,
  FactoryParameter parameter,
) {
  final variantSource = _variantSource(structured, variant);
  final label = _parameterLabel(parameter);
  return variantSource.endsWith('.')
      ? '$variantSource$label'
      : '$variantSource.$label';
}

Future<Uri?> _packageRoot(String package) async {
  final packageConfigUri = await Isolate.packageConfig;
  if (packageConfigUri == null) return null;
  final config = await loadPackageConfigUri(packageConfigUri);
  final packageConfig = config[package];
  if (packageConfig == null || !packageConfig.root.isScheme('file')) {
    return null;
  }
  return packageConfig.root;
}
