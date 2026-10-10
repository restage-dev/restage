import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:restage_cli/src/api/discovery_models.dart';

/// Sealed hierarchy for typed backend exceptions shared by multiple CLI
/// commands.
///
/// Paywall- and surface-specific exceptions stay in their own model files;
/// these variants are endpoint-agnostic and render the same way everywhere.
@experimental
@immutable
sealed class GenericTypedException implements Exception {
  const GenericTypedException();
}

/// A project with the requested slug does not exist (or the caller does
/// not own it). The wire field is `slug` on the server; the CLI exposes
/// it as [projectSlug] for clarity at the call site.
@experimental
class ProjectNotFound extends GenericTypedException {
  /// Construct with the missing [projectSlug].
  const ProjectNotFound({required this.projectSlug});

  /// Missing project slug.
  final String projectSlug;

  @override
  String toString() => 'ProjectNotFound(projectSlug: $projectSlug)';
}

/// An app with the requested slug does not exist under the resolved
/// project.
@experimental
class AppNotFound extends GenericTypedException {
  /// Construct with the missing [appSlug] and its parent [projectSlug].
  const AppNotFound({required this.appSlug, required this.projectSlug});

  /// Missing app slug.
  final String appSlug;

  /// Parent project slug.
  final String projectSlug;

  @override
  String toString() =>
      'AppNotFound(appSlug: $appSlug, projectSlug: $projectSlug)';
}

/// A surface id did not match the published id grammar.
@experimental
class SurfaceSlugRejected extends GenericTypedException {
  /// Construct with the refused [slug] and the [reason] it was refused.
  const SurfaceSlugRejected({required this.slug, required this.reason});

  /// The refused surface id.
  final String slug;

  /// The rule the id must satisfy.
  final String reason;

  @override
  String toString() => 'SurfaceSlugRejected(slug: $slug, reason: $reason)';
}

/// What keeps an app from being deleted, and how many things hold it.
@experimental
enum AppDeleteHoldKind {
  /// A surface serves in one of the app's environments.
  servingSurface,

  /// An API key of the app is active.
  activeApiKey,

  /// An experiment on the app is running or paused.
  runningExperiment,

  /// A delivery rule routes one of the app's surfaces.
  deliveryRule,

  /// The app is the only one in its project.
  lastAppInProject;

  /// Decode the wire name.
  static AppDeleteHoldKind? fromWireName(Object? value) {
    for (final kind in values) {
      if (kind.name == value) return kind;
    }
    return null;
  }
}

/// An app delete refused while something still uses the app. Maps from the
/// backend's `AppDeleteRefusedException`.
@experimental
class AppDeleteRefused extends GenericTypedException {
  /// Construct a refusal.
  const AppDeleteRefused({
    required this.appName,
    required this.projectName,
    required this.holds,
  });

  /// The app's name.
  final String appName;

  /// The app's project, named by the last-app hold.
  final String projectName;

  /// Each hold with its count, in the order the server named them.
  final List<({AppDeleteHoldKind kind, int count})> holds;
}

/// An app delete whose confirmation named another app. Maps from the
/// backend's `AppDeleteNameMismatchException`.
@experimental
class AppDeleteNameMismatch extends GenericTypedException {
  /// Construct with the app's actual [appName].
  const AppDeleteNameMismatch({required this.appName});

  /// The app's name.
  final String appName;
}

/// A measurement read named a window or selector it cannot answer.
@experimental
class MeasurementReadRejected extends GenericTypedException {
  /// Construct with the read's closed [reason] and its operator-readable
  /// [detail].
  const MeasurementReadRejected({required this.reason, required this.detail});

  /// The read transport's closed refusal reason.
  final String reason;

  /// What the caller must change.
  final String detail;

  @override
  String toString() =>
      'MeasurementReadRejected(reason: $reason, detail: $detail)';
}

/// Why the server refused a signed-in caller.
@experimental
enum UnauthorizedReason {
  /// The caller's role does not allow it.
  roleMissing,

  /// The request carries no signed-in session.
  notSignedIn,

  /// The credential kind may not call this.
  credentialNotAllowed,

  /// The organization's plan does not allow changes to the live plane.
  liveChangesNotAllowed,

  /// This needs a paid plan.
  paidPlanRequired,

  /// The sample workspace is read-only.
  sampleWorkspaceReadOnly,

  /// The caller's membership changed during the request.
  membershipChanged;

  /// Decode the wire name, defaulting to [roleMissing].
  static UnauthorizedReason fromWireName(Object? value) => values.firstWhere(
    (reason) => reason.name == value,
    orElse: () => roleMissing,
  );
}

/// The caller is not authorised to act on the named [resource]. Maps
/// from the backend's `UnauthorizedException`.
@experimental
class UnauthorizedAccess extends GenericTypedException {
  /// Construct with the offending [resource] name and why.
  const UnauthorizedAccess({
    required this.resource,
    this.reason = UnauthorizedReason.roleMissing,
  });

