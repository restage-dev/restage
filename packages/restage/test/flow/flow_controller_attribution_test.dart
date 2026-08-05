import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/analytics/root_analytics_context.dart';

import 'flow_test_support.dart';

/// The controller hoists the RENDERED artifact's assignment to a field that
/// survives `FlowUnavailable`'s frame-stack clear. The hoist happens only when
/// an artifact actually renders (never at fetch/resolve — a rejected fresh arm
/// never reaches the field), and a failed render does not fabricate one.
void main() {
  setUp(Restage.debugReset);

  const armA = FlowAssignment(
    experimentId: 'exp_copy',
    variantId: 'variant_a',
    experimentEpoch: 3,
  );

  testWidgets(
      'renderedAssignment commits only after the view builds the screen',
      (tester) async {
    final controller = _controller(_assignedFlow(armA));
    addTearDown(controller.dispose);

    await tester.runAsync(controller.load);
    expect(controller.currentScreenEntryId, isNotNull);
    expect(controller.hasRenderedContent, isFalse);
    expect(controller.renderedAssignment, isNull);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(controller: controller),
    ));
    await tester.pump();

    final observed = (
      ready: controller.hasRenderedContent,
      assignment: controller.renderedAssignment,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(observed, (ready: true, assignment: armA));
  });

  test('render readiness and assignment are atomic at the first screen',
      () async {
    ({bool ready, FlowAssignment? assignment})? stateAtStart;
    late final RestageFlowController<FirstRunResult> controller;
    controller = RestageFlowController<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: StaticFlowResolver(_assignedFlow(armA)),
      actions: null,
      onEvent: (event) {
        if (event is FlowStarted) {
          stateAtStart = (
            ready: controller.hasRenderedContent,
            assignment: controller.renderedAssignment,
          );
        }
      },
      onComplete: (_) {},
      onUnavailable: (_) {},
    );
    addTearDown(controller.dispose);

    await controller.load();
    await drainFlowTasks();

    expect(stateAtStart, (ready: false, assignment: null));
    expect(controller.hasRenderedContent, isFalse);
    expect(controller.renderedAssignment, isNull);
  });

  testWidgets(
      'an initial sub-flow exposes the root assignment only when its first '
      'actual screen commits', (tester) async {
    const childArm = FlowAssignment(
      experimentId: 'exp_child',
      variantId: 'variant_child',
      experimentEpoch: 8,
    );
    final child = childScreenFlow(assignment: childArm);
    final childCompleter = Completer<ResolvedFlow>();
    final resolver = ControlledInitialSubFlowResolver(
      root: initialSubFlowRoot(child: child, assignment: armA),
      child: childCompleter,
    );
    final observations = <({
      String flowId,
      bool ready,
      FlowAssignment? assignment,
    })>[];
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
            assignment: controller.renderedAssignment,
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
      (flowId: 'first_run', ready: false, assignment: null),
    ]);
    expect(controller.hasRenderedContent, isFalse);
    expect(controller.renderedAssignment, isNull);

    childCompleter.complete(child);
    await tester.runAsync(() => load);

    expect(controller.hasRenderedContent, isFalse);
    expect(controller.renderedAssignment, isNull);
    expect(
      RootAnalyticsArtifactRegistry.surfaceVersionFor(controller),
      firstRunFlowRef.version.toString(),
    );
    expect(observations, [
      (flowId: 'first_run', ready: false, assignment: null),
      (flowId: 'child_flow', ready: false, assignment: null),
    ]);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(controller: controller),
    ));
    await tester.pump();

    final observed = (
      ready: controller.hasRenderedContent,
      assignment: controller.renderedAssignment,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(observed, (ready: true, assignment: armA));
  });

  testWidgets(
      'a root screen reached after a screenless child marks readiness with '
      'the root assignment', (tester) async {
    const childArm = FlowAssignment(
      experimentId: 'exp_child',
      variantId: 'variant_child',
      experimentEpoch: 8,
    );
    final child = screenlessChildFlow(assignment: childArm);
    final childCompleter = Completer<ResolvedFlow>();
    final resolver = ControlledInitialSubFlowResolver(
      root: initialSubFlowThenScreenRoot(
        child: child,
        assignment: armA,
      ),
      child: childCompleter,
    );
    final readyStates = <FlowAssignment?>[];
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
          readyStates.add(controller.renderedAssignment);
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
    expect(controller.renderedAssignment, isNull);

    childCompleter.complete(child);
    await tester.runAsync(() => load);

    expect(controller.hasRenderedContent, isFalse);
    expect(controller.renderedAssignment, isNull);
    expect(readyStates, isEmpty);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(controller: controller),
    ));
    await tester.pump();

    final observed = (
      ready: controller.hasRenderedContent,
      assignment: controller.renderedAssignment,
      readyStates: List<FlowAssignment?>.of(readyStates),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(observed.ready, isTrue);
    expect(observed.assignment, armA);
    expect(observed.readyStates, <FlowAssignment?>[armA]);
  });

  test('renderedAssignment is null for an artifact with no experiment',
      () async {
    final controller = _controller(_assignedFlow(null));
    addTearDown(controller.dispose);

    await controller.load();
    await drainFlowTasks();

    expect(controller.renderedAssignment, isNull);
  });

  testWidgets('renderedAssignment SURVIVES a later render failure',
      (tester) async {
    final controller = _controller(_assignedFlow(armA));
    addTearDown(controller.dispose);

    await tester.runAsync(controller.load);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(controller: controller),
    ));
    await tester.pump();
    expect(controller.renderedAssignment, equals(armA));

    // A late render failure fails the flow closed and clears the frame stack.
    controller.reportRenderFailure(StateError('boom'));

    // The assignment of the artifact that DID render is retained.
    final observed = controller.renderedAssignment;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(observed, equals(armA));
  });

  test(
      'FlowStarted.toMap() emits NO assignment keys '
      '(assignment exposure requires an explicit contract change)', () {
    const started = FlowStarted(
      flowId: 'first_run',
      flowVersion: 1,
      flowSessionId: 'session-1',
    );
    final map = started.toMap();
    expect(map.containsKey('experimentId'), isFalse);
    expect(map.containsKey('variantId'), isFalse);
    expect(map.containsKey('experimentEpoch'), isFalse);
  });

  test(
      'a resolve that never renders leaves renderedAssignment null '
      '(a rejected fresh arm is never stamped)', () async {
    final controller = RestageFlowController<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: const _ThrowingResolver(),
      actions: null,
      onEvent: (_) {},
      onComplete: (_) {},
      onUnavailable: (_) {},
    );
    addTearDown(controller.dispose);

    await controller.load();
    await drainFlowTasks();

    expect(controller.renderedAssignment, isNull);
  });

  test('controller disposal is idempotent without an external retention set',
      () {
    final controller = _controller(_assignedFlow(null));

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

/// The default first-run flow, tagged with [assignment] as its artifact-owned
/// arm (null for an artifact with no experiment).
ResolvedFlow _assignedFlow(FlowAssignment? assignment) {
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
    assignment: assignment,
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
