import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
// `package:matcher` (via `flutter_test`) also exports `allOf`, used below as a
// matcher; hide the flow-authoring `allOf` here since this file only needs the
// `state(...)` predicate sugar.
import 'package:restage/restage.dart' hide allOf;
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart';

void main() {
  setUp(Restage.debugReset);

  group('RestageFlowController chrome-availability getters', () {
    test('isComplete is false until the flow reaches an end state', () async {
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: _StaticFlowResolver(_resolvedFlow()),
        actions: null,
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (_) {},
      );

      await controller.load();
      expect(controller.isComplete, isFalse);

      controller.handleEvent('next', const <String, Object?>{});
      await Future<void>.delayed(Duration.zero);
      expect(controller.isComplete, isFalse);

      controller.handleEvent('finish', const <String, Object?>{});
      await Future<void>.delayed(Duration.zero);
      expect(controller.isComplete, isTrue);
    });

    test('isBusy is true while a state change is in flight, false at rest',
        () async {
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: _StaticFlowResolver(_resolvedFlow()),
        actions: null,
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (_) {},
      );

      await controller.load();
      expect(controller.isBusy, isFalse);

      // _goTo flips _isChangingState synchronously before its first await, so a
      // goto event makes the controller observably busy until the change drains.
      controller.handleEvent('next', const <String, Object?>{});
      expect(controller.isBusy, isTrue);

      await Future<void>.delayed(Duration.zero);
      expect(controller.isBusy, isFalse);
    });

    test('isBusy is true while a host action is in flight', () async {
      final pending = Completer<bool>();
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: _StaticFlowResolver(_actionFromProfileFlow()),
        actions: _MatchingActionRegistry(handler: (_, __) => pending.future),
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (_) {},
      );
      addTearDown(controller.dispose);

      await controller.load();
      controller.handleEvent('next', const <String, Object?>{});
      await _drainFlowTasks();
      expect(controller.currentScreenId, 'profile');
      expect(controller.isBusy, isFalse);

      // Start the action; it never completes within this turn — isChangingState
      // is false here, so this exercises the _activeActionToken arm of isBusy.
      controller.handleEvent('request', const <String, Object?>{});
      await _drainFlowTasks();
      expect(controller.isBusy, isTrue);

      pending.complete(false);
      await _drainFlowTasks();
      expect(controller.isBusy, isFalse);
    });
  });

  group('RestageFlowController action-start notify re-entrancy', () {
    test(
        'a listener that fails the controller closed during the action-start '
        'notify prevents the host action from running', () async {
      var handlerInvoked = false;
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: _StaticFlowResolver(_actionFromProfileFlow()),
        actions: _MatchingActionRegistry(handler: (_, __) {
          handlerInvoked = true;
          return true;
        }),
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (_) {},
      );
      addTearDown(controller.dispose);

      await controller.load();
      controller.handleEvent('next', const <String, Object?>{});
      await _drainFlowTasks();
      expect(controller.currentScreenId, 'profile');

      // A host listener fails the controller closed the instant the action goes
      // in flight (the action-start notify) — e.g. a render failure observed
      // elsewhere. `reportRenderFailure` is not gated by the action token, so it
      // takes effect mid-`_invokeAction`; the host action must NOT then run on
      // the now-failed-closed controller.
      var failed = false;
      controller.addListener(() {
        if (controller.isBusy && !failed) {
          failed = true;
          controller.reportRenderFailure(
            StateError('render failed during the action-start notify'),
          );
        }
      });

      controller.handleEvent('request', const <String, Object?>{});
      await _drainFlowTasks();

      expect(
        handlerInvoked,
        isFalse,
        reason: 'the host action must not fire after the controller failed '
            'closed during the action-start notify',
      );
      expect(controller.isUnavailable, isTrue);
    });
  });

  group('RestageFlowController', () {
    test('loads the initial screen blob', () async {
      final resolver = _StaticFlowResolver(_resolvedFlow());
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: null,
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (_) {},
      );

      await controller.load();

      expect(controller.currentScreenId, 'welcome');
      expect(controller.currentLibrary, isNotNull);
    });

    test('transitions only from the current state', () async {
      final resolver = _StaticFlowResolver(_resolvedFlow());
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: null,
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (_) {},
      );

      await controller.load();
      controller.handleEvent('finish', const <String, Object?>{});
      await Future<void>.delayed(Duration.zero);

      expect(controller.currentScreenId, 'welcome');

      controller.handleEvent('next', const <String, Object?>{});
      await Future<void>.delayed(Duration.zero);

      expect(controller.currentScreenId, 'profile');
    });

    test('gates events while changing state', () async {
      _FirstRunResult? completed;
      final resolver = _StaticFlowResolver(_resolvedFlow());
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: null,
        onEvent: (_) {},
        onComplete: (result) => completed = result,
        onUnavailable: (_) {},
      );

      await controller.load();

      controller.handleEvent('next', const <String, Object?>{});
      controller.handleEvent('finish', const <String, Object?>{});
      await Future<void>.delayed(Duration.zero);

      expect(controller.currentScreenId, 'profile');
      expect(completed, isNull);
    });

    test('terminal event calls onComplete with decoded typed result', () async {
      _FirstRunResult? completed;
      final resolver = _StaticFlowResolver(_resolvedFlow());
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: null,
        onEvent: (_) {},
        onComplete: (result) => completed = result,
        onUnavailable: (_) {},
      );

      await controller.load();
      controller.handleEvent('next', const <String, Object?>{});
      await Future<void>.delayed(Duration.zero);
      controller.handleEvent('finish', const <String, Object?>{});
      await Future<void>.delayed(Duration.zero);

      expect(completed, isA<_FirstRunResult>());
      expect(completed?.completed, isTrue);
    });

    test('terminal result filtering removes unallowlisted keys before decode',
        () async {
      _FirstRunResult? completed;
      FlowUnavailableError? unavailable;
      final resolver = _StaticFlowResolver(
        _resolvedFlow(
          document: _document(
            flowState: const {
              'completed': FlowStateDeclaration(
                type: FlowDataType.bool,
                classification: FlowStateClassification.exportable,
              ),
              'secret': FlowStateDeclaration(
                type: FlowDataType.string,
                classification: FlowStateClassification.internal,
              ),
            },
            outbound: const FlowOutboundDeclarations(
              terminalResult: FlowOutboundPayloadDeclaration(
                fields: {
                  'completed': FlowOutboundField(
                    type: FlowDataType.bool,
                    ref: StateFlowOutboundRef(key: 'completed'),
                  ),
                },
              ),
            ),
            states: const {
              'welcome': ScreenFlowState(
                screen: 'welcome',
                on: {'finish': FlowTransition.goto('done')},
              ),
              'done': EndFlowState(
                result: {
                  'completed': true,
                  'secret': 'do-not-emit',
                },
              ),
            },
          ),
        ),
      );
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: null,
        onEvent: (_) {},
        onComplete: (result) => completed = result,
        onUnavailable: (error) => unavailable = error,
      );

      await controller.load();
      controller.handleEvent('finish', const <String, Object?>{});
      await Future<void>.delayed(Duration.zero);

      expect(unavailable, isNull);
      expect(completed?.completed, isTrue);
    });

    test('terminal result is denied by default for declared-output documents',
        () async {
      _FirstRunResult? completed;
      FlowUnavailableError? unavailable;
      final resolver = _StaticFlowResolver(
        _resolvedFlow(
          document: _document(
            flowState: const {
              'completed': FlowStateDeclaration(
                type: FlowDataType.bool,
                classification: FlowStateClassification.exportable,
              ),
            },
            states: const {
              'welcome': ScreenFlowState(
                screen: 'welcome',
                on: {'finish': FlowTransition.goto('done')},
              ),
              'done': EndFlowState(result: {'completed': true}),
            },
          ),
        ),
      );
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: null,
        onEvent: (_) {},
        onComplete: (result) => completed = result,
        onUnavailable: (error) => unavailable = error,
      );

      await controller.load();
      controller.handleEvent('finish', const <String, Object?>{});
      await Future<void>.delayed(Duration.zero);

      expect(completed, isNull);
      expect(unavailable?.reason, 'result_decode_failed');
    });

    test('explicit empty outbound denies terminal result by default', () async {
      _FirstRunResult? completed;
      FlowUnavailableError? unavailable;
      final resolver = _StaticFlowResolver(
        _resolvedFlow(
          document: _document(
            outbound: const FlowOutboundDeclarations(),
            states: const {
              'welcome': ScreenFlowState(
                screen: 'welcome',
                on: {'finish': FlowTransition.goto('done')},
              ),
              'done': EndFlowState(result: {'completed': true}),
            },
          ),
        ),
      );
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: null,
        onEvent: (_) {},
        onComplete: (result) => completed = result,
        onUnavailable: (error) => unavailable = error,
      );

      await controller.load();
      controller.handleEvent('finish', const <String, Object?>{});
      await Future<void>.delayed(Duration.zero);

      expect(completed, isNull);
      expect(unavailable?.reason, 'result_decode_failed');
    });

    test('terminal completion is delivered once', () async {
      var completions = 0;
      final resolver = _StaticFlowResolver(
        _resolvedFlow(
          states: const {
            'welcome': ScreenFlowState(
              screen: 'welcome',
              on: {'finish': FlowTransition.goto('done')},
            ),
            'done': EndFlowState(result: {'completed': true}),
          },
        ),
      );
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: null,
        onEvent: (_) {},
        onComplete: (_) => completions += 1,
        onUnavailable: (_) {},
      );

      await controller.load();
      controller.handleEvent('finish', const <String, Object?>{});
      await Future<void>.delayed(Duration.zero);
      controller.handleEvent('finish', const <String, Object?>{});
      await Future<void>.delayed(Duration.zero);

      expect(completions, 1);
    });

    test('action transition invokes handler and follows true predicate',
        () async {
      _FirstRunResult? completed;
      FlowUnavailableError? unavailable;
      FlowActionContext? seenContext;
      final resolver = _StaticFlowResolver(
        _actionResolvedFlow(),
      );
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: _MatchingActionRegistry(
          handler: (_, context) {
            seenContext = context;
            return true;
          },
        ),
        onEvent: (_) {},
        onComplete: (result) => completed = result,
        onUnavailable: (error) => unavailable = error,
      );

      await controller.load();
      controller.handleEvent('request', const <String, Object?>{});
      await _drainFlowTasks();

      expect(unavailable, isNull);
      expect(completed?.completed, isTrue);
      expect(seenContext?.operationId, isNotEmpty);
      expect(seenContext?.isRetry, isFalse);
      expect(seenContext?.attemptNumber, 1);
    });

    test('action handler receives context with null args', () async {
      var handlerCalled = false;
      FlowActionContext? seenContext;
      final resolver = _StaticFlowResolver(
        _actionResolvedFlow(),
      );
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: _MatchingActionRegistry(
          handler: (_, context) {
            handlerCalled = true;
            seenContext = context;
            return true;
          },
        ),
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (_) {},
      );

      await controller.load();
      controller.handleEvent('request', null);
      await _drainFlowTasks();

      expect(handlerCalled, isTrue);
      expect(seenContext?.operationId, isNotEmpty);
      expect(seenContext?.attemptNumber, 1);
    });

    test('action args without outbound declaration fail before host handler',
        () async {
      var decodeCalls = 0;
      var handlerCalls = 0;
      FlowUnavailableError? unavailable;
      final resolver = _StaticFlowResolver(
        _resolvedFlow(
          actions: {
            'requestNotifications': _actionContract(
              argsSchema: _profileArgsSchema,
            ),
          },
          states: const {
            'welcome': ScreenFlowState(
              screen: 'welcome',
              on: {
                'request': ActionFlowTransition(
                  action: 'requestNotifications',
                  resultPredicate: BoolEqualsActionResultPredicate(
                    value: true,
                  ),
                  target: 'done',
                ),
              },
            ),
            'done': EndFlowState(result: {'completed': true}),
          },
        ),
      );
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: _TestActionRegistry({
          'requestNotifications': FlowActionBinding<Map<String, Object?>, bool>(
            descriptor: FlowActionDescriptor<Map<String, Object?>, bool>(
              actionName: 'requestNotifications',
              contractVersion: 1,
              argsSchema: _profileArgsSchema,
              resultSchema: _boolResultSchema,
              minClient: 3,
              idempotent: false,
            ),
            actionName: 'requestNotifications',
            contractVersion: 1,
            argsSchema: _profileArgsSchema,
            resultSchema: _boolResultSchema,
            minClient: 3,
            idempotent: false,
            handler: (_, __) {
              handlerCalls += 1;
              return true;
            },
            decodeArgs: (value) {
              decodeCalls += 1;
              return Map<String, Object?>.from(value as Map);
            },
            encodeResult: (value) => value,
          ),
        }),
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (error) => unavailable = error,
      );

      await controller.load();
      controller.handleEvent('request', const {'profileId': 'profile-123'});
      await _drainFlowTasks();

      expect(decodeCalls, 0);
      expect(handlerCalls, 0);
      expect(unavailable?.reason, 'action_args_unavailable');
      expect(unavailable?.message, contains('requestNotifications'));
    });

    test('action args are filtered through outbound declaration before decode',
        () async {
      Map<String, Object?>? seenArgs;
      FlowUnavailableError? unavailable;
      final resolver = _StaticFlowResolver(
        _resolvedFlow(
          document: _document(
            actions: {
              'requestNotifications': _actionContract(
                argsSchema: _profileArgsSchema,
              ),
            },
            outbound: const FlowOutboundDeclarations(
              actionArgs: {
                'requestNotifications': FlowOutboundPayloadDeclaration(
                  fields: {
                    'profileId': FlowOutboundField(
                      type: FlowDataType.string,
                      ref: EventFlowOutboundRef(key: 'profileId'),
                    ),
                  },
                ),
              },
              terminalResult: FlowOutboundPayloadDeclaration(
                fields: {
                  'completed': FlowOutboundField(
                    type: FlowDataType.bool,
                    ref: EventFlowOutboundRef(key: 'completed'),
                  ),
                },
              ),
            ),
            states: const {
              'welcome': ScreenFlowState(
                screen: 'welcome',
                on: {
                  'request': ActionFlowTransition(
                    action: 'requestNotifications',
                    resultPredicate: BoolEqualsActionResultPredicate(
                      value: true,
                    ),
                    target: 'done',
                  ),
                },
              ),
              'done': EndFlowState(result: {'completed': true}),
            },
          ),
        ),
      );
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: _TestActionRegistry({
          'requestNotifications': FlowActionBinding<Map<String, Object?>, bool>(
            descriptor: FlowActionDescriptor<Map<String, Object?>, bool>(
              actionName: 'requestNotifications',
              contractVersion: 1,
              argsSchema: _profileArgsSchema,
              resultSchema: _boolResultSchema,
              minClient: 3,
              idempotent: false,
            ),
            actionName: 'requestNotifications',
            contractVersion: 1,
            argsSchema: _profileArgsSchema,
            resultSchema: _boolResultSchema,
            minClient: 3,
            idempotent: false,
            handler: (args, _) {
              seenArgs = args;
              return true;
            },
            decodeArgs: (value) {
              final args = Map<String, Object?>.from(value as Map);
              if (args.keys.any((key) => key != 'profileId')) {
                throw StateError('unfiltered action args reached decode');
              }
              return args;
            },
            encodeResult: (value) => value,
          ),
        }),
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (error) => unavailable = error,
      );

      await controller.load();
      controller.handleEvent('request', const {
        'profileId': 'profile-123',
        'secret': 'do-not-pass',
      });
      await _drainFlowTasks();

      expect(unavailable, isNull);
      expect(seenArgs, {'profileId': 'profile-123'});
    });

    test('action args can be sourced from flow state declaration', () async {
      Map<String, Object?>? seenArgs;
      FlowUnavailableError? unavailable;
      final resolver = _StaticFlowResolver(
        _resolvedFlow(
          document: _document(
            actions: {
              'requestNotifications': _actionContract(
                argsSchema: _profileArgsSchema,
              ),
            },
            flowState: const {
              'profileId': FlowStateDeclaration(
                type: FlowDataType.string,
                classification: FlowStateClassification.exportable,
                defaultValue: 'profile-123',
              ),
            },
            outbound: const FlowOutboundDeclarations(
              actionArgs: {
                'requestNotifications': FlowOutboundPayloadDeclaration(
                  fields: {
                    'profileId': FlowOutboundField(
                      type: FlowDataType.string,
                      ref: StateFlowOutboundRef(key: 'profileId'),
                    ),
                  },
                ),
              },
              terminalResult: FlowOutboundPayloadDeclaration(
                fields: {
                  'completed': FlowOutboundField(
                    type: FlowDataType.bool,
                    ref: EventFlowOutboundRef(key: 'completed'),
                  ),
                },
              ),
            ),
            states: const {
              'welcome': ScreenFlowState(
                screen: 'welcome',
                on: {
                  'request': ActionFlowTransition(
                    action: 'requestNotifications',
                    resultPredicate: BoolEqualsActionResultPredicate(
                      value: true,
                    ),
                    target: 'done',
                  ),
                },
              ),
              'done': EndFlowState(result: {'completed': true}),
            },
          ),
        ),
      );
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: _TestActionRegistry({
          'requestNotifications': FlowActionBinding<Map<String, Object?>, bool>(
            descriptor: FlowActionDescriptor<Map<String, Object?>, bool>(
              actionName: 'requestNotifications',
              contractVersion: 1,
              argsSchema: _profileArgsSchema,
              resultSchema: _boolResultSchema,
              minClient: 3,
              idempotent: false,
            ),
            actionName: 'requestNotifications',
            contractVersion: 1,
            argsSchema: _profileArgsSchema,
            resultSchema: _boolResultSchema,
            minClient: 3,
            idempotent: false,
            handler: (args, _) {
              seenArgs = args;
              return true;
            },
            decodeArgs: (value) => Map<String, Object?>.from(value as Map),
            encodeResult: (value) => value,
          ),
        }),
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (error) => unavailable = error,
      );

      await controller.load();
      controller.handleEvent('request', const {
        'profileId': 'raw-profile',
        'secret': 'do-not-pass',
      });
      await _drainFlowTasks();

      expect(unavailable, isNull);
      expect(seenArgs, {'profileId': 'profile-123'});
    });

    test('bad terminal result emits unavailable and skips completion',
        () async {
      _FirstRunResult? completed;
      FlowUnavailableError? unavailable;
      final events = <RestageEvent>[];
      final resolver = _StaticFlowResolver(
        _resolvedFlow(
          states: const {
            'welcome': ScreenFlowState(
              screen: 'welcome',
              on: {'finish': FlowTransition.goto('done')},
            ),
            'done': EndFlowState(result: {'completed': 'yes'}),
          },
        ),
      );
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: null,
        onEvent: events.add,
        onComplete: (result) => completed = result,
        onUnavailable: (error) => unavailable = error,
      );

      await controller.load();
      controller.handleEvent('finish', const <String, Object?>{});
      await Future<void>.delayed(Duration.zero);

      expect(completed, isNull);
      expect(unavailable?.reason, 'result_decode_failed');
      expect(events.whereType<FlowUnavailable>().single.reason,
          'result_decode_failed');
      expect(events.whereType<FlowCompleted>(), isEmpty);
    });

    test('unknown RFW events are dropped without PaywallCustomEvent', () async {
      final events = <RestageEvent>[];
      final resolver = _StaticFlowResolver(_resolvedFlow());
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: null,
        onEvent: events.add,
        onComplete: (_) {},
        onUnavailable: (_) {},
      );

      await controller.load();
      controller.handleEvent('restage.purchase', const {'slot': 'primary'});
      await Future<void>.delayed(Duration.zero);

      expect(events.whereType<PaywallCustomEvent>(), isEmpty);
      expect(events.whereType<FlowCustomEvent>(), isEmpty);
      expect(controller.currentScreenId, 'welcome');
    });

    test('paywall purchase event routes to authored purchase transition',
        () async {
      _FirstRunResult? completed;
      final events = <RestageEvent>[];
      final resolver = _StaticFlowResolver(
        _resolvedFlow(
          states: const {
            'welcome': ScreenFlowState(
              screen: 'welcome',
              on: {'purchase': FlowTransition.goto('done')},
            ),
            'done': EndFlowState(result: {'completed': true}),
          },
        ),
      );
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: null,
        onEvent: events.add,
        onComplete: (result) => completed = result,
        onUnavailable: (_) {},
      );

      await controller.load();
      controller.handleEvent('restage.purchase', const {'slot': 'primary'});
      await Future<void>.delayed(Duration.zero);

      expect(completed?.completed, isTrue);
      expect(events.whereType<PaywallCustomEvent>(), isEmpty);
      expect(controller.isComplete, isTrue);
    });

    test('allowlisted custom event emits only filtered flow fields', () async {
      final events = <RestageEvent>[];
      final resolver = _StaticFlowResolver(
        _resolvedFlow(
          document: _document(
            outbound: const FlowOutboundDeclarations(
              customEvents: {
                'analyticsTap': FlowOutboundPayloadDeclaration(
                  fields: {
                    'ctaId': FlowOutboundField(
                      type: FlowDataType.string,
                      ref: EventFlowOutboundRef(key: 'ctaId'),
                    ),
                    'campaign': FlowOutboundField(
                      type: FlowDataType.string,
                      ref: EventFlowOutboundRef(
                        key: 'properties',
                        path: ['campaign'],
                      ),
                    ),
                    'ignoredMismatch': FlowOutboundField(
                      type: FlowDataType.string,
                      ref: EventFlowOutboundRef(key: 'count'),
                    ),
                  },
                ),
              },
            ),
          ),
        ),
      );
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: null,
        onEvent: events.add,
        onComplete: (_) {},
        onUnavailable: (_) {},
      );

      await controller.load();
      controller.handleEvent('analyticsTap', const {
        'ctaId': 'primary',
        'properties': {
          'campaign': 'spring',
          'secret': 'do-not-emit',
        },
        'count': 3,
        'secret': 'do-not-emit',
      });
      await Future<void>.delayed(Duration.zero);

      final event = events.whereType<FlowCustomEvent>().single;
      expect(event.flowId, 'first_run');
      expect(event.flowVersion, 1);
      expect(event.eventName, 'analyticsTap');
      expect(event.fields, {'ctaId': 'primary', 'campaign': 'spring'});
      expect(events.whereType<PaywallCustomEvent>(), isEmpty);
    });

    test('flow lifecycle events are emitted around successful completion',
        () async {
      final events = <RestageEvent>[];
      final resolver = _StaticFlowResolver(_resolvedFlow());
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: null,
        onEvent: events.add,
        onComplete: (_) {},
        onUnavailable: (_) {},
      );

      await controller.load();

      expect(events.whereType<FlowStarted>(), hasLength(1));

      controller.handleEvent('next', const <String, Object?>{});
      await Future<void>.delayed(Duration.zero);
      controller.handleEvent('finish', const <String, Object?>{});
      await Future<void>.delayed(Duration.zero);

      expect(events.whereType<FlowCompleted>(), hasLength(1));
      expect(events.whereType<PaywallCustomEvent>(), isEmpty);
    });

    test('screenless initial completion emits started before completed',
        () async {
      final events = <RestageEvent>[];
      _FirstRunResult? completed;
      final resolver = _StaticFlowResolver(
        _resolvedFlow(
          document: _document(
            initial: 'branch',
            outbound: const FlowOutboundDeclarations(
              terminalResult: FlowOutboundPayloadDeclaration(
                fields: {
                  'completed': FlowOutboundField(
                    type: FlowDataType.bool,
                    ref: EventFlowOutboundRef(key: 'completed'),
                  ),
                },
              ),
            ),
            states: const {
              'branch': DecisionFlowState(
                branches: [],
                defaultBranch: FlowBranchTarget(target: 'done'),
              ),
              'done': EndFlowState(result: {'completed': true}),
            },
          ),
        ),
      );
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: null,
        onEvent: events.add,
        onComplete: (result) => completed = result,
        onUnavailable: (_) {},
      );

      await controller.load();
      await _drainFlowTasks();

      expect(completed?.completed, isTrue);
      expect(events.map((event) => event.runtimeType), [
        FlowStarted,
        FlowCompleted,
      ]);
    });

    test('unsupported document features fail closed before initial screen',
        () async {
      FlowUnavailableError? unavailable;
      final resolver = _StaticFlowResolver(
        _resolvedFlow(document: _document(unsupportedFeatures: {'decision'})),
      );
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: null,
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (error) => unavailable = error,
      );

      await controller.load();

      expect(controller.currentLibrary, isNull);
      expect(unavailable?.reason, 'unsupported_feature');
    });

    test('outbound validation issues fail closed before initial screen',
        () async {
      FlowUnavailableError? unavailable;
      final resolver = _StaticFlowResolver(
        _resolvedFlow(
          document: _document(
            outbound: const FlowOutboundDeclarations(
              terminalResult: FlowOutboundPayloadDeclaration(
                fields: {
                  'selectedPlan': FlowOutboundField(
                    type: FlowDataType.string,
                    ref: StateFlowOutboundRef(key: 'missing'),
                  ),
                },
              ),
            ),
          ),
        ),
      );
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: null,
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (error) => unavailable = error,
      );

      await controller.load();

      expect(controller.currentLibrary, isNull);
      expect(unavailable?.reason, 'validation_failed');
      expect(
        unavailable?.message,
        contains(r'$.outbound.terminalResult.fields.selectedPlan.ref'),
      );
    });

    test('missing screen blob fails closed before initial screen', () async {
      FlowUnavailableError? unavailable;
      final resolver = _StaticFlowResolver(
        ResolvedFlow(
          document: _document(),
          screenBlobs: const {},
          cacheHit: false,
        ),
      );
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: null,
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (error) => unavailable = error,
      );

      await controller.load();

      expect(controller.currentLibrary, isNull);
      expect(unavailable?.reason, 'missing_screen_blob');
    });

    test('corrupt screen blob fails closed before initial screen', () async {
      FlowUnavailableError? unavailable;
      final resolver = _StaticFlowResolver(
        ResolvedFlow(
          document: _document(
            screenHashes: {
              'welcome': FlowContentHash.compute(Uint8List.fromList([0, 1])),
              'profile': FlowContentHash.compute(_screenBlob('Profile')),
            },
          ),
          screenBlobs: {
            'welcome': Uint8List.fromList([0, 1]),
            'profile': _screenBlob('Profile'),
          },
          cacheHit: false,
        ),
      );
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: null,
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (error) => unavailable = error,
      );

      await controller.load();

      expect(controller.currentLibrary, isNull);
      expect(unavailable?.reason, 'decode_failed');
    });

    test('corrupt transition screen blob fails closed during transition',
        () async {
      FlowUnavailableError? unavailable;
      final welcome = _screenBlob('Welcome');
      final corruptProfile = Uint8List.fromList([0, 1]);
      final resolver = _StaticFlowResolver(
        ResolvedFlow(
          document: _document(
            screenHashes: {
              'welcome': FlowContentHash.compute(welcome),
              'profile': FlowContentHash.compute(corruptProfile),
            },
          ),
          screenBlobs: {
            'welcome': welcome,
            'profile': corruptProfile,
          },
          cacheHit: false,
        ),
      );
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: null,
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (error) => unavailable = error,
      );

      await controller.load();
      controller.handleEvent('next', const <String, Object?>{});
      await Future<void>.delayed(Duration.zero);

      expect(controller.currentLibrary, isNull);
      expect(unavailable?.reason, 'decode_failed');
    });

    test('document requiring actions fails closed when actions are omitted',
        () async {
      FlowUnavailableError? unavailable;
      final resolver = _StaticFlowResolver(
        _resolvedFlow(actions: {'requestNotifications': _actionContract()}),
      );
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: null,
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (error) => unavailable = error,
      );

      await controller.load();

      expect(controller.currentLibrary, isNull);
      expect(unavailable?.reason, 'action_contract_mismatch');
      expect(unavailable?.message, contains('actions'));
    });

    test('missing binding fails closed before first screen', () async {
      FlowUnavailableError? unavailable;
      final resolver = _StaticFlowResolver(
        _resolvedFlow(actions: {'requestNotifications': _actionContract()}),
      );
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: _TestActionRegistry(const {}),
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (error) => unavailable = error,
      );

      await controller.load();

      expect(controller.currentLibrary, isNull);
      expect(unavailable?.message, contains('binding'));
      expect(unavailable?.message, contains('requestNotifications'));
    });

    test('contract version mismatch fails closed with field name', () async {
      FlowUnavailableError? unavailable;
      final resolver = _StaticFlowResolver(
        _resolvedFlow(actions: {'requestNotifications': _actionContract()}),
      );
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: _MatchingActionRegistry(contractVersion: 2),
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (error) => unavailable = error,
      );

      await controller.load();

      expect(controller.currentLibrary, isNull);
      expect(unavailable?.message, contains('contractVersion'));
    });

    test('args schema hash mismatch fails closed with both hashes', () async {
      FlowUnavailableError? unavailable;
      final resolver = _StaticFlowResolver(
        _resolvedFlow(actions: {'requestNotifications': _actionContract()}),
      );
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: _MatchingActionRegistry(argsSchema: _stringArgsSchema),
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (error) => unavailable = error,
      );

      await controller.load();

      expect(controller.currentLibrary, isNull);
      expect(unavailable?.message, contains('argsSchemaHash'));
      expect(unavailable?.message, contains(_emptyArgsHash));
      expect(unavailable?.message, contains(_stringArgsHash));
      expect(unavailable?.message, contains('kindMismatch'));
    });

    test('result schema hash mismatch fails closed with both hashes', () async {
      FlowUnavailableError? unavailable;
      final resolver = _StaticFlowResolver(
        _resolvedFlow(actions: {'requestNotifications': _actionContract()}),
      );
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: _MatchingActionRegistry(resultSchema: _stringResultSchema),
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (error) => unavailable = error,
      );

      await controller.load();

      expect(controller.currentLibrary, isNull);
      expect(unavailable?.message, contains('resultSchemaHash'));
      expect(unavailable?.message, contains(_boolResultHash));
      expect(unavailable?.message, contains(_stringResultHash));
    });

    test('schema hash mismatch diagnostics include structural diffs', () async {
      FlowUnavailableError? unavailable;
      final resolver = _StaticFlowResolver(
        _resolvedFlow(actions: {'requestNotifications': _actionContract()}),
      );
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: _MatchingActionRegistry(resultSchema: _stringResultSchema),
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (error) => unavailable = error,
      );

      await controller.load();

      expect(controller.currentLibrary, isNull);
      expect(
        unavailable?.message,
        allOf(
          contains('resultSchemaHash'),
          contains(_boolResultHash),
          contains(_stringResultHash),
          contains('kindMismatch'),
          contains(r'$'),
        ),
      );
    });

    test('idempotent mismatch fails closed before first screen', () async {
      FlowUnavailableError? unavailable;
      final resolver = _StaticFlowResolver(
        _resolvedFlow(actions: {'requestNotifications': _actionContract()}),
      );
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: _MatchingActionRegistry(idempotent: true),
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (error) => unavailable = error,
      );

      await controller.load();

      expect(controller.currentLibrary, isNull);
      expect(unavailable?.reason, 'action_contract_mismatch');
      expect(unavailable?.message, contains('idempotent'));
    });

    test('result predicate incompatible with action result schema fails closed',
        () async {
      FlowUnavailableError? unavailable;
      final resolver = _StaticFlowResolver(
        _resolvedFlow(
          actions: {'requestNotifications': _actionContract()},
          states: {
            'welcome': const ScreenFlowState(
              screen: 'welcome',
              on: {
                'request': ActionFlowTransition(
                  action: 'requestNotifications',
                  resultPredicate: ObjectBoolFieldEqualsActionResultPredicate(
                    field: 'granted',
                    value: true,
                  ),
                  target: 'done',
                ),
              },
            ),
            'done': const EndFlowState(result: {'completed': true}),
          },
        ),
      );
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: _MatchingActionRegistry(),
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (error) => unavailable = error,
      );

      await controller.load();

      expect(controller.currentLibrary, isNull);
      expect(unavailable?.reason, 'action_contract_mismatch');
      expect(unavailable?.message, contains('resultPredicate'));
      expect(unavailable?.message, contains('granted'));
    });

    test('minClient mismatch fails closed', () async {
      FlowUnavailableError? unavailable;
      final resolver = _StaticFlowResolver(
        _resolvedFlow(actions: {
          'requestNotifications': _actionContract(minClient: 4),
        }),
      );
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: _MatchingActionRegistry(),
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (error) => unavailable = error,
      );

      await controller.load();

      expect(controller.currentLibrary, isNull);
      expect(unavailable?.message, contains('minClient'));
    });

    test('matching action contracts proceed to initial screen', () async {
      FlowUnavailableError? unavailable;
      final resolver = _StaticFlowResolver(
        _resolvedFlow(actions: {'requestNotifications': _actionContract()}),
      );
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: _MatchingActionRegistry(),
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (error) => unavailable = error,
      );

      await controller.load();

      expect(unavailable, isNull);
      expect(controller.currentScreenId, 'welcome');
      expect(controller.currentLibrary, isNotNull);
    });

    test('matching contract for previously unused action proceeds', () async {
      FlowUnavailableError? unavailable;
      final resolver = _StaticFlowResolver(
        _resolvedFlow(
          actions: {
            'futureAction': _actionContract(actionName: 'futureAction'),
          },
        ),
      );
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: _TestActionRegistry({
          'futureAction': _actionBinding(actionName: 'futureAction'),
        }),
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (error) => unavailable = error,
      );

      await controller.load();

      expect(unavailable, isNull);
      expect(controller.currentScreenId, 'welcome');
      expect(controller.currentLibrary, isNotNull);
    });

    test('false action predicate stays on current screen and clears in-flight',
        () async {
      final operationIds = <String>[];
      FlowUnavailableError? unavailable;
      final resolver = _StaticFlowResolver(
        _actionResolvedFlow(),
      );
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: _MatchingActionRegistry(
          handler: (_, context) {
            operationIds.add(context.operationId);
            return false;
          },
        ),
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (error) => unavailable = error,
      );

      await controller.load();
      controller.handleEvent('request', const <String, Object?>{});
      await _drainFlowTasks();
      controller.handleEvent('request', const <String, Object?>{});
      await _drainFlowTasks();

      expect(unavailable, isNull);
      expect(controller.currentScreenId, 'welcome');
      expect(operationIds, hasLength(2));
      expect(operationIds.first, isNot(operationIds.last));
    });

    test('fresh flow sessions mint distinct operation IDs', () async {
      final operationIds = <String>[];

      Future<void> runSession() async {
        final controller = RestageFlowController<_FirstRunResult>(
          flow: _flowRef,
          resolver: _StaticFlowResolver(_actionResolvedFlow()),
          actions: _MatchingActionRegistry(
            handler: (_, context) {
              operationIds.add(context.operationId);
              return false;
            },
          ),
          onEvent: (_) {},
          onComplete: (_) {},
          onUnavailable: (_) {},
        );

        await controller.load();
        controller.handleEvent('request', const <String, Object?>{});
        await _drainFlowTasks();
      }

      await runSession();
      await runSession();

      expect(operationIds, hasLength(2));
      expect(operationIds.first, isNot(operationIds.last));
    });

    test('object bool-field predicate evaluates encoded action result',
        () async {
      _FirstRunResult? completed;
      final resolver = _StaticFlowResolver(
        _resolvedFlow(
          actions: {
            'requestNotifications': _actionContract(
              resultSchema: _notificationResultSchema,
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
                  target: 'done',
                ),
              },
            ),
            'done': EndFlowState(result: {'completed': true}),
          },
        ),
      );
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: _TestActionRegistry({
          'requestNotifications': FlowActionBinding<void, _PermissionResult>(
            descriptor: FlowActionDescriptor<void, _PermissionResult>(
              actionName: 'requestNotifications',
              contractVersion: 1,
              argsSchema: _emptyArgsSchema,
              resultSchema: _notificationResultSchema,
              minClient: 3,
              idempotent: false,
            ),
            actionName: 'requestNotifications',
            contractVersion: 1,
            argsSchema: _emptyArgsSchema,
            resultSchema: _notificationResultSchema,
            minClient: 3,
            idempotent: false,
            handler: (_, __) => const _PermissionResult(granted: true),
            decodeArgs: (_) {},
            encodeResult: (result) => {'granted': result.granted},
          ),
        }),
        onEvent: (_) {},
        onComplete: (result) => completed = result,
        onUnavailable: (_) {},
      );

      await controller.load();
      controller.handleEvent('request', const <String, Object?>{});
      await _drainFlowTasks();

      expect(completed?.completed, isTrue);
    });

    test('event state write drives ordered decision branch', () async {
      final resolver = _StaticFlowResolver(
        _resolvedFlow(
          document: _document(
            flowState: const {
              'isPro': FlowStateDeclaration(
                type: FlowDataType.bool,
                classification: FlowStateClassification.internal,
              ),
            },
            outbound: const FlowOutboundDeclarations(
              terminalResult: FlowOutboundPayloadDeclaration(
                fields: {
                  'completed': FlowOutboundField(
                    type: FlowDataType.bool,
                    ref: EventFlowOutboundRef(key: 'completed'),
                  ),
                },
              ),
            ),
            states: const {
              'welcome': ScreenFlowState(
                screen: 'welcome',
                on: {
                  'next': GotoFlowTransition(
                    'branch',
                    stateWrites: {
                      'isPro': FlowStateWrite(
                        type: FlowDataType.bool,
                        value: EventFlowValueSource(key: 'isPro'),
                      ),
                    },
                  ),
                },
              ),
              'branch': DecisionFlowState(
                branches: [
                  FlowBranch(
                    when: FlowBranchPredicate(
                      fields: {
                        'isPro': EqualsFlowPredicateCondition(
                          value: LiteralFlowValueSource(
                            type: FlowDataType.bool,
                            value: true,
                          ),
                        ),
                      },
                    ),
                    target: 'profile',
                  ),
                ],
                defaultBranch: FlowBranchTarget(target: 'done'),
              ),
              'profile': ScreenFlowState(
                screen: 'profile',
                on: {'finish': FlowTransition.goto('done')},
              ),
              'done': EndFlowState(result: {'completed': true}),
            },
          ),
        ),
      );
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: null,
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (_) {},
      );

      await controller.load();
      controller.handleEvent('next', const {'isPro': true});
      await _drainFlowTasks();

      expect(controller.currentScreenId, 'profile');
    });

    test(
        'a forking screen lands a captured event field + a literal write and '
        'dispatches by event name', () async {
      const flowState = {
        'goal': FlowStateDeclaration(
          type: FlowDataType.string,
          classification: FlowStateClassification.internal,
        ),
        'wantsPro': FlowStateDeclaration(
          type: FlowDataType.bool,
          classification: FlowStateClassification.internal,
        ),
      };
      const states = {
        'welcome': ScreenFlowState(
          screen: 'welcome',
          on: {
            // The capturing transition: write the event's scalar value (carried
            // under the reserved value key) into flow-state 'goal' and a literal
            // 'wantsPro', then route via the decision.
            'choose': GotoFlowTransition(
              'branch',
              stateWrites: {
                'goal': FlowStateWrite(
                  type: FlowDataType.string,
                  value: EventFlowValueSource(key: kCapturedEventValueKey),
                ),
                'wantsPro': FlowStateWrite(
                  type: FlowDataType.bool,
                  value: LiteralFlowValueSource(
                    type: FlowDataType.bool,
                    value: true,
                  ),
                ),
              },
            ),
            // A second transition on the same screen (a multi-key `on` map).
            'cancel': FlowTransition.goto('done'),
          },
        ),
        // The decision requires BOTH writes to have landed, so a passing route
        // to 'profile' proves the capture AND the literal both applied.
        'branch': DecisionFlowState(
          branches: [
            FlowBranch(
              when: FlowBranchPredicate(
                fields: {
                  'goal': EqualsFlowPredicateCondition(
                    value: LiteralFlowValueSource(
                      type: FlowDataType.string,
                      value: 'sleep',
                    ),
                  ),
                  'wantsPro': EqualsFlowPredicateCondition(
                    value: LiteralFlowValueSource(
                      type: FlowDataType.bool,
                      value: true,
                    ),
                  ),
                },
              ),
              target: 'profile',
            ),
          ],
          defaultBranch: FlowBranchTarget(target: 'done'),
        ),
        'profile': ScreenFlowState(
          screen: 'profile',
          on: {'finish': FlowTransition.goto('done')},
        ),
        'done': EndFlowState(result: {'completed': true}),
      };
      // Allowlist the terminal 'completed' field so it survives outbound
      // filtering and the generated result decoder accepts it.
      const outbound = FlowOutboundDeclarations(
        terminalResult: FlowOutboundPayloadDeclaration(
          fields: {
            'completed': FlowOutboundField(
              type: FlowDataType.bool,
              ref: EventFlowOutboundRef(key: 'completed'),
            ),
          },
        ),
      );

      RestageFlowController<_FirstRunResult> controllerFor() {
        return RestageFlowController<_FirstRunResult>(
          flow: _flowRef,
          resolver: _StaticFlowResolver(
            _resolvedFlow(
              document: _document(
                flowState: flowState,
                states: states,
                outbound: outbound,
              ),
            ),
          ),
          actions: null,
          onEvent: (_) {},
          onComplete: (_) {},
          onUnavailable: (_) {},
        );
      }

      // 'choose' captures the event value ('sleep') into 'goal' and writes
      // wantsPro=true; both must land for the decision to route to 'profile'.
      final captured = controllerFor();
      await captured.load();
      captured.handleEvent('choose', const {kCapturedEventValueKey: 'sleep'});
      await _drainFlowTasks();
      expect(captured.currentScreenId, 'profile');
      expect(captured.isComplete, isFalse);

      // The screen's second transition dispatches to its own target. Dispose
      // the first controller so a single flow is live (matching the
      // single-controller tests in this group).
      captured.dispose();
      final cancelled = controllerFor();
      await cancelled.load();
      cancelled.handleEvent('cancel', const <String, Object?>{});
      await _drainFlowTasks();
      expect(cancelled.isComplete, isTrue);
    });

    test('a captured answer routes a decision via state().equals() sugar',
        () async {
      const flowState = {
        'goal': FlowStateDeclaration(
          type: FlowDataType.string,
          classification: FlowStateClassification.internal,
        ),
      };
      // The decision branch predicate is built by the authoring SUGAR
      // (state('goal').equals('sleep')), proving the sugar's output is a real,
      // engine-routable predicate fed by a captured scalar answer.
      final states = <String, FlowState>{
        'welcome': const ScreenFlowState(
          screen: 'welcome',
          on: {
            'choose': GotoFlowTransition(
              'route',
              stateWrites: {
                'goal': FlowStateWrite(
                  type: FlowDataType.string,
                  value: EventFlowValueSource(key: kCapturedEventValueKey),
                ),
              },
            ),
          },
        ),
        'route': DecisionFlowState(
          branches: [
            FlowBranch(
              when: state('goal').equals('sleep'),
              target: 'profile',
            ),
          ],
          defaultBranch: const FlowBranchTarget(target: 'done'),
        ),
        'profile': const ScreenFlowState(
          screen: 'profile',
          on: {'finish': FlowTransition.goto('done')},
        ),
        'done': const EndFlowState(result: {'completed': true}),
      };
      const outbound = FlowOutboundDeclarations(
        terminalResult: FlowOutboundPayloadDeclaration(
          fields: {
            'completed': FlowOutboundField(
              type: FlowDataType.bool,
              ref: EventFlowOutboundRef(key: 'completed'),
            ),
          },
        ),
      );

      RestageFlowController<_FirstRunResult> controllerFor() {
        return RestageFlowController<_FirstRunResult>(
          flow: _flowRef,
          resolver: _StaticFlowResolver(
            _resolvedFlow(
              document: _document(
                flowState: flowState,
                states: states,
                outbound: outbound,
              ),
            ),
          ),
          actions: null,
          onEvent: (_) {},
          onComplete: (_) {},
          onUnavailable: (_) {},
        );
      }

      // Captured 'sleep' -> the sugar branch matches -> routes to 'profile'.
      final matched = controllerFor();
      await matched.load();
      matched.handleEvent('choose', const {kCapturedEventValueKey: 'sleep'});
      await _drainFlowTasks();
      expect(matched.currentScreenId, 'profile');
      expect(matched.isComplete, isFalse);
      matched.dispose();

      // Captured 'focus' -> no branch matches -> default routes to 'done'.
      final defaulted = controllerFor();
      await defaulted.load();
      defaulted.handleEvent('choose', const {kCapturedEventValueKey: 'focus'});
      await _drainFlowTasks();
      expect(defaulted.isComplete, isTrue);
    });

    test('decision default branch is used when no branch matches', () async {
      final resolver = _StaticFlowResolver(
        _resolvedFlow(
          document: _document(
            flowState: const {
              'isPro': FlowStateDeclaration(
                type: FlowDataType.bool,
                classification: FlowStateClassification.internal,
                defaultValue: false,
              ),
            },
            outbound: const FlowOutboundDeclarations(
              terminalResult: FlowOutboundPayloadDeclaration(
                fields: {
                  'completed': FlowOutboundField(
                    type: FlowDataType.bool,
                    ref: EventFlowOutboundRef(key: 'completed'),
                  ),
                },
              ),
            ),
            states: const {
              'welcome': ScreenFlowState(
                screen: 'welcome',
                on: {'next': FlowTransition.goto('branch')},
              ),
              'branch': DecisionFlowState(
                branches: [
                  FlowBranch(
                    when: FlowBranchPredicate(
                      fields: {
                        'isPro': EqualsFlowPredicateCondition(
                          value: LiteralFlowValueSource(
                            type: FlowDataType.bool,
                            value: true,
                          ),
                        ),
                      },
                    ),
                    target: 'done',
                  ),
                ],
                defaultBranch: FlowBranchTarget(target: 'profile'),
              ),
              'profile': ScreenFlowState(
                screen: 'profile',
                on: {'finish': FlowTransition.goto('done')},
              ),
              'done': EndFlowState(result: {'completed': true}),
            },
          ),
        ),
      );
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: null,
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (_) {},
      );

      await controller.load();
      controller.handleEvent('next', const <String, Object?>{});
      await _drainFlowTasks();

      expect(controller.currentScreenId, 'profile');
    });

    test('host seed overlays seedable state before initial decision', () async {
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: _StaticFlowResolver(
          _resolvedFlow(document: _hostSeedDecisionDocument()),
        ),
        initialState: const _MapSeed({'isReturningUser': true}),
        actions: null,
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (_) {},
      );

      await controller.load();

      expect(controller.currentScreenId, 'profile');
    });

    test('host seed overrides a declared default value', () async {
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: _StaticFlowResolver(
          _resolvedFlow(
            document: _hostSeedDecisionDocument(defaultValue: false),
          ),
        ),
        initialState: const _MapSeed({'isReturningUser': true}),
        actions: null,
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (_) {},
      );

      await controller.load();

      expect(controller.currentScreenId, 'profile');
    });

    test('unknown host seed key fails closed before initial screen', () async {
      FlowUnavailableError? unavailable;
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: _StaticFlowResolver(_resolvedFlow()),
        initialState: const _MapSeed({'nope': true}),
        actions: null,
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (error) => unavailable = error,
      );

      await controller.load();

      expect(controller.currentLibrary, isNull);
      expect(unavailable?.reason, 'seed_unknown_key');
      expect(unavailable?.message, contains('nope'));
    });

    test('non-seedable host seed key fails closed before initial screen',
        () async {
      FlowUnavailableError? unavailable;
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: _StaticFlowResolver(
          _resolvedFlow(
            document: _hostSeedDecisionDocument(hostSeedable: false),
          ),
        ),
        initialState: const _MapSeed({'isReturningUser': true}),
        actions: null,
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (error) => unavailable = error,
      );

      await controller.load();

      expect(controller.currentLibrary, isNull);
      expect(unavailable?.reason, 'seed_not_seedable');
      expect(unavailable?.message, contains('isReturningUser'));
    });

    test('host seed type mismatch fails closed before initial screen',
        () async {
      FlowUnavailableError? unavailable;
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: _StaticFlowResolver(
          _resolvedFlow(
            document: _document(
              flowState: const {
                'launchCount': FlowStateDeclaration(
                  type: FlowDataType.int,
                  classification: FlowStateClassification.internal,
                  hostSeedable: true,
                ),
              },
            ),
          ),
        ),
        initialState: const _MapSeed({'launchCount': 'one'}),
        actions: null,
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (error) => unavailable = error,
      );

      await controller.load();

      expect(controller.currentLibrary, isNull);
      expect(unavailable?.reason, 'seed_type_mismatch');
      expect(unavailable?.message, contains('launchCount'));
      expect(unavailable?.message, contains('int'));
      expect(unavailable?.message, contains('String'));
    });

    test('host seed lands after the resolved flow document is frozen',
        () async {
      final resolved = _resolvedFlow(document: _hostSeedDecisionDocument());
      expect(
        resolved.document.flowState['isReturningUser']!.hostSeedable,
        isTrue,
      );
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: _StaticFlowResolver(resolved),
        initialState: const _MapSeed({'isReturningUser': true}),
        actions: null,
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (_) {},
      );

      await controller.load();

      expect(controller.currentScreenId, 'profile');
    });

    test('null host seed value fails closed before initial screen', () async {
      FlowUnavailableError? unavailable;
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: _StaticFlowResolver(
          _resolvedFlow(document: _hostSeedDecisionDocument()),
        ),
        initialState: const _MapSeed({'isReturningUser': null}),
        actions: null,
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (error) => unavailable = error,
      );

      await controller.load();

      expect(controller.currentLibrary, isNull);
      expect(unavailable?.reason, 'seed_type_mismatch');
      expect(unavailable?.message, contains('isReturningUser'));
      expect(unavailable?.message, contains('bool'));
      expect(unavailable?.message, contains('null'));
    });

    test('empty host seed leaves declared defaults intact', () async {
      FlowUnavailableError? unavailable;
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: _StaticFlowResolver(
          _resolvedFlow(
            document: _hostSeedDecisionDocument(defaultValue: false),
          ),
        ),
        // An empty (but non-null) seed is a clean no-op: the flow loads and the
        // declaration default drives the decision.
        initialState: const _MapSeed({}),
        actions: null,
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (error) => unavailable = error,
      );

      await controller.load();

      expect(unavailable, isNull);
      expect(controller.currentScreenId, 'welcome');
    });

    test('host seed routes a decision via the typed-builder map shape',
        () async {
      // End-to-end: a builder-shaped seed (the omit-null `toFlowState()` shape
      // codegen emits) flows through the controller's validate + overlay and
      // drives a decision(). Ties the producer (the codegen golden asserts the
      // builder emits exactly this body) to the consumer (the runtime here).
      Future<String?> routeFor(_BuilderShapedSeed seed) async {
        final controller = RestageFlowController<_FirstRunResult>(
          flow: _flowRef,
          resolver: _StaticFlowResolver(
            _resolvedFlow(document: _hostSeedDecisionDocument()),
          ),
          initialState: seed,
          actions: null,
          onEvent: (_) {},
          onComplete: (_) {},
          onUnavailable: (_) {},
        );
        await controller.load();
        return controller.currentScreenId;
      }

      // Field set -> builder emits {'isReturningUser': true} -> routes to the
      // seeded branch.
      expect(
        await routeFor(const _BuilderShapedSeed(isReturningUser: true)),
        'profile',
      );
      // Field omitted -> builder emits {} -> the decision sees no value ->
      // default branch.
      expect(await routeFor(const _BuilderShapedSeed()), 'welcome');
    });

    test('missing event state write source fails closed', () async {
      FlowUnavailableError? unavailable;
      final resolver = _StaticFlowResolver(
        _resolvedFlow(
          document: _document(
            flowState: const {
              'isPro': FlowStateDeclaration(
                type: FlowDataType.bool,
                classification: FlowStateClassification.internal,
              ),
            },
            states: const {
              'welcome': ScreenFlowState(
                screen: 'welcome',
                on: {
                  'next': GotoFlowTransition(
                    'done',
                    stateWrites: {
                      'isPro': FlowStateWrite(
                        type: FlowDataType.bool,
                        value: EventFlowValueSource(key: 'missing'),
                      ),
                    },
                  ),
                },
              ),
              'done': EndFlowState(result: {'completed': true}),
            },
          ),
        ),
      );
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: null,
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (error) => unavailable = error,
      );

      await controller.load();
      controller.handleEvent('next', const <String, Object?>{});
      await _drainFlowTasks();

      expect(unavailable?.reason, 'state_write_unavailable');
    });

    test('action result state write drives decision branch', () async {
      _FirstRunResult? completed;
      final resolver = _StaticFlowResolver(
        _resolvedFlow(
          document: _document(
            actions: {
              'requestNotifications': _actionContract(
                resultSchema: _notificationResultSchema,
              ),
            },
            flowState: const {
              'notificationsOn': FlowStateDeclaration(
                type: FlowDataType.bool,
                classification: FlowStateClassification.internal,
              ),
            },
            outbound: const FlowOutboundDeclarations(
              terminalResult: FlowOutboundPayloadDeclaration(
                fields: {
                  'completed': FlowOutboundField(
                    type: FlowDataType.bool,
                    ref: EventFlowOutboundRef(key: 'completed'),
                  ),
                },
              ),
            ),
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
                    target: 'branch',
                    stateWrites: {
                      'notificationsOn': FlowStateWrite(
                        type: FlowDataType.bool,
                        value: ActionResultFlowValueSource(key: 'granted'),
                      ),
                    },
                  ),
                },
              ),
              'branch': DecisionFlowState(
                branches: [
                  FlowBranch(
                    when: FlowBranchPredicate(
                      fields: {
                        'notificationsOn': EqualsFlowPredicateCondition(
                          value: LiteralFlowValueSource(
                            type: FlowDataType.bool,
                            value: true,
                          ),
                        ),
                      },
                    ),
                    target: 'done',
                  ),
                ],
                defaultBranch: FlowBranchTarget(target: 'failed'),
              ),
              'done': EndFlowState(result: {'completed': true}),
              'failed': EndFlowState(result: {'completed': false}),
            },
          ),
        ),
      );
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: _TestActionRegistry({
          'requestNotifications': FlowActionBinding<void, _PermissionResult>(
            descriptor: FlowActionDescriptor<void, _PermissionResult>(
              actionName: 'requestNotifications',
              contractVersion: 1,
              argsSchema: _emptyArgsSchema,
              resultSchema: _notificationResultSchema,
              minClient: 3,
              idempotent: false,
            ),
            actionName: 'requestNotifications',
            contractVersion: 1,
            argsSchema: _emptyArgsSchema,
            resultSchema: _notificationResultSchema,
            minClient: 3,
            idempotent: false,
            handler: (_, __) => const _PermissionResult(granted: true),
            decodeArgs: (_) {},
            encodeResult: (result) => {'granted': result.granted},
          ),
        }),
        onEvent: (_) {},
        onComplete: (result) => completed = result,
        onUnavailable: (_) {},
      );

      await controller.load();
      controller.handleEvent('request', const <String, Object?>{});
      await _drainFlowTasks();

      expect(completed?.completed, isTrue);
    });

    test('graph documents do not fall back from state refs to terminal result',
        () async {
      FlowUnavailableError? unavailable;
      final resolver = _StaticFlowResolver(
        _resolvedFlow(
          document: _document(
            flowState: const {
              'completed': FlowStateDeclaration(
                type: FlowDataType.bool,
                classification: FlowStateClassification.exportable,
              ),
              'visited': FlowStateDeclaration(
                type: FlowDataType.bool,
                classification: FlowStateClassification.internal,
              ),
            },
            outbound: const FlowOutboundDeclarations(
              terminalResult: FlowOutboundPayloadDeclaration(
                fields: {
                  'completed': FlowOutboundField(
                    type: FlowDataType.bool,
                    ref: StateFlowOutboundRef(key: 'completed'),
                  ),
                },
              ),
            ),
            states: const {
              'welcome': ScreenFlowState(
                screen: 'welcome',
                on: {
                  'finish': GotoFlowTransition(
                    'done',
                    stateWrites: {
                      'visited': FlowStateWrite(
                        type: FlowDataType.bool,
                        value: LiteralFlowValueSource(
                          type: FlowDataType.bool,
                          value: true,
                        ),
                      ),
                    },
                  ),
                },
              ),
              'done': EndFlowState(result: {'completed': true}),
            },
          ),
        ),
      );
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: null,
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (error) => unavailable = error,
      );

      await controller.load();
      controller.handleEvent('finish', const <String, Object?>{});
      await _drainFlowTasks();

      expect(unavailable?.reason, 'result_decode_failed');
    });

    test('sub-flow passes explicit input and routes filtered child completion',
        () async {
      _FirstRunResult? completed;
      FlowUnavailableError? unavailable;
      final events = <RestageEvent>[];
      final childDocument = _profileChildDocument();
      final childHash = _documentHash(childDocument);
      final parentDocument = _document(
        flowState: const {
          'isPro': FlowStateDeclaration(
            type: FlowDataType.bool,
            classification: FlowStateClassification.internal,
          ),
          'completed': FlowStateDeclaration(
            type: FlowDataType.bool,
            classification: FlowStateClassification.exportable,
          ),
        },
        outbound: const FlowOutboundDeclarations(
          subFlowResult: FlowOutboundPayloadDeclaration(
            fields: {
              'accepted': FlowOutboundField(
                type: FlowDataType.bool,
                ref: EventFlowOutboundRef(key: 'accepted'),
              ),
            },
          ),
          terminalResult: FlowOutboundPayloadDeclaration(
            fields: {
              'completed': FlowOutboundField(
                type: FlowDataType.bool,
                ref: StateFlowOutboundRef(key: 'completed'),
              ),
            },
          ),
        ),
        states: {
          'welcome': const ScreenFlowState(
            screen: 'welcome',
            on: {
              'next': GotoFlowTransition(
                'profile',
                stateWrites: {
                  'isPro': FlowStateWrite(
                    type: FlowDataType.bool,
                    value: EventFlowValueSource(key: 'isPro'),
                  ),
                },
              ),
            },
          ),
          'profile': SubFlowState(
            flow: 'profile_child',
            version: 1,
            schemaVersion: 1,
            minClient: 3,
            contentHash: childHash,
            input: const {
              'parentIsPro': StateFlowValueSource(key: 'isPro'),
            },
            onComplete: const [
              FlowBranch(
                when: FlowBranchPredicate(
                  fields: {
                    'accepted': EqualsFlowPredicateCondition(
                      value: LiteralFlowValueSource(
                        type: FlowDataType.bool,
                        value: true,
                      ),
                    ),
                  },
                ),
                target: 'done',
                stateWrites: {
                  'completed': FlowStateWrite(
                    type: FlowDataType.bool,
                    value: SubFlowResultFlowValueSource(key: 'accepted'),
                  ),
                },
              ),
            ],
            defaultBranch: const FlowBranchTarget(
              target: 'failed',
              stateWrites: {
                'completed': FlowStateWrite(
                  type: FlowDataType.bool,
                  value: LiteralFlowValueSource(
                    type: FlowDataType.bool,
                    value: false,
                  ),
                ),
              },
            ),
          ),
          'done': const EndFlowState(result: {}),
          'failed': const EndFlowState(result: {}),
        },
      );
      final resolver = _MapFlowResolver({
        'first_run': _resolvedFlow(document: parentDocument),
        'profile_child': _resolvedFlow(
          document: childDocument,
          contentHash: childHash,
        ),
      });
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: null,
        onEvent: events.add,
        onComplete: (result) => completed = result,
        onUnavailable: (error) => unavailable = error,
      );

      await controller.load();
      controller.handleEvent('next', const {'isPro': true});
      await _drainFlowTasks();

      expect(unavailable, isNull);
      expect(completed?.completed, isTrue);
      final started = events.whereType<FlowStarted>().toList();
      expect(started, hasLength(2));
      expect(started.first.flowId, 'first_run');
      expect(started.last.flowId, 'profile_child');
      expect(started.first.flowSessionId, isNotNull);
      expect(started.last.flowSessionId, isNot(started.first.flowSessionId));
      expect(started.last.parentFlowSessionId, started.first.flowSessionId);
      expect(events.whereType<FlowCompleted>().map((event) => event.flowId), [
        'profile_child',
        'first_run',
      ]);
    });

    test('sub-flow unavailable branch completes parent without raw child error',
        () async {
      _FirstRunResult? completed;
      FlowUnavailableError? unavailable;
      final parentDocument = _document(
        initial: 'profile',
        flowState: const {
          'completed': FlowStateDeclaration(
            type: FlowDataType.bool,
            classification: FlowStateClassification.exportable,
          ),
        },
        outbound: const FlowOutboundDeclarations(
          terminalResult: FlowOutboundPayloadDeclaration(
            fields: {
              'completed': FlowOutboundField(
                type: FlowDataType.bool,
                ref: StateFlowOutboundRef(key: 'completed'),
              ),
            },
          ),
        ),
        states: {
          'profile': SubFlowState(
            flow: 'missing_child',
            version: 1,
            schemaVersion: 1,
            minClient: 3,
            contentHash: _missingFlowHash,
            input: const {},
            onComplete: const [],
            defaultBranch: const FlowBranchTarget(target: 'done'),
            subFlowUnavailable: const FlowBranchTarget(
              target: 'failed',
              stateWrites: {
                'completed': FlowStateWrite(
                  type: FlowDataType.bool,
                  value: LiteralFlowValueSource(
                    type: FlowDataType.bool,
                    value: false,
                  ),
                ),
              },
            ),
          ),
          'failed': const EndFlowState(result: {}),
          'done': const EndFlowState(result: {}),
        },
      );
      final resolver = _MapFlowResolver({
        'first_run': _resolvedFlow(document: parentDocument),
      });
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: null,
        onEvent: (_) {},
        onComplete: (result) => completed = result,
        onUnavailable: (error) => unavailable = error,
      );

      await controller.load();
      await _drainFlowTasks();

      expect(unavailable, isNull);
      expect(completed?.completed, isFalse);
    });

    test('sub-flow unavailable without branch fails parent closed', () async {
      FlowUnavailableError? unavailable;
      final parentDocument = _document(
        initial: 'profile',
        states: {
          'profile': SubFlowState(
            flow: 'missing_child',
            version: 1,
            schemaVersion: 1,
            minClient: 3,
            contentHash: _missingFlowHash,
            input: const {},
            onComplete: const [],
            defaultBranch: const FlowBranchTarget(target: 'done'),
          ),
          'done': const EndFlowState(result: {'completed': true}),
        },
      );
      final resolver = _MapFlowResolver({
        'first_run': _resolvedFlow(document: parentDocument),
      });
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: null,
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (error) => unavailable = error,
      );

      await controller.load();
      await _drainFlowTasks();

      expect(unavailable?.flowId, 'first_run');
      expect(unavailable?.reason, 'sub_flow_unavailable');
    });

    test('sub-flow content-hash mismatch fails parent closed', () async {
      _FirstRunResult? completed;
      FlowUnavailableError? unavailable;
      final childDocument = _profileChildDocument();
      final childHash = _documentHash(childDocument);
      final parentDocument = _document(
        initial: 'profile',
        states: {
          'profile': SubFlowState(
            flow: 'profile_child',
            version: 1,
            schemaVersion: 1,
            minClient: 3,
            contentHash: childHash,
            input: const {},
            onComplete: const [],
            defaultBranch: const FlowBranchTarget(target: 'done'),
          ),
          'done': const EndFlowState(result: {'completed': true}),
        },
      );
      final resolver = _MapFlowResolver({
        'first_run': _resolvedFlow(document: parentDocument),
        // Resolver returns the pinned child document but with a different
        // content hash than the SubFlowState pin: the hash pin must reject it.
        'profile_child': _resolvedFlow(
          document: childDocument,
          contentHash: _missingFlowHash,
        ),
      });
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: null,
        onEvent: (_) {},
        onComplete: (result) => completed = result,
        onUnavailable: (error) => unavailable = error,
      );

      await controller.load();
      await _drainFlowTasks();

      expect(unavailable?.reason, 'sub_flow_unavailable');
      expect(completed, isNull);
    });

    test('sub-flow version mismatch fails parent closed', () async {
      _FirstRunResult? completed;
      FlowUnavailableError? unavailable;
      final childDocument = _profileChildDocument();
      final childHash = _documentHash(childDocument);
      final parentDocument = _document(
        initial: 'profile',
        states: {
          'profile': SubFlowState(
            flow: 'profile_child',
            // Pin a version the resolved child (version 1) does not satisfy.
            version: 2,
            schemaVersion: 1,
            minClient: 3,
            contentHash: childHash,
            input: const {},
            onComplete: const [],
            defaultBranch: const FlowBranchTarget(target: 'done'),
          ),
          'done': const EndFlowState(result: {'completed': true}),
        },
      );
      final resolver = _MapFlowResolver({
        'first_run': _resolvedFlow(document: parentDocument),
        'profile_child': _resolvedFlow(
          document: childDocument,
          contentHash: childHash,
        ),
      });
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: null,
        onEvent: (_) {},
        onComplete: (result) => completed = result,
        onUnavailable: (error) => unavailable = error,
      );

      await controller.load();
      await _drainFlowTasks();

      expect(unavailable?.reason, 'sub_flow_unavailable');
      expect(completed, isNull);
    });

    test('sub-flow minClient mismatch fails parent closed', () async {
      _FirstRunResult? completed;
      FlowUnavailableError? unavailable;
      final childDocument = _profileChildDocument();
      final childHash = _documentHash(childDocument);
      final parentDocument = _document(
        initial: 'profile',
        states: {
          'profile': SubFlowState(
            flow: 'profile_child',
            version: 1,
            schemaVersion: 1,
            // Pin a client floor the resolved child (minClient 3) does not meet.
            minClient: 99,
            contentHash: childHash,
            input: const {},
            onComplete: const [],
            defaultBranch: const FlowBranchTarget(target: 'done'),
          ),
          'done': const EndFlowState(result: {'completed': true}),
        },
      );
      final resolver = _MapFlowResolver({
        'first_run': _resolvedFlow(document: parentDocument),
        'profile_child': _resolvedFlow(
          document: childDocument,
          contentHash: childHash,
        ),
      });
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: null,
        onEvent: (_) {},
        onComplete: (result) => completed = result,
        onUnavailable: (error) => unavailable = error,
      );

      await controller.load();
      await _drainFlowTasks();

      expect(unavailable?.reason, 'sub_flow_unavailable');
      expect(completed, isNull);
    });

    test('sub-flow undeclared input fails parent closed', () async {
      _FirstRunResult? completed;
      FlowUnavailableError? unavailable;
      final childDocument = _profileChildDocument();
      final childHash = _documentHash(childDocument);
      final parentDocument = _document(
        initial: 'profile',
        states: {
          'profile': SubFlowState(
            flow: 'profile_child',
            version: 1,
            schemaVersion: 1,
            minClient: 3,
            contentHash: childHash,
            // Pass an input key the child does not declare in its flow state.
            input: const {
              'notDeclared': LiteralFlowValueSource(
                type: FlowDataType.bool,
                value: true,
              ),
            },
            onComplete: const [],
            defaultBranch: const FlowBranchTarget(target: 'done'),
          ),
          'done': const EndFlowState(result: {'completed': true}),
        },
      );
      final resolver = _MapFlowResolver({
        'first_run': _resolvedFlow(document: parentDocument),
        'profile_child': _resolvedFlow(
          document: childDocument,
          contentHash: childHash,
        ),
      });
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: null,
        onEvent: (_) {},
        onComplete: (result) => completed = result,
        onUnavailable: (error) => unavailable = error,
      );

      await controller.load();
      await _drainFlowTasks();

      // An input key the child does not declare fails the parent closed; the
      // child session is never entered.
      expect(unavailable?.reason, 'sub_flow_unavailable');
      expect(completed, isNull);
    });

    test('sub-flow failure after child frame push resumes parent fallback',
        () async {
      _FirstRunResult? completed;
      FlowUnavailableError? unavailable;
      final childDocument = _document(
        flow: 'profile_child',
        states: const {
          'welcome': ScreenFlowState(
            screen: 'welcome',
            on: {'finish': FlowTransition.goto('done')},
          ),
          'done': EndFlowState(result: {'accepted': true}),
        },
      );
      final childHash = _documentHash(childDocument);
      final parentDocument = _document(
        initial: 'profile',
        flowState: const {
          'completed': FlowStateDeclaration(
            type: FlowDataType.bool,
            classification: FlowStateClassification.exportable,
          ),
        },
        outbound: const FlowOutboundDeclarations(
          terminalResult: FlowOutboundPayloadDeclaration(
            fields: {
              'completed': FlowOutboundField(
                type: FlowDataType.bool,
                ref: StateFlowOutboundRef(key: 'completed'),
              ),
            },
          ),
        ),
        states: {
          'profile': SubFlowState(
            flow: 'profile_child',
            version: 1,
            schemaVersion: 1,
            minClient: 3,
            contentHash: childHash,
            input: const {},
            onComplete: const [],
            defaultBranch: const FlowBranchTarget(target: 'done'),
            subFlowUnavailable: const FlowBranchTarget(
              target: 'welcome',
              stateWrites: {
                'completed': FlowStateWrite(
                  type: FlowDataType.bool,
                  value: LiteralFlowValueSource(
                    type: FlowDataType.bool,
                    value: false,
                  ),
                ),
              },
            ),
          ),
          'welcome': const ScreenFlowState(
            screen: 'welcome',
            on: {'finish': FlowTransition.goto('done')},
          ),
          'done': const EndFlowState(result: {}),
        },
      );
      final resolver = _MapFlowResolver({
        'first_run': _resolvedFlow(document: parentDocument),
        'profile_child': ResolvedFlow(
          document: childDocument,
          screenBlobs: const {},
          contentHash: childHash,
          cacheHit: false,
        ),
      });
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: null,
        onEvent: (_) {},
        onComplete: (result) => completed = result,
        onUnavailable: (error) => unavailable = error,
      );

      await controller.load();
      await _drainFlowTasks();

      expect(unavailable, isNull);
      expect(controller.currentScreenId, 'welcome');

      controller.handleEvent('finish', const <String, Object?>{});
      await _drainFlowTasks();

      expect(completed?.completed, isFalse);
    });

    test('sub-flow uses child action bindings after root action bindings',
        () async {
      _FirstRunResult? completed;
      FlowUnavailableError? unavailable;
      var rootInvocations = 0;
      var childInvocations = 0;
      final childDocument = _document(
        flow: 'profile_child',
        actions: {
          'acceptProfile': _actionContract(actionName: 'acceptProfile'),
        },
        outbound: const FlowOutboundDeclarations(
          terminalResult: FlowOutboundPayloadDeclaration(
            fields: {
              'accepted': FlowOutboundField(
                type: FlowDataType.bool,
                ref: EventFlowOutboundRef(key: 'accepted'),
              ),
            },
          ),
        ),
        states: const {
          'welcome': ScreenFlowState(
            screen: 'welcome',
            on: {
              'accept': ActionFlowTransition(
                action: 'acceptProfile',
                resultPredicate: BoolEqualsActionResultPredicate(value: true),
                target: 'done',
              ),
            },
          ),
          'done': EndFlowState(result: {'accepted': true}),
        },
      );
      final childHash = _documentHash(childDocument);
      final parentDocument = _document(
        actions: {
          'startProfile': _actionContract(actionName: 'startProfile'),
        },
        flowState: const {
          'completed': FlowStateDeclaration(
            type: FlowDataType.bool,
            classification: FlowStateClassification.exportable,
          ),
        },
        outbound: const FlowOutboundDeclarations(
          subFlowResult: FlowOutboundPayloadDeclaration(
            fields: {
              'accepted': FlowOutboundField(
                type: FlowDataType.bool,
                ref: EventFlowOutboundRef(key: 'accepted'),
              ),
            },
          ),
          terminalResult: FlowOutboundPayloadDeclaration(
            fields: {
              'completed': FlowOutboundField(
                type: FlowDataType.bool,
                ref: StateFlowOutboundRef(key: 'completed'),
              ),
            },
          ),
        ),
        states: {
          'welcome': const ScreenFlowState(
            screen: 'welcome',
            on: {
              'start': ActionFlowTransition(
                action: 'startProfile',
                resultPredicate: BoolEqualsActionResultPredicate(value: true),
                target: 'profile',
              ),
            },
          ),
          'profile': SubFlowState(
            flow: 'profile_child',
            version: 1,
            schemaVersion: 1,
            minClient: 3,
            contentHash: childHash,
            input: const {},
            onComplete: const [
              FlowBranch(
                when: FlowBranchPredicate(
                  fields: {
                    'accepted': EqualsFlowPredicateCondition(
                      value: LiteralFlowValueSource(
                        type: FlowDataType.bool,
                        value: true,
                      ),
                    ),
                  },
                ),
                target: 'done',
                stateWrites: {
                  'completed': FlowStateWrite(
                    type: FlowDataType.bool,
                    value: SubFlowResultFlowValueSource(key: 'accepted'),
                  ),
                },
              ),
            ],
            defaultBranch: const FlowBranchTarget(
              target: 'failed',
              stateWrites: {
                'completed': FlowStateWrite(
                  type: FlowDataType.bool,
                  value: LiteralFlowValueSource(
                    type: FlowDataType.bool,
                    value: false,
                  ),
                ),
              },
            ),
          ),
          'done': const EndFlowState(result: {}),
          'failed': const EndFlowState(result: {}),
        },
      );
      final resolver = _MapFlowResolver({
        'first_run': _resolvedFlow(document: parentDocument),
        'profile_child': _resolvedFlow(
          document: childDocument,
          contentHash: childHash,
        ),
      });
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: _SequencedActionRegistry([
          {
            'startProfile': _actionBinding(
              actionName: 'startProfile',
              handler: (_, __) {
                rootInvocations += 1;
                return true;
              },
            ),
          },
          {
            'acceptProfile': _actionBinding(
              actionName: 'acceptProfile',
              handler: (_, __) {
                childInvocations += 1;
                return true;
              },
            ),
          },
        ]),
        onEvent: (_) {},
        onComplete: (result) => completed = result,
        onUnavailable: (error) => unavailable = error,
      );

      await controller.load();
      controller.handleEvent('start', const <String, Object?>{});
      await _drainFlowTasks();
      controller.handleEvent('accept', const <String, Object?>{});
      await _drainFlowTasks();

      expect(unavailable, isNull);
      expect(completed?.completed, isTrue);
      expect(rootInvocations, 1);
      expect(childInvocations, 1);
    });

    test('sub-flow action failure takes parent unavailable branch', () async {
      _FirstRunResult? completed;
      FlowUnavailableError? unavailable;
      final childDocument = _document(
        flow: 'profile_child',
        actions: {
          'acceptProfile': _actionContract(actionName: 'acceptProfile'),
        },
        states: const {
          'welcome': ScreenFlowState(
            screen: 'welcome',
            on: {
              'accept': ActionFlowTransition(
                action: 'acceptProfile',
                resultPredicate: BoolEqualsActionResultPredicate(value: true),
                target: 'done',
              ),
            },
          ),
          'done': EndFlowState(result: {'accepted': true}),
        },
      );
      final childHash = _documentHash(childDocument);
      final parentDocument = _document(
        initial: 'profile',
        flowState: const {
          'completed': FlowStateDeclaration(
            type: FlowDataType.bool,
            classification: FlowStateClassification.exportable,
          ),
        },
        outbound: const FlowOutboundDeclarations(
          terminalResult: FlowOutboundPayloadDeclaration(
            fields: {
              'completed': FlowOutboundField(
                type: FlowDataType.bool,
                ref: StateFlowOutboundRef(key: 'completed'),
              ),
            },
          ),
        ),
        states: {
          'profile': SubFlowState(
            flow: 'profile_child',
            version: 1,
            schemaVersion: 1,
            minClient: 3,
            contentHash: childHash,
            input: const {},
            onComplete: const [],
            defaultBranch: const FlowBranchTarget(target: 'done'),
            subFlowUnavailable: const FlowBranchTarget(
              target: 'fallback',
              stateWrites: {
                'completed': FlowStateWrite(
                  type: FlowDataType.bool,
                  value: LiteralFlowValueSource(
                    type: FlowDataType.bool,
                    value: false,
                  ),
                ),
              },
            ),
          ),
          'fallback': const ScreenFlowState(
            screen: 'welcome',
            on: {'finish': FlowTransition.goto('done')},
          ),
          'done': const EndFlowState(result: {}),
        },
      );
      final resolver = _MapFlowResolver({
        'first_run': _resolvedFlow(document: parentDocument),
        'profile_child': _resolvedFlow(
          document: childDocument,
          contentHash: childHash,
        ),
      });
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: _TestActionRegistry({
          'acceptProfile': _actionBinding(
            actionName: 'acceptProfile',
            handler: (_, __) => throw StateError('child action failed'),
          ),
        }),
        onEvent: (_) {},
        onComplete: (result) => completed = result,
        onUnavailable: (error) => unavailable = error,
      );

      await controller.load();
      await _drainFlowTasks();
      controller.handleEvent('accept', const <String, Object?>{});
      await _drainFlowTasks();

      expect(unavailable, isNull);
      expect(controller.currentScreenId, 'fallback');

      controller.handleEvent('finish', const <String, Object?>{});
      await _drainFlowTasks();

      expect(completed?.completed, isFalse);
    });

    test('late sub-flow action result after parent dispose is discarded',
        () async {
      _FirstRunResult? completed;
      FlowUnavailableError? unavailable;
      final completer = Completer<bool>();
      final childDocument = _document(
        flow: 'profile_child',
        actions: {'requestNotifications': _actionContract()},
        states: const {
          'welcome': ScreenFlowState(
            screen: 'welcome',
            on: {
              'request': ActionFlowTransition(
                action: 'requestNotifications',
                resultPredicate: BoolEqualsActionResultPredicate(value: true),
                target: 'done',
              ),
            },
          ),
          'done': EndFlowState(result: {'accepted': true}),
        },
        outbound: const FlowOutboundDeclarations(
          terminalResult: FlowOutboundPayloadDeclaration(
            fields: {
              'accepted': FlowOutboundField(
                type: FlowDataType.bool,
                ref: EventFlowOutboundRef(key: 'accepted'),
              ),
            },
          ),
        ),
      );
      final childHash = _documentHash(childDocument);
      final parentDocument = _document(
        initial: 'profile',
        outbound: const FlowOutboundDeclarations(
          subFlowResult: FlowOutboundPayloadDeclaration(
            fields: {
              'accepted': FlowOutboundField(
                type: FlowDataType.bool,
                ref: EventFlowOutboundRef(key: 'accepted'),
              ),
            },
          ),
        ),
        states: {
          'profile': SubFlowState(
            flow: 'profile_child',
            version: 1,
            schemaVersion: 1,
            minClient: 3,
            contentHash: childHash,
            input: const {},
            onComplete: const [],
            defaultBranch: const FlowBranchTarget(target: 'done'),
          ),
          'done': const EndFlowState(result: {'completed': true}),
        },
      );
      final resolver = _MapFlowResolver({
        'first_run': _resolvedFlow(document: parentDocument),
        'profile_child': _resolvedFlow(
          document: childDocument,
          contentHash: childHash,
        ),
      });
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: _MatchingActionRegistry(
          handler: (_, __) => completer.future,
        ),
        onEvent: (_) {},
        onComplete: (result) => completed = result,
        onUnavailable: (error) => unavailable = error,
      );

      await controller.load();
      expect(controller.currentScreenId, 'welcome');
      controller.handleEvent('request', const <String, Object?>{});
      controller.dispose();
      completer.complete(true);
      await _drainFlowTasks();

      expect(completed, isNull);
      expect(unavailable, isNull);
    });

    test('handler exception fails closed through unavailable', () async {
      FlowUnavailableError? unavailable;
      final resolver = _StaticFlowResolver(
        _actionResolvedFlow(),
      );
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: _MatchingActionRegistry(
          handler: (_, __) => throw StateError('host failed'),
        ),
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (error) => unavailable = error,
      );

      await controller.load();
      controller.handleEvent('request', const <String, Object?>{});
      await Future<void>.delayed(Duration.zero);

      expect(controller.currentLibrary, isNull);
      expect(unavailable?.reason, 'action_handler_failed');
      expect(unavailable?.message, contains('requestNotifications'));
    });

    test('in-flight action gates duplicate events', () async {
      final completer = Completer<bool>();
      var invocations = 0;
      final resolver = _StaticFlowResolver(
        _actionResolvedFlow(),
      );
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: _MatchingActionRegistry(
          handler: (_, __) {
            invocations += 1;
            return completer.future;
          },
        ),
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (_) {},
      );

      await controller.load();
      controller.handleEvent('request', const <String, Object?>{});
      controller.handleEvent('request', const <String, Object?>{});
      await Future<void>.delayed(Duration.zero);

      expect(invocations, 1);

      completer.complete(false);
      await Future<void>.delayed(Duration.zero);
    });

    test('late action result after dispose is discarded', () async {
      _FirstRunResult? completed;
      FlowUnavailableError? unavailable;
      final completer = Completer<bool>();
      final resolver = _StaticFlowResolver(
        _actionResolvedFlow(),
      );
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: _MatchingActionRegistry(
          handler: (_, __) => completer.future,
        ),
        onEvent: (_) {},
        onComplete: (result) => completed = result,
        onUnavailable: (error) => unavailable = error,
      );

      await controller.load();
      controller.handleEvent('request', const <String, Object?>{});
      controller.dispose();
      completer.complete(true);
      await Future<void>.delayed(Duration.zero);

      expect(completed, isNull);
      expect(unavailable, isNull);
    });

    test('mints a fresh currentScreenEntryId on each screen entry', () async {
      final resolver = _StaticFlowResolver(_resolvedFlow());
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: resolver,
        actions: null,
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (_) {},
      );
      addTearDown(controller.dispose);

      expect(controller.currentScreenEntryId, isNull);

      await controller.load();
      final welcomeEntry = controller.currentScreenEntryId;
      expect(welcomeEntry, isNotNull);
      expect(controller.currentScreenId, 'welcome');

      controller.handleEvent('next', const <String, Object?>{});
      await Future<void>.delayed(Duration.zero);

      expect(controller.currentScreenId, 'profile');
      expect(controller.currentScreenEntryId, isNotNull);
      expect(controller.currentScreenEntryId, isNot(welcomeEntry));
    });

    test('currentScreenEntryId is unique across controller instances',
        () async {
      final first = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: _StaticFlowResolver(_resolvedFlow()),
        actions: null,
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (_) {},
      );
      addTearDown(first.dispose);
      final second = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: _StaticFlowResolver(_resolvedFlow()),
        actions: null,
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (_) {},
      );
      addTearDown(second.dispose);

      await first.load();
      await second.load();

      // A stale event captured against one controller's entry id must never
      // collide with another controller's current entry id (the swap hole).
      expect(first.currentScreenEntryId, isNotNull);
      expect(second.currentScreenEntryId, isNotNull);
      expect(first.currentScreenEntryId, isNot(second.currentScreenEntryId));
    });

    test('reportRenderFailure fails the flow closed through the controller',
        () async {
      FlowUnavailableError? unavailable;
      final events = <RestageEvent>[];
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: _StaticFlowResolver(_resolvedFlow()),
        actions: null,
        onEvent: events.add,
        onComplete: (_) {},
        onUnavailable: (error) => unavailable = error,
      );
      addTearDown(controller.dispose);

      await controller.load();
      expect(controller.currentScreenEntryId, isNotNull);

      controller.reportRenderFailure(StateError('boom'));

      expect(unavailable?.reason, 'render_failed');
      expect(unavailable?.message, contains('threw during build'));
      expect(controller.currentScreenEntryId, isNull);
      expect(controller.currentScreenId, isNull);
      expect(
          events.whereType<FlowUnavailable>().single.reason, 'render_failed');

      // After failing closed the controller no longer accepts events.
      controller.handleEvent('next', const <String, Object?>{});
      await Future<void>.delayed(Duration.zero);
      expect(controller.currentScreenId, isNull);
    });

    test('reportRenderFailure is a no-op once the flow has completed',
        () async {
      FlowUnavailableError? unavailable;
      _FirstRunResult? completed;
      final events = <RestageEvent>[];
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: _StaticFlowResolver(_resolvedFlow()),
        actions: null,
        onEvent: events.add,
        onComplete: (result) => completed = result,
        onUnavailable: (error) => unavailable = error,
      );
      addTearDown(controller.dispose);

      await controller.load();
      controller.handleEvent('next', const <String, Object?>{});
      await Future<void>.delayed(Duration.zero);
      controller.handleEvent('finish', const <String, Object?>{});
      await Future<void>.delayed(Duration.zero);
      expect(completed?.completed, isTrue);

      // A late render error from a lingering completed screen must NOT
      // retroactively fail a flow that already delivered its result.
      controller.reportRenderFailure(StateError('late error after completion'));

      expect(unavailable, isNull);
      expect(events.whereType<FlowUnavailable>(), isEmpty);
      expect(events.whereType<FlowCompleted>().length, 1);
    });
  });

  group('RestageFlowController back navigation', () {
    test('canBack reflects the per-frame screen history', () async {
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: _StaticFlowResolver(_resolvedFlow()),
        actions: null,
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (_) {},
      );
      addTearDown(controller.dispose);

      await controller.load();
      // On the first screen there is no prior screen to go back to.
      expect(controller.currentScreenId, 'welcome');
      expect(controller.canBack, isFalse);

      // Forward to profile: now there is history.
      controller.handleEvent('next', const <String, Object?>{});
      await _drainFlowTasks();
      expect(controller.currentScreenId, 'profile');
      expect(controller.canBack, isTrue);
    });

    test('back restores the prior screen and its original entry id', () async {
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: _StaticFlowResolver(_resolvedFlow()),
        actions: null,
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (_) {},
      );
      addTearDown(controller.dispose);

      await controller.load();
      final welcomeEntryId = controller.currentScreenEntryId;
      expect(controller.currentScreenId, 'welcome');

      controller.handleEvent('next', const <String, Object?>{});
      await _drainFlowTasks();
      expect(controller.currentScreenId, 'profile');
      expect(controller.currentScreenEntryId, isNot(welcomeEntryId));

      controller.back();
      expect(controller.currentScreenId, 'welcome');
      // Restores the SAME entry id, so the rendering surface restores the
      // still-mounted welcome instance (its state preserved) rather than
      // re-decoding it.
      expect(controller.currentScreenEntryId, welcomeEntryId);
      expect(controller.canBack, isFalse);
    });

    test('back is a no-op on the first screen (no history)', () async {
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: _StaticFlowResolver(_resolvedFlow()),
        actions: null,
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (_) {},
      );
      addTearDown(controller.dispose);

      await controller.load();
      expect(controller.canBack, isFalse);
      controller.back();
      expect(controller.currentScreenId, 'welcome');
    });

    test('the reserved back event pops when the screen has no back handler',
        () async {
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: _StaticFlowResolver(_resolvedFlow()),
        actions: null,
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (_) {},
      );
      addTearDown(controller.dispose);

      await controller.load();
      controller.handleEvent('next', const <String, Object?>{});
      await _drainFlowTasks();
      expect(controller.currentScreenId, 'profile');

      // An in-screen `back` event with no authored `on['back']` handler falls
      // back to the default history pop.
      controller.handleEvent('back', null);
      expect(controller.currentScreenId, 'welcome');
    });

    test('an authored back handler takes precedence over the history pop',
        () async {
      _FirstRunResult? completed;
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: _StaticFlowResolver(
          _resolvedFlow(
            states: const {
              'welcome': ScreenFlowState(
                screen: 'welcome',
                on: {'next': FlowTransition.goto('profile')},
              ),
              'profile': ScreenFlowState(
                screen: 'profile',
                on: {
                  'finish': FlowTransition.goto('done'),
                  // The author redefines back on this screen to jump to done.
                  'back': FlowTransition.goto('done'),
                },
              ),
              'done': EndFlowState(result: {'completed': true}),
            },
          ),
        ),
        actions: null,
        onEvent: (_) {},
        onComplete: (result) => completed = result,
        onUnavailable: (_) {},
      );
      addTearDown(controller.dispose);

      await controller.load();
      controller.handleEvent('next', const <String, Object?>{});
      await _drainFlowTasks();
      expect(controller.currentScreenId, 'profile');

      // The authored `on['back']` transition runs instead of the history pop.
      controller.handleEvent('back', null);
      await _drainFlowTasks();
      expect(completed?.completed, isTrue);
    });

    test('skip routes the reserved skip event as a custom event', () async {
      final events = <RestageEvent>[];
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: _StaticFlowResolver(
          _resolvedFlow(
            document: _document(
              outbound: const FlowOutboundDeclarations(
                customEvents: {
                  'skip': FlowOutboundPayloadDeclaration(fields: {}),
                },
              ),
            ),
          ),
        ),
        actions: null,
        onEvent: events.add,
        onComplete: (_) {},
        onUnavailable: (_) {},
      );
      addTearDown(controller.dispose);

      await controller.load();
      expect(controller.canSkip, isTrue);
      controller.skip();
      await _drainFlowTasks();

      // skip() routes the reserved `skip` event; with a declared custom event
      // (and no authored on['skip']), it emits a FlowCustomEvent the host
      // handles (e.g. to dismiss the flow / open a paywall).
      final skips = events.whereType<FlowCustomEvent>().where(
            (event) => event.eventName == 'skip',
          );
      expect(skips, hasLength(1));
    });

    test('canSkip is false when the screen has no skip destination', () async {
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: _StaticFlowResolver(_resolvedFlow()),
        actions: null,
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (_) {},
      );
      addTearDown(controller.dispose);

      await controller.load();
      // No authored on['skip'] and no declared customEvents['skip'].
      expect(controller.canSkip, isFalse);
    });

    // SPINE (1): back across a *completed* action never re-fires it.
    test('back across a completed action never re-fires the action', () async {
      var actionCalls = 0;
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: _StaticFlowResolver(_actionThenScreenFlow()),
        actions: _MatchingActionRegistry(
          handler: (_, __) {
            actionCalls += 1;
            return true;
          },
        ),
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (_) {},
      );
      addTearDown(controller.dispose);

      await controller.load();
      expect(controller.currentScreenId, 'welcome');

      // Fire the action -> it runs once -> advances to the profile screen.
      controller.handleEvent('request', const <String, Object?>{});
      await _drainFlowTasks();
      expect(controller.currentScreenId, 'profile');
      expect(actionCalls, 1);

      // Back to the prior *screen* (welcome). The action sat *between* welcome
      // and profile and was never recorded, so back skips it structurally and
      // does NOT re-fire it.
      controller.back();
      expect(controller.currentScreenId, 'welcome');
      expect(actionCalls, 1);

      // A fresh user submission re-runs the action (a new operation) — correct,
      // and emphatically not a back re-fire.
      controller.handleEvent('request', const <String, Object?>{});
      await _drainFlowTasks();
      expect(controller.currentScreenId, 'profile');
      expect(actionCalls, 2);
    });

    // SPINE (2): back is gated while an action is in flight, just like events.
    test('back is gated while an action is in flight', () async {
      final pending = Completer<bool>();
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: _StaticFlowResolver(_actionFromProfileFlow()),
        actions: _MatchingActionRegistry(handler: (_, __) => pending.future),
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (_) {},
      );
      addTearDown(controller.dispose);

      await controller.load();
      controller.handleEvent('next', const <String, Object?>{});
      await _drainFlowTasks();
      expect(controller.currentScreenId, 'profile');
      expect(controller.canBack, isTrue);

      // Start the action; it never completes within this turn.
      controller.handleEvent('request', const <String, Object?>{});
      await _drainFlowTasks();
      expect(controller.currentScreenId, 'profile');

      // back() is gated while the action is in flight: a no-op.
      controller.back();
      expect(controller.currentScreenId, 'profile');

      // Once the action resolves (predicate false -> no transition), back is no
      // longer gated.
      pending.complete(false);
      await _drainFlowTasks();
      expect(controller.currentScreenId, 'profile');
      controller.back();
      expect(controller.currentScreenId, 'welcome');
    });

    // SPINE (3): the back-stack is in-memory only — never an outbound surface.
    test('back emits no events (the back-stack never leaves the runtime)',
        () async {
      final events = <RestageEvent>[];
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: _StaticFlowResolver(_resolvedFlow()),
        actions: null,
        onEvent: events.add,
        onComplete: (_) {},
        onUnavailable: (_) {},
      );
      addTearDown(controller.dispose);

      await controller.load();
      controller.handleEvent('next', const <String, Object?>{});
      await _drainFlowTasks();
      final eventsBeforeBack = events.length;

      controller.back();
      await _drainFlowTasks();

      // back() only restored a prior screen and notified listeners — it emitted
      // no RestageEvent at all, so no back-stack/history data crossed any
      // outbound surface (no FlowCustomEvent, no action args, no result).
      expect(events.length, eventsBeforeBack);
      expect(events.whereType<FlowCustomEvent>(), isEmpty);
    });

    // SPINE (4): capability-floor / fail-closed is unaffected by back.
    test('canBack and back() are no-ops once the flow has failed closed',
        () async {
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: _StaticFlowResolver(_resolvedFlow()),
        actions: null,
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (_) {},
      );
      addTearDown(controller.dispose);

      await controller.load();
      controller.handleEvent('next', const <String, Object?>{});
      await _drainFlowTasks();
      expect(controller.canBack, isTrue);

      controller.reportRenderFailure(StateError('boom'));
      expect(controller.isUnavailable, isTrue);
      expect(controller.canBack, isFalse);
      // back() does nothing once unavailable.
      controller.back();
      expect(controller.currentScreenId, isNull);
      expect(controller.isUnavailable, isTrue);
    });

    test('the screen back-stack is bounded and evicts the oldest visit',
        () async {
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: _StaticFlowResolver(_pingPongFlow()),
        actions: null,
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (_) {},
      );
      addTearDown(controller.dispose);

      await controller.load();
      // Visit 11 screens in one frame (welcome + 10 hops). The cap is 8, so the
      // three oldest visits are evicted; 8 remain retained.
      for (var i = 0; i < 10; i++) {
        controller.handleEvent('go', const <String, Object?>{});
        await _drainFlowTasks();
      }

      // From the current screen we can back through exactly the 7 retained
      // priors before reaching the oldest retained visit (a natural barrier).
      var backs = 0;
      while (controller.canBack) {
        controller.back();
        backs += 1;
      }
      expect(backs, 7);
      expect(controller.canBack, isFalse);
    });

    // The sub-flow boundary is the (automatic) back barrier — HQ-B's
    // commit/replacement barrier, expressed by the existing graph with no
    // schema field.
    test('back does not cross a sub-flow boundary', () async {
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: _subFlowResolver(),
        actions: null,
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (_) {},
      );
      addTearDown(controller.dispose);

      await controller.load();
      // Parent welcome (its own frame has 1 screen) -> enter the sub-flow.
      expect(controller.canBack, isFalse);
      controller.handleEvent('next', const <String, Object?>{});
      await _drainFlowTasks();

      // We are now on the CHILD's first screen. canBack is false: the parent's
      // welcome screen lives in the parent frame and is not reachable across the
      // sub-flow boundary (the barrier).
      expect(controller.currentScreenId, 'welcome');
      expect(controller.canBack, isFalse);

      // Advancing within the child grows the child's own back-stack.
      controller.handleEvent('next', const <String, Object?>{});
      await _drainFlowTasks();
      expect(controller.currentScreenId, 'profile');
      expect(controller.canBack, isTrue);

      // Back stays within the child frame; it never pops into the parent.
      controller.back();
      expect(controller.currentScreenId, 'welcome');
      expect(controller.canBack, isFalse);
    });

    // The rendering surface mirrors `reachableScreenEntryIds` (the union across
    // live frames) to decide what to keep mounted. While inside a sub-flow the
    // parent's prior screen must stay reachable (the parent resumes after the
    // child completes), so the union spans both frames.
    test('reachableScreenEntryIds spans all live frames', () async {
      final controller = RestageFlowController<_FirstRunResult>(
        flow: _flowRef,
        resolver: _subFlowResolver(),
        actions: null,
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (_) {},
      );
      addTearDown(controller.dispose);

      await controller.load();
      final parentWelcomeId = controller.currentScreenEntryId;
      expect(controller.reachableScreenEntryIds, [parentWelcomeId]);

      // Enter the sub-flow -> the child's first screen.
      controller.handleEvent('next', const <String, Object?>{});
      await _drainFlowTasks();
      final childWelcomeId = controller.currentScreenEntryId;
      expect(childWelcomeId, isNot(parentWelcomeId));

      // The union keeps BOTH the parent's prior screen and the child's current
      // screen reachable, so the view holds the parent mounted for the resume.
      expect(
        controller.reachableScreenEntryIds,
        containsAll(<int?>[parentWelcomeId, childWelcomeId]),
      );
    });
  });
}

