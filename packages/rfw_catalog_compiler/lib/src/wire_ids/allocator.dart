import 'package:meta/meta.dart';
import 'package:rfw_catalog_compiler/src/factory_variant_fields.dart';
import 'package:rfw_catalog_compiler/src/wire_ids/current_state.dart';
import 'package:rfw_catalog_compiler/src/wire_ids/events.dart';
import 'package:rfw_catalog_compiler/src/wire_ids/union_source_key.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// A source/catalog entry that needs a wire ID allocation.
@immutable
final class WireIdAllocationCandidate {
  /// Creates a raw allocation candidate.
  const WireIdAllocationCandidate({
    required this.type,
    this.name,
    this.source,
    this.owner,
    this.sourceKind,
    this.namedConstructor,
    this.staticAccessor,
    this.tokenType,
    this.resolver = const WireIdEventField<Map<String, Object?>?>.absent(),
    this.literalFallback = const WireIdEventField<Object?>.absent(),
    this.description,
    this.stability,
  });

  /// Creates a widget allocation candidate.
  const WireIdAllocationCandidate.widget({
    required String name,
    required String source,
  }) : this(
          type: WireIdKind.widget,
          name: name,
          source: source,
        );

  /// Creates a property allocation candidate.
  const WireIdAllocationCandidate.property({
    required WireId owner,
    required String name,
    required String source,
  }) : this(
          type: WireIdKind.property,
          owner: owner,
          name: name,
          source: source,
        );

  /// Creates a structured-type allocation candidate.
  const WireIdAllocationCandidate.structured({
    required String name,
    required String source,
  }) : this(
          type: WireIdKind.structured,
          name: name,
          source: source,
        );

  /// Creates a factory-variant allocation candidate.
  const WireIdAllocationCandidate.variant({
    required WireId owner,
    required VariantSourceKind sourceKind,
    required String source,
    String? namedConstructor,
    String? staticAccessor,
  }) : this(
          type: WireIdKind.variant,
          owner: owner,
          sourceKind: sourceKind,
          namedConstructor: namedConstructor,
          staticAccessor: staticAccessor,
          source: source,
        );

  /// Creates a factory-parameter allocation candidate.
  const WireIdAllocationCandidate.parameter({
    required WireId owner,
    required String name,
    required String source,
  }) : this(
          type: WireIdKind.parameter,
          owner: owner,
          name: name,
          source: source,
        );

  /// Creates a union allocation candidate.
  const WireIdAllocationCandidate.union({
    required String name,
    required String source,
  }) : this(
          type: WireIdKind.union,
          name: name,
          source: source,
        );

  /// Creates a design-token allocation candidate.
  const WireIdAllocationCandidate.designToken({
    required String name,
    required String tokenType,
    WireIdEventField<Map<String, Object?>?> resolver =
        const WireIdEventField<Map<String, Object?>?>.absent(),
    WireIdEventField<Object?> literalFallback =
        const WireIdEventField<Object?>.absent(),
    String? description,
    String? stability,
  }) : this(
          type: WireIdKind.designToken,
          name: name,
          tokenType: tokenType,
          resolver: resolver,
          literalFallback: literalFallback,
          description: description,
          stability: stability,
        );

  /// Kind to allocate.
  final WireIdKind type;

  /// Advisory display name.
  final String? name;

  /// Source path for source-derived entries.
  final String? source;

  /// Owner for property, variant, and parameter entries.
  final WireId? owner;

  /// Variant source kind.
  final VariantSourceKind? sourceKind;

  /// Constructor name for constructor variants.
  final String? namedConstructor;

  /// Static member name for non-constructor variants.
  final String? staticAccessor;

  /// Design-token type string.
  final String? tokenType;

  /// Design-token resolver payload.
  final WireIdEventField<Map<String, Object?>?> resolver;

  /// Design-token literal fallback payload.
  final WireIdEventField<Object?> literalFallback;

  /// Design-token description.
  final String? description;

  /// Design-token stability tier.
  final String? stability;
}

