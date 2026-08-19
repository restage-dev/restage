import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:restage_shared/restage_shared.dart';

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
    this.contractVersion,
    this.sourceKind,
    this.payloadKind,
  });

  /// Surface type wire name (`paywall` / `onboarding` / `message` / `survey` /
  /// `general`).
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

  /// Current generated contract version for a standalone screen, when the
  /// backend includes publication identity metadata.
  final int? contractVersion;

  /// Authored source shape, when the backend includes publication identity
  /// metadata.
  final String? sourceKind;

  /// Declared payload shape, when the backend includes publication identity
  /// metadata.
  final String? payloadKind;

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
      contractVersion: _asInt(json['contractVersion']),
      sourceKind: json['sourceKind'] as String?,
      payloadKind: json['payloadKind'] as String?,
    );
  }

  /// Encode for `--json` CLI output.
  Map<String, dynamic> toJson() => {
    'surfaceType': surfaceType,
    'slug': slug,
    'name': name,
    'draftUpdatedAt': draftUpdatedAt.toUtc().toIso8601String(),
    'publishedVersionByEnvironment': publishedVersionByEnvironment,
    if (contractVersion != null) 'contractVersion': contractVersion,
    if (sourceKind != null) 'sourceKind': sourceKind,
    if (payloadKind != null) 'payloadKind': payloadKind,
  };
}

/// Exact generated family address returned by the surface control plane.
@experimental
@immutable
class SurfaceFamilyReferenceResult {
  /// Construct a generated family address.
  const SurfaceFamilyReferenceResult({
    required this.surfaceType,
    required this.surfaceSlug,
    required this.sourceKind,
    required this.contractVersion,
  });

  /// Surface category (`onboarding`, `message`, `survey`, `paywall`, or
  /// `general`).
  final String surfaceType;

  /// Stable surface slug.
  final String surfaceSlug;

  /// Authored source kind (`screen`, `flowGraph`, or `paywall`).
  final String sourceKind;

  /// Positive standalone-screen contract version, or null for the existing
  /// non-versioned flow/paywall lineage.
  final int? contractVersion;

  /// Human-readable family address.
  String get familyAddress => contractVersion == null
      ? 'non-versioned $sourceKind'
      : 'contract v$contractVersion';

  /// Decode the generated `SurfaceContractFamilyReference` wire shape.
  factory SurfaceFamilyReferenceResult.fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      throw const FormatException(
        'The response did not contain a generated surface family.',
      );
    }
    final surfaceType = _requiredString(raw, 'surfaceType');
    try {
      SurfaceType.fromWireName(surfaceType);
    } on FormatException {
      throw const FormatException(
        'The response contained an invalid surface family category.',
      );
    }
    final surfaceSlug = _requiredString(raw, 'surfaceSlug');
    if (surfaceSlug.isEmpty) {
      throw const FormatException(
        'The response contained an empty surface family slug.',
      );
    }
    final sourceKind = _requiredString(raw, 'sourceKind');
    try {
      SurfaceSourceKind.fromWireName(sourceKind);
    } on FormatException {
      throw const FormatException(
        'The response contained an invalid surface family source kind.',
      );
    }
    final rawContractVersion = raw['contractVersion'];
    if (rawContractVersion != null && rawContractVersion is! int) {
      throw const FormatException(
        'The response contained an invalid surface contract version.',
      );
    }
    final contractVersion = rawContractVersion as int?;
    if (sourceKind == SurfaceSourceKind.screen.wireName &&
        (contractVersion == null || contractVersion < 1)) {
      throw const FormatException(
        'A standalone screen family must contain a positive contract version.',
      );
    }
    if (sourceKind != SurfaceSourceKind.screen.wireName &&
        contractVersion != null) {
      throw const FormatException(
        'A non-versioned surface family cannot contain a contract version.',
      );
    }
    return SurfaceFamilyReferenceResult(
      surfaceType: surfaceType,
      surfaceSlug: surfaceSlug,
      sourceKind: sourceKind,
      contractVersion: contractVersion,
    );
  }

  /// Encode the generated family-reference JSON shape.
  Map<String, dynamic> toJson() => {
    '__className__': 'SurfaceContractFamilyReference',
    'surfaceType': surfaceType,
    'surfaceSlug': surfaceSlug,
    'sourceKind': sourceKind,
    if (contractVersion != null) 'contractVersion': contractVersion,
  };
}

