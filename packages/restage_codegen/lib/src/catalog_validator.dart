import 'package:restage_compiler_core/src/builder_scope_values.dart';
import 'package:restage_compiler_core/src/rfw_program_envelope.dart';
import 'package:restage_compiler_core/src/surface_capability_derivation.dart'
    show validateRfwNativeReferences;
import 'package:restage_codegen/src/catalog_loader.dart';
import 'package:restage_codegen/src/commerce_authoring.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/optional_native_values.dart';
import 'package:restage_codegen/src/surface_publication/split_widgets.dart'
    show kAppWidgetPlacementArguments;
import 'package:restage_codegen/src/native_binding_routes.dart';
import 'package:restage_shared/restage_shared.dart'
    show
        kSupportedCurveNames,
        kBuilderContinuationWidgetName,
        ValueOperation,
        SurfaceScreenHostDataSchema,
        SurfaceScreenHostDataShape,
        SurfaceScreenHostDataNativeBindingShapeV1,
        SurfaceScreenHostDataNullableShapeV1,
        SurfaceScreenHostDataObjectShapeV1,
        SurfaceScreenHostDataListShapeV1,
        SurfaceScreenHostDataMapShapeV1,
        kStandardValueOperations;
import 'package:restage_shared/rfw_formats.dart' hide WidgetLibrary;
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

/// Validates constructor names and properties in [library] against [catalog].
///
/// Local widget definitions resolve within the library; their bodies are
/// validated separately. Nested calls are checked recursively, with one
/// issue per failing call. Unqualified names use the first catalog match.
///
/// Checks top-level scalar values. Structured-map fields are validated by
/// the typed emitters. [rootLabels] uses authored class names in diagnostics.
/// [operations] comes from the source-installed declarations; the default
/// accepts only the closed built-in operations. [hostDataContract] supplies
/// the installed declarations used to validate native constructor keys.
List<Issue> validateModelAgainstCatalog(
  RemoteWidgetLibrary library,
  Catalog catalog, {
  Map<String, String> rootLabels = const {},
  SurfaceScreenHostDataSchema hostDataContract =
      const SurfaceScreenHostDataSchema.empty(),
  Map<String, ValueOperation> operations = kStandardValueOperations,
}) {
  // Validate nested programs with the same lexical ownership as the runtime.
  // Isolated re-decodes lose outer locals declared by an enclosing builder.
  final scope = RfwProgramScope(
    library.widgets.map((widget) => widget.root),
    operations: operations,
    scopedNativeValues: rfwBuilderScopeValues(library, catalog),
  );
  final issues = validateCommerceAuthoring(library, rootLabels: rootLabels);
  final localNames = {for (final widget in library.widgets) widget.name};
  for (final widget in library.widgets) {
    if (widget.name == kBuilderContinuationWidgetName) {
      throw const FormatException(
        'Authored declarations cannot shadow the builder continuation.',
      );
    }
    _walkNode(
      widget.root,
      catalog,
      localNames,
      issues,
      rootLabels[widget.name] ?? widget.name,
      operations,
      scope,
      hostDataContract,
    );
  }
  if (issues.isEmpty) {
    validateRfwNativeReferences(library, catalog, scope: scope);
  }
  return issues;
}

