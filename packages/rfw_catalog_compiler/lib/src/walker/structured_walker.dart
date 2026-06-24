import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:meta/meta.dart';
import 'package:rfw_catalog_compiler/src/ir/diagnostic.dart';
import 'package:rfw_catalog_compiler/src/ir/factory_variant_ir.dart';
import 'package:rfw_catalog_compiler/src/ir/policy_decision.dart';
import 'package:rfw_catalog_compiler/src/ir/property_ir.dart';
import 'package:rfw_catalog_compiler/src/ir/provenance.dart';
import 'package:rfw_catalog_compiler/src/ir/structured_ir.dart';
import 'package:rfw_catalog_compiler/src/ir/type_ir.dart';
import 'package:rfw_catalog_compiler/src/policy/denylist_filter.dart';
import 'package:rfw_catalog_compiler/src/policy/policy_ledger.dart';
import 'package:rfw_catalog_compiler/src/walker/abstract_type_fallback.dart';
import 'package:rfw_catalog_compiler/src/walker/dart_ui_doc_fallbacks.dart';
import 'package:rfw_catalog_compiler/src/walker/dartdoc.dart';
import 'package:rfw_catalog_compiler/src/walker/element_fqn.dart';
import 'package:rfw_catalog_compiler/src/walker/factory_variant_enumerator.dart';
import 'package:rfw_catalog_compiler/src/walker/structured_type_predicate.dart';
import 'package:rfw_catalog_compiler/src/walker/value_shape_resolver.dart';
import 'package:rfw_catalog_compiler/src/walker/walker_issue_codes.dart'
    as issue_codes;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Result of walking one structured type entry point.
@immutable
final class StructuredWalkResult {
  /// Creates a structured walk result.
  const StructuredWalkResult({
    required this.ir,
    required this.descendants,
  });

  /// IR for the requested type. A cycle or depth-budget cutoff yields a
  /// placeholder IR carrying that diagnostic rather than dropping the entry.
  final StructuredIR? ir;

  /// Structured field types discovered while walking this entry point.
  final List<StructuredIR> descendants;
}

/// Walks a structured value type and returns its compiler IR.
StructuredWalkResult walkStructuredType({
  required ClassElement element,
  required WidgetLibrary library,
  required PolicyLedger policy,
  required String location,
  required Set<String> visited,
  required int depth,
}) {
  if (depth < 0) {
    throw ArgumentError.value(depth, 'depth', 'must be non-negative');
  }

  // Bounded recursion: short-circuit before any FQN work if the caller has
  // already descended past the configured depth budget. The budget defends
  // against pathologically deep or self-referential type graphs.
  final maxDepth = policy.structuredWalk.maxDepth;
  if (depth > maxDepth) {
    return StructuredWalkResult(
      ir: _structuredIr(
        element: element,
        library: library,
        location: location,
        diagnostics: [
          DiagnosticIR(
            code: issue_codes.structuredDepthExceeded,
            message: 'Structured-type walk exceeded the configured depth '
                'budget ($maxDepth) at ${element.name ?? '<unnamed>'}.',
            location: location,
            severity: DiagnosticSeverity.info,
            target: element.name,
          ),
        ],
      ),
      descendants: const [],
    );
  }

  final fqn = elementFqn(element);
  final kind = classifyStructured(element.thisType, policy);

  return switch (kind) {
    StructuredKind.abstractBase => StructuredWalkResult(
        ir: _structuredIr(
          element: element,
          library: library,
          location: location,
          diagnostics: [
            _abstractDiagnostic(location: location, target: element.name),
          ],
        ),
        descendants: const [],
      ),
    StructuredKind.notStructured => throw ArgumentError.value(
        fqn,
        'element',
        'ClassElement is not classified as a structured type.',
      ),
    StructuredKind.concrete => _walkConcrete(
        element: element,
        library: library,
        policy: policy,
        location: location,
        visited: visited,
        fqn: fqn,
      ),
  };
}