/// Monotonic per-library wire-ID allocator.
///
/// The allocator validates the existing event stream, keeps independent
/// counters for each wire-ID kind, and appends candidate allocations in the
/// order they are provided.
final class WireIdAllocator {
  /// Creates an allocator seeded by [existingEvents].
  WireIdAllocator({
    required this.library,
    required this.at,
    required this.by,
    Iterable<WireIdEvent> existingEvents = const [],
    Map<String, WireIdCurrentState> externalStates = const {},
  })  : _events = List<WireIdEvent>.of(existingEvents),
        _builder = WireIdReplayBuilder(
          library: library,
          externalStates: externalStates,
        ) {
    _events.forEach(_builder.apply);
    _highestByKind = {
      for (final kind in WireIdKind.values)
        kind: _builder.highestSequence(kind),
    };
  }

  /// Library namespace this allocator writes into.
  final String library;

  /// Timestamp used for newly generated events.
  final String at;

  /// Actor identifier used for newly generated events.
  final String by;

  final List<WireIdEvent> _events;
  // Incremental replay state; each appended event applies to the builder
  // in O(1) rather than replaying the whole event stream on each step.
  final WireIdReplayBuilder _builder;
  late Map<WireIdKind, int> _highestByKind;
  WireIdCurrentState? _frozenState;

  /// Current state after all allocations made through this allocator.
  WireIdCurrentState get currentState =>
      _frozenState ??= _builder.freeze(generatedAt: at);

  /// Newly allocated and existing event stream.
  List<WireIdEvent> get events => List<WireIdEvent>.unmodifiable(_events);

  /// Allocates one candidate and returns the emitted event.
  AllocWireIdEvent allocate(WireIdAllocationCandidate candidate) {
    final id = _nextId(candidate.type);
    final event = AllocWireIdEvent(
      type: candidate.type,
      id: id,
      name: candidate.name,
      source: candidate.source,
      owner: candidate.owner,
      sourceKind: candidate.sourceKind,
      namedConstructor: candidate.namedConstructor,
      staticAccessor: candidate.staticAccessor,
      tokenType: candidate.tokenType,
      resolver: candidate.resolver,
      literalFallback: candidate.literalFallback,
      description: candidate.description,
      stability: candidate.stability,
      at: at,
      by: by,
    );
    _builder.apply(event);
    _events.add(event);
    _frozenState = null;
    _highestByKind[candidate.type] = id.sequence;
    return event;
  }

  /// Allocates all candidates in their iterable declaration order.
  List<AllocWireIdEvent> allocateAll(
    Iterable<WireIdAllocationCandidate> candidates,
  ) {
    final allocated = <AllocWireIdEvent>[];
    for (final candidate in candidates) {
      allocated.add(allocate(candidate));
    }
    return allocated;
  }

  /// Allocates unallocated sentinel IDs in catalog declaration order.
  ///
  /// The walk preserves the existing catalog order: widgets and their
  /// properties, structured types and their fields/variants, then unions, then
  /// design tokens. Entries already carrying real wire IDs must exist in the
  /// seeded event state.
  List<WireIdEvent> allocateCatalog(
    Catalog catalog,
    WidgetLibrary targetLibrary,
  ) {
    if (library != targetLibrary.namespace) {
      throw WireIdReplayException(
        'allocator library $library must match target library '
        '${targetLibrary.namespace}',
      );
    }
    final allocated = <WireIdEvent>[];
    for (final widget in catalog.widgets) {
      if (widget.library != targetLibrary) continue;
      final widgetId = _ensureWidget(widget, allocated);
      for (final property in widget.properties) {
        _ensureWidgetProperty(widget, property, widgetId, allocated);
      }
    }
    // Each structured type's source FQN maps to its allocated wire ID so
    // union members — which carry only their source FQN until this pass —
    // can be correlated to a real structured ID instead of a sentinel.
    final structuredIdsBySource = <String, WireId>{};
    for (final structured in catalog.structuredTypes) {
      if (structured.library != targetLibrary) continue;
      final structuredId = _ensureStructured(structured, allocated);
      structuredIdsBySource[structured.sourceType] = structuredId;
      for (final field in structured.fields) {
        _ensureStructuredField(structured, field, structuredId, allocated);
      }
      for (final variant in structured.variants) {
        final variantId = _ensureVariant(
          structured,
          variant,
          structuredId,
          allocated,
        );
        for (final parameter in factoryVariantFields(variant).parameters) {
          _ensureParameter(
            structured,
            variant,
            parameter,
            variantId,
            allocated,
          );
        }
      }
    }
    for (final union in catalog.unions) {
      if (union.library != targetLibrary) continue;
      final unionId = _ensureUnion(union, allocated);
      _ensureUnionMembers(union, unionId, structuredIdsBySource, allocated);
    }
    for (final token in catalog.designTokens) {
      if (token.library != targetLibrary) continue;
      _ensureToken(token, allocated);
    }
    return allocated;
  }

