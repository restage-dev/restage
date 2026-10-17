import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_mcp/server.dart';
import 'package:restage_cli/api.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    show
        CanonicalFormatException,
        TargetCoordinate,
        DeliveryPolicyScopeV1,
        DeliveryPolicyReviewRequestV1,
        DeliveryPolicyReviewV1,
        DeliveryPolicyPublishRequestV1,
        DeliveryPolicySimulationRequestV1;

import 'api_runner.dart';
import 'tool_support.dart';

/// The routing tools, bound to [ctx].
List<ToolEntry> routingTools(ToolContext ctx) => [
  (_listRoutingAudiencesTool, (request) => _listRoutingAudiences(ctx, request)),
  (_routingAudienceUsageTool, (request) => _routingAudienceUsage(ctx, request)),
  (_readRoutingTool, (request) => _readRouting(ctx, request)),
  (
    _readDeliveryDiagnosticsTool,
    (request) => _readDeliveryDiagnostics(ctx, request),
  ),
  (_readDeliveryFlowTool, (request) => _readDeliveryFlow(ctx, request)),
  (_readRoutingRevisionTool, (request) => _readRoutingRevision(ctx, request)),
  (_previewRoutingTool, (request) => _previewRouting(ctx, request)),
  liveGuarded(ctx, (
    _reviewRoutingTool,
    (request) => _reviewRouting(ctx, request),
  )),
  liveGuarded(ctx, (
    _reviewRouteRollbackTool,
    (request) => _reviewRouteRollback(ctx, request),
  )),
  liveGuarded(ctx, (
    _publishRoutingTool,
    (request) => _publishRouting(ctx, request),
  )),
  liveGuarded(ctx, (
    _rollbackRouteTool,
    (request) => _rollbackRoute(ctx, request),
  )),
];

/// Largest routing document or preview input this server will accept.
const _maximumRoutingBytes = kMaximumRoutingRequestBytes;

final _pageSizeProperty = Schema.int(
  description: 'Optional rows per page, 1 to 200. Defaults to 50.',
);

final _cursorProperty = Schema.string(
  description: 'Optional cursor from a previous page.',
);

final _operationIdProperty = Schema.string(
  description:
      'Optional retry identity as a canonical version 4 UUID. A repeat with '
      'the same id and the same content is the same attempt. Generated when '
      'omitted.',
);

Map<String, Schema> _targetProperties({required bool surfaceScoped}) => {
  ...appProperties(),
  if (surfaceScoped) 'surfaceType': surfaceTypeProperty,
  if (surfaceScoped) 'surfaceSlug': surfaceSlugProperty,
  'environmentSlug': Schema.string(
    description:
        'The environment slug. Names the target with runtimePlane when '
        'environmentTargetId is left out.',
  ),
  'runtimePlane': runtimePlaneProperty,
  'environmentTargetId': environmentTargetIdProperty,
  if (surfaceScoped) 'contractVersion': contractVersionProperty,
};

List<String> _requiredTarget({required bool surfaceScoped}) => [
  ...appRequired,
  if (surfaceScoped) 'surfaceType',
  if (surfaceScoped) 'surfaceSlug',
];

/// List the sealed audience revisions routing rules can reference.
final _listRoutingAudiencesTool = Tool(
  name: 'restage_list_routing_audiences',
  description:
      'List the sealed audience revisions a routing rule can name, newest '
      'first. Returns each audience id, its exact revision, its ordinal, and '
      'the name and description recorded for it. One page per call: pass the '
      'returned cursor to continue.',
  inputSchema: Schema.object(
    properties: {
      ..._targetProperties(surfaceScoped: false),
      'pageSize': _pageSizeProperty,
      'cursor': _cursorProperty,
    },
    required: _requiredTarget(surfaceScoped: false),
    additionalProperties: false,
  ),
);