StructuredWalkResult _walkConcrete({
  required ClassElement element,
  required WidgetLibrary library,
  required PolicyLedger policy,
  required String location,
  required Set<String> visited,
  required String fqn,
}) {
  if (!visited.add(fqn)) {
    // The FQN was already encountered earlier in this walk pass — emit a
    // placeholder IR carrying the cycle diagnostic so downstream stages
    // can surface the bounded-walk decision without losing the entry.
    return StructuredWalkResult(
      ir: _structuredIr(
        element: element,
        library: library,
        location: location,
        diagnostics: [
          DiagnosticIR(
            code: issue_codes.structuredCycle,
            message: 'Structured type ${element.name ?? '<unnamed>'} '
                'was already walked in this pass.',
            location: location,
            severity: DiagnosticSeverity.info,
            target: element.name,
          ),
        ],
      ),
      descendants: const [],
    );
  }

  final fields = <StructuredFieldIR>[];
  final diagnostics = <DiagnosticIR>[];
  final policyTrace = <PolicyDecisionIR>[];
  final descendants = <StructuredIR>[];
  final descendantFqns = <String>{};
  // Registered abstract-union bases referenced by this type's fields.
  // Surfaced on the resulting IR so a later pass can resolve each into a
  // discriminated union; the walker itself records only the FQN.
  final referencedUnionFqns = <String>{};

  // The constructible state of a value type is what its public *generative*
  // constructors accept. A getter-backed member (Offset exposes dx/dy as
  // getters over private fields) is kept only when a generative constructor
  // names it; a value reachable solely through a *factory* constructor is a
  // conversion (Offset.fromDirection computes dx/dy from polar inputs), not
  // stored state, so factory parameters do not count. This is the discriminator
  // that separates real value fields from computed getters (distance,
  // isUniform, preferPaintInterior) without a deprecated synthetic-field API.
  final generativeConstructorParameterNames = <String>{
    for (final constructor in element.constructors)
      if (!constructor.isFactory)
        for (final parameter in constructor.formalParameters)
          if (parameter.name case final name? when name.isNotEmpty) name,
  };

  for (final field in element.fields) {
    final fieldName = field.name;
    if (fieldName == null || fieldName.isEmpty || fieldName.startsWith('_')) {
      continue;
    }
    if (field.isStatic) continue;
    if (_isComputedGetterField(field, generativeConstructorParameterNames)) {
      continue;
    }

    final denylistMatch = DenylistFilter.match(field.type, policy);
    if (denylistMatch != null) {
      policyTrace.add(
        PolicyDecisionIR(
          policy: denylistMatch.policy,
          decision: 'excluded',
          reason: denylistMatch.reason,
          target: fieldName,
        ),
      );
      diagnostics.add(
        DiagnosticIR(
          code: issue_codes.denylistedPropertyType,
          message: '${denylistMatch.reason} on ${element.name}.$fieldName',
          location: location,
          severity: DiagnosticSeverity.warning,
          target: fieldName,
        ),
      );
      continue;
    }

    final scalarKind = _inlineScalarKind(field.type);
    if (scalarKind != null) {
      fields.add(
        _structuredField(
          field,
          ownerSourceType: fqn,
          kind: scalarKind,
          valueShape: _scalarValueShape(scalarKind, field.type),
        ),
      );
      continue;
    }

    switch (classifyStructured(field.type, policy)) {
      case StructuredKind.concrete:
        final descendant = classElementFor(field.type);
        final descendantFqn =
            descendant == null ? null : elementFqn(descendant);
        // The descendant's wire ID resolves in a later allocator pass.
        // Until then the structuredRef carries the unallocated structured
        // sentinel paired with the owning library so the allocator can
        // resolve by FQN.
        final structuredRef = descendant != null
            ? WireIdRef(
                library: library.namespace,
                wireId: WireId.unallocatedStructured,
              )
            : null;
        fields.add(
          _structuredField(
            field,
            ownerSourceType: fqn,
            structuredRef: structuredRef,
            structuredRefFqn: descendantFqn,
            valueShape: structuredRef == null
                ? null
                : StructuredShape(
                    propertyType: PropertyType.structured,
                    structuredRef: structuredRef,
                  ),
          ),
        );
        if (descendant != null && descendantFqn != null) {
          if (descendantFqns.add(descendantFqn)) {
            // The descendant is materialized as a shallow stub — its own
            // fields are not re-walked here. A later allocator pass resolves
            // the stub's wire ID, but the shallow walk never follows the
            // descendant's *own* abstract-base / union references. When the
            // descendant declares such a field, attach an informational
            // diagnostic to the stub so the unfollowed reference is visible
            // (rather than silently dropped). No current built-in catalog
            // reaches a registered union past the direct walk path, so this
            // guard fires only on deeper customer type graphs.
            final stubDiagnostics = _descendantCarriesUnionReference(
              descendant,
              policy,
            )
                ? <DiagnosticIR>[
                    DiagnosticIR(
                      code: issue_codes.descendantUnionReferenceUndiscovered,
                      message: 'Structured descendant '
                          '${descendant.name ?? '<unnamed>'} carries '
                          'abstract-base / union fields that the shallow '
                          'descendant walk does not resolve.',
                      location: location,
                      severity: DiagnosticSeverity.info,
                      target: descendant.name,
                    ),
                  ]
                : const <DiagnosticIR>[];
            descendants.add(
              _structuredIr(
                element: descendant,
                library: library,
                location: location,
                diagnostics: stubDiagnostics,
              ),
            );
          }
        }
      case StructuredKind.abstractBase:
        // Consult the shared abstract-base fallback map (same one the
        // top-level property path uses). When a legacy PropertyType
        // exists for this abstract type — e.g. Gradient -> gradient,
        // BoxBorder -> border — lower the field to that kind so the
        // wire shape is internally consistent. The no-fallback abstract
        // bases keep `ResolvedTypeKind.structured`.
        final fallback = abstractStructuredFallback(field.type);
        final kind = fallback == null
            ? ResolvedTypeKind.structured
            : _abstractFallbackKind(fallback);
        // When the abstract base is a registered union, attach a union
        // reference. The union's wire ID resolves in a later allocator
        // pass; until then the reference carries the unallocated-union
        // sentinel paired with the owning library, mirroring how
        // structuredRef carries the unallocated-structured sentinel for
        // descendant references. This keeps a `structured`-kinded field
        // from emitting with neither a structuredRef nor a unionRef.
        final fieldFqn = typeFqn(field.type);
        final registeredUnionFqn =
            fieldFqn != null && policy.unionRegistry.lookup(fieldFqn) != null
                ? fieldFqn
                : null;
        final unionRef = registeredUnionFqn != null
            ? WireIdRef(
                library: library.namespace,
                wireId: WireId.unallocatedUnion,
              )
            : null;
        // Record the registered base's FQN so a later reference-driven
        // pass can resolve the union this field's `unionRef` points at.
        if (registeredUnionFqn != null) {
          referencedUnionFqns.add(registeredUnionFqn);
        }
        fields.add(
          _structuredField(
            field,
            ownerSourceType: fqn,
            kind: kind,
            unionRef: unionRef,
            unionSourceKey: registeredUnionFqn == null
                ? null
                : '${library.namespace}#$registeredUnionFqn',
            valueShape: _abstractValueShape(
              kind: kind,
              unionRef: unionRef,
            ),
            diagnostics: [
              _abstractDiagnostic(location: location, target: fieldName),
            ],
          ),
        );
      case StructuredKind.notStructured:
        // The branches above handle the value types the structured-walk
        // policy enumerates (concrete structured types + registered abstract
        // unions) and the inline primitives. Everything else historically
        // dropped here with a warning — silently losing enum / typed-scalar /
        // `List` / `WidgetStateProperty`-wrapped fields the recipe path
        // already materializes. Route those through the shared value-shape
        // resolver so the two producers agree.
        //
        // Only NON-LINKING shapes (scalar / enum / list-of-scalar) are
        // materialized here. A structured/union/box-shadow-list result is a
        // type the policy did not enumerate, so it carries no descendant stub
        // or union back-reference — materializing it would risk a dangling
        // ref at link time. Those keep the warning + drop (a policy gap, not a
        // walker concern). `referencedUnionFqns` is left null: this fallback
        // never keeps a union result, so it must not contribute an FQN to the
        // type's referenced-union set (the resolver's union path no-ops the
        // null add).
        final resolved = resolveValueShape(
          field.type,
          library: library,
          policy: policy,
        );
        if (resolved != null && !valueShapeNeedsLinking(resolved)) {
          fields.add(
            _structuredField(
              field,
              ownerSourceType: fqn,
              kind: _resolvedKindForPropertyType(resolved.propertyType),
              valueShape: resolved,
            ),
          );
        } else {
          diagnostics.add(
            DiagnosticIR(
              code: issue_codes.unsupportedPropertyType,
              message: 'Unsupported structured field type '
                  '${field.type.getDisplayString()} on '
                  '${element.name}.$fieldName.',
              location: location,
              severity: DiagnosticSeverity.warning,
              target: fieldName,
            ),
          );
        }
    }
  }

  final variantEnumeration = enumerateFactoryVariants(
    element: element,
    fields: fields,
    policy: policy,
  );
  policyTrace.addAll(variantEnumeration.policyTrace);

  return StructuredWalkResult(
    ir: _structuredIr(
      element: element,
      library: library,
      location: location,
      fields: fields,
      variants: variantEnumeration.variants,
      diagnostics: diagnostics,
      policyTrace: policyTrace,
      referencedUnionFqns: referencedUnionFqns,
    ),
    descendants: descendants,
  );
}

