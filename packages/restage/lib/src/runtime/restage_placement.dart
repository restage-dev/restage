import 'package:flutter/widgets.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';

import '../flow/flow_descriptors.dart';
import '../flow/flow_seed.dart';
import '../flow/restage_surface_flow.dart';
import '../events/restage_event.dart' show RestageEvent;
import '../flow/system_back_policy.dart';
import '../refresh/surface_refresh_trigger.dart';
import 'placement_event_scope.dart';
import 'placement_mount.dart';
import 'restage.dart' show Restage;
import 'restage_paywall.dart';

/// A placement mounted through the SDK's existing surface hosts.
///
/// Prefer generated `*Surface(...)` widgets for typed bindings, registration,
/// compiled fallbacks and implicit placements.
///
/// `onEvent` receives the events this placement fires; they also flow
/// through [Restage.events] for app-wide listeners. A flow placement's
/// `surfaceType` selects the host its content needs, and only content of
/// that type is delivered to it.
final class RestagePlacement extends StatelessWidget
    implements RestagePlacementMount {
  factory RestagePlacement(
          {Key? key,
          required String id,
          required WidgetBuilder fallback,
          SurfaceHostContractV1? contract,
          Map<String, Object?>? context,
          WidgetBuilder? loadingBuilder,
          void Function(RestageEvent event)? onEvent}) =>
      RestagePlacement._single(
          key: key,
          placement: PlacementKeyV1.named(slug: id),
          fallback: fallback,
          contract: contract,
          context: context,
          loadingBuilder: loadingBuilder,
          onEvent: onEvent);

  factory RestagePlacement.forSurface(
          {Key? key,
          required Surface surfaceType,
          required String surfaceId,
          DeliveryFamilySelectorV1 family =
              const DeliveryFamilySelectorV1.general(),
          required WidgetBuilder fallback,
          SurfaceHostContractV1? contract,
          Map<String, Object?>? context,
          WidgetBuilder? loadingBuilder,
          void Function(RestageEvent event)? onEvent}) =>
      RestagePlacement._single(
          key: key,
          placement: PlacementKeyV1.generatedDefault(
              surfaceType: DeliverySurfaceTypeId(surfaceType.wireName),
              slug: surfaceId),
          defaultSurface: DeliverySurfaceLocatorV1(
              surfaceType: DeliverySurfaceTypeId(surfaceType.wireName),
              slug: surfaceId,
              family: family),
          fallback: fallback,
          contract: contract,
          context: context,
          loadingBuilder: loadingBuilder,
          onEvent: onEvent);

  /// A named flow placement that hosts only `surfaceType` content; content of
  /// any other surface type is never delivered to it.
  factory RestagePlacement.flow(
          {Key? key,
          required String id,
          Surface surfaceType = Surface.onboarding,
          required WidgetBuilder fallback,
          required SurfaceHostContractV1 contract,
          FlowSeed? initialState,
          FlowActionRegistry? actions,
          Set<String> installedSignalNames = const {},
          ValueChanged<Map<String, Object?>>? onComplete,
          Map<String, Object?>? context,
          WidgetBuilder? loadingBuilder,
          SystemBackPolicy systemBack = SystemBackPolicy.popHost,
          Set<SurfaceRefreshTrigger>? liveRefresh,
          void Function(RestageEvent event)? onEvent}) =>
      RestagePlacement._flow(
          key: key,
          onEvent: onEvent,
          placement: PlacementKeyV1.named(slug: id),
          surface: surfaceType,
          fallback: fallback,
          contract: contract,
          initialState: initialState,
          actions: actions,
          installedSignalNames: installedSignalNames,
          onComplete: onComplete,
          context: context,
          loadingBuilder: loadingBuilder,
          systemBack: systemBack,
          liveRefresh: liveRefresh);

  factory RestagePlacement.flowForSurface(
          {Key? key,
          required Surface surfaceType,
          required String surfaceId,
          required WidgetBuilder fallback,
          required SurfaceHostContractV1 contract,
          FlowSeed? initialState,
          FlowActionRegistry? actions,
          Set<String> installedSignalNames = const {},
          ValueChanged<Map<String, Object?>>? onComplete,
          Map<String, Object?>? context,
          WidgetBuilder? loadingBuilder,
          SystemBackPolicy systemBack = SystemBackPolicy.popHost,
          Set<SurfaceRefreshTrigger>? liveRefresh,
          void Function(RestageEvent event)? onEvent}) =>
      RestagePlacement._flow(
          key: key,
          onEvent: onEvent,
          placement: PlacementKeyV1.generatedDefault(
              surfaceType: DeliverySurfaceTypeId(surfaceType.wireName),
              slug: surfaceId),
          defaultSurface: DeliverySurfaceLocatorV1(
              surfaceType: DeliverySurfaceTypeId(surfaceType.wireName),
              slug: surfaceId,
              family: const DeliveryFamilySelectorV1.general()),
          surface: surfaceType,
          fallback: fallback,
          contract: contract,
          initialState: initialState,
          actions: actions,
          installedSignalNames: installedSignalNames,
          onComplete: onComplete,
          context: context,
          loadingBuilder: loadingBuilder,
          systemBack: systemBack,
          liveRefresh: liveRefresh);

  const RestagePlacement._(
      {super.key, required this.placementBinding, required Widget host})
      : _host = host;
  @override
  final PlacementMountBinding placementBinding;
  final Widget _host;

  static RestagePlacement _single(
      {Key? key,
      required PlacementKeyV1 placement,
      DeliverySurfaceLocatorV1? defaultSurface,
      required WidgetBuilder fallback,
      SurfaceHostContractV1? contract,
      Map<String, Object?>? context,
      WidgetBuilder? loadingBuilder,
      void Function(RestageEvent event)? onEvent}) {
    contract ??= SurfaceHostContractV1(
        hosting: const SurfaceHostingV1(
            contentKind: SurfaceContentKindV1.single,
            presentation: SurfacePresentationV1.inline),
        providedContext: const SurfaceScreenHostDataSchema.empty(),
        handledEvents: SurfaceScreenEventSchema(events: const []));
    if (contract.hosting.contentKind != SurfaceContentKindV1.single ||
        contract.handledEvents.events.isNotEmpty) {
      throw ArgumentError.value(contract, 'contract',
          'A single placement must have no handled events.');
    }
    final binding = PlacementMountBinding.request(
        mount: PlacementMountRequestV1(
            key: placement,
            hostContractHash: contract.contentHash,
            defaultSurface: defaultSurface),
        hostContract: contract);
    return RestagePlacement._(
        key: key,
        placementBinding: binding,
        host: RestagePaywall(
            id: defaultSurface?.slug ?? placement.slug,
            placementBinding: binding,
            fallbackBuilder: fallback,
            loadingBuilder: loadingBuilder,
            onEvent: onEvent,
            context: context));
  }

  static RestagePlacement _flow(
      {Key? key,
      required PlacementKeyV1 placement,
      DeliverySurfaceLocatorV1? defaultSurface,
      required Surface surface,
      required WidgetBuilder fallback,
      required SurfaceHostContractV1 contract,
      FlowSeed? initialState,
      FlowActionRegistry? actions,
      required Set<String> installedSignalNames,
      ValueChanged<Map<String, Object?>>? onComplete,
      Map<String, Object?>? context,
      WidgetBuilder? loadingBuilder,
      required SystemBackPolicy systemBack,
      Set<SurfaceRefreshTrigger>? liveRefresh,
      void Function(RestageEvent event)? onEvent}) {
    final boundary = contract.flowBoundary;
    if (contract.hosting.contentKind != SurfaceContentKindV1.flow ||
        boundary == null ||
        contract.handledEvents.events.isNotEmpty) {
      throw ArgumentError.value(
          contract, 'contract', 'A flow host boundary is required.');
    }
    _validateFlowInputs(boundary, initialState, actions, installedSignalNames);
    final binding = PlacementMountBinding.request(
        mount: PlacementMountRequestV1(
            key: placement,
            hostContractHash: contract.contentHash,
            defaultSurface: defaultSurface,
            surfaceType: DeliverySurfaceTypeId(surface.wireName)),
        hostContract: contract);
    if (surface == Surface.paywall) {
      // Paywall flows use the paywall host, which delivers their events.
      if (onComplete != null ||
          actions != null ||
          systemBack != SystemBackPolicy.popHost) {
        throw ArgumentError(
            'A paywall flow takes no onComplete, actions or systemBack.');
      }
      return RestagePlacement._(
          key: key,
          placementBinding: binding,
          host: RestagePaywall(
              id: defaultSurface?.slug ?? placement.slug,
              placementBinding: binding,
              fallbackBuilder: fallback,
              loadingBuilder: loadingBuilder,
              liveRefresh: liveRefresh,
              onEvent: onEvent,
              context: context));
    }
    final selector = SurfaceFlowRef<Map<String, Object?>>(
        id: defaultSurface?.slug ?? placement.slug,
        // No original publication is claimed by a low-level mount.
        version: 0,
        minClient: 0,
        surface: surface,
        deliveryMode: boundary.deliveryMode,
        decodeResult: (result) => Map.unmodifiable({
              for (final entry in result.entries)
                if (boundary.outbound.terminalResult.containsKey(entry.key))
                  entry.key: entry.value
            }));
    final host = RestageFlowGraph<Map<String, Object?>>(
        flow: selector,
        placementBinding: binding,
        initialState: initialState,
        actions: actions,
        installedSignalNames: installedSignalNames,
        onComplete: onComplete,
        unavailable: FlowUnavailablePolicy.fallback(
            builder: (context, _) => fallback(context)),
        context: context,
        loadingBuilder: loadingBuilder,
        systemBack: systemBack,
        liveRefresh: liveRefresh);
    return RestagePlacement._(
        key: key,
        placementBinding: binding,
        host: onEvent == null
            ? host
            : PlacementEventScope(onEvent: onEvent, child: host));
  }

  @override
  Widget build(BuildContext context) => _host;
}

