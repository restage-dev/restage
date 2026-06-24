import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_shared/restage_shared.dart';

import 'flow_test_support.dart';

/// Emission-point coverage for the onboarding analytics events fired by the
/// flow controller: `onboarding_step_viewed`, `onboarding_skipped`, and
/// `onboarding_permission_response`. The event→envelope conformance is locked
/// separately in `analytics/analytics_event_mapper_test.dart`.
void main() {
  setUp(Restage.debugReset);

  ({
    RestageFlowController<FirstRunResult> controller,
    List<RestageEvent> events
  }) build(ResolvedFlow flow, {FlowActionRegistry? actions}) {
    final events = <RestageEvent>[];
    final controller = RestageFlowController<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: StaticFlowResolver(flow),
      actions: actions,
      onEvent: events.add,
      onComplete: (_) {},
      onUnavailable: (_) {},
    );
    addTearDown(controller.dispose);
    return (controller: controller, events: events);
  }

  group('onboarding_step_viewed', () {
    test('fires for the initial screen, after flow_started', () async {
      final h = build(resolvedFlow());

      await h.controller.load();

      final steps = h.events.whereType<OnboardingStepViewed>().toList();
      expect(steps, hasLength(1));
      expect(steps.single.screenId, 'welcome');
      expect(steps.single.stepIndex, 0);
      expect(steps.single.stepCount, 2);
      expect(steps.single.flowId, 'first_run');
      expect(steps.single.flowVersion, 1);
      expect(steps.single.flowSessionId, isNotNull);

      // flow_started precedes the first step impression.
      final names = h.events.map((e) => e.name).toList();
      expect(
        names.indexOf('flow_started'),
        lessThan(names.indexOf('onboarding_step_viewed')),
      );
    });

    test('forward navigation emits the next step index', () async {
      final h = build(resolvedFlow());

      await h.controller.load();
      h.controller.handleEvent('next', null);
      await drainFlowTasks();

      final steps = h.events.whereType<OnboardingStepViewed>().toList();
      expect(steps.map((e) => e.screenId).toList(), ['welcome', 'profile']);
      expect(steps.map((e) => e.stepIndex).toList(), [0, 1]);
    });

    test('back does not re-fire; a forward re-entry keeps the depth index',
        () async {
      final h = build(threeScreenResolvedFlow());

      await h.controller.load(); // one (0)
      h.controller.handleEvent('next', null); // two (1)
      await drainFlowTasks();
      h.controller.handleEvent('next', null); // three (2)
      await drainFlowTasks();
      h.controller.back(); // -> two, no impression
      h.controller.handleEvent('next', null); // three again (2)
      await drainFlowTasks();

      final steps = h.events.whereType<OnboardingStepViewed>().toList();
      expect(
        steps.map((e) => e.screenId).toList(),
        ['one', 'two', 'three', 'three'],
      );
      expect(steps.map((e) => e.stepIndex).toList(), [0, 1, 2, 2]);
      expect(steps.map((e) => e.stepCount).toList(), everyElement(3));
    });
  });

  group('onboarding_skipped', () {
    test('an authored on[skip] transition emits the skip event', () async {
      final h = build(skipResolvedFlow());

      await h.controller.load();
      h.controller.skip();
      await drainFlowTasks();

      final skips = h.events.whereType<OnboardingSkipped>().toList();
      expect(skips, hasLength(1));
      expect(skips.single.atScreenId, 'welcome');
      expect(skips.single.stepIndex, 0);
      expect(skips.single.flowId, 'first_run');
      expect(skips.single.flowSessionId, isNotNull);
    });

    test('a declared skip custom event emits skipped AND the custom event',
        () async {
      // A declared `skip` custom event requires a non-legacy outbound section.
      final flow = resolvedFlow(
        document: flowDocument(
          outbound: const FlowOutboundDeclarations(
            customEvents: {'skip': FlowOutboundPayloadDeclaration()},
          ),
        ),
      );
      final h = build(flow);

      await h.controller.load();
      expect(h.controller.isUnavailable, isFalse,
          reason: 'flow should load: ${h.events.map((e) => e.name).toList()}');
      h.controller.skip();
      await drainFlowTasks();

      expect(h.events.whereType<OnboardingSkipped>(), hasLength(1));
      expect(
        h.events
            .whereType<FlowCustomEvent>()
            .where((e) => e.eventName == 'skip'),
        hasLength(1),
      );
    });

    test('a skip with no destination emits nothing', () async {
      final h = build(resolvedFlow()); // no on[skip], no skip custom event

      await h.controller.load();
      h.controller.skip();
      await drainFlowTasks();

      expect(h.events.whereType<OnboardingSkipped>(), isEmpty);
    });
  });

  group('onboarding_permission_response', () {
    test('a granted permission action emits the response and advances',
        () async {
      final h = build(
        _permissionFlow(),
        actions: _permissionRegistry(granted: true),
      );

      await h.controller.load();
      h.controller.handleEvent('request', null);
      await drainFlowTasks();

      final perms = h.events.whereType<OnboardingPermissionResponse>().toList();
      expect(perms, hasLength(1));
      expect(perms.single.permission, 'requestNotifications');
      expect(perms.single.granted, isTrue);
      expect(perms.single.flowId, 'first_run');
      expect(perms.single.flowSessionId, isNotNull);
      expect(h.controller.currentScreenId, 'profile');
    });

    test('a declined permission still emits the response and stays put',
        () async {
      final h = build(
        _permissionFlow(),
        actions: _permissionRegistry(granted: false),
      );

      await h.controller.load();
      h.controller.handleEvent('request', null);
      await drainFlowTasks();

      final perms = h.events.whereType<OnboardingPermissionResponse>().toList();
      expect(perms, hasLength(1));
      expect(perms.single.granted, isFalse);
      expect(h.controller.currentScreenId, 'welcome');
    });

    test('a plain bool-result action is not a permission response', () async {
      final h = build(_boolActionFlow(), actions: _boolRegistry(result: true));

      await h.controller.load();
      h.controller.handleEvent('request', null);
      await drainFlowTasks();

      expect(h.events.whereType<OnboardingPermissionResponse>(), isEmpty);
    });
  });

  // A host onEvent listener runs synchronously and may re-enter the controller
  // (e.g. fail it closed via reportRenderFailure). The emission points must
  // re-check liveness so the next controller step never runs on a closed frame.
  group('emission re-entrancy (host fails the flow closed during an event)',
      () {
    test('step_viewed does not fire when flow_started fails the flow closed',
        () async {
      final events = <RestageEvent>[];
      late final RestageFlowController<FirstRunResult> controller;
      controller = RestageFlowController<FirstRunResult>(
        flow: firstRunFlowRef,
        resolver: StaticFlowResolver(resolvedFlow()),
        actions: null,
        onEvent: (event) {
          events.add(event);
          if (event is FlowStarted) {
            controller.reportRenderFailure(StateError('failed on start'));
          }
        },
        onComplete: (_) {},
        onUnavailable: (_) {},
      );
      addTearDown(controller.dispose);

      await controller.load();
      await drainFlowTasks();

      expect(events.whereType<FlowStarted>(), hasLength(1));
      expect(events.whereType<FlowUnavailable>(), hasLength(1));
      // The closed frame must not produce a step impression.
      expect(events.whereType<OnboardingStepViewed>(), isEmpty);
    });

    test(
        'a skip does not run its custom event when the skip fails the flow '
        'closed', () async {
      final flow = resolvedFlow(
        document: flowDocument(
          outbound: const FlowOutboundDeclarations(
            customEvents: {'skip': FlowOutboundPayloadDeclaration()},
          ),
        ),
      );
      final events = <RestageEvent>[];
      late final RestageFlowController<FirstRunResult> controller;
      controller = RestageFlowController<FirstRunResult>(
        flow: firstRunFlowRef,
        resolver: StaticFlowResolver(flow),
        actions: null,
        onEvent: (event) {
          events.add(event);
          if (event is OnboardingSkipped) {
            controller.reportRenderFailure(StateError('failed on skip'));
          }
        },
        onComplete: (_) {},
        onUnavailable: (_) {},
      );
      addTearDown(controller.dispose);

      await controller.load();
      await drainFlowTasks();
      controller.skip();
      await drainFlowTasks();

      expect(events.whereType<OnboardingSkipped>(), hasLength(1));
      // The closed controller must not then emit the declared skip custom event.
      expect(
        events.whereType<FlowCustomEvent>().where((e) => e.eventName == 'skip'),
        isEmpty,
      );
    });
  });
}

