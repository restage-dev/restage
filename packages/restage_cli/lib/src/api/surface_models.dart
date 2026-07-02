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

  /// Encode for `--json` CLI output.
  Map<String, dynamic> toJson() => {
    'surfaceType': surfaceType,
    'slug': slug,
    'name': name,
    'draftUpdatedAt': draftUpdatedAt.toUtc().toIso8601String(),
    'publishedVersionByEnvironment': publishedVersionByEnvironment,
  };
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
  /// blob surface serves; version-pinned flow surfaces are previewed through
  /// rollback preflight instead.
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

/// One rendered server-side audit event for a surface/governance timeline.
@experimental
@immutable
class SurfaceAuditLogEntry {
  /// Construct an audit log entry.
  const SurfaceAuditLogEntry({
    required this.action,
    required this.actorType,
    required this.actorEmail,
    required this.outcome,
    required this.severity,
    required this.targetType,
    required this.targetId,
    required this.occurredAt,
    required this.reason,
    required this.context,
    required this.chainState,
    required this.chainVerified,
    required this.entryId,
  });

  /// Audit action wire name.
  final String action;

  /// Actor type wire name.
  final String actorType;

  /// Resolved actor email when visible to this caller.
  final String? actorEmail;

  /// Audit outcome wire name.
  final String outcome;

  /// Audit severity wire name.
  final String severity;

  /// Target type wire name, when present.
  final String? targetType;

  /// Target id, when present.
  final String? targetId;

  /// Event occurrence time.
  final DateTime occurredAt;

  /// Audit reason, when visible.
  final String? reason;

  /// Action-specific immutable context recorded by the server.
  final Map<String, String> context;

  /// `chained` or `pendingChain`.
  final String chainState;

  /// Whether a chained entry is at/below the verified high-water mark.
  final bool chainVerified;

  /// Chain entry id for chained rows.
  final int? entryId;

  /// Decode from the backend's JSON-shaped wire payload.
  factory SurfaceAuditLogEntry.fromJson(Map<String, dynamic> json) {
    return SurfaceAuditLogEntry(
      action: json['action']! as String,
      actorType: json['actorType']! as String,
      actorEmail: json['actorEmail'] as String?,
      outcome: json['outcome']! as String,
      severity: json['severity']! as String,
      targetType: json['targetType'] as String?,
      targetId: json['targetId'] as String?,
      occurredAt: DateTime.parse(json['occurredAt']! as String),
      reason: json['reason'] as String?,
      context: _stringMap(json['context']),
      chainState: json['chainState']! as String,
      chainVerified: json['chainVerified']! as bool,
      entryId: json['entryId'] as int?,
    );
  }

  /// Encode for `--json` CLI output.
  Map<String, dynamic> toJson() => {
    'action': action,
    'actorType': actorType,
    if (actorEmail != null) 'actorEmail': actorEmail,
    'outcome': outcome,
    'severity': severity,
    if (targetType != null) 'targetType': targetType,
    if (targetId != null) 'targetId': targetId,
    'occurredAt': occurredAt.toUtc().toIso8601String(),
    if (reason != null) 'reason': reason,
    'context': context,
    'chainState': chainState,
    'chainVerified': chainVerified,
    if (entryId != null) 'entryId': entryId,
  };
}

/// One row in the compliance / DHF export.
@experimental
@immutable
class SurfaceComplianceExportRow {
  /// Construct an export row.
  const SurfaceComplianceExportRow({
    required this.occurredAt,
    required this.action,
    required this.surfaceSlug,
    required this.surfaceType,
    required this.environmentSlug,
    required this.version,
    required this.actorEmail,
    required this.reason,
    required this.chainState,
    required this.chainVerified,
    required this.entryId,
  });

  /// Event occurrence time.
  final DateTime occurredAt;

  /// Audit action wire name.
  final String action;

  /// Surface slug, when the action context carries it.
  final String? surfaceSlug;

  /// Surface type wire name.
  final String? surfaceType;

  /// Environment slug, when applicable.
  final String? environmentSlug;

  /// Action-specific version, when one exists.
  final int? version;

  /// Resolved actor email.
  final String? actorEmail;

  /// Audit reason.
  final String? reason;

  /// `chained` or `pendingChain`.
  final String chainState;

  /// Whether the row is verified by the current chain high-water.
  final bool chainVerified;

  /// Chain entry id for chained rows.
  final int? entryId;

  /// Decode from the backend's JSON-shaped wire payload.
  factory SurfaceComplianceExportRow.fromJson(Map<String, dynamic> json) {
    return SurfaceComplianceExportRow(
      occurredAt: DateTime.parse(json['occurredAt']! as String),
      action: json['action']! as String,
      surfaceSlug: json['surfaceSlug'] as String?,
      surfaceType: json['surfaceType'] as String?,
      environmentSlug: json['environmentSlug'] as String?,
      version: json['version'] as int?,
      actorEmail: json['actorEmail'] as String?,
      reason: json['reason'] as String?,
      chainState: json['chainState']! as String,
      chainVerified: json['chainVerified']! as bool,
      entryId: json['entryId'] as int?,
    );
  }

  /// Encode for `--json` CLI output.
  Map<String, dynamic> toJson() => {
    'occurredAt': occurredAt.toUtc().toIso8601String(),
    'action': action,
    if (surfaceSlug != null) 'surfaceSlug': surfaceSlug,
    if (surfaceType != null) 'surfaceType': surfaceType,
    if (environmentSlug != null) 'environmentSlug': environmentSlug,
    if (version != null) 'version': version,
    if (actorEmail != null) 'actorEmail': actorEmail,
    if (reason != null) 'reason': reason,
    'chainState': chainState,
    'chainVerified': chainVerified,
    if (entryId != null) 'entryId': entryId,
  };
}