void _walkNode(
  Object? node,
  Catalog catalog,
  Set<String> localNames,
  List<Issue> issues,
  String location,
  Map<String, ValueOperation> operations,
  RfwProgramScope scope,
  SurfaceScreenHostDataSchema hostDataContract, {
  List<SurfaceScreenHostDataShape?> loops = const [],
}) {
  if (node is ConstructorCall) {
    if (node.name == kBuilderContinuationWidgetName) {
      for (final value in node.arguments.values) {
        _walkNode(
          value,
          catalog,
          localNames,
          issues,
          location,
          operations,
          scope,
          hostDataContract,
          loops: loops,
        );
      }
      return;
    }

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
            message:
                "Widget '${node.name}' is not in the merged catalog. A "
                'custom widget must be referenced from Dart source, where the '
                'transpiler can resolve and classify its class.',
            location: location,
          ),
        );
      } else {
        for (final argEntry in node.arguments.entries) {
          final propName = argEntry.key;
          final matches = entry.properties.where((p) => p.name == propName);
          // Where the design places an app widget, read by its factory.
          if (matches.isEmpty &&
              WidgetLibrary.builtInByNamespace(entry.library.namespace) ==
                  null &&
              kAppWidgetPlacementArguments.contains(propName)) {
            continue;
          }
          if (matches.isEmpty) {
            issues.add(
              Issue(
                code: IssueCode.unknownProperty,
                message:
                    "Property '$propName' is not declared on "
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
          final property = matches.first;
          final shape = property.valueShape;
          final ref =
              property.structuredRef ??
              (shape is StructuredShape ? shape.structuredRef : null);
          final structured = ref == null
              ? null
              : catalog.structuredTypes
                    .where(
                      (type) =>
                          type.library.namespace == ref.library &&
                          type.wireId == ref.wireId,
                    )
                    .firstOrNull;
          if (structured != null &&
              nativeBindingRoute(structured.sourceType)?.contractType ==
                  'flutter.Key' &&
              !_forwardedArg(argEntry.value) &&
              !_validNativeKeyArgument(
                argEntry.value,
                property,
                scope,
                hostDataContract,
                loops,
              )) {
            issues.add(
              Issue(
                code: IssueCode.propertyValueTypeMismatch,
                message:
                    "Property '$propName' on '${entry.name}' requires a typed native Key reference.",
                location: '$location/${node.name}',
              ),
            );
          }
          if (entry.library.namespace == 'restage.svg' &&
              ref != null &&
              catalog.structuredTypes.any(
                (type) =>
                    type.library.namespace == ref.library &&
                    type.wireId == ref.wireId &&
                    optionalNativeBindingTypes.containsKey(type.sourceType),
              ) &&
              _containsOpaqueNativeArgument(argEntry.value)) {
            issues.add(
              Issue(
                code: IssueCode.propertyValueTypeMismatch,
                message:
                    "Property '$propName' on '${entry.name}' requires "
                    'an installed native value; RFW widgets, builders and '
                    'events cannot supply it.',
                location: '$location/${node.name}',
              ),
            );
          }
        }
        // A required argument Flutter can't take as null must be present:
        // absence has no Flutter meaning. Widget slots are checked always.
        for (final property in entry.properties) {
          final isWidgetSlot =
              property.type == PropertyType.widget ||
              property.type == PropertyType.widgetList;
          if (property.required &&
              (isWidgetSlot || property.constructorNullable != true) &&
              !node.arguments.containsKey(property.name)) {
            issues.add(
              Issue(
                code: IssueCode.missingRequiredSlot,
                message:
                    '`${entry.name}` is missing its required argument '
                    '`${property.name}`. Try passing `${property.name}`.',
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
        operations,
        scope,
        hostDataContract,
        loops: loops,
      );
    }
  } else if (node is List) {
    for (final child in node) {
      _walkNode(
        child,
        catalog,
        localNames,
        issues,
        location,
        operations,
        scope,
        hostDataContract,
        loops: loops,
      );
    }
  } else if (node is Switch) {
    // Each branch is a candidate value for whatever slot the switch is bound
    // to; walk every output so nested constructor calls inside a branch are
    // validated. (Branch-literal type-checking against the slot type happens
    // in `_checkArgValueType`, where the property type is known.)
    for (final output in node.outputs.values) {
      _walkNode(
        output,
        catalog,
        localNames,
        issues,
        location,
        operations,
        scope,
        hostDataContract,
        loops: loops,
      );
    }
  } else if (node is Loop) {
    // The loop template is applied per element; walk it for nested calls,
    // with each item read against its list's item shape.
    var input = _referencedShape(node.input, hostDataContract, loops);
    while (input is SurfaceScreenHostDataNullableShapeV1) input = input.value;
    _walkNode(
      node.output,
      catalog,
      localNames,
      issues,
      location,
      operations,
      scope,
      hostDataContract,
      loops: [
        ...loops,
        input is SurfaceScreenHostDataListShapeV1 ? input.items : null,
      ],
    );
  } else if (node is WidgetBuilderDeclaration) {
    // The builder's returned widget (usually a constructor call) must be
    // validated like any other widget.
    _walkNode(
      node.widget,
      catalog,
      localNames,
      issues,
      location,
      operations,
      scope,
      hostDataContract,
      loops: loops,
    );
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
      _walkNode(
        value,
        catalog,
        localNames,
        issues,
        location,
        operations,
        scope,
        hostDataContract,
        loops: loops,
      );
    }
  }
  // Remaining node types (literal scalars, `DataReference`/`ArgsReference`,
  // `EventHandler`) carry no catalog references — skip them.
}

/// The host-data shape [value] reads: `data.context.<input>…`, or an item of
/// an enclosing loop, whose item shapes [loops] holds, nearest last.
SurfaceScreenHostDataShape? _referencedShape(
  Object? value,
  SurfaceScreenHostDataSchema contract,
  List<SurfaceScreenHostDataShape?> loops,
) {
  if (value is DataReference) {
    final parts = value.parts;
    if (parts.length < 2 || parts.first != 'context') return null;
    return _shapeAt(contract.inputs[parts[1]], parts.skip(2));
  }
  if (value is LoopReference) {
    if (value.loop >= loops.length) return null;
    return _shapeAt(loops[loops.length - 1 - value.loop], value.parts);
  }
  return null;
}

/// The shape at [parts] below [shape].
SurfaceScreenHostDataShape? _shapeAt(
  SurfaceScreenHostDataShape? shape,
  Iterable<Object> parts,
) {
  for (final part in parts) {
    while (shape is SurfaceScreenHostDataNullableShapeV1) shape = shape.value;
    shape = switch (shape) {
      SurfaceScreenHostDataObjectShapeV1(:final fields) => fields[part],
      SurfaceScreenHostDataMapShapeV1(:final values) when part is String =>
        values,
      SurfaceScreenHostDataListShapeV1(:final items)
          when part is int && part >= 0 =>
        items,
      _ => null,
    };
  }
  return shape;
}

// A custom widget forwards a native value it was given as that same value;
// its own placement was checked.
bool _forwardedArg(Object? value) =>
    value is ArgsReference && value.parts.length == 1;

bool _validNativeKeyArgument(
  Object? value,
  PropertyEntry property,
  RfwProgramScope scope,
  SurfaceScreenHostDataSchema hostDataContract,
  List<SurfaceScreenHostDataShape?> loops,
) {
  if (RfwConstructorPresenceProtocol.appliesTo(property) &&
      value is Map &&
      value[RfwConstructorPresenceProtocol.markerKey] ==
          RfwConstructorPresenceProtocol.version) {
    if (value.length != 1 &&
        (value.length != 2 ||
            !value.containsKey(RfwConstructorPresenceProtocol.valueKey))) {
      return false;
    }
    value = value[RfwConstructorPresenceProtocol.valueKey];
  }
  if (value == null) return property.constructorNullable;
  if (value is Switch)
    return value.outputs.values.every(
      (branch) => _validNativeKeyArgument(
        branch,
        property,
        scope,
        hostDataContract,
        loops,
      ),
    );
  if (value is DataReference || value is LoopReference) {
    final shape = _referencedShape(value, hostDataContract, loops);
    return shape is SurfaceScreenHostDataNativeBindingShapeV1 &&
        shape.contract.type == 'flutter.Key' &&
        shape.contract.call == null &&
        (property.constructorNullable || !shape.contract.nullable);
  }
  if (value is Map &&
      (value['kind'] == 'nativeBinding' || value['kind'] == 'nativeLocal')) {
    final nativeLocal = value['kind'] == 'nativeLocal';
    final name = value[nativeLocal ? 'slot' : 'key'];
    if (value.length != 4 ||
        name is! String ||
        name.isEmpty ||
        value['type'] != 'flutter.Key' ||
        value['nullable'] is! bool ||
        !property.constructorNullable && value['nullable'] != false)
      return false;
    // Lexical cells are validated by RfwProgramScope; borrowed declarations
    // must also agree with the installed host contract for this exact key slot.
    if (nativeLocal) return true;
    final shape = hostDataContract.inputs[name];
    return shape is SurfaceScreenHostDataNativeBindingShapeV1 &&
        shape.contract.type == 'flutter.Key' &&
        shape.contract.call == null &&
        shape.contract.nullable == value['nullable'];
  }
  final envelope = scope.decode(value);
  if (envelope == null ||
      envelope.builder != null ||
      envelope.values.parameters.isNotEmpty)
    return false;
  final type = envelope.values.nodes[envelope.values.root].type;
  return type.kind == 'native' &&
      type.nativeType == 'flutter.Key' &&
      (property.constructorNullable || !type.nullable);
}

bool _containsOpaqueNativeArgument(Object? value) {
  if (value is ConstructorCall ||
      value is WidgetBuilderDeclaration ||
      value is AnyEventHandler) {
    return true;
  }
  if (value is Switch) {
    return _containsOpaqueNativeArgument(value.input) ||
        value.outputs.values.any(_containsOpaqueNativeArgument);
  }
  if (value is Loop) {
    return _containsOpaqueNativeArgument(value.input) ||
        _containsOpaqueNativeArgument(value.output);
  }
  if (value is Map) return value.values.any(_containsOpaqueNativeArgument);
  if (value is List) return value.any(_containsOpaqueNativeArgument);
  return false;
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
  if (property.type == PropertyType.edgeInsets && value is Map) {
    final directional = value.containsKey('start') || value.containsKey('end');
    final keys = directional
        ? const {'start', 'top', 'end', 'bottom'}
        : const {'left', 'top', 'right', 'bottom'};
    if (value.keys.any((key) => !keys.contains(key)) ||
        value.values.any(
          (component) =>
              component is String || component is bool || component == null,
        )) {
      issues.add(
        Issue(
          code: IssueCode.propertyValueTypeMismatch,
          message:
              "Property '${property.name}' on '$widgetName' has invalid inset components.",
          location: location,
        ),
      );
    }
  }
  if (_scalarValueMismatch(property.type, value)) {
    issues.add(
      Issue(
        code: IssueCode.propertyValueTypeMismatch,
        message:
            "Property '${property.name}' on '$widgetName' expects a "
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
    case PropertyType.widgetBuilder:
    case PropertyType.scalarCallback:
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
    case PropertyType.integerList:
    case PropertyType.realList:
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