StructuredIR _structuredIr({
  required ClassElement element,
  required WidgetLibrary library,
  required String location,
  List<StructuredFieldIR> fields = const [],
  List<FactoryVariantIR> variants = const [],
  List<DiagnosticIR> diagnostics = const [],
  List<PolicyDecisionIR> policyTrace = const [],
  Set<String> referencedUnionFqns = const {},
}) {
  final sourceType = elementFqn(element);
  return StructuredIR(
    wireId: WireId.unallocatedStructured,
    source: element,
    name: element.name ?? '<unnamed>',
    library: library,
    description: stripDartdocSlashes(element.documentationComment) ??
        dartUiClassDescription(sourceType) ??
        '',
    fields: fields,
    variants: variants,
    stability: Stability.volatile,
    diagnostics: diagnostics,
    provenance: ProvenanceIR(
      flutterType: sourceType,
      curationSource: location,
      derivationTrace: const ['structured_walker'],
    ),
    policyTrace: policyTrace,
    referencedUnionFqns: Set<String>.unmodifiable(referencedUnionFqns),
  );
}

StructuredFieldIR _structuredField(
  FieldElement field, {
  required String ownerSourceType,
  ResolvedTypeKind kind = ResolvedTypeKind.structured,
  WireIdRef? structuredRef,
  WireIdRef? unionRef,
  String? structuredRefFqn,
  String? unionSourceKey,
  CatalogValueShape? valueShape,
  List<DiagnosticIR> diagnostics = const [],
}) {
  return StructuredFieldIR(
    wireId: WireId.unallocatedProperty,
    source: field,
    name: field.name ?? '<unnamed>',
    type: ResolvedType(
      kind: kind,
      dartType: field.type,
      structuredRef: structuredRef,
      unionRef: unionRef,
      valueShape: valueShape,
    ),
    description: stripDartdocSlashes(field.documentationComment) ??
        dartUiFieldDescription(ownerSourceType, field.name ?? '') ??
        '',
    defaultSource: null,
    metadata: const PropertyMetadataIR(),
    diagnostics: diagnostics,
    structuredRefFqn: structuredRefFqn,
    unionSourceKey: unionSourceKey,
  );
}

