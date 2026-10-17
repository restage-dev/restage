/// HTTP/RPC clients, typed API wrappers and stored credentials for Restage tools.
/// Re-exported APIs are experimental and may change. Most integrations use
/// the `restage` executable.
library;

export 'package:restage_shared/restage_shared.dart'
    show
        LibraryRequirement,
        Surface,
        SurfaceSourceKind,
        SurfacePublicationUploadRequest,
        SurfacePublicationUploadRequestV1Codec,
        SurfaceType;

export 'package:restage_shared/restage_shared.dart'
    show
        PlacementScreenCaptureV1,
        PlacementSampleDraftV1,
        PlacementSamplePrepareV1,
        PlacementSampleUploadTicketV1,
        PlacementSampleUploadLimitsV1,
        PlacementSampleStoreV1,
        PlacementSampleStoredV1,
        PlacementSampleBindV1,
        PlacementScreenSampleRefV1,
        PlacementSampleReadV1,
        PlacementSampleReadResultV1,
        PlacementSampleDeleteV1,
        PlacementSampleDeleteResultV1,
        PlacementDirectoryRequestV1,
        PlacementDirectoryPageV1,
        PlacementReadRequestV1,
        PlacementReadV1,
        PlacementObservedHistoryReadRequestV1,
        PlacementObservedHistoryQueryV1,
        PlacementObservedHistoryV1,
        PlacementSimulationPageRequestV1,
        PlacementSimulationPageV1,
        kMaximumPlacementManagementRequestBytes,
        placementScreenSampleMaxBytes;

export 'src/api/app_admin_api.dart';
export 'src/api/auth_api.dart';
export 'src/api/auth_models.dart';
export 'src/api/byte_data_wire.dart';
export 'src/api/catalog_api.dart';
export 'src/api/default_endpoint.dart';
export 'src/api/discovery_api.dart';
export 'src/api/discovery_models.dart';
export 'src/api/delivery_management_api.dart';
export 'src/api/experiment_activation_api.dart';
export 'src/api/experiment_activation_host_transport.dart';
export 'src/api/experiment_api.dart';
export 'src/api/library_requirements_api.dart';
export 'src/api/measurement_page_api.dart';
export 'src/api/measurement_wire.dart';
export 'src/api/placement_sample_api.dart';
export 'src/api/programmatic_mutation_api.dart';
export 'src/api/render_bundle_api.dart';
export 'src/api/render_bundle_coverage_sentence.dart';
export 'src/api/surface_api.dart';
export 'src/api/surface_funnel_api.dart';
export 'src/api/surface_publication_api.dart';
export 'src/api/surface_routing_api.dart';
export 'src/api/typed_error_models.dart' hide typedErrorListItems;
export 'src/api/typed_error_renderer.dart'
    show
        TypedErrorOutcome,
        appNotFoundSentence,
        fitConfirmationSentence,
        renderApiError,
        staleCredentialSentence,
        typedErrorSentence,
        unauthorizedSentence;
export 'src/commands/surface_identity.dart'
    show
        SurfaceLifecycleIdentity,
        explicitLifecycleIdentity,
        kLifecycleSourceKinds,
        lookUpLifecycleIdentity,
        kLifecycleSurfaceTypes;
export 'src/commands/surface_publish_operation.dart'
    show
        FamilyTarget,
        SurfacePublication,
        familyHistory,
        familyTargetOf,
        mountGuide,
        mountLine,
        publishSurface;
export 'src/commands/target_resolution.dart'
    show ResolvedEnvironmentTargetContext, resolveTargetSelection;
export 'src/commands/surface_routing_command.dart'
    show isCanonicalOperationId, newOperationId;
export 'src/operations/operation.dart';
export 'src/delivery/delivery_operations.dart';
export 'src/delivery/measurement_impact.dart';
export 'src/delivery/policy_review.dart';
export 'src/measurement/page_read.dart';
export 'src/operations/operations.dart' show sharedOperation, sharedOperations;
export 'src/api/surface_models.dart';
export 'src/api/selector_syntax.dart';
export 'src/api/restage_api.dart'
    show
        FitDeclinedException,
        FitDecider,
        RestageApi,
        RestageApiException,
        InsecureEndpointException,
        decodeFitNeedsConfirmation,
        isAcceptableTransport;
export 'src/api/scope_snapshot_api.dart';
export 'src/config/restage_config.dart'
    show
        RestageConfig,
        RestageConfigFormatException,
        loadRestageConfig,
        resolveApiEndpoint,
        EndpointConfigurationException,
        EndpointFormatException,
        EndpointMismatchException;
export 'src/credentials/credential.dart';
export 'src/libraries/library_contract_check.dart';
export 'src/receipts/release_recorder.dart'
    show ReleaseRecorder, ReleaseRecorderException;
export 'src/credentials/file_credential_store.dart';
export 'src/config/config_target_check.dart' show noOrganizationSentence;
export 'src/docs/docs_search.dart';