const _flowRef = OnboardingFlowRef<_FirstRunResult>(
  id: 'first_run',
  version: 1,
  minClient: 3,
  decodeResult: _FirstRunResult.decode,
);

final class _FirstRunResult {
  const _FirstRunResult({required this.completed});

  final bool completed;

  static _FirstRunResult decode(Map<String, Object?> result) {
    if (result.keys.toSet().difference({'completed'}).isNotEmpty) {
      throw const FormatException('Unexpected result keys.');
    }
    final completed = result['completed'];
    if (completed is! bool) {
      throw const FormatException('Expected completed bool.');
    }
    return _FirstRunResult(completed: completed);
  }
}

final class _StaticFlowResolver implements FlowResolver {
  const _StaticFlowResolver(this.flow);

  final ResolvedFlow flow;

  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) async => this.flow;
}

final class _MapSeed implements FlowSeed {
  const _MapSeed(this._values);

  final Map<String, Object?> _values;

  @override
  Map<String, Object?> toFlowState() => _values;
}

/// Mirrors the shape codegen emits for a generated `…Seed` builder: only
/// seedable keys as optional, nullable, typed parameters, and a `toFlowState`
/// that omits unset keys. Lets the controller e2e exercise the exact map shape
/// the codegen golden asserts the builder emits.
final class _BuilderShapedSeed implements FlowSeed {
  const _BuilderShapedSeed({this.isReturningUser});

