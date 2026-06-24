import 'package:restage_codegen/src/catalog_loader.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_shared/restage_shared.dart' show kSupportedCurveNames;
import 'package:restage_shared/rfw_formats.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// The nine canonical `FontWeight` member names the
/// `enumValue<FontWeight>(FontWeight.values, …)` decoder resolves. A
/// `fontWeight` slot value outside this set is silently nulled at runtime; the
/// codegen translator canonicalises aliases (`normal`/`bold`) to these names,
/// and this set is the validator's member-set backstop.
const Set<String> _kCanonicalFontWeightNames = {
  'w100',
  'w200',
  'w300',
  'w400',
  'w500',
  'w600',
  'w700',
  'w800',
  'w900',
};

/// Walks a parsed RFW [library] and verifies every [ConstructorCall] references
/// a widget present in [catalog], and every property name used is declared on
/// that widget.
///
/// A [ConstructorCall] naming a **library-local** `widget` definition (a
/// `widget X = …` declared in this same [library] — e.g. an inlined custom
/// widget) resolves within the library: its name and its arguments — which
/// bind the definition's `args.`, not catalog properties — are not checked
/// against the catalog. The definition's body is still validated, walked as
/// its own library widget.
///
/// Issues collected describe the first failure for each constructor call;
/// nested calls inside arguments are walked recursively. The check is name-
/// based — the parsed RFW model only carries unqualified widget names — so
/// shadowed names across libraries match against the priority-ordered first
/// hit, mirroring the translator's lookup at construction time.
///
/// **Scope of the scalar-value type check.** The property-value type check
/// (`_checkArgValueType` → `_scalarValueMismatch`) reaches **top-level scalar
/// slots only** — a literal scalar (`String` / `num` / `bool`) bound directly
/// to a widget property slot is checked against that slot's declared
/// [PropertyType]. It does **not** descend into the fields of a structured map
/// literal: a scalar nested inside a map bound to a structured slot (e.g. a
/// `{left: "x"}`-style field value) is not type-checked against the structured
/// recipe's per-field types here. That structured-field-scalar correctness is
/// **closed by emitter-arm discipline, not by this validator** — the
/// translator lowers each structured slot through a typed emitter arm that
/// only ever writes a well-typed field value, so a wrong-typed structured
/// field cannot be authored through the normal lowering path. The residual a
/// validator-side field check would catch — a non-finite or otherwise
/// out-of-shape scalar reaching a structured field through some other path —
/// is closed at the emit layer (the non-finite / bare-name emit guard, owned
/// elsewhere). See the map-handling branch in `_walkNode` for the exact reason
/// a validator-side structured-field check is not wired in today and what a
/// future one would require.
List<Issue> validateModelAgainstCatalog(
  RemoteWidgetLibrary library,
  Catalog catalog,
) {
  final issues = <Issue>[];
  final localNames = {for (final widget in library.widgets) widget.name};
  for (final widget in library.widgets) {
    _walkNode(widget.root, catalog, localNames, issues, widget.name);
  }
  return issues;
}

