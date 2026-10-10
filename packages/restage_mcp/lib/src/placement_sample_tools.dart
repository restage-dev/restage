import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_mcp/server.dart';
import 'package:restage_cli/api.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    show CanonicalFormatException, CanonicalValue;

import 'api_runner.dart';
import 'tool_support.dart';

/// Private sample tools over explicitly supplied capture and PNG content.
List<ToolEntry> placementSampleTools(ToolContext ctx) => [
  for (final operation in DeliveryOperation.values)
    if (operation.name.startsWith('placementSample'))
      if (operation.liveGuarded)
        liveGuarded(ctx, (
          _sampleTool(operation),
          (request) => _handle(ctx, operation, request),
        ))
      else
        (_sampleTool(operation), (request) => _handle(ctx, operation, request)),
];

Tool _sampleTool(DeliveryOperation operation) {
  final properties = <String, Schema>{...exactTargetProperties()};
  final required = <String>[
    'projectSlug',
    'appSlug',
    'organizationId',
    'environmentSlug',
    'runtimePlane',
  ];
  void text(String key, String help, {bool optional = false}) {
    properties[key] = Schema.string(description: help);
    if (!optional) required.add(key);
  }

  switch (operation) {
    case DeliveryOperation.placementSampleImport:
      text(
        'captureJson',
        'Explicit canonical target-free capture JSON with its full offline build contract.',
      );
      text(
        'pngBase64',
        'PNG bytes from the same frame as canonical padded base64.',
      );
      text(
        'screenLabel',
        'Optional screen label bound in the local draft.',
        optional: true,
      );
    case DeliveryOperation.placementSamplePrepare:
      text(
        'draftJson',
        'Explicit canonical target-bound draft returned by sample import.',
      );
      text(
        'pngBase64',
        'Current PNG bytes explicitly supplied as canonical padded base64.',
      );
      text(
        'reviewedDigest',
        'Exact digest explicitly approved after reviewing this image and manifest.',
      );
      text(
        'operationId',
        'Canonical lowercase UUIDv4 for this review operation.',
      );
    case DeliveryOperation.placementSampleStore:
      text('ticketJson', 'Exact canonical server-issued upload ticket JSON.');
      text(
        'pngBase64',
        'Current PNG bytes matching the reviewed ticket as canonical padded base64.',
      );
    case DeliveryOperation.placementSampleBind:
      text('storedJson', 'Exact canonical stored-sample result JSON.');
      text(
        'operationId',
        'Canonical lowercase UUIDv4 for this binding operation.',
      );
      properties['expectedBindingRevision'] = Schema.int(
        description:
            'Expected complete frame binding revision; omit only for a new association.',
        minimum: 1,
      );
    case DeliveryOperation.placementSampleRead ||
        DeliveryOperation.placementSampleReadImage:
      text('sampleId', 'Exact private sample UUIDv4.');
    case DeliveryOperation.placementSampleDelete:
      text('sampleId', 'Exact private sample UUIDv4.');
      text(
        'operationId',
        'Canonical lowercase UUIDv4 for this deletion operation.',
      );
      properties['expectedBindingRevision'] = Schema.int(
        description: 'Expected current complete frame binding revision.',
        minimum: 1,
      );
    default:
      throw ArgumentError.value(operation, 'operation');
  }
  return Tool(
    name: operation.mcpName,
    description: switch (operation) {
      DeliveryOperation.placementSampleImport =>
        'Validate supplied capture and PNG content and bind a local draft to the authenticated target. Returns a review digest without upload or binding.',
      DeliveryOperation.placementSamplePrepare =>
        'Prepare a private upload for the explicitly reviewed image and target-bound manifest.',
      DeliveryOperation.placementSampleStore =>
        'Store supplied PNG bytes that match the explicitly reviewed upload ticket.',
      DeliveryOperation.placementSampleBind =>
        'Bind every occurrence in a stored frame atomically at an expected binding revision.',
      DeliveryOperation.placementSampleRead =>
        'Read authorized sample metadata and truthful availability without creating a binding.',
      DeliveryOperation.placementSampleReadImage =>
        'Read an authorized private sample PNG as canonical padded base64.',
      DeliveryOperation.placementSampleDelete =>
        'Remove a private sample image and its current frame association.',
      _ => throw ArgumentError.value(operation, 'operation'),
    },
    inputSchema: Schema.object(
      properties: properties,
      required: required,
      additionalProperties: false,
    ),
  );
}

