import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/analytics/root_analytics_context.dart';

import 'flow_test_support.dart';

/// The controller reports readiness only after content is actually painted.
void main() {
  setUp(Restage.debugReset);

  testWidgets('render readiness commits only after the view builds the screen',
      (tester) async {
    final controller = _controller(_resolvedFlow());
    addTearDown(controller.dispose);

    await tester.runAsync(controller.load);
    expect(controller.currentScreenEntryId, isNotNull);
    expect(controller.hasRenderedContent, isFalse);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(controller: controller),
    ));
    await tester.pump();

    final observed = controller.hasRenderedContent;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(observed, isTrue);
  });

  test('render readiness is false when the first screen starts', () async {
    bool? readyAtStart;
    late final RestageFlowController<FirstRunResult> controller;
    controller = RestageFlowController<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: StaticFlowResolver(_resolvedFlow()),
      actions: null,
      onEvent: (event) {
        if (event is FlowStarted) {
          readyAtStart = controller.hasRenderedContent;
        }
      },
      onComplete: (_) {},
      onUnavailable: (_) {},
    );
    addTearDown(controller.dispose);

    await controller.load();
    await drainFlowTasks();

    expect(readyAtStart, isFalse);
    expect(controller.hasRenderedContent, isFalse);
  });

  testWidgets('an initial sub-flow becomes ready when its first screen commits',
      (tester) async {
    final child = childScreenFlow();
    final childCompleter = Completer<ResolvedFlow>();
    final resolver = ControlledInitialSubFlowResolver(
      root: initialSubFlowRoot(child: child),
      child: childCompleter,
    );
    final observations = <({String flowId, bool ready})>[];
    late final RestageFlowController<FirstRunResult> controller;
    controller = RestageFlowController<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: resolver,
      actions: null,
      onEvent: (event) {
        if (event is FlowStarted) {
          observations.add((
            flowId: event.flowId,
            ready: controller.hasRenderedContent,
          ));
        }
      },
      onComplete: (_) {},
      onUnavailable: (_) {},
    );
    addTearDown(controller.dispose);

    late Future<void> load;
    await tester.runAsync(() async {
      load = controller.load();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
    });

    expect(observations, [
      (flowId: 'first_run', ready: false),
    ]);
    expect(controller.hasRenderedContent, isFalse);

    childCompleter.complete(child);
    await tester.runAsync(() => load);

    expect(controller.hasRenderedContent, isFalse);
    expect(
      RootAnalyticsArtifactRegistry.surfaceVersionFor(controller),
      firstRunFlowRef.version.toString(),
    );
    expect(observations, [
      (flowId: 'first_run', ready: false),
      (flowId: 'child_flow', ready: false),
    ]);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(controller: controller),
    ));
    await tester.pump();

    final observed = controller.hasRenderedContent;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(observed, isTrue);
  });

  testWidgets('a root screen reached after a screenless child marks readiness',
      (tester) async {
    final child = screenlessChildFlow();
    final childCompleter = Completer<ResolvedFlow>();
    final resolver = ControlledInitialSubFlowResolver(
      root: initialSubFlowThenScreenRoot(child: child),
      child: childCompleter,
    );
    final readyStates = <bool>[];
    late final RestageFlowController<FirstRunResult> controller;
    controller = RestageFlowController<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: resolver,
      actions: null,
      onEvent: (_) {},
      onComplete: (_) {},
      onUnavailable: (_) {},
    )..addListener(() {
        if (controller.hasRenderedContent) {
          readyStates.add(true);
        }
      });
    addTearDown(controller.dispose);

    late Future<void> load;
    await tester.runAsync(() async {
      load = controller.load();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
    });

    expect(controller.hasRenderedContent, isFalse);

    childCompleter.complete(child);
    await tester.runAsync(() => load);

    expect(controller.hasRenderedContent, isFalse);
    expect(readyStates, isEmpty);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(controller: controller),
    ));
    await tester.pump();

    final observed = (
      ready: controller.hasRenderedContent,
      readyStates: List<bool>.of(readyStates),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(observed.ready, isTrue);
    expect(observed.readyStates, [true]);
  });

  test('a resolved flow remains unpainted until its view builds', () async {
    final controller = _controller(_resolvedFlow());
    addTearDown(controller.dispose);

    await controller.load();
    await drainFlowTasks();

    expect(controller.currentScreenEntryId, isNotNull);
    expect(controller.hasRenderedContent, isFalse);
  });

  testWidgets('a later render failure closes the controller', (tester) async {
    FlowUnavailableError? unavailable;
    final controller = RestageFlowController<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: StaticFlowResolver(_resolvedFlow()),
      actions: null,
      onEvent: (_) {},
      onComplete: (_) {},
      onUnavailable: (error) => unavailable = error,
    );
    addTearDown(controller.dispose);

    await tester.runAsync(controller.load);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(controller: controller),
    ));
    await tester.pump();
    expect(controller.hasRenderedContent, isTrue);

    controller.reportRenderFailure(StateError('boom'));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(controller.isUnavailable, isTrue);
    expect(unavailable?.reason, 'render_failed');
  });

  test('FlowStarted.toMap() omits retired experiment fields', () {
    const started = FlowStarted(
      flowId: 'first_run',
      flowVersion: 1,
      flowSessionId: 'session-1',
    );
    final map = started.toMap();
    for (final key in const [
      'decision',
      'experimentId',
      'variantId',
      'experimentEpoch',
    ]) {
      expect(map.containsKey(key), isFalse, reason: key);
    }
  });

  test('a failed resolve leaves the controller unavailable', () async {
    FlowUnavailableError? unavailable;
    final controller = RestageFlowController<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: const _ThrowingResolver(),
      actions: null,
      onEvent: (_) {},
      onComplete: (_) {},
      onUnavailable: (error) => unavailable = error,
    );
    addTearDown(controller.dispose);

    await controller.load();
    await drainFlowTasks();

    expect(controller.isUnavailable, isTrue);
    expect(unavailable?.reason, 'unavailable');
    expect(controller.currentScreenEntryId, isNull);
  });

  test('controller disposal is idempotent without an external retention set',
      () {
    final controller = _controller(_resolvedFlow());

    controller.dispose();

    expect(controller.dispose, returnsNormally);
  });
}

RestageFlowController<FirstRunResult> _controller(ResolvedFlow flow) =>
    RestageFlowController<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: StaticFlowResolver(flow),
      actions: null,
      onEvent: (_) {},
      onComplete: (_) {},
      onUnavailable: (_) {},
    );

/// The default first-run flow used by these controller tests.
ResolvedFlow _resolvedFlow() {
  final welcome = screenBlob('Welcome', 'next');
  final profile = screenBlob('Profile', 'finish');
  return ResolvedFlow(
    document: flowDocument(
      legacyTerminalResultPassthrough: true,
      screenHashes: {
        'welcome': FlowContentHash.compute(welcome),
        'profile': FlowContentHash.compute(profile),
      },
    ),
    screenBlobs: {'welcome': welcome, 'profile': profile},
    cacheHit: false,
  );
}

final class _ThrowingResolver implements FlowResolver {
  const _ThrowingResolver();

  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) async {
    throw const FlowUnavailableError(
      flowId: 'first_run',
      flowVersion: 1,
      reason: 'unavailable',
      message: 'no artifact',
    );
  }
}
