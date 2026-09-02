import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

import 'flow_test_support.dart';

/// Refreshes keep an ordinary mounted surface eligible for new content.
void main() {
  setUp(Restage.debugReset);

  testWidgets('a pristine surface refreshes its active content',
      (tester) async {
    final resolver = _MutableFlowResolver(_resolvedFlow('First'));
    await tester.pumpWidget(_host(resolver));
    await tester.pumpAndSettle();
    expect(find.text('First'), findsOneWidget);
    expect(resolver.calls, 1);

    resolver.flow = _resolvedFlow('Second');
    await Restage.reloadSurfaces();
    await tester.pumpAndSettle();

    final firstCount = find.text('First').evaluate().length;
    final secondCount = find.text('Second').evaluate().length;
    final resolveCalls = resolver.calls;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(firstCount, 0);
    expect(secondCount, 1);
    expect(resolveCalls, 2);
  });

  testWidgets('a pristine surface promotes an active refresh candidate',
      (tester) async {
    final resolver = _MutableFlowResolver(_resolvedFlow('First'));
    await tester.pumpWidget(_host(resolver));
    await tester.pumpAndSettle();
    expect(find.text('First'), findsOneWidget);

    resolver.flow = _resolvedFlow('Second');
    await Restage.reloadSurfaces();
    await tester.pumpAndSettle();

    final firstCount = find.text('First').evaluate().length;
    final secondCount = find.text('Second').evaluate().length;
    final resolveCalls = resolver.calls;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(resolveCalls, 2);
    expect(firstCount, 0);
    expect(secondCount, 1);
  });

  testWidgets('successive pristine refreshes promote ordinary content',
      (tester) async {
    final resolver = _MutableFlowResolver(_resolvedFlow('First'));
    await tester.pumpWidget(_host(resolver));
    await tester.pumpAndSettle();

    resolver.flow = _resolvedFlow('Second');
    await Restage.reloadSurfaces();
    await tester.pumpAndSettle();

    resolver.flow = _resolvedFlow('Third');
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
      'an initial sub-flow candidate stays pending until its child screen is '
      'ready', (tester) async {
    final child = childScreenFlow();
    final childCompleter = Completer<ResolvedFlow>();
    final resolver = ControlledInitialSubFlowResolver(
      root: _resolvedFlow('Current'),
      child: childCompleter,
    );
    await tester.pumpWidget(_host(resolver));
    await tester.pumpAndSettle();

    resolver.root = initialSubFlowRoot(child: child);
    await Restage.reloadSurfaces();
    await tester.pump();
    final currentWhileChildPending = find.text('Current').evaluate().length;

    childCompleter.complete(child);
    await tester.pumpAndSettle();
    final currentAfterChildReady = find.text('Current').evaluate().length;
    final childAfterReady = find.text('Child').evaluate().length;

    resolver.root = _resolvedFlow('Replacement');
    resolver.child = Completer<ResolvedFlow>();
    await Restage.reloadSurfaces();
    await tester.pumpAndSettle();
    final replacementAfterDiscard = find.text('Replacement').evaluate().length;
    final rootCalls = resolver.rootCalls;
    final childCalls = resolver.childCalls;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(currentWhileChildPending, 1);
    expect(currentAfterChildReady, 0);
    expect(childAfterReady, 1);
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
      root: _resolvedFlow('Current'),
      child: childCompleter,
    );
    await tester.pumpWidget(_host(resolver));
    await tester.pumpAndSettle();

    resolver.root = initialSubFlowRoot(child: child);
    await Restage.reloadSurfaces();
    await tester.pump();
    final currentWhileChildPending = find.text('Current').evaluate().length;

    childCompleter.complete(childScreenFlow(text: 'Wrong child'));
    await tester.pumpAndSettle();
    final currentAfterChildFailure = find.text('Current').evaluate().length;

    resolver.root = _resolvedFlow('Replacement');
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
    final child = screenlessChildFlow();
    final childCompleter = Completer<ResolvedFlow>();
    final resolver = ControlledInitialSubFlowResolver(
      root: _resolvedFlow('Current'),
      child: childCompleter,
    );
    await tester.pumpWidget(_host(resolver));
    await tester.pumpAndSettle();

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
      root: _resolvedFlow('Current'),
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

    resolver.root = _resolvedFlow('Replacement');
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
      root: _resolvedFlow('Current'),
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

  testWidgets('a pristine refresh swaps normally', (tester) async {
    final resolver = _MutableFlowResolver(_resolvedFlow('First'));
    await tester.pumpWidget(_host(resolver));
    await tester.pumpAndSettle();
    expect(find.text('First'), findsOneWidget);

    resolver.flow = _resolvedFlow('Second');
    await Restage.reloadSurfaces();
    await tester.pumpAndSettle();

    expect(find.text('Second'), findsOneWidget);
    expect(find.text('First'), findsNothing);
  });

  testWidgets('a resolver identity change starts a new presentation',
      (tester) async {
    final resolver = _MutableFlowResolver(_resolvedFlow('First'));
    await tester.pumpWidget(_host(resolver));
    await tester.pumpAndSettle();
    expect(find.text('First'), findsOneWidget);

    final restarted = _MutableFlowResolver(_resolvedFlow('Second'));
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

/// A pristine two-screen first-run flow rendering [welcomeText].
ResolvedFlow _resolvedFlow(String welcomeText) {
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
