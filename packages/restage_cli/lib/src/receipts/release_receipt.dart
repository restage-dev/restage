import 'dart:convert';

import 'package:meta/meta.dart';

/// Schema version written into every receipt.
const int kReleaseReceiptVersion = 1;

/// The operation a receipt records.
enum ReceiptOperation {
  /// A generated surface uploaded to an environment.
  surfacePush('surface-push'),

  /// A pushed revision made live.
  surfacePublish('surface-publish'),

  /// A render bundle uploaded to a head.
  renderBundlePush('render-bundle-push');

  const ReceiptOperation(this.wireName);

  /// Exact value written to the receipt.
  final String wireName;

  /// Parse [wireName]; throws [FormatException] for anything else.
  static ReceiptOperation fromWireName(String wireName) {
    for (final operation in values) {
      if (operation.wireName == wireName) return operation;
    }
    throw FormatException('Unknown receipt operation "$wireName".');
  }
}

/// How much is known about the source the recorded artifacts came from.
enum ReceiptSourceState {
  /// The source was committed and the artifacts were produced from it.
  verified('verified'),

  /// The tree carried uncommitted changes when the artifacts were produced.
  dirty('dirty'),

  /// Nothing recorded where the artifacts came from.
  unknown('unknown');

  const ReceiptSourceState(this.wireName);

  /// Exact value written to the receipt.
  final String wireName;

  /// Parse [wireName]; throws [FormatException] for anything else.
  static ReceiptSourceState fromWireName(String wireName) {
    for (final state in values) {
      if (state.wireName == wireName) return state;
    }
    throw FormatException('Unknown receipt source state "$wireName".');
  }
}

/// Where an operation landed.
@immutable
final class ReceiptTarget {
  /// Construct a target.
  const ReceiptTarget({
    required this.project,
    required this.app,
    this.environment,
    this.organization,
    this.organizationId,
    this.environmentTargetId,
    this.runtimePlane,
  });

  /// Organization slug the invocation asked for, when it named one.
  final String? organization;

  /// Organization the operation resolved to.
  final int? organizationId;

  /// Project slug.
  final String project;

  /// App slug.
  final String app;

  /// Environment slug, for an operation that addresses one.
  final String? environment;

  /// Exact environment target the operation resolved to.
  final int? environmentTargetId;

  /// Runtime plane the operation resolved to.
  final String? runtimePlane;

  /// Encode in canonical key order.
  Map<String, Object?> toJson() => <String, Object?>{
    if (organization != null) 'organization': organization,
    if (organizationId != null) 'organizationId': organizationId,
    'project': project,
    'app': app,
    if (environment != null) 'environment': environment,
    if (environmentTargetId != null) 'environmentTargetId': environmentTargetId,
    if (runtimePlane != null) 'runtimePlane': runtimePlane,
  };

  /// Decode a target section.
  factory ReceiptTarget.fromJson(Object? value) {
    final json = _requireMap(value, 'target');
    return ReceiptTarget(
      organization: _optionalString(json, 'organization'),
      organizationId: _optionalInt(json, 'organizationId'),
      project: _requireString(json, 'project'),
      app: _requireString(json, 'app'),
      environment: _optionalString(json, 'environment'),
      environmentTargetId: _optionalInt(json, 'environmentTargetId'),
      runtimePlane: _optionalString(json, 'runtimePlane'),
    );
  }
}

/// The surface family an operation addressed.
@immutable
final class ReceiptSurface {
  /// Construct a surface section.
  const ReceiptSurface({
    required this.type,
    required this.id,
    required this.sourceKind,
    this.contractVersion,
  });

  /// Surface category.
  final String type;

  /// Surface id.
  final String id;

  /// Authored source shape.
  final String sourceKind;

  /// Positive contract version, or null for the non-versioned lineage.
  final int? contractVersion;

  /// Encode in canonical key order.
  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    'id': id,
    'sourceKind': sourceKind,
    if (contractVersion != null) 'contractVersion': contractVersion,
  };

  /// Decode a surface section.
  factory ReceiptSurface.fromJson(Object? value) {
    final json = _requireMap(value, 'surface');
    return ReceiptSurface(
      type: _requireString(json, 'type'),
      id: _requireString(json, 'id'),
      sourceKind: _requireString(json, 'sourceKind'),
      contractVersion: _optionalInt(json, 'contractVersion'),
    );
  }
}