/// Org-level chain verification verdict projected by the backend.
@experimental
@immutable
class SurfaceChainVerdictResult {
  /// Construct a chain verdict result.
  const SurfaceChainVerdictResult({
    required this.status,
    required this.verifiedThroughEntryId,
    required this.verifiedThroughOccurredAt,
    required this.failedEntryId,
    required this.failedCheck,
    required this.lastRunAt,
  });

  /// Verdict status wire name.
  final String status;

  /// Latest clean high-water entry id.
  final int? verifiedThroughEntryId;

  /// Occurrence time of the latest clean high-water entry.
  final DateTime? verifiedThroughOccurredAt;

  /// Failed entry id for a broken verdict.
  final int? failedEntryId;

  /// Failed check label for a broken verdict.
  final String? failedCheck;

  /// Latest verifier run completion time.
  final DateTime? lastRunAt;

  /// Decode from the backend's JSON-shaped wire payload.
  factory SurfaceChainVerdictResult.fromJson(Map<String, dynamic> json) {
    return SurfaceChainVerdictResult(
      status: json['status']! as String,
      verifiedThroughEntryId: json['verifiedThroughEntryId'] as int?,
      verifiedThroughOccurredAt: _optionalDateTime(
        json['verifiedThroughOccurredAt'],
      ),
      failedEntryId: json['failedEntryId'] as int?,
      failedCheck: json['failedCheck'] as String?,
      lastRunAt: _optionalDateTime(json['lastRunAt']),
    );
  }

  /// Encode for `--json` CLI output.
  Map<String, dynamic> toJson() => {
    'status': status,
    if (verifiedThroughEntryId != null)
      'verifiedThroughEntryId': verifiedThroughEntryId,
    if (verifiedThroughOccurredAt != null)
      'verifiedThroughOccurredAt': verifiedThroughOccurredAt!
          .toUtc()
          .toIso8601String(),
    if (failedEntryId != null) 'failedEntryId': failedEntryId,
    if (failedCheck != null) 'failedCheck': failedCheck,
    if (lastRunAt != null) 'lastRunAt': lastRunAt!.toUtc().toIso8601String(),
  };
}

/// How rolling a surface back to a target version is expected to affect the
/// currently-live cohort. Informational — rollback is never blocked by it.
/// [unknown] is a forward-compatible fallback for a classification the backend
/// may add later; the command treats it as "proceed, no special note".
@experimental
enum RollbackPreflightClassification {
  /// The target's contract is within the current-active contract — live clients
  /// render the rolled-back version via the active arm.
  compatible,

  /// The target's contract differs from the current-active one — live clients
  /// on the current contract fall back to their bundled copy.
  contractChange,

  /// A flow-shaped paywall target — re-pointing is refused (no hosted paywall
  /// flow serve path yet).
  unsupportedTargetShape,

  /// No current-active version (killed / never-activated) — the re-point
  /// reactivates the target; there is no live cohort to compare against.
  noActiveBaseline,

  /// An unrecognized classification (forward-compatibility).
  unknown;

  /// Maps the backend's by-name wire value to a classification, tolerating an
  /// unknown value rather than throwing.
  static RollbackPreflightClassification fromWire(String name) =>
      values.firstWhere((c) => c.name == name, orElse: () => unknown);
}

/// Informational preview of a rollback to [toVersion]: how it is expected to
/// affect the currently-live cohort ([classification]) and, for a contract
/// change, the offending contract differences ([blockingChanges]). A read —
/// rollback is never blocked by it.
@experimental
@immutable
class RollbackPreflightResult {
  /// Construct a preflight result.
  const RollbackPreflightResult({
    required this.surfaceType,
    required this.surfaceSlug,
    required this.environmentSlug,
    required this.toVersion,
    required this.classification,
    required this.blockingChanges,
  });

  /// Surface type wire name (`paywall` / `onboarding` / `message` / `survey`).
  final String surfaceType;

  /// Surface slug, unique within an app + type.
  final String surfaceSlug;

  /// Environment slug the preview is scoped to.
  final String environmentSlug;

  /// The version the rollback would re-point to.
  final int toVersion;

  /// The expected cohort impact.
  final RollbackPreflightClassification classification;

  /// For [RollbackPreflightClassification.contractChange], the rendered
  /// offending contract differences; empty otherwise.
  final List<String> blockingChanges;

  /// Decode from the backend's JSON-shaped wire payload.
  factory RollbackPreflightResult.fromJson(Map<String, dynamic> json) {
    final rawChanges = json['blockingChanges'] as List<dynamic>? ?? const [];
    return RollbackPreflightResult(
      surfaceType: json['surfaceType']?.toString() ?? '',
      surfaceSlug: json['surfaceSlug']! as String,
      environmentSlug: json['environmentSlug']! as String,
      toVersion: json['toVersion']! as int,
      classification: RollbackPreflightClassification.fromWire(
        json['classification']?.toString() ?? '',
      ),
      blockingChanges: [for (final c in rawChanges) c.toString()],
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

Map<String, String> _stringMap(Object? raw) {
  if (raw is! Map) return const {};
  return {
    for (final entry in raw.entries)
      entry.key.toString(): entry.value?.toString() ?? '',
  };
}

DateTime? _optionalDateTime(Object? raw) {
  if (raw == null) return null;
  return DateTime.parse(raw as String);
}
