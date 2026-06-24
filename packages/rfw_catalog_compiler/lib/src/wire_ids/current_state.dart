import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:rfw_catalog_compiler/src/wire_ids/_validators.dart' as v;
import 'package:rfw_catalog_compiler/src/wire_ids/events.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Error thrown when event replay violates wire-ID invariants.
final class WireIdReplayException implements Exception {
  /// Creates a replay exception.
  const WireIdReplayException(this.message);

  /// Human-readable failure reason.
  final String message;

  @override
  String toString() => 'WireIdReplayException: $message';
}

/// Materialized current-state entry produced by replay.
@immutable
final class WireIdEntryState {
  /// Creates an immutable entry state.
  const WireIdEntryState({
    required this.id,
    required this.kind,
    required this.deprecated,
    this.name,
    this.source,
    this.owner,
    this.sourceKind,
    this.namedConstructor,
    this.staticAccessor,
    this.tokenType,
    this.resolver,
    this.literalFallback,
    this.description,
    this.stability = 'volatile',
    this.members = const [],
    this.deprecationReason,
    this.deprecationAt,
    this.predecessor,
    this.successor,
    this.replacementTransition,
  });

  /// Wire ID for this entry.
  final WireId id;

  /// Kind represented by [id].
  final WireIdKind kind;

  /// Advisory display name, where the entry kind has one.
  final String? name;

  /// Advisory source path, where the entry kind has one.
  final String? source;

  /// Owner for properties, variants, and parameters.
  final WireId? owner;

  /// Variant source kind.
  final VariantSourceKind? sourceKind;

  /// Constructor name for constructor variants.
  final String? namedConstructor;

  /// Static member name for non-constructor variants.
  final String? staticAccessor;

  /// Design-token value type.
  final String? tokenType;

  /// Design-token resolver payload.
  final Map<String, Object?>? resolver;

  /// Design-token literal fallback.
  final Object? literalFallback;

  /// Design-token description.
  final String? description;

  /// Design-token stability tier.
  final String stability;

  /// Union member references.
  final List<WireIdRef> members;

  /// Whether the entry is catalog-deprecated.
  final bool deprecated;

  /// Deprecation reason, when [deprecated] is true.
  final String? deprecationReason;

  /// Deprecation timestamp, when [deprecated] is true.
  final String? deprecationAt;

  /// Replacement predecessor reference.
  final WireIdRef? predecessor;

  /// Replacement successor reference.
  final WireIdRef? successor;

  /// Transition identifier for [predecessor] or [successor].
  final String? replacementTransition;

  /// Converts this entry to the derived current-state JSON value.
  Map<String, Object?> toJson() {
    final json = <String, Object?>{};
    switch (kind) {
      case WireIdKind.widget:
      case WireIdKind.structured:
        json
          ..['name'] = name
          ..['source'] = source;
      case WireIdKind.property:
        json
          ..['owner'] = owner?.value
          ..['name'] = name
          ..['source'] = source;
      case WireIdKind.parameter:
        json
          ..['owner'] = owner?.value
          ..['name'] = name
          ..['source'] = source;
      case WireIdKind.variant:
        json
          ..['owner'] = owner?.value
          ..['sourceKind'] = sourceKind?.name;
        if (namedConstructor != null ||
            sourceKind == VariantSourceKind.constructor) {
          json['namedConstructor'] = namedConstructor;
        }
        if (staticAccessor != null) json['staticAccessor'] = staticAccessor;
        json['source'] = source;
      case WireIdKind.union:
        json
          ..['name'] = name
          ..['source'] = source
          ..['members'] = members.map(_wireIdRefToJson).toList();
      case WireIdKind.designToken:
        json
          ..['name'] = name
          ..['tokenType'] = tokenType;
        if (resolver != null) json['resolver'] = resolver;
        if (literalFallback != null) {
          json['literalFallback'] = literalFallback;
        }
        if (description != null) json['description'] = description;
        json['stability'] = stability;
    }

    json['deprecated'] = deprecated;
    if (deprecationReason != null || deprecationAt != null) {
      json['deprecation'] = {
        if (deprecationAt != null) 'at': deprecationAt,
        if (deprecationReason != null) 'reason': deprecationReason,
      };
    }
    if (predecessor != null) {
      json['predecessor'] = _wireIdRefToJson(predecessor!);
    }
    if (successor != null) json['successor'] = _wireIdRefToJson(successor!);
    if (replacementTransition != null) {
      json['transition'] = replacementTransition;
    }
    return json;
  }
}