  final bool? isReturningUser;

  @override
  Map<String, Object?> toFlowState() => {
        if (isReturningUser != null) 'isReturningUser': isReturningUser,
      };
}

final class _MapFlowResolver implements FlowResolver {
  const _MapFlowResolver(this.flows);

  final Map<String, ResolvedFlow> flows;

  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) async {
    final resolved = flows[flow.id];
    if (resolved == null) {
      throw FlowUnavailableError(
        flowId: flow.id,
        flowVersion: flow.version,
        reason: 'missing_flow_json',
        message: 'Missing flow ${flow.id}.',
      );
    }
    return resolved;
  }
}

ResolvedFlow _resolvedFlow({
  FlowDocument? document,
  Map<String, FlowActionContract>? actions,
  Map<String, FlowState>? states,
  FlowContentHash? contentHash,
}) {
  final welcome = _screenBlob('Welcome');
  final profile = _screenBlob('Profile');
  return ResolvedFlow(
    document: document ??
        _document(
          actions: actions,
          legacyTerminalResultPassthrough: true,
          states: states,
          screenHashes: {
            'welcome': FlowContentHash.compute(welcome),
            'profile': FlowContentHash.compute(profile),
          },
        ),
    screenBlobs: {
      'welcome': welcome,
      'profile': profile,
    },
    contentHash: contentHash,
    cacheHit: false,
  );
}