/// One immutable revision in a generated family history response.
@experimental
@immutable
class SurfaceContractFamilyRevisionResult {
  /// Construct a generated family revision.
  const SurfaceContractFamilyRevisionResult({
    required this.publishedRevision,
    required this.publishedAt,
    required this.contentHash,
    required this.minClient,
    required this.payloadKind,
    required this.isActive,
  });

  /// Immutable revision number.
  final int publishedRevision;

  /// Publication time.
  final DateTime publishedAt;

  /// Content hash of the published payload.
  final String contentHash;

  /// Minimum client floor declared by the publication.
  final int minClient;

  /// Payload shape (`blob` or `flow`).
  final String payloadKind;

  /// Whether this revision is selected by the family active pointer.
  final bool isActive;

  /// Decode the generated `SurfaceContractPublishedRevisionView` wire shape.
  factory SurfaceContractFamilyRevisionResult.fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      throw const FormatException(
        'The response contained an invalid generated surface revision.',
      );
    }
    final publishedRevision = _requiredInt(raw, 'publishedRevision');
    final publishedAt = _requiredDateTime(raw, 'publishedAt');
    final contentHash = _requiredString(raw, 'contentHash');
    final minClient = _requiredInt(raw, 'minClient');
    final payloadKind = _requiredString(raw, 'payloadKind');
    try {
      SurfacePayloadKind.fromWireName(payloadKind);
    } on FormatException {
      throw const FormatException(
        'The response contained an invalid surface payload kind.',
      );
    }
    final isActive = raw['isActive'];
    if (publishedRevision < 1 || isActive is! bool) {
      throw const FormatException(
        'The response contained an invalid generated surface revision.',
      );
    }
    return SurfaceContractFamilyRevisionResult(
      publishedRevision: publishedRevision,
      publishedAt: publishedAt,
      contentHash: contentHash,
      minClient: minClient,
      payloadKind: payloadKind,
      isActive: isActive,
    );
  }

  /// Encode the generated revision JSON shape.
  Map<String, dynamic> toJson() => {
    '__className__': 'SurfaceContractPublishedRevisionView',
    'publishedRevision': publishedRevision,
    'publishedAt': publishedAt.toUtc().toIso8601String(),
    'contentHash': contentHash,
    'minClient': minClient,
    'payloadKind': payloadKind,
    'isActive': isActive,
  };
}

/// Exact family-scoped history returned by `surfaceContractHistory`.
@experimental
@immutable
class SurfaceContractFamilyHistoryResult {
  /// Construct a generated family history.
  const SurfaceContractFamilyHistoryResult({
    required this.family,
    required this.payloadKind,
    required this.capabilityManifestJson,
    required this.eventContractHash,
    required this.contractFingerprint,
    required this.activePublishedRevision,
    required this.revisions,
  });

  /// Exact family address.
  final SurfaceFamilyReferenceResult family;

  /// Family payload kind, when the backend has one at family level.
  final String? payloadKind;

  /// Canonical capability manifest for a standalone screen, when present.
  final String? capabilityManifestJson;

  /// Event contract hash for a standalone screen, when present.
  final String? eventContractHash;

  /// Immutable contract fingerprint for a standalone screen, when present.
  final String? contractFingerprint;

  /// Active published revision, or null when the family is inactive.
  final int? activePublishedRevision;

  /// Immutable revisions, newest first.
  final List<SurfaceContractFamilyRevisionResult> revisions;

