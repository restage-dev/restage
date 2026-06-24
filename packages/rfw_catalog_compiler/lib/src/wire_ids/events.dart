import 'dart:collection';
import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:rfw_catalog_compiler/src/wire_ids/_validators.dart' as v;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// One of the append-only wire-ID event verbs.
enum WireIdEventKind {
  /// Allocates a new wire ID.
  alloc,

  /// Renames a wire-ID-backed catalog entry.
  rename,

  /// Marks a catalog entry as deprecated.
  deprecate,

  /// Links an entry to its successor.
  replace,

  /// Adds a structured member to a union.
  addMember,

  /// Mutates design-token payload in place.
  updateToken,
}

/// Optional event field that preserves JSON field presence.
///
/// This is needed for token events where an omitted field means "leave it
/// alone", while an explicit `null` means "clear it".
@immutable
final class WireIdEventField<T> {
  /// Creates an absent field.
  const WireIdEventField.absent()
      : isPresent = false,
        value = null;

  /// Creates a present field whose value may be `null`.
  const WireIdEventField.value(this.value) : isPresent = true;

  /// Whether the field appeared in the source event.
  final bool isPresent;

  /// Field value when [isPresent] is true.
  final T? value;

  @override
  bool operator ==(Object other) =>
      other is WireIdEventField<T> &&
      other.isPresent == isPresent &&
      _jsonEquals(other.value, value);

  @override
  int get hashCode => Object.hash(isPresent, _jsonHash(value));
}

/// Error thrown when a wire-ID event is structurally invalid.
final class WireIdEventException implements Exception {
  /// Creates an event exception.
  const WireIdEventException(this.message, {this.lineNumber});

  /// Human-readable failure reason.
  final String message;

  /// One-based JSONL line number, when available.
  final int? lineNumber;

  @override
  String toString() {
    final line = lineNumber;
    if (line == null) return 'WireIdEventException: $message';
    return 'WireIdEventException: line $line: $message';
  }
}

/// Base type for all wire-ID event-log records.
@immutable
sealed class WireIdEvent {
  /// Creates a wire-ID event.
  const WireIdEvent({required this.at, required this.by});

  /// Event verb.
  WireIdEventKind get kind;

  /// ISO-8601 UTC timestamp string.
  final String at;

  /// Actor identifier.
  final String by;

  /// Converts this event to its strict JSON object shape.
  Map<String, Object?> toJson();
}

/// Event that allocates a new wire ID.
@immutable
final class AllocWireIdEvent extends WireIdEvent {
  /// Creates an allocation event.
  const AllocWireIdEvent({
    required this.type,
    required this.id,
    required super.at,
    required super.by,
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

  @override
  WireIdEventKind get kind => WireIdEventKind.alloc;

  /// Kind of entry being allocated.
  final WireIdKind type;

  /// Allocated wire ID.
  final WireId id;

  /// Advisory display name for non-variant entries.
  final String? name;

  /// Source path for source-derived entries.
  final String? source;

  /// Owner wire ID for property and variant allocations.
  final WireId? owner;

  /// Variant source kind for variant allocations.
  final VariantSourceKind? sourceKind;

  /// Constructor name for constructor variants.
  final String? namedConstructor;

  /// Static member name for non-constructor variants.
  final String? staticAccessor;

  /// Design-token value type.
  final String? tokenType;

  /// Optional token resolver payload.
  final WireIdEventField<Map<String, Object?>?> resolver;

  /// Optional token literal fallback payload.
  final WireIdEventField<Object?> literalFallback;

  /// Optional design-token description.
  final String? description;

  /// Optional design-token stability tier.
  final String? stability;

  @override
  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'kind': kind.name,
      'type': wireIdKindToEventType(type),
      'id': id.value,
    };

    switch (type) {
      case WireIdKind.widget:
      case WireIdKind.structured:
      case WireIdKind.union:
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
        if (sourceKind == VariantSourceKind.constructor) {
          json['namedConstructor'] = namedConstructor;
        } else {
          json['staticAccessor'] = staticAccessor;
        }
        json['source'] = source;
      case WireIdKind.designToken:
        json
          ..['name'] = name
          ..['tokenType'] = tokenType;
        if (resolver.isPresent) json['resolver'] = resolver.value;
        if (literalFallback.isPresent) {
          json['literalFallback'] = literalFallback.value;
        }
        if (description != null) json['description'] = description;
        if (stability != null) json['stability'] = stability;
    }

    json
      ..['at'] = at
      ..['by'] = by;
    return json;
  }
}

/// Event that renames an existing wire-ID-backed entry.
@immutable
final class RenameWireIdEvent extends WireIdEvent {
  /// Creates a rename event.
  const RenameWireIdEvent({
    required this.type,
    required this.id,
    required this.from,
    required this.to,
    required super.at,
    required super.by,
    this.source,
    this.fromSource,
    this.toSource,
  });

