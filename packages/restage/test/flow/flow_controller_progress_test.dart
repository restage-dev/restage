import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_shared/restage_shared.dart';

import 'flow_test_support.dart';

/// A flow advances when the user enters a second screen or a host handler
/// runs; nothing else counts.
void main() {
  setUp(Restage.debugReset);

  late RestageFlowController<FirstRunResult> controller;
  late List<bool> advancedAtFailure;

  Future<void> start(ResolvedFlow flow, {FlowActionRegistry? actions}) async {
    advancedAtFailure = [];
    controller = RestageFlowController<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: StaticFlowResolver(flow),
      actions: actions,
      onEvent: (_) {},
      onComplete: (_) {},
      onUnavailable: (_) => advancedAtFailure.add(controller.hasAdvanced),
    );
    addTearDown(controller.dispose);
    await controller.load();
    await drainFlowTasks();
    expect(controller.hasAdvanced, isFalse);
  }

  test('entering a second screen advances, and going back keeps it', () async {
    await start(resolvedFlow());
    controller.handleEvent('next', null);
    await drainFlowTasks();
    expect(controller.currentScreenId, 'profile');
    expect(controller.hasAdvanced, isTrue);
    controller.back();
    expect(controller.currentScreenId, 'welcome');
    expect(controller.hasAdvanced, isTrue);
  });

  test('a host handler still running when the flow fails advances', () async {
    await start(_actionOnWelcomeFlow(), actions: HoldActionRegistry());
    controller.handleEvent('request', null);
    await drainFlowTasks();
    expect(controller.isBusy, isTrue);
    controller.reportRenderFailure(StateError('render failed'));
    expect(advancedAtFailure, [true]);
  });

  test('a host handler that throws does not advance', () async {
    await start(_actionOnWelcomeFlow(), actions: _ThrowingActionRegistry());
    controller.handleEvent('request', null);
    await drainFlowTasks();
    expect(controller.loadFailed, isTrue);
    expect(advancedAtFailure, [false]);
  });

  test('a host handler that returned advances even when its target fails',
      () async {
    final actions = HoldActionRegistry();
    await start(
      _actionOnWelcomeFlow(target: Uint8List.fromList([1, 2, 3])),
      actions: actions,
    );
    controller.handleEvent('request', null);
    await drainFlowTasks();
    actions.release(result: true);
    await drainFlowTasks();
    await drainFlowTasks();
    expect(controller.loadFailed, isTrue);
    expect(advancedAtFailure, [true]);
  });

  test('a routing state write does not advance', () async {
    await start(_routedFlow());
    expect(controller.currentScreenId, 'welcome');
    controller.reportRenderFailure(StateError('render failed'));
    expect(advancedAtFailure, [false]);
  });
}

/// The first-run flow with a `requestNotifications` action on its welcome
/// screen; a matching result goes to the profile screen, backed by [target].
ResolvedFlow _actionOnWelcomeFlow({Uint8List? target}) {
  final welcome = screenBlob('Welcome', 'request');
  final profile = target ?? screenBlob('Profile', 'finish');
  return resolvedFlow(
    screenBlobs: {'welcome': welcome, 'profile': profile},
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
      screenHashes: {
        'welcome': FlowContentHash.compute(welcome),
        'profile': FlowContentHash.compute(profile),
      },
    ),
  );
}

/// A typed flow whose initial decision writes state, then shows welcome.
ResolvedFlow _routedFlow() {
  final welcome = screenBlob('Welcome', 'next');
  final profile = screenBlob('Profile', 'finish');
  final document = flowDocument(
    screenHashes: {
      'welcome': FlowContentHash.compute(welcome),
      'profile': FlowContentHash.compute(profile),
    },
  ).copyWith(
    schemaVersion: 2,
    deliveryMode: FlowDeliveryMode.typed,
    initial: 'route',
    flowState: const {
      'seen': FlowStateDeclaration(
        type: FlowDataType.bool,
        classification: FlowStateClassification.internal,
      ),
    },
    states: const {
      'route': DecisionFlowState(
        branches: [],
        defaultBranch: FlowBranchTarget(
          target: 'welcome',
          stateWrites: {
            'seen': FlowStateWrite(
              type: FlowDataType.bool,
              value: LiteralFlowValueSource(
                type: FlowDataType.bool,
                value: true,
              ),
            ),
          },
        ),
      ),
      'welcome': ScreenFlowState(
        screen: 'welcome',
        on: {'next': FlowTransition.goto('profile')},
      ),
      'profile': ScreenFlowState(
        screen: 'profile',
        on: {'finish': FlowTransition.goto('done')},
      ),
      'done': EndFlowState(result: <String, Object?>{}),
    },
  );
  return ResolvedFlow(
    document: document,
    screenBlobs: {'welcome': welcome, 'profile': profile},
    cacheHit: false,
  );
}

/// Binds `requestNotifications` to a handler that throws.
final class _ThrowingActionRegistry implements FlowActionRegistry {
  @override
  late final Map<String, FlowActionBinding<dynamic, dynamic>>
      flowActionBindings = {
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
      handler: (_, __) => throw StateError('declined'),
      decodeArgs: (_) {},
      encodeResult: (value) => value,
    ),
  };
}