FlowDocument _profileChildDocument() {
  return _document(
    flow: 'profile_child',
    flowState: const {
      'parentIsPro': FlowStateDeclaration(
        type: FlowDataType.bool,
        classification: FlowStateClassification.internal,
        defaultValue: false,
      ),
    },
    outbound: const FlowOutboundDeclarations(
      terminalResult: FlowOutboundPayloadDeclaration(
        fields: {
          'accepted': FlowOutboundField(
            type: FlowDataType.bool,
            ref: EventFlowOutboundRef(key: 'accepted'),
          ),
        },
      ),
    ),
    states: const {
      'welcome': DecisionFlowState(
        branches: [
          FlowBranch(
            when: FlowBranchPredicate(
              fields: {
                'parentIsPro': EqualsFlowPredicateCondition(
                  value: LiteralFlowValueSource(
                    type: FlowDataType.bool,
                    value: true,
                  ),
                ),
              },
            ),
            target: 'accepted',
          ),
        ],
        defaultBranch: FlowBranchTarget(target: 'declined'),
      ),
      'accepted': EndFlowState(result: {'accepted': true}),
      'declined': EndFlowState(result: {'accepted': false}),
    },
  );
}

FlowContentHash _documentHash(FlowDocument document) {
  return FlowContentHash.compute(
    utf8.encode(FlowDocumentCodec.encodePrettyJson(document)),
  );
}

