import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_mcp/server.dart';
import 'package:restage_cli/api.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    as measurement;

import 'api_runner.dart';

const _activationCommandError =
    'canonicalCommandBase64 must contain one non-empty, bounded, canonical '
    'base64-encoded activation command.';
const _activationResultError =
    'The authority returned an invalid canonical activation result.';
const _activationTargetError =
    'The canonical activation command does not match the configured '
    'activation target.';
const _activationTransportError =
    'The configured activation transport is unavailable.';

/// The injected-only MCP route for one exact experiment activation command.
final experimentActivationTool = Tool(
  name: 'restage_activate_experiment',
  description:
      'Apply one exact canonical experiment activation command. The command is '
      'standard padded base64 over canonical command bytes.',
  inputSchema: Schema.object(
    properties: {
      'canonicalCommandBase64': Schema.string(
        description:
            'One exact canonical activation command as standard padded base64.',
      ),
    },
    required: ['canonicalCommandBase64'],
    additionalProperties: false,
  ),
);

/// Applies an exact activation command through one injected authority API.
///
/// This handler has no credential, discovery, target, endpoint, or legacy
/// mutation dependency. Its embedding server supplies the authority boundary.
Future<CallToolResult> handleExperimentActivation({
  required CallToolRequest request,
  required ExperimentActivationApi api,
}) async {
  final bytes = _decodeCanonicalCommand(request.str('canonicalCommandBase64'));
  if (bytes == null) return mcpError(_activationCommandError);

  try {
    final result = await api.executeCanonicalBytes(bytes);
    return CallToolResult(
      content: [
        TextContent(
          text:
              'Canonical activation result received '
              '(${result.canonicalBytes.length} bytes).',
        ),
      ],
      structuredContent: {
        'canonicalResultBase64': base64Encode(result.canonicalBytes),
        'resultKind': result.outcome,
        'byteLength': result.canonicalBytes.length,
      },
    );
  } on ExperimentActivationRouteProfileMismatchException {
    return mcpError(_activationTargetError);
  } on ExperimentActivationTransportUnavailableException {
    return mcpError(_activationTransportError);
  } on measurement.CanonicalFormatException {
    return mcpError(_activationResultError);
  }
}

Uint8List? _decodeCanonicalCommand(String encoded) {
  final maximumEncodedLength =
      ((kMaximumExperimentActivationWireBytes + 2) ~/ 3) * 4;
  if (encoded.isEmpty || encoded.length > maximumEncodedLength) return null;

  late final Uint8List bytes;
  try {
    bytes = Uint8List.fromList(base64Decode(encoded));
  } on FormatException {
    return null;
  }
  if (bytes.isEmpty ||
      bytes.length > kMaximumExperimentActivationWireBytes ||
      base64Encode(bytes) != encoded) {
    return null;
  }
  try {
    ExperimentActivationCommandWireV1.fromCanonicalBytes(bytes);
  } on measurement.CanonicalFormatException {
    return null;
  }
  return bytes;
}
