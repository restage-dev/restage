import 'dart:convert';

import 'package:meta/meta.dart';

/// Slim view of the backend's `SurfaceSummary` — the fields the command-line
/// surface displays. The wire payload may carry additional fields; unknown
/// fields are ignored. Parallel to [PaywallSummary]; a paywall view adapts a
/// `SurfaceSummary` of [surfaceType] `paywall` by dropping the type.
@experimental
@immutable
class SurfaceSummary {
  /// Construct a summary.
  const SurfaceSummary({
    required this.surfaceType,
    required this.slug,
    required this.name,
    required this.draftUpdatedAt,
    required this.publishedVersionByEnvironment,
  });

  /// Surface type wire name (`paywall` / `onboarding` / `message` / `survey`).
  final String surfaceType;

  /// Surface slug, unique within an app + type.
  final String slug;

  /// Human-readable name (defaults to the slug if unset on the server).
  final String name;

  /// Wall-clock instant the draft was last saved.
  final DateTime draftUpdatedAt;

  /// One entry per environment under the resolved app. The value is the
  /// most-recent published version, or null when the surface has never been
  /// published to that environment.
  final Map<String, int?> publishedVersionByEnvironment;

  /// Decode from the backend's JSON-shaped wire payload. Tolerates an absent
  /// `publishedVersionByEnvironment` (treated as empty) and the trailing
  /// `__className__` discriminator the server emits. `surfaceType` is read
  /// defensively (the server serializes the enum byName).
  factory SurfaceSummary.fromJson(Map<String, dynamic> json) {
    final raw =
        json['publishedVersionByEnvironment'] as Map<String, dynamic>? ?? {};
    return SurfaceSummary(
      surfaceType: json['surfaceType']?.toString() ?? '',
      slug: json['slug']! as String,
      name: json['name']! as String,
      draftUpdatedAt: DateTime.parse(json['draftUpdatedAt']! as String),
      publishedVersionByEnvironment: <String, int?>{
        for (final entry in raw.entries) entry.key: entry.value as int?,
      },
    );
  }
}

/// Operator lifecycle snapshot of one surface in one environment, decoded from
/// the backend's status view. Unknown fields (and the trailing `__className__`
/// discriminator) are ignored.
@experimental
@immutable
class SurfaceStatusResult {
  /// Construct a status result.
  const SurfaceStatusResult({
    required this.surfaceType,
    required this.surfaceSlug,
    required this.environmentSlug,
    required this.liveVersion,
    required this.locked,
    required this.deliveryShape,
    required this.versions,
  });

  /// Surface type wire name (`paywall` / `onboarding` / `message` / `survey`).
  final String surfaceType;

  /// Surface slug, unique within an app + type.
  final String surfaceSlug;

  /// Environment slug the snapshot is scoped to.
  final String environmentSlug;

  /// Active published version, or null when nothing has been activated.
  final int? liveVersion;

  /// Whether the surface is locked against new publishes.
  final bool locked;

  /// Delivery shape wire name (`blob` or `flow`).
  final String deliveryShape;

  /// Ordered list of published versions, most-recent first.
  final List<SurfaceVersionResult> versions;

  /// Rollback re-points the active-version pointer, which only changes what a
  /// blob surface serves; a version-pinned flow is unaffected, so rollback is
  /// offered only for blob-shaped surfaces.
  bool get supportsRollback => deliveryShape == 'blob';

  /// Decode from the backend's JSON-shaped wire payload.
  factory SurfaceStatusResult.fromJson(Map<String, dynamic> json) {
    final rawVersions = json['versions'] as List<dynamic>? ?? const [];
    return SurfaceStatusResult(
      surfaceType: json['surfaceType']?.toString() ?? '',
      surfaceSlug: json['surfaceSlug']! as String,
      environmentSlug: json['environmentSlug']! as String,
      liveVersion: json['liveVersion'] as int?,
      locked: json['locked']! as bool,
      deliveryShape: json['deliveryShape']?.toString() ?? '',
      versions: [
        for (final v in rawVersions)
          SurfaceVersionResult.fromJson(v as Map<String, dynamic>),
      ],
    );
  }
}

/// One immutable published version in [SurfaceStatusResult.versions].
@experimental
@immutable
class SurfaceVersionResult {
  /// Construct a version result.
  const SurfaceVersionResult({
    required this.version,
    required this.publishedAt,
    required this.contentHash,
    required this.isActive,
  });

  /// Monotonically increasing version number.
  final int version;

  /// Wall-clock instant the version was published.
  final DateTime publishedAt;

  /// Content hash of the published payload.
  final String contentHash;

  /// Whether this version is the current active-serve version.
  final bool isActive;

  /// Decode from the backend's JSON-shaped wire payload.
  factory SurfaceVersionResult.fromJson(Map<String, dynamic> json) =>
      SurfaceVersionResult(
        version: json['version']! as int,
        publishedAt: DateTime.parse(json['publishedAt']! as String),
        contentHash: json['contentHash']! as String,
        isActive: json['isActive']! as bool,
      );
}

