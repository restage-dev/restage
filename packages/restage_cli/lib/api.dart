/// Reusable Restage backend access layer: the HTTP/RPC wire, the auth-header
/// scheme, the typed paywall/auth wrappers, and the on-disk credential store.
///
/// This is promoted to a public library so other first-party tools can reuse a
/// single wire implementation, a single auth-header scheme, and a single
/// credential format instead of re-implementing them. Most users invoke the
/// `restage` binary directly and never import this library.
///
/// This surface exists for first-party reuse. Every symbol it re-exports is
/// annotated `@experimental` (from `package:meta`): the shape may change in a
/// future release, so external code that pins to it should expect to track
/// those changes. Most users invoke the `restage` binary directly and never
/// import this library.
library;

export 'package:restage_shared/restage_shared.dart'
    show LibraryRequirement, SurfaceType;

export 'src/api/auth_api.dart';
export 'src/api/auth_models.dart';
export 'src/api/paywall_api.dart';
export 'src/api/paywall_models.dart';
export 'src/api/surface_api.dart';
export 'src/api/typed_error_models.dart';
export 'src/api/surface_models.dart';
export 'src/api/restage_api.dart'
    show
        RestageApi,
        RestageApiException,
        InsecureEndpointException,
        isAcceptableTransport;
export 'src/credentials/credential.dart';
export 'src/credentials/file_credential_store.dart';