/// Per-library materialized view derived from a wire-ID event log.
@immutable
final class WireIdCurrentState {
  /// Creates a current-state snapshot.
  const WireIdCurrentState({
    required this.library,
    required this.generatedAt,
    required this.widgets,
    required this.properties,
    required this.structuredTypes,
    required this.variants,
    required this.parameters,
    required this.unions,
    required this.designTokens,
  });

  /// Library namespace.
  final String library;

  /// Timestamp used for this derived artifact.
  final String generatedAt;

  /// Widget entries by wire ID.
  final Map<WireId, WireIdEntryState> widgets;

  /// Property and structured-field entries by wire ID.
  final Map<WireId, WireIdEntryState> properties;

  /// Structured entries by wire ID.
  final Map<WireId, WireIdEntryState> structuredTypes;

  /// Variant entries by wire ID.
  final Map<WireId, WireIdEntryState> variants;

  /// Factory-parameter entries by wire ID.
  final Map<WireId, WireIdEntryState> parameters;

  /// Union entries by wire ID.
  final Map<WireId, WireIdEntryState> unions;

  /// Design-token entries by wire ID.
  final Map<WireId, WireIdEntryState> designTokens;

  /// Resolves a wire ID in this current state.
  WireIdEntryState? resolve(WireId id) {
    return switch (id.kind) {
      WireIdKind.widget => widgets[id],
      WireIdKind.property => properties[id],
      WireIdKind.structured => structuredTypes[id],
      WireIdKind.variant => variants[id],
      WireIdKind.parameter => parameters[id],
      WireIdKind.union => unions[id],
      WireIdKind.designToken => designTokens[id],
    };
  }

  /// Whether [id] exists in this current state.
  bool contains(WireId id) => resolve(id) != null;

  /// Highest allocated sequence observed for [kind].
  int highestSequence(WireIdKind kind) {
    final entries = switch (kind) {
      WireIdKind.widget => widgets,
      WireIdKind.property => properties,
      WireIdKind.structured => structuredTypes,
      WireIdKind.variant => variants,
      WireIdKind.parameter => parameters,
      WireIdKind.union => unions,
      WireIdKind.designToken => designTokens,
    };
    var highest = 0;
    for (final id in entries.keys) {
      if (id.sequence > highest) highest = id.sequence;
    }
    return highest;
  }

  /// Converts this state to deterministic current-state JSON.
  Map<String, Object?> toJson() => {
        'library': library,
        'generatedAt': generatedAt,
        'widgets': _entryMapToJson(widgets),
        'properties': _entryMapToJson(properties),
        'structuredTypes': _entryMapToJson(structuredTypes),
        'variants': _entryMapToJson(variants),
        'parameters': _entryMapToJson(parameters),
        'unions': _entryMapToJson(unions),
        'designTokens': _entryMapToJson(designTokens),
      };
}

/// Replays one library's event stream into a materialized current state.
WireIdCurrentState replayWireIdEvents({
  required String library,
  required Iterable<WireIdEvent> events,
  String? generatedAt,
  Map<String, WireIdCurrentState> externalStates = const {},
}) {
  final builder = WireIdReplayBuilder(
    library: library,
    externalStates: externalStates,
  );
  String? lastAt;
  for (final event in events) {
    lastAt = event.at;
    builder.apply(event);
  }
  return builder.freeze(
    generatedAt: generatedAt ?? lastAt ?? '1970-01-01T00:00:00Z',
  );
}

/// Encodes a current-state snapshot as pretty deterministic JSON.
String encodeWireIdCurrentStateJson(WireIdCurrentState state) =>
    const JsonEncoder.withIndent('  ').convert(state.toJson());

/// Writes a derived `wire_ids.current.json` file.
void writeWireIdCurrentStateSync(File file, WireIdCurrentState state) {
  file.writeAsStringSync(
    '${encodeWireIdCurrentStateJson(state)}\n',
    flush: true,
  );
}

Map<String, Object?> _entryMapToJson(
  Map<WireId, WireIdEntryState> entries,
) {
  final sorted = SplayTreeMap<String, Object?>();
  for (final entry in entries.entries) {
    sorted[entry.key.value] = entry.value.toJson();
  }
  return sorted;
}

