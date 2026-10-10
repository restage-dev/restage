import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dart_mcp/server.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/api.dart';

import 'api_runner.dart';

/// Largest routing document or preview input this server will accept.
const _maximumRoutingBytes = kMaximumRoutingDocumentBytes;

final _surfaceTypeWireNames = [
  for (final type in SurfaceType.values) type.wireName,
];

final _surfaceTypeProperty = UntitledSingleSelectEnumSchema(
  description:
      'The surface type: one of '
      '${_surfaceTypeWireNames.map((n) => '"$n"').join(', ')}.',
  values: _surfaceTypeWireNames,
);

final _organizationIdProperty = Schema.int(
  description: 'The organization id, from restage_list_organizations.',
);

final _environmentTargetIdProperty = Schema.int(
  description:
      'The exact environment target id, from '
      'restage_list_environment_targets.',
);

final _surfaceSlugProperty = Schema.string(description: 'The surface slug.');

final _projectSlugProperty = Schema.string(description: 'The project slug.');

final _appSlugProperty = Schema.string(description: 'The app slug.');

final _contractVersionProperty = Schema.int(
  description:
      'Optional standalone-screen contract version. Omit for the '
      'non-versioned flow or paywall lineage.',
);

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
  'organizationId': _organizationIdProperty,
  'projectSlug': _projectSlugProperty,
  'appSlug': _appSlugProperty,
  if (surfaceScoped) 'surfaceType': _surfaceTypeProperty,
  if (surfaceScoped) 'surfaceSlug': _surfaceSlugProperty,
  'environmentTargetId': _environmentTargetIdProperty,
  if (surfaceScoped) 'contractVersion': _contractVersionProperty,
};

List<String> _requiredTarget({required bool surfaceScoped}) => [
  'organizationId',
  'projectSlug',
  'appSlug',
  if (surfaceScoped) 'surfaceType',
  if (surfaceScoped) 'surfaceSlug',
  'environmentTargetId',
];

