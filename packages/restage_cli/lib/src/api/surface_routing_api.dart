import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:restage_cli/src/api/byte_data_wire.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

/// Largest routing document, preview input, or delivery blob the client will
/// put on, or accept from, the wire.
const kMaximumRoutingDocumentBytes = 1 << 20;

/// Whether a consumer of an audience is using it now.
@experimental
enum RoutingConsumerLifecycle {
  /// Serving or evaluating against the audience now.
  active,

  /// Held, and able to resume against the audience.
  paused,

  /// Finished. The reference row survives; the usage does not.
  concluded,

  /// Authored against the audience but never started.
  notActivated;

  /// Decode a wire name, or null when the server sent an unknown value.
  static RoutingConsumerLifecycle? fromWireName(Object? raw) {
    for (final value in values) {
      if (value.name == raw) return value;
    }
    return null;
  }
}

/// Why a preview classified one rule the way it did.
@experimental
enum RoutingPreviewRuleReason {
  /// The rule is switched off, so it was not evaluated.
  disabled,

  /// The rule's predicate held against the supplied request context.
  matched,

  /// The rule's predicate did not hold.
  notMatched;

  /// Decode a wire name, or null when the server sent an unknown value.
  static RoutingPreviewRuleReason? fromWireName(Object? raw) {
    for (final value in values) {
      if (value.name == raw) return value;
    }
    return null;
  }
}

/// Whether a publication changed the document or replayed an earlier attempt.
@experimental
enum RoutingPublicationOutcome {
  /// The document was written and the ordinal advanced.
  applied,

  /// The same operation id had already been applied with the same content.
  replayed;

  /// Decode a wire name, or null when the server sent an unknown value.
  static RoutingPublicationOutcome? fromWireName(Object? raw) {
    for (final value in values) {
      if (value.name == raw) return value;
    }
    return null;
  }
}

/// One sealed audience revision available to routing rules.
@experimental
@immutable
class RoutingAudience {
  /// Construct an audience summary.
  const RoutingAudience({
    required this.authorityId,
    required this.revisionId,
    required this.revisionOrdinal,
    required this.label,
    this.description,
  });

  /// Stable authority identity the revision belongs to.
  final String authorityId;

  /// Exact sealed revision identity a rule references.
  final String revisionId;

  /// Position of this revision within its authority.
  final int revisionOrdinal;

  /// Operator-facing name for the audience.
  final String label;

  /// Operator-facing description, when the service supplies one.
  final String? description;

  /// Decode one wire object.
  factory RoutingAudience.fromJson(Map<String, dynamic> json) =>
      RoutingAudience(
        authorityId: json['authorityId']! as String,
        revisionId: json['revisionId']! as String,
        revisionOrdinal: json['revisionOrdinal']! as int,
        label: json['label']! as String,
        description: json['description'] as String?,
      );

  /// Encode for `--json` output.
  Map<String, dynamic> toJson() => {
    'authorityId': authorityId,
    'revisionId': revisionId,
    'revisionOrdinal': revisionOrdinal,
    'label': label,
    'description': description,
  };
}

/// One page of audience revisions.
@experimental
@immutable
class RoutingAudiencePage {
  /// Construct a page.
  const RoutingAudiencePage({
    required this.audiences,
    required this.lastPage,
    this.nextCursor,
  });

  /// The page's audiences, newest first.
  final List<RoutingAudience> audiences;

  /// Whether this is the final page.
  final bool lastPage;

  /// Cursor for the next page, or null on the final page.
  final String? nextCursor;

  /// Decode one wire object.
  factory RoutingAudiencePage.fromJson(Map<String, dynamic> json) =>
      RoutingAudiencePage(
        audiences: _objects(
          json['audiences'],
        ).map(RoutingAudience.fromJson).toList(growable: false),
        lastPage: json['lastPage']! as bool,
        nextCursor: json['nextCursor'] as String?,
      );

  /// Encode for `--json` output.
  Map<String, dynamic> toJson() => {
    'audiences': [for (final a in audiences) a.toJson()],
    'lastPage': lastPage,
    'nextCursor': nextCursor,
  };
}