Map<String, Object?> _wireIdRefToJson(WireIdRef ref) => {
      'library': ref.library,
      'id': ref.wireId.value,
    };

/// Incremental builder for wire-ID current-state replay.
///
/// Maintains the in-progress entry maps as events are applied so callers
/// that allocate iteratively (e.g. an allocator appending one event at
/// a time) avoid the cost of replaying the whole event log on each step.
/// Snapshot the materialized [WireIdCurrentState] via [freeze].
final class WireIdReplayBuilder {
  /// Creates a replay builder for [library], with cross-library lookups
  /// resolved through [externalStates].
  WireIdReplayBuilder({
    required this.library,
    required this.externalStates,
  });

  /// Library namespace this builder is replaying into.
  final String library;

  /// Other libraries' frozen states, consulted for cross-library
  /// references (`addMember`, etc.).
  final Map<String, WireIdCurrentState> externalStates;

  final _widgets = <WireId, _EntryBuilder>{};
  final _properties = <WireId, _EntryBuilder>{};
  final _structuredTypes = <WireId, _EntryBuilder>{};
  final _variants = <WireId, _EntryBuilder>{};
  final _parameters = <WireId, _EntryBuilder>{};
  final _unions = <WireId, _EntryBuilder>{};
  final _designTokens = <WireId, _EntryBuilder>{};
  final _highestByKind = <WireIdKind, int>{
    for (final kind in WireIdKind.values) kind: 0,
  };
  final _memberships = <String>{};

  /// Highest sequence allocated so far for [kind], or `0` when no
  /// allocation has happened yet.
  int highestSequence(WireIdKind kind) => _highestByKind[kind] ?? 0;

  /// Whether the builder has applied an allocation for [id]. Mirrors
  /// [WireIdCurrentState.contains] without forcing a freeze.
  bool contains(WireId id) => _resolveLocal(id) != null;

  /// Resolves [id] against the builder's in-progress state without
  /// freezing. Returns `null` when the id is unknown.
  WireIdEntryState? resolve(WireId id) => _resolveLocal(id)?.freeze();

  /// Applies [event] to the builder's in-progress state.
  void apply(WireIdEvent event) {
    v.validateCommonEventFields(
      at: event.at,
      by: event.by,
      kindName: event.kind.name,
      raise: WireIdReplayException.new,
    );
    switch (event) {
      case AllocWireIdEvent():
        _applyAlloc(event);
      case RenameWireIdEvent():
        _applyRename(event);
      case DeprecateWireIdEvent():
        _applyDeprecate(event);
      case ReplaceWireIdEvent():
        _applyReplace(event);
      case AddMemberWireIdEvent():
        _applyAddMember(event);
      case UpdateTokenWireIdEvent():
        _applyUpdateToken(event);
    }
  }

  /// Materializes the builder's in-progress state into an immutable
  /// snapshot stamped with [generatedAt].
  WireIdCurrentState freeze({required String generatedAt}) {
    return WireIdCurrentState(
      library: library,
      generatedAt: generatedAt,
      widgets: _freezeMap(_widgets),
      properties: _freezeMap(_properties),
      structuredTypes: _freezeMap(_structuredTypes),
      variants: _freezeMap(_variants),
      parameters: _freezeMap(_parameters),
      unions: _freezeMap(_unions),
      designTokens: _freezeMap(_designTokens),
    );
  }