DiagnosticIR _abstractDiagnostic({
  required String location,
  required String? target,
}) {
  return DiagnosticIR(
    code: issue_codes.abstractTypeAwaitingUnion,
    message: 'Abstract structured type awaits union resolution.',
    location: location,
    severity: DiagnosticSeverity.info,
    target: target,
  );
}

// Narrow projection for the abstract-base fallback set. The map is
// bound to whatever members the shared [abstractStructuredFallback]
// helper returns — extending the schema with a new abstract base
// goes through both the helper and this projection in lockstep.
ResolvedTypeKind _abstractFallbackKind(PropertyType fallback) {
  return switch (fallback) {
    PropertyType.gradient => ResolvedTypeKind.gradient,
    PropertyType.border => ResolvedTypeKind.border,
    PropertyType.shapeBorder => ResolvedTypeKind.shapeBorder,
    _ => throw StateError(
        'abstractStructuredFallback returned $fallback, which has no '
        'matching ResolvedTypeKind projection. Add a case here when '
        'extending the abstract-base fallback map.',
      ),
  };
}

/// Whether [descendant] declares a field whose type is a registered abstract
/// base (the types that resolve into discriminated unions on the direct walk
/// path).
///
/// Reuses the same shallow field classification the direct walk applies in its
/// `abstractBase` branch — it does NOT recurse, and it does NOT resolve the
/// union. It only answers "does the shallow descendant walk leave an
/// abstract-base / union reference unfollowed?" so the caller can attach an
/// informational diagnostic. The private / static / computed-getter skips
/// mirror the direct field loop so a getter-backed computed member is not
/// mistaken for an unresolved reference.
bool _descendantCarriesUnionReference(
  ClassElement descendant,
  PolicyLedger policy,
) {
  final generativeConstructorParameterNames = <String>{
    for (final constructor in descendant.constructors)
      if (!constructor.isFactory)
        for (final parameter in constructor.formalParameters)
          if (parameter.name case final name? when name.isNotEmpty) name,
  };
  for (final field in descendant.fields) {
    final fieldName = field.name;
    if (fieldName == null || fieldName.isEmpty || fieldName.startsWith('_')) {
      continue;
    }
    if (field.isStatic) continue;
    if (_isComputedGetterField(field, generativeConstructorParameterNames)) {
      continue;
    }
    if (classifyStructured(field.type, policy) == StructuredKind.abstractBase) {
      return true;
    }
  }
  return false;
}