  /// Decode the generated `SurfaceContractFamilyView` wire shape.
  factory SurfaceContractFamilyHistoryResult.fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      throw const FormatException(
        'The response did not contain a generated family history.',
      );
    }
    final payloadKind = _optionalPayloadKind(raw['payloadKind']);
    final activePublishedRevision = _optionalPositiveInt(
      raw,
      'activePublishedRevision',
    );
    final rawRevisions = raw['revisions'];
    if (rawRevisions is! List<dynamic>) {
      throw const FormatException(
        'The response did not contain generated family revisions.',
      );
    }
    return SurfaceContractFamilyHistoryResult(
      family: SurfaceFamilyReferenceResult.fromJson(raw['family']),
      payloadKind: payloadKind,
      capabilityManifestJson: _optionalString(raw, 'capabilityManifestJson'),
      eventContractHash: _optionalString(raw, 'eventContractHash'),
      contractFingerprint: _optionalString(raw, 'contractFingerprint'),
      activePublishedRevision: activePublishedRevision,
      revisions: [
        for (final revision in rawRevisions)
          SurfaceContractFamilyRevisionResult.fromJson(revision),
      ],
    );
  }

  /// Encode the generated family-history JSON shape.
  Map<String, dynamic> toJson() => {
    '__className__': 'SurfaceContractFamilyView',
    'family': family.toJson(),
    if (payloadKind != null) 'payloadKind': payloadKind,
    if (capabilityManifestJson != null)
      'capabilityManifestJson': capabilityManifestJson,
    if (eventContractHash != null) 'eventContractHash': eventContractHash,
    if (contractFingerprint != null) 'contractFingerprint': contractFingerprint,
    if (activePublishedRevision != null)
      'activePublishedRevision': activePublishedRevision,
    'revisions': [for (final revision in revisions) revision.toJson()],
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
    this.contractVersion,
    this.sourceKind,
    this.payloadKind,
    this.frozen,
    this.publishedRevision,
    this.families = const <SurfaceFamilyStatus>[],
    this.affectedFamilies = const <SurfaceAffectedFamily>[],
  });

  /// Surface type wire name (`paywall` / `onboarding` / `message` / `survey` /
  /// `general`).
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

  /// Exact standalone-screen contract family, or null for a non-versioned
  /// flow/paywall lineage.
  final int? contractVersion;

  /// Authored source kind supplied by the lifecycle authority.
  final String? sourceKind;

  /// Payload kind supplied by the lifecycle authority.
  final String? payloadKind;

  /// Identity-wide freeze state when the backend returns it separately from
  /// the legacy `locked` field.
  final bool? frozen;

  /// Latest immutable revision number for the selected family, when present.
  final int? publishedRevision;

  /// Family summaries returned by an identity-wide status read.
  final List<SurfaceFamilyStatus> families;

  /// Family effects returned by an identity-wide mutation read.
  final List<SurfaceAffectedFamily> affectedFamilies;

  /// Current identity-wide freeze state.
  bool get isFrozen => frozen ?? locked;

  /// Rollback re-points the selected family's active-revision pointer. Both
  /// blob and flow lineages are supported; specialized paywalls may retain
  /// either shape across their revision history.
  bool get supportsRollback =>
      deliveryShape == 'blob' ||
      deliveryShape == 'flow' ||
      payloadKind == 'blob' ||
      payloadKind == 'flow';

  /// Decode from the backend's JSON-shaped wire payload.
  factory SurfaceStatusResult.fromJson(
    Map<String, dynamic> json, {
    String? environmentSlug,
  }) {
    final identity = json['identity'];
    final identityJson = identity is Map<String, dynamic> ? identity : null;
    final rawVersions =
        (json['versions'] ?? json['revisions']) as List<dynamic>? ?? const [];
    final families = _decodeFamilyStatuses(json['families']);
    final contractVersion = _asInt(json['contractVersion']);
    final selectedFamily = contractVersion == null
        ? families.length == 1
              ? families.single
              : null
        : families
              .where((family) => family.contractVersion == contractVersion)
              .firstOrNull;
    final versions = rawVersions.isNotEmpty
        ? [
            for (final v in rawVersions)
              SurfaceVersionResult.fromJson(v as Map<String, dynamic>),
          ]
        : selectedFamily?.versions ?? const <SurfaceVersionResult>[];
    final payloadKind =
        json['payloadKind']?.toString() ?? selectedFamily?.payloadKind;
    return SurfaceStatusResult(
      surfaceType:
          json['surfaceType']?.toString() ??
          identityJson?['surfaceType']?.toString() ??
          '',
      surfaceSlug:
          json['surfaceSlug']?.toString() ??
          identityJson?['surfaceSlug']?.toString() ??
          '',
      environmentSlug:
          json['environmentSlug']?.toString() ?? environmentSlug ?? '',
      liveVersion: _asInt(
        json['liveVersion'] ??
            json['activeRevision'] ??
            json['publishedRevision'] ??
            selectedFamily?.activeRevision,
      ),
      locked: (json['locked'] ?? json['frozen'] ?? false) as bool,
      deliveryShape: json['deliveryShape']?.toString() ?? payloadKind ?? '',
      versions: versions,
      contractVersion: contractVersion,
      sourceKind:
          json['sourceKind']?.toString() ??
          identityJson?['sourceKind']?.toString() ??
          selectedFamily?.sourceKind,
      payloadKind: payloadKind,
      frozen: json['frozen'] as bool?,
      publishedRevision: _asInt(
        json['publishedRevision'] ??
            json['activeRevision'] ??
            selectedFamily?.publishedRevision,
      ),
      families: families,
      affectedFamilies: _decodeAffectedFamilies(json['affectedFamilies']),
    );
  }

  /// Encode for JSON-shaped consumer output (CLI `--json`, tool results).
  Map<String, dynamic> toJson() => {
    'surfaceType': surfaceType,
    'surfaceSlug': surfaceSlug,
    'environmentSlug': environmentSlug,
    'liveVersion': liveVersion,
    'locked': locked,
    'deliveryShape': deliveryShape,
    'versions': [for (final v in versions) v.toJson()],
    if (contractVersion != null) 'contractVersion': contractVersion,
    if (sourceKind != null) 'sourceKind': sourceKind,
    if (payloadKind != null) 'payloadKind': payloadKind,
    if (frozen != null) 'frozen': frozen,
    if (publishedRevision != null) 'publishedRevision': publishedRevision,
    if (families.isNotEmpty) 'families': [for (final f in families) f.toJson()],
    if (affectedFamilies.isNotEmpty)
      'affectedFamilies': [
        for (final family in affectedFamilies) family.toJson(),
      ],
  };
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
    this.deliveryMode,
    this.publishedRevision,
    this.contractVersion,
  });

  /// Monotonically increasing version number.
  final int version;

  /// Wall-clock instant the version was published.
  final DateTime publishedAt;

  /// Content hash of the published payload.
  final String contentHash;

  /// Whether this version is the current active-serve version.
  final bool isActive;

  /// Flow delivery mode of this version's payload (`typed` / `general`), or
  /// null for a blob payload, an undecodable payload, or a server that
  /// predates the field.
  final String? deliveryMode;

  /// Explicit revision-axis spelling used by the family lifecycle contract.
  final int? publishedRevision;

  /// Contract family version, when this row carries family metadata.
  final int? contractVersion;

  /// Decode from the backend's JSON-shaped wire payload.
  factory SurfaceVersionResult.fromJson(Map<String, dynamic> json) =>
      SurfaceVersionResult(
        version: _asInt(json['version'] ?? json['publishedRevision']) ?? 0,
        publishedAt: DateTime.parse(json['publishedAt']! as String),
        contentHash: json['contentHash']! as String,
        isActive: json['isActive']! as bool,
        deliveryMode: json['deliveryMode'] as String?,
        publishedRevision: _asInt(json['publishedRevision'] ?? json['version']),
        contractVersion: _asInt(json['contractVersion']),
      );

  /// Encode for JSON-shaped consumer output (CLI `--json`, tool results).
  Map<String, dynamic> toJson() => {
    'version': version,
    'publishedAt': publishedAt.toUtc().toIso8601String(),
    'contentHash': contentHash,
    'isActive': isActive,
    if (deliveryMode != null) 'deliveryMode': deliveryMode,
    if (publishedRevision != null) 'publishedRevision': publishedRevision,
    if (contractVersion != null) 'contractVersion': contractVersion,
  };
}