const _grantedResultSchema = FlowActionSchema.object({
  'granted': FlowActionSchemaField(
    required: true,
    schema: FlowActionSchema.bool(),
  ),
});

final class _PermissionResult {
  const _PermissionResult({required this.granted});

  final bool granted;
}

/// welcome --(requestNotifications, {granted} result)--> profile.
ResolvedFlow _permissionFlow() {
  return resolvedFlow(
    document: flowDocument(
      legacyTerminalResultPassthrough: true,
      actions: {
        'requestNotifications': const FlowActionContract(
          actionName: 'requestNotifications',
          contractVersion: 1,
          argsSchema: FlowActionSchema.object({}),
          resultSchema: _grantedResultSchema,
          minClient: 3,
          idempotent: false,
        ),
      },
      states: const {
        'welcome': ScreenFlowState(
          screen: 'welcome',
          on: {
            'request': ActionFlowTransition(
              action: 'requestNotifications',
              resultPredicate: ObjectBoolFieldEqualsActionResultPredicate(
                field: 'granted',
                value: true,
              ),
              target: 'profile',
            ),
          },
        ),
        'profile': ScreenFlowState(
          screen: 'profile',
          on: {'finish': FlowTransition.goto('done')},
        ),
        'done': EndFlowState(result: {'completed': true}),
      },
    ),
  );
}

