import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// A customer structured widget that was excluded from the RFW path, paired
/// with a human-readable reason naming the offending property/target.
typedef ExcludedStructuredWidget = ({WidgetEntry widget, String reason});

/// The outcome of the recursive resolve-or-exclude-loud admissibility check
/// over a package's customer `@RestageWidget`s + their structured closure.
typedef CustomerStructuredAdmission = ({
  List<WidgetEntry> admitted,
  List<ExcludedStructuredWidget> excluded,
  Set<String> admittedSourceTypes,
});

/// The out-of-band key that associates a structured slot — a widget property or
/// a nested structured field — with its target structured type's `sourceType`,
/// mirroring the source-key convention the allocator uses
/// (`'<ownerFqn>.<slotName>'`). Producer (discovery) and consumers (allocation
/// resolution, this admissibility check) route through this single definition
/// so the convention cannot drift between them.
String structuredSlotKey(String ownerFqn, String slotName) =>
    '$ownerFqn.$slotName';

/// Whether [shape] is the customer list value contract: an opaque list whose
/// items point at a structured entry.
bool isCustomerStructuredListShape(CatalogValueShape? shape) =>
    shape is ListShape && shape.isOpaqueStructuredList;

/// Whether [prop] is a customer structured slot whose target is resolved
/// through [structuredSlotKey].
bool isCustomerStructuredPropertySlot(PropertyEntry prop) =>
    prop.type == PropertyType.structured ||
    isCustomerStructuredListShape(prop.valueShape);

/// Whether [field] is a customer structured slot whose target is resolved
/// through [structuredSlotKey].
bool isCustomerStructuredFieldSlot(StructuredField field) =>
    field.type == PropertyType.structured ||
    isCustomerStructuredListShape(field.valueShape);

/// Whether [entry]'s full transitive structured closure renders on the RFW
/// path. A thin wrapper over [_obstruction]: renderable IFF there is no
/// obstruction anywhere in the closure.
///
/// Renderable IFF (a) its own walk lowered cleanly ([localUnrenderable] carries
/// no entry for its `sourceType`), (b) its reconstruction variant sources every
/// required ctor parameter from a same-named field, and (c) every
/// `PropertyType.structured` field's target — resolved via [slotTargets] — is
/// present in [bySourceType] and itself renderable (recursively). A dangling
/// target (absent from [bySourceType]) is non-renderable (resolve-or-exclude-
/// loud). The walk is cycle-safe via [visiting].
bool isRenderableStructuredType(
  StructuredEntry entry, {
  required Map<String, StructuredEntry> bySourceType,
  required Map<String, String> slotTargets,
  required Map<String, String> localUnrenderable,
  Set<String>? visiting,
}) =>
    _obstruction(
      entry,
      bySourceType: bySourceType,
      slotTargets: slotTargets,
      localUnrenderable: localUnrenderable,
      visiting: visiting,
    ) ==
    null;