  @override
  WireIdEventKind get kind => WireIdEventKind.rename;

  /// Kind of entry being renamed.
  final WireIdKind type;

  /// Entry being renamed.
  final WireId id;

  /// Previous display label.
  final String from;

  /// New display label.
  final String to;

  /// Source path for annotation-renames.
  final String? source;

  /// Previous source path for source-renames.
  final String? fromSource;

  /// New source path for source-renames.
  final String? toSource;

  @override
  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'kind': kind.name,
      'type': wireIdKindToEventType(type),
      'id': id.value,
      'from': from,
      'to': to,
    };
    if (source != null) json['source'] = source;
    if (fromSource != null) json['fromSource'] = fromSource;
    if (toSource != null) json['toSource'] = toSource;
    json
      ..['at'] = at
      ..['by'] = by;
    return json;
  }
}

/// Event that marks an entry as deprecated.
@immutable
final class DeprecateWireIdEvent extends WireIdEvent {
  /// Creates a deprecation event.
  const DeprecateWireIdEvent({
    required this.type,
    required this.id,
    required this.reason,
    required super.at,
    required super.by,
  });

  @override
  WireIdEventKind get kind => WireIdEventKind.deprecate;

  /// Kind of entry being deprecated.
  final WireIdKind type;

  /// Entry being deprecated.
  final WireId id;

  /// Maintainer-supplied reason.
  final String reason;

  @override
  Map<String, Object?> toJson() => {
        'kind': kind.name,
        'type': wireIdKindToEventType(type),
        'id': id.value,
        'reason': reason,
        'at': at,
        'by': by,
      };
}

/// Event that links an entry to its successor.
@immutable
final class ReplaceWireIdEvent extends WireIdEvent {
  /// Creates a replacement event.
  const ReplaceWireIdEvent({
    required this.type,
    required this.from,
    required this.to,
    required this.transition,
    required super.at,
    required super.by,
  });

  @override
  WireIdEventKind get kind => WireIdEventKind.replace;

  /// Kind of both replacement endpoints.
  final WireIdKind type;

  /// Predecessor entry.
  final WireId from;

  /// Successor entry.
  final WireId to;

  /// Transition identifier, using the `tx*` namespace.
  final String transition;

  @override
  Map<String, Object?> toJson() => {
        'kind': kind.name,
        'type': wireIdKindToEventType(type),
        'from': from.value,
        'to': to.value,
        'transition': transition,
        'at': at,
        'by': by,
      };
}

/// Event that adds a structured member to a union.
@immutable
final class AddMemberWireIdEvent extends WireIdEvent {
  /// Creates a union-member event.
  const AddMemberWireIdEvent({
    required this.target,
    required this.member,
    required super.at,
    required super.by,
  });

  @override
  WireIdEventKind get kind => WireIdEventKind.addMember;

  /// Target union.
  final WireIdRef target;

  /// Structured member being added.
  final WireIdRef member;

  @override
  Map<String, Object?> toJson() => {
        'kind': kind.name,
        'type': wireIdKindToEventType(WireIdKind.union),
        'target': wireIdEventRefToJson(target),
        'member': wireIdEventRefToJson(member),
        'at': at,
        'by': by,
      };
}

/// Event that updates mutable design-token payload.
@immutable
final class UpdateTokenWireIdEvent extends WireIdEvent {
  /// Creates a token-update event.
  const UpdateTokenWireIdEvent({
    required this.id,
    required super.at,
    required super.by,
    this.resolver = const WireIdEventField<Map<String, Object?>?>.absent(),
    this.literalFallback = const WireIdEventField<Object?>.absent(),
    this.description = const WireIdEventField<String?>.absent(),
    this.stability = const WireIdEventField<String>.absent(),
  });

  @override
  WireIdEventKind get kind => WireIdEventKind.updateToken;

  /// Token being updated.
  final WireId id;

  /// Resolver patch; explicit `null` clears the resolver.
  final WireIdEventField<Map<String, Object?>?> resolver;

  /// Literal fallback patch; explicit `null` clears the fallback.
  final WireIdEventField<Object?> literalFallback;

  /// Description patch; explicit `null` clears the description.
  final WireIdEventField<String?> description;

  /// Stability patch.
  final WireIdEventField<String> stability;

  /// Whether this update carries at least one mutable-field patch.
  bool get hasPatch =>
      resolver.isPresent ||
      literalFallback.isPresent ||
      description.isPresent ||
      stability.isPresent;

  @override
  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'kind': kind.name,
      'id': id.value,
    };
    if (resolver.isPresent) json['resolver'] = resolver.value;
    if (literalFallback.isPresent) {
      json['literalFallback'] = literalFallback.value;
    }
    if (description.isPresent) json['description'] = description.value;
    if (stability.isPresent) json['stability'] = stability.value;
    json
      ..['at'] = at
      ..['by'] = by;
    return json;
  }
}