/// The render bundle an operation uploaded.
@immutable
final class ReceiptBundle {
  /// Construct a bundle section.
  const ReceiptBundle({
    required this.head,
    required this.version,
    required this.contentHash,
    required this.engineSetId,
    this.toolchain,
  });

  /// Head the version was pushed to.
  final String head;

  /// Version number the server stored.
  final int version;

  /// Content hash the server stored the version under.
  final String contentHash;

  /// Identity of the engine set the bundle was built against.
  final String engineSetId;

  /// Toolchain version the bundle was built with.
  final String? toolchain;

  /// Encode in canonical key order.
  Map<String, Object?> toJson() => <String, Object?>{
    'head': head,
    'version': version,
    'contentHash': contentHash,
    'engineSetId': engineSetId,
    if (toolchain != null) 'toolchain': toolchain,
  };

  /// Decode a bundle section.
  factory ReceiptBundle.fromJson(Object? value) {
    final json = _requireMap(value, 'bundle');
    return ReceiptBundle(
      head: _requireString(json, 'head'),
      version: _requireInt(json, 'version'),
      contentHash: _requireHash(json, 'contentHash'),
      engineSetId: _requireEngineSetId(json, 'engineSetId'),
      toolchain: _optionalString(json, 'toolchain'),
    );
  }
}

/// What the operation did to the family's revisions.
@immutable
final class ReceiptRevision {
  /// Construct a revision section.
  const ReceiptRevision({
    this.stored,
    this.activeBefore,
    this.activeAfter,
    this.identityFrozen,
  });

  /// Revision the operation acted on: newly stored by a push, made live by
  /// a publish.
  final int? stored;

  /// Active pointer before the operation, when the server reports it.
  final int? activeBefore;

  /// Active pointer after the operation, when the server reports it.
  final int? activeAfter;

  /// Identity freeze state after the operation.
  final bool? identityFrozen;

  /// Encode in canonical key order.
  Map<String, Object?> toJson() => <String, Object?>{
    if (stored != null) 'stored': stored,
    if (activeBefore != null) 'activeBefore': activeBefore,
    if (activeAfter != null) 'activeAfter': activeAfter,
    if (identityFrozen != null) 'identityFrozen': identityFrozen,
  };

  /// Decode a revision section.
  factory ReceiptRevision.fromJson(Object? value) {
    final json = _requireMap(value, 'revision');
    return ReceiptRevision(
      stored: _optionalInt(json, 'stored'),
      activeBefore: _optionalInt(json, 'activeBefore'),
      activeAfter: _optionalInt(json, 'activeAfter'),
      identityFrozen: _optionalBool(json, 'identityFrozen'),
    );
  }
}

/// One uploaded artifact and the bytes it carried.
@immutable
final class ReceiptArtifact {
  /// Construct an artifact entry.
  const ReceiptArtifact({required this.path, required this.contentHash});

  /// Canonical logical path.
  final String path;

  /// Hash of the exact bytes uploaded.
  final String contentHash;

  /// Encode in canonical key order.
  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'contentHash': contentHash,
  };

  /// Decode an artifact entry.
  factory ReceiptArtifact.fromJson(Object? value) {
    final json = _requireMap(value, 'artifact');
    return ReceiptArtifact(
      path: _requireString(json, 'path'),
      contentHash: _requireHash(json, 'contentHash'),
    );
  }
}

/// Where the recorded artifacts came from.
@immutable
final class ReceiptSource {
  /// Construct a source section.
  const ReceiptSource({
    required this.state,
    this.commit,
    this.branch,
    this.packages = const <String>[],
    this.from,
  });

  /// Nothing recorded where the artifacts came from.
  const ReceiptSource.unknown()
    : state = ReceiptSourceState.unknown,
      commit = null,
      branch = null,
      packages = const <String>[],
      from = null;

  /// How much is known.
  final ReceiptSourceState state;

  /// Commit the artifacts were produced from.
  final String? commit;

  /// Branch that commit was on when the operation ran.
  final String? branch;

  /// Repository-relative package roots checked for uncommitted content.
  final List<String> packages;

