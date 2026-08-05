/// Public entry point for the Remote Flutter Widget catalog compiler.
///
/// The compiler's full internal IR lives under `src/ir`; selected walker and
/// lowering entry points are exported for reflector integration.
library;

export 'src/adapter/restage_catalog_gen_adapter.dart';
export 'src/diff/diff.dart';
export 'src/ir/diagnostic.dart' show DiagnosticIR, DiagnosticSeverity;
export 'src/ir/ir_lower.dart' show lowerStructured, lowerUnion;
export 'src/ir/policy_decision.dart';
export 'src/link/cross_ref_resolution_index.dart';
export 'src/link/link_cross_references.dart';
export 'src/policy/policy.dart';
export 'src/walker/abstract_type_fallback.dart' show abstractStructuredFallback;
export 'src/walker/default_value_resolver.dart'
    show
        literalFromDartObject,
        resolveDefaultFromConstant,
        resolveParameterDefault,
        resolveThemeBindingDefault,
        staticConstMemberName;
export 'src/walker/element_fqn.dart'
    show
        classElementFor,
        dartCoreMapType,
        elementFqn,
        interfaceFqn,
        interfaceFqnOrNull,
        listItemType,
        mapValueType,
        typeFqn;
export 'src/walker/library_walker.dart'
    show LibraryWalkResult, RestageLibraryDeclaration, walkRestageLibrary;
export 'src/walker/map_shape_resolver.dart'
    show
        MapAdmitted,
        MapClassification,
        MapExcluded,
        MapKeyKind,
        NotAMap,
        classifyMapType;
export 'src/walker/record_shape_resolver.dart'
    show
        NotARecord,
        RecordAdmitted,
        RecordClassification,
        RecordExcluded,
        RecordLabel,
        classifyRecordType;
export 'src/walker/structured_description_resolver.dart'
    show
        StructuredDescriptionConflict,
        StructuredDescriptionResolution,
        resolveStructuredDescriptions;
export 'src/walker/structured_type_predicate.dart'
    show StructuredKind, classifyStructured;
export 'src/walker/structured_walker.dart'
    show StructuredWalkResult, walkStructuredType;
export 'src/walker/union_resolver.dart'
    show MemberElementResolver, UnionResolution, resolveUnion;
export 'src/walker/value_shape_resolver.dart'
    show knownRecipeStructuredTypes, resolveValueShape, valueShapeNeedsLinking;
export 'src/walker/walker_issue_codes.dart'
    show
        abstractTypeAwaitingUnion,
        restageLibraryForeignWidget,
        restageLibraryMalformed,
        restageLibraryReservedNamespace,
        restageLibraryUnexportedWidget,
        structuredCycle,
        structuredDepthExceeded,
        structuredDescriptionConflict,
        structuredFactoryUnsupportedParam,
        unionMemberInvalid,
        unionMemberUnresolved;
export 'src/wire_ids/wire_id_backfill.dart';
export 'src/wire_ids/wire_ids.dart';