/// One family returned by an identity-wide lifecycle read.
@experimental
@immutable
class SurfaceFamilyStatus {
  /// Construct a family status.
  const SurfaceFamilyStatus({
    required this.contractVersion,
    required this.sourceKind,
    required this.payloadKind,
    required this.publishedRevision,
    required this.activeRevision,
    required this.versions,
  });

  /// Positive standalone-screen version, or null for flow/paywall lineage.
  final int? contractVersion;

  /// Authored source shape.
  final String sourceKind;

  /// Payload shape, when the server reports one.
  final String? payloadKind;

  /// Latest stored revision.
  final int? publishedRevision;

  /// Active revision pointer.
  final int? activeRevision;

  /// Immutable revisions in this family.
  final List<SurfaceVersionResult> versions;

  /// Human-readable family address.
  String get familyAddress => contractVersion == null
      ? 'non-versioned $sourceKind'
      : 'contract v$contractVersion';

  /// Decode a family status from a wire map.
  factory SurfaceFamilyStatus.fromJson(Map<String, dynamic> json) {
    final family = json['family'];
    final familyJson = family is Map<String, dynamic> ? family : json;
    final rawVersions = json['versions'] ?? json['revisions'];
    return SurfaceFamilyStatus(
      contractVersion: _asInt(familyJson['contractVersion']),
      sourceKind:
          json['sourceKind']?.toString() ??
          familyJson['sourceKind']?.toString() ??
          '',
      payloadKind:
          json['payloadKind']?.toString() ??
          familyJson['payloadKind']?.toString(),
      publishedRevision: _asInt(
        json['publishedRevision'] ??
            json['latestRevision'] ??
            json['activePublishedRevision'],
      ),
      activeRevision: _asInt(
        json['activeRevision'] ??
            json['liveVersion'] ??
            json['activePublishedRevision'],
      ),
      versions: rawVersions is List<dynamic>
          ? [
              for (final version in rawVersions)
                SurfaceVersionResult.fromJson(version as Map<String, dynamic>),
            ]
          : const <SurfaceVersionResult>[],
    );
  }

