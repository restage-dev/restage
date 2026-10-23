import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:restage_cli/src/api/byte_data_wire.dart';
import 'package:restage_cli/src/api/delivery_management_api.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/surface_reach.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

/// Largest retained policy or review the routing client accepts from the wire.
const kMaximumRoutingDocumentBytes = kMaximumRoutingResponseBytes;

/// Largest current routing request accepted by the service.
const kMaximumRoutingRequestBytes = 512 * 1024;

/// Largest complete routing policy, simulation, or review response.
const kMaximumRoutingResponseBytes = 32 * 1024 * 1024;

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

/// An experiment whose authoring names an audience.
@experimental
@immutable
class RoutingExperimentConsumer {
  /// Construct an experiment consumer.
  const RoutingExperimentConsumer({
    required this.experimentId,
    required this.experimentLabel,
    required this.lifecycle,
  });

  /// The experiment's identity.
  final String experimentId;

  /// The experiment's name, when it has one.
  final String? experimentLabel;

  /// Whether the experiment is using the audience now. Null for an unknown
  /// wire value.
  final RoutingConsumerLifecycle? lifecycle;

  /// Decode one wire object.
  factory RoutingExperimentConsumer.fromJson(Map<String, dynamic> json) =>
      RoutingExperimentConsumer(
        experimentId: json['experimentId']! as String,
        experimentLabel: json['experimentLabel'] as String?,
        lifecycle: RoutingConsumerLifecycle.fromWireName(json['lifecycle']),
      );