/// List what references one audience revision.
final _routingAudienceUsageTool = Tool(
  name: 'restage_routing_audience_usage',
  description:
      'List the experiments and routing documents that reference one audience '
      'revision, each with whether it is using the audience now. One page per '
      'call: pass the returned cursor to continue.',
  inputSchema: Schema.object(
    properties: {
      ..._targetProperties(surfaceScoped: false),
      'audienceRevisionId': Schema.string(
        description: 'The exact sealed audience revision to report on.',
      ),
      'pageSize': _pageSizeProperty,
      'cursor': _cursorProperty,
    },
    required: [..._requiredTarget(surfaceScoped: false), 'audienceRevisionId'],
    additionalProperties: false,
  ),
);

/// Read the stored routing document.
final _readRoutingTool = Tool(
  name: 'restage_read_routing',
  description:
      'Read the routing document stored for one surface in one environment: '
      'the ordered rules deciding which published version a request receives. '
      'Returns the canonical document as standard padded base64 plus the '
      'revision ordinal to pass back as a compare-and-set precondition.',
  inputSchema: Schema.object(
    properties: _targetProperties(surfaceScoped: true),
    required: _requiredTarget(surfaceScoped: true),
    additionalProperties: false,
  ),
);

/// Read bounded delivery diagnostics for one surface and UTC-day window.
final _readDeliveryDiagnosticsTool = Tool(
  name: 'restage_read_delivery_diagnostics',
  description:
      'Read delivery diagnostics for one surface over a whole, half-open UTC '
      'date window. It returns separate observed served-default presentations '
      'and recorded server refusals, with each section\'s coverage and '
      'disclosure state. Held and unavailable counts are not zero, and neither '
      'section is a people, device, or all-request census.',
  inputSchema: Schema.object(
    properties: {
      ..._targetProperties(surfaceScoped: true),
      'windowStartDateUtc': Schema.string(
        description:
            'First UTC date included, in strict YYYY-MM-DD calendar form.',
      ),
      'windowEndDateExclusiveUtc': Schema.string(
        description:
            'First UTC date excluded, in strict YYYY-MM-DD calendar form. '
            'The window is half-open and may span at most the retained '
            'Measurement period.',
      ),
    },
    required: [
      ..._requiredTarget(surfaceScoped: true),
      'windowStartDateUtc',
      'windowEndDateExclusiveUtc',
    ],
    additionalProperties: false,
  ),
);

/// Read who saw which version for one surface and UTC-day window.
final _readDeliveryFlowTool = Tool(
  name: 'restage_read_delivery_flow',
  description:
      'Who saw which version of one surface over whole UTC days: each routing '
      'rule\'s views by version, each experiment\'s, everyone else, and views '
      'with no delivery record. A count under the disclosure floor of 5 is '
      'null and reads "<5". A total or merged cell that includes one is null, '
      'and its approx field carries a rounded figure built only from the '
      'stated counts. The approx field is null when the total is a single '
      'held count.',
  inputSchema: Schema.object(
    properties: {
      ..._targetProperties(surfaceScoped: true),
      'windowStartDateUtc': Schema.string(
        description:
            'First UTC date included, in strict YYYY-MM-DD calendar form.',
      ),
      'windowEndDateExclusiveUtc': Schema.string(
        description:
            'First UTC date excluded, in strict YYYY-MM-DD calendar form. '
            'The window is half-open and may span at most the retained '
            'Measurement period.',
      ),
    },
    required: [
      ..._requiredTarget(surfaceScoped: true),
      'windowStartDateUtc',
      'windowEndDateExclusiveUtc',
    ],
    additionalProperties: false,
  ),
);

