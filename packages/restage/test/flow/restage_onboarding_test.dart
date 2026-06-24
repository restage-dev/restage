// Some cases shell out to `dart analyze` (cold-start resolution); give them
// headroom over the 30s default so they don't flake under load.
@Timeout(Duration(minutes: 2))
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart' hide WidgetLibrary;

void main() {
  const welcome = OnboardingScreenRef(
    id: 'welcome',
    artifactPath: 'assets/restage/welcome.rfw',
    version: 1,
    minClient: 3,
  );
  const profile = OnboardingScreenRef(
    id: 'profile',
    artifactPath: 'assets/restage/profile.rfw',
    version: 1,
    minClient: 3,
  );
  const next = OnboardingEvent<void>('next');
  const flowRef = OnboardingFlowRef<_FirstRunResult>(
    id: 'first_run',
    version: 1,
    minClient: 3,
    decodeResult: _FirstRunResult.decode,
  );
  const createProfile = FlowActionRef<void, bool>('create_profile');

  test('linear flow descriptors expose bounded screen and end transitions', () {
    final first = screen(welcome).on(next).goTo(profile);
    final doneRef = endState('completed');
    final second = screen(profile).on(next).goTo(doneRef);
    final done = end(doneRef, result: {'completed': true});
    final definition = flow(initial: welcome, states: [first, second, done]);

    expect(definition.initial, welcome);
    expect(definition.states, [first, second, done]);
    expect(first.ref, welcome);
    expect(first.transitions.single.event, next);
    expect(first.transitions.single.target, profile);
    expect(second.transitions.single.target, doneRef);
    expect(done.endState, doneRef);
    expect(done.result, {'completed': true});
  });

  test('string transition targets are rejected by static analysis', () async {
    final result = await _analyzeNegativeSample(
      fileName: 'string_target.dart',
      source: '''
import 'package:restage/restage.dart';

void main() {
  const welcome = OnboardingScreenRef(
    id: 'welcome',
    artifactPath: 'assets/restage/welcome.rfw',
    version: 1,
    minClient: 3,
  );
  const next = OnboardingEvent<void>('next');
  screen(welcome).on(next).goTo('some_state');
}
''',
    );

    expect(result.exitCode, isNot(0), reason: result.output);
    expect(result.output, contains('String'));
    expect(result.output, contains('FlowTargetRef'));
  });

  test('action result predicates stay typed on transition descriptors', () {
    final doneRef = endState('completed');
    final node = screen(welcome)
        .on(next)
        .run(createProfile)
        .result((completed) => completed)
        .goTo(doneRef);
    final action = node.transitions.single.action as FlowActionDef<void, bool>;

    expect(action.action, createProfile);
    expect(action.resultPredicate(true), isTrue);
    expect(action.resultPredicate(false), isFalse);
  });

  test('RestageOnboarding requires an explicit unavailable policy', () {
    const widget = RestageOnboarding<_FirstRunResult>(
      flow: flowRef,
      unavailable: FlowUnavailablePolicy.hide(),
    );

    expect(widget.flow, flowRef);
    expect(widget.unavailable.isHide, isTrue);
  });

  testWidgets('FlowUnavailablePolicy fallback stores and invokes its builder',
      (tester) async {
    final error = FlowUnavailableError(
      flowId: flowRef.id,
      flowVersion: flowRef.version,
      reason: 'missing_descriptor',
      message: 'Flow descriptor was not found.',
    );
    Widget fallbackBuilder(BuildContext context, FlowUnavailableError error) {
      return Text(error.reason, textDirection: TextDirection.ltr);
    }

    final policy = FlowUnavailablePolicy.fallback(builder: fallbackBuilder);
    BuildContext? context;
    await tester.pumpWidget(Builder(
      builder: (builderContext) {
        context = builderContext;
        return const SizedBox.shrink();
      },
    ));

    expect(policy.isFallback, isTrue);
    expect(policy.isHide, isFalse);
    expect(policy.fallbackBuilder, same(fallbackBuilder));
    expect(policy.fallbackBuilder!(context!, error), isA<Text>());
  });

  test('FlowUnavailablePolicy hide is explicit and has no fallback builder',
      () {
    const policy = FlowUnavailablePolicy.hide();

    expect(policy.isHide, isTrue);
    expect(policy.isFallback, isFalse);
    expect(policy.fallbackBuilder, isNull);
  });

  test('FlowUnavailablePolicy fallback requires a builder', () async {
    final result = await _analyzeNegativeSample(
      fileName: 'missing_fallback_builder.dart',
      source: '''
import 'package:restage/restage.dart';

void main() {
  FlowUnavailablePolicy.fallback();
}
''',
    );

    expect(result.exitCode, isNot(0), reason: result.output);
    expect(result.output, contains('builder'));
  });

  testWidgets('RestageOnboarding renders loading while resolving',
      (tester) async {
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageOnboarding<_FirstRunResult>(
        flow: flowRef,
        resolver: _PendingResolver(),
        unavailable: const FlowUnavailablePolicy.hide(),
        loadingBuilder: (_) => const Text('Loading'),
      ),
    ));

    expect(find.text('Loading'), findsOneWidget);
  });

  testWidgets('RestageOnboarding default loading is SizedBox.shrink',
      (tester) async {
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageOnboarding<_FirstRunResult>(
        flow: flowRef,
        resolver: _PendingResolver(),
        unavailable: const FlowUnavailablePolicy.hide(),
      ),
    ));

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SizedBox && widget.width == 0 && widget.height == 0,
      ),
      findsOneWidget,
    );
  });

  testWidgets('RestageOnboarding renders and advances a linear flow',
      (tester) async {
    _FirstRunResult? completed;
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageOnboarding<_FirstRunResult>(
        flow: flowRef,
        resolver: _StaticFlowResolver(_resolvedFlow()),
        unavailable: const FlowUnavailablePolicy.hide(),
        onComplete: (result) => completed = result,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Welcome'), findsOneWidget);

    await tester.tap(find.text('Welcome'));
    await tester.pumpAndSettle();

    expect(find.text('Profile'), findsOneWidget);

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();

    expect(completed?.completed, isTrue);
  });

  testWidgets('legacy linear flow works when actions are omitted',
      (tester) async {
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageOnboarding<_FirstRunResult>(
        flow: flowRef,
        resolver: _StaticFlowResolver(_resolvedFlow()),
        unavailable: const FlowUnavailablePolicy.hide(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Welcome'), findsOneWidget);
  });

  testWidgets(
      'document requiring actions fails closed when actions are omitted',
      (tester) async {
    FlowUnavailableError? callbackError;

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageOnboarding<_FirstRunResult>(
        flow: flowRef,
        resolver: _StaticFlowResolver(
          _resolvedFlow(actions: {'create_profile': _actionContract()}),
        ),
        unavailable: FlowUnavailablePolicy.fallback(
          builder: (_, error) => Text(error.reason),
        ),
        onFlowUnavailable: (error) => callbackError = error,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('action_contract_mismatch'), findsOneWidget);
    expect(callbackError?.message, contains('actions'));
    expect(find.text('Welcome'), findsNothing);
  });

  test('wrong actions type is rejected by static analysis', () async {
    final result = await _analyzeNegativeSample(
      fileName: 'wrong_actions_type.dart',
      source: '''
import 'package:restage/restage.dart';

void main() {
  const flow = OnboardingFlowRef<_Result>(
    id: 'first_run',
    version: 1,
    minClient: 3,
    decodeResult: _Result.decode,
  );
  RestageOnboarding<_Result>(
    flow: flow,
    actions: Object(),
    unavailable: FlowUnavailablePolicy.hide(),
  );
}

final class _Result {
  const _Result();
  static _Result decode(Map<String, Object?> result) => const _Result();
}
''',
    );

    expect(result.exitCode, isNot(0), reason: result.output);
    expect(result.output, contains('Object'));
    expect(result.output, contains('FlowActionRegistry'));
  });

  testWidgets('document requiring actions accepts generated-style registry',
      (tester) async {
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageOnboarding<_FirstRunResult>(
        flow: flowRef,
        resolver: _StaticFlowResolver(
          _resolvedFlow(actions: {'create_profile': _actionContract()}),
        ),
        actions: _GeneratedActions(),
        unavailable: FlowUnavailablePolicy.fallback(
          builder: (_, error) => Text(error.reason),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Welcome'), findsOneWidget);
    expect(find.text('action_contract_mismatch'), findsNothing);
  });

  testWidgets('bad terminal result emits unavailable and skips completion',
      (tester) async {
    _FirstRunResult? completed;
    FlowUnavailableError? callbackError;
    final globalEvents = <RestageEvent>[];
    final sub = Restage.events.listen(globalEvents.add);
    addTearDown(sub.cancel);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageOnboarding<_FirstRunResult>(
        flow: flowRef,
        resolver: _StaticFlowResolver(
          _resolvedFlow(
            states: const {
              'welcome': ScreenFlowState(
                screen: 'welcome',
                on: {'next': FlowTransition.goto('done')},
              ),
              'done': EndFlowState(result: {'completed': 'yes'}),
            },
          ),
        ),
        unavailable: FlowUnavailablePolicy.fallback(
          builder: (_, error) => Text(error.reason),
        ),
        onComplete: (result) => completed = result,
        onFlowUnavailable: (error) => callbackError = error,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Welcome'));
    await tester.pumpAndSettle();

    expect(completed, isNull);
    expect(callbackError?.reason, 'result_decode_failed');
    expect(find.text('result_decode_failed'), findsOneWidget);
    expect(
      globalEvents.whereType<FlowUnavailable>().single.reason,
      'result_decode_failed',
    );
    expect(globalEvents.whereType<FlowCompleted>(), isEmpty);
  });

  testWidgets('fallback policy renders fallback and emits FlowUnavailable',
      (tester) async {
    FlowUnavailableError? callbackError;
    final globalEvents = <RestageEvent>[];
    final sub = Restage.events.listen(globalEvents.add);
    addTearDown(sub.cancel);
    const error = FlowUnavailableError(
      flowId: 'first_run',
      flowVersion: 1,
      reason: 'unsupported_feature',
      message: 'No decisions in legacy linear flow.',
    );

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageOnboarding<_FirstRunResult>(
        flow: flowRef,
        resolver: const _FailingResolver(error),
        unavailable: FlowUnavailablePolicy.fallback(
          builder: (_, error) => Text('fallback:${error.reason}'),
        ),
        onFlowUnavailable: (error) => callbackError = error,
      ),
    ));
    await tester.pumpAndSettle();

    final event = globalEvents.whereType<FlowUnavailable>().single;
    expect(find.text('fallback:unsupported_feature'), findsOneWidget);
    expect(callbackError, same(error));
    expect(event.reason, callbackError?.reason);
    expect(event.message, callbackError?.message);
  });

  testWidgets('hide policy renders shrink and emits FlowUnavailable',
      (tester) async {
    final globalEvents = <RestageEvent>[];
    final sub = Restage.events.listen(globalEvents.add);
    addTearDown(sub.cancel);
    const error = FlowUnavailableError(
      flowId: 'first_run',
      flowVersion: 1,
      reason: 'missing_screen_blob',
      message: 'Missing screen.',
    );

    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: RestageOnboarding<_FirstRunResult>(
        flow: flowRef,
        resolver: _FailingResolver(error),
        unavailable: FlowUnavailablePolicy.hide(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SizedBox && widget.width == 0 && widget.height == 0,
      ),
      findsOneWidget,
    );
    expect(
      globalEvents.whereType<FlowUnavailable>().single.reason,
      'missing_screen_blob',
    );
  });

  testWidgets('render error fails closed through fallback and emits event',
      (tester) async {
    Restage.debugReset();
    _registerThrowingWidget();
    FlowUnavailableError? callbackError;
    final globalEvents = <RestageEvent>[];
    final sub = Restage.events.listen(globalEvents.add);
    addTearDown(sub.cancel);
    final throwingBlob = _throwingScreenBlob();
    final profileBlob = _screenBlob('Profile', 'finish');

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageOnboarding<_FirstRunResult>(
        flow: flowRef,
        resolver: _StaticFlowResolver(
          ResolvedFlow(
            document: _flowDocument(
              screenHashes: {
                'welcome': FlowContentHash.compute(throwingBlob),
                'profile': FlowContentHash.compute(profileBlob),
              },
            ),
            screenBlobs: {
              'welcome': throwingBlob,
              'profile': profileBlob,
            },
            cacheHit: false,
          ),
        ),
        unavailable: FlowUnavailablePolicy.fallback(
          builder: (_, error) => Text('fallback:${error.reason}'),
        ),
        onFlowUnavailable: (error) => callbackError = error,
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(callbackError?.reason, 'render_failed');
    expect(find.text('fallback:render_failed'), findsOneWidget);
    expect(
      globalEvents.whereType<FlowUnavailable>().single.reason,
      'render_failed',
    );
  });

  testWidgets('concurrent render error is attributed to the throwing flow',
      (tester) async {
    Restage.debugReset();
    _registerThrowingWidget();
    final firstErrors = <FlowUnavailableError>[];
    final secondErrors = <FlowUnavailableError>[];
    final globalEvents = <RestageEvent>[];
    final sub = Restage.events.listen(globalEvents.add);
    addTearDown(sub.cancel);
    const secondFlowRef = OnboardingFlowRef<_FirstRunResult>(
      id: 'second_run',
      version: 1,
      minClient: 3,
      decodeResult: _FirstRunResult.decode,
    );
    final firstWelcomeBlob = _screenBlob('First', 'next');
    final firstThrowingBlob = _throwingScreenBlob();
    final secondWelcomeBlob = _screenBlob('Second', 'next');
    final secondProfileBlob = _screenBlob('Second Profile', 'finish');

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        children: [
          RestageOnboarding<_FirstRunResult>(
            flow: flowRef,
            resolver: _StaticFlowResolver(
              ResolvedFlow(
                document: _flowDocument(
                  screenHashes: {
                    'welcome': FlowContentHash.compute(firstWelcomeBlob),
                    'profile': FlowContentHash.compute(firstThrowingBlob),
                  },
                ),
                screenBlobs: {
                  'welcome': firstWelcomeBlob,
                  'profile': firstThrowingBlob,
                },
                cacheHit: false,
              ),
            ),
            unavailable: FlowUnavailablePolicy.fallback(
              builder: (_, error) =>
                  Text('fallback:${error.flowId}:${error.reason}'),
            ),
            onFlowUnavailable: firstErrors.add,
          ),
          RestageOnboarding<_FirstRunResult>(
            flow: secondFlowRef,
            resolver: _StaticFlowResolver(
              ResolvedFlow(
                document: _flowDocument(
                  flow: secondFlowRef.id,
                  screenHashes: {
                    'welcome': FlowContentHash.compute(secondWelcomeBlob),
                    'profile': FlowContentHash.compute(secondProfileBlob),
                  },
                ),
                screenBlobs: {
                  'welcome': secondWelcomeBlob,
                  'profile': secondProfileBlob,
                },
                cacheHit: false,
              ),
            ),
            unavailable: FlowUnavailablePolicy.fallback(
              builder: (_, error) =>
                  Text('fallback:${error.flowId}:${error.reason}'),
            ),
            onFlowUnavailable: secondErrors.add,
          ),
        ],
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('First'));
    await tester.pumpAndSettle();

    final exception = tester.takeException();
    final firstFallbackCount =
        find.text('fallback:first_run:render_failed').evaluate().length;
    final secondTextCount = find.text('Second').evaluate().length;

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(exception, isNull);
    expect(firstErrors.map((error) => error.reason), ['render_failed']);
    expect(secondErrors, isEmpty);
    expect(firstFallbackCount, 1);
    expect(secondTextCount, 1);
    expect(
        globalEvents.whereType<FlowUnavailable>().single.flowId, 'first_run');
  });

  testWidgets('unmount during async resolve skips widget callbacks',
      (tester) async {
    var callbackCalled = false;
    final globalEvents = <RestageEvent>[];
    final sub = Restage.events.listen(globalEvents.add);
    addTearDown(sub.cancel);
    final resolver = _CompletingResolver();

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageOnboarding<_FirstRunResult>(
        flow: flowRef,
        resolver: resolver,
        unavailable: const FlowUnavailablePolicy.hide(),
        onFlowUnavailable: (_) => callbackCalled = true,
        onComplete: (_) => callbackCalled = true,
      ),
    ));

    await tester.pumpWidget(const SizedBox.shrink());
    resolver.completeError(const FlowUnavailableError(
      flowId: 'first_run',
      flowVersion: 1,
      reason: 'missing_flow_json',
      message: 'Missing flow.',
    ));
    await tester.pump();

    expect(callbackCalled, isFalse);
    expect(globalEvents.whereType<FlowUnavailable>(), isEmpty);
  });

  testWidgets('unmount cancels active sub-flow action global events',
      (tester) async {
    final actionCompleter = Completer<bool>();
    var callbacks = 0;
    final globalEvents = <RestageEvent>[];
    final sub = Restage.events.listen(globalEvents.add);
    addTearDown(sub.cancel);

    final childDocument = _flowDocument(
      flow: 'profile_child',
      actions: {'create_profile': _actionContract()},
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
            'next': ActionFlowTransition(
              action: 'create_profile',
              resultPredicate: BoolEqualsActionResultPredicate(value: true),
              target: 'done',
            ),
          },
        ),
        'done': EndFlowState(result: {'accepted': true}),
      },
    );
    final childHash = _documentHash(childDocument);
    final parentDocument = _flowDocument(
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
              ref: EventFlowOutboundRef(key: 'completed'),
            ),
          },
        ),
      ),
      states: {
        'welcome': const ScreenFlowState(
          screen: 'welcome',
          on: {'next': FlowTransition.goto('profile')},
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
            ),
          ],
          defaultBranch: const FlowBranchTarget(target: 'failed'),
        ),
        'done': const EndFlowState(result: {'completed': true}),
        'failed': const EndFlowState(result: {'completed': false}),
      },
    );

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageOnboarding<_FirstRunResult>(
        flow: flowRef,
        resolver: _MapFlowResolver({
          'first_run': _resolvedFlow(document: parentDocument),
          'profile_child': _resolvedFlow(
            document: childDocument,
            contentHash: childHash,
          ),
        }),
        actions: _GeneratedActions(handler: (_, __) => actionCompleter.future),
        unavailable: const FlowUnavailablePolicy.hide(),
        onComplete: (_) => callbacks += 1,
        onFlowUnavailable: (_) => callbacks += 1,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Welcome'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Welcome'));
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    globalEvents.clear();
    actionCompleter.complete(true);
    await tester.pumpAndSettle();

    expect(callbacks, 0);
    expect(globalEvents, isEmpty);
  });

  testWidgets('stale unavailable from replaced resolver is ignored',
      (tester) async {
    final oldResolver = _CompletingResolver();
    final globalEvents = <RestageEvent>[];
    final callbackErrors = <FlowUnavailableError>[];
    final sub = Restage.events.listen(globalEvents.add);
    addTearDown(sub.cancel);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageOnboarding<_FirstRunResult>(
        flow: flowRef,
        resolver: oldResolver,
        unavailable: FlowUnavailablePolicy.fallback(
          builder: (_, error) => Text('fallback:${error.reason}'),
        ),
        onFlowUnavailable: callbackErrors.add,
      ),
    ));

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageOnboarding<_FirstRunResult>(
        flow: flowRef,
        resolver: _StaticFlowResolver(_resolvedFlow(welcomeText: 'New')),
        unavailable: FlowUnavailablePolicy.fallback(
          builder: (_, error) => Text('fallback:${error.reason}'),
        ),
        onFlowUnavailable: callbackErrors.add,
      ),
    ));
    await tester.pumpAndSettle();

    oldResolver.completeError(const FlowUnavailableError(
      flowId: 'first_run',
      flowVersion: 1,
      reason: 'missing_flow_json',
      message: 'Missing flow.',
    ));
    await tester.pump();

    expect(find.text('New'), findsOneWidget);
    expect(find.text('fallback:missing_flow_json'), findsNothing);
    expect(callbackErrors, isEmpty);
    expect(globalEvents.whereType<FlowUnavailable>(), isEmpty);
  });

  testWidgets('stale terminal transition after widget update is ignored',
      (tester) async {
    var completions = 0;
    final directCompletionFlow = _resolvedFlow(
      states: const {
        'welcome': ScreenFlowState(
          screen: 'welcome',
          on: {'next': FlowTransition.goto('done')},
        ),
        'done': EndFlowState(result: {'completed': true}),
      },
    );

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageOnboarding<_FirstRunResult>(
        flow: flowRef,
        resolver: _StaticFlowResolver(directCompletionFlow),
        unavailable: const FlowUnavailablePolicy.hide(),
        onComplete: (_) => completions += 1,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Welcome'));
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageOnboarding<_FirstRunResult>(
        flow: flowRef,
        resolver: _StaticFlowResolver(_resolvedFlow(welcomeText: 'New')),
        unavailable: const FlowUnavailablePolicy.hide(),
        onComplete: (_) => completions += 1,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 1));

    expect(completions, 0);
    expect(find.text('New'), findsOneWidget);
  });
}

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