/// Sealed hierarchy for typed errors returned by surface endpoints. The
/// CLI catches the transport-layer exception, runs
/// [decodeSurfaceTypedException] over the body, and surfaces these to the
/// user as legible messages.
///
/// This is a parallel decoder to the paywall one: the surface endpoints
/// throw their own `Surface*` exception classes, so the surface-specific
/// class names are decoded here rather than overloading the paywall
/// decoder. Generic, shared exceptions (project / app not found,
/// unauthorized) are decoded by the shared error renderer.
@experimental
@immutable
sealed class SurfaceException implements Exception {
  const SurfaceException();
}

/// A surface with the requested slug does not exist.
@experimental
class SurfaceNotFound extends SurfaceException {
  /// Construct with the missing [surfaceSlug].
  const SurfaceNotFound({required this.surfaceSlug});
  final String surfaceSlug;

  @override
  String toString() => 'SurfaceNotFound(surfaceSlug: $surfaceSlug)';
}

/// Concurrent publishes raced; the caller should retry.
@experimental
class SurfacePublishConflict extends SurfaceException {
  /// Construct with the offending [surfaceSlug] and [environmentSlug].
  const SurfacePublishConflict({
    required this.surfaceSlug,
    required this.environmentSlug,
  });
  final String surfaceSlug;
  final String environmentSlug;

  @override
  String toString() =>
      'SurfacePublishConflict(surfaceSlug: $surfaceSlug, '
      'environmentSlug: $environmentSlug)';
}

/// An environment with the requested slug does not exist under the
/// resolved app. Named distinctly from the paywall path's
/// `EnvironmentNotFound` so the two decoders stay independent even though
/// the wire class name (`EnvironmentNotFoundException`) is shared.
@experimental
class SurfaceEnvironmentNotFound extends SurfaceException {
  /// Construct with the missing [environmentSlug].
  const SurfaceEnvironmentNotFound({required this.environmentSlug});
  final String environmentSlug;

  @override
  String toString() =>
      'SurfaceEnvironmentNotFound(environmentSlug: $environmentSlug)';
}

/// Rollback was requested on a surface whose delivery shape does not support
/// re-pointing (e.g. a flow surface).
@experimental
class SurfaceRollbackUnsupported extends SurfaceException {
  /// Construct with the offending [surfaceSlug].
  const SurfaceRollbackUnsupported({required this.surfaceSlug});
  final String surfaceSlug;

  @override
  String toString() => 'SurfaceRollbackUnsupported(surfaceSlug: $surfaceSlug)';
}

/// The requested rollback target version does not exist for the surface.
@experimental
class SurfaceVersionNotFound extends SurfaceException {
  /// Construct with the offending [surfaceSlug] and [toVersion].
  const SurfaceVersionNotFound({
    required this.surfaceSlug,
    required this.toVersion,
  });
  final String surfaceSlug;
  final int toVersion;

  @override
  String toString() =>
      'SurfaceVersionNotFound(surfaceSlug: $surfaceSlug, toVersion: $toVersion)';
}

/// Attempt to decode [body] as one of the typed surface exceptions.
///
/// Returns null when [body] is not a surface typed-exception payload (the
/// caller should fall through to the generic error-handling path). Only
/// the surface-specific class names are matched here; shared exceptions
/// (`ProjectNotFoundException`, `AppNotFoundException`,
/// `UnauthorizedException`) are handled by the shared renderer.
///
/// The transport returns a serializable exception as:
///
/// ```json
/// {"className": "<Name>", "data": {"__className__": "<Name>", ...fields}}
/// ```
@experimental
SurfaceException? decodeSurfaceTypedException(String body) {
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
    case 'SurfaceNotFoundException':
      return SurfaceNotFound(surfaceSlug: data['surfaceSlug'] as String);
    case 'SurfacePublishConflictException':
      return SurfacePublishConflict(
        surfaceSlug: data['surfaceSlug'] as String,
        environmentSlug: data['environmentSlug'] as String,
      );
    case 'EnvironmentNotFoundException':
      return SurfaceEnvironmentNotFound(
        environmentSlug: data['environmentSlug'] as String,
      );
    case 'SurfaceRollbackUnsupportedException':
      return SurfaceRollbackUnsupported(
        surfaceSlug: data['surfaceSlug'] as String,
      );
    case 'SurfaceVersionNotFoundException':
      // Defensive: if the expected fields are absent or wrong-typed, fall
      // through to the generic renderer rather than throwing.
      final versionSlug = data['surfaceSlug'];
      final versionNum =
          data['version']; // wire key is 'version', not 'toVersion'
      if (versionSlug is! String || versionNum is! int) return null;
      return SurfaceVersionNotFound(
        surfaceSlug: versionSlug,
        toVersion: versionNum,
      );
    default:
      return null;
  }
}