/// A routing document that references an audience.
@experimental
@immutable
class RoutingAudienceConsumer {
  /// Construct a routing consumer.
  const RoutingAudienceConsumer({
    required this.surfaceType,
    required this.surfaceSlug,
    required this.revisionOrdinal,
    required this.routeIds,
    required this.lifecycle,
    this.contractVersion,
  });

  /// Type of the surface whose routing document holds the reference.
  final String surfaceType;

  /// Slug of that surface.
  final String surfaceSlug;

  /// Standalone-screen contract version, or null for a flow lineage.
  final int? contractVersion;

  /// Routing revision holding the reference.
  final int revisionOrdinal;

  /// The routes inside that revision that name the audience.
  final List<String> routeIds;

  /// Whether the reference is current usage. Null for an unknown wire value.
  final RoutingConsumerLifecycle? lifecycle;

  /// Decode one wire object.
  factory RoutingAudienceConsumer.fromJson(Map<String, dynamic> json) =>
      RoutingAudienceConsumer(
        surfaceType: json['surfaceType']! as String,
        surfaceSlug: json['surfaceSlug']! as String,
        contractVersion: json['contractVersion'] as int?,
        revisionOrdinal: json['revisionOrdinal']! as int,
        routeIds: [
          for (final id in json['routeIds']! as List<dynamic>) id as String,
        ],
        lifecycle: RoutingConsumerLifecycle.fromWireName(json['lifecycle']),
      );

  /// Encode for `--json` output.
  Map<String, dynamic> toJson() => {
    'surfaceType': surfaceType,
    'surfaceSlug': surfaceSlug,
    'contractVersion': contractVersion,
    'revisionOrdinal': revisionOrdinal,
    'routeIds': routeIds,
    'lifecycle': lifecycle?.name,
  };
}

/// An experiment that references an audience.
@experimental
@immutable
class RoutingExperimentConsumer {
  /// Construct an experiment consumer.
  const RoutingExperimentConsumer({
    required this.ownerAuthorityKind,
    required this.ownerAuthorityId,
    required this.ownerRevisionId,
    required this.lifecycle,
  });

  /// Kind of the referencing authority.
  final String ownerAuthorityKind;

  /// Identity of the referencing authority.
  final String ownerAuthorityId;

  /// Exact revision of the referencing authority.
  final String ownerRevisionId;

  /// Whether the reference is current usage. Null for an unknown wire value.
  final RoutingConsumerLifecycle? lifecycle;

  /// Decode one wire object.
  factory RoutingExperimentConsumer.fromJson(Map<String, dynamic> json) =>
      RoutingExperimentConsumer(
        ownerAuthorityKind: json['ownerAuthorityKind']! as String,
        ownerAuthorityId: json['ownerAuthorityId']! as String,
        ownerRevisionId: json['ownerRevisionId']! as String,
        lifecycle: RoutingConsumerLifecycle.fromWireName(json['lifecycle']),
      );

  /// Encode for `--json` output.
  Map<String, dynamic> toJson() => {
    'ownerAuthorityKind': ownerAuthorityKind,
    'ownerAuthorityId': ownerAuthorityId,
    'ownerRevisionId': ownerRevisionId,
    'lifecycle': lifecycle?.name,
  };
}

/// One page of the consumers of a single audience revision.
@experimental
@immutable
class RoutingAudienceUsage {
  /// Construct a usage page.
  const RoutingAudienceUsage({
    required this.experiments,
    required this.routing,
    required this.lastPage,
    this.nextCursor,
  });

  /// Experiment references on this page.
  final List<RoutingExperimentConsumer> experiments;

  /// Routing-document references on this page.
  final List<RoutingAudienceConsumer> routing;

  /// Whether this is the final page.
  final bool lastPage;

  /// Cursor for the next page, or null on the final page.
  final String? nextCursor;