final class _PendingResolver implements FlowResolver {
  final Completer<ResolvedFlow> _completer = Completer<ResolvedFlow>();

  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) =>
      _completer.future;
}

final class _StaticFlowResolver implements FlowResolver {
  const _StaticFlowResolver(this.flow);

  final ResolvedFlow flow;

  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) async => this.flow;
}

final class _FailingResolver implements FlowResolver {
  const _FailingResolver(this.error);

  final FlowUnavailableError error;

  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) async {
    throw error;
  }
}

final class _CompletingResolver implements FlowResolver {
  final Completer<ResolvedFlow> _completer = Completer<ResolvedFlow>();

  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) =>
      _completer.future;

  void completeError(FlowUnavailableError error) {
    _completer.completeError(error);
  }
}

ResolvedFlow _resolvedFlow({
  FlowDocument? document,
  Map<String, FlowActionContract>? actions,
  Map<String, FlowState>? states,
  String welcomeText = 'Welcome',
  String profileText = 'Profile',
  FlowContentHash? contentHash,
}) {
  final welcome = _screenBlob(welcomeText, 'next');
  final profile = _screenBlob(profileText, 'finish');
  return ResolvedFlow(
    document: document ??
        _flowDocument(
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

FlowDocument _flowDocument({
  String flow = 'first_run',
  Map<String, FlowActionContract>? actions,
  FlowOutboundDeclarations outbound = const FlowOutboundDeclarations(),
  bool legacyTerminalResultPassthrough = false,
  Map<String, FlowState>? states,
  Map<String, FlowContentHash>? screenHashes,
}) {
  final hashes = screenHashes ??
      {
        'welcome': FlowContentHash.compute(_screenBlob('Welcome', 'next')),
        'profile': FlowContentHash.compute(_screenBlob('Profile', 'finish')),
      };
  return FlowDocument(
    flow: flow,
    version: 1,
    schemaVersion: 1,
    minClient: 3,
    initial: 'welcome',
    actions: actions ?? const {},
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
  );
}

FlowContentHash _documentHash(FlowDocument document) {
  return FlowContentHash.compute(
    FlowDocumentCodec.encodePrettyJson(document).codeUnits,
  );
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

FlowActionContract _actionContract() {
  return FlowActionContract(
    actionName: 'create_profile',
    contractVersion: 1,
    argsSchema: _emptyArgsSchema,
    resultSchema: _boolResultSchema,
    minClient: 3,
    idempotent: false,
  );
}

final class _GeneratedActions implements FlowActionRegistry {
  _GeneratedActions({FlowActionHandler<void, bool>? handler})
      : flowActionBindings = {
          'create_profile': FlowActionBinding<void, bool>(
            actionName: 'create_profile',
            contractVersion: 1,
            argsSchema: _emptyArgsSchema,
            resultSchema: _boolResultSchema,
            minClient: 3,
            idempotent: false,
            handler: handler ?? ((_, __) => true),
            decodeArgs: (_) {},
            encodeResult: (value) => value,
          ),
        };

  @override
  final Map<String, FlowActionBinding<dynamic, dynamic>> flowActionBindings;
}

const _emptyArgsSchema = FlowActionSchema.object({});
const _boolResultSchema = FlowActionSchema.bool();
const _throwingLibrary = WidgetLibrary.custom('acme.throwing');

class _ThrowingWidget extends StatelessWidget {
  const _ThrowingWidget();

  @override
  Widget build(BuildContext context) {
    throw StateError('onboarding render failed');
  }
}

void _registerThrowingWidget() {
  Restage.registerWidgetLibrary(
    _throwingLibrary,
    widgets: <RestageWidgetFactory>[
      RestageWidgetFactory(
        name: 'ThrowingWidget',
        builder: (_, __) => const _ThrowingWidget(),
      ),
    ],
  );
}

Uint8List _screenBlob(String text, String event) {
  final source = '''
    import restage.core;
    widget OnboardingScreen = GestureDetector(
      onTap: event "$event" { },
      child: Text(text: "$text")
    );
  ''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

Uint8List _throwingScreenBlob() {
  const source = '''
    import acme.throwing;
    widget OnboardingScreen = ThrowingWidget();
  ''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

Future<_AnalyzeResult> _analyzeNegativeSample({
  required String fileName,
  required String source,
}) async {
  final negativeDir = Directory('.dart_tool/restage_negative_tests');
  negativeDir.createSync(recursive: true);
  final negativeFile = File('${negativeDir.path}/$fileName');
  negativeFile.writeAsStringSync(source);
  addTearDown(() {
    if (negativeFile.existsSync()) {
      negativeFile.deleteSync();
    }
  });

  final result = await Process.run(
    'dart',
    <String>['analyze', negativeFile.path],
    workingDirectory: Directory.current.path,
  );

  return _AnalyzeResult(
    exitCode: result.exitCode,
    output: '${result.stdout}\n${result.stderr}',
  );
}

final class _AnalyzeResult {
  const _AnalyzeResult({
    required this.exitCode,
    required this.output,
  });

  final int exitCode;
  final String output;
}