void _walkNode(
  Object? node,
  Catalog catalog,
  Set<String> localNames,
  List<Issue> issues,
  String location,
) {
  if (node is ConstructorCall) {
    // A call to a library-local `widget` definition resolves within the
    // library; its arguments bind the definition's `args.`, not catalog
    // properties — skip the catalog + property-name checks for the call
    // itself. The definition's body is validated separately, as its own
    // library widget. A non-local name is held to the catalog.
    if (!localNames.contains(node.name)) {
      final candidates = findWidgetsByName(catalog, node.name);
      final entry = candidates.isEmpty ? null : candidates.first;
      if (entry == null) {
        issues.add(
          Issue(
            code: IssueCode.unknownWidget,
            message: "Widget '${node.name}' is not in the merged catalog. A "
                'custom widget must be referenced from Dart source, where the '
                'transpiler can resolve and classify its class.',
            location: location,
          ),
        );
      } else {
        for (final argEntry in node.arguments.entries) {
          final propName = argEntry.key;
          final matches = entry.properties.where((p) => p.name == propName);
          if (matches.isEmpty) {
            issues.add(
              Issue(
                code: IssueCode.unknownProperty,
                message: "Property '$propName' is not declared on "
                    "'${entry.name}'. Catalog properties: "
                    '${entry.properties.map((p) => p.name).join(", ")}.',
                location: '$location/${node.name}',
              ),
            );
            continue;
          }
          _checkArgValueType(
            argEntry.value,
            matches.first,
            entry.name,
            issues,
            '$location/${node.name}',
          );
        }
        // Required widget / widgetList slots must be present. A required
        // `widget` left out decodes to a runtime cast error; a required
        // `widgetList` silently decodes to an empty list. Required scalars are
        // already enforced by the typed decode, and a required event is an
        // authoring choice (by design), so only widget-shaped slots are
        // checked here.
        for (final property in entry.properties) {
          final isWidgetSlot = property.type == PropertyType.widget ||
              property.type == PropertyType.widgetList;
          if (property.required &&
              isWidgetSlot &&
              !node.arguments.containsKey(property.name)) {
            final shape = property.type == PropertyType.widgetList
                ? 'widget-list'
                : 'widget';
            issues.add(
              Issue(
                code: IssueCode.missingRequiredSlot,
                message: "Required $shape slot '${property.name}' is missing "
                    "on '${entry.name}'. Supply it — a missing required slot "
                    'ships a degraded blob (a runtime cast error for a widget, '
                    'or a silently-empty list).',
                location: '$location/${node.name}',
              ),
            );
          }
        }
      }
    }
    // Recurse into arguments regardless — they may contain nested catalog
    // widgets (or further local references) worth walking individually.
    for (final argEntry in node.arguments.entries) {
      _walkNode(
        argEntry.value,
        catalog,
        localNames,
        issues,
        '$location/${node.name}.${argEntry.key}',
      );
    }
  } else if (node is List) {
    for (final child in node) {
      _walkNode(child, catalog, localNames, issues, location);
    }
  } else if (node is Switch) {
    // Each branch is a candidate value for whatever slot the switch is bound
    // to; walk every output so nested constructor calls inside a branch are
    // validated. (Branch-literal type-checking against the slot type happens
    // in `_checkArgValueType`, where the property type is known.)
    for (final output in node.outputs.values) {
      _walkNode(output, catalog, localNames, issues, location);
    }
  } else if (node is Loop) {
    // The loop template is applied per element; walk it for nested calls.
    _walkNode(node.output, catalog, localNames, issues, location);
  } else if (node is WidgetBuilderDeclaration) {
    // The builder's returned widget (usually a constructor call) must be
    // validated like any other widget.
    _walkNode(node.widget, catalog, localNames, issues, location);
  } else if (node is Map) {
    // A map literal bound to a structured slot can carry nested calls in its
    // values (keys are inert strings). This walk recurses into the values ONLY
    // to find nested constructor calls — it does NOT type-check a structured
    // field's scalar against the structured recipe's per-field types.
    //
    // Why no structured-field scalar type-check here:
    //   * By the time the walk reaches a map node, the binding's
    //     [PropertyEntry] is no longer in scope (this is the generic value
    //     recursion). The slot→recipe linkage a field check needs — the
    //     declared [PropertyType], its `structuredRef`, and the resolved
    //     structured entry's `fields` — is not threaded down to this node.
    //   * No widget property is typed `PropertyType.structured` with a
    //     *top-level* `structuredRef` — that direct slot→recipe linkage is not
    //     populated. The structured/union references that widget slots DO carry
    //     live on the slot's `valueShape`: a `unionRef` on the discriminated
    //     slots (gradient / border / shapeBorder) and a list-item
    //     `structuredRef` on list slots (e.g. boxShadowList). So a
    //     validator-side check would not be entirely inert — it could resolve a
    //     map against those `valueShape` references — but it is non-trivial: a
    //     union slot's map must first be discriminated to a member (a gradient
    //     map is one of linear/radial/sweep, each with a different field set)
    //     before its fields can be matched, and the [PropertyEntry] carrying
    //     that `valueShape` is not threaded down to this generic map node.
    //
    // So a wrong-typed scalar inside a structured field is "closed by
    // emitter-arm discipline, not by this validator": each structured slot
    // lowers through a typed emitter arm that only writes well-typed field
    // values, and the residual (a non-finite or otherwise out-of-shape scalar
    // reaching a structured field through some other path) is closed at the
    // emit layer's non-finite / bare-name guard, owned elsewhere.
    //
    // A future validator-side second line of defense would: (a) thread the
    // bound slot's [PropertyEntry] from `_checkArgValueType` into this map
    // walk; (b) resolve the slot's `valueShape` — a `unionRef` (discriminating
    // the union member first) or a list-item `structuredRef` — against
    // `catalog.unions` / `catalog.structuredTypes`; (c) match each map key to
    // the member/structured `StructuredField` by name and re-run the scalar
    // check against that field's [PropertyType], recursing via nested refs.
    // The emit-layer guard stays the primary floor; this is a scoped hardening
    // follow-up, not a blocked one.
    for (final value in node.values) {
      _walkNode(value, catalog, localNames, issues, location);
    }
  }
  // Remaining node types (literal scalars, `DataReference`/`ArgsReference`,
  // `EventHandler`) carry no catalog references — skip them.
}