  void _applyAlloc(AllocWireIdEvent event) {
    final id = event.id;
    _validateId(id, event.type, 'alloc.id');
    if (_resolveLocal(id) != null) {
      throw WireIdReplayException('duplicate alloc for ${id.value}');
    }
    final highest = _highestByKind[event.type]!;
    if (id.sequence <= highest) {
      throw WireIdReplayException(
        'alloc ${id.value} is out of order for '
        '${wireIdKindToEventType(event.type)}; '
        'highest prior sequence is $highest',
      );
    }

    final entry = switch (event.type) {
      WireIdKind.widget => _EntryBuilder(
          id: id,
          kind: event.type,
          name: v.requireNonEmpty(
            event.name,
            'alloc.name',
            WireIdReplayException.new,
          ),
          source: v.requireNonEmpty(
            event.source,
            'alloc.source',
            WireIdReplayException.new,
          ),
        ),
      WireIdKind.property => _buildPropertyAlloc(event),
      WireIdKind.structured => _EntryBuilder(
          id: id,
          kind: event.type,
          name: v.requireNonEmpty(
            event.name,
            'alloc.name',
            WireIdReplayException.new,
          ),
          source: v.requireNonEmpty(
            event.source,
            'alloc.source',
            WireIdReplayException.new,
          ),
        ),
      WireIdKind.variant => _buildVariantAlloc(event),
      WireIdKind.parameter => _buildParameterAlloc(event),
      WireIdKind.union => _EntryBuilder(
          id: id,
          kind: event.type,
          name: v.requireNonEmpty(
            event.name,
            'alloc.name',
            WireIdReplayException.new,
          ),
          source: v.requireNonEmpty(
            event.source,
            'alloc.source',
            WireIdReplayException.new,
          ),
        ),
      WireIdKind.designToken => _buildTokenAlloc(event),
    };
    _highestByKind[event.type] = id.sequence;
    _mapFor(event.type)[id] = entry;
  }

  _EntryBuilder _buildPropertyAlloc(AllocWireIdEvent event) {
    final owner = _requiredWireId(event.owner, 'alloc.owner');
    final ownerEntry = _resolveLocalOrThrow(owner, 'alloc.owner');
    if (ownerEntry.kind != WireIdKind.widget &&
        ownerEntry.kind != WireIdKind.structured) {
      throw WireIdReplayException(
        'property owner ${owner.value} must be a widget or structured entry',
      );
    }
    return _EntryBuilder(
      id: event.id,
      kind: event.type,
      owner: owner,
      name: v.requireNonEmpty(
        event.name,
        'alloc.name',
        WireIdReplayException.new,
      ),
      source: v.requireNonEmpty(
        event.source,
        'alloc.source',
        WireIdReplayException.new,
      ),
    );
  }

  _EntryBuilder _buildVariantAlloc(AllocWireIdEvent event) {
    final owner = _requiredWireId(event.owner, 'alloc.owner');
    final ownerEntry = _resolveLocalOrThrow(owner, 'alloc.owner');
    if (ownerEntry.kind != WireIdKind.structured) {
      throw WireIdReplayException(
        'variant owner ${owner.value} must be a structured entry',
      );
    }
    final sourceKind = event.sourceKind;
    if (sourceKind == null) {
      throw const WireIdReplayException('variant alloc requires sourceKind');
    }
    if (sourceKind == VariantSourceKind.constructor) {
      if (event.staticAccessor != null) {
        throw const WireIdReplayException(
          'constructor variant must not carry staticAccessor',
        );
      }
      if (event.namedConstructor != null && event.namedConstructor!.isEmpty) {
        throw const WireIdReplayException(
          'constructor variant namedConstructor must be non-empty or null',
        );
      }
    } else if (event.staticAccessor == null ||
        event.staticAccessor!.isEmpty ||
        event.namedConstructor != null) {
      throw const WireIdReplayException(
        'non-constructor variant requires staticAccessor only',
      );
    }
    return _EntryBuilder(
      id: event.id,
      kind: event.type,
      owner: owner,
      sourceKind: sourceKind,
      namedConstructor: event.namedConstructor,
      staticAccessor: event.staticAccessor,
      source: v.requireNonEmpty(
        event.source,
        'alloc.source',
        WireIdReplayException.new,
      ),
    );
  }

  _EntryBuilder _buildParameterAlloc(AllocWireIdEvent event) {
    final owner = _requiredWireId(event.owner, 'alloc.owner');
    final ownerEntry = _resolveLocalOrThrow(owner, 'alloc.owner');
    if (ownerEntry.kind != WireIdKind.variant) {
      throw WireIdReplayException(
        'parameter owner ${owner.value} must be a variant entry',
      );
    }
    return _EntryBuilder(
      id: event.id,
      kind: event.type,
      owner: owner,
      name: v.requireNonEmpty(
        event.name,
        'alloc.name',
        WireIdReplayException.new,
      ),
      source: v.requireNonEmpty(
        event.source,
        'alloc.source',
        WireIdReplayException.new,
      ),
    );
  }

