/// Restage Flutter SDK.
///
/// Renders bundled surface artifacts as real Flutter widgets through RFW.
/// Flow and paywall artifacts are declarative; host actions stay typed
/// app-owned callbacks installed by the app.
library;

export 'src/authoring/event_dispatcher.dart';
export 'src/authoring/flow_definition.dart';
export 'src/authoring/flow_source.dart';
export 'src/authoring/onboarding_event.dart';
export 'src/authoring/onboarding_event_dispatcher.dart';
export 'src/authoring/onboarding_source.dart';
export 'src/authoring/paywall_event.dart';
export 'src/authoring/paywall_price_for.dart';
export 'src/authoring/paywall_purchase.dart';
export 'src/authoring/paywall_source.dart';
export 'src/authoring/screen.dart';
export 'src/billing/billing_gateway.dart';
export 'src/billing/in_app_purchase_gateway.dart'
    hide PurchaseCoordinator, PurchaseProcessingContext;
export 'src/billing/signed_native_offer.dart';
export 'src/events/event_enums.dart';
export 'src/events/restage_event.dart';
export 'src/flow/flow_assignment.dart';
export 'src/flow/flow_chrome.dart';
export 'src/flow/flow_controller.dart' show RestageFlowController;
export 'src/flow/flow_descriptors.dart';
export 'src/flow/flow_experiment_artifact_metadata.dart'
    show FlowExperimentArtifactMetadata;
export 'src/flow/flow_predicates.dart';
// `ActiveArmFlowResolver` is an SDK-internal resolver capability (the active-arm
// seam); it is consumed within the package, not part of the public API.
export 'src/flow/flow_resolver.dart' hide ActiveArmFlowResolver;
export 'src/flow/flow_seed.dart';
export 'src/flow/flow_transitions.dart';
export 'src/flow/restage_flow_view.dart';
export 'src/flow/restage_onboarding.dart';
export 'src/flow/restage_surface_flow.dart';
export 'src/flow/restage_screen_view.dart';
export 'src/flow/server_flow_resolver.dart';
export 'src/flow/system_back_policy.dart';
export 'src/surface_screen/surface_screen.dart';
export 'package:restage_shared/restage_shared.dart'
    show
        ChildrenSlot,
        CapabilityManifest,
        EmitTarget,
        EntitlementSource,
        Ignore,
        RestageEntitlement,
        RestageLibrary,
        RestageProduct,
        RestageProperty,
        RestageWidget,
        RestageBundleEntryRoleV1,
        Surface,
        // ignore: deprecated_member_use
        SurfaceType,
        SurfacePayloadKind,
        SurfaceSourceKind,
        SurfaceExperimentAssignmentV1,
        FlowActionSchema,
        FlowActionSchemaField,
        FlowBranchPredicate,
        FlowContentHash,
        FlowDataType,
        FlowDeliveryMode,
        FlowPredicateCondition,
        FlowOutboundDeclarations,
        FlowOutboundField,
        FlowOutboundPayloadDeclaration,
        FlowOutboundRef,
        FlowStateClassification,
        FlowStateDeclaration,
        FlowStateWrite,
        FlowValueSource,
        ActionResultFlowValueSource,
        EqualsFlowPredicateCondition,
        EventFlowOutboundRef,
        EventFlowValueSource,
        ExistsFlowPredicateCondition,
        GreaterThanFlowPredicateCondition,
        GreaterThanOrEqualsFlowPredicateCondition,
        InFlowPredicateCondition,
        LessThanFlowPredicateCondition,
        LessThanOrEqualsFlowPredicateCondition,
        LibraryRequirement,
        LiteralFlowValueSource,
        NotEqualsFlowPredicateCondition,
        kReservedPreviewConstructorName,
        kReservedPreviewLibraryName,
        StateFlowOutboundRef,
        StateFlowValueSource,
        SubFlowResultFlowValueSource,
        WidgetCategory,
        WidgetLibrary,
        ignore;

export 'src/refresh/surface_refresh_trigger.dart';
export 'src/refresh/surface_update_channel.dart';
export 'src/resolver/asset_variant_resolver.dart';
export 'src/resolver/restage_variant_resolver.dart'
    hide stampFlowPayloadForDelivery, withoutAssignmentLeaseForDelivery;
// The exception thrown when a configured origin would transmit credentials or
// purchaser data over cleartext. Public so hosts can catch it by type.
export 'src/secure_transport.dart' show InsecureBaseUrlException;
export 'src/resolver/resolved_variant.dart';
export 'src/resolver/variant_resolver.dart';
export 'src/runtime/error_boundary.dart' show RuntimeErrorBoundary;
export 'src/runtime/restage.dart';
export 'src/runtime/restage_widget_factory.dart';
export 'src/runtime/restage_widget_library_registration.dart';
export 'src/runtime/rfw_constructor_presence.dart';
// RFW types host-side builder closures depend on. Re-exporting keeps
// hand-written extensions (and generated factory bodies) free of a direct
// `package:rfw` import.
export 'package:restage_core/restage_core.dart' show RestageDecoders;
export 'package:rfw/rfw.dart'
    show ArgumentDecoders, DataSource, LocalWidgetBuilder;
export 'src/runtime/restage_identity.dart';
export 'src/runtime/restage_paywall.dart' hide debugClearRestagePaywallCache;
export 'src/runtime/paywall_controller.dart';
export 'src/runtime/paywall_error.dart';
export 'src/runtime/state_variables.dart';