/// Type-checks an argument [value] against its matched catalog [property].
///
/// A literal scalar is checked directly against the property type. A `Switch`
/// resolves at runtime, but every branch is a candidate value for the **same**
/// slot, so each branch is checked (recursively — a branch may itself be a
/// switch). Non-scalar, non-switch values (references, lists, maps, nested
/// constructor calls) are runtime-resolved or walked elsewhere and are not
/// type-checked here.
///
/// In particular, a **map** bound to a structured slot is not descended into:
/// a scalar nested inside that map is not checked against the structured
/// recipe's per-field types. That structured-field-scalar correctness is
/// closed by emitter-arm discipline (and the emit-layer guard, owned
/// elsewhere), not by this check — see the map-handling branch in `_walkNode`
/// for the precise reason and what a validator-side field check would require.
void _checkArgValueType(
  Object? value,
  PropertyEntry property,
  String widgetName,
  List<Issue> issues,
  String location,
) {
  if (value is Switch) {
    for (final branch in value.outputs.values) {
      _checkArgValueType(branch, property, widgetName, issues, location);
    }
    return;
  }
  if (_scalarValueMismatch(property.type, value)) {
    issues.add(
      Issue(
        code: IssueCode.propertyValueTypeMismatch,
        message: "Property '${property.name}' on '$widgetName' expects a "
            '${property.type.name} value, but a ${_literalKindName(value)} '
            '(${_describeLiteral(value)}) was emitted. A value of the wrong '
            'type is silently dropped by the runtime decode — pass a value the '
            'property type accepts, or check the source expression lowers '
            'correctly.',
        location: location,
      ),
    );
  }
}

