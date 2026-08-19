import 'package:meta/meta.dart';
import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/surface_models.dart';
import 'package:restage_shared/restage_shared.dart';

/// The control-plane RPC operation for generated publication uploads.
///
/// This operation is intentionally separate from the legacy draft and
/// lifecycle methods. It accepts one canonical
/// [SurfacePublicationUploadRequestV1] JSON document and performs publication
/// atomically.
const String surfacePublicationUploadMethod = 'publishPublication';

/// Result of one generated publication upload.
@experimental
@immutable
final class SurfacePublicationUploadResult {
  /// Construct a publication result.
  const SurfacePublicationUploadResult({
    required this.family,
    required this.storedRevision,
    required this.identityFrozen,
    this.activeRevision,
  });

  /// Exact family published by the operation.
  final SurfaceFamilyReferenceResult family;

  /// Newly stored immutable revision. This is not necessarily the revision
  /// selected for delivery when the identity is frozen.
  final int storedRevision;

  /// Active revision after the operation, when the control response provides
  /// it. This may remain unchanged when the identity is frozen.
  final int? activeRevision;

  /// Identity-wide freeze state after the operation.
  final bool identityFrozen;

  /// Wire-shaped spelling for callers that need to mirror the generated DTO.
  int get storedPublishedRevision => storedRevision;

  /// Wire-shaped spelling for the active delivery pointer.
  int? get activePublishedRevision => activeRevision;

  /// Stable description used by both surface publication commands.
  String get stateDescription =>
      'stored revision $storedRevision; '
      'active revision ${activeRevision ?? 'none'}; '
      'identity frozen: $identityFrozen.';

  /// Decode the small control response returned by the publication operation.
  factory SurfacePublicationUploadResult.fromWire(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException(
        'The publication response did not contain a stored revision.',
      );
    }
    final family = SurfaceFamilyReferenceResult.fromJson(value['family']);
    final storedRevision = value['storedPublishedRevision'];
    final activeRevision = value['activePublishedRevision'];
    final identityFrozen = value['identityFrozen'];
    if (storedRevision is! int || storedRevision < 1) {
      throw const FormatException(
        'The publication response did not contain a valid stored revision.',
      );
    }
    if (activeRevision != null &&
        (activeRevision is! int || activeRevision < 1)) {
      throw const FormatException(
        'The publication response contained an invalid active revision.',
      );
    }
    if (identityFrozen is! bool) {
      throw const FormatException(
        'The publication response did not contain freeze state.',
      );
    }
    return SurfacePublicationUploadResult(
      family: family,
      storedRevision: storedRevision,
      activeRevision: activeRevision as int?,
      identityFrozen: identityFrozen,
    );
  }

  /// Encode the generated publication-result JSON shape.
  Map<String, dynamic> toJson() => {
    '__className__': 'SurfaceContractPublicationResult',
    'family': family.toJson(),
    'storedPublishedRevision': storedRevision,
    if (activeRevision != null) 'activePublishedRevision': activeRevision,
    'identityFrozen': identityFrozen,
  };
}

/// Typed client for the one-operation generated publication path.
@experimental
final class SurfacePublicationApi {
  /// Build a publication API client backed by [api].
  SurfacePublicationApi(this._api);

  final RestageApi _api;

  /// Submit [request] as one canonical publication operation.
  ///
  /// The request is serialized with the shared strict codec and sent as the
  /// generated publication upload model. No draft-save or follow-up publish
  /// call is made.
  Future<SurfacePublicationUploadResult> publish({
    required String project,
    required String app,
    required String environment,
    required SurfacePublicationUploadRequestV1 request,
    int? environmentTargetId,
    RuntimePlane? runtimePlane,
    int? organizationId,
  }) async {
    final canonicalJson =
        SurfacePublicationUploadRequestV1Codec.encodeCanonicalJson(request);
    final raw = await _api.call('surface', surfacePublicationUploadMethod, {
      'projectSlug': project,
      'appSlug': app,
      'environmentSlug': environment,
      'upload': <String, dynamic>{
        '__className__': 'SurfacePublicationUpload',
        'canonicalJson': canonicalJson,
      },
      'environmentTargetId': ?environmentTargetId,
      'runtimePlane': ?runtimePlane?.wireName,
      'organizationId': ?organizationId,
    });
    try {
      return SurfacePublicationUploadResult.fromWire(raw);
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException(
        'The publication response could not be decoded.',
      );
    }
  }
}