  /// Decode one wire object.
  factory RoutingAudienceUsage.fromJson(Map<String, dynamic> json) =>
      RoutingAudienceUsage(
        experiments: _objects(
          json['experiments'],
        ).map(RoutingExperimentConsumer.fromJson).toList(growable: false),
        routing: _objects(
          json['routing'],
        ).map(RoutingAudienceConsumer.fromJson).toList(growable: false),
        lastPage: json['lastPage']! as bool,
        nextCursor: json['nextCursor'] as String?,
      );

  /// Encode for `--json` output.
  Map<String, dynamic> toJson() => {
    'experiments': [for (final e in experiments) e.toJson()],
    'routing': [for (final r in routing) r.toJson()],
    'lastPage': lastPage,
    'nextCursor': nextCursor,
  };
}

/// The routing document currently stored for a surface and environment.
///
/// The document travels as opaque canonical bytes. The service is the only
/// decoder of its contents; this client carries them.
@experimental
@immutable
class RoutingDocumentRead {
  /// Construct a read result.
  const RoutingDocumentRead({
    required this.empty,
    this.documentBytes,
    this.revisionOrdinal,
  });

  /// Whether no routing document exists at the requested coordinates.
  final bool empty;

  /// Canonical document bytes, or null when [empty].
  final Uint8List? documentBytes;

  /// Ordinal of the stored revision, or null when [empty].
  final int? revisionOrdinal;

  /// Decode one wire object.
  factory RoutingDocumentRead.fromJson(Map<String, dynamic> json) =>
      RoutingDocumentRead(
        empty: json['empty']! as bool,
        documentBytes: json['documentBytes'] == null
            ? null
            : _routingBytes(json['documentBytes']),
        revisionOrdinal: json['revisionOrdinal'] as int?,
      );

  /// Encode for `--json` output. Bytes are standard padded base64.
  Map<String, dynamic> toJson() => {
    'empty': empty,
    'documentBase64': documentBytes == null
        ? null
        : base64Encode(documentBytes!),
    'revisionOrdinal': revisionOrdinal,
  };
}

/// One earlier revision of the routing document stored for a surface.
///
/// Read so a restore can be reviewed before it is asked for. The document
/// travels as opaque canonical bytes, exactly as the current read does.
@experimental
@immutable
class RoutingRevisionRead {
  /// Construct a revision read result.
  const RoutingRevisionRead({
    required this.revisionOrdinal,
    required this.documentBytes,
    required this.publishedAtMicros,
  });

  /// Ordinal of the revision that was read.
  final int revisionOrdinal;

  /// Canonical document bytes as they were stored at that revision.
  final Uint8List documentBytes;

  /// When the revision was published, in microseconds since the epoch, UTC.
  final int publishedAtMicros;

  /// When the revision was published.
  DateTime get publishedAt =>
      DateTime.fromMicrosecondsSinceEpoch(publishedAtMicros, isUtc: true);

  /// Decode one wire object.
  factory RoutingRevisionRead.fromJson(Map<String, dynamic> json) =>
      RoutingRevisionRead(
        revisionOrdinal: json['revisionOrdinal']! as int,
        documentBytes: _routingBytes(json['documentBytes']),
        publishedAtMicros: json['publishedAtMicros']! as int,
      );

  /// Encode for `--json` output. Bytes are standard padded base64.
  Map<String, dynamic> toJson() => {
    'revisionOrdinal': revisionOrdinal,
    'documentBase64': base64Encode(documentBytes),
    'publishedAtMicros': publishedAtMicros,
  };
}

/// How one rule classified against a supplied request context.
@experimental
@immutable
class RoutingPreviewRule {
  /// Construct a preview rule.
  const RoutingPreviewRule({
    required this.routeId,
    required this.matches,
    required this.reason,
  });

  /// The route this rule selects.
  final String routeId;

  /// Whether the rule matched.
  final bool matches;

  /// Why it classified that way. Null for an unknown wire value.
  final RoutingPreviewRuleReason? reason;

  /// Decode one wire object.
  factory RoutingPreviewRule.fromJson(Map<String, dynamic> json) =>
      RoutingPreviewRule(
        routeId: json['routeId']! as String,
        matches: json['matches']! as bool,
        reason: RoutingPreviewRuleReason.fromWireName(json['reason']),
      );