/// Read one earlier revision of the stored routing document.
final _readRoutingRevisionTool = Tool(
  name: 'restage_read_routing_revision',
  description:
      'Read one earlier revision of the routing document stored for a surface '
      'in one environment, so a restore can be reviewed before it is asked '
      'for. Returns that revision as standard padded base64, its ordinal, and '
      'when it was published. Pass an ordinal below the one a read returns.',
  inputSchema: Schema.object(
    properties: {
      ..._targetProperties(surfaceScoped: true),
      'revisionOrdinal': Schema.int(
        description: 'The revision to read. One or greater.',
      ),
    },
    required: [..._requiredTarget(surfaceScoped: true), 'revisionOrdinal'],
    additionalProperties: false,
  ),
);

final _reviewedDigestProperty = Schema.string(
  description:
      'Exact digest of the complete original policy review whose measurement warnings you approved.',
);

/// Simulate one current policy request using retained server authority.
final _previewRoutingTool = Tool(
  name: 'restage_preview_routing',
  description:
      'Simulate a current DeliveryPolicySimulationRequestV1 without allocating or enrolling an identity. Returns complete selection and validation evidence.',
  inputSchema: Schema.object(
    properties: {
      ..._targetProperties(surfaceScoped: true),
      'documentBase64': Schema.string(
        description:
            'Canonical DeliveryPolicySimulationRequestV1 as standard padded base64.',
      ),
    },
    required: [
      ..._requiredTarget(surfaceScoped: true),
      'environmentSlug',
      'documentBase64',
    ],
    additionalProperties: false,
  ),
);

/// Freeze a complete candidate under the expected current policy head.
final _reviewRoutingTool = Tool(
  name: 'restage_review_routing',
  description:
      'Retain a complete candidate policy and its original server measurement impact review. Publish that exact review separately. '
      'A rule may carry an optional name of 1 to 60 characters with no leading or trailing space; serving ignores it.',
  inputSchema: Schema.object(
    properties: {
      ..._targetProperties(surfaceScoped: true),
      'requestBase64': Schema.string(
        description:
            'Canonical DeliveryPolicyReviewRequestV1 as standard padded base64.',
      ),
    },
    required: [
      ..._requiredTarget(surfaceScoped: true),
      'environmentSlug',
      'requestBase64',
    ],
    additionalProperties: false,
  ),
);

/// Publish only a complete original server review.
final _publishRoutingTool = Tool(
  name: 'restage_publish_routing',
  description:
      'Publish an original DeliveryPolicyReviewV1 with its exact head, operation id, and explicitly acknowledged complete warning set.',
  inputSchema: Schema.object(
    properties: {
      ..._targetProperties(surfaceScoped: true),
      'reviewBase64': Schema.string(
        description:
            'The complete original canonical DeliveryPolicyReviewV1 as standard padded base64.',
      ),
      'reviewedDigest': _reviewedDigestProperty,
      'expectedRevisionOrdinal': Schema.int(
        description:
            'Optional expected-head assertion, which must match the review.',
      ),
      'expectNoRevision': Schema.bool(
        description:
            'Optional first-publication assertion, which must match the review.',
      ),
      'operationId': _operationIdProperty,
      'acceptFit': acceptFitProperty,
    },
    required: [
      ..._requiredTarget(surfaceScoped: true),
      'environmentSlug',
      'reviewBase64',
    ],
    additionalProperties: false,
  ),
);

Map<String, Schema> get _routeRollbackProperties => {
  ..._targetProperties(surfaceScoped: true),
  'routeId': Schema.string(description: 'The original route to restore.'),
  'priorRevisionOrdinal': Schema.int(
    description: 'The retained revision to restore the selected route from.',
  ),
  'expectedRevisionOrdinal': Schema.int(
    description: 'Expected current whole-policy ordinal.',
  ),
};

List<String> get _routeRollbackRequired => [
  ..._requiredTarget(surfaceScoped: true),
  'environmentSlug',
  'routeId',
  'priorRevisionOrdinal',
  'expectedRevisionOrdinal',
];