/// Whether [field] is a computed getter rather than constructible state.
///
/// A non-getter-backed declared field is always kept. A getter-backed field
/// (`isOriginGetterSetter`) is kept only when the parameter-name set —
/// the union of every public generative constructor's parameter names —
/// contains it: that is the type's settable state. Computed getters
/// (`Offset.distance`, `Border.isUniform`), override getters
/// (`*Border.preferPaintInterior`), and the universal `Object` getters
/// (`hashCode` / `runtimeType`) reach no generative constructor and are dropped.
/// KEEP-on-doubt: anything a generative constructor names is retained.
bool _isComputedGetterField(
  FieldElement field,
  Set<String> generativeConstructorParameterNames,
) {
  if (!field.isOriginGetterSetter) return false;
  return !generativeConstructorParameterNames.contains(field.name);
}

/// Maps a schema [PropertyType] to its compiler [ResolvedTypeKind].
///
/// The inverse of [ResolvedType.loweredPropertyType]. Used by the
/// `notStructured` fallback to give a resolver-materialized field its
/// compiler-level kind directly from the value shape's `propertyType` (every
/// shape — including [EnumShape], whose `propertyType` is `enumValue` — carries
/// the correct discriminator). Total over [PropertyType]; the
/// [PropertyType.unknown] sentinel never originates from a resolver shape and
/// throws if it somehow reaches here.
ResolvedTypeKind _resolvedKindForPropertyType(PropertyType type) {
  return switch (type) {
    PropertyType.boolean => ResolvedTypeKind.boolean,
    PropertyType.integer => ResolvedTypeKind.integer,
    PropertyType.real => ResolvedTypeKind.real,
    PropertyType.length => ResolvedTypeKind.length,
    PropertyType.string => ResolvedTypeKind.string,
    PropertyType.stringList => ResolvedTypeKind.stringList,
    PropertyType.booleanList => ResolvedTypeKind.booleanList,
    PropertyType.color => ResolvedTypeKind.color,
    PropertyType.edgeInsets => ResolvedTypeKind.edgeInsets,
    PropertyType.alignment => ResolvedTypeKind.alignment,
    PropertyType.alignmentXY => ResolvedTypeKind.alignmentXY,
    PropertyType.offset => ResolvedTypeKind.offset,
    PropertyType.fontWeight => ResolvedTypeKind.fontWeight,
    PropertyType.duration => ResolvedTypeKind.duration,
    PropertyType.curve => ResolvedTypeKind.curve,
    PropertyType.locale => ResolvedTypeKind.locale,
    PropertyType.paint => ResolvedTypeKind.paint,
    PropertyType.shadowList => ResolvedTypeKind.shadowList,
    PropertyType.fontFeatureList => ResolvedTypeKind.fontFeatureList,
    PropertyType.fontVariationList => ResolvedTypeKind.fontVariationList,
    PropertyType.textDecoration => ResolvedTypeKind.textDecoration,
    PropertyType.enumValue => ResolvedTypeKind.enumValue,
    PropertyType.gradient => ResolvedTypeKind.gradient,
    PropertyType.border => ResolvedTypeKind.border,
    PropertyType.shapeBorder => ResolvedTypeKind.shapeBorder,
    PropertyType.boxShadowList => ResolvedTypeKind.boxShadowList,
    PropertyType.structured => ResolvedTypeKind.structured,
    PropertyType.inlineSpan => ResolvedTypeKind.inlineSpan,
    PropertyType.decorationImage => ResolvedTypeKind.decorationImage,
    PropertyType.selectionOptionList => ResolvedTypeKind.selectionOptionList,
    PropertyType.widget => ResolvedTypeKind.widget,
    PropertyType.widgetList => ResolvedTypeKind.widgetList,
    PropertyType.event => ResolvedTypeKind.event,
    PropertyType.dataReference => ResolvedTypeKind.dataReference,
    PropertyType.unknown => throw ArgumentError.value(
        type,
        'type',
        'PropertyType.unknown has no ResolvedTypeKind; a resolver value '
            'shape never carries it.',
      ),
  };
}

