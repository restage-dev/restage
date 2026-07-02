import 'package:meta/meta.dart';

/// One organization the signed-in user belongs to.
///
/// Unknown fields in the backend view are ignored so this client can keep
/// decoding when the server adds fields the CLI does not use.
@experimental
@immutable
class OrganizationSummary {
  /// Construct an organization summary.
  const OrganizationSummary({
    required this.organizationId,
    required this.slug,
    required this.name,
  });

  /// Stable backend id for the organization.
  final int organizationId;

  /// Human-readable organization slug.
  final String slug;

  /// Display name.
  final String name;

  /// Decode from the backend's organization membership view.
  factory OrganizationSummary.fromJson(Map<String, dynamic> json) =>
      OrganizationSummary(
        organizationId: json['organizationId']! as int,
        slug: json['slug']! as String,
        name: json['name']! as String,
      );
}

/// A project under an organization.
@experimental
@immutable
class ProjectSummary {
  /// Construct a project summary.
  const ProjectSummary({required this.slug, required this.name});

  /// Project slug.
  final String slug;

  /// Display name.
  final String name;

  /// Decode from the backend project view.
  factory ProjectSummary.fromJson(Map<String, dynamic> json) => ProjectSummary(
    slug: json['slug']! as String,
    name: json['name']! as String,
  );
}

/// An app under a project.
@experimental
@immutable
class AppSummary {
  /// Construct an app summary.
  const AppSummary({required this.slug, required this.name});

  /// App slug.
  final String slug;

  /// Display name.
  final String name;

  /// Decode from the backend app view.
  factory AppSummary.fromJson(Map<String, dynamic> json) =>
      AppSummary(slug: json['slug']! as String, name: json['name']! as String);
}

/// An environment under a project.
@experimental
@immutable
class EnvironmentSummary {
  /// Construct an environment summary.
  const EnvironmentSummary({required this.slug});

  /// Environment slug.
  final String slug;

  /// Decode from the backend environment view.
  factory EnvironmentSummary.fromJson(Map<String, dynamic> json) =>
      EnvironmentSummary(slug: json['slug']! as String);
}