/// Review restoration of only the selected original route.
final _reviewRouteRollbackTool = Tool(
  name: 'restage_review_route_rollback',
  description:
      'Return the complete original server review for restoring only one original route. Structured schedules require a whole-policy review.',
  inputSchema: Schema.object(
    properties: _routeRollbackProperties,
    required: _routeRollbackRequired,
    additionalProperties: false,
  ),
);

/// Review and publish restoration of only the selected route.
final _rollbackRouteTool = Tool(
  name: 'restage_rollback_route',
  description:
      'Review and restore only the selected original route with separate explicit measurement warning acknowledgement. Structured schedules require a whole-policy review.',
  inputSchema: Schema.object(
    properties: {
      ..._routeRollbackProperties,
      'operationId': _operationIdProperty,
      'reviewedDigest': _reviewedDigestProperty,
      'acceptFit': acceptFitProperty,
      'reviewOnly': Schema.bool(
        description: 'Return the complete original review without publishing.',
      ),
    },
    required: _routeRollbackRequired,
    additionalProperties: false,
  ),
);

/// Handle `restage_list_routing_audiences`.
Future<CallToolResult> _listRoutingAudiences(
  ToolContext ctx,
  CallToolRequest request,
) => _withRouting(
  ctx,
  request,
  action: 'listing the routing audiences',
  body: (api, target) async {
    final pageSize = _pageSize(request);
    if (pageSize is String) return mcpError(pageSize);
    final page = await api.listAudiences(
      projectSlug: target.projectSlug,
      appSlug: target.appSlug,
      environmentId: target.environmentId,
      organizationId: target.organizationId,
      pageSize: pageSize as int? ?? 50,
      cursor: request.optStr('cursor'),
    );
    return jsonResult(page.toJson());
  },
);

/// Handle `restage_routing_audience_usage`.
Future<CallToolResult> _routingAudienceUsage(
  ToolContext ctx,
  CallToolRequest request,
) => _withRouting(
  ctx,
  request,
  action: 'listing the audience consumers',
  body: (api, target) async {
    final pageSize = _pageSize(request);
    if (pageSize is String) return mcpError(pageSize);
    final usage = await api.listAudienceUsage(
      projectSlug: target.projectSlug,
      appSlug: target.appSlug,
      environmentId: target.environmentId,
      organizationId: target.organizationId,
      audienceRevisionId: request.str('audienceRevisionId'),
      pageSize: pageSize as int? ?? 50,
      cursor: request.optStr('cursor'),
    );
    return jsonResult(usage.toJson());
  },
);

/// Handle `restage_read_routing`.
Future<CallToolResult> _readRouting(ToolContext ctx, CallToolRequest request) =>
    _withRouting(
      ctx,
      request,
      action: 'reading the routing document',
      surfaceScoped: true,
      body: (api, target) async {
        final read = await api.readRouting(
          projectSlug: target.projectSlug,
          appSlug: target.appSlug,
          surfaceType: target.surfaceType!,
          surfaceSlug: target.surfaceSlug!,
          environmentId: target.environmentId,
          organizationId: target.organizationId,
          contractVersion: target.contractVersion,
        );
        return jsonResult(read.toJson());
      },
    );

/// Handle `restage_read_delivery_diagnostics`.
Future<CallToolResult> _readDeliveryDiagnostics(
  ToolContext ctx,
  CallToolRequest request,
) => _withRouting(
  ctx,
  request,
  action: 'reading delivery diagnostics',
  surfaceScoped: true,
  body: (api, target) async {
    final int windowStartDayUtc;
    final int windowEndDayExclusiveUtc;
    try {
      windowStartDayUtc = parseDeliveryDiagnosticsUtcDate(
        request.str('windowStartDateUtc'),
      );
      windowEndDayExclusiveUtc = parseDeliveryDiagnosticsUtcDate(
        request.str('windowEndDateExclusiveUtc'),
      );
      validateDeliveryDiagnosticsUtcWindow(
        windowStartDayUtc: windowStartDayUtc,
        windowEndDayExclusiveUtc: windowEndDayExclusiveUtc,
      );
    } on FormatException catch (error) {
      return mcpError('Invalid UTC date window: ${error.message}');
    }

    final diagnostics = await api.readDeliveryDiagnostics(
      projectSlug: target.projectSlug,
      appSlug: target.appSlug,
      surfaceType: target.surfaceType!,
      surfaceSlug: target.surfaceSlug!,
      environmentId: target.environmentId,
      organizationId: target.organizationId,
      windowStartDayUtc: windowStartDayUtc,
      windowEndDayExclusiveUtc: windowEndDayExclusiveUtc,
      contractVersion: target.contractVersion,
    );
    return jsonResult(diagnostics.toJson());
  },
);