final _missingFlowHash = FlowContentHash.parse(
  'sha256:0000000000000000000000000000000000000000000000000000000000000000',
);

ResolvedFlow _actionResolvedFlow() {
  return _resolvedFlow(
    actions: {'requestNotifications': _actionContract()},
    states: const {
      'welcome': ScreenFlowState(
        screen: 'welcome',
        on: {
          'request': ActionFlowTransition(
            action: 'requestNotifications',
            resultPredicate: BoolEqualsActionResultPredicate(value: true),
            target: 'done',
          ),
        },
      ),
      'done': EndFlowState(result: {'completed': true}),
    },
  );
}

/// welcome --(action)--> profile (a screen): the action sits *between* two
/// screens, so backing from profile lands on welcome without re-firing it.
ResolvedFlow _actionThenScreenFlow() {
  return _resolvedFlow(
    actions: {'requestNotifications': _actionContract()},
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
  );
}

/// welcome --(goto)--> profile --(action)--> done: lets a test reach a screen
/// with back history (welcome) and then fire an action from profile.
ResolvedFlow _actionFromProfileFlow() {
  return _resolvedFlow(
    actions: {'requestNotifications': _actionContract()},
    states: const {
      'welcome': ScreenFlowState(
        screen: 'welcome',
        on: {'next': FlowTransition.goto('profile')},
      ),
      'profile': ScreenFlowState(
        screen: 'profile',
        on: {
          'request': ActionFlowTransition(
            action: 'requestNotifications',
            resultPredicate: BoolEqualsActionResultPredicate(value: true),
            target: 'done',
          ),
        },
      ),
      'done': EndFlowState(result: {'completed': true}),
    },
  );
}