  /// Unauthorized resource.
  final String resource;

  /// Why the caller was refused.
  final UnauthorizedReason reason;

  @override
  String toString() =>
      'UnauthorizedAccess(resource: $resource, reason: ${reason.name})';
}

/// Why the server could not resolve a request's selectors to one target.
@experimental
enum TargetSelectionRefusal {
  /// No environment by that slug, or a target assertion does not hold.
  environmentNotFound,

  /// The environment has targets on both planes and the request named none.
  environmentOnBothPlanes,

  /// The environment has no target on the plane the request named.
  noTargetOnPlane,

  /// The caller belongs to no organization.
  noOrganization,

  /// The project is in more than one of the caller's organizations.
  multipleOrganizations,

  /// The named organization is not one of the caller's.
  organizationNotFound,

  /// A key's request names a target the key does not belong to.
  keyTargetMismatch;

  /// Decode the wire name.
  static TargetSelectionRefusal? fromWireName(Object? value) {
    for (final reason in values) {
      if (reason.name == value) return reason;
    }
    return null;
  }
}

/// The request's selectors name no single target. Maps from the backend's
/// `TargetSelectionRefusedException`.
@experimental
class TargetSelectionRefused extends GenericTypedException {
  /// Construct a refusal.
  const TargetSelectionRefused({
    required this.reason,
    this.environmentSlug,
    this.candidates = const [],
    this.organizationSlugs = const [],
  });

  /// Why the selectors were refused.
  final TargetSelectionRefusal reason;

  /// The environment the request named, when it named one.
  final String? environmentSlug;

  /// The targets an ambiguous environment offers.
  final List<EnvironmentTargetSummary> candidates;

  /// The caller's organizations an ambiguous project lives in.
  final List<String> organizationSlugs;

  @override
  String toString() =>
      'TargetSelectionRefused(reason: ${reason.name}, '
      'environmentSlug: $environmentSlug)';
}

/// Attempt to decode [body] as one of the shared typed exceptions.
///
/// Returns null when [body] is not a shared backend typed-exception
/// payload. Callers can then try command-specific decoders or fall
/// through to generic HTTP handling.
///
/// The backend returns a `SerializableException` as:
///
/// ```json
/// {"className": "<Name>", "data": {"__className__": "<Name>", ...fields}}
/// ```
@experimental
GenericTypedException? decodeGenericTypedException(String body) {
  if (body.isEmpty) return null;
  final dynamic doc;
  try {
    doc = jsonDecode(body);
  } on FormatException {
    return null;
  }
  if (doc is! Map<String, dynamic>) return null;
  final className = doc['className'];
  final data = doc['data'];
  if (className is! String || data is! Map<String, dynamic>) return null;
  switch (className) {
    case 'ProjectNotFoundException':
      return ProjectNotFound(projectSlug: data['slug'] as String);
    case 'AppNotFoundException':
      return AppNotFound(
        appSlug: data['appSlug'] as String,
        projectSlug: data['projectSlug'] as String,
      );
    case 'UnauthorizedException':
      return UnauthorizedAccess(
        resource: data['resource'] as String,
        reason: UnauthorizedReason.fromWireName(data['reason']),
      );
    case 'TargetSelectionRefusedException':
      final reason = TargetSelectionRefusal.fromWireName(data['reason']);
      if (reason == null) return null;
      return TargetSelectionRefused(
        reason: reason,
        environmentSlug: data['environmentSlug'] as String?,
        candidates: [
          for (final candidate in data['candidates'] as List<dynamic>? ?? [])
            EnvironmentTargetSummary.fromJson(
              candidate as Map<String, dynamic>,
            ),
        ],
        organizationSlugs: [
          for (final slug in data['organizationSlugs'] as List<dynamic>? ?? [])
            slug as String,
        ],
      );
    case 'SurfaceSlugRejectedException':
      return SurfaceSlugRejected(
        slug: data['slug'] as String,
        reason: data['reason'] as String,
      );
    case 'AppDeleteRefusedException':
      return AppDeleteRefused(
        appName: data['appName'] as String,
        projectName: data['projectName'] as String,
        holds: [
          for (final hold in data['holds'] as List<dynamic>? ?? [])
            if (AppDeleteHoldKind.fromWireName(
                  (hold as Map<String, dynamic>)['kind'],
                )
                case final kind?)
              (kind: kind, count: hold['count'] as int),
        ],
      );
    case 'AppDeleteNameMismatchException':
      return AppDeleteNameMismatch(appName: data['appName'] as String);
    case 'MeasurementReadRejectedException':
      return MeasurementReadRejected(
        reason: data['reason'] as String,
        detail: data['detail'] as String,
      );
    default:
      return null;
  }
}