  WireId _nextId(WireIdKind kind) {
    final next = _highestByKind[kind]! + 1;
    return WireId('${kind.prefix}${next.toString().padLeft(4, '0')}');
  }

  WireId _ensureWidget(
    WidgetEntry widget,
    List<WireIdEvent> allocated,
  ) {
    if (!widget.wireId.isUnallocated) {
      _requireExisting(
        widget.wireId,
        WireIdKind.widget,
        'widget ${widget.name}.wireId',
      );
      return widget.wireId;
    }
    final event = allocate(
      WireIdAllocationCandidate.widget(
        name: widget.name,
        source: widget.flutterType,
      ),
    );
    allocated.add(event);
    return event.id;
  }

  void _ensureWidgetProperty(
    WidgetEntry widget,
    PropertyEntry property,
    WireId owner,
    List<WireIdEvent> allocated,
  ) {
    if (!property.wireId.isUnallocated) {
      _requireExistingOwned(
        property.wireId,
        WireIdKind.property,
        owner,
        'property ${widget.name}.${property.name}.wireId',
      );
      return;
    }
    allocated.add(
      allocate(
        WireIdAllocationCandidate.property(
          owner: owner,
          name: property.name,
          source: '${widget.flutterType}.${property.name}',
        ),
      ),
    );
  }

  WireId _ensureStructured(
    StructuredEntry structured,
    List<WireIdEvent> allocated,
  ) {
    if (!structured.wireId.isUnallocated) {
      _requireExisting(
        structured.wireId,
        WireIdKind.structured,
        'structured ${structured.name}.wireId',
      );
      return structured.wireId;
    }
    final event = allocate(
      WireIdAllocationCandidate.structured(
        name: structured.name,
        source: structured.sourceType,
      ),
    );
    allocated.add(event);
    return event.id;
  }

  void _ensureStructuredField(
    StructuredEntry structured,
    StructuredField field,
    WireId owner,
    List<WireIdEvent> allocated,
  ) {
    if (!field.wireId.isUnallocated) {
      _requireExistingOwned(
        field.wireId,
        WireIdKind.property,
        owner,
        'structured field ${structured.name}.${field.name}.wireId',
      );
      return;
    }
    allocated.add(
      allocate(
        WireIdAllocationCandidate.property(
          owner: owner,
          name: field.name,
          source: '${structured.sourceType}.${field.name}',
        ),
      ),
    );
  }

  WireId _ensureVariant(
    StructuredEntry structured,
    FactoryVariant variant,
    WireId owner,
    List<WireIdEvent> allocated,
  ) {
    if (!variant.wireId.isUnallocated) {
      _requireExistingOwned(
        variant.wireId,
        WireIdKind.variant,
        owner,
        'variant ${_variantSource(structured, variant)}.wireId',
      );
      return variant.wireId;
    }
    final fields = factoryVariantFields(variant);
    final event = allocate(
      WireIdAllocationCandidate.variant(
        owner: owner,
        sourceKind: factoryVariantSourceKind(variant),
        namedConstructor: fields.namedConstructor,
        staticAccessor: fields.staticAccessor,
        source: _variantSource(structured, variant),
      ),
    );
    allocated.add(event);
    return event.id;
  }

  void _ensureParameter(
    StructuredEntry structured,
    FactoryVariant variant,
    FactoryParameter parameter,
    WireId owner,
    List<WireIdEvent> allocated,
  ) {
    if (!parameter.wireId.isUnallocated) {
      _requireExistingOwned(
        parameter.wireId,
        WireIdKind.parameter,
        owner,
        'parameter ${_parameterSource(structured, variant, parameter)}.wireId',
      );
      return;
    }
    allocated.add(
      allocate(
        WireIdAllocationCandidate.parameter(
          owner: owner,
          name: _parameterLabel(parameter),
          source: _parameterSource(structured, variant, parameter),
        ),
      ),
    );
  }