FlowActionRegistry _permissionRegistry({required bool granted}) {
  return TestActionRegistry({
    'requestNotifications': FlowActionBinding<void, _PermissionResult>(
      descriptor: const FlowActionDescriptor<void, _PermissionResult>(
        actionName: 'requestNotifications',
        contractVersion: 1,
        argsSchema: FlowActionSchema.object({}),
        resultSchema: _grantedResultSchema,
        minClient: 3,
        idempotent: false,
      ),
      actionName: 'requestNotifications',
      contractVersion: 1,
      argsSchema: const FlowActionSchema.object({}),
      resultSchema: _grantedResultSchema,
      minClient: 3,
      idempotent: false,
      handler: (_, __) => _PermissionResult(granted: granted),
      decodeArgs: (_) {},
      encodeResult: (result) => {'granted': result.granted},
    ),
  });
}

/// welcome --(requestNotifications, bare bool result)--> profile.
ResolvedFlow _boolActionFlow() {
  return resolvedFlow(
    document: flowDocument(
      legacyTerminalResultPassthrough: true,
      actions: {'requestNotifications': actionContract()},
      states: const {
        'welcome': ScreenFlowState(
          screen: 'welcome',
          on: {
            'request': ActionFlowTransition(
              action: 'requestNotifications',
              resultPredicate: BoolEqualsActionResultPredicate(value: true),
              target: 'profile',
            ),
          },
        ),
        'profile': ScreenFlowState(
          screen: 'profile',
          on: {'finish': FlowTransition.goto('done')},
        ),
        'done': EndFlowState(result: {'completed': true}),
      },
    ),
  );
}

FlowActionRegistry _boolRegistry({required bool result}) {
  return TestActionRegistry({
    'requestNotifications': FlowActionBinding<void, bool>(
      descriptor: const FlowActionDescriptor<void, bool>(
        actionName: 'requestNotifications',
        contractVersion: 1,
        argsSchema: FlowActionSchema.object({}),
        resultSchema: FlowActionSchema.bool(),
        minClient: 3,
        idempotent: false,
      ),
      actionName: 'requestNotifications',
      contractVersion: 1,
      argsSchema: const FlowActionSchema.object({}),
      resultSchema: const FlowActionSchema.bool(),
      minClient: 3,
      idempotent: false,
      handler: (_, __) => result,
      decodeArgs: (_) {},
      encodeResult: (value) => value,
    ),
  });
}