/// Returns `true` when [value] is a literal scalar whose runtime type the
/// declared property [type] cannot accept — the property-value-type mismatch
/// that the runtime decode would otherwise silently null.
///
/// Only literal scalars (`String` / `int` / `double` / `bool`) are checked. A
/// non-scalar value — a list, a map, a `DataReference`, a `Switch`, an
/// `EventHandler`, a nested `ConstructorCall` — is runtime-resolved or
/// structurally recursed elsewhere and is never flagged here.
///
/// Each accept/reject decision is matched to what the slot's runtime decoder
/// actually reads, and the runtime `DataSource.v<T>` decode is **exact**
/// (`value is T`), so the numeric axis is type-precise, not "any number":
///   * `length` / `real` decode via `v<double>` — an `int` is silently nulled,
///     so a double is required;
///   * `integer` / `duration` / `color` decode via `v<int>` — a `double` is
///     silently nulled, so an int is required;
///   * a slot whose decoder reads a child / list / map / handler / reference
///     never accepts a bare scalar at all, so any literal scalar is flagged.
bool _scalarValueMismatch(PropertyType type, Object? value) {
  if (value is! String && value is! num && value is! bool) {
    // Not a literal scalar — lists, maps, references, switches, event
    // handlers and nested constructor calls are handled by recursion / the
    // runtime decoder, never by this scalar check.
    return false;
  }
  switch (type) {
    // Double-decoded slots (`source.v<double>`): an int is silently nulled.
    case PropertyType.length:
    case PropertyType.real:
      return value is! double;
    // Int-decoded slots (`source.v<int>`): a double is silently nulled.
    case PropertyType.integer:
    case PropertyType.duration:
    case PropertyType.color:
      return value is! int;
    // Boolean slot.
    case PropertyType.boolean:
      return value is! bool;
    // String-decoded slots: the runtime decoder reads a bare string
    // (`enumValue`, `locale`) or a string-or-list (`textDecoration`).
    // Lists are non-scalar and return before this switch.
    case PropertyType.string:
    case PropertyType.enumValue:
    case PropertyType.textDecoration:
    case PropertyType.locale:
      return value is! String;
    // `fontWeight` decodes via `enumValue<FontWeight>(FontWeight.values, …)`,
    // which resolves ONLY the nine canonical `w100`..`w900` member names — any
    // other string is silently nulled to the slot default. The codegen
    // translator canonicalises FontWeight aliases (`normal`/`bold` → `wN`), so a
    // legitimate emission is always one of these; the validator backstops the
    // member set.
    case PropertyType.fontWeight:
      return value is! String || !_kCanonicalFontWeightNames.contains(value);
    // `curve` decodes via a closed name→curve lookup table; a name outside the
    // supported vocabulary is silently nulled to the framework default. The
    // validator backstops the shared `kSupportedCurveNames` vocabulary — the
    // single source the runtime decoder's table is pinned to by test, so this
    // accept-set is exactly what the decoder can resolve.
    case PropertyType.curve:
      return value is! String || !kSupportedCurveNames.contains(value);
    // Slots whose decoder reads a child / list / map / handler / reference —
    // NEVER a bare scalar (verified: no structured/list/map decoder accepts a
    // top-level scalar). Any literal scalar here is the silent-loss case
    // (`padding: "zero"` or `padding: 8`; `alignment: "center"` — `alignment`
    // decodes from a `{x, y}` map, not a member name).
    case PropertyType.widget:
    case PropertyType.widgetList:
    case PropertyType.event:
    case PropertyType.dataReference:
    case PropertyType.edgeInsets:
    case PropertyType.alignment:
    case PropertyType.alignmentXY:
    case PropertyType.offset:
    case PropertyType.gradient:
    case PropertyType.border:
    case PropertyType.boxShadowList:
    case PropertyType.shapeBorder:
    case PropertyType.paint:
    case PropertyType.shadowList:
    case PropertyType.fontFeatureList:
    case PropertyType.fontVariationList:
    case PropertyType.stringList:
    // A list of booleans (a multi-toggle widget's per-child selection flags),
    // never a bare scalar.
    case PropertyType.booleanList:
    case PropertyType.structured:
    // A recursive span map (Text.rich / TextSpan), never a bare scalar — the
    // explicit classification for the new structured-slot type (decided here,
    // not inherited from a default — there is none).
    case PropertyType.inlineSpan:
    // A self-describing image map (DecorationImage), never a bare scalar.
    case PropertyType.decorationImage:
    // A list of `{value, label}` option maps (single-select items), never a
    // bare scalar.
    case PropertyType.selectionOptionList:
      return true;
    // Opaque additive member — never flag.
    case PropertyType.unknown:
      return false;
  }
}

String _literalKindName(Object? value) {
  if (value is String) return 'string';
  if (value is int) return 'integer';
  if (value is double) return 'number';
  if (value is bool) return 'boolean';
  return value.runtimeType.toString();
}

String _describeLiteral(Object? value) =>
    value is String ? '"$value"' : '$value';
