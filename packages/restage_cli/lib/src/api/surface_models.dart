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
    default:
      return null;
  }
}
