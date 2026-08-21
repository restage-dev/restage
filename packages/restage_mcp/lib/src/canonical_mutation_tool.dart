import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_mcp/server.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/api.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    as measurement;

import 'api_runner.dart';

const _canonicalMutationRequestError =
    'canonicalRequestBase64 must contain one non-empty, bounded, canonical '
    'base64-encoded mutation request.';
const _canonicalMutationTargetError =
    'The declared target does not resolve to one exact authorized target.';
const _canonicalMutationTargetMismatchError =
    'The canonical request target does not match the declared target.';
const _canonicalMutationResponseError =
    'The service returned an invalid canonical mutation response.';

const _runtimePlaneValues = ['sandbox', 'live'];

/// The one route-neutral canonical mutation transport exposed through MCP.
final canonicalMutationTool = Tool(
  name: 'restage_apply_canonical_mutation',
  description:
      'Apply one exact canonical measurement or experiment mutation. The '
      'request is standard padded base64 over the canonical request bytes. '
      'Its complete target must match the declared organization, project, app, '
      'environment target, and runtime plane.',
  inputSchema: Schema.object(
    properties: {
      'canonicalRequestBase64': Schema.string(
        description:
            'One exact canonical mutation request as standard padded base64.',
      ),
      'organizationId': Schema.int(description: 'The organization id.'),
      'projectSlug': Schema.string(description: 'The project slug.'),
      'appSlug': Schema.string(description: 'The app slug.'),
      'environmentSlug': Schema.string(description: 'The environment slug.'),
      'environmentTargetId': Schema.int(
        description: 'The exact environment target id.',
      ),
      'runtimePlane': UntitledSingleSelectEnumSchema(
        description: 'The target runtime plane: sandbox or live.',
        values: _runtimePlaneValues,
      ),
    },
    required: [
      'canonicalRequestBase64',
      'organizationId',
      'projectSlug',
      'appSlug',
      'environmentSlug',
      'environmentTargetId',
      'runtimePlane',
    ],
    additionalProperties: false,
  ),
);

/// Apply one exact canonical request through the shared authenticated API.
///
/// This transport only verifies the JSON-safe base64 envelope and uses the
/// public schema decoder to reject noncanonical request bytes before any
/// network work. [ProgrammaticMutationApi] owns the complete coordinate
/// binding immediately before its single mutation route.
Future<CallToolResult> handleCanonicalMutation({
  required CallToolRequest request,
  required FileCredentialStore store,
  http.Client? httpClient,
}) {
  final bytes = _decodeCanonicalRequestBase64(
    request.str('canonicalRequestBase64'),
  );
  if (bytes == null) {
    return Future.value(mcpError(_canonicalMutationRequestError));
  }

  final RuntimePlane runtimePlane;
  try {
    runtimePlane = RuntimePlane.fromWireName(request.str('runtimePlane'));
  } on FormatException {
    return Future.value(mcpError('The declared runtime plane is invalid.'));
  }

  final organizationId = request.reqInt('organizationId');
  final projectSlug = request.str('projectSlug');
  final appSlug = request.str('appSlug');
  final environmentSlug = request.str('environmentSlug');
  final environmentTargetId = request.reqInt('environmentTargetId');

  return withApi(
    store: store,
    httpClient: httpClient,
    action: 'applying the canonical mutation',
    surfaceNoun: 'surface',
    body: (api) async {
      final target = await _resolveExactTarget(
        api: api,
        organizationId: organizationId,
        projectSlug: projectSlug,
        appSlug: appSlug,
        environmentSlug: environmentSlug,
        environmentTargetId: environmentTargetId,
        runtimePlane: runtimePlane,
      );
      if (target == null) return mcpError(_canonicalMutationTargetError);

      try {
        final response = await ProgrammaticMutationApi(api)
            .mutateCanonicalBytes(
              projectSlug: projectSlug,
              appSlug: appSlug,
              environmentSlug: environmentSlug,
              organizationId: organizationId,
              appId: target.appId,
              namedEnvironmentId: target.namedEnvironmentId,
              environmentTargetId: target.environmentTargetId,
              runtimePlane: target.runtimePlane,
              canonicalRequestBytes: bytes,
            );
        return _canonicalMutationSuccess(response, target);
      } on ProgrammaticMutationTargetMismatchException {
        return mcpError(_canonicalMutationTargetMismatchError);
      } on measurement.CanonicalFormatException {
        return mcpError(_canonicalMutationResponseError);
      } on FormatException {
        return mcpError(_canonicalMutationResponseError);
      }
    },
  );
}

