import 'package:meta/meta.dart';
import 'package:rfw_catalog_compiler/src/diff/catalog_change.dart';
import 'package:rfw_catalog_compiler/src/factory_variant_fields.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Detects every per-entry change between two canonical catalog versions.
///
/// [baseline] is version A, [current] is version B. Both must be canonical
/// catalogs — entries carry wire IDs. Entries are joined by
/// `(library, wireId)`; the compatibility taxonomy is wire-ID-predicated,
/// so a legacy catalog (wire IDs dropped) cannot be diffed.
///
/// Changes are returned in a deterministic order: by wire-ID kind
/// (widget, property, structured, variant, union, design token), then by
/// `(library, wireId)` within each kind. One entry may produce several
/// changes (e.g. renamed *and* children-slot-changed).
///
/// Infrastructure ahead of application: this catalog-diff path has no
/// production consumer yet (the emitted `CompatRule` type is production; the
/// diff/classifier logic that produces it is not wired in).
@experimental
List<CatalogChange> diffCatalogs(Catalog baseline, Catalog current) {
  final out = <CatalogChange>[];
  _diffKind(
    WireIdKind.widget,
    _indexWidgets(baseline),
    _indexWidgets(current),
    out,
    _widgetPair,
  );
  _diffKind(
    WireIdKind.property,
    _indexProperties(baseline),
    _indexProperties(current),
    out,
    _propertyPair,
  );
  _diffKind(
    WireIdKind.structured,
    _indexStructured(baseline),
    _indexStructured(current),
    out,
    _structuredPair,
  );
  _diffKind(
    WireIdKind.variant,
    _indexVariants(baseline),
    _indexVariants(current),
    out,
    _variantPair,
  );
  _diffKind(
    WireIdKind.union,
    _indexUnions(baseline),
    _indexUnions(current),
    out,
    _unionPair,
  );
  _diffKind(
    WireIdKind.designToken,
    _indexTokens(baseline),
    _indexTokens(current),
    out,
    _tokenPair,
  );
  return out;
}

/// Joins one wire-ID kind's entries by `(library, wireId)`. Emits
/// [EntryAdded] / [EntryRemoved] for keys present in only one version and
/// delegates shared keys to [onPair]. Keys are visited in deterministic
/// `(library, wireId)` order.
void _diffKind<E>(
  WireIdKind kind,
  Map<WireIdRef, E> before,
  Map<WireIdRef, E> after,
  List<CatalogChange> out,
  Iterable<CatalogChange> Function(WireIdRef key, E before, E after) onPair,
) {
  for (final key in _sortedRefs(<WireIdRef>{...before.keys, ...after.keys})) {
    final b = before[key];
    final a = after[key];
    if (b == null) {
      out.add(EntryAdded(kind: kind, affected: key));
    } else if (a == null) {
      out.add(EntryRemoved(kind: kind, affected: key));
    } else {
      out.addAll(onPair(key, b, a));
    }
  }
}

// --- widgets -----------------------------------------------------------

Iterable<CatalogChange> _widgetPair(
  WireIdRef key,
  WidgetEntry before,
  WidgetEntry after,
) sync* {
  if (before.name != after.name || before.flutterType != after.flutterType) {
    yield EntryRenamed(kind: WireIdKind.widget, affected: key);
  }
  final lifecycle = _lifecycleChange(
    WireIdKind.widget,
    key,
    before.deprecated,
    after.deprecated,
  );
  if (lifecycle != null) yield lifecycle;
  if (before.childrenSlot != after.childrenSlot) {
    yield WidgetChildrenSlotChanged(
      affected: key,
      from: before.childrenSlot,
      to: after.childrenSlot,
    );
  }
}

Map<WireIdRef, WidgetEntry> _indexWidgets(Catalog catalog) => _indexByRef(
      catalog.widgets,
      (widget) =>
          WireIdRef(library: widget.library.namespace, wireId: widget.wireId),
    );

// --- properties --------------------------------------------------------

Iterable<CatalogChange> _propertyPair(
  WireIdRef key,
  _PropertyView before,
  _PropertyView after,
) sync* {
  if (before.name != after.name) {
    yield EntryRenamed(kind: WireIdKind.property, affected: key);
  }
  final lifecycle = _lifecycleChange(
    WireIdKind.property,
    key,
    before.deprecated,
    after.deprecated,
  );
  if (lifecycle != null) yield lifecycle;
  if (before.type != after.type) {
    yield PropertyTypeChanged(
      affected: key,
      from: before.type,
      to: after.type,
    );
  }
  if (before.required != after.required) {
    yield RequiredFlagChanged(
      affected: key,
      direction: after.required
          ? RequiredFlagDirection.tightened
          : RequiredFlagDirection.loosened,
    );
  }
  if (before.defaultSource != after.defaultSource) {
    yield PropertyDefaultChanged(affected: key);
  }
  if (before.category != after.category || before.priority != after.priority) {
    yield PropertyMetadataChanged(affected: key);
  }
  if (before.synthetic != after.synthetic) {
    yield SyntheticStrategyChanged(affected: key);
  }
}