/// A parent flow (welcome -> sub-flow -> done) whose sub-flow child shows two
/// screens (welcome -> profile -> done): exercises the per-frame back barrier
/// and the cross-frame reachable union.
_MapFlowResolver _subFlowResolver() {
  final childDocument = _document(
    flow: 'child_flow',
    states: const {
      'welcome': ScreenFlowState(
        screen: 'welcome',
        on: {'next': FlowTransition.goto('profile')},
      ),
      'profile': ScreenFlowState(
        screen: 'profile',
        on: {'finish': FlowTransition.goto('done')},
      ),
      'done': EndFlowState(result: {}),
    },
  );
  final childHash = _documentHash(childDocument);
  final parentDocument = _document(
    states: {
      'welcome': const ScreenFlowState(
        screen: 'welcome',
        on: {'next': GotoFlowTransition('profile')},
      ),
      'profile': SubFlowState(
        flow: 'child_flow',
        version: 1,
        schemaVersion: 1,
        minClient: 3,
        contentHash: childHash,
        input: const {},
        onComplete: const [],
        defaultBranch: const FlowBranchTarget(target: 'done'),
      ),
      'done': const EndFlowState(result: {'completed': true}),
    },
  );
  return _MapFlowResolver({
    'first_run': _resolvedFlow(document: parentDocument),
    'child_flow':
        _resolvedFlow(document: childDocument, contentHash: childHash),
  });
}