Uint8List _content(CallToolRequest request, String key) {
  final value = request.str(key);
  if (value.length > maximumPlacementSampleDocumentBytes) {
    throw const FormatException(
      'The supplied sample JSON exceeds its byte limit.',
    );
  }
  final bytes = Uint8List.fromList(utf8.encode(value));
  if (bytes.length > maximumPlacementSampleDocumentBytes) {
    throw const FormatException(
      'The supplied sample JSON exceeds its byte limit.',
    );
  }
  return bytes;
}

Uint8List _png(CallToolRequest request) => decodeByteDataWire(
  "decode('${request.str('pngBase64')}', 'base64')",
  maximumBytes: placementScreenSampleMaxBytes,
  malformed: (detail) => FormatException('The supplied PNG $detail.'),
);

Future<CallToolResult> _handle(
  ToolContext ctx,
  DeliveryOperation operation,
  CallToolRequest request,
) => ctx.authed(operation.cliPath, (api) async {
  try {
    final target = await exactTargetCoordinate(api, request);
    if (target == null) return mcpError(exactTargetError);
    final samples = PlacementSampleApi(api);
    final project = request.str('projectSlug');
    final app = request.str('appSlug');
    final CanonicalValue result;
    switch (operation) {
      case DeliveryOperation.placementSampleImport:
        result = importPlacementSample(
          captureBytes: _content(request, 'captureJson'),
          pngBytes: _png(request),
          target: target,
          screenLabel: request.optStr('screenLabel'),
        );
      case DeliveryOperation.placementSamplePrepare:
        final draft = PlacementSampleDraftV1.fromCanonicalBytes(
          _content(request, 'draftJson'),
        );
        result = await samples.prepare(
          projectSlug: project,
          appSlug: app,
          target: target,
          request: PlacementSamplePrepareV1(
            manifest: draft.manifest,
            buildContract: draft.buildContract,
            reviewedDigest: request.str('reviewedDigest'),
            operationId: request.str('operationId'),
          ),
          pngBytes: _png(request),
        );
      case DeliveryOperation.placementSampleStore:
        result = await samples.store(
          projectSlug: project,
          appSlug: app,
          target: target,
          ticket: PlacementSampleUploadTicketV1.fromCanonicalBytes(
            _content(request, 'ticketJson'),
          ),
          pngBytes: _png(request),
        );
      case DeliveryOperation.placementSampleBind:
        final stored = PlacementSampleStoredV1.fromCanonicalBytes(
          _content(request, 'storedJson'),
        );
        final ref = await samples.bind(
          projectSlug: project,
          appSlug: app,
          target: target,
          request: PlacementSampleBindV1(
            sampleId: stored.sampleId,
            operationId: request.str('operationId'),
            expectedBindingRevision: request.optInt('expectedBindingRevision'),
          ),
        );
        if (ref.manifestDigest != stored.manifestDigest ||
            ref.imageSha256 != stored.imageSha256) {
          throw const PlacementSampleResponseException();
        }
        result = ref;
      case DeliveryOperation.placementSampleRead:
        result = await samples.read(
          projectSlug: project,
          appSlug: app,
          target: target,
          request: PlacementSampleReadV1(sampleId: request.str('sampleId')),
        );
      case DeliveryOperation.placementSampleReadImage:
        final bytes = await samples.readImage(
          projectSlug: project,
          appSlug: app,
          target: target,
          request: PlacementSampleReadV1(sampleId: request.str('sampleId')),
        );
        return jsonResult({
          'sampleId': request.str('sampleId'),
          'pngBase64': base64Encode(bytes),
        });
      case DeliveryOperation.placementSampleDelete:
        result = await samples.delete(
          projectSlug: project,
          appSlug: app,
          target: target,
          request: PlacementSampleDeleteV1(
            sampleId: request.str('sampleId'),
            operationId: request.str('operationId'),
            expectedBindingRevision: request.optInt('expectedBindingRevision'),
          ),
        );
      default:
        throw ArgumentError.value(operation, 'operation');
    }
    return CallToolResult(
      content: [TextContent(text: utf8.decode(result.canonicalBytes))],
    );
  } on PlacementSampleException catch (error) {
    return mcpError(error.toString());
  } on PlacementSampleResponseException catch (error) {
    return mcpError(error.toString());
  } on CanonicalFormatException catch (error) {
    return mcpError(error.toString());
  } on FormatException catch (error) {
    return mcpError(error.message);
  }
});