  /// Encode for JSON-shaped CLI output.
  Map<String, dynamic> toJson() => {
    'contractVersion': contractVersion,
    'sourceKind': sourceKind,
    if (payloadKind != null) 'payloadKind': payloadKind,
    'publishedRevision': publishedRevision,
    'activeRevision': activeRevision,
    'versions': [for (final version in versions) version.toJson()],
  };
}

/// One family pointer effect returned by an identity-wide mutation.
@experimental
@immutable
class SurfaceAffectedFamily {
  /// Construct a family effect.
  const SurfaceAffectedFamily({
    required this.contractVersion,
    required this.sourceKind,
    required this.payloadKind,
    required this.publishedRevision,
    required this.activeRevisionBefore,
    required this.activeRevisionAfter,
  });

  /// Positive standalone-screen version, or null for flow/paywall lineage.
  final int? contractVersion;

  /// Authored source shape.
  final String sourceKind;

  /// Payload shape, when the server reports one.
  final String? payloadKind;

  /// Revision stored by the mutation, when one was created.
  final int? publishedRevision;

  /// Pointer before the mutation.
  final int? activeRevisionBefore;

  /// Pointer after the mutation.
  final int? activeRevisionAfter;

  /// Human-readable family address.
  String get familyAddress => contractVersion == null
      ? 'non-versioned $sourceKind'
      : 'contract v$contractVersion';