  /// Encode for `--json` output.
  Map<String, dynamic> toJson() => {
    'routeId': routeId,
    'matches': matches,
    'reason': reason?.name,
  };
}

/// A read-only evaluation of a routing document. Draws no percentage branch
/// and allocates no identity.
@experimental
@immutable
class RoutingPreview {
  /// Construct a preview result.
  const RoutingPreview({
    required this.rules,
    required this.usesActivePointer,
    this.deliveryBytes,
  });

  /// Every rule in document order, with its classification.
  final List<RoutingPreviewRule> rules;

  /// Whether the selection follows the surface's current default.
  final bool usesActivePointer;

  /// Canonical bytes of the selected delivery, or null when nothing matched.
  final Uint8List? deliveryBytes;

  /// Decode one wire object.
  factory RoutingPreview.fromJson(Map<String, dynamic> json) => RoutingPreview(
    rules: _objects(
      json['rules'],
    ).map(RoutingPreviewRule.fromJson).toList(growable: false),
    usesActivePointer: json['usesActivePointer']! as bool,
    deliveryBytes: json['deliveryBytes'] == null
        ? null
        : _routingBytes(json['deliveryBytes']),
  );

  /// Encode for `--json` output. Bytes are standard padded base64.
  Map<String, dynamic> toJson() => {
    'rules': [for (final rule in rules) rule.toJson()],
    'usesActivePointer': usesActivePointer,
    'deliveryBase64': deliveryBytes == null
        ? null
        : base64Encode(deliveryBytes!),
  };
}

/// The result of publishing or rolling back a routing document.
@experimental
@immutable
class RoutingPublication {
  /// Construct a publication result.
  const RoutingPublication({
    required this.outcome,
    required this.revisionOrdinal,
  });

  /// Whether the write applied or replayed. Null for an unknown wire value.
  final RoutingPublicationOutcome? outcome;

  /// The revision ordinal now stored.
  final int revisionOrdinal;

  /// Decode one wire object.
  factory RoutingPublication.fromJson(Map<String, dynamic> json) =>
      RoutingPublication(
        outcome: RoutingPublicationOutcome.fromWireName(json['outcome']),
        revisionOrdinal: json['revisionOrdinal']! as int,
      );

  /// Encode for `--json` output.
  Map<String, dynamic> toJson() => {
    'outcome': outcome?.name,
    'revisionOrdinal': revisionOrdinal,
  };
}

/// Sealed hierarchy for the routing endpoint's typed exceptions.
@experimental
@immutable
sealed class SurfaceRoutingTypedException implements Exception {
  /// Construct a routing typed exception.
  const SurfaceRoutingTypedException();
}

/// The stored revision is not the one the write expected. Carries both
/// ordinals so a reviewed retry can be built without a second read.
@experimental
class SurfaceRoutingConflict extends SurfaceRoutingTypedException {
  /// Construct with the ordinals the server reported.
  const SurfaceRoutingConflict({
    this.expectedRevisionOrdinal,
    this.actualRevisionOrdinal,
  });

  /// The ordinal the refused write expected, or null when it expected none.
  final int? expectedRevisionOrdinal;

  /// The ordinal actually stored, or null when nothing is stored.
  final int? actualRevisionOrdinal;

  @override
  String toString() =>
      'SurfaceRoutingConflict(expected: $expectedRevisionOrdinal, '
      'actual: $actualRevisionOrdinal)';
}

/// The service refused the request. [reason] is the service's own wire term,
/// surfaced without translation.
@experimental
class SurfaceRoutingRejected extends SurfaceRoutingTypedException {
  /// Construct with the service's [reason].
  const SurfaceRoutingRejected({required this.reason});

  /// The service's refusal term.
  final String reason;

  @override
  String toString() => 'SurfaceRoutingRejected(reason: $reason)';
}