/// welcome <-> profile, both re-entrant via `go`: visiting the pair repeatedly
/// grows the screen back-stack so eviction can be exercised. `done` is reachable
/// (validation requires an end state) but never fired by the eviction test.
ResolvedFlow _pingPongFlow() {
  return _resolvedFlow(
    states: const {
      'welcome': ScreenFlowState(
        screen: 'welcome',
        on: {'go': FlowTransition.goto('profile')},
      ),
      'profile': ScreenFlowState(
        screen: 'profile',
        on: {
          'go': FlowTransition.goto('welcome'),
          'finish': FlowTransition.goto('done'),
        },
      ),
      'done': EndFlowState(result: {'completed': true}),
    },
  );
}

FlowDocument _hostSeedDecisionDocument({
  bool? defaultValue,
  bool hostSeedable = true,
}) {
  return _document(
    initial: 'branch',
    flowState: {
      'isReturningUser': FlowStateDeclaration(
        type: FlowDataType.bool,
        classification: FlowStateClassification.internal,
        defaultValue: defaultValue,
        hostSeedable: hostSeedable,
      ),
    },
    states: const {
      'branch': DecisionFlowState(
        branches: [
          FlowBranch(
            when: FlowBranchPredicate(
              fields: {
                'isReturningUser': EqualsFlowPredicateCondition(
                  value: LiteralFlowValueSource(
                    type: FlowDataType.bool,
                    value: true,
                  ),
                ),
              },
            ),
            target: 'profile',
          ),
        ],
        defaultBranch: FlowBranchTarget(target: 'welcome'),
      ),
      'welcome': ScreenFlowState(
        screen: 'welcome',
        on: {'next': FlowTransition.goto('done')},
      ),
      'profile': ScreenFlowState(
        screen: 'profile',
        on: {'finish': FlowTransition.goto('done')},
      ),
      'done': EndFlowState(result: {'completed': true}),
    },
  );
}

