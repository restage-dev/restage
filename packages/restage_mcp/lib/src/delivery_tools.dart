import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_mcp/server.dart';
import 'package:restage_cli/api.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    show
        CanonicalValue,
        CanonicalFormatException,
        DeliveryPolicyPublishResultV1,
        DeliveryPolicyReviewV1;

import 'api_runner.dart';
import 'tool_support.dart';

/// Delivery reads and reviewed mutations through the public typed API.
List<ToolEntry> deliveryTools(ToolContext ctx) => [
  for (final operation in DeliveryOperation.values)
    if (!operation.name.startsWith('placementSample'))
      if (operation.liveGuarded)
        liveGuarded(ctx, (
          _tool(operation),
          (request) => _handle(ctx, operation, request),
        ))
      else
        (_tool(operation), (request) => _handle(ctx, operation, request)),
];

Tool _tool(DeliveryOperation operation) => Tool(
  name: operation.mcpName,
  description: switch (operation) {
    DeliveryOperation.placementList =>
      'Read the target placement directory and preserve its exact opaque continuation and reporting cutoff.',
    DeliveryOperation.placementRead =>
      'Read one exact namespace-qualified placement with authoritative surface and experiment availability.',
    DeliveryOperation.placementObservedHistory =>
      'Read successful authenticated first paints over explicit UTC bounds with the stated source coverage.',
    DeliveryOperation.placementSimulate =>
      'Probe both placement selection and subsequent surface delivery for an explicit bounded set of keys. This read never enrolls or reports observations.',
    DeliveryOperation.deliveryPolicyRead =>
      'Read the complete current policy for an exact surface or placement scope and family.',
    DeliveryOperation.deliveryPolicyTimeline =>
      'Read user-local scheduled starts and ordered rules from the current serving authority.',
    DeliveryOperation.deliveryPolicyHistory =>
      'Read immutable complete policy revisions and their exact continuation.',
    DeliveryOperation.deliveryPolicyFit =>
      'Read authoritative fit for an exact policy scope or exact pushed publication reference.',
    DeliveryOperation.deliveryPolicySimulate =>
      'Simulate one policy with explicit local time, optional identity, and canonical public built-ins.',
    DeliveryOperation.deliveryPolicyReview =>
      'Freeze one complete plan and its source impact review under the exact expected head.',
    DeliveryOperation.deliveryPolicyPublish =>
      'Publish only a server-issued review reference, exact measurement warning acknowledgement, and operation identity. A complete plan is not accepted here.',
    DeliveryOperation.deliveryPolicyUndoReview =>
      'Review restoration of an immutable complete plan. Publish that server review separately.',
    _ => throw ArgumentError.value(operation, 'operation'),
  },
  inputSchema: Schema.object(
    properties: {
      ...exactTargetProperties(),
      'requestJson': Schema.string(
        description:
            'Explicit canonical JSON for the public ${operation.id} request. Its complete target, root, key, and family must agree with the authenticated target.',
      ),
    },
    required: [
      'projectSlug',
      'appSlug',
      'organizationId',
      'environmentSlug',
      'runtimePlane',
      'requestJson',
    ],
    additionalProperties: false,
  ),
);

Future<CallToolResult> _handle(
  ToolContext ctx,
  DeliveryOperation operation,
  CallToolRequest request,
) => ctx.authed(operation.cliPath, (api) async {
  try {
    final json = request.str('requestJson');
    if (json.length > kMaximumPlacementManagementRequestBytes) {
      throw const FormatException(
        'The delivery request exceeds its byte limit.',
      );
    }
    final bytes = Uint8List.fromList(utf8.encode(json));
    if (bytes.length > kMaximumPlacementManagementRequestBytes) {
      throw const FormatException(
        'The delivery request exceeds its byte limit.',
      );
    }
    final decoded = operation.decodeRequest(bytes) as CanonicalValue;
    final target = await exactTargetCoordinate(api, request);
    if (target == null) return mcpError(exactTargetError);
    final result = await DeliveryManagementApi(api).invoke(
      operation: operation,
      projectSlug: request.str('projectSlug'),
      appSlug: request.str('appSlug'),
      target: target,
      request: decoded,
    );
    final refused = switch (result) {
      DeliveryPolicyPublishResultV1 value =>
        value.outcome == 'conflict' || value.outcome == 'refused',
      DeliveryPolicyReviewV1 value => value.refusalCodes.isNotEmpty,
      _ => false,
    };
    return CallToolResult(
      content: [TextContent(text: utf8.decode(result.canonicalBytes))],
      isError: refused ? true : null,
    );
  } on DeliveryManagementResponseException catch (error) {
    return mcpError(error.toString());
  } on SurfaceRoutingTypedException catch (error) {
    return mcpError(error.toString());
  } on CanonicalFormatException catch (error) {
    return mcpError(error.toString());
  } on FormatException catch (error) {
    return mcpError(error.message);
  }
});