ResolvedTypeKind? _inlineScalarKind(DartType type) {
  switch (_displayName(type)) {
    case 'Color':
      return ResolvedTypeKind.color;
    case 'double':
    case 'num':
      return ResolvedTypeKind.real;
    case 'int':
      return ResolvedTypeKind.integer;
    case 'String':
      return ResolvedTypeKind.string;
    case 'bool':
      return ResolvedTypeKind.boolean;
  }
  return null;
}

CatalogValueShape? _scalarValueShape(ResolvedTypeKind kind, DartType type) {
  final propertyType = switch (kind) {
    ResolvedTypeKind.boolean => PropertyType.boolean,
    ResolvedTypeKind.integer => PropertyType.integer,
    ResolvedTypeKind.real => PropertyType.real,
    ResolvedTypeKind.length => PropertyType.length,
    ResolvedTypeKind.string => PropertyType.string,
    ResolvedTypeKind.color => PropertyType.color,
    ResolvedTypeKind.edgeInsets => PropertyType.edgeInsets,
    ResolvedTypeKind.alignment => PropertyType.alignment,
    ResolvedTypeKind.alignmentXY => PropertyType.alignmentXY,
    ResolvedTypeKind.offset => PropertyType.offset,
    ResolvedTypeKind.fontWeight => PropertyType.fontWeight,
    ResolvedTypeKind.duration => PropertyType.duration,
    ResolvedTypeKind.curve => PropertyType.curve,
    _ => null,
  };
  if (propertyType == null) return null;
  return ScalarShape(
    propertyType: propertyType,
    dartTypeRef: _dartTypeRef(type),
  );
}

CatalogValueShape? _abstractValueShape({
  required ResolvedTypeKind kind,
  required WireIdRef? unionRef,
}) {
  final propertyType = switch (kind) {
    ResolvedTypeKind.gradient => PropertyType.gradient,
    ResolvedTypeKind.border => PropertyType.border,
    ResolvedTypeKind.shapeBorder => PropertyType.shapeBorder,
    _ => null,
  };
  if (propertyType == null || unionRef == null) return null;
  return UnionShape(
    propertyType: propertyType,
    unionRef: unionRef,
    wireCodec: switch (propertyType) {
      PropertyType.gradient => CatalogWireCodec.rfwGradient,
      PropertyType.border => CatalogWireCodec.rfwBorder,
      PropertyType.shapeBorder => CatalogWireCodec.rfwShapeBorder,
      _ => null,
    },
  );
}

DartTypeRef? _dartTypeRef(DartType type) {
  final element = type.element;
  final name = element?.name;
  final library = element?.library;
  if (name == null || name.isEmpty || library == null) return null;
  return DartTypeRef(libraryUri: library.identifier, symbolName: name);
}

String _displayName(DartType type) {
  final displayName = type.getDisplayString();
  if (displayName.endsWith('?') || displayName.endsWith('*')) {
    return displayName.substring(0, displayName.length - 1);
  }
  return displayName;
}