/// Converts a schema wire-ID kind to the event-log `type` string.
String wireIdKindToEventType(WireIdKind kind) {
  return switch (kind) {
    WireIdKind.widget => 'widget',
    WireIdKind.property => 'property',
    WireIdKind.structured => 'structured',
    WireIdKind.variant => 'variant',
    WireIdKind.union => 'union',
    WireIdKind.designToken => 'design_token',
    WireIdKind.parameter => 'parameter',
  };
}

/// Parses an event-log `type` string.
WireIdKind wireIdKindFromEventType(String value) {
  return switch (value) {
    'widget' => WireIdKind.widget,
    'property' => WireIdKind.property,
    'structured' => WireIdKind.structured,
    'variant' => WireIdKind.variant,
    'union' => WireIdKind.union,
    'design_token' => WireIdKind.designToken,
    'parameter' => WireIdKind.parameter,
    _ => throw WireIdEventException('unknown wire ID event type: $value'),
  };
}

/// Converts an event reference tuple to JSON.
Map<String, Object?> wireIdEventRefToJson(WireIdRef ref) => {
      'library': ref.library,
      'id': ref.wireId.value,
    };

/// Parses an event reference tuple from JSON.
WireIdRef wireIdEventRefFromJson(Object? raw, {int? lineNumber}) {
  final reader = _EventReader(
    _objectMap(raw, 'reference', lineNumber),
    lineNumber: lineNumber,
  )..expectOnly(const {'library', 'id'});
  final id = reader.readWireId('id');
  return WireIdRef(
    library: reader.readNonEmptyString('library'),
    wireId: id,
  );
}

/// Parses one wire-ID event from its JSON object representation.
WireIdEvent wireIdEventFromJson(
  Map<String, Object?> json, {
  int? lineNumber,
}) {
  final reader = _EventReader(json, lineNumber: lineNumber);
  final kind = _eventKindFromString(
    reader.readNonEmptyString('kind'),
    lineNumber: lineNumber,
  );
  return switch (kind) {
    WireIdEventKind.alloc => _allocFromJson(reader),
    WireIdEventKind.rename => _renameFromJson(reader),
    WireIdEventKind.deprecate => _deprecateFromJson(reader),
    WireIdEventKind.replace => _replaceFromJson(reader),
    WireIdEventKind.addMember => _addMemberFromJson(reader),
    WireIdEventKind.updateToken => _updateTokenFromJson(reader),
  };
}

/// Returns a deterministic JSON string for a single event.
String encodeWireIdEventJson(WireIdEvent event) {
  _validateTypedEvent(event);
  final json = event.toJson();
  wireIdEventFromJson(json);
  return jsonEncode(_canonicalJson(json));
}

void _validateTypedEvent(WireIdEvent event) {
  _validateTypedCommon(event);
  switch (event) {
    case AllocWireIdEvent():
      _validateTypedAlloc(event);
    case RenameWireIdEvent():
      _validateTypedRename(event);
    case DeprecateWireIdEvent():
      _validateTypedId(event.id, event.type, 'deprecate.id');
      v.requireNonEmpty(
        event.reason,
        'deprecate.reason',
        WireIdEventException.new,
      );
    case ReplaceWireIdEvent():
      _validateTypedId(event.from, event.type, 'replace.from');
      _validateTypedId(event.to, event.type, 'replace.to');
      if (event.from == event.to) {
        throw const WireIdEventException(
          'replace endpoints must be different IDs',
        );
      }
      if (!v.isValidTransitionId(event.transition)) {
        throw const WireIdEventException(
          'transition must use the tx* positive sequence namespace',
        );
      }
    case AddMemberWireIdEvent():
      _validateTypedRef(
        event.target,
        WireIdKind.union,
        'addMember.target',
      );
      _validateTypedRef(
        event.member,
        WireIdKind.structured,
        'addMember.member',
      );
    case UpdateTokenWireIdEvent():
      _validateTypedUpdateToken(event);
  }
}

void _validateTypedCommon(WireIdEvent event) {
  v.validateCommonEventFields(
    at: event.at,
    by: event.by,
    kindName: event.kind.name,
    raise: WireIdEventException.new,
  );
}