  /// Encode for `--json` output.
  Map<String, dynamic> toJson() => {
    'experimentId': experimentId,
    'experimentLabel': experimentLabel,
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

/// Views one source served to one version: a rule, an experiment, everyone
/// else, or views with no delivery record.
@experimental
@immutable
class DeliveryFlowCell {
  /// Construct a cell.
  const DeliveryFlowCell({
    required this.source,
    required this.version,
    required this.views,
    this.approxViews,
    this.routeId,
    this.experimentId,
    this.experimentLabel,
    this.experimentState,
    this.removed = false,
  });

  /// Who served the views: `rule`, `experiment`, `earlierExperiments`,
  /// `everyoneElse` or `notRecorded`.
  final String source;

  /// The rule, for a rule's cell.
  final String? routeId;

  /// The experiment, for an experiment's cell.
  final String? experimentId;

  /// The experiment's name; null when it has none to show.
  final String? experimentLabel;

  /// Where the experiment stands: `running`, `paused` or `finished`.
  final String? experimentState;

  /// Whether the rule has left the routing since it served these views.
  final bool removed;

  /// The published version the views saw.
  final int version;

  /// The views; null when held under the disclosure floor, never zero.
  final int? views;

  /// A merged cell's rounded views when one of its cells is held; null when
  /// [views] is stated or the cell is one held count (under the floor).
  final int? approxViews;

  /// One cell of a flow source, as the service states it.
  factory DeliveryFlowCell.fromSource(
    Map<String, dynamic> source,
    Map<String, dynamic> cell,
  ) {
    final kind = source['kind']! as String;
    return DeliveryFlowCell(
      source: kind,
      routeId: kind == 'rule' ? source['id'] as String? : null,
      experimentId: kind == 'experiment' ? source['id'] as String? : null,
      experimentLabel: kind == 'experiment' ? source['label'] as String? : null,
      experimentState: kind == 'experiment' ? source['state'] as String? : null,
      removed: source['removed'] == true,
      version: cell['version']! as int,
      views: cell['views'] as int?,
    );
  }

  /// Encode for `--json` output.
  Map<String, dynamic> toJson() => {
    'source': source,
    'routeId': routeId,
    'experimentId': experimentId,
    'experimentLabel': source == 'experiment'
        ? experimentLabel ?? 'Unnamed experiment'
        : experimentLabel,
    'experimentState': experimentState,
    'removed': removed,
    'version': version,
    'views': views,
    'approxViews': approxViews,
  };
}

/// One surface's views over a whole UTC-day window, by rule and version.
@experimental
@immutable
class DeliveryFlowRead {
  /// Construct a flow read.
  const DeliveryFlowRead({
    required this.windowStartDayUtc,
    required this.windowEndDayExclusiveUtc,
    required this.disclosureFloor,
    required this.cells,
  });

  /// First UTC day included, in microseconds since the epoch.
  final int windowStartDayUtc;

  /// First UTC day excluded, in microseconds since the epoch.
  final int windowEndDayExclusiveUtc;

  /// The floor the service applied: a count under it is withheld.
  final int disclosureFloor;

  /// Each rule's cells, each experiment's, everyone else's, then the cells
  /// with no delivery record.
  final List<DeliveryFlowCell> cells;

  /// Decode the service's flow for the window that was asked for.
  factory DeliveryFlowRead.fromJson(
    Map<String, dynamic> json, {
    required int windowStartDayUtc,
    required int windowEndDayExclusiveUtc,
  }) => DeliveryFlowRead(
    windowStartDayUtc: windowStartDayUtc,
    windowEndDayExclusiveUtc: windowEndDayExclusiveUtc,
    disclosureFloor: json['disclosureFloor']! as int,
    cells: [
      for (final source in _objects(json['sources']))
        for (final cell in _objects(source['cells']))
          DeliveryFlowCell.fromSource(source, cell),
    ],
  );

  /// The cells as shown: each rule's, each running experiment's, finished
  /// experiments' together per version, then everyone else's. Views with no
  /// delivery record are counted in [notRecordedViews] instead.
  List<DeliveryFlowCell> get shownCells {
    final earlier = <int, List<int?>>{};
    final shown = <DeliveryFlowCell>[];
    for (final cell in cells) {
      switch (cell.source) {
        case 'notRecorded':
          continue;
        case 'experiment' when cell.experimentState == 'finished':
          (earlier[cell.version] ??= <int?>[]).add(cell.views);
        default:
          shown.add(cell);
      }
    }
    final everyoneElse = shown.indexWhere(
      (cell) => cell.source == 'everyoneElse',
    );
    shown.insertAll(everyoneElse < 0 ? shown.length : everyoneElse, [
      for (final MapEntry(key: version, value: parts) in earlier.entries)
        if (measurementDisclosedSumV1(parts) case (:final exact, :final approx))
          DeliveryFlowCell(
            source: 'earlierExperiments',
            version: version,
            views: exact,
            approxViews: approx,
          ),
    ]);
    return shown;
  }

  /// Every view in the window; null when any count is hidden.
  int? get totalViews => _sum(cells).exact;

  /// The total's rounded stand-in when a count is hidden; null when
  /// [totalViews] is stated or the total is one hidden count.
  int? get approxTotalViews => _sum(cells).approx;

  /// Views with no delivery record; null when one is hidden.
  int? get notRecordedViews => _sum(_notRecorded).exact;

  /// [notRecordedViews] rounded when one is hidden.
  int? get approxNotRecordedViews => _sum(_notRecorded).approx;

  Iterable<DeliveryFlowCell> get _notRecorded =>
      cells.where((cell) => cell.source == 'notRecorded');

  static ({int? exact, int? approx}) _sum(Iterable<DeliveryFlowCell> cells) =>
      measurementDisclosedSumV1([for (final cell in cells) cell.views]);

  /// Encode for `--json` output: the shown cells and the totals.
  Map<String, dynamic> toJson() => {
    'windowStartDayUtc': windowStartDayUtc,
    'windowEndDayExclusiveUtc': windowEndDayExclusiveUtc,
    'disclosureFloor': disclosureFloor,
    'cells': [for (final cell in shownCells) cell.toJson()],
    'totalViews': totalViews,
    'approxTotalViews': approxTotalViews,
    'notRecordedViews': notRecordedViews,
    'approxNotRecordedViews': approxNotRecordedViews,
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

  /// The complete current simulation, including validation and selection evidence.
  DeliveryPolicySimulationV1? get simulation => deliveryBytes == null
      ? null
      : DeliveryPolicySimulationV1.fromCanonicalBytes(deliveryBytes!);

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
    'simulation': simulation?.toJson(),
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
/// Stored complete policies travel as original opaque bytes. Review,
/// simulation, and publish requests use the strict public delivery codecs.
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
    List<int>? schemaBytes,
    List<int>? requestContextBytes,
    List<List<int>> audienceBytes = const [],
    List<int>? sdkBuiltInsBytes,
    TargetCoordinate? expectedTarget,
  }) async {
    if (schemaBytes != null ||
        requestContextBytes != null ||
        audienceBytes.isNotEmpty ||
        sdkBuiltInsBytes != null) {
      throw const FormatException('Use one current simulation request.');
    }
    final request = DeliveryPolicySimulationRequestV1.fromCanonicalBytes(
      documentBytes,
    );
    requireSurfaceRoutingScope(
      request.scope,
      organizationId: organizationId,
      environmentId: environmentId,
      expectedTarget: expectedTarget,
    );
    final raw = await _call('previewRouting', <String, dynamic>{
      'projectSlug': projectSlug,
      'appSlug': appSlug,
      'surfaceType': surfaceType,
      'surfaceSlug': surfaceSlug,
      'environmentId': environmentId,
      'documentBytes': _wire(documentBytes, 'document'),
      'schemaBytes': null,
      'requestContextBytes': null,
      'audienceBytes': <Object>[],
      'sdkBuiltInsBytes': null,
      'organizationId': organizationId,
    });
    try {
      final preview = RoutingPreview.fromJson(_object(raw));
      if (preview.deliveryBytes == null ||
          DeliveryPolicySimulationV1.fromCanonicalBytes(
                preview.deliveryBytes!,
              ).scope !=
              request.scope) {
        throw const DeliveryManagementResponseException();
      }
      return preview;
    } on CanonicalFormatException {
      throw const DeliveryManagementResponseException();
    } on FormatException {
      throw const DeliveryManagementResponseException();
    }
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
    TargetCoordinate? expectedTarget,
    bool acceptFit = false,
  }) async {
    final request = DeliveryPolicyPublishRequestV1.fromCanonicalBytes(
      documentBytes,
    );
    requireSurfaceRoutingScope(
      request.reviewRef.scope,
      organizationId: organizationId,
      environmentId: environmentId,
      expectedTarget: expectedTarget,
    );
    if (request.operationId != operationId) {
      throw const FormatException('The operation id differs from the request.');
    }
    final raw = await _call('publishRouting', <String, dynamic>{
      if (acceptFit) 'acceptFit': true,
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
    DeliveryPolicyPublishRequestV1? reviewedPublishRequest,
    TargetCoordinate? expectedTarget,
    bool acceptFit = false,
  }) async {
    if (reviewedPublishRequest == null) {
      throw const FormatException('A server-issued route review is required.');
    }
    requireSurfaceRoutingScope(
      reviewedPublishRequest.reviewRef.scope,
      organizationId: organizationId,
      environmentId: environmentId,
      contractVersion: contractVersion,
      expectedTarget: expectedTarget,
    );
    if (reviewedPublishRequest.operationId != operationId) {
      throw const FormatException('The operation id differs from the review.');
    }
    final raw = await _call('rollbackRoute', <String, dynamic>{
      if (acceptFit) 'acceptFit': true,
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
      'reviewedPublishRequestBytes': _wire(
        reviewedPublishRequest.canonicalBytes,
        'reviewed publish request',
      ),
    });
    return RoutingPublication.fromJson(_object(raw));
  }

  /// Freezes one complete candidate policy under its exact expected head.
  Future<DeliveryPolicyReviewV1> reviewRouting({
    required String projectSlug,
    required String appSlug,
    required String surfaceType,
    required String surfaceSlug,
    required int environmentId,
    required int organizationId,
    required DeliveryPolicyReviewRequestV1 request,
    TargetCoordinate? expectedTarget,
  }) async {
    requireSurfaceRoutingScope(
      request.scope,
      organizationId: organizationId,
      environmentId: environmentId,
      expectedTarget: expectedTarget,
    );
    final raw = await _call('reviewRouting', <String, dynamic>{
      'projectSlug': projectSlug,
      'appSlug': appSlug,
      'surfaceType': surfaceType,
      'surfaceSlug': surfaceSlug,
      'environmentId': environmentId,
      'organizationId': organizationId,
      'requestBytes': _wire(request.canonicalBytes, 'review request'),
    });
    final review = _routingReview(raw);
    if (review.scope != request.scope ||
        review.expectedHeadOrdinal != request.expectedHeadOrdinal ||
        review.candidatePlan != request.candidatePlan ||
        review.reason != request.reason) {
      throw const DeliveryManagementResponseException();
    }
    return review;
  }

  /// Reviews restoration of the selected route using retained server authority.
  Future<DeliveryPolicyReviewV1> reviewRouteRollback({
    required String projectSlug,
    required String appSlug,
    required String surfaceType,
    required String surfaceSlug,
    required int environmentId,
    required int organizationId,
    required String routeId,
    required int priorRevisionOrdinal,
    required int expectedRevisionOrdinal,
    int? contractVersion,
    TargetCoordinate? expectedTarget,
  }) async {
    final raw = await _call('reviewRouteRollback', <String, dynamic>{
      'projectSlug': projectSlug,
      'appSlug': appSlug,
      'surfaceType': surfaceType,
      'surfaceSlug': surfaceSlug,
      'environmentId': environmentId,
      'organizationId': organizationId,
      'routeId': routeId,
      'priorRevisionOrdinal': priorRevisionOrdinal,
      'expectedRevisionOrdinal': expectedRevisionOrdinal,
      'contractVersion': contractVersion,
    });
    final review = _routingReview(raw);
    try {
      requireSurfaceRoutingScope(
        review.scope,
        organizationId: organizationId,
        environmentId: environmentId,
        contractVersion: contractVersion,
        expectedTarget: expectedTarget,
      );
      if (review.expectedHeadOrdinal != expectedRevisionOrdinal) {
        throw const DeliveryManagementResponseException();
      }
    } on FormatException {
      throw const DeliveryManagementResponseException();
    }
    return review;
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

  /// Reads how far one surface's live version reached devices on one target.
  Future<SurfaceReach> readSurfaceReach({
    required String projectSlug,
    required String appSlug,
    required String surfaceType,
    required String surfaceSlug,
    required int environmentId,
    int? organizationId,
  }) async {
    final raw = await _call('readSurfaceReach', <String, dynamic>{
      'projectSlug': projectSlug,
      'appSlug': appSlug,
      'surfaceType': surfaceType,
      'surfaceSlug': surfaceSlug,
      'environmentId': environmentId,
      'organizationId': organizationId,
    });
    return SurfaceReach.fromBytes(
      decodeByteDataWire(
        raw,
        maximumBytes: surfaceReachMaximumBytes,
        malformed: (detail) =>
            FormatException('The surface reach response $detail.'),
      ),
    );
  }

  /// Reads every view of one surface over a whole UTC-day window, by who
  /// served it and the version it saw.
  Future<DeliveryFlowRead> readDeliveryFlow({
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
    final raw = await _call('readDeliveryFlow', <String, dynamic>{
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
    final bytes = decodeByteDataWire(
      raw,
      maximumBytes: deliveryFlowMaximumBytes,
      malformed: (detail) =>
          FormatException('The delivery flow response $detail.'),
    );
    final read = DeliveryFlowRead.fromJson(
      jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
      windowStartDayUtc: windowStartDayUtc,
      windowEndDayExclusiveUtc: windowEndDayExclusiveUtc,
    );
    return read;
  }

  Future<Object?> _call(String method, Map<String, dynamic> args) =>
      _api.call(_endpointName, method, args);
}

/// The most bytes a delivery flow reply may carry.
const int deliveryFlowMaximumBytes = 256 * 1024;

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
      'The $role must be between 1 and $kMaximumRoutingRequestBytes bytes.';
}

String _wire(List<int> bytes, String role) {
  if (bytes.isEmpty || bytes.length > kMaximumRoutingRequestBytes) {
    throw RoutingDocumentBytesException(role);
  }
  return encodeByteDataWire(bytes);
}

Uint8List _routingBytes(Object? raw) => decodeByteDataWire(
  raw,
  maximumBytes: kMaximumRoutingResponseBytes,
  malformed: (detail) =>
      FormatException('The routing response byte field $detail.'),
);

DeliveryPolicyReviewV1 _routingReview(Object? raw) {
  try {
    return DeliveryPolicyReviewV1.fromCanonicalBytes(_routingBytes(raw));
  } on CanonicalFormatException {
    throw const DeliveryManagementResponseException();
  } on FormatException {
    throw const DeliveryManagementResponseException();
  }
}

/// Requires the reviewed public scope to name this exact admitted surface target.
@experimental
void requireSurfaceRoutingScope(
  DeliveryPolicyScopeV1 scope, {
  required int organizationId,
  required int environmentId,
  int? contractVersion,
  TargetCoordinate? expectedTarget,
}) {
  if (scope.root.surface == null ||
      scope.target.organizationId.value != organizationId ||
      scope.target.environmentTargetId.value != environmentId ||
      (contractVersion != null &&
          scope.family.contractVersion != contractVersion) ||
      (expectedTarget != null && scope.target != expectedTarget)) {
    throw const FormatException('The policy names another surface target.');
  }
}

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