  /// Repository-relative receipt this source was read from.
  final String? from;

  /// Encode in canonical key order.
  Map<String, Object?> toJson() => <String, Object?>{
    'state': state.wireName,
    if (commit != null) 'commit': commit,
    if (branch != null) 'branch': branch,
    if (packages.isNotEmpty) 'packages': <String>[...packages]..sort(),
    if (from != null) 'from': from,
  };

  /// Decode a source section.
  factory ReceiptSource.fromJson(Object? value) {
    final json = _requireMap(value, 'source');
    return ReceiptSource(
      state: ReceiptSourceState.fromWireName(_requireString(json, 'state')),
      commit: _optionalCommit(json, 'commit'),
      branch: _optionalString(json, 'branch'),
      packages: _stringList(json, 'packages'),
      from: _optionalString(json, 'from'),
    );
  }
}

/// One recorded release operation, as written into the repository.
@immutable
final class ReleaseReceipt {
  /// Construct a receipt.
  const ReleaseReceipt({
    required this.operation,
    required this.recordedAt,
    required this.target,
    required this.source,
    this.surface,
    this.bundle,
    this.revision,
    this.artifacts = const <ReceiptArtifact>[],
    this.generationFingerprint,
  });

  /// What the operation was.
  final ReceiptOperation operation;

  /// When it was recorded.
  final DateTime recordedAt;

  /// Where it landed.
  final ReceiptTarget target;

  /// The surface family it addressed, for a surface operation.
  final ReceiptSurface? surface;

  /// The render bundle it uploaded, for a bundle operation.
  final ReceiptBundle? bundle;

  /// What it did to the family's revisions.
  final ReceiptRevision? revision;

  /// Artifacts uploaded by a push.
  final List<ReceiptArtifact> artifacts;

  /// The generator's fingerprint over the manifest the push was assembled
  /// from.
  final String? generationFingerprint;

  /// Where the artifacts came from.
  final ReceiptSource source;

  /// Encode in canonical key order, artifacts sorted by path.
  Map<String, Object?> toJson() {
    final ordered = <ReceiptArtifact>[...artifacts]
      ..sort((a, b) => a.path.compareTo(b.path));
    return <String, Object?>{
      'receiptVersion': kReleaseReceiptVersion,
      'operation': operation.wireName,
      'recordedAt': formatReceiptTimestamp(recordedAt),
      'target': target.toJson(),
      if (surface != null) 'surface': surface!.toJson(),
      if (bundle != null) 'bundle': bundle!.toJson(),
      if (revision != null) 'revision': revision!.toJson(),
      if (ordered.isNotEmpty)
        'artifacts': <Object?>[for (final a in ordered) a.toJson()],
      if (generationFingerprint != null)
        'generation': <String, Object?>{'fingerprint': generationFingerprint},
      'source': source.toJson(),
    };
  }

  /// The exact text written to the receipt file.
  String encode() =>
      '${const JsonEncoder.withIndent('  ').convert(toJson())}\n';

  /// Decode a receipt file's text.
  static ReleaseReceipt decode(String source) {
    final Object? value;
    try {
      value = jsonDecode(source);
    } on FormatException catch (error) {
      throw FormatException('The receipt is not valid JSON: ${error.message}');
    }
    return ReleaseReceipt.fromJson(value);
  }

  /// Decode a receipt document.
  factory ReleaseReceipt.fromJson(Object? value) {
    final json = _requireMap(value, 'receipt');
    final version = _requireInt(json, 'receiptVersion');
    if (version != kReleaseReceiptVersion) {
      throw FormatException(
        'The receipt has version $version; this tool reads version '
        '$kReleaseReceiptVersion.',
      );
    }
    final rawArtifacts = json['artifacts'];
    return ReleaseReceipt(
      operation: ReceiptOperation.fromWireName(
        _requireString(json, 'operation'),
      ),
      recordedAt: _requireTimestamp(json, 'recordedAt'),
      target: ReceiptTarget.fromJson(json['target']),
      surface: json['surface'] == null
          ? null
          : ReceiptSurface.fromJson(json['surface']),
      bundle: json['bundle'] == null
          ? null
          : ReceiptBundle.fromJson(json['bundle']),
      revision: json['revision'] == null
          ? null
          : ReceiptRevision.fromJson(json['revision']),
      artifacts: rawArtifacts == null
          ? const <ReceiptArtifact>[]
          : <ReceiptArtifact>[
              for (final artifact in _requireList(rawArtifacts, 'artifacts'))
                ReceiptArtifact.fromJson(artifact),
            ],
      generationFingerprint: json['generation'] == null
          ? null
          : _requireHash(
              _requireMap(json['generation'], 'generation'),
              'fingerprint',
            ),
      source: ReceiptSource.fromJson(json['source']),
    );
  }
}

