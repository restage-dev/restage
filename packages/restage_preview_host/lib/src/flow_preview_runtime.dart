import 'package:restage/restage.dart';
import 'package:restage_shared/restage_shared.dart'
    show
        FlowActionContract,
        FlowBoolActionSchema,
        FlowDocument,
        FlowDoubleActionSchema,
        FlowEnumActionSchema,
        FlowIntActionSchema,
        FlowListActionSchema,
        FlowNullableActionSchema,
        FlowObjectActionSchema,
        FlowStringActionSchema,
        FlowSurfacePayload;

/// Builds a flow controller over an already-resolved [payload], for a preview
/// that has no app behind it.
///
/// The controller is the SDK's own: the same document interpretation, state
/// writes, action gating and outbound filtering a device runs. Only the two
/// ends are stubbed — the resolver hands back the payload the dashboard already
/// holds, and every host action is granted.
RestageFlowController<Map<String, Object?>> buildPreviewFlowController({
  required FlowSurfacePayload payload,
  required Surface surface,
  required void Function(RestageEvent event) onEvent,
  required void Function(Map<String, Object?> result) onComplete,
  required void Function(FlowUnavailableError error) onUnavailable,
}) {
  final document = payload.flowDocument;
  final registry = _GrantingActionRegistry(document);
  return RestageFlowController<Map<String, Object?>>(
    flow: SurfaceFlowRef<Map<String, Object?>>(
      id: document.flow,
      version: document.version,
      minClient: _clientFloor(document),
      surface: surface,
      decodeResult: (result) => result,
      deliveryMode: document.deliveryMode,
    ),
    resolver: _PreviewFlowResolver(payload),
    actions: registry,
    installedSignalNames: registry.installedSignalNames,
    onEvent: onEvent,
    onComplete: onComplete,
    onUnavailable: onUnavailable,
  );
}

/// The client version the preview claims. The runtime refuses a document (or a
/// screen) that asks for more than the host supports, and this host is the
/// document's own reader, so it claims exactly what the document needs.
int _clientFloor(FlowDocument document) {
  var floor = document.minClient;
  for (final artifact in document.screenArtifacts.values) {
    if (artifact.minClient > floor) floor = artifact.minClient;
  }
  return floor;
}

/// Serves the payload the dashboard already loaded.
class _PreviewFlowResolver implements FlowResolver {
  _PreviewFlowResolver(this._payload);

  final FlowSurfacePayload _payload;

  @override
  Future<ResolvedFlow> resolve<R>(SurfaceFlowRef<R> flow) async => ResolvedFlow(
        document: _payload.flowDocument,
        screenBlobs: _payload.screenBlobs,
        cacheHit: false,
      );
}

/// Grants every host action the document declares.
///
/// Bindings are built from the document's own contracts, so the runtime's
/// contract match is satisfied by construction. A permission gate such as
/// "advance once reminders are granted" therefore passes, which is what a
/// reader walking the flow wants to see.
class _GrantingActionRegistry
    implements FlowActionRegistry, FlowSignalRegistry {
  _GrantingActionRegistry(FlowDocument document)
      : flowActionBindings =
            Map<String, FlowActionBinding<dynamic, dynamic>>.unmodifiable(
          <String, FlowActionBinding<dynamic, dynamic>>{
            for (final entry in document.actions.entries)
              entry.key: _grantingBinding(entry.value),
          },
        ),
        installedSignalNames =
            Set<String>.unmodifiable(document.outbound.customEvents.keys);

  @override
  final Map<String, FlowActionBinding<dynamic, dynamic>> flowActionBindings;

  @override
  final Set<String> installedSignalNames;
}

FlowActionBinding<Object?, Object?> _grantingBinding(
  FlowActionContract contract,
) {
  return FlowActionBinding<Object?, Object?>(
    actionName: contract.actionName,
    contractVersion: contract.contractVersion,
    argsSchema: contract.argsSchema,
    resultSchema: contract.resultSchema,
    minClient: contract.minClient,
    idempotent: contract.idempotent,
    handler: (args, context) => grantingActionResult(contract.resultSchema),
    decodeArgs: (value) => value,
    encodeResult: (result) => result,
  );
}

/// The most permissive value [schema] admits: booleans true, collections empty,
/// optional fields omitted.
Object? grantingActionResult(FlowActionSchema schema) {
  return switch (schema) {
    FlowObjectActionSchema(:final fields) => <String, Object?>{
        for (final entry in fields.entries)
          if (entry.value.required)
            entry.key: grantingActionResult(entry.value.schema),
      },
    FlowBoolActionSchema() => true,
    FlowIntActionSchema() => 1,
    FlowDoubleActionSchema() => 1.0,
    FlowStringActionSchema() => '',
    FlowEnumActionSchema(:final values) => values.isEmpty ? null : values.first,
    FlowListActionSchema() => const <Object?>[],
    FlowNullableActionSchema(:final child) => grantingActionResult(child),
  };
}