/// Decode a routing typed exception from a response body, or null when the
/// body is not one.
@experimental
SurfaceRoutingTypedException? decodeSurfaceRoutingException(String body) {
  if (body.isEmpty) return null;
  final Object? doc;
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
    case 'SurfaceRoutingConflictException':
      return SurfaceRoutingConflict(
        expectedRevisionOrdinal: data['expectedRevisionOrdinal'] as int?,
        actualRevisionOrdinal: data['actualRevisionOrdinal'] as int?,
      );
    case 'SurfaceRoutingRejectedException':
      return SurfaceRoutingRejected(reason: data['reason']! as String);
    default:
      return null;
  }
}

/// Typed client for the surface routing operations.
///
/// Documents, schemas, request contexts and audiences travel as opaque
/// canonical bytes: the routing contracts are not part of the public SDK, so
/// this client validates the byte envelope and lets the service decode. Every
/// call carries the complete target on its arguments.
@experimental
class SurfaceRoutingApi {
  /// Create a client over the shared RPC transport.
  SurfaceRoutingApi(this._api);

  final RestageApi _api;

  /// List sealed audience revisions available at the target, newest first.
  Future<RoutingAudiencePage> listAudiences({
    required String projectSlug,
    required String appSlug,
    required int environmentId,
    required int organizationId,
    int pageSize = 50,
    String? cursor,
  }) async {
    final raw = await _call('listAudiences', <String, dynamic>{
      'projectSlug': projectSlug,
      'appSlug': appSlug,
      'environmentId': environmentId,
      'pageSize': pageSize,
      'cursor': cursor,
      'organizationId': organizationId,
    });
    return RoutingAudiencePage.fromJson(_object(raw));
  }

  /// List the experiments and routing documents that reference one audience.
  Future<RoutingAudienceUsage> listAudienceUsage({
    required String projectSlug,
    required String appSlug,
    required int environmentId,
    required int organizationId,
    required String audienceRevisionId,
    int pageSize = 50,
    String? cursor,
  }) async {
    final raw = await _call('listAudienceUsage', <String, dynamic>{
      'projectSlug': projectSlug,
      'appSlug': appSlug,
      'environmentId': environmentId,
      'audienceRevisionId': audienceRevisionId,
      'pageSize': pageSize,
      'cursor': cursor,
      'organizationId': organizationId,
    });
    return RoutingAudienceUsage.fromJson(_object(raw));
  }

  /// Read the routing document stored at the target.
  Future<RoutingDocumentRead> readRouting({
    required String projectSlug,
    required String appSlug,
    required String surfaceType,
    required String surfaceSlug,
    required int environmentId,
    required int organizationId,
    int? contractVersion,
  }) async {
    final raw = await _call('readRouting', <String, dynamic>{
      'projectSlug': projectSlug,
      'appSlug': appSlug,
      'surfaceType': surfaceType,
      'surfaceSlug': surfaceSlug,
      'environmentId': environmentId,
      'contractVersion': contractVersion,
      'organizationId': organizationId,
    });
    return RoutingDocumentRead.fromJson(_object(raw));
  }

  /// Read one earlier revision of the routing document at the target, so a
  /// restore can be reviewed before it is asked for.
  Future<RoutingRevisionRead> readRoutingRevision({
    required String projectSlug,
    required String appSlug,
    required String surfaceType,
    required String surfaceSlug,
    required int environmentId,
    required int organizationId,
    required int revisionOrdinal,
    int? contractVersion,
  }) async {
    final raw = await _call('readRoutingRevision', <String, dynamic>{
      'projectSlug': projectSlug,
      'appSlug': appSlug,
      'surfaceType': surfaceType,
      'surfaceSlug': surfaceSlug,
      'environmentId': environmentId,
      'revisionOrdinal': revisionOrdinal,
      'contractVersion': contractVersion,
      'organizationId': organizationId,
    });
    return RoutingRevisionRead.fromJson(_object(raw));
  }