void _validateFlowInputs(FlowHostBoundaryV1 boundary, FlowSeed? seed,
    FlowActionRegistry? actions, Set<String> signals) {
  final bindings = actions?.flowActionBindings ??
      const <String, FlowActionBinding<dynamic, dynamic>>{};
  for (final entry in boundary.actions.entries) {
    final binding = bindings[entry.key];
    final expected = entry.value;
    if (binding == null ||
        binding.actionName != expected.actionName ||
        binding.contractVersion != expected.contractVersion ||
        binding.argsSchemaHash !=
            FlowActionSchema.hashFor(
                contractKind: 'args', schema: expected.argsSchema) ||
        binding.resultSchemaHash !=
            FlowActionSchema.hashFor(
                contractKind: 'result', schema: expected.resultSchema) ||
        binding.minClient < expected.minClient ||
        binding.idempotent != expected.idempotent) {
      throw ArgumentError.value(actions, 'actions',
          'The installed action does not implement the declared boundary.');
    }
  }
  final installed = {
    ...signals,
    if (actions is FlowSignalRegistry)
      ...(actions as FlowSignalRegistry).installedSignalNames
  };
  // Typed flows emit their declared events without an installed set.
  if (boundary.deliveryMode == FlowDeliveryMode.general &&
      !installed.containsAll(boundary.signals)) {
    throw ArgumentError.value(
        signals, 'installedSignalNames', 'A declared signal is not installed.');
  }
  for (final entry
      in (seed?.toFlowState() ?? const <String, Object?>{}).entries) {
    final type = boundary.hostSeedableState[entry.key]?.type;
    final valid = switch (type) {
      FlowDataType.bool => entry.value is bool,
      FlowDataType.int => entry.value is int,
      FlowDataType.string => entry.value is String,
      null => false,
    };
    if (!valid) {
      throw ArgumentError.value(
          seed, 'initialState', 'The seed does not fit the declared boundary.');
    }
  }
}