void _validateTypedAlloc(AllocWireIdEvent event) {
  _validateTypedId(event.id, event.type, 'alloc.id');
  switch (event.type) {
    case WireIdKind.widget:
    case WireIdKind.structured:
    case WireIdKind.union:
      v.requireNonEmpty(event.name, 'alloc.name', WireIdEventException.new);
      v.requireNonEmpty(event.source, 'alloc.source', WireIdEventException.new);
      _rejectUnusedAllocFields(
        event,
        allowed: const {'name', 'source'},
      );
    case WireIdKind.property:
      final owner = event.owner;
      if (owner == null) {
        throw const WireIdEventException('alloc.owner is required');
      }
      if (owner.kind != WireIdKind.widget &&
          owner.kind != WireIdKind.structured) {
        throw WireIdEventException(
          'property owner must be a widget or structured wire ID, '
          'got ${owner.value}',
        );
      }
      _validateTypedIdKindOnly(owner, 'alloc.owner');
      v.requireNonEmpty(event.name, 'alloc.name', WireIdEventException.new);
      v.requireNonEmpty(event.source, 'alloc.source', WireIdEventException.new);
      _rejectUnusedAllocFields(
        event,
        allowed: const {'owner', 'name', 'source'},
      );
    case WireIdKind.parameter:
      final owner = event.owner;
      if (owner == null) {
        throw const WireIdEventException('alloc.owner is required');
      }
      if (owner.kind != WireIdKind.variant) {
        throw WireIdEventException(
          'parameter owner must be a variant wire ID, got ${owner.value}',
        );
      }
      _validateTypedIdKindOnly(owner, 'alloc.owner');
      v.requireNonEmpty(event.name, 'alloc.name', WireIdEventException.new);
      v.requireNonEmpty(event.source, 'alloc.source', WireIdEventException.new);
      _rejectUnusedAllocFields(
        event,
        allowed: const {'owner', 'name', 'source'},
      );
    case WireIdKind.variant:
      _validateTypedVariantAlloc(event);
    case WireIdKind.designToken:
      _validateTypedTokenAlloc(event);
  }
}

void _validateTypedVariantAlloc(AllocWireIdEvent event) {
  final owner = event.owner;
  if (owner == null) {
    throw const WireIdEventException('alloc.owner is required');
  }
  _validateTypedId(owner, WireIdKind.structured, 'alloc.owner');
  final sourceKind = event.sourceKind;
  if (sourceKind == null) {
    throw const WireIdEventException('variant alloc requires sourceKind');
  }
  v.requireNonEmpty(event.source, 'alloc.source', WireIdEventException.new);
  switch (sourceKind) {
    case VariantSourceKind.constructor:
      if (event.staticAccessor != null) {
        throw const WireIdEventException(
          'constructor variant must not carry staticAccessor',
        );
      }
      if (event.namedConstructor != null) {
        v.requireNonEmpty(
          event.namedConstructor,
          'alloc.namedConstructor',
          WireIdEventException.new,
        );
      }
    case VariantSourceKind.staticMethod:
    case VariantSourceKind.staticGetter:
    case VariantSourceKind.constValue:
      if (event.namedConstructor != null) {
        throw const WireIdEventException(
          'non-constructor variant must not carry namedConstructor',
        );
      }
      v.requireNonEmpty(
        event.staticAccessor,
        'alloc.staticAccessor',
        WireIdEventException.new,
      );
  }
  _rejectUnusedAllocFields(
    event,
    allowed: const {
      'owner',
      'sourceKind',
      'namedConstructor',
      'staticAccessor',
      'source',
    },
  );
}

void _validateTypedTokenAlloc(AllocWireIdEvent event) {
  v.requireNonEmpty(event.name, 'alloc.name', WireIdEventException.new);
  final tokenType = v.requireNonEmpty(
    event.tokenType,
    'alloc.tokenType',
    WireIdEventException.new,
  );
  v.validateTokenType(tokenType, WireIdEventException.new);
  if (event.resolver.isPresent && event.resolver.value != null) {
    v.validateResolverShape(event.resolver.value!, WireIdEventException.new);
  }
  if (event.literalFallback.isPresent) {
    v.validateLiteralFallback(
      tokenType,
      event.literalFallback.value,
      WireIdEventException.new,
    );
  }
  if (event.resolver.value == null && event.literalFallback.value == null) {
    throw WireIdEventException(
      'design token ${event.id.value} must have resolver or literalFallback',
    );
  }
  if (event.description != null) {
    v.requireNonEmpty(
      event.description,
      'alloc.description',
      WireIdEventException.new,
    );
  }
  if (event.stability != null) {
    v.validateStability(event.stability!, WireIdEventException.new);
  }
  _rejectUnusedAllocFields(
    event,
    allowed: const {
      'name',
      'tokenType',
      'resolver',
      'literalFallback',
      'description',
      'stability',
    },
  );
}