  /// Decode a family effect from a wire map.
  factory SurfaceAffectedFamily.fromJson(Map<String, dynamic> json) {
    final family = json['family'];
    final familyJson = family is Map<String, dynamic> ? family : json;
    return SurfaceAffectedFamily(
      contractVersion: _asInt(familyJson['contractVersion']),
      sourceKind: familyJson['sourceKind']?.toString() ?? '',
      payloadKind: familyJson['payloadKind']?.toString(),
      publishedRevision: _asInt(
        json['publishedRevision'] ?? familyJson['publishedRevision'],
      ),
      activeRevisionBefore: _asInt(
        json['activeRevisionBefore'] ??
            json['activePublishedRevisionBefore'] ??
            json['activeRevision'],
      ),
      activeRevisionAfter: _asInt(
        json['activeRevisionAfter'] ??
            json['activePublishedRevisionAfter'] ??
            json['activeRevision'],
      ),
    );
  }

  /// Encode for JSON-shaped CLI output.
  Map<String, dynamic> toJson() => {
    'contractVersion': contractVersion,
    'sourceKind': sourceKind,
    if (payloadKind != null) 'payloadKind': payloadKind,
    if (publishedRevision != null) 'publishedRevision': publishedRevision,
    'activeRevisionBefore': activeRevisionBefore,
    'activeRevisionAfter': activeRevisionAfter,
  };
}

/// Identity-wide mutation result with the complete affected-family list.
@experimental
@immutable
class SurfaceIdentityMutationResult {
  /// Construct an identity mutation result.
  const SurfaceIdentityMutationResult({
    required this.surfaceType,
    required this.surfaceSlug,
    required this.environmentSlug,
    required this.frozen,
    required this.affectedFamilies,
  });

  /// Surface type wire name.
  final String surfaceType;

  /// Surface slug.
  final String surfaceSlug;

  /// Environment slug.
  final String environmentSlug;

  /// Identity-wide freeze state after the operation.
  final bool frozen;

  /// Every family pointer affected by the operation.
  final List<SurfaceAffectedFamily> affectedFamilies;

  /// Decode an optional mutation response. Legacy empty responses remain
  /// accepted while newer servers can return complete family effects.
  static SurfaceIdentityMutationResult? fromJsonOrNull(
    Object? raw, {
    String? environmentSlug,
  }) {
    if (raw is! Map<String, dynamic>) return null;
    final identity = raw['identity'];
    final identityJson = identity is Map<String, dynamic> ? identity : raw;
    final rawFamilies = raw['affectedFamilies'] ?? raw['families'];
    final families = _decodeAffectedFamilies(rawFamilies);
    return SurfaceIdentityMutationResult(
      surfaceType: identityJson['surfaceType']?.toString() ?? '',
      surfaceSlug: identityJson['surfaceSlug']?.toString() ?? '',
      environmentSlug:
          raw['environmentSlug']?.toString() ?? environmentSlug ?? '',
      frozen: (raw['frozen'] ?? raw['locked'] ?? false) as bool,
      affectedFamilies: families,
    );
  }

  /// Encode for JSON-shaped CLI output.
  Map<String, dynamic> toJson() => {
    'surfaceType': surfaceType,
    'surfaceSlug': surfaceSlug,
    'environmentSlug': environmentSlug,
    'frozen': frozen,
    'affectedFamilies': [
      for (final family in affectedFamilies) family.toJson(),
    ],
  };
}

/// Family-scoped activation or rollback result.
@experimental
@immutable
class SurfaceFamilyMutationResult {
  /// Construct a family mutation result.
  const SurfaceFamilyMutationResult({
    required this.surfaceType,
    required this.surfaceSlug,
    required this.environmentSlug,
    required this.contractVersion,
    this.sourceKind,
    this.payloadKind,
    required this.publishedRevision,
    required this.activeRevisionBefore,
    required this.activeRevisionAfter,
    required this.frozen,
  });

  /// Surface type wire name.
  final String surfaceType;

  /// Surface slug.
  final String surfaceSlug;

  /// Environment slug.
  final String environmentSlug;

  /// Positive standalone-screen family version, or null for flow/paywall.
  final int? contractVersion;

  /// Authored source shape, when the server returns the family reference.
  final String? sourceKind;

  /// Payload shape, when the server returns the family reference.
  final String? payloadKind;