/// Handle `restage_read_delivery_flow`.
Future<CallToolResult> _readDeliveryFlow(
  ToolContext ctx,
  CallToolRequest request,
) => _withRouting(
  ctx,
  request,
  action: 'reading who saw which version',
  surfaceScoped: true,
  body: (api, target) async {
    final int windowStartDayUtc;
    final int windowEndDayExclusiveUtc;
    try {
      windowStartDayUtc = parseDeliveryDiagnosticsUtcDate(
        request.str('windowStartDateUtc'),
      );
      windowEndDayExclusiveUtc = parseDeliveryDiagnosticsUtcDate(
        request.str('windowEndDateExclusiveUtc'),
      );
      validateDeliveryDiagnosticsUtcWindow(
        windowStartDayUtc: windowStartDayUtc,
        windowEndDayExclusiveUtc: windowEndDayExclusiveUtc,
      );
    } on FormatException catch (error) {
      return mcpError('Invalid UTC date window: ${error.message}');
    }

    final flow = await api.readDeliveryFlow(
      projectSlug: target.projectSlug,
      appSlug: target.appSlug,
      surfaceType: target.surfaceType!,
      surfaceSlug: target.surfaceSlug!,
      environmentId: target.environmentId,
      organizationId: target.organizationId,
      windowStartDayUtc: windowStartDayUtc,
      windowEndDayExclusiveUtc: windowEndDayExclusiveUtc,
      contractVersion: target.contractVersion,
    );
    return jsonResult(flow.toJson());
  },
);

/// Handle `restage_read_routing_revision`.
Future<CallToolResult> _readRoutingRevision(
  ToolContext ctx,
  CallToolRequest request,
) => _withRouting(
  ctx,
  request,
  action: 'reading the earlier routing revision',
  surfaceScoped: true,
  body: (api, target) async {
    final ordinal = request.reqInt('revisionOrdinal');
    if (ordinal < 1) {
      return mcpError('revisionOrdinal must be a positive integer.');
    }
    final read = await api.readRoutingRevision(
      projectSlug: target.projectSlug,
      appSlug: target.appSlug,
      surfaceType: target.surfaceType!,
      surfaceSlug: target.surfaceSlug!,
      environmentId: target.environmentId,
      organizationId: target.organizationId,
      revisionOrdinal: ordinal,
      contractVersion: target.contractVersion,
    );
    return jsonResult(read.toJson());
  },
);

/// Handle `restage_preview_routing`.
Future<CallToolResult> _previewRouting(
  ToolContext ctx,
  CallToolRequest request,
) => _withRouting(
  ctx,
  request,
  action: 'simulating the routing policy',
  surfaceScoped: true,
  body: (api, target) async {
    final document = _publicDocument(
      request.optStr('documentBase64'),
      DeliveryPolicySimulationRequestV1.fromCanonicalBytes,
    );
    if (document == null) {
      return mcpError(
        'documentBase64 must be one canonical DeliveryPolicySimulationRequestV1.',
      );
    }
    _requireScope(document.scope, target);
    final preview = await api.previewRouting(
      projectSlug: target.projectSlug,
      appSlug: target.appSlug,
      surfaceType: target.surfaceType!,
      surfaceSlug: target.surfaceSlug!,
      environmentId: target.environmentId,
      organizationId: target.organizationId,
      documentBytes: document.canonicalBytes,
      expectedTarget: target.coordinate,
    );
    return jsonResult(preview.toJson());
  },
);