  _EntryBuilder _buildTokenAlloc(AllocWireIdEvent event) {
    final resolver = event.resolver.isPresent ? event.resolver.value : null;
    if (resolver != null) {
      v.validateResolverShape(resolver, WireIdReplayException.new);
    }
    final literalFallback =
        event.literalFallback.isPresent ? event.literalFallback.value : null;
    final stability = event.stability ?? 'volatile';
    final tokenType = v.requireNonEmpty(
      event.tokenType,
      'alloc.tokenType',
      WireIdReplayException.new,
    );
    v.validateTokenType(tokenType, WireIdReplayException.new);
    v.validateLiteralFallback(
      tokenType,
      literalFallback,
      WireIdReplayException.new,
    );
    v.validateStability(stability, WireIdReplayException.new);
    if (resolver == null && literalFallback == null) {
      throw WireIdReplayException(
        'design token ${event.id.value} must have resolver or literalFallback',
      );
    }
    return _EntryBuilder(
      id: event.id,
      kind: event.type,
      name: v.requireNonEmpty(
        event.name,
        'alloc.name',
        WireIdReplayException.new,
      ),
      tokenType: tokenType,
      resolver: _copyJsonMap(resolver),
      literalFallback: literalFallback,
      description: event.description,
      stability: stability,
    );
  }

  void _applyRename(RenameWireIdEvent event) {
    _validateId(event.id, event.type, 'rename.id');
    if (event.from == event.to) {
      throw const WireIdReplayException('rename must change the label');
    }
    if (event.type == WireIdKind.designToken) {
      if (event.source != null ||
          event.fromSource != null ||
          event.toSource != null) {
        throw const WireIdReplayException(
          'design-token rename must not carry source fields',
        );
      }
    } else {
      final annotationRename = event.source != null;
      final sourceRename = event.fromSource != null || event.toSource != null;
      if (annotationRename == sourceRename) {
        throw const WireIdReplayException(
          'rename requires either source or fromSource + toSource, '
          'exclusively',
        );
      }
      if (sourceRename &&
          (event.fromSource == null || event.toSource == null)) {
        throw const WireIdReplayException(
          'source rename requires both fromSource and toSource',
        );
      }
    }
    final entry = _resolveLocalOrThrow(event.id, 'rename.id');
    if (entry.kind != event.type) {
      throw WireIdReplayException(
        'rename ${event.id.value} targets ${entry.kind.name}, not '
        '${event.type.name}',
      );
    }
    final currentLabel = _entryLabel(entry);
    if (currentLabel != event.from) {
      throw WireIdReplayException(
        'rename ${event.id.value} expected current label ${event.from}, '
        'found ${currentLabel ?? '<none>'}',
      );
    }

    if (event.source != null && entry.source != event.source) {
      throw WireIdReplayException(
        'rename ${event.id.value} source mismatch: expected '
        '${event.source}, found ${entry.source}',
      );
    }
    if (event.fromSource != null) {
      if (entry.source != event.fromSource) {
        throw WireIdReplayException(
          'source rename ${event.id.value} expected source '
          '${event.fromSource}, found ${entry.source}',
        );
      }
    }

    if (event.type == WireIdKind.variant) {
      if (entry.sourceKind == VariantSourceKind.constructor) {
        entry.namedConstructor = event.to;
      } else {
        entry.staticAccessor = event.to;
      }
    } else {
      entry.name = event.to;
    }

    if (event.type == WireIdKind.designToken) return;
    if (event.fromSource != null) entry.source = event.toSource;
  }

  void _applyDeprecate(DeprecateWireIdEvent event) {
    _validateId(event.id, event.type, 'deprecate.id');
    final entry = _resolveLocalOrThrow(event.id, 'deprecate.id');
    if (entry.kind != event.type) {
      throw WireIdReplayException(
        'deprecate ${event.id.value} targets ${entry.kind.name}, not '
        '${event.type.name}',
      );
    }
    entry
      ..deprecated = true
      ..deprecationReason = event.reason
      ..deprecationAt = event.at;
  }