void _validateTypedRename(RenameWireIdEvent event) {
  _validateTypedId(event.id, event.type, 'rename.id');
  v.requireNonEmpty(event.from, 'rename.from', WireIdEventException.new);
  v.requireNonEmpty(event.to, 'rename.to', WireIdEventException.new);
  if (event.from == event.to) {
    throw const WireIdEventException('rename must change the display label');
  }
  if (event.type == WireIdKind.designToken) {
    if (event.source != null ||
        event.fromSource != null ||
        event.toSource != null) {
      throw const WireIdEventException(
        'design-token rename must not carry source fields',
      );
    }
    return;
  }
  final annotationRename = event.source != null;
  final sourceRename = event.fromSource != null || event.toSource != null;
  if (annotationRename == sourceRename) {
    throw const WireIdEventException(
      'rename requires either source or fromSource + toSource, exclusively',
    );
  }
  if (event.source != null) {
    v.requireNonEmpty(event.source, 'rename.source', WireIdEventException.new);
  }
  if (sourceRename) {
    v.requireNonEmpty(
      event.fromSource,
      'rename.fromSource',
      WireIdEventException.new,
    );
    v.requireNonEmpty(
      event.toSource,
      'rename.toSource',
      WireIdEventException.new,
    );
  }
}

void _validateTypedUpdateToken(UpdateTokenWireIdEvent event) {
  _validateTypedId(event.id, WireIdKind.designToken, 'updateToken.id');
  if (!event.hasPatch) {
    throw const WireIdEventException(
      'updateToken requires at least one of resolver, literalFallback, '
      'description, or stability',
    );
  }
  if (event.resolver.isPresent && event.resolver.value != null) {
    v.validateResolverShape(event.resolver.value!, WireIdEventException.new);
  }
  if (event.description.isPresent && event.description.value != null) {
    v.requireNonEmpty(
      event.description.value,
      'updateToken.description',
      WireIdEventException.new,
    );
  }
  if (event.stability.isPresent) {
    final value = event.stability.value;
    if (value == null) {
      throw const WireIdEventException('stability must be a string');
    }
    v.validateStability(value, WireIdEventException.new);
  }
}

void _rejectUnusedAllocFields(
  AllocWireIdEvent event, {
  required Set<String> allowed,
}) {
  void reject(String field) {
    throw WireIdEventException(
      '${wireIdKindToEventType(event.type)} alloc must not carry $field',
    );
  }

  if (!allowed.contains('owner') && event.owner != null) reject('owner');
  if (!allowed.contains('name') && event.name != null) reject('name');
  if (!allowed.contains('source') && event.source != null) reject('source');
  if (!allowed.contains('sourceKind') && event.sourceKind != null) {
    reject('sourceKind');
  }
  if (!allowed.contains('namedConstructor') && event.namedConstructor != null) {
    reject('namedConstructor');
  }
  if (!allowed.contains('staticAccessor') && event.staticAccessor != null) {
    reject('staticAccessor');
  }
  if (!allowed.contains('tokenType') && event.tokenType != null) {
    reject('tokenType');
  }
  if (!allowed.contains('resolver') && event.resolver.isPresent) {
    reject('resolver');
  }
  if (!allowed.contains('literalFallback') && event.literalFallback.isPresent) {
    reject('literalFallback');
  }
  if (!allowed.contains('description') && event.description != null) {
    reject('description');
  }
  if (!allowed.contains('stability') && event.stability != null) {
    reject('stability');
  }
}

void _validateTypedRef(
  WireIdRef ref,
  WireIdKind expectedKind,
  String path,
) {
  v.requireNonEmpty(ref.library, '$path.library', WireIdEventException.new);
  _validateTypedId(ref.wireId, expectedKind, '$path.id');
}

void _validateTypedId(WireId id, WireIdKind expectedKind, String path) {
  _validateTypedIdKindOnly(id, path);
  if (id.kind != expectedKind) {
    throw WireIdEventException(
      '$path expected ${wireIdKindToEventType(expectedKind)} '
      '(${expectedKind.prefix}*) but got ${id.value}',
    );
  }
}

void _validateTypedIdKindOnly(WireId id, String path) {
  if (id.isUnallocated) {
    throw WireIdEventException(
      '$path must not use internal sentinel ID ${id.value}',
    );
  }
}

Object? _canonicalJson(Object? value) {
  if (value is Map<String, Object?>) {
    final sorted = SplayTreeMap<String, Object?>();
    for (final entry in value.entries) {
      sorted[entry.key] = _canonicalJson(entry.value);
    }
    return sorted;
  }
  if (value is Map) {
    final sorted = SplayTreeMap<String, Object?>();
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String) {
        throw const WireIdEventException('JSON object keys must be strings');
      }
      sorted[key] = _canonicalJson(entry.value);
    }
    return sorted;
  }
  if (value is Iterable<Object?>) {
    return value.map(_canonicalJson).toList(growable: false);
  }
  return value;
}