/// Handle `restage_review_routing`.
Future<CallToolResult> _reviewRouting(
  ToolContext ctx,
  CallToolRequest request,
) => _withRouting(
  ctx,
  request,
  action: 'reviewing the routing policy',
  surfaceScoped: true,
  body: (api, target) async {
    final document = _publicDocument(
      request.optStr('requestBase64'),
      DeliveryPolicyReviewRequestV1.fromCanonicalBytes,
    );
    if (document == null) {
      return mcpError(
        'requestBase64 must be one canonical DeliveryPolicyReviewRequestV1.',
      );
    }
    _requireScope(document.scope, target);
    final review = await api.reviewRouting(
      projectSlug: target.projectSlug,
      appSlug: target.appSlug,
      surfaceType: target.surfaceType!,
      surfaceSlug: target.surfaceSlug!,
      environmentId: target.environmentId,
      organizationId: target.organizationId,
      request: document,
      expectedTarget: target.coordinate,
    );
    return _policyReviewResult(review);
  },
);

/// Handle `restage_publish_routing`.
Future<CallToolResult> _publishRouting(
  ToolContext ctx,
  CallToolRequest request,
) => _withRouting(
  ctx,
  request,
  action: 'publishing the routing policy',
  surfaceScoped: true,
  body: (api, target) async {
    final review = _publicDocument(
      request.optStr('reviewBase64'),
      DeliveryPolicyReviewV1.fromCanonicalBytes,
      maximumBytes: kMaximumRoutingResponseBytes,
    );
    if (review == null) {
      return mcpError(
        'reviewBase64 must be one complete canonical DeliveryPolicyReviewV1.',
      );
    }
    _requireScope(review.scope, target);
    final expected = request.optInt('expectedRevisionOrdinal');
    final expectNone = request.optBool('expectNoRevision') ?? false;
    if ((expected != null &&
            (expected < 1 || expected != review.expectedHeadOrdinal)) ||
        (expectNone &&
            (expected != null || review.expectedHeadOrdinal != null))) {
      return mcpError(
        'The expected-head assertion differs from the original server review.',
      );
    }
    final publish = _reviewedPublish(review, request);
    final result = await api.publishRouting(
      projectSlug: target.projectSlug,
      appSlug: target.appSlug,
      surfaceType: target.surfaceType!,
      surfaceSlug: target.surfaceSlug!,
      environmentId: target.environmentId,
      organizationId: target.organizationId,
      documentBytes: publish.canonicalBytes,
      expectedRevisionOrdinal: review.expectedHeadOrdinal,
      operationId: publish.operationId,
      expectedTarget: target.coordinate,
      acceptFit: request.optBool('acceptFit') ?? false,
    );
    return jsonResult({...result.toJson(), 'operationId': publish.operationId});
  },
);

/// Handle `restage_review_route_rollback`.
Future<CallToolResult> _reviewRouteRollback(
  ToolContext ctx,
  CallToolRequest request,
) => _routeRollback(ctx, request, reviewOnly: true);

/// Handle `restage_rollback_route`.
Future<CallToolResult> _rollbackRoute(
  ToolContext ctx,
  CallToolRequest request,
) => _routeRollback(
  ctx,
  request,
  reviewOnly: request.optBool('reviewOnly') ?? false,
);