  /// Evaluate [documentBytes] against a supplied request context.
  ///
  /// Read-only: no percentage branch is drawn and no identity is allocated.
  Future<RoutingPreview> previewRouting({
    required String projectSlug,
    required String appSlug,
    required String surfaceType,
    required String surfaceSlug,
    required int environmentId,
    required int organizationId,
    required List<int> documentBytes,
    required List<int> schemaBytes,
    required List<int> requestContextBytes,
    required List<List<int>> audienceBytes,
    List<int>? sdkBuiltInsBytes,
  }) async {
    final raw = await _call('previewRouting', <String, dynamic>{
      'projectSlug': projectSlug,
      'appSlug': appSlug,
      'surfaceType': surfaceType,
      'surfaceSlug': surfaceSlug,
      'environmentId': environmentId,
      'documentBytes': _wire(documentBytes, 'document'),
      'schemaBytes': _wire(schemaBytes, 'context schema'),
      'requestContextBytes': _wire(requestContextBytes, 'request context'),
      'audienceBytes': [
        for (final bytes in audienceBytes) _wire(bytes, 'audience'),
      ],
      'sdkBuiltInsBytes': sdkBuiltInsBytes == null
          ? null
          : _wire(sdkBuiltInsBytes, 'SDK built-ins'),
      'organizationId': organizationId,
    });
    return RoutingPreview.fromJson(_object(raw));
  }

  /// Publish [documentBytes] as the whole routing document at the target.
  ///
  /// [expectedRevisionOrdinal] is the compare-and-set precondition: the
  /// ordinal read with the document, or null to require that none is stored.
  /// [operationId] is the retry identity; a repeat with the same id and the
  /// same content is the same attempt.
  Future<RoutingPublication> publishRouting({
    required String projectSlug,
    required String appSlug,
    required String surfaceType,
    required String surfaceSlug,
    required int environmentId,
    required int organizationId,
    required List<int> documentBytes,
    required int? expectedRevisionOrdinal,
    required String operationId,
  }) async {
    final raw = await _call('publishRouting', <String, dynamic>{
      'projectSlug': projectSlug,
      'appSlug': appSlug,
      'surfaceType': surfaceType,
      'surfaceSlug': surfaceSlug,
      'environmentId': environmentId,
      'documentBytes': _wire(documentBytes, 'document'),
      'expectedRevisionOrdinal': expectedRevisionOrdinal,
      'operationId': operationId,
      'organizationId': organizationId,
    });
    return RoutingPublication.fromJson(_object(raw));
  }

  /// Restore one route to the shape it held at [priorRevisionOrdinal],
  /// leaving the rest of the document as stored.
  Future<RoutingPublication> rollbackRoute({
    required String projectSlug,
    required String appSlug,
    required String surfaceType,
    required String surfaceSlug,
    required int environmentId,
    required int organizationId,
    required String routeId,
    required int priorRevisionOrdinal,
    required int expectedRevisionOrdinal,
    required String operationId,
    int? contractVersion,
  }) async {
    final raw = await _call('rollbackRoute', <String, dynamic>{
      'projectSlug': projectSlug,
      'appSlug': appSlug,
      'surfaceType': surfaceType,
      'surfaceSlug': surfaceSlug,
      'environmentId': environmentId,
      'routeId': routeId,
      'priorRevisionOrdinal': priorRevisionOrdinal,
      'expectedRevisionOrdinal': expectedRevisionOrdinal,
      'contractVersion': contractVersion,
      'operationId': operationId,
      'organizationId': organizationId,
    });
    return RoutingPublication.fromJson(_object(raw));
  }

  /// Reads bounded, target-resolved delivery diagnostics for one UTC window.
  ///
  /// The result keeps admitted served-default presentations separate from
  /// recorded server refusals. It is decoded by the public Measurement
  /// contract so canonical bytes, disclosure state, and both populations stay
  /// intact for every consumer.
  Future<MeasurementDeliveryDiagnosticsV1> readDeliveryDiagnostics({
    required String projectSlug,
    required String appSlug,
    required String surfaceType,
    required String surfaceSlug,
    required int environmentId,
    required int organizationId,
    required int windowStartDayUtc,
    required int windowEndDayExclusiveUtc,
    int? contractVersion,
  }) async {
    final raw = await _call('readDeliveryDiagnostics', <String, dynamic>{
      'projectSlug': projectSlug,
      'appSlug': appSlug,
      'surfaceType': surfaceType,
      'surfaceSlug': surfaceSlug,
      'environmentId': environmentId,
      'windowStartDayUtc': windowStartDayUtc,
      'windowEndDayExclusiveUtc': windowEndDayExclusiveUtc,
      'contractVersion': contractVersion,
      'organizationId': organizationId,
    });
    return MeasurementDeliveryDiagnosticsV1.fromCanonicalBytes(
      decodeByteDataWire(
        raw,
        maximumBytes: measurementDeliveryDiagnosticsMaximumCanonicalBytes,
        malformed: (detail) =>
            FormatException('The delivery diagnostics response $detail.'),
      ),
    );
  }