/// Collects every property and structured-field entry in [catalog] into one
/// `(library, wireId)`-keyed map. Property wire IDs are library-scoped and
/// shared between widget properties and structured fields, so the two
/// flatten into a single `p*` diff path.
Map<WireIdRef, _PropertyView> _indexProperties(Catalog catalog) {
  final map = <WireIdRef, _PropertyView>{};
  for (final widget in catalog.widgets) {
    final library = widget.library.namespace;
    for (final property in widget.properties) {
      map[WireIdRef(library: library, wireId: property.wireId)] =
          _PropertyView.fromProperty(property);
    }
  }
  for (final structured in catalog.structuredTypes) {
    final library = structured.library.namespace;
    for (final field in structured.fields) {
      map[WireIdRef(library: library, wireId: field.wireId)] =
          _PropertyView.fromField(field);
    }
  }
  return map;
}

/// The comparable shape shared by a widget [PropertyEntry] and a
/// structured-type [StructuredField]. `synthetic` is always `null` for a
/// structured field (the schema has no synthetic strategy on fields).
final class _PropertyView {
  _PropertyView.fromProperty(PropertyEntry property)
      : name = property.name,
        type = property.type,
        required = property.required,
        defaultSource = property.defaultSource,
        category = property.category,
        priority = property.priority,
        synthetic = property.synthetic,
        deprecated = property.deprecated;

  _PropertyView.fromField(StructuredField field)
      : name = field.name,
        type = field.type,
        required = field.required,
        defaultSource = field.defaultSource,
        category = field.category,
        priority = field.priority,
        synthetic = null,
        deprecated = field.deprecated;

  final String name;
  final PropertyType type;
  final bool required;
  final DefaultValueSource? defaultSource;
  final PropertyCategory? category;
  final PropertyPriority? priority;
  final String? synthetic;
  final DeprecationInfo? deprecated;
}

// --- structured types --------------------------------------------------

Iterable<CatalogChange> _structuredPair(
  WireIdRef key,
  StructuredEntry before,
  StructuredEntry after,
) sync* {
  if (before.name != after.name || before.sourceType != after.sourceType) {
    yield EntryRenamed(kind: WireIdKind.structured, affected: key);
  }
  final lifecycle = _lifecycleChange(
    WireIdKind.structured,
    key,
    before.deprecated,
    after.deprecated,
  );
  if (lifecycle != null) yield lifecycle;
}

Map<WireIdRef, StructuredEntry> _indexStructured(Catalog catalog) =>
    _indexByRef(
      catalog.structuredTypes,
      (structured) => WireIdRef(
        library: structured.library.namespace,
        wireId: structured.wireId,
      ),
    );

// --- factory variants --------------------------------------------------

Iterable<CatalogChange> _variantPair(
  WireIdRef key,
  FactoryVariant before,
  FactoryVariant after,
) sync* {
  final beforeShape = factoryVariantFields(before);
  final afterShape = factoryVariantFields(after);
  if (factoryVariantSourceKind(before) != factoryVariantSourceKind(after) ||
      !_argMappingsEqual(beforeShape.argMappings, afterShape.argMappings)) {
    yield VariantArgumentsChanged(affected: key);
  } else if (beforeShape.namedConstructor != afterShape.namedConstructor ||
      beforeShape.staticAccessor != afterShape.staticAccessor) {
    yield EntryRenamed(kind: WireIdKind.variant, affected: key);
  }
  final lifecycle = _lifecycleChange(
    WireIdKind.variant,
    key,
    before.deprecated,
    after.deprecated,
  );
  if (lifecycle != null) yield lifecycle;
}

Map<WireIdRef, FactoryVariant> _indexVariants(Catalog catalog) {
  final map = <WireIdRef, FactoryVariant>{};
  for (final structured in catalog.structuredTypes) {
    final library = structured.library.namespace;
    for (final variant in structured.variants) {
      map[WireIdRef(library: library, wireId: variant.wireId)] = variant;
    }
  }
  return map;
}

// --- unions ------------------------------------------------------------