Future<CallToolResult> _routeRollback(
  ToolContext ctx,
  CallToolRequest request, {
  required bool reviewOnly,
}) => _withRouting(
  ctx,
  request,
  action: 'reviewing restoration of the original route',
  surfaceScoped: true,
  body: (api, target) async {
    final prior = request.reqInt('priorRevisionOrdinal');
    final expected = request.reqInt('expectedRevisionOrdinal');
    if (prior < 1 || expected < 1) {
      return mcpError('Both revision ordinals must be positive integers.');
    }
    final review = await api.reviewRouteRollback(
      projectSlug: target.projectSlug,
      appSlug: target.appSlug,
      surfaceType: target.surfaceType!,
      surfaceSlug: target.surfaceSlug!,
      environmentId: target.environmentId,
      organizationId: target.organizationId,
      routeId: request.str('routeId'),
      priorRevisionOrdinal: prior,
      expectedRevisionOrdinal: expected,
      contractVersion: target.contractVersion,
      expectedTarget: target.coordinate,
    );
    if (reviewOnly || review.refusalCodes.isNotEmpty) {
      return _policyReviewResult(review);
    }
    final publish = _reviewedPublish(review, request);
    final result = await api.rollbackRoute(
      projectSlug: target.projectSlug,
      appSlug: target.appSlug,
      surfaceType: target.surfaceType!,
      surfaceSlug: target.surfaceSlug!,
      environmentId: target.environmentId,
      organizationId: target.organizationId,
      routeId: request.str('routeId'),
      priorRevisionOrdinal: prior,
      expectedRevisionOrdinal: expected,
      contractVersion: target.contractVersion,
      operationId: publish.operationId,
      reviewedPublishRequest: publish,
      expectedTarget: target.coordinate,
      acceptFit: request.optBool('acceptFit') ?? false,
    );
    return jsonResult({...result.toJson(), 'operationId': publish.operationId});
  },
);

DeliveryPolicyPublishRequestV1 _reviewedPublish(
  DeliveryPolicyReviewV1 review,
  CallToolRequest request,
) {
  try {
    return reviewedDeliveryPolicyPublish(
      review: review,
      reviewedDigest: request.optStr('reviewedDigest'),
      operationId: request.optStr('operationId'),
    );
  } on DeliveryPolicyReviewRequired {
    rethrow;
  } on FormatException catch (error) {
    throw TargetSelectionException(error.message.toString());
  }
}

CallToolResult _policyReviewResult(DeliveryPolicyReviewV1 review) {
  final result = jsonResult({
    'policyReview': review.toJson(),
    'reviewBase64': base64Encode(review.canonicalBytes),
    'reviewDigest': review.digest.hex,
  });
  return CallToolResult(
    isError: review.refusalCodes.isNotEmpty,
    content: result.content,
    structuredContent: result.structuredContent,
  );
}

void _requireScope(DeliveryPolicyScopeV1 scope, _RoutingTarget target) {
  if (target.coordinate == null) {
    throw const TargetSelectionException(
      'Name environmentSlug for a current whole-policy request.',
    );
  }
  try {
    requireSurfaceRoutingScope(
      scope,
      organizationId: target.organizationId,
      environmentId: target.environmentId,
      contractVersion: target.contractVersion,
      expectedTarget: target.coordinate,
    );
  } on FormatException catch (error) {
    throw TargetSelectionException(error.message.toString());
  }
}

T? _publicDocument<T>(
  String? encoded,
  T Function(List<int>) decode, {
  int maximumBytes = kMaximumRoutingRequestBytes,
}) {
  final bytes = _decode(
    encoded,
    'current document',
    maximumBytes: maximumBytes,
  );
  if (bytes == null) return null;
  try {
    return decode(bytes);
  } on CanonicalFormatException {
    return null;
  } on FormatException {
    return null;
  }
}

/// The complete target one routing call carries.
class _RoutingTarget {
  const _RoutingTarget({
    required this.organizationId,
    required this.projectSlug,
    required this.appSlug,
    required this.environmentId,
    required this.surfaceType,
    required this.surfaceSlug,
    required this.contractVersion,
    required this.coordinate,
  });

