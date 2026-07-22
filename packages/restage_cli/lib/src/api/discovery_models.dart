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

  /// Stable organization id.
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

/// Status-safe workspace fields returned by organization discovery.
///
/// The CLI intentionally keeps only the server-owned presentation fields it
/// renders. Capability flags and sample-generation details remain on the
/// server response and are ignored here.
@experimental
@immutable
class WorkspaceExperienceSummary {
  /// Construct a workspace experience summary.
  const WorkspaceExperienceSummary({
    required this.organizationId,
    required this.provenance,
    required this.hostedAccessState,
    required this.productionAllowed,
  });

  /// Stable organization id.
  final int organizationId;

  /// Server-derived workspace provenance (`sample` or `customer`).
  final String provenance;

  /// Server-derived hosted-access state.
  final String hostedAccessState;

  /// Whether production-class hosted operations are currently allowed.
  final bool productionAllowed;

  /// Decode the existing workspace-experience projection.
  factory WorkspaceExperienceSummary.fromJson(Map<String, dynamic> json) =>
      WorkspaceExperienceSummary(
        organizationId: json['organizationId']! as int,
        provenance: json['provenance']! as String,
        hostedAccessState: json['hostedAccessState']! as String,
        productionAllowed: json['productionAllowed']! as bool,
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
  const AppSummary({required this.slug, required this.name, this.appId});

  /// Stable numeric app id when returned by the current backend.
  ///
  /// This remains nullable so older servers that omit the additive field keep
  /// decoding. Target-aware consumers can require it before proceeding.
  final int? appId;

  /// App slug.
  final String slug;

  /// Display name.
  final String name;

  /// Decode from the backend app view.
  factory AppSummary.fromJson(Map<String, dynamic> json) => AppSummary(
    slug: json['slug']! as String,
    name: json['name']! as String,
    appId: json['id'] as int?,
  );
}

/// An environment under a project.
@experimental
@immutable
class EnvironmentSummary {
  /// Construct an environment summary.
  const EnvironmentSummary({
    required this.slug,
    this.environmentTargetId,
    this.appId,
  });

  /// Stable numeric environment target id when returned by the current
  /// backend.
  final int? environmentTargetId;

  /// Stable numeric parent app id when returned by the current backend.
  final int? appId;

  /// Environment slug.
  final String slug;

  /// Decode from the backend environment view.
  factory EnvironmentSummary.fromJson(Map<String, dynamic> json) =>
      EnvironmentSummary(
        slug: json['slug']! as String,
        environmentTargetId: json['id'] as int?,
        appId: json['appId'] as int?,
      );
}

/// Canonical execution plane for an environment target.
@experimental
enum RuntimePlane {
  /// Isolated evaluation and development traffic.
  sandbox,

  /// Customer-facing production traffic.
  live;

  /// Decode the backend wire name.
  factory RuntimePlane.fromWireName(String value) => switch (value) {
    'sandbox' => RuntimePlane.sandbox,
    'live' => RuntimePlane.live,
    _ => throw FormatException('Unknown runtime plane: $value'),
  };

  /// Backend wire name.
  String get wireName => name;
}

/// One concrete target for a named environment and runtime plane.
@experimental
@immutable
class EnvironmentTargetSummary {
  /// Construct an environment target summary.
  const EnvironmentTargetSummary({
    required this.environmentTargetId,
    required this.namedEnvironmentId,
    required this.environmentSlug,
    required this.runtimePlane,
  });

  /// Stable numeric target id used by target-scoped operations.
  final int environmentTargetId;

  /// Stable parent named-environment id.
  final int namedEnvironmentId;

  /// Human-readable named-environment slug.
  final String environmentSlug;

  /// Runtime plane served by this target.
  final RuntimePlane runtimePlane;

  /// Decode from the backend target reference.
  factory EnvironmentTargetSummary.fromJson(Map<String, dynamic> json) =>
      EnvironmentTargetSummary(
        environmentTargetId: json['environmentTargetId']! as int,
        namedEnvironmentId: json['namedEnvironmentId']! as int,
        environmentSlug: json['environmentSlug']! as String,
        runtimePlane: RuntimePlane.fromWireName(
          json['runtimePlane']! as String,
        ),
      );
}