/// List the sealed audience revisions routing rules can reference.
final listRoutingAudiencesTool = Tool(
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
final routingAudienceUsageTool = Tool(
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
final readRoutingTool = Tool(
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
final readDeliveryDiagnosticsTool = Tool(
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

/// Read one earlier revision of the stored routing document.
final readRoutingRevisionTool = Tool(
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

/// Evaluate a routing document against a supplied request context.
final previewRoutingTool = Tool(
  name: 'restage_preview_routing',
  description:
      'Evaluate a routing document against a supplied request context without '
      'publishing it. Read-only: no percentage branch is drawn and no '
      'identity is allocated. Returns every rule with whether it matched and '
      'why, and the selected destination when one matched.',
  inputSchema: Schema.object(
    properties: {
      ..._targetProperties(surfaceScoped: true),
      'documentBase64': Schema.string(
        description:
            'The canonical routing document as standard padded base64.',
      ),
      'schemaBase64': Schema.string(
        description:
            'The canonical context schema revision as standard padded base64.',
      ),
      'requestContextBase64': Schema.string(
        description: 'The canonical request context as standard padded base64.',
      ),
      'audiencesBase64': Schema.list(
        description:
            'One canonical audience revision, as standard padded base64, per '
            'audience the document references.',
        items: Schema.string(),
      ),
      'sdkBuiltInsBase64': Schema.string(
        description:
            'Optional canonical SDK request built-ins as standard padded '
            'base64.',
      ),
    },
    required: [
      ..._requiredTarget(surfaceScoped: true),
      'documentBase64',
      'schemaBase64',
      'requestContextBase64',
      'audiencesBase64',
    ],
    additionalProperties: false,
  ),
);

/// Publish a whole routing document.
final publishRoutingTool = Tool(
  name: 'restage_publish_routing',
  description:
      'Publish a whole routing document, replacing what is stored. The write '
      'carries a compare-and-set precondition: pass the revision ordinal read '
      'with the document, or expectNoRevision for the first publish at a '
      'target. A document authored in Dart and compiled is the input; this '
      'tool carries it and does not author it.',
  inputSchema: Schema.object(
    properties: {
      ..._targetProperties(surfaceScoped: true),
      'documentBase64': Schema.string(
        description:
            'The canonical routing document as standard padded base64.',
      ),
      'expectedRevisionOrdinal': Schema.int(
        description:
            'The revision ordinal this write expects, read with the document. '
            'Omit only when passing expectNoRevision.',
      ),
      'expectNoRevision': Schema.bool(
        description:
            'Pass true to require that no document is stored at the target. '
            'Mutually exclusive with expectedRevisionOrdinal; exactly one is '
            'required.',
      ),
      'operationId': _operationIdProperty,
    },
    required: [..._requiredTarget(surfaceScoped: true), 'documentBase64'],
    additionalProperties: false,
  ),
);

/// Restore one route to an earlier revision.
final rollbackRouteTool = Tool(
  name: 'restage_rollback_route',
  description:
      'Restore one route to the shape it held at an earlier revision, leaving '
      'the rest of the stored document as it is. Carries the same '
      'compare-and-set precondition as a publish.',
  inputSchema: Schema.object(
    properties: {
      ..._targetProperties(surfaceScoped: true),
      'routeId': Schema.string(description: 'The route to restore.'),
      'priorRevisionOrdinal': Schema.int(
        description: 'The revision to restore the route from.',
      ),
      'expectedRevisionOrdinal': Schema.int(
        description: 'The revision ordinal this write expects.',
      ),
      'operationId': _operationIdProperty,
    },
    required: [
      ..._requiredTarget(surfaceScoped: true),
      'routeId',
      'priorRevisionOrdinal',
      'expectedRevisionOrdinal',
    ],
    additionalProperties: false,
  ),
);

/// Handle `restage_list_routing_audiences`.
Future<CallToolResult> handleListRoutingAudiences({
  required CallToolRequest request,
  required FileCredentialStore store,
  http.Client? httpClient,
}) => _withRouting(
  request: request,
  store: store,
  httpClient: httpClient,
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
Future<CallToolResult> handleRoutingAudienceUsage({
  required CallToolRequest request,
  required FileCredentialStore store,
  http.Client? httpClient,
}) => _withRouting(
  request: request,
  store: store,
  httpClient: httpClient,
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
Future<CallToolResult> handleReadRouting({
  required CallToolRequest request,
  required FileCredentialStore store,
  http.Client? httpClient,
}) => _withRouting(
  request: request,
  store: store,
  httpClient: httpClient,
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
Future<CallToolResult> handleReadDeliveryDiagnostics({
  required CallToolRequest request,
  required FileCredentialStore store,
  http.Client? httpClient,
}) => _withRouting(
  request: request,
  store: store,
  httpClient: httpClient,
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

/// Handle `restage_read_routing_revision`.
Future<CallToolResult> handleReadRoutingRevision({
  required CallToolRequest request,
  required FileCredentialStore store,
  http.Client? httpClient,
}) => _withRouting(
  request: request,
  store: store,
  httpClient: httpClient,
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
Future<CallToolResult> handlePreviewRouting({
  required CallToolRequest request,
  required FileCredentialStore store,
  http.Client? httpClient,
}) => _withRouting(
  request: request,
  store: store,
  httpClient: httpClient,
  action: 'previewing the routing document',
  surfaceScoped: true,
  body: (api, target) async {
    final document = _decode(request.optStr('documentBase64'), 'document');
    if (document == null) return mcpError(_bytesError('document'));
    final schema = _decode(request.optStr('schemaBase64'), 'context schema');
    if (schema == null) return mcpError(_bytesError('context schema'));
    final context = _decode(
      request.optStr('requestContextBase64'),
      'request context',
    );
    if (context == null) return mcpError(_bytesError('request context'));

    final rawAudiences =
        (request.arguments?['audiencesBase64'] as List<Object?>?) ??
        const <Object?>[];
    final audiences = <Uint8List>[];
    for (final raw in rawAudiences) {
      final decoded = _decode(raw is String ? raw : null, 'audience');
      if (decoded == null) return mcpError(_bytesError('audience'));
      audiences.add(decoded);
    }

    Uint8List? builtIns;
    final rawBuiltIns = request.optStr('sdkBuiltInsBase64');
    if (rawBuiltIns != null && rawBuiltIns.isNotEmpty) {
      builtIns = _decode(rawBuiltIns, 'SDK built-ins');
      if (builtIns == null) return mcpError(_bytesError('SDK built-ins'));
    }

    final preview = await api.previewRouting(
      projectSlug: target.projectSlug,
      appSlug: target.appSlug,
      surfaceType: target.surfaceType!,
      surfaceSlug: target.surfaceSlug!,
      environmentId: target.environmentId,
      organizationId: target.organizationId,
      documentBytes: document,
      schemaBytes: schema,
      requestContextBytes: context,
      audienceBytes: audiences,
      sdkBuiltInsBytes: builtIns,
    );
    return jsonResult(preview.toJson());
  },
);

/// Handle `restage_publish_routing`.
Future<CallToolResult> handlePublishRouting({
  required CallToolRequest request,
  required FileCredentialStore store,
  http.Client? httpClient,
}) => _withRouting(
  request: request,
  store: store,
  httpClient: httpClient,
  action: 'publishing the routing document',
  surfaceScoped: true,
  body: (api, target) async {
    final expected = request.optInt('expectedRevisionOrdinal');
    final expectNone = request.optBool('expectNoRevision') ?? false;
    if (expectNone == (expected != null)) {
      return mcpError(
        'Pass exactly one of expectedRevisionOrdinal or expectNoRevision.',
      );
    }
    if (expected != null && expected < 1) {
      return mcpError('expectedRevisionOrdinal must be a positive integer.');
    }

    final document = _decode(request.optStr('documentBase64'), 'document');
    if (document == null) return mcpError(_bytesError('document'));

    final operationId = _operationId(request);
    if (operationId == null) return mcpError(_operationIdError);

    final result = await api.publishRouting(
      projectSlug: target.projectSlug,
      appSlug: target.appSlug,
      surfaceType: target.surfaceType!,
      surfaceSlug: target.surfaceSlug!,
      environmentId: target.environmentId,
      organizationId: target.organizationId,
      documentBytes: document,
      expectedRevisionOrdinal: expected,
      operationId: operationId,
    );
    return jsonResult({...result.toJson(), 'operationId': operationId});
  },
);

/// Handle `restage_rollback_route`.
Future<CallToolResult> handleRollbackRoute({
  required CallToolRequest request,
  required FileCredentialStore store,
  http.Client? httpClient,
}) => _withRouting(
  request: request,
  store: store,
  httpClient: httpClient,
  action: 'rolling the route back',
  surfaceScoped: true,
  body: (api, target) async {
    final prior = request.reqInt('priorRevisionOrdinal');
    final expected = request.reqInt('expectedRevisionOrdinal');
    if (prior < 1 || expected < 1) {
      return mcpError('Both revision ordinals must be positive integers.');
    }

    final operationId = _operationId(request);
    if (operationId == null) return mcpError(_operationIdError);

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
      operationId: operationId,
    );
    return jsonResult({...result.toJson(), 'operationId': operationId});
  },
);

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
  });

  final int organizationId;
  final String projectSlug;
  final String appSlug;
  final int environmentId;
  final String? surfaceType;
  final String? surfaceSlug;
  final int? contractVersion;
}

/// Run [body] against the routing client, translating routing's own typed
/// refusals before the shared error seam sees them.
Future<CallToolResult> _withRouting({
  required CallToolRequest request,
  required FileCredentialStore store,
  required http.Client? httpClient,
  required String action,
  required Future<CallToolResult> Function(
    SurfaceRoutingApi api,
    _RoutingTarget target,
  )
  body,
  bool surfaceScoped = false,
}) {
  final target = _RoutingTarget(
    organizationId: request.reqInt('organizationId'),
    projectSlug: request.str('projectSlug'),
    appSlug: request.str('appSlug'),
    environmentId: request.reqInt('environmentTargetId'),
    surfaceType: surfaceScoped ? request.str('surfaceType') : null,
    surfaceSlug: surfaceScoped ? request.str('surfaceSlug') : null,
    contractVersion: surfaceScoped ? request.optInt('contractVersion') : null,
  );

  return withApi(
    store: store,
    httpClient: httpClient,
    action: action,
    surfaceNoun: target.surfaceType ?? 'surface',
    body: (api) async {
      try {
        return await body(SurfaceRoutingApi(api), target);
      } on RoutingDocumentBytesException catch (error) {
        return mcpError(error.toString());
      } on RestageApiException catch (error) {
        final typed = decodeSurfaceRoutingException(error.body);
        if (typed == null) rethrow;
        return mcpError(_routingRefusal(typed));
      }
    },
  );
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

String _bytesError(String role) =>
    'The $role must be one non-empty, bounded, standard padded base64 value '
    'of at most $_maximumRoutingBytes bytes.';

const _operationIdError = 'operationId must be a canonical version 4 UUID.';

/// Decode one bounded, canonical base64 argument, or null when it is not one.
Uint8List? _decode(String? encoded, String role) {
  if (encoded == null || encoded.isEmpty) return null;
  if (encoded.length > ((_maximumRoutingBytes + 2) ~/ 3) * 4) return null;
  final Uint8List bytes;
  try {
    bytes = Uint8List.fromList(base64Decode(encoded));
  } on FormatException {
    return null;
  }
  if (bytes.isEmpty ||
      bytes.length > _maximumRoutingBytes ||
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

final _operationIdShape = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

final _random = Random.secure();

/// Read the retry identity, minting one when omitted. Null when the supplied
/// value is not a canonical version 4 UUID.
String? _operationId(CallToolRequest request) {
  final supplied = request.optStr('operationId');
  if (supplied == null || supplied.isEmpty) return newRoutingOperationId();
  return _operationIdShape.hasMatch(supplied) ? supplied : null;
}

/// Mint one retry identity as a canonical version 4 UUID.
String newRoutingOperationId() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