WireIdEvent _allocFromJson(_EventReader reader) {
  final type = reader.readType();
  final sourceKind = type == WireIdKind.variant
      ? _variantSourceKindFromString(
          reader.readNonEmptyString('sourceKind'),
          lineNumber: reader.lineNumber,
        )
      : null;
  reader.expectOnly(_allocKeys(type, sourceKind));

  final id = reader.readWireId('id', expectedKind: type);

  switch (type) {
    case WireIdKind.widget:
    case WireIdKind.structured:
    case WireIdKind.union:
      return AllocWireIdEvent(
        type: type,
        id: id,
        name: reader.readNonEmptyString('name'),
        source: reader.readNonEmptyString('source'),
        at: reader.readTimestamp(),
        by: reader.readActor(),
      );
    case WireIdKind.property:
      final owner = reader.readWireId('owner');
      if (owner.kind != WireIdKind.widget &&
          owner.kind != WireIdKind.structured) {
        reader.fail(
          'property owner must be a widget or structured wire ID, '
          'got ${owner.value}',
        );
      }
      return AllocWireIdEvent(
        type: type,
        id: id,
        owner: owner,
        name: reader.readNonEmptyString('name'),
        source: reader.readNonEmptyString('source'),
        at: reader.readTimestamp(),
        by: reader.readActor(),
      );
    case WireIdKind.parameter:
      final owner = reader.readWireId('owner');
      if (owner.kind != WireIdKind.variant) {
        reader.fail(
          'parameter owner must be a variant wire ID, got ${owner.value}',
        );
      }
      return AllocWireIdEvent(
        type: type,
        id: id,
        owner: owner,
        name: reader.readNonEmptyString('name'),
        source: reader.readNonEmptyString('source'),
        at: reader.readTimestamp(),
        by: reader.readActor(),
      );
    case WireIdKind.variant:
      final owner = reader.readWireId(
        'owner',
        expectedKind: WireIdKind.structured,
      );
      final variantKind = sourceKind!;
      return AllocWireIdEvent(
        type: type,
        id: id,
        owner: owner,
        sourceKind: variantKind,
        namedConstructor: variantKind == VariantSourceKind.constructor
            ? reader.readNullableNonEmptyString('namedConstructor')
            : null,
        staticAccessor: variantKind == VariantSourceKind.constructor
            ? null
            : reader.readNonEmptyString('staticAccessor'),
        source: reader.readNonEmptyString('source'),
        at: reader.readTimestamp(),
        by: reader.readActor(),
      );
    case WireIdKind.designToken:
      final tokenType = reader.readNonEmptyString('tokenType');
      _validateTokenType(tokenType, reader);
      final resolver = reader.field<Map<String, Object?>?>(
        'resolver',
        (raw) {
          if (raw == null) return null;
          final map = _objectMap(raw, 'resolver', reader.lineNumber);
          _validateThemeBindingShape(map, reader);
          return map;
        },
      );
      final literalFallback = reader.field<Object?>(
        'literalFallback',
        (raw) {
          _validateLiteralFallback(tokenType, raw, reader);
          return raw;
        },
      );
      final stability = reader.optionalString('stability');
      if (stability != null) _validateStability(stability, reader);
      return AllocWireIdEvent(
        type: type,
        id: id,
        name: reader.readNonEmptyString('name'),
        tokenType: tokenType,
        resolver: resolver,
        literalFallback: literalFallback,
        description: reader.optionalNonEmptyString('description'),
        stability: stability,
        at: reader.readTimestamp(),
        by: reader.readActor(),
      );
  }
}

Set<String> _allocKeys(WireIdKind type, VariantSourceKind? sourceKind) {
  const common = {'kind', 'type', 'id', 'at', 'by'};
  return switch (type) {
    WireIdKind.widget || WireIdKind.structured || WireIdKind.union => {
        ...common,
        'name',
        'source',
      },
    WireIdKind.property => {...common, 'owner', 'name', 'source'},
    WireIdKind.parameter => {...common, 'owner', 'name', 'source'},
    WireIdKind.variant => {
        ...common,
        'owner',
        'sourceKind',
        if (sourceKind == VariantSourceKind.constructor)
          'namedConstructor'
        else
          'staticAccessor',
        'source',
      },
    WireIdKind.designToken => {
        ...common,
        'name',
        'tokenType',
        'resolver',
        'literalFallback',
        'description',
        'stability',
      },
  };
}

WireIdEvent _renameFromJson(_EventReader reader) {
  final type = reader.readType();
  final token = type == WireIdKind.designToken;
  if (token) {
    reader.expectOnly(
      const {'kind', 'type', 'id', 'from', 'to', 'at', 'by'},
    );
  } else {
    reader.expectOnly(
      const {
        'kind',
        'type',
        'id',
        'from',
        'to',
        'source',
        'fromSource',
        'toSource',
        'at',
        'by',
      },
    );
    final annotationRename = reader.has('source');
    final sourceRename = reader.has('fromSource') || reader.has('toSource');
    if (annotationRename == sourceRename) {
      reader.fail(
        'rename requires either source or fromSource + toSource, exclusively',
      );
    }
    if (sourceRename &&
        (!reader.has('fromSource') || !reader.has('toSource'))) {
      reader.fail('source rename requires both fromSource and toSource');
    }
  }
  final from = reader.readNonEmptyString('from');
  final to = reader.readNonEmptyString('to');
  if (from == to) reader.fail('rename must change the display label');
  return RenameWireIdEvent(
    type: type,
    id: reader.readWireId('id', expectedKind: type),
    from: from,
    to: to,
    source: reader.optionalNonEmptyString('source'),
    fromSource: reader.optionalNonEmptyString('fromSource'),
    toSource: reader.optionalNonEmptyString('toSource'),
    at: reader.readTimestamp(),
    by: reader.readActor(),
  );
}