FlowDocument _document({
  String flow = 'first_run',
  String initial = 'welcome',
  Map<String, FlowActionContract>? actions,
  FlowOutboundDeclarations outbound = const FlowOutboundDeclarations(),
  bool legacyTerminalResultPassthrough = false,
  Map<String, FlowState>? states,
  Map<String, FlowStateDeclaration> flowState = const {},
  Map<String, FlowContentHash>? screenHashes,
  Set<String> unsupportedFeatures = const {},
}) {
  final hashes = screenHashes ??
      {
        'welcome': FlowContentHash.compute(_screenBlob('Welcome')),
        'profile': FlowContentHash.compute(_screenBlob('Profile')),
      };
  return FlowDocument(
    flow: flow,
    version: 1,
    schemaVersion: 1,
    minClient: 3,
    initial: initial,
    actions: actions ?? const {},
    flowState: flowState,
    outbound: outbound,
    legacyTerminalResultPassthrough: legacyTerminalResultPassthrough,
    screenArtifacts: {
      'welcome': ScreenArtifact(
        path: 'welcome.rfw',
        version: 1,
        schemaVersion: 1,
        minClient: 3,
        contentHash: hashes['welcome']!,
      ),
      'profile': ScreenArtifact(
        path: 'profile.rfw',
        version: 1,
        schemaVersion: 1,
        minClient: 3,
        contentHash: hashes['profile']!,
      ),
    },
    states: states ??
        const {
          'welcome': ScreenFlowState(
            screen: 'welcome',
            on: {'next': FlowTransition.goto('profile')},
          ),
          'profile': ScreenFlowState(
            screen: 'profile',
            on: {'finish': FlowTransition.goto('done')},
          ),
          'done': EndFlowState(result: {'completed': true}),
        },
    unsupportedFeatures: unsupportedFeatures,
  );
}

const _emptyArgsSchema = FlowActionSchema.object({});
const _boolResultSchema = FlowActionSchema.bool();
const _stringArgsSchema = FlowActionSchema.string();
const _stringResultSchema = FlowActionSchema.string();
const _profileArgsSchema = FlowActionSchema.object({
  'profileId': FlowActionSchemaField(
    required: true,
    schema: FlowActionSchema.string(),
  ),
});
const _notificationResultSchema = FlowActionSchema.object({
  'granted': FlowActionSchemaField(
    required: true,
    schema: FlowActionSchema.bool(),
  ),
});

final _emptyArgsHash = FlowActionSchema.hashFor(
  contractKind: 'args',
  schema: _emptyArgsSchema,
).value;
final _boolResultHash = FlowActionSchema.hashFor(
  contractKind: 'result',
  schema: _boolResultSchema,
).value;
final _stringArgsHash = FlowActionSchema.hashFor(
  contractKind: 'args',
  schema: _stringArgsSchema,
).value;
final _stringResultHash = FlowActionSchema.hashFor(
  contractKind: 'result',
  schema: _stringResultSchema,
).value;

FlowActionContract _actionContract({
  String actionName = 'requestNotifications',
  int contractVersion = 1,
  FlowActionSchema argsSchema = _emptyArgsSchema,
  FlowActionSchema resultSchema = _boolResultSchema,
  int minClient = 3,
  bool idempotent = false,
}) {
  return FlowActionContract(
    actionName: actionName,
    contractVersion: contractVersion,
    argsSchema: argsSchema,
    resultSchema: resultSchema,
    minClient: minClient,
    idempotent: idempotent,
  );
}

final class _MatchingActionRegistry implements FlowActionRegistry {
  _MatchingActionRegistry({
    int contractVersion = 1,
    FlowActionSchema argsSchema = _emptyArgsSchema,
    FlowActionSchema resultSchema = _boolResultSchema,
    bool idempotent = false,
    FlowActionHandler<void, bool>? handler,
  }) : flowActionBindings = {
          'requestNotifications': _actionBinding(
            contractVersion: contractVersion,
            argsSchema: argsSchema,
            resultSchema: resultSchema,
            idempotent: idempotent,
            handler: handler,
          ),
        };

  @override
  final Map<String, FlowActionBinding<dynamic, dynamic>> flowActionBindings;
}

FlowActionBinding<void, bool> _actionBinding({
  String actionName = 'requestNotifications',
  int contractVersion = 1,
  FlowActionSchema argsSchema = _emptyArgsSchema,
  FlowActionSchema resultSchema = _boolResultSchema,
  bool idempotent = false,
  FlowActionHandler<void, bool>? handler,
}) {
  return FlowActionBinding<void, bool>(
    descriptor: FlowActionDescriptor<void, bool>(
      actionName: actionName,
      contractVersion: contractVersion,
      argsSchema: argsSchema,
      resultSchema: resultSchema,
      minClient: 3,
      idempotent: idempotent,
    ),
    actionName: actionName,
    contractVersion: contractVersion,
    argsSchema: argsSchema,
    resultSchema: resultSchema,
    minClient: 3,
    idempotent: idempotent,
    handler: handler ?? ((_, __) => true),
    decodeArgs: (_) {},
    encodeResult: (value) => value,
  );
}

final class _TestActionRegistry implements FlowActionRegistry {
  const _TestActionRegistry(this.flowActionBindings);

  @override
  final Map<String, FlowActionBinding<dynamic, dynamic>> flowActionBindings;
}

final class _SequencedActionRegistry implements FlowActionRegistry {
  _SequencedActionRegistry(this._bindingsByRead);

  final List<Map<String, FlowActionBinding<dynamic, dynamic>>> _bindingsByRead;
  int _reads = 0;

  @override
  Map<String, FlowActionBinding<dynamic, dynamic>> get flowActionBindings {
    final index =
        _reads < _bindingsByRead.length ? _reads : _bindingsByRead.length - 1;
    _reads += 1;
    return _bindingsByRead[index];
  }
}

final class _PermissionResult {
  const _PermissionResult({required this.granted});

  final bool granted;
}

Uint8List _screenBlob(String text) {
  final source = '''
    import restage.core;
    widget OnboardingScreen = Text(text: "$text");
  ''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

Future<void> _drainFlowTasks() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}