  void _applyReplace(ReplaceWireIdEvent event) {
    _validateId(event.from, event.type, 'replace.from');
    _validateId(event.to, event.type, 'replace.to');
    if (event.from == event.to) {
      throw const WireIdReplayException(
        'replace endpoints must be different IDs',
      );
    }
    if (!v.isValidTransitionId(event.transition)) {
      throw const WireIdReplayException(
        'transition must use the tx* positive sequence namespace',
      );
    }
    final from = _resolveLocalOrThrow(event.from, 'replace.from');
    final to = _resolveLocalOrThrow(event.to, 'replace.to');
    if (from.kind != event.type || to.kind != event.type) {
      throw WireIdReplayException(
        'replace endpoints must both be ${event.type.name} entries',
      );
    }
    if (from.successor != null && from.successor!.wireId != event.to) {
      throw WireIdReplayException(
        'replace ${event.from.value} already has successor '
        '${from.successor!.wireId.value}',
      );
    }
    if (to.predecessor != null && to.predecessor!.wireId != event.from) {
      throw WireIdReplayException(
        'replace ${event.to.value} already has predecessor '
        '${to.predecessor!.wireId.value}',
      );
    }
    from
      ..successor = WireIdRef(library: library, wireId: event.to)
      ..replacementTransition = event.transition;
    to
      ..predecessor = WireIdRef(library: library, wireId: event.from)
      ..replacementTransition = event.transition;
  }

  void _applyAddMember(AddMemberWireIdEvent event) {
    final target = _resolveRefOrThrow(event.target, 'addMember.target');
    final member = _resolveRefOrThrow(event.member, 'addMember.member');
    if (target.kind != WireIdKind.union) {
      throw WireIdReplayException(
        'addMember target ${event.target} must resolve to a union',
      );
    }
    if (member.kind != WireIdKind.structured) {
      throw WireIdReplayException(
        'addMember member ${event.member} must resolve to a structured entry',
      );
    }
    final key = '${event.target.library}:${event.target.wireId.value}->'
        '${event.member.library}:${event.member.wireId.value}';
    if (!_memberships.add(key)) {
      throw WireIdReplayException('duplicate addMember for $key');
    }
    if (event.target.library == library) {
      _resolveLocalOrThrow(event.target.wireId, 'addMember.target')
          .members
          .add(event.member);
    }
  }

  void _applyUpdateToken(UpdateTokenWireIdEvent event) {
    _validateId(event.id, WireIdKind.designToken, 'updateToken.id');
    if (!event.hasPatch) {
      throw const WireIdReplayException(
        'updateToken requires at least one mutable field',
      );
    }
    final entry = _resolveLocalOrThrow(event.id, 'updateToken.id');
    if (entry.kind != WireIdKind.designToken) {
      throw WireIdReplayException(
        'updateToken ${event.id.value} must target a design token',
      );
    }

    var resolver = entry.resolver;
    var literalFallback = entry.literalFallback;
    var description = entry.description;
    var stability = entry.stability;
    var changed = false;

    if (event.resolver.isPresent) {
      final value = event.resolver.value;
      if (value != null) {
        v.validateResolverShape(value, WireIdReplayException.new);
      }
      changed = changed || !_jsonEquals(resolver, value);
      resolver = _copyJsonMap(value);
    }
    if (event.literalFallback.isPresent) {
      v.validateLiteralFallback(
        v.requireNonEmpty(
          entry.tokenType,
          'updateToken.tokenType',
          WireIdReplayException.new,
        ),
        event.literalFallback.value,
        WireIdReplayException.new,
      );
      changed =
          changed || !_jsonEquals(literalFallback, event.literalFallback.value);
      literalFallback = event.literalFallback.value;
    }
    if (event.description.isPresent) {
      changed = changed || description != event.description.value;
      description = event.description.value;
    }
    if (event.stability.isPresent) {
      final value = v.requireNonEmpty(
        event.stability.value,
        'updateToken.stability',
        WireIdReplayException.new,
      );
      v.validateStability(value, WireIdReplayException.new);
      changed = changed || stability != value;
      stability = value;
    }

    if (!changed) {
      throw WireIdReplayException(
        'updateToken ${event.id.value} must change at least one field',
      );
    }
    if (resolver == null && literalFallback == null) {
      throw WireIdReplayException(
        'updateToken ${event.id.value} would leave token unresolvable',
      );
    }

    entry
      ..resolver = resolver
      ..literalFallback = literalFallback
      ..description = description
      ..stability = stability;
  }