  Future<Object?> _call(String method, Map<String, dynamic> args) =>
      _api.call(_endpointName, method, args);
}

const _endpointName = 'surfaceRouting';

/// Converts a strict `YYYY-MM-DD` UTC calendar date to its day-start instant.
///
/// Diagnostics reads take integer microseconds on the wire, while CLI and MCP
/// callers use a calendar date so a local time zone never changes the window.
@experimental
int parseDeliveryDiagnosticsUtcDate(String value) {
  final match = _deliveryDiagnosticsDatePattern.firstMatch(value);
  if (match == null || match.start != 0 || match.end != value.length) {
    throw const FormatException('Expected a UTC date in YYYY-MM-DD form.');
  }
  final year = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  final date = DateTime.utc(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    throw const FormatException('Expected a real UTC calendar date.');
  }
  return date.microsecondsSinceEpoch;
}

/// Checks the public contract's whole-day, half-open retained window.
@experimental
void validateDeliveryDiagnosticsUtcWindow({
  required int windowStartDayUtc,
  required int windowEndDayExclusiveUtc,
}) {
  if (windowStartDayUtc <= 0 || windowEndDayExclusiveUtc <= 0) {
    throw const FormatException('UTC dates must be after 1970-01-01.');
  }
  if (windowStartDayUtc.remainder(measurementDeliveryDiagnosticsDayMicros) !=
          0 ||
      windowEndDayExclusiveUtc.remainder(
            measurementDeliveryDiagnosticsDayMicros,
          ) !=
          0) {
    throw const FormatException('Diagnostics bounds must be UTC day starts.');
  }
  final span = windowEndDayExclusiveUtc - windowStartDayUtc;
  if (span <= 0) {
    throw const FormatException(
      'The exclusive end date must be after the start date.',
    );
  }
  if (span > measurementDeliveryDiagnosticsRetentionWindowMicros) {
    final maximumDays =
        measurementDeliveryDiagnosticsRetentionWindowMicros ~/
        measurementDeliveryDiagnosticsDayMicros;
    throw FormatException(
      'The UTC date window must span no more than $maximumDays days.',
    );
  }
}

final _deliveryDiagnosticsDatePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// Raised when a caller hands this client bytes outside the bounded shape the
/// wire accepts. Raised before any request is sent.
@experimental
class RoutingDocumentBytesException implements Exception {
  /// Construct with the [role] of the offending byte sequence.
  const RoutingDocumentBytesException(this.role);

  /// Which argument was out of bounds, for the operator's message.
  final String role;

  @override
  String toString() =>
      'The $role must be between 1 and $kMaximumRoutingDocumentBytes bytes.';
}

String _wire(List<int> bytes, String role) {
  if (bytes.isEmpty || bytes.length > kMaximumRoutingDocumentBytes) {
    throw RoutingDocumentBytesException(role);
  }
  return encodeByteDataWire(bytes);
}

Uint8List _routingBytes(Object? raw) => decodeByteDataWire(
  raw,
  maximumBytes: kMaximumRoutingDocumentBytes,
  malformed: (detail) =>
      FormatException('The routing response byte field $detail.'),
);

Map<String, dynamic> _object(Object? raw) {
  if (raw is! Map<String, dynamic>) {
    throw const FormatException('The routing response was not an object.');
  }
  return raw;
}

Iterable<Map<String, dynamic>> _objects(Object? raw) {
  if (raw == null) return const [];
  if (raw is! List<dynamic>) {
    throw const FormatException('The routing response was not a list.');
  }
  return raw.map(_object);
}
