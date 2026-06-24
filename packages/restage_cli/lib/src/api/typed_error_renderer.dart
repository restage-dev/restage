import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/typed_error_models.dart';

/// Outcome of [renderGenericTypedError]: the exit code to return and the
/// stderr message to write.
class TypedErrorOutcome {
  /// Construct an outcome with the matching exit code + message.
  const TypedErrorOutcome(this.exitCode, this.message);

  /// Exit code the caller should return.
  final int exitCode;

  /// Human-readable message to write to stderr.
  final String message;
}

/// Render the legible message + exit code for a generic
/// [RestageApiException].
///
/// Returns:
///   - a [TypedErrorOutcome] for typed exceptions every command surfaces
///     uniformly (`ProjectNotFound`, `AppNotFound`, `Unauthorized`,
///     credential rot via HTTP 401/403, the catch-all non-200);
///   - a catch-all HTTP outcome for any other response body.
///
/// Callers with endpoint-specific typed exceptions should decode those
/// before calling this helper so they can keep command-specific wording.
TypedErrorOutcome? renderGenericTypedError(RestageApiException e) {
  final typed = decodeGenericTypedException(e.body);
  switch (typed) {
    case ProjectNotFound(:final projectSlug):
      return TypedErrorOutcome(
        1,
        'Project `$projectSlug` not found or you do not have access to it.',
      );
    case AppNotFound(:final appSlug, :final projectSlug):
      return TypedErrorOutcome(
        1,
        'App `$appSlug` not found under project `$projectSlug`.',
      );
    case UnauthorizedAccess():
      return const TypedErrorOutcome(
        1,
        'Not authorised. Sign in again with `restage login`.',
      );
    case null:
      if (e.statusCode == 401 || e.statusCode == 403) {
        return const TypedErrorOutcome(
          1,
          'The stored credential is no longer accepted by the server. '
          'Run `restage login` to refresh it.',
        );
      }
      return TypedErrorOutcome(
        2,
        'Could not contact the backend: HTTP ${e.statusCode} — ${e.body}',
      );
  }
}