  /// Revision created by a publish, when applicable.
  final int? publishedRevision;

  /// Pointer before the mutation.
  final int? activeRevisionBefore;

  /// Pointer after the mutation.
  final int? activeRevisionAfter;

  /// Identity freeze state after the mutation.
  final bool frozen;

  /// Decode the non-null generated family-operation result.
  static SurfaceFamilyMutationResult fromJson(
    Object? raw, {
    String? environmentSlug,
  }) {
    if (raw is! Map<String, dynamic>) {
      throw const FormatException(
        'The response did not contain a generated family operation result.',
      );
    }
    final family = SurfaceFamilyReferenceResult.fromJson(raw['family']);
    final publishedRevision = _requiredInt(raw, 'publishedRevision');
    final activeRevisionBefore = _optionalPositiveInt(
      raw,
      'activePublishedRevisionBefore',
    );
    final activeRevisionAfter = _optionalPositiveInt(
      raw,
      'activePublishedRevisionAfter',
    );
    final identityFrozenAfter = raw['identityFrozenAfter'];
    if (publishedRevision < 1 || identityFrozenAfter is! bool) {
      throw const FormatException(
        'The response contained an invalid generated family operation result.',
      );
    }
    return SurfaceFamilyMutationResult(
      surfaceType: family.surfaceType,
      surfaceSlug: family.surfaceSlug,
      environmentSlug:
          raw['environmentSlug']?.toString() ?? environmentSlug ?? '',
      contractVersion: family.contractVersion,
      sourceKind: family.sourceKind,
      payloadKind: raw['payloadKind']?.toString(),
      publishedRevision: publishedRevision,
      activeRevisionBefore: activeRevisionBefore,
      activeRevisionAfter: activeRevisionAfter,
      frozen: identityFrozenAfter,
    );
  }

  /// Decode an optional family mutation response.
  static SurfaceFamilyMutationResult? fromJsonOrNull(
    Object? raw, {
    String? environmentSlug,
  }) {
    if (raw is! Map<String, dynamic>) return null;
    final family = raw['family'];
    final familyJson = family is Map<String, dynamic> ? family : raw;
    return SurfaceFamilyMutationResult(
      surfaceType:
          raw['surfaceType']?.toString() ??
          familyJson['surfaceType']?.toString() ??
          '',
      surfaceSlug:
          raw['surfaceSlug']?.toString() ??
          familyJson['surfaceSlug']?.toString() ??
          '',
      environmentSlug:
          raw['environmentSlug']?.toString() ??
          familyJson['environmentSlug']?.toString() ??
          environmentSlug ??
          '',
      contractVersion: _asInt(
        raw['contractVersion'] ?? familyJson['contractVersion'],
      ),
      sourceKind:
          raw['sourceKind']?.toString() ?? familyJson['sourceKind']?.toString(),
      payloadKind:
          raw['payloadKind']?.toString() ??
          familyJson['payloadKind']?.toString(),
      publishedRevision: _asInt(
        raw['publishedRevision'] ?? raw['activeRevision'],
      ),
      activeRevisionBefore: _asInt(
        raw['activeRevisionBefore'] ??
            raw['activePublishedRevisionBefore'] ??
            raw['previousActiveRevision'],
      ),
      activeRevisionAfter: _asInt(
        raw['activeRevisionAfter'] ??
            raw['activePublishedRevisionAfter'] ??
            raw['activeRevision'],
      ),
      frozen:
          (raw['frozen'] ??
                  raw['locked'] ??
                  raw['identityFrozenAfter'] ??
                  false)
              as bool,
    );
  }

  /// Encode for JSON-shaped CLI output.
  Map<String, dynamic> toJson() => {
    'surfaceType': surfaceType,
    'surfaceSlug': surfaceSlug,
    'environmentSlug': environmentSlug,
    'contractVersion': contractVersion,
    if (sourceKind != null) 'sourceKind': sourceKind,
    if (payloadKind != null) 'payloadKind': payloadKind,
    'publishedRevision': publishedRevision,
    'activeRevisionBefore': activeRevisionBefore,
    'activeRevisionAfter': activeRevisionAfter,
    'frozen': frozen,
  };
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