WireIdEvent _deprecateFromJson(_EventReader reader) {
  reader.expectOnly(const {'kind', 'type', 'id', 'reason', 'at', 'by'});
  final type = reader.readType();
  return DeprecateWireIdEvent(
    type: type,
    id: reader.readWireId('id', expectedKind: type),
    reason: reader.readNonEmptyString('reason'),
    at: reader.readTimestamp(),
    by: reader.readActor(),
  );
}

WireIdEvent _replaceFromJson(_EventReader reader) {
  reader.expectOnly(
    const {'kind', 'type', 'from', 'to', 'transition', 'at', 'by'},
  );
  final type = reader.readType();
  final from = reader.readWireId('from', expectedKind: type);
  final to = reader.readWireId('to', expectedKind: type);
  if (from == to) reader.fail('replace endpoints must be different IDs');
  final transition = reader.readNonEmptyString('transition');
  if (!v.isValidTransitionId(transition)) {
    reader.fail('transition must use the tx* positive sequence namespace');
  }
  return ReplaceWireIdEvent(
    type: type,
    from: from,
    to: to,
    transition: transition,
    at: reader.readTimestamp(),
    by: reader.readActor(),
  );
}

WireIdEvent _addMemberFromJson(_EventReader reader) {
  reader.expectOnly(const {'kind', 'type', 'target', 'member', 'at', 'by'});
  final type = reader.readType();
  if (type != WireIdKind.union) {
    reader.fail('addMember type must be union');
  }
  final target = wireIdEventRefFromJson(
    reader.raw('target'),
    lineNumber: reader.lineNumber,
  );
  final member = wireIdEventRefFromJson(
    reader.raw('member'),
    lineNumber: reader.lineNumber,
  );
  if (target.wireId.kind != WireIdKind.union) {
    reader.fail('addMember target must be a union wire ID');
  }
  if (member.wireId.kind != WireIdKind.structured) {
    reader.fail('addMember member must be a structured wire ID');
  }
  return AddMemberWireIdEvent(
    target: target,
    member: member,
    at: reader.readTimestamp(),
    by: reader.readActor(),
  );
}

WireIdEvent _updateTokenFromJson(_EventReader reader) {
  reader.expectOnly(
    const {
      'kind',
      'id',
      'resolver',
      'literalFallback',
      'description',
      'stability',
      'at',
      'by',
    },
  );
  final resolver = reader.field<Map<String, Object?>?>('resolver', (raw) {
    if (raw == null) return null;
    final map = _objectMap(raw, 'resolver', reader.lineNumber);
    _validateThemeBindingShape(map, reader);
    return map;
  });
  final literalFallback = reader.field<Object?>(
    'literalFallback',
    (raw) => raw,
  );
  final description = reader.field<String?>('description', (raw) {
    if (raw == null) return null;
    if (raw is String && raw.isNotEmpty) return raw;
    reader.fail('description must be a non-empty string or null');
  });
  final stability = reader.field<String>('stability', (raw) {
    if (raw is! String) reader.fail('stability must be a string');
    _validateStability(raw, reader);
    return raw;
  });
  final event = UpdateTokenWireIdEvent(
    id: reader.readWireId('id', expectedKind: WireIdKind.designToken),
    resolver: resolver,
    literalFallback: literalFallback,
    description: description,
    stability: stability,
    at: reader.readTimestamp(),
    by: reader.readActor(),
  );
  if (!event.hasPatch) {
    reader.fail(
      'updateToken requires at least one of resolver, literalFallback, '
      'description, or stability',
    );
  }
  return event;
}

WireIdEventKind _eventKindFromString(String value, {int? lineNumber}) {
  for (final kind in WireIdEventKind.values) {
    if (kind.name == value) return kind;
  }
  throw WireIdEventException(
    'unknown wire ID event kind: $value',
    lineNumber: lineNumber,
  );
}

VariantSourceKind _variantSourceKindFromString(
  String value, {
  int? lineNumber,
}) {
  for (final kind in VariantSourceKind.values) {
    if (kind.name == value) return kind;
  }
  throw WireIdEventException(
    'unknown variant sourceKind: $value',
    lineNumber: lineNumber,
  );
}

