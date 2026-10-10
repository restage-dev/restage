import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_mcp/server.dart';
import 'package:restage_cli/api.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    as measurement;

import 'api_runner.dart';
import 'tool_support.dart';

const _canonicalMutationRequestError =
    'canonicalRequestBase64 must contain one non-empty, bounded, canonical '
    'base64-encoded mutation request.';
const _canonicalMutationTargetMismatchError =
    'The canonical request target does not match the declared target.';
const _canonicalMutationResponseError =
    'The service returned an invalid canonical mutation response.';

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
      ...exactTargetProperties(),
    },
    required: ['canonicalRequestBase64', ...exactTargetRequired],
    additionalProperties: false,
  ),
);

/// Apply one exact canonical request through the shared authenticated API.
///
/// This transport only verifies the JSON-safe base64 envelope and uses the
/// public schema decoder to reject noncanonical request bytes before any
/// network work. [ProgrammaticMutationApi] owns the complete coordinate
/// binding immediately before its single mutation route.
Future<CallToolResult> handleCanonicalMutation(
  ToolContext ctx,
  CallToolRequest request,
) {
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

  return ctx.authed('applying the canonical mutation', (api) async {
    final target = await exactTargetCoordinate(api, request);
    if (target == null) return mcpError(exactTargetError);

    try {
      final response = await ProgrammaticMutationApi(api).mutateCanonicalBytes(
        projectSlug: request.str('projectSlug'),
        appSlug: request.str('appSlug'),
        environmentSlug: request.str('environmentSlug'),
        organizationId: request.reqInt('organizationId'),
        appId: target.appId.value,
        namedEnvironmentId: target.namedEnvironmentId.value,
        environmentTargetId: target.environmentTargetId.value,
        runtimePlane: runtimePlane,
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
  });
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

CallToolResult _canonicalMutationSuccess(
  ProgrammaticMutationResponseWireV1 response,
  measurement.TargetCoordinate target,
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
        'organizationId': target.organizationId.value,
        'appId': target.appId.value,
        'namedEnvironmentId': target.namedEnvironmentId.value,
        'environmentTargetId': target.environmentTargetId.value,
        'runtimePlane': target.runtimePlane.wireName,
      },
    },
  );
}
