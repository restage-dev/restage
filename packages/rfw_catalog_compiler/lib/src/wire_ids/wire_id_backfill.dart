import 'package:rfw_catalog_compiler/src/adapter/restage_catalog_gen_adapter.dart';
import 'package:rfw_catalog_compiler/src/factory_variant_fields.dart';
import 'package:rfw_catalog_compiler/src/wire_ids/allocator.dart';
import 'package:rfw_catalog_compiler/src/wire_ids/current_state.dart';
import 'package:rfw_catalog_compiler/src/wire_ids/events.dart';
import 'package:rfw_catalog_compiler/src/wire_ids/union_source_key.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Actor recorded on the initial built-in catalog backfill events.
const String kBuiltInWireIdBackfillActor = 'rfw-catalog-compiler-phase-1';

/// Timestamp recorded on the initial built-in catalog backfill events.
const String kBuiltInWireIdBackfillTimestamp = '2026-05-11T19:00:00.000Z';

/// Replayed event-log resolver for restage_catalog_gen's adapter.
///
/// The resolver matches the current reflected catalog by advisory labels and
/// source names, then supplies the stable IDs from `wire_ids.events.jsonl`.
final class RestageCatalogGenEventLogWireIdResolver {
  /// Creates a resolver backed by [events].
  RestageCatalogGenEventLogWireIdResolver({
    required String library,
    required Iterable<WireIdEvent> events,
    String generatedAt = kBuiltInWireIdBackfillTimestamp,
  }) : this.fromState(
          replayWireIdEvents(
            library: library,
            events: events,
            generatedAt: generatedAt,
          ),
        );

  /// Creates a resolver backed by an already replayed [state].
  RestageCatalogGenEventLogWireIdResolver.fromState(this.state);

  /// Replayed current state used for lookups.
  final WireIdCurrentState state;

  /// Adapter hooks backed by [state].
  RestageCatalogGenWireIdHooks get hooks => RestageCatalogGenWireIdHooks(
        widget: resolveWidget,
        property: resolveProperty,
        decomposition: resolveDecomposition,
        structured: resolveStructured,
        union: resolveUnion,
      );

  /// Resolves a widget wire ID from the event log.
  ///
  /// Strict on the unallocated branch: a widget absent from the seeded event
  /// log raises [WireIdReplayException]. This suits the built-in
  /// pre-complete-log path — a built-in event log enumerates the entire
  /// built-in surface up front, so a missing widget is a genuine error and
  /// must fail loud. For the incremental library-import path use
  /// [resolveWidgetLenient] instead.
  WireId resolveWidget(WidgetEntry widget) {
    if (!widget.wireId.isUnallocated) {
      return _requireExisting(widget.wireId, WireIdKind.widget);
    }
    return _findWidget(widget).id;
  }

  /// Resolves a widget wire ID from the event log, lenient on a miss.
  ///
  /// Mirrors [resolveWidget] for the already-allocated branch — an entry
  /// carrying a real wire ID must still resolve against the seeded log — but
  /// is lenient on the unallocated branch: a widget absent from the log is a
  /// genuinely-new widget rather than an error, so its unallocated sentinel
  /// passes straight through for the downstream allocator to mint a fresh ID.
  ///
  /// This is the resolve for the library-import path, whose event log grows
  /// incrementally as widgets are added — unlike the built-in path's
  /// pre-complete log, where a missing widget is a real error and the strict
  /// [resolveWidget] is correct. The leniency here matches that of
  /// [resolveProperty] and [resolveStructured].
  ///
  /// Lookup is keyed by [WidgetEntry.name] — the same key the strict
  /// [_findWidget] uses and the same key [resolveProperty] uses for its owner
  /// lookup — so a lenient resolve of an *existing* widget yields exactly the
  /// wire ID the strict path would.
  ///
  /// Identity here is the catalog name: a widget whose `@RestageWidget` name
  /// has changed since its `alloc` is therefore seen as new — a fresh ID is
  /// minted and the prior ID is left unreferenced. Recognizing a rename as
  /// identity-preserving is not handled on this path.
  WireId resolveWidgetLenient(WidgetEntry widget) {
    if (!widget.wireId.isUnallocated) {
      return _requireExisting(widget.wireId, WireIdKind.widget);
    }
    return _widgetsByName[widget.name]?.id ?? widget.wireId;
  }