  Map<WireId, _EntryBuilder> _mapFor(WireIdKind kind) {
    return switch (kind) {
      WireIdKind.widget => _widgets,
      WireIdKind.property => _properties,
      WireIdKind.structured => _structuredTypes,
      WireIdKind.variant => _variants,
      WireIdKind.parameter => _parameters,
      WireIdKind.union => _unions,
      WireIdKind.designToken => _designTokens,
    };
  }

  _EntryBuilder? _resolveLocal(WireId id) => _mapFor(id.kind)[id];

  _EntryBuilder _resolveLocalOrThrow(WireId id, String path) {
    final entry = _resolveLocal(id);
    if (entry == null) {
      throw WireIdReplayException(
        '$path ${id.value} does not resolve to a prior local alloc',
      );
    }
    return entry;
  }

  WireIdEntryState _resolveRefOrThrow(WireIdRef ref, String path) {
    if (ref.library == library) {
      return _resolveLocalOrThrow(ref.wireId, path).freeze();
    }
    final state = externalStates[ref.library];
    final entry = state?.resolve(ref.wireId);
    if (entry == null) {
      throw WireIdReplayException(
        '$path $ref does not resolve to an allocated entry',
      );
    }
    return entry;
  }

  void _validateId(WireId id, WireIdKind expectedKind, String path) {
    if (id.isUnallocated) {
      throw WireIdReplayException(
        '$path ${id.value} is an internal sentinel ID',
      );
    }
    if (id.kind != expectedKind) {
      throw WireIdReplayException(
        '$path expected ${expectedKind.prefix}* but got ${id.value}',
      );
    }
  }
}

Map<WireId, WireIdEntryState> _freezeMap(Map<WireId, _EntryBuilder> source) {
  return Map<WireId, WireIdEntryState>.unmodifiable(
    source.map((key, value) => MapEntry(key, value.freeze())),
  );
}

String? _entryLabel(_EntryBuilder entry) {
  if (entry.kind != WireIdKind.variant) return entry.name;
  return entry.sourceKind == VariantSourceKind.constructor
      ? entry.namedConstructor
      : entry.staticAccessor;
}

WireId _requiredWireId(WireId? value, String path) {
  if (value == null) throw WireIdReplayException('$path is required');
  return value;
}

Map<String, Object?>? _copyJsonMap(Map<String, Object?>? value) {
  if (value == null) return null;
  return Map<String, Object?>.unmodifiable(SplayTreeMap.of(value));
}

bool _jsonEquals(Object? left, Object? right) {
  if (left is Map && right is Map) {
    if (left.length != right.length) return false;
    for (final key in left.keys) {
      if (!right.containsKey(key)) return false;
      if (!_jsonEquals(left[key], right[key])) return false;
    }
    return true;
  }
  if (left is List && right is List) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (!_jsonEquals(left[i], right[i])) return false;
    }
    return true;
  }
  return left == right;
}

final class _EntryBuilder {
  _EntryBuilder({
    required this.id,
    required this.kind,
    this.name,
    this.source,
    this.owner,
    this.sourceKind,
    this.namedConstructor,
    this.staticAccessor,
    this.tokenType,
    this.resolver,
    this.literalFallback,
    this.description,
    this.stability = 'volatile',
  });

  final WireId id;
  final WireIdKind kind;
  String? name;
  String? source;
  WireId? owner;
  VariantSourceKind? sourceKind;
  String? namedConstructor;
  String? staticAccessor;
  String? tokenType;
  Map<String, Object?>? resolver;
  Object? literalFallback;
  String? description;
  String stability;
  final members = <WireIdRef>[];
  bool deprecated = false;
  String? deprecationReason;
  String? deprecationAt;
  WireIdRef? predecessor;
  WireIdRef? successor;
  String? replacementTransition;

  WireIdEntryState freeze() {
    return WireIdEntryState(
      id: id,
      kind: kind,
      name: name,
      source: source,
      owner: owner,
      sourceKind: sourceKind,
      namedConstructor: namedConstructor,
      staticAccessor: staticAccessor,
      tokenType: tokenType,
      resolver: _copyJsonMap(resolver),
      literalFallback: literalFallback,
      description: description,
      stability: stability,
      members: List<WireIdRef>.unmodifiable(members),
      deprecated: deprecated,
      deprecationReason: deprecationReason,
      deprecationAt: deprecationAt,
      predecessor: predecessor,
      successor: successor,
      replacementTransition: replacementTransition,
    );
  }
}
