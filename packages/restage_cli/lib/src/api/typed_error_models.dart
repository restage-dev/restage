import 'dart:convert';

import 'package:meta/meta.dart';

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

/// The caller is not authorised to act on the named [resource]. Maps
/// from the backend's `UnauthorizedException`.
@experimental
class UnauthorizedAccess extends GenericTypedException {
  /// Construct with the offending [resource] name.
  const UnauthorizedAccess({required this.resource});

  /// Unauthorized resource.
  final String resource;

  @override
  String toString() => 'UnauthorizedAccess(resource: $resource)';
}

/// Attempt to decode [body] as one of the shared typed exceptions.
///
/// Returns null when [body] is not a shared Serverpod typed-exception
/// payload. Callers can then try command-specific decoders or fall
/// through to generic HTTP handling.
///
/// Serverpod 3 returns a `SerializableException` as:
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
      return UnauthorizedAccess(resource: data['resource'] as String);
    default:
      return null;
  }
}