  /// Resolves a widget-property wire ID from the event log.
  ///
  /// Matches the lenient semantics of [_resolveStructuredField]: when a
  /// matching `(owner, name)` entry exists in the seeded event log this
  /// returns the recorded wire ID, otherwise the input's unallocated
  /// sentinel passes through so the downstream allocator can mint a fresh
  /// ID in catalog-declaration order. The widget owner is likewise looked
  /// up leniently: when the owning widget has no event-log match (e.g. a
  /// brand-new entry surfaced by the reflector), the property surfaces as
  /// unallocated for the allocator to mint.
  WireId resolveProperty(WidgetEntry widget, PropertyEntry property) {
    if (!property.wireId.isUnallocated) {
      return _requireExisting(property.wireId, WireIdKind.property);
    }
    final owner = _widgetsByName[widget.name]?.id;
    if (owner == null) return property.wireId;
    final match = _propertyByOwner[(owner, property.name)];
    return match?.id ?? property.wireId;
  }

  /// Resolves a standalone structured entry against the event log.
  ///
  /// Walker-emitted entries arrive with unallocated wire IDs on the entry,
  /// its fields, and its variants. When the event log already carries a
  /// matching structured entry (by name), this resolver patches every wire
  /// ID in place; fields and variants without a match keep their unallocated
  /// sentinels so the allocator can mint fresh IDs downstream. When the
  /// event log has no structured entry by [StructuredEntry.name], the
  /// resolver returns the input unchanged.
  StructuredEntry resolveStructured(StructuredEntry entry) {
    if (!entry.wireId.isUnallocated) {
      return entry;
    }
    final match = _structuredByName[entry.name];
    if (match == null) return entry;
    final structuredId = match.id;
    return StructuredEntry(
      wireId: structuredId,
      name: entry.name,
      library: entry.library,
      description: entry.description,
      sourceType: entry.sourceType,
      fields: [
        for (final field in entry.fields)
          _resolveStructuredField(structuredId, field),
      ],
      variants: [
        for (final variant in entry.variants)
          _resolveFactoryVariant(structuredId, variant),
      ],
      stability: entry.stability,
      deprecated: entry.deprecated,
    );
  }

  StructuredField _resolveStructuredField(
    WireId owner,
    StructuredField field,
  ) {
    if (!field.wireId.isUnallocated) return field;
    final match = _propertyByOwner[(owner, field.name)];
    if (match == null) return field;
    return StructuredField(
      wireId: match.id,
      name: field.name,
      type: field.type,
      description: field.description,
      required: field.required,
      defaultSource: field.defaultSource,
      category: field.category,
      priority: field.priority,
      deprecated: field.deprecated,
      structuredRef: field.structuredRef,
      unionRef: field.unionRef,
      valueShape: field.valueShape,
    );
  }

  FactoryVariant _resolveFactoryVariant(
    WireId owner,
    FactoryVariant variant,
  ) {
    final fields = factoryVariantFields(variant);
    if (!variant.wireId.isUnallocated) {
      _requireExisting(variant.wireId, WireIdKind.variant);
      return _copyFactoryVariant(
        variant,
        wireId: variant.wireId,
        parameters: [
          for (final parameter in fields.parameters)
            _resolveFactoryParameter(variant.wireId, parameter),
        ],
      );
    }
    final match = _variantByShape[(
      owner,
      factoryVariantSourceKind(variant),
      fields.namedConstructor,
      fields.staticAccessor,
    )];
    if (match == null) return variant;
    return _copyFactoryVariant(
      variant,
      wireId: match.id,
      parameters: [
        for (final parameter in fields.parameters)
          _resolveFactoryParameter(match.id, parameter),
      ],
    );
  }