/// Format [at] as the receipt's UTC second-precision timestamp.
String formatReceiptTimestamp(DateTime at) {
  final utc = at.toUtc();
  String pad(int value, int width) => value.toString().padLeft(width, '0');
  return '${pad(utc.year, 4)}-${pad(utc.month, 2)}-${pad(utc.day, 2)}'
      'T${pad(utc.hour, 2)}:${pad(utc.minute, 2)}:${pad(utc.second, 2)}Z';
}

Map<String, Object?> _requireMap(Object? value, String what) {
  if (value is! Map) throw FormatException('Expected an object for $what.');
  return <String, Object?>{
    for (final entry in value.entries) '${entry.key}': entry.value,
  };
}

List<Object?> _requireList(Object? value, String key) {
  if (value is! List) throw FormatException('Expected a list for `$key`.');
  return value;
}

String _requireString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('Expected a non-empty string for `$key`.');
  }
  return value;
}

String? _optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  return _requireString(json, key);
}

int _requireInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int) throw FormatException('Expected an integer for `$key`.');
  return value;
}

int? _optionalInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  return _requireInt(json, key);
}

bool? _optionalBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! bool) throw FormatException('Expected a boolean for `$key`.');
  return value;
}

List<String> _stringList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return const <String>[];
  return <String>[
    for (final entry in _requireList(value, key))
      if (entry is String && entry.isNotEmpty)
        entry
      else
        throw FormatException('Expected non-empty strings in `$key`.'),
  ];
}

DateTime _requireTimestamp(Map<String, Object?> json, String key) {
  final value = _requireString(json, key);
  final DateTime parsed;
  try {
    parsed = DateTime.parse(value);
  } on FormatException {
    throw FormatException('Expected a UTC timestamp for `$key`.');
  }
  if (!value.endsWith('Z')) {
    throw FormatException('Expected a UTC timestamp for `$key`.');
  }
  return parsed.toUtc();
}

/// Content hashes are written as the pipeline produced them, which is a
/// 64-character digest with an optional algorithm in front.
final RegExp _contentHashPattern = RegExp(r'^(?:[a-z0-9]+:)?[0-9a-f]{64}$');

/// An engine set is identified by the bare digest of its canonical form.
final RegExp _engineSetPattern = RegExp(r'^[0-9a-f]{64}$');

/// Whether [value] is a content hash a receipt can carry.
bool isReceiptContentHash(String value) => _contentHashPattern.hasMatch(value);

/// Whether [value] identifies an engine set.
bool isEngineSetIdentity(String value) => _engineSetPattern.hasMatch(value);

String _requireHash(Map<String, Object?> json, String key) {
  final value = _requireString(json, key);
  if (!_contentHashPattern.hasMatch(value)) {
    throw FormatException('Expected a content hash for `$key`.');
  }
  return value;
}

String _requireEngineSetId(Map<String, Object?> json, String key) {
  final value = _requireString(json, key);
  if (!isEngineSetIdentity(value)) {
    throw FormatException('Expected an engine set identity for `$key`.');
  }
  return value;
}

String? _optionalCommit(Map<String, Object?> json, String key) {
  final value = _optionalString(json, key);
  if (value == null) return null;
  if (!_isHex(value, 40)) {
    throw FormatException('Expected a commit hash for `$key`.');
  }
  return value;
}

bool _isHex(String value, int length) {
  if (value.length != length) return false;
  for (final unit in value.codeUnits) {
    final isDigit = unit >= 0x30 && unit <= 0x39;
    final isLower = unit >= 0x61 && unit <= 0x66;
    if (!isDigit && !isLower) return false;
  }
  return true;
}
