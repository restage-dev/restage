/// Build-time code generator for the Restage SDK: translates a
/// server-driven UI surface authored in standard Flutter source (or a
/// hand-authored `.rfwtxt` file) into the `.rfwtxt` + `.rfw` artifacts and
/// catalogs the runtime consumes. Surface-general — the same machinery
/// serves paywalls, onboarding, messages, surveys, and any other surface.
///
/// Consumed via the `build.yaml` builders (see `builder.dart`), not by
/// importing this library API. The exports below are the build-time
/// toolchain's internal surface, not a stable contract.
library;

export 'src/a2ui/a2ui_catalog_adapter.dart' show emitA2uiCatalog;
export 'src/a2ui/a2ui_catalog_model.dart'
    show
        A2uiComponent,
        A2uiLibraryCapability,
        RestageCapabilityStamp,
        RestageStampedA2uiCatalog;
export 'src/a2ui/a2ui_dart_emitter.dart'
    show
        A2uiChildField,
        A2uiDartCatalogPlan,
        A2uiDartCoverage,
        A2uiDartCoverageReason,
        A2uiDartFieldOmission,
        A2uiDartFieldPlan,
        A2uiDartWidgetDrop,
        A2uiDartWidgetPlan,
        A2uiDataField,
        A2uiFieldEmission,
        classifyA2uiCatalogDart,
        emitA2uiCatalogDart;
export 'src/a2ui/a2ui_protocol.dart'
    show kA2uiProtocolVersion, kA2uiSchemaDialect;
export 'src/a2ui/a2ui_schema_node.dart'
    show
        A2uiChildNode,
        A2uiChildSlot,
        A2uiChildrenNode,
        A2uiScalarType,
        A2uiSchemaNode,
        EnumNode,
        ListNode,
        MapNode,
        ObjectNode,
        RefNode,
        ScalarNode,
        UnionNode;
export 'src/annotation_lookup.dart' show firstAnnotation;
export 'src/capability_derivation.dart'
    show CapabilityDerivationResult, deriveCapabilityManifest;
export 'src/catalog_loader.dart' show findWidgetsByName, loadMergedCatalog;
export 'src/emit_utils.dart' show formatGeneratedDart;
export 'src/factory_emitter.dart' show kSupportedSyntheticStrategies;
export 'src/issue.dart' show Issue, IssueCode;
export 'src/type_inference.dart' show inferPropertyType;
export 'src/user_catalog_emitter.dart' show emitUserCatalogDart;
export 'src/widget_visitor.dart' show WidgetVisitorResult, visitRestageWidgets;
