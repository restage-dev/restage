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
        RestageBundleEntryRole,
        Surface,
        // ignore: deprecated_member_use
        SurfaceType,
        SurfacePayloadKind,
        SurfaceSourceKind,
        SurfaceExperimentAssignment,
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
export 'src/measurement/bundled_measurement_publication_binding_read_port.dart'
    show BundledMeasurementPublicationBindingReadPort;
export 'src/measurement/bundled_measurement_target_profile_loader.dart'
    hide enforceBundledMeasurementAssetByteLimitBeforeCopy;
export 'src/measurement/restage_measurement.dart';
export 'src/measurement/restage_privacy.dart';
export 'src/measurement/governed_measurement_transport.dart'
    show RestageGovernedMeasurementTransport;
// RFW types host-side builder closures depend on. Re-exporting keeps
// hand-written extensions (and generated factory bodies) free of a direct
// `package:rfw` import.
export 'package:restage_core/restage_core.dart' show RestageDecoders;
// The measurement contract types this package's own public API names, plus
// what a caller needs to use them. An explicit list rather than the whole
// contract package: re-exporting all of it made every future contract
// addition an addition to this package's published surface, silently. The list
// is derived from this barrel's own signatures rather than hand-kept, so it
// stays exactly as wide as the public API and no wider.
export 'package:restage_measurement_schema/restage_measurement_schema.dart'
    show
        AnalyticsSurfaceKey,
        AncestryNodeRefV1,
        ApplicationId,
        ArtifactId,
        ArtifactKindId,
        ArtifactOccurrenceEdgeToken,
        ArtifactOccurrenceEdgeV1,
        AuthorityRevisionId,
        CanonicalDigest,
        CanonicalDocument,
        CanonicalHashDomain,
        CanonicalNodeAncestryIndexV1,
        CanonicalNodeParentEdgeV1,
        CanonicalValue,
        CodeIdentityBindingV1,
        CodeIdentityId,
        CompleteMeasurementManifestV1,
        DeliverySurfaceTypeId,
        DisplayMetadataRef,
        EnvironmentTargetId,
        ExactArtifactGraphV1,
        GeneratedDartSymbol,
        GeneratedPointReferenceV1,
        GeneratedReferenceId,
        GovernancePolicyRefV1,
        LineageOperation,
        LineageTransitionAuthority,
        LineageTransitionId,
        LocalMeasurementManifestV1,
        MeasurementBundledGeneratedPublicationLocatorV1,
        MeasurementCapabilityKind,
        MeasurementCollectionClass,
        MeasurementConsentEvidence,
        MeasurementIdentifier,
        MeasurementLinkAcceptedV1,
        MeasurementLinkAction,
        MeasurementLinkChallengeAcceptedV1,
        MeasurementLinkChallengeFailedV1,
        MeasurementLinkChallengeOperationResultV1,
        MeasurementLinkChallengeRequestV1,
        MeasurementLinkChallengeV1,
        MeasurementLinkFailedV1,
        MeasurementLinkFailureCode,
        MeasurementLinkFailureV1,
        MeasurementLinkOperationResultV1,
        MeasurementLinkProvenance,
        MeasurementLinkReceiptResult,
        MeasurementLinkReceiptV1,
        MeasurementLinkRequestV1,
        MeasurementManifestId,
        MeasurementPointOccurrenceIdentityV1,
        MeasurementPointOccurrenceV1,
        MeasurementPrivacyClass,
        MeasurementPublicationAuthorityId,
        MeasurementPublicationBindingAbsent,
        MeasurementPublicationBindingMismatched,
        MeasurementPublicationBindingReadAccepted,
        MeasurementPublicationBindingReadResult,
        MeasurementPublicationBindingReferenceV1,
        MeasurementPublicationBindingReplayed,
        MeasurementPublicationBindingTransportUnavailable,
        MeasurementPublicationBindingUnsupportedFuture,
        MeasurementPublicationBindingV1,
        MeasurementPublicationBundledRegistryEntryV1,
        MeasurementPublicationBundledRegistryLocatorAbsent,
        MeasurementPublicationBundledRegistryLocatorAccepted,
        MeasurementPublicationBundledRegistryLocatorAmbiguous,
        MeasurementPublicationBundledRegistryLocatorResolution,
        MeasurementPublicationBundledRegistryV1,
        MeasurementPublicationCandidateArtifactTupleV1,
        MeasurementPublicationCandidateProofV1,
        MeasurementPublicationCandidateReferenceV1,
        MeasurementPublicationCurrentEndpointIntentV1,
        MeasurementPublicationDraftArtifactV1,
        MeasurementPublicationDraftEventV1,
        MeasurementPublicationDraftNodeV1,
        MeasurementPublicationDraftRouteSeedV1,
        MeasurementPublicationDraftRouteV1,
        MeasurementPublicationDraftV1,
        MeasurementPublicationLineageIntentV1,
        MeasurementPublicationMountedArtifactRoutesV1,
        MeasurementPublicationRouteArtifactV1,
        MeasurementPublicationRoutePlanV1,
        MeasurementPublicationRouteV1,
        MeasurementRegionEvidence,
        MeasurementRequesterBinding,
        MeasurementSubjectKind,
        MeasurementSubjectOperationAcceptedV1,
        MeasurementSubjectOperationAction,
        MeasurementSubjectOperationFailedV1,
        MeasurementSubjectOperationReceiptV1,
        MeasurementSubjectOperationRequestV1,
        MeasurementSubjectOperationResultV1,
        NamedEnvironmentId,
        NodeTokenId,
        NormalizedInteractionKind,
        OpaqueMeasurementRouteTokenV1,
        OrganizationId,
        PointLineageId,
        PositivePortableIntegerIdentifier,
        PublishedArtifactIdentityV1,
        PublishedArtifactV1,
        PublishedSurfaceIdentityV1,
        PublishedSurfaceRevisionV1,
        PurposePolicyRefV1,
        PurposePolicyRevisionId,
        RegisteredPublicationAttestationV1,
        RegisteredPublicationAuthorityReferenceV1,
        RestagePrivacyAction,
        RestagePrivacyCoordinatorStatus,
        RestagePrivacyDomainAuthority,
        RestagePrivacyDomainFailedV1,
        RestagePrivacyDomainFailureV1,
        RestagePrivacyDomainReceiptResultV1,
        RestagePrivacyDomainReceipt,
        RestagePrivacyDomainResult,
        RestagePrivacyDomainStatus,
        RestagePrivacyDomain,
        RestagePrivacyFailureCode,
        RestagePrivacyReceiptV1,
        RestagePrivacyRequestV1,
        RestagePrivacyTargets,
        RuntimePlane,
        SemanticValueClass,
        SourceEventIdentity,
        SubjectPolicyId,
        SubjectPolicyRefV1,
        SubjectPolicyRevisionId,
        SurfaceId,
        SurfaceRevisionId,
        TargetCoordinate;
export 'package:rfw/rfw.dart'
    show ArgumentDecoders, DataSource, LocalWidgetBuilder;
export 'src/runtime/restage_identity.dart';
export 'src/runtime/restage_paywall.dart' hide debugClearRestagePaywallCache;
export 'src/runtime/paywall_controller.dart';
export 'src/runtime/paywall_error.dart';
export 'src/runtime/state_variables.dart';
