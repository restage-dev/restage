/// Restage Flutter SDK.
///
/// Renders bundled paywall and onboarding artifacts as real Flutter widgets
/// through RFW. Flow and paywall artifacts are declarative; host actions stay
/// typed app-owned callbacks installed by the app.
library;

export 'src/authoring/event_dispatcher.dart';
export 'src/authoring/flow_source.dart';
export 'src/authoring/onboarding_event.dart';
export 'src/authoring/onboarding_event_dispatcher.dart';
export 'src/authoring/onboarding_source.dart';
export 'src/authoring/paywall_event.dart';
export 'src/authoring/paywall_price_for.dart';
export 'src/authoring/paywall_purchase.dart';
export 'src/authoring/paywall_source.dart';
export 'src/billing/billing_gateway.dart';
export 'src/billing/in_app_purchase_gateway.dart';
export 'src/billing/signed_native_offer.dart';
export 'src/events/event_enums.dart';
export 'src/events/restage_event.dart';
export 'src/flow/flow_chrome.dart';
export 'src/flow/flow_controller.dart' show RestageFlowController;
export 'src/flow/flow_descriptors.dart';
export 'src/flow/flow_resolver.dart';
export 'src/flow/flow_transitions.dart';
export 'src/flow/restage_flow_view.dart';
export 'src/flow/restage_onboarding.dart';
export 'src/flow/restage_screen_view.dart';
export 'src/flow/server_flow_resolver.dart';
export 'src/flow/system_back_policy.dart';
export 'package:restage_shared/restage_shared.dart'
    show
        ChildrenSlot,
        EntitlementSource,
        RestageEntitlement,
        RestageProduct,
        RestageProperty,
        RestageWidget,
        WidgetEventName,
        FlowActionSchema,
        FlowActionSchemaField,
        FlowBranchPredicate,
        FlowContentHash,
        FlowDataType,
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
        LiteralFlowValueSource,
        NotEqualsFlowPredicateCondition,
        StateFlowOutboundRef,
        StateFlowValueSource,
        SubFlowResultFlowValueSource,
        WidgetCategory,
        WidgetLibrary;

export 'src/resolver/asset_variant_resolver.dart';
export 'src/resolver/restage_variant_resolver.dart';
// The exception thrown when a configured origin would transmit credentials or
// purchaser data over cleartext. Public so hosts can catch it by type.
export 'src/secure_transport.dart' show InsecureBaseUrlException;
export 'src/resolver/resolved_variant.dart';
export 'src/resolver/variant_resolver.dart';
export 'src/runtime/restage.dart';
export 'src/runtime/restage_widget_factory.dart';
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