Iterable<CatalogChange> _unionPair(
  WireIdRef key,
  UnionEntry before,
  UnionEntry after,
) sync* {
  if (before.name != after.name || before.sourceType != after.sourceType) {
    yield EntryRenamed(kind: WireIdKind.union, affected: key);
  }
  final lifecycle = _lifecycleChange(
    WireIdKind.union,
    key,
    before.deprecated,
    after.deprecated,
  );
  if (lifecycle != null) yield lifecycle;
  if (before.discriminator.field != after.discriminator.field) {
    yield UnionDiscriminatorChanged(affected: key);
  }
  final beforeMembers = before.members.toSet();
  final afterMembers = after.members.toSet();
  for (final member in _sortedRefs(afterMembers.difference(beforeMembers))) {
    yield UnionMemberAdded(affected: key, member: member);
  }
  for (final member in _sortedRefs(beforeMembers.difference(afterMembers))) {
    yield UnionMemberRemoved(affected: key, member: member);
  }
}

Map<WireIdRef, UnionEntry> _indexUnions(Catalog catalog) => _indexByRef(
      catalog.unions,
      (union) =>
          WireIdRef(library: union.library.namespace, wireId: union.wireId),
    );

// --- design tokens -----------------------------------------------------

Iterable<CatalogChange> _tokenPair(
  WireIdRef key,
  DesignTokenEntry before,
  DesignTokenEntry after,
) sync* {
  if (before.name != after.name) {
    yield EntryRenamed(kind: WireIdKind.designToken, affected: key);
  }
  final lifecycle = _lifecycleChange(
    WireIdKind.designToken,
    key,
    before.deprecated,
    after.deprecated,
  );
  if (lifecycle != null) yield lifecycle;
  if (before.type != after.type) {
    yield TokenTypeChanged(affected: key, from: before.type, to: after.type);
  }
  if (before.resolver != after.resolver) {
    yield TokenResolverChanged(affected: key);
  }
  if (before.literalFallback != after.literalFallback) {
    yield TokenFallbackChanged(affected: key);
  }
}

Map<WireIdRef, DesignTokenEntry> _indexTokens(Catalog catalog) => _indexByRef(
      catalog.designTokens,
      (token) =>
          WireIdRef(library: token.library.namespace, wireId: token.wireId),
    );

// --- shared helpers ----------------------------------------------------

/// Detects the catalog-lifecycle change (`replace` or `deprecate`) between
/// an entry's old and new [DeprecationInfo].
///
/// A `replace` (the entry's `catalog.replaceWith` became non-null)
/// subsumes the paired `deprecate`: only [EntryReplaced] is emitted, never
/// both, so one lifecycle transition produces one change. A standalone
/// catalog deprecation (the `catalog` layer became non-null with no
/// successor) emits [EntryDeprecated]. Source-only `@Deprecated`
/// annotations (`DeprecationInfo.source`) are not wire-compat events and
/// are ignored.
CatalogChange? _lifecycleChange(
  WireIdKind kind,
  WireIdRef key,
  DeprecationInfo? before,
  DeprecationInfo? after,
) {
  final beforeCatalog = before?.catalog;
  final afterCatalog = after?.catalog;
  if (afterCatalog != null) {
    final replaceWith = afterCatalog.replaceWith;
    if (replaceWith != null && beforeCatalog?.replaceWith == null) {
      return EntryReplaced(
        kind: kind,
        affected: key,
        successor: replaceWith,
        transitionId: afterCatalog.transitionId,
      );
    }
    if (beforeCatalog == null) {
      return EntryDeprecated(kind: kind, affected: key);
    }
  }
  return null;
}

/// Structural equality for two variant arg-mapping tables. `ArgMapping`
/// has no value equality, so the table is compared key-by-key and the
/// per-arg `targetFields` wire-ID lists element-by-element.
bool _argMappingsEqual(
  Map<String, ArgMapping> before,
  Map<String, ArgMapping> after,
) {
  if (before.length != after.length) return false;
  for (final entry in before.entries) {
    final other = after[entry.key];
    if (other == null) return false;
    final mine = entry.value.targetFields;
    final theirs = other.targetFields;
    if (mine.length != theirs.length) return false;
    for (var i = 0; i < mine.length; i++) {
      if (mine[i] != theirs[i]) return false;
    }
  }
  return true;
}

/// Indexes [entries] into a `(library, wireId)`-keyed map. The entry types
/// share no supertype carrying `library` + `wireId`, so [refOf] supplies
/// the reference for an entry.
Map<WireIdRef, E> _indexByRef<E>(
  Iterable<E> entries,
  WireIdRef Function(E entry) refOf,
) {
  return {for (final entry in entries) refOf(entry): entry};
}

List<WireIdRef> _sortedRefs(Iterable<WireIdRef> refs) {
  return refs.toList()
    ..sort((x, y) {
      final byLibrary = x.library.compareTo(y.library);
      if (byLibrary != 0) return byLibrary;
      return x.wireId.value.compareTo(y.wireId.value);
    });
}
