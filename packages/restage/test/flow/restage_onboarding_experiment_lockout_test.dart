import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

import 'flow_test_support.dart';

/// Symmetric refresh lockout on the onboarding host: a live refresh must never
/// move a mounted surface INTO or OUT OF an experiment arm. Mirrors the paywall
/// host's four-boundary lockout. Test artifacts carry assignments to pin the
/// invariant without a request-side assignment key.
///
/// The four refresh boundaries map to two host check-sites (the ladder TIER that
/// sourced a candidate is pinned separately in the resolver attribution matrix):
///  - boundary 1 (current assignment) → `_canSwap` gate, BEFORE any fetch;
///  - boundaries 2/3/4 (candidate / promotion / hold-last-good) → the candidate
///    is fetched but its promotion is refused when it carries an arm.
void main() {
  setUp(Restage.debugReset);

  const armA = FlowAssignment(
    experimentId: 'exp_copy',
    variantId: 'variant_a',
    experimentEpoch: 3,
  );

  testWidgets(
      'boundary 1: a currently-arm-assigned surface never refreshes '
      '(gated BEFORE the fetch)', (tester) async {
    final resolver = _MutableFlowResolver(_assignedFlow('First', armA));
    await tester.pumpWidget(_host(resolver));
    await tester.pumpAndSettle();
    expect(find.text('First'), findsOneWidget);
    expect(resolver.calls, 1); // the mount resolve

    resolver.flow = _assignedFlow('Second', armA);
    await Restage.reloadSurfaces();
    await tester.pumpAndSettle();

    final firstCount = find.text('First').evaluate().length;
    final secondCount = find.text('Second').evaluate().length;
    final resolveCalls = resolver.calls;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    // The render is arm-assigned → the swap gate is closed BEFORE re-resolving:
    // no second fetch, and the original content stays.
    expect(firstCount, 1);
    expect(secondCount, 0);
    expect(resolveCalls, 1);
  });

  testWidgets(
      'boundary 2/3: a pristine surface refuses to promote a candidate that '
      'carries an arm (fetched, never swapped IN)', (tester) async {
    final resolver = _MutableFlowResolver(_assignedFlow('First', null));
    await tester.pumpWidget(_host(resolver));
    await tester.pumpAndSettle();
    expect(find.text('First'), findsOneWidget);

    // The current render carries no arm, so the gate opens and the refresh
    // fetches — but the candidate resolves INTO an arm, so it is never promoted.
    resolver.flow = _assignedFlow('Second', armA);
    await Restage.reloadSurfaces();
    await tester.pumpAndSettle();

    final firstCount = find.text('First').evaluate().length;
    final secondCount = find.text('Second').evaluate().length;
    final resolveCalls = resolver.calls;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(resolveCalls, 2); // the candidate WAS fetched (gate was open)
    expect(firstCount, 1); // but never swapped in
    expect(secondCount, 0);
  });

  testWidgets(
      'a refused arm promotion never moves the rendered assignment '
      '(a later no-arm candidate can still promote)', (tester) async {
    final resolver = _MutableFlowResolver(_assignedFlow('First', null));
    await tester.pumpWidget(_host(resolver));
    await tester.pumpAndSettle();

    // Rejecting the arm-bearing pending controller must not move the current
    // render's assignment. A later no-arm candidate is therefore still
    // eligible to refresh and promotes normally.
    resolver.flow = _assignedFlow('Second', armA);
    await Restage.reloadSurfaces();
    await tester.pumpAndSettle();

    resolver.flow = _assignedFlow('Third', null);
    await Restage.reloadSurfaces();
    await tester.pumpAndSettle();

    final firstCount = find.text('First').evaluate().length;
    final secondCount = find.text('Second').evaluate().length;
    final thirdCount = find.text('Third').evaluate().length;
    final resolveCalls = resolver.calls;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(resolveCalls, 3);
    expect(thirdCount, 1);
    expect(firstCount, 0);
    expect(secondCount, 0);
  });

  testWidgets(
      'an assigned initial-sub-flow candidate stays pending until its child '
      'screen is ready and never replaces the current render', (tester) async {
    const childArm = FlowAssignment(
      experimentId: 'exp_child',
      variantId: 'variant_child',
      experimentEpoch: 8,
    );
    final child = childScreenFlow(assignment: childArm);
    final childCompleter = Completer<ResolvedFlow>();
    final resolver = ControlledInitialSubFlowResolver(
      root: _assignedFlow('Current', null),
      child: childCompleter,
    );
    await tester.pumpWidget(_host(resolver));
    await tester.pumpAndSettle();

    resolver.root = initialSubFlowRoot(child: child, assignment: armA);
    await Restage.reloadSurfaces();
    await tester.pump();
    final currentWhileChildPending = find.text('Current').evaluate().length;

    childCompleter.complete(child);
    await tester.pumpAndSettle();
    final currentAfterChildReady = find.text('Current').evaluate().length;
    final childAfterReady = find.text('Child').evaluate().length;

    // The assigned pending controller was discarded. Its readiness listener
    // must be detached so a later ordinary refresh can promote normally.
    resolver.root = _assignedFlow('Replacement', null);
    resolver.child = Completer<ResolvedFlow>();
    await Restage.reloadSurfaces();
    await tester.pumpAndSettle();
    final replacementAfterDiscard = find.text('Replacement').evaluate().length;
    final rootCalls = resolver.rootCalls;
    final childCalls = resolver.childCalls;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(currentWhileChildPending, 1);
    expect(currentAfterChildReady, 1);
    expect(childAfterReady, 0);
    expect(replacementAfterDiscard, 1);
    expect(rootCalls, 3);
    expect(childCalls, 1);
  });

  testWidgets(
      'an initial-sub-flow child failure discards the pending candidate and '
      'keeps the current render', (tester) async {
    final child = childScreenFlow();
    final childCompleter = Completer<ResolvedFlow>();
    final resolver = ControlledInitialSubFlowResolver(
      root: _assignedFlow('Current', null),
      child: childCompleter,
    );
    await tester.pumpWidget(_host(resolver));
    await tester.pumpAndSettle();

    resolver.root = initialSubFlowRoot(child: child, assignment: armA);
    await Restage.reloadSurfaces();
    await tester.pump();
    final currentWhileChildPending = find.text('Current').evaluate().length;

    // Complete resolution with an artifact that does not match the root's
    // pinned child hash. Validation fails inside the controller's guarded
    // resolution path without injecting an unhandled Future error into the
    // mounted RuntimeErrorBoundary test zone.
    childCompleter.complete(childScreenFlow(text: 'Wrong child'));
    await tester.pumpAndSettle();
    final currentAfterChildFailure = find.text('Current').evaluate().length;

    // Failure discards only the pending controller and its readiness listener;
    // the current host remains refreshable.
    resolver.root = _assignedFlow('Replacement', null);
    resolver.child = Completer<ResolvedFlow>();
    await Restage.reloadSurfaces();
    await tester.pumpAndSettle();
    final replacementAfterFailure = find.text('Replacement').evaluate().length;
    final rootCalls = resolver.rootCalls;
    final childCalls = resolver.childCalls;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(currentWhileChildPending, 1);
    expect(currentAfterChildFailure, 1);
    expect(replacementAfterFailure, 1);
    expect(rootCalls, 3);
    expect(childCalls, 1);
  });

  testWidgets(
      'promotion observes readiness when a screenless child returns to the '
      'already-started root', (tester) async {
    const childArm = FlowAssignment(
      experimentId: 'exp_child',
      variantId: 'variant_child',
      experimentEpoch: 8,
    );
    final child = screenlessChildFlow(assignment: childArm);
    final childCompleter = Completer<ResolvedFlow>();
    final resolver = ControlledInitialSubFlowResolver(
      root: _assignedFlow('Current', null),
      child: childCompleter,
    );
    await tester.pumpWidget(_host(resolver));
    await tester.pumpAndSettle();

    // Root assignment governs the presentation. The assigned child completes
    // without rendering, then the unassigned root installs its first screen.
    resolver.root = initialSubFlowThenScreenRoot(
      child: child,
      text: 'Replacement',
    );
    await Restage.reloadSurfaces();
    await tester.pump();
    final currentWhileChildPending = find.text('Current').evaluate().length;

    childCompleter.complete(child);
    await tester.pumpAndSettle();
    final replacementAfterChild = find.text('Replacement').evaluate().length;
    final currentAfterChild = find.text('Current').evaluate().length;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(currentWhileChildPending, 1);
    expect(replacementAfterChild, 1);
    expect(currentAfterChild, 0);
  });

  testWidgets(
      'a superseded pending readiness listener cannot promote its late child',
      (tester) async {
    final abandonedChild = Completer<ResolvedFlow>();
    final resolver = ControlledInitialSubFlowResolver(
      root: _assignedFlow('Current', null),
      child: abandonedChild,
    );
    await tester.pumpWidget(_host(resolver));
    await tester.pumpAndSettle();

    resolver.root = initialSubFlowRoot(
      child: childScreenFlow(text: 'Abandoned'),
    );
    await Restage.reloadSurfaces();
    await tester.pump();
    final currentWhileFirstPending = find.text('Current').evaluate().length;

    // A second refresh supersedes the first pending controller before its
    // child resolves and promotes its own ready screen.
    resolver.root = _assignedFlow('Replacement', null);
    resolver.child = Completer<ResolvedFlow>();
    await Restage.reloadSurfaces();
    await tester.pumpAndSettle();
    final replacementBeforeLateChild =
        find.text('Replacement').evaluate().length;

    abandonedChild.complete(childScreenFlow(text: 'Abandoned'));
    await tester.pumpAndSettle();
    final replacementAfterLateChild =
        find.text('Replacement').evaluate().length;
    final abandonedAfterLateChild = find.text('Abandoned').evaluate().length;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(currentWhileFirstPending, 1);
    expect(replacementBeforeLateChild, 1);
    expect(replacementAfterLateChild, 1);
    expect(abandonedAfterLateChild, 0);
  });

  testWidgets('disposing the host detaches a pending readiness listener',
      (tester) async {
    final childCompleter = Completer<ResolvedFlow>();
    final resolver = ControlledInitialSubFlowResolver(
      root: _assignedFlow('Current', null),
      child: childCompleter,
    );
    await tester.pumpWidget(_host(resolver));
    await tester.pumpAndSettle();

    resolver.root = initialSubFlowRoot(child: childScreenFlow());
    await Restage.reloadSurfaces();
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    childCompleter.complete(childScreenFlow());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a pristine → pristine (no-arm) refresh still swaps normally '
      '(the lockout does not over-block)', (tester) async {
    final resolver = _MutableFlowResolver(_assignedFlow('First', null));
    await tester.pumpWidget(_host(resolver));
    await tester.pumpAndSettle();
    expect(find.text('First'), findsOneWidget);

    resolver.flow = _assignedFlow('Second', null);
    await Restage.reloadSurfaces();
    await tester.pumpAndSettle();

    expect(find.text('Second'), findsOneWidget);
    expect(find.text('First'), findsNothing);
  });

  testWidgets(
      '_start (a config-identity change) is a NEW PRESENTATION: mounting into '
      'an arm is allowed, not an in-place swap', (tester) async {
    final resolver = _MutableFlowResolver(_assignedFlow('First', null));
    await tester.pumpWidget(_host(resolver));
    await tester.pumpAndSettle();
    expect(find.text('First'), findsOneWidget);

    // A different resolver identity → didUpdateWidget → _start: a hard restart,
    // which is a NEW presentation. Mounting fresh into an arm is allowed (it is
    // not a live in-place swap of an existing session).
    final restarted = _MutableFlowResolver(_assignedFlow('Second', armA));
    await tester.pumpWidget(_host(restarted));
    await tester.pumpAndSettle();

    expect(find.text('Second'), findsOneWidget);
    expect(find.text('First'), findsNothing);
  });
}

Widget _host(FlowResolver resolver) => Directionality(
      textDirection: TextDirection.ltr,
      child: RestageOnboarding<FirstRunResult>(
        flow: firstRunFlowRef,
        resolver: resolver,
        unavailable: const FlowUnavailablePolicy.hide(),
      ),
    );

/// A pristine two-screen first-run flow rendering [welcomeText], tagged with
/// [assignment] (null = no experiment arm).
ResolvedFlow _assignedFlow(String welcomeText, FlowAssignment? assignment) {
  final welcome = screenBlob(welcomeText, 'next');
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

class _MutableFlowResolver implements FlowResolver {
  _MutableFlowResolver(this.flow);
  ResolvedFlow flow;
  int calls = 0;

  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) async {
    calls++;
    return this.flow;
  }
}