  FactoryParameter _resolveFactoryParameter(
    WireId owner,
    FactoryParameter parameter,
  ) {
    if (!parameter.wireId.isUnallocated) {
      _requireExistingParameter(owner, parameter.wireId);
      return parameter;
    }
    final match = _parameterByOwner[(owner, _parameterLabel(parameter))];
    if (match == null) return parameter;
    return FactoryParameter(
      wireId: match.id,
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

  /// Reconstructs [variant] with a backfilled [wireId] and the [parameters]
  /// resolved by the caller, preserving its sealed subtype. The accessor kinds
  /// take no parameters (the resolved list is empty for them by construction).
  FactoryVariant _copyFactoryVariant(
    FactoryVariant variant, {
    required WireId wireId,
    required List<FactoryParameter> parameters,
  }) {
    switch (variant) {
      case ConstructorVariant(:final namedConstructor, :final argMappings):
        return ConstructorVariant(
          wireId: wireId,
          namedConstructor: namedConstructor,
          argMappings: argMappings,
          parameters: parameters,
          description: variant.description,
          deprecated: variant.deprecated,
        );
      case StaticMethodVariant(:final staticAccessor, :final argMappings):
        return StaticMethodVariant(
          wireId: wireId,
          staticAccessor: staticAccessor,
          argMappings: argMappings,
          parameters: parameters,
          description: variant.description,
          deprecated: variant.deprecated,
        );
      case StaticGetterVariant(:final staticAccessor):
        return StaticGetterVariant(
          wireId: wireId,
          staticAccessor: staticAccessor,
          description: variant.description,
          deprecated: variant.deprecated,
        );
      case ConstValueVariant(:final staticAccessor):
        return ConstValueVariant(
          wireId: wireId,
          staticAccessor: staticAccessor,
          description: variant.description,
          deprecated: variant.deprecated,
        );
    }
  }

  /// Resolves a discriminated-union entry against the event log.
  ///
  /// Walker-emitted unions arrive with an unallocated wire ID. A union is
  /// identified by its source key — `'<library>#<sourceType>'`, the same key
  /// the allocator records on the union's `alloc` event. When the event log
  /// already carries a matching union this resolver patches the union's
  /// wire ID in place; member and discriminator references keep their
  /// unallocated structured sentinels so the allocator re-derives them from
  /// `memberSourceTypes` (and the `addMember` replay then recognizes the
  /// existing memberships and emits nothing). When the event log has no
  /// matching union the resolver returns the input unchanged so the
  /// allocator can mint a fresh ID downstream.
  UnionEntry resolveUnion(UnionEntry entry) {
    if (!entry.wireId.isUnallocated) {
      return entry;
    }
    final match = _unionsBySource[unionSourceKey(entry)];
    if (match == null) return entry;
    return UnionEntry(
      wireId: match.id,
      name: entry.name,
      library: entry.library,
      description: entry.description,
      sourceType: entry.sourceType,
      memberSourceTypes: entry.memberSourceTypes,
      discriminator: entry.discriminator,
      members: entry.members,
      stability: entry.stability,
      deprecated: entry.deprecated,
    );
  }

  /// Leaves canonical v4 decomposition recipes unchanged.
  ///
  /// Recipe identity is now carried by canonical wire refs already present in
  /// the generated graph; this resolver only remains to satisfy the adapter
  /// hook shape.
  DecompositionRecipe resolveDecomposition(
    WidgetEntry _,
    DecompositionRecipe recipe,
  ) =>
      recipe;

  late final Map<String, WireIdEntryState> _widgetsByName = _indexBy(
    state.widgets.values,
    (entry) => entry.name!,
    (key) => 'widget $key',
  );

  late final Map<String, WireIdEntryState> _structuredByName = _indexBy(
    state.structuredTypes.values,
    (entry) => entry.name!,
    (key) => 'structured type $key',
  );

  late final Map<String, WireIdEntryState> _unionsBySource = _indexBy(
    state.unions.values,
    (entry) => entry.source!,
    (key) => 'union $key',
  );

  late final Map<(WireId, String), WireIdEntryState> _propertyByOwner =
      _indexBy(
    state.properties.values,
    (entry) => (entry.owner!, entry.name!),
    (key) => 'property owner=${key.$1.value} name=${key.$2}',
  );

  late final Map<(WireId, VariantSourceKind, String?, String?),
      WireIdEntryState> _variantByShape = _indexBy(
    state.variants.values,
    (entry) => (
      entry.owner!,
      entry.sourceKind!,
      entry.namedConstructor,
      entry.staticAccessor,
    ),
    (key) => 'variant owner=${key.$1.value} kind=${key.$2.name} '
        'namedConstructor=${key.$3} staticAccessor=${key.$4}',
  );

  late final Map<(WireId, String), WireIdEntryState> _parameterByOwner =
      _indexBy(
    state.parameters.values,
    (entry) => (entry.owner!, entry.name!),
    (key) => 'parameter owner=${key.$1.value} name=${key.$2}',
  );

  WireIdEntryState _findWidget(WidgetEntry widget) {
    final match = _widgetsByName[widget.name];
    if (match == null) {
      throw WireIdReplayException(
        'event log is missing widget ${widget.name} in the current catalog',
      );
    }
    return match;
  }

  WireId _requireExisting(WireId id, WireIdKind kind) {
    final entry = state.resolve(id);
    if (entry == null || entry.kind != kind) {
      throw WireIdReplayException(
        'wire ID ${id.value} is missing from ${state.library} event log',
      );
    }
    return id;
  }

  WireId _requireExistingParameter(WireId owner, WireId id) {
    final entry = state.resolve(id);
    if (entry == null || entry.kind != WireIdKind.parameter) {
      throw WireIdReplayException(
        'wire ID ${id.value} is missing from ${state.library} event log',
      );
    }
    if (entry.owner != owner) {
      throw WireIdReplayException(
        'parameter ${id.value} is owned by ${entry.owner?.value}, not '
        '${owner.value}',
      );
    }
    return id;
  }
}

/// Allocates the initial built-in wire-ID backfill for [catalog].
///
/// The walk is deterministic and idempotent against [existingEvents]:
/// widgets and widget properties are allocated in catalog declaration order,
/// followed by the current built-in structured surface, its fields, and
/// structured factory variants. Unions and design tokens are intentionally not
/// allocated by this built-in backfill.
List<WireIdEvent> backfillRestageCatalogWireIds({
  required Catalog catalog,
  required WidgetLibrary library,
  Iterable<WireIdEvent> existingEvents = const [],
  String at = kBuiltInWireIdBackfillTimestamp,
  String by = kBuiltInWireIdBackfillActor,
}) {
  final allocator = WireIdAllocator(
    library: library.namespace,
    at: at,
    by: by,
    existingEvents: existingEvents,
  );

  final widgets = catalog.widgetsIn(library);
  for (final widget in widgets) {
    final widgetId = _ensureWidget(allocator, widget);
    for (final property in widget.properties) {
      _ensureProperty(
        allocator,
        owner: widgetId,
        name: property.name,
        source: '${widget.flutterType}.${property.name}',
      );
    }
  }

  final structuredIds = <String, WireId>{};
  for (final structured in _builtInStructuredTypesFor(library)) {
    final structuredId = structuredIds.putIfAbsent(
      structured.name,
      () => _ensureStructured(
        allocator,
        name: structured.name,
        source: structured.sourceType,
      ),
    );
    for (final field in structured.fields) {
      _ensureProperty(
        allocator,
        owner: structuredId,
        name: field.name,
        source: '${structured.sourceType}.${field.name}',
      );
    }
    for (final variant in structured.variants) {
      _ensureVariant(
        allocator,
        owner: structuredId,
        structuredSource: structured.sourceType,
        variant: variant,
      );
    }
  }

  return allocator.events;
}

WireId _ensureWidget(WireIdAllocator allocator, WidgetEntry widget) {
  if (!widget.wireId.isUnallocated) {
    return _requireSeeded(allocator.currentState, widget.wireId);
  }
  final existing = _findExisting(
    allocator.currentState.widgets.values.where(
      (entry) => entry.name == widget.name,
    ),
    'widget ${widget.name}',
  );
  if (existing != null) return existing.id;
  return allocator
      .allocate(
        WireIdAllocationCandidate.widget(
          name: widget.name,
          source: widget.flutterType,
        ),
      )
      .id;
}

WireId _ensureStructured(
  WireIdAllocator allocator, {
  required String name,
  required String source,
}) {
  final existing = _findExisting(
    allocator.currentState.structuredTypes.values.where(
      (entry) => entry.name == name,
    ),
    'structured type $name',
  );
  if (existing != null) return existing.id;
  return allocator
      .allocate(
        WireIdAllocationCandidate.structured(name: name, source: source),
      )
      .id;
}

WireId _ensureProperty(
  WireIdAllocator allocator, {
  required WireId owner,
  required String name,
  required String source,
}) {
  final existing = _findExisting(
    allocator.currentState.properties.values.where(
      (entry) => entry.owner == owner && entry.name == name,
    ),
    'property $name',
  );
  if (existing != null) return existing.id;
  return allocator
      .allocate(
        WireIdAllocationCandidate.property(
          owner: owner,
          name: name,
          source: source,
        ),
      )
      .id;
}

WireId _ensureVariant(
  WireIdAllocator allocator, {
  required WireId owner,
  required String structuredSource,
  required _BuiltInVariant variant,
}) {
  final existing = _findExisting(
    allocator.currentState.variants.values.where(
      (entry) =>
          entry.owner == owner &&
          entry.sourceKind == variant.sourceKind &&
          entry.namedConstructor == variant.namedConstructor &&
          entry.staticAccessor == variant.staticAccessor,
    ),
    'variant ${_variantSource(structuredSource, variant)}',
  );
  if (existing != null) return existing.id;
  return allocator
      .allocate(
        WireIdAllocationCandidate.variant(
          owner: owner,
          sourceKind: variant.sourceKind,
          namedConstructor: variant.namedConstructor,
          staticAccessor: variant.staticAccessor,
          source: _variantSource(structuredSource, variant),
        ),
      )
      .id;
}

WireId _requireSeeded(WireIdCurrentState state, WireId id) {
  if (!state.contains(id)) {
    throw WireIdReplayException(
      'catalog entry ${id.value} is already allocated but is missing from '
      'the seeded event log',
    );
  }
  return id;
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

WireIdEntryState? _findExisting(
  Iterable<WireIdEntryState> entries,
  String label,
) {
  final matches = entries.toList(growable: false);
  if (matches.length > 1) {
    throw WireIdReplayException(
      'event log contains multiple matches for $label',
    );
  }
  return matches.isEmpty ? null : matches.single;
}

String _variantSource(String structuredSource, _BuiltInVariant variant) {
  final suffix = switch (variant.sourceKind) {
    VariantSourceKind.constructor => variant.namedConstructor ?? '',
    VariantSourceKind.staticMethod ||
    VariantSourceKind.staticGetter ||
    VariantSourceKind.constValue =>
      variant.staticAccessor ?? '',
  };
  return suffix.isEmpty ? '$structuredSource.' : '$structuredSource.$suffix';
}

String _parameterLabel(FactoryParameter parameter) {
  final name = parameter.name;
  if (name != null && name.isNotEmpty) return name;
  final position = parameter.position;
  if (position != null) return position.toString();
  return 'parameter';
}

List<_BuiltInStructuredType> _builtInStructuredTypesFor(WidgetLibrary library) {
  return switch (library) {
    WidgetLibrary.core => _coreBuiltInStructuredTypes,
    WidgetLibrary.material => _materialBuiltInStructuredTypes,
    WidgetLibrary.cupertino => const [],
    _ => const [],
  };
}

const _coreBuiltInStructuredTypes = [
  _BuiltInStructuredType(
    name: 'TextStyle',
    sourceType: 'package:flutter/src/painting/text_style.dart#TextStyle',
    fields: [
      _BuiltInStructuredField('fontSize'),
      _BuiltInStructuredField('fontWeight'),
      _BuiltInStructuredField('color'),
    ],
    variants: [
      _BuiltInVariant(),
    ],
  ),
  _BuiltInStructuredType(
    name: 'BoxDecoration',
    sourceType:
        'package:flutter/src/painting/box_decoration.dart#BoxDecoration',
    fields: [
      _BuiltInStructuredField('color'),
      _BuiltInStructuredField('borderRadius'),
      _BuiltInStructuredField('gradient'),
      _BuiltInStructuredField('border'),
      _BuiltInStructuredField('boxShadow'),
      _BuiltInStructuredField('shape'),
    ],
    variants: [
      _BuiltInVariant(),
    ],
  ),
  _BuiltInStructuredType(
    name: 'BorderRadius',
    sourceType: 'package:flutter/src/painting/border_radius.dart#BorderRadius',
    fields: [
      _BuiltInStructuredField('radius'),
    ],
    variants: [
      _BuiltInVariant(namedConstructor: 'circular'),
    ],
  ),
  _BuiltInStructuredType(
    name: 'EdgeInsets',
    sourceType: 'package:flutter/src/painting/edge_insets.dart#EdgeInsets',
    fields: [
      _BuiltInStructuredField('left'),
      _BuiltInStructuredField('top'),
      _BuiltInStructuredField('right'),
      _BuiltInStructuredField('bottom'),
    ],
    variants: [
      _BuiltInVariant(namedConstructor: 'fromLTRB'),
      _BuiltInVariant(namedConstructor: 'all'),
      _BuiltInVariant(namedConstructor: 'symmetric'),
      _BuiltInVariant(namedConstructor: 'only'),
    ],
  ),
  _BuiltInStructuredType(
    name: 'Border',
    sourceType: 'package:flutter/src/painting/box_border.dart#Border',
    fields: [
      _BuiltInStructuredField('top'),
      _BuiltInStructuredField('right'),
      _BuiltInStructuredField('bottom'),
      _BuiltInStructuredField('left'),
    ],
    variants: [
      _BuiltInVariant(),
      _BuiltInVariant(namedConstructor: 'all'),
    ],
  ),
  _BuiltInStructuredType(
    name: 'BorderSide',
    sourceType: 'package:flutter/src/painting/borders.dart#BorderSide',
    fields: [
      _BuiltInStructuredField('color'),
      _BuiltInStructuredField('width'),
      _BuiltInStructuredField('style'),
    ],
    variants: [
      _BuiltInVariant(),
    ],
  ),
  _BuiltInStructuredType(
    name: 'BoxShadow',
    sourceType: 'package:flutter/src/painting/box_shadow.dart#BoxShadow',
    fields: [
      _BuiltInStructuredField('color'),
      _BuiltInStructuredField('offset'),
      _BuiltInStructuredField('blurRadius'),
      _BuiltInStructuredField('spreadRadius'),
    ],
    variants: [
      _BuiltInVariant(),
    ],
  ),
  _BuiltInStructuredType(
    name: 'LinearGradient',
    sourceType: 'package:flutter/src/painting/gradient.dart#LinearGradient',
    fields: [
      _BuiltInStructuredField('begin'),
      _BuiltInStructuredField('end'),
      _BuiltInStructuredField('colors'),
      _BuiltInStructuredField('stops'),
    ],
    variants: [
      _BuiltInVariant(),
    ],
  ),
];

const _materialBuiltInStructuredTypes = [
  _BuiltInStructuredType(
    name: 'ButtonStyle',
    sourceType: 'package:flutter/src/material/button_style.dart#ButtonStyle',
    fields: [
      _BuiltInStructuredField('backgroundColor'),
      _BuiltInStructuredField('foregroundColor'),
      _BuiltInStructuredField('padding'),
      _BuiltInStructuredField('elevation'),
    ],
    variants: [
      _BuiltInVariant(
        sourceKind: VariantSourceKind.staticMethod,
        staticAccessor: 'styleFrom',
      ),
    ],
  ),
];

final class _BuiltInStructuredType {
  const _BuiltInStructuredType({
    required this.name,
    required this.sourceType,
    required this.fields,
    required this.variants,
  });

  final String name;
  final String sourceType;
  final List<_BuiltInStructuredField> fields;
  final List<_BuiltInVariant> variants;
}

final class _BuiltInStructuredField {
  const _BuiltInStructuredField(this.name);

  final String name;
}

final class _BuiltInVariant {
  const _BuiltInVariant({
    this.sourceKind = VariantSourceKind.constructor,
    this.namedConstructor,
    this.staticAccessor,
  });

  final VariantSourceKind sourceKind;

  final String? namedConstructor;

  final String? staticAccessor;
}
