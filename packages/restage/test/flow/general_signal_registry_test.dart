import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/flow/flow_resolver.dart' show ActiveArmFlowResolver;
import 'package:restage/src/runtime/builtin_catalog_capabilities.dart';
import 'package:restage_shared/restage_shared.dart';

import 'flow_test_support.dart' show screenBlob;

/// The signal-name registry union: a generated flow action registry that also
/// implements [FlowSignalRegistry] installs its custom-event names by
/// construction, so a general surface admits and emits them with NO
/// host-supplied `installedSignalNames`. A plain [FlowActionRegistry] that does
/// not implement the sibling interface contributes no names (fail-closed).
const int _installed = RestageBuiltInCatalogCapabilities.currentVersion;

const flowRef = OnboardingFlowRef<Map<String, Object?>>(
  id: 'first_run',
  version: 1,
  minClient: _installed,
  surface: Surface.general,
  decodeResult: _identity,
);

void main() {
  setUp(Restage.debugReset);

  test(
      'a registry that implements FlowSignalRegistry installs its signal names '
      '— a general surface admits + emits them with NO host set', () async {
    final events = <RestageEvent>[];
    final welcome = screenBlob('Welcome', 'next');
    final doc = _generalDoc(
      welcome,
      outbound: const FlowOutboundDeclarations(
        customEvents: {'submitAnswer': FlowOutboundPayloadDeclaration()},
      ),
    );
    final controller = RestageFlowController<Map<String, Object?>>(
      flow: flowRef,
      resolver: _FakeActiveResolver(_resolved(doc, welcome)),
      // The registry carries the signal name; NO host installedSignalNames set.
      actions: const _SignalOnlyRegistry({'submitAnswer'}),
      onEvent: events.add,
      onComplete: (_) {},
      onUnavailable: (_) {},
    );
    addTearDown(controller.dispose);

    await controller.load();
    expect(controller.isUnavailable, isFalse);
    controller.handleEvent('submitAnswer', const <String, Object?>{});
    await Future<void>.delayed(Duration.zero);

    expect(
      events
          .whereType<FlowCustomEvent>()
          .where((e) => e.eventName == 'submitAnswer'),
      hasLength(1),
    );
  });

  test(
      'a plain FlowActionRegistry (no FlowSignalRegistry) contributes no signal '
      'names — an undeclared-handler general surface still fails closed',
      () async {
    FlowUnavailableError? error;
    final welcome = screenBlob('Welcome', 'next');
    final doc = _generalDoc(
      welcome,
      outbound: const FlowOutboundDeclarations(
        customEvents: {'submitAnswer': FlowOutboundPayloadDeclaration()},
      ),
    );
    final controller = RestageFlowController<Map<String, Object?>>(
      flow: flowRef,
      resolver: _FakeActiveResolver(_resolved(doc, welcome)),
      // A registry that does NOT implement FlowSignalRegistry, and no host set.
      actions: const _ActionOnlyRegistry(),
      installedSignalNames: const {},
      onEvent: (_) {},
      onComplete: (_) {},
      onUnavailable: (e) => error = e,
    );
    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.isUnavailable, isTrue);
    expect(error?.reason, 'signal_not_installed');
  });

  test(
      'the host set and the registry set UNION — a name from either source is '
      'installed', () async {
    final events = <RestageEvent>[];
    final welcome = screenBlob('Welcome', 'next');
    final doc = _generalDoc(
      welcome,
      outbound: const FlowOutboundDeclarations(
        customEvents: {
          'fromRegistry': FlowOutboundPayloadDeclaration(),
          'fromHost': FlowOutboundPayloadDeclaration(),
        },
      ),
    );
    final controller = RestageFlowController<Map<String, Object?>>(
      flow: flowRef,
      resolver: _FakeActiveResolver(_resolved(doc, welcome)),
      actions: const _SignalOnlyRegistry({'fromRegistry'}),
      installedSignalNames: const {'fromHost'},
      onEvent: events.add,
      onComplete: (_) {},
      onUnavailable: (_) {},
    );
    addTearDown(controller.dispose);

    await controller.load();
    expect(controller.isUnavailable, isFalse);
    controller.handleEvent('fromRegistry', const <String, Object?>{});
    controller.handleEvent('fromHost', const <String, Object?>{});
    await Future<void>.delayed(Duration.zero);

    final names =
        events.whereType<FlowCustomEvent>().map((e) => e.eventName).toSet();
    expect(names, containsAll(<String>['fromRegistry', 'fromHost']));
  });
}

Map<String, Object?> _identity(Map<String, Object?> result) => result;

/// A registry that installs signal names but binds no host actions — the
/// zero-action general case (both channels installed by construction).
final class _SignalOnlyRegistry
    implements FlowActionRegistry, FlowSignalRegistry {
  const _SignalOnlyRegistry(this.installedSignalNames);

  @override
  final Set<String> installedSignalNames;

  @override
  Map<String, FlowActionBinding<dynamic, dynamic>> get flowActionBindings =>
      const {};
}

/// A plain action registry that does NOT implement FlowSignalRegistry.
final class _ActionOnlyRegistry implements FlowActionRegistry {
  const _ActionOnlyRegistry();

  @override
  Map<String, FlowActionBinding<dynamic, dynamic>> get flowActionBindings =>
      const {};
}

FlowDocument _generalDoc(
  Uint8List screenBytes, {
  FlowOutboundDeclarations outbound = const FlowOutboundDeclarations(),
}) {
  return FlowDocument(
    flow: 'first_run',
    version: 1,
    schemaVersion: 1,
    minClient: _installed,
    initial: 'welcome',
    outbound: outbound,
    screenArtifacts: {
      'welcome': ScreenArtifact(
        path: 'welcome.rfw',
        version: 1,
        schemaVersion: 1,
        minClient: _installed,
        contentHash: FlowContentHash.compute(screenBytes),
      ),
    },
    states: const {
      'welcome': ScreenFlowState(
        screen: 'welcome',
        on: {'next': FlowTransition.goto('done')},
      ),
      'done': EndFlowState(result: {'completed': true}),
    },
    deliveryMode: FlowDeliveryMode.general,
  );
}

ResolvedFlow _resolved(FlowDocument document, Uint8List screenBytes) {
  return ResolvedFlow(
    document: document,
    screenBlobs: {'welcome': screenBytes},
    cacheHit: false,
  );
}

final class _FakeActiveResolver implements FlowResolver, ActiveArmFlowResolver {
  const _FakeActiveResolver(this._flow);

  final ResolvedFlow _flow;

  @override
  bool get activeArmEnabled => true;

  @override
  Future<ResolvedFlow> resolveActiveRoot<R>(OnboardingFlowRef<R> flow) async =>
      _flow;

  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) async => _flow;
}