  WireId _ensureUnion(
    UnionEntry union,
    List<WireIdEvent> allocated,
  ) {
    if (!union.wireId.isUnallocated) {
      _requireExisting(
        union.wireId,
        WireIdKind.union,
        'union ${union.name}.wireId',
      );
      return union.wireId;
    }
    final event = allocate(
      WireIdAllocationCandidate.union(
        name: union.name,
        source: unionSourceKey(union),
      ),
    );
    allocated.add(event);
    return event.id;
  }

  void _ensureUnionMembers(
    UnionEntry union,
    WireId unionId,
    Map<String, WireId> structuredIdsBySource,
    List<WireIdEvent> allocated,
  ) {
    if (union.members.length != union.memberSourceTypes.length) {
      throw WireIdReplayException(
        'union ${union.name} members.length (${union.members.length}) != '
        'memberSourceTypes.length (${union.memberSourceTypes.length})',
      );
    }
    final target = WireIdRef(
      library: union.library.namespace,
      wireId: unionId,
    );
    // Union member WireIdRefs carry the unallocated sentinel until this pass;
    // memberSourceTypes[i] is the FQN key that maps each member back to the
    // structured ID allocated above.
    for (var i = 0; i < union.members.length; i++) {
      final memberSource = union.memberSourceTypes[i];
      final memberId = structuredIdsBySource[memberSource];
      if (memberId == null) {
        throw WireIdReplayException(
          'union ${union.name} member $memberSource has no allocated '
          'structured entry',
        );
      }
      final memberRef = WireIdRef(
        library: union.library.namespace,
        wireId: memberId,
      );
      if (_hasMembership(target, memberRef)) continue;
      allocated.add(_appendAddMember(target: target, member: memberRef));
    }
  }

  void _ensureToken(
    DesignTokenEntry token,
    List<WireIdEvent> allocated,
  ) {
    if (!token.wireId.isUnallocated) {
      _requireExisting(
        token.wireId,
        WireIdKind.designToken,
        'design token ${token.name}.wireId',
      );
      return;
    }
    allocated.add(
      allocate(
        WireIdAllocationCandidate.designToken(
          name: token.name,
          tokenType: token.type.name,
          resolver: token.resolver == null
              ? const WireIdEventField<Map<String, Object?>?>.absent()
              : WireIdEventField<Map<String, Object?>?>.value(
                  _themeBindingToJson(token.resolver!),
                ),
          literalFallback: token.literalFallback == null
              ? const WireIdEventField<Object?>.absent()
              : WireIdEventField<Object?>.value(token.literalFallback),
          description: token.description,
          stability: token.stability.name,
        ),
      ),
    );
  }

  AddMemberWireIdEvent _appendAddMember({
    required WireIdRef target,
    required WireIdRef member,
  }) {
    final event = AddMemberWireIdEvent(
      target: target,
      member: member,
      at: at,
      by: by,
    );
    _builder.apply(event);
    _events.add(event);
    _frozenState = null;
    return event;
  }

  bool _hasMembership(WireIdRef target, WireIdRef member) {
    if (target.library != library) return false;
    final entry = _builder.resolve(target.wireId);
    if (entry == null || entry.kind != WireIdKind.union) return false;
    return entry.members.contains(member);
  }

  void _requireExisting(WireId id, WireIdKind expectedKind, String path) {
    if (id.kind != expectedKind) {
      throw WireIdReplayException(
        '$path expected ${expectedKind.prefix}* but got ${id.value}',
      );
    }
    if (!_builder.contains(id)) {
      throw WireIdReplayException(
        'catalog entry ${id.value} is already allocated but is missing from '
        'the seeded event log',
      );
    }
  }

  void _requireExistingOwned(
    WireId id,
    WireIdKind expectedKind,
    WireId owner,
    String path,
  ) {
    if (id.kind != expectedKind) {
      throw WireIdReplayException(
        '$path expected ${expectedKind.prefix}* but got ${id.value}',
      );
    }
    final entry = _builder.resolve(id);
    if (entry == null) {
      throw WireIdReplayException(
        'catalog entry ${id.value} is already allocated but is missing from '
        'the seeded event log',
      );
    }
    if (entry.owner != owner) {
      throw WireIdReplayException(
        '$path references ${id.value}, owned by ${entry.owner?.value}, '
        'not ${owner.value}',
      );
    }
  }
}

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

Map<String, Object?> _themeBindingToJson(ThemeBindingPath path) => {
      if (path.path != null) 'path': path.path,
      if (path.resolverName != null) 'resolverName': path.resolverName,
    };