/// Decides, for each customer `@RestageWidget`, whether it can render on the
/// RFW path: admitted IFF every `PropertyType.structured` property resolves to
/// an allocated, fully-renderable structured entry; otherwise excluded with a
/// reason naming the first offending property/target.
///
/// `admittedSourceTypes` is the transitive closure of renderable structured
/// entries reachable from the admitted widgets — the set the catalog/factory
/// path threads through (never the excluded ones).
///
/// [isWholeWidgetEmittable] closes the admit-then-skip gap: a widget admitted
/// here for a renderable structured prop but whose OTHER properties are not all
/// factory-emittable (e.g. a direct enum prop with no metadata) would otherwise
/// be carried by the catalog yet SKIPPED by the factory — the incoherence the
/// single-admission invariant forbids. When supplied, a structured-prop widget
/// that fails it is EXCLUDED-loud here (at the one admission point, feeding
/// both builders), never admitted-then-skipped. It is a callback (not a direct
/// factory call) so this predicate stays free of a factory-emitter import. A
/// PURE-scalar widget (no structured prop) is NOT gated by it — that
/// pre-existing catalog/factory skip is out of scope for this feature.
CustomerStructuredAdmission computeAdmission({
  required List<WidgetEntry> widgets,
  required List<StructuredEntry> structuredTypes,
  required Map<String, String> slotTargets,
  required Map<String, String> localUnrenderable,
  Map<String, String> widgetUnrenderable = const {},
  bool Function(WidgetEntry widget)? isWholeWidgetEmittable,
}) {
  final bySourceType = {
    for (final structured in structuredTypes) structured.sourceType: structured,
  };
  final admitted = <WidgetEntry>[];
  final excluded = <ExcludedStructuredWidget>[];

  for (final widget in widgets) {
    // A widget-level unrenderability (e.g. a ctor positional hole — a silent
    // wrong-render) excludes the widget outright, before the structured-closure
    // check, at this one admission point.
    var reason = widgetUnrenderable[widget.flutterType] ??
        _widgetExclusionReason(
          widget,
          bySourceType: bySourceType,
          slotTargets: slotTargets,
          localUnrenderable: localUnrenderable,
        );
    // Whole-widget emittability: a widget admitted for its structured prop but
    // not fully factory-emittable is excluded here, not admitted-then-skipped.
    if (reason == null &&
        isWholeWidgetEmittable != null &&
        widget.properties.any(isCustomerStructuredPropertySlot) &&
        !isWholeWidgetEmittable(widget)) {
      reason = 'the widget has a property the factory cannot emit — admitted '
          'for its structured property but not whole-widget emittable (an '
          'admitted-then-skipped incoherence, excluded at admission)';
    }
    if (reason == null) {
      admitted.add(widget);
    } else {
      excluded.add((widget: widget, reason: reason));
    }
  }

  final admittedSourceTypes = <String>{};
  for (final widget in admitted) {
    for (final prop in widget.properties) {
      if (!isCustomerStructuredPropertySlot(prop)) continue;
      final targetFqn =
          slotTargets[structuredSlotKey(widget.flutterType, prop.name)];
      if (targetFqn == null) continue;
      _collectClosure(
        targetFqn,
        bySourceType: bySourceType,
        slotTargets: slotTargets,
        into: admittedSourceTypes,
      );
    }
  }

  return (
    admitted: admitted,
    excluded: excluded,
    admittedSourceTypes: admittedSourceTypes,
  );
}

/// The reason [widget] cannot render on the RFW path, or `null` when every
/// structured property resolves to a fully-renderable closure.
String? _widgetExclusionReason(
  WidgetEntry widget, {
  required Map<String, StructuredEntry> bySourceType,
  required Map<String, String> slotTargets,
  required Map<String, String> localUnrenderable,
}) {
  for (final prop in widget.properties) {
    if (!isCustomerStructuredPropertySlot(prop)) continue;
    final targetFqn =
        slotTargets[structuredSlotKey(widget.flutterType, prop.name)];
    if (targetFqn == null) {
      return "property '${prop.name}' has no resolvable customer structured "
          'target';
    }
    final target = bySourceType[targetFqn];
    if (target == null) {
      return "property '${prop.name}' targets '$targetFqn', which is not an "
          'admitted (renderable) structured type';
    }
    final obstruction = _obstruction(
      target,
      bySourceType: bySourceType,
      slotTargets: slotTargets,
      localUnrenderable: localUnrenderable,
    );
    if (obstruction != null) {
      return "property '${prop.name}' targets '${target.name}' whose closure "
          'is not fully renderable ($obstruction)';
    }
  }
  return null;
}

/// The first obstruction that makes [entry]'s closure unrenderable, or `null`
/// when it renders faithfully. A single traversal answers both "is it
/// renderable?" (the return is `null`) and "why not?" (the return names the
/// offending type/field), so the predicate and the exclusion reason never walk
/// the closure twice or diverge.
///
/// Obstructions, in check order: a locally-dropped field ([localUnrenderable]);
/// the reconstructor-soundness invariant (a reconstruction-variant required
/// ctor parameter that name-matches no field — the generated factory sources
/// each param from the same-named field, so a non-canonical shape cannot be
/// sourced and must be excluded loud); an unresolved or dangling nested target;
/// a non-renderable nested type (recursively). Cycle-safe via [visiting]: a
/// back-edge poses no new obstruction (the outer call owns that type).
String? _obstruction(
  StructuredEntry entry, {
  required Map<String, StructuredEntry> bySourceType,
  required Map<String, String> slotTargets,
  required Map<String, String> localUnrenderable,
  Set<String>? visiting,
}) {
  final local = localUnrenderable[entry.sourceType];
  if (local != null) return '${entry.name}: $local';
  final seen = visiting ?? <String>{};
  if (!seen.add(entry.sourceType)) {
    // A back-edge = a cycle (the type reaches back to itself through the
    // closure). Cycle-safety here previously treated a back-edge as renderable,
    // which is correct for a FINITE check but wrong for finite INLINE emission:
    // the generated reconstructor would expand `next: Node(next: Node(...))`
    // forever. A cyclic customer type can't be reconstructed by inline emission
    // — exclude-loud (it renders in A2UI via `$ref`, not RFW inline). A DIAMOND
    // (a type reached twice on separate paths) is NOT a cycle: the try/finally
    // backtracking removes each sourceType after its subtree, so only a true
    // ancestor-on-the-stack back-edge lands here.
    return '${entry.name}: cyclic structured type (a field reaches back to '
        'it); a cyclic value cannot be reconstructed by inline emission';
  }
  try {
    final unsourceable = _unsourceableParam(entry);
    if (unsourceable != null) {
      return '${entry.name}: ctor parameter $unsourceable has no matching '
          'decodable field (non-canonical shape)';
    }
    for (final field in entry.fields) {
      if (!isCustomerStructuredFieldSlot(field)) continue;
      final targetFqn =
          slotTargets[structuredSlotKey(entry.sourceType, field.name)];
      if (targetFqn == null) {
        return '${entry.name}.${field.name}: unresolved structured target';
      }
      final target = bySourceType[targetFqn];
      if (target == null) {
        return '${entry.name}.${field.name} -> $targetFqn '
            '(not an admitted structured type)';
      }
      final nested = _obstruction(
        target,
        bySourceType: bySourceType,
        slotTargets: slotTargets,
        localUnrenderable: localUnrenderable,
        visiting: seen,
      );
      if (nested != null) return nested;
    }
    return null;
  } finally {
    seen.remove(entry.sourceType);
  }
}