Uint8List? _decodeCanonicalRequestBase64(String encoded) {
  final maximumEncodedLength =
      ((kMaximumProgrammaticMutationWireBytes + 2) ~/ 3) * 4;
  if (encoded.isEmpty || encoded.length > maximumEncodedLength) return null;

  late final Uint8List bytes;
  try {
    bytes = Uint8List.fromList(base64Decode(encoded));
  } on FormatException {
    return null;
  }
  if (bytes.isEmpty ||
      bytes.length > kMaximumProgrammaticMutationWireBytes ||
      base64Encode(bytes) != encoded) {
    return null;
  }

  try {
    ProgrammaticMutationRequestWireV1.fromCanonicalBytes(bytes);
  } on measurement.CanonicalFormatException {
    return null;
  }
  return bytes;
}

Future<_CanonicalMutationTarget?> _resolveExactTarget({
  required RestageApi api,
  required int organizationId,
  required String projectSlug,
  required String appSlug,
  required String environmentSlug,
  required int environmentTargetId,
  required RuntimePlane runtimePlane,
}) async {
  final discovery = DiscoveryApi(api);
  final apps = await discovery.listApps(
    organizationId: organizationId,
    projectSlug: projectSlug,
  );
  final matchingApps = [
    for (final app in apps)
      if (app.slug == appSlug && app.appId != null) app,
  ];
  if (matchingApps.length != 1) return null;
  final appId = matchingApps.single.appId!;

  final targets = await discovery.listEnvironmentTargets(
    organizationId: organizationId,
    projectSlug: projectSlug,
    appSlug: appSlug,
    appId: appId,
    runtimePlane: runtimePlane,
  );
  final matchingTargets = [
    for (final target in targets)
      if (target.environmentTargetId == environmentTargetId &&
          target.environmentSlug == environmentSlug &&
          target.runtimePlane == runtimePlane)
        target,
  ];
  if (matchingTargets.length != 1) return null;
  final target = matchingTargets.single;
  return _CanonicalMutationTarget(
    organizationId: organizationId,
    appId: appId,
    namedEnvironmentId: target.namedEnvironmentId,
    environmentTargetId: target.environmentTargetId,
    runtimePlane: target.runtimePlane,
  );
}

CallToolResult _canonicalMutationSuccess(
  ProgrammaticMutationResponseWireV1 response,
  _CanonicalMutationTarget target,
) {
  final bytes = response.canonicalBytes;
  return CallToolResult(
    content: [
      TextContent(
        text: 'Canonical mutation response received (${bytes.length} bytes).',
      ),
    ],
    structuredContent: {
      'canonicalResponseBase64': base64Encode(bytes),
      'responseKind': response.resultKind,
      'byteLength': bytes.length,
      'target': {
        'organizationId': target.organizationId,
        'appId': target.appId,
        'namedEnvironmentId': target.namedEnvironmentId,
        'environmentTargetId': target.environmentTargetId,
        'runtimePlane': target.runtimePlane.wireName,
      },
    },
  );
}

final class _CanonicalMutationTarget {
  const _CanonicalMutationTarget({
    required this.organizationId,
    required this.appId,
    required this.namedEnvironmentId,
    required this.environmentTargetId,
    required this.runtimePlane,
  });

  final int organizationId;
  final int appId;
  final int namedEnvironmentId;
  final int environmentTargetId;
  final RuntimePlane runtimePlane;
}