void _validateStability(String value, _EventReader reader) {
  try {
    v.validateStability(value, WireIdEventException.new);
  } on WireIdEventException catch (error) {
    reader.fail(error.message);
  }
}

void _validateTokenType(String value, _EventReader reader) {
  try {
    v.validateTokenType(value, WireIdEventException.new);
  } on WireIdEventException catch (error) {
    reader.fail(error.message);
  }
}

void _validateLiteralFallback(
  String tokenType,
  Object? value,
  _EventReader reader,
) {
  try {
    v.validateLiteralFallback(tokenType, value, WireIdEventException.new);
  } on WireIdEventException catch (error) {
    reader.fail(error.message);
  }
}

void _validateThemeBindingShape(
  Map<String, Object?> map,
  _EventReader reader,
) {
  try {
    v.validateResolverShape(map, WireIdEventException.new);
  } on WireIdEventException catch (error) {
    reader.fail(error.message);
  }
}

Map<String, Object?> _objectMap(
  Object? raw,
  String path,
  int? lineNumber,
) {
  if (raw is! Map) {
    throw WireIdEventException(
      '$path must be a JSON object',
      lineNumber: lineNumber,
    );
  }
  final result = <String, Object?>{};
  for (final entry in raw.entries) {
    final key = entry.key;
    if (key is! String) {
      throw WireIdEventException(
        '$path contains a non-string key',
        lineNumber: lineNumber,
      );
    }
    result[key] = entry.value;
  }
  return result;
}

final class _EventReader {
  _EventReader(this.json, {required this.lineNumber});

  final Map<String, Object?> json;
  final int? lineNumber;

  bool has(String key) => json.containsKey(key);

  Object? raw(String key) {
    if (!json.containsKey(key)) fail('missing required field: $key');
    return json[key];
  }

  void expectOnly(Set<String> allowed) {
    final unknown = json.keys.toSet().difference(allowed);
    if (unknown.isNotEmpty) {
      fail('unknown field(s): ${unknown.join(', ')}');
    }
  }

  WireIdKind readType() {
    try {
      return wireIdKindFromEventType(readNonEmptyString('type'));
    } on WireIdEventException catch (error) {
      fail(error.message);
    }
  }

  WireId readWireId(String key, {WireIdKind? expectedKind}) {
    final value = readNonEmptyString(key);
    if (value.length < 5) {
      fail('$key must be at least 5 characters');
    }
    if (!const {'w', 'p', 's', 'v', 'u', 't', 'a'}.contains(value[0])) {
      fail('$key prefix must be one of w/p/s/v/u/t/a');
    }
    final sequence = int.tryParse(value.substring(1), radix: 10);
    if (sequence == null || sequence <= 0) {
      fail('$key sequence must be a positive decimal integer');
    }
    final id = WireId(value);
    if (id.isUnallocated) {
      fail('$key must not use internal sentinel ID ${id.value}');
    }
    if (expectedKind != null && id.kind != expectedKind) {
      fail(
        '$key expected ${wireIdKindToEventType(expectedKind)} '
        '(${expectedKind.prefix}*) but got ${id.value}',
      );
    }
    return id;
  }

  String readTimestamp() {
    final value = readNonEmptyString('at');
    final parsed = DateTime.tryParse(value);
    if (parsed == null || !parsed.isUtc) {
      fail('at must be an ISO-8601 UTC timestamp');
    }
    return value;
  }

  String readActor() => readNonEmptyString('by');

  String readNonEmptyString(String key) {
    final value = raw(key);
    if (value is String && value.isNotEmpty) return value;
    fail('$key must be a non-empty string');
  }

  String? readNullableNonEmptyString(String key) {
    final value = raw(key);
    if (value == null) return null;
    if (value is String && value.isNotEmpty) return value;
    fail('$key must be a non-empty string or null');
  }

  String? optionalString(String key) {
    if (!has(key)) return null;
    final value = json[key];
    if (value is String) return value;
    fail('$key must be a string');
  }

  String? optionalNonEmptyString(String key) {
    if (!has(key)) return null;
    final value = json[key];
    if (value is String && value.isNotEmpty) return value;
    fail('$key must be a non-empty string');
  }

  WireIdEventField<T> field<T>(String key, T Function(Object? raw) parse) {
    if (!has(key)) return WireIdEventField<T>.absent();
    return WireIdEventField<T>.value(parse(json[key]));
  }

  Never fail(String message) {
    throw WireIdEventException(message, lineNumber: lineNumber);
  }
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

int _jsonHash(Object? value) {
  if (value is Map) {
    final entries = value.entries.toList()
      ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
    return Object.hashAll(
      entries.map((entry) => Object.hash(entry.key, _jsonHash(entry.value))),
    );
  }
  if (value is List) return Object.hashAll(value.map(_jsonHash));
  return value.hashCode;
}