/// Adds [sourceType] and its transitive structured closure to [into].
void _collectClosure(
  String sourceType, {
  required Map<String, StructuredEntry> bySourceType,
  required Map<String, String> slotTargets,
  required Set<String> into,
}) {
  if (!into.add(sourceType)) return;
  final entry = bySourceType[sourceType];
  if (entry == null) return;
  for (final field in entry.fields) {
    if (!isCustomerStructuredFieldSlot(field)) continue;
    final targetFqn =
        slotTargets[structuredSlotKey(entry.sourceType, field.name)];
    if (targetFqn == null) continue;
    _collectClosure(
      targetFqn,
      bySourceType: bySourceType,
      slotTargets: slotTargets,
      into: into,
    );
  }
}

/// The label of a reconstruction-variant parameter — required OR optional —
/// that the by-name reconstructor cannot source — one that name-matches no
/// field (a renamed or positional ctor param), or `'<no constructor
/// variant>'` when the type has no constructor to reconstruct with. Returns
/// `null` when every parameter maps to a same-named field (a canonical data
/// class). Optionality doesn't make a renamed param sourceable: the
/// reconstructor would still supply the field under ITS name, so a
/// genuinely-authored value would silently read back as whatever default the
/// reconstruction ctor gives that field, never the author's actual value.
String? _unsourceableParam(StructuredEntry entry) {
  final variant = reconstructionVariant(entry);
  if (variant == null) return '<no constructor variant>';
  final fieldNames = {for (final field in entry.fields) field.name};
  // This is a BACKSTOP, not the enforcement point: for real customer variants
  // `variant.parameters` is EMPTY (`enumerateFactoryVariants` never populates
  // it — only `argMappings`), so this loop is a no-op and only the
  // `variant == null` guard above is live. The authoritative reconstructor-
  // soundness checks (BOTH the param->field and the field->param directions)
  // run upstream in `customer_structured_discovery._reconstructionObstruction`
  // over the REAL analyzer constructor, and their verdict reaches admission via
  // `localUnrenderable` (read first in `_obstruction`). Do NOT add the
  // field->param dual here: iterating `fieldNames` against this empty
  // `variant.parameters` would report EVERY field unsourceable and exclude all.
  for (final parameter in variant.parameters) {
    final name = parameter.name;
    if (name == null) {
      // A trailing optional positional with no matching field is a
      // deliberately admitted shape (mirrors the analyzer-level check in
      // customer_structured_discovery.dart) — a positional param can only be
      // unsourceable-by-shift, which the positional-hole check handles.
      if (!parameter.required) continue;
      return "'<positional ${parameter.position ?? '?'}>'";
    }
    if (!fieldNames.contains(name)) return "'$name'";
  }
  return null;
}

/// The variant the reconstructor uses to rebuild a value of [entry]: the
/// canonical unnamed constructor when present, else the first constructor
/// variant. `null` when the type declares no constructor variant (e.g. a
/// const-value-only wrapper) — such a type cannot be ctor-reconstructed.
ConstructorVariant? reconstructionVariant(StructuredEntry entry) {
  ConstructorVariant? firstCtor;
  for (final variant in entry.variants) {
    if (variant is! ConstructorVariant) continue;
    firstCtor ??= variant;
    if (variant.namedConstructor == null) return variant;
  }
  return firstCtor;
}