  final int organizationId;
  final String projectSlug;
  final String appSlug;
  final int environmentId;
  final String? surfaceType;
  final String? surfaceSlug;
  final int? contractVersion;
  final TargetCoordinate? coordinate;
}

/// Run [body] against the routing client, translating routing's own typed
/// refusals before the shared error seam sees them.
Future<CallToolResult> _withRouting(
  ToolContext ctx,
  CallToolRequest request, {
  required String action,
  required Future<CallToolResult> Function(
    SurfaceRoutingApi api,
    _RoutingTarget target,
  )
  body,
  bool surfaceScoped = false,
}) {
  return ctx.authed(action, (api) async {
    final declaredOrganization = request.optInt('organizationId');
    final declaredTarget = request.optInt('environmentTargetId');
    final TargetCoordinate? coordinate;
    final int organization;
    final int environmentId;
    if (request.optStr('environmentSlug') == null &&
        declaredOrganization != null &&
        declaredTarget != null) {
      coordinate = null;
      organization = declaredOrganization;
      environmentId = declaredTarget;
    } else {
      if (request.optStr('environmentSlug') == null) {
        throw const TargetSelectionException(
          'Name environmentSlug, or an exact organizationId and environmentTargetId.',
        );
      }
      coordinate = await exactTargetCoordinate(api, request);
      if (coordinate == null) {
        throw const TargetSelectionException(exactTargetError);
      }
      organization = coordinate.organizationId.value;
      environmentId = coordinate.environmentTargetId.value;
    }
    final target = _RoutingTarget(
      organizationId: organization,
      projectSlug: request.str('projectSlug'),
      appSlug: request.str('appSlug'),
      environmentId: environmentId,
      surfaceType: surfaceScoped ? request.str('surfaceType') : null,
      surfaceSlug: surfaceScoped ? request.str('surfaceSlug') : null,
      contractVersion: surfaceScoped ? request.optInt('contractVersion') : null,
      coordinate: coordinate,
    );
    try {
      return await body(SurfaceRoutingApi(api), target);
    } on RoutingDocumentBytesException catch (error) {
      return mcpError(error.toString());
    } on RestageApiException catch (error) {
      final typed = decodeSurfaceRoutingException(error.body);
      if (typed == null) rethrow;
      return mcpError(_routingRefusal(typed));
    }
  });
}

String _routingRefusal(SurfaceRoutingTypedException typed) => switch (typed) {
  SurfaceRoutingConflict(
    :final expectedRevisionOrdinal,
    :final actualRevisionOrdinal,
  ) =>
    'The stored routing document has moved on. This write expected '
        '${expectedRevisionOrdinal ?? "no revision"} and the stored revision '
        'is ${actualRevisionOrdinal ?? "none"}. Read the document again, '
        'review the difference, and retry.',
  SurfaceRoutingRejected(:final reason) =>
    'The routing service refused the request: $reason.',
};

/// Decode one bounded, canonical base64 argument, or null when it is not one.
Uint8List? _decode(
  String? encoded,
  String role, {
  int maximumBytes = _maximumRoutingBytes,
}) {
  if (encoded == null || encoded.isEmpty) return null;
  if (encoded.length > ((maximumBytes + 2) ~/ 3) * 4) return null;
  final Uint8List bytes;
  try {
    bytes = Uint8List.fromList(base64Decode(encoded));
  } on FormatException {
    return null;
  }
  if (bytes.isEmpty ||
      bytes.length > maximumBytes ||
      base64Encode(bytes) != encoded) {
    return null;
  }
  return bytes;
}

/// Read the page size, returning the value, null for the default, or a
/// message when the supplied value is out of range.
Object? _pageSize(CallToolRequest request) {
  final value = request.optInt('pageSize');
  if (value == null) return null;
  if (value < 1 || value > 200) return 'pageSize must be between 1 and 200.';
  return value;
}

/// Mint a retry identity through the shared CLI operation-id owner.
String newRoutingOperationId() => newOperationId();