  /// RESERVED — no longer emitted. A flow-shaped paywall target used to be
  /// refused here; it now rolls back and classifies as compatible or
  /// contractChange. Kept for wire stability + forward-compatibility.
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
    this.rawClassification,
  });

  /// Surface type wire name (`paywall` / `onboarding` / `message` / `survey` /
  /// `general`).
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

  /// The classification exactly as the backend sent it, before the
  /// forward-compat fold to [RollbackPreflightClassification.unknown]. Null
  /// when constructed directly rather than decoded from the wire.
  final String? rawClassification;

  /// The classification's wire name for output: the raw backend value when
  /// one was decoded, else the enum name. Keeps a classification this client
  /// does not recognize legible instead of laundering it to `"unknown"`.
  String get classificationWireName => rawClassification ?? classification.name;

  /// Decode from the backend's JSON-shaped wire payload.
  factory RollbackPreflightResult.fromJson(Map<String, dynamic> json) {
    final rawChanges = json['blockingChanges'] as List<dynamic>? ?? const [];
    final rawClassification = json['classification']?.toString();
    return RollbackPreflightResult(
      surfaceType: json['surfaceType']?.toString() ?? '',
      surfaceSlug: json['surfaceSlug']! as String,
      environmentSlug: json['environmentSlug']! as String,
      toVersion: json['toVersion']! as int,
      classification: RollbackPreflightClassification.fromWire(
        rawClassification ?? '',
      ),
      blockingChanges: [for (final c in rawChanges) c.toString()],
      rawClassification: rawClassification,
    );
  }

  /// Encode for JSON-shaped consumer output (CLI `--json`, tool results).
  /// The classification is written by wire name — the raw backend value when
  /// one was decoded — matching the convention
  /// [RollbackPreflightClassification.fromWire] parses.
  Map<String, dynamic> toJson() => {
    'surfaceType': surfaceType,
    'surfaceSlug': surfaceSlug,
    'environmentSlug': environmentSlug,
    'toVersion': toVersion,
    'classification': classificationWireName,
    'blockingChanges': blockingChanges,
  };
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

/// A server refused to re-point the requested surface family. Older servers
/// may use this for a flow-shaped target; current family lifecycle support
/// accepts flow and blob revisions.
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

int? _asInt(Object? value) => value is int ? value : int.tryParse('$value');

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('The response did not contain a valid $key.');
  }
  return value;
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int) {
    throw FormatException('The response did not contain a valid $key.');
  }
  return value;
}

DateTime _requiredDateTime(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('The response did not contain a valid $key.');
  }
  try {
    return DateTime.parse(value);
  } on FormatException {
    throw FormatException('The response did not contain a valid $key.');
  }
}

String? _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('The response contained an invalid $key.');
  }
  return value;
}

String? _optionalPayloadKind(Object? value) {
  if (value == null) return null;
  if (value is! String) {
    throw const FormatException(
      'The response contained an invalid surface payload kind.',
    );
  }
  try {
    SurfacePayloadKind.fromWireName(value);
  } on FormatException {
    throw const FormatException(
      'The response contained an invalid surface payload kind.',
    );
  }
  return value;
}

int? _optionalPositiveInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! int || value < 1) {
    throw FormatException('The response contained an invalid $key.');
  }
  return value;
}

List<SurfaceFamilyStatus> _decodeFamilyStatuses(Object? raw) {
  if (raw is! List<dynamic>) return const <SurfaceFamilyStatus>[];
  return [
    for (final family in raw)
      if (family is Map<String, dynamic>) SurfaceFamilyStatus.fromJson(family),
  ];
}

List<SurfaceAffectedFamily> _decodeAffectedFamilies(Object? raw) {
  if (raw is! List<dynamic>) return const <SurfaceAffectedFamily>[];
  return [
    for (final family in raw)
      if (family is Map<String, dynamic>)
        SurfaceAffectedFamily.fromJson(family),
  ];
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
