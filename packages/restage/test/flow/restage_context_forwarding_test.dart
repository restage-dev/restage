import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/runtime/context_data.dart'
    show ContextSnapshot, RestageContextSnapshotScope;
import 'package:rfw/rfw.dart' show DynamicContent, RemoteWidget;

import 'flow_test_support.dart';

Object? _readContextLabel(DynamicContent data) {
  void noop(Object _) {}
  final value = data.subscribe(const <Object>['context'], noop);
  data.unsubscribe(const <Object>['context'], noop);
  return value is Map<Object?, Object?> ? value['label'] : value;
}

Object? _visibleLabel(WidgetTester tester) => _readContextLabel(
      tester.widget<RemoteWidget>(find.byType(RemoteWidget)).data,
    );

Future<void> _verifyContextPublication(
  WidgetTester tester,
  Widget Function(
    ControlledFlowResolver resolver,
    Map<String, Object?>? hostContext,
  ) buildHost,
) async {
  final resolver = ControlledFlowResolver();
  Map<String, Object?>? hostContext = <String, Object?>{'label': 'first'};
  late StateSetter updateHost;

  await tester.pumpWidget(
    MaterialApp(
      home: StatefulBuilder(
        builder: (context, setState) {
          updateHost = setState;
          return buildHost(resolver, hostContext);
        },
      ),
    ),
  );
  await tester.pump();
  final visibleBeforeResolution = find.text('first').evaluate().length;

  hostContext['label'] = 'later';
  resolver.response.complete(contextResolvedFlow());
  await tester.pumpAndSettle();
  final visibleInitially = find.text('first').evaluate().length;
  final laterVisibleInitially = find.text('later').evaluate().length;
  final data = tester.widget<RemoteWidget>(find.byType(RemoteWidget)).data;
  var notifications = 0;
  void onContext(Object _) {
    notifications += 1;
  }

  data.subscribe(const <Object>['context'], onContext);

  updateHost(() {
    hostContext = <String, Object?>{'label': 'first'};
  });
  await tester.pump();
  final notificationsAfterEqual = notifications;
  final equalLabelVisible = find.text('first').evaluate().length;

  updateHost(() {
    hostContext = <String, Object?>{'label': 'second'};
  });
  await tester.pump();
  final notificationsAfterChange = notifications;
  final changedLabelVisible = find.text('second').evaluate().length;

  updateHost(() {
    hostContext = null;
  });
  await tester.pump();
  final notificationsAfterWithdrawal = notifications;
  final changedLabelAfterWithdrawal = find.text('second').evaluate().length;

  data.unsubscribe(const <Object>['context'], onContext);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();

  expect(visibleBeforeResolution, 0);
  expect(visibleInitially, 1);
  expect(laterVisibleInitially, 0);
  expect(equalLabelVisible, 1);
  expect(notificationsAfterEqual, 0);
  expect(changedLabelVisible, 1);
  expect(notificationsAfterChange, 1);
  expect(changedLabelAfterWithdrawal, 0);
  expect(notificationsAfterWithdrawal, 2);
}

void main() {
  setUp(Restage.debugReset);

  testWidgets('flow graph publishes, deduplicates, and withdraws context', (
    tester,
  ) async {
    await _verifyContextPublication(
      tester,
      (resolver, hostContext) => RestageFlowGraph<FirstRunResult>(
        flow: firstRunFlowRef,
        resolver: resolver,
        context: hostContext,
        unavailable: FlowUnavailablePolicy.fallback(
          builder: (_, error) => Text(error.reason),
        ),
      ),
    );
  });

  testWidgets('onboarding publishes, deduplicates, and withdraws context', (
    tester,
  ) async {
    await _verifyContextPublication(
      tester,
      (resolver, hostContext) => RestageOnboarding<FirstRunResult>(
        flow: firstRunFlowRef,
        resolver: resolver,
        context: hostContext,
        unavailable: FlowUnavailablePolicy.fallback(
          builder: (_, error) => Text(error.reason),
        ),
      ),
    );
  });

  testWidgets(
      'a flow graph under a snapshotless ancestor tracks its own '
      'context updates', (tester) async {
    final resolver = ControlledFlowResolver();
    var hostContext = <String, Object?>{'label': 'free'};
    late StateSetter updateHost;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            updateHost = setState;
            return RestageContextSnapshotScope(
              snapshot: null,
              child: RestageFlowGraph<FirstRunResult>(
                flow: firstRunFlowRef,
                resolver: resolver,
                context: hostContext,
                unavailable: FlowUnavailablePolicy.fallback(
                  builder: (_, error) => Text(error.reason),
                ),
              ),
            );
          },
        ),
      ),
    );
    resolver.response.complete(contextResolvedFlow());
    await tester.pumpAndSettle();
    final initial = _visibleLabel(tester);

    updateHost(() => hostContext = <String, Object?>{'label': 'pro'});
    await tester.pumpAndSettle();
    final afterUpdate = _visibleLabel(tester);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(initial, 'free');
    expect(afterUpdate, 'pro');
  });

  testWidgets(
      'a flow view under a snapshotless ancestor tracks its own '
      'context updates', (tester) async {
    final resolver = ControlledFlowResolver();
    final controller = RestageFlowController<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: resolver,
      actions: null,
      onEvent: (_) {},
      onComplete: (_) {},
      onUnavailable: (_) {},
    );
    addTearDown(controller.dispose);
    var hostContext = <String, Object?>{'label': 'free'};
    late StateSetter updateHost;

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          updateHost = setState;
          return Directionality(
            textDirection: TextDirection.ltr,
            child: RestageContextSnapshotScope(
              snapshot: null,
              child: RestageFlowView<FirstRunResult>(
                controller: controller,
                context: hostContext,
              ),
            ),
          );
        },
      ),
    );
    unawaited(controller.load());
    resolver.response.complete(contextResolvedFlow());
    await tester.pumpAndSettle();
    final initial = _visibleLabel(tester);

    updateHost(() => hostContext = <String, Object?>{'label': 'pro'});
    await tester.pumpAndSettle();
    final afterUpdate = _visibleLabel(tester);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(initial, 'free');
    expect(afterUpdate, 'pro');
  });

  testWidgets('an ancestor snapshot supersedes the widget context parameter', (
    tester,
  ) async {
    final resolver = ControlledFlowResolver();

    await tester.pumpWidget(
      MaterialApp(
        home: RestageContextSnapshotScope(
          snapshot: ContextSnapshot.of(const <String, Object?>{
            'label': 'ancestor',
          }),
          child: RestageFlowGraph<FirstRunResult>(
            flow: firstRunFlowRef,
            resolver: resolver,
            context: const <String, Object?>{'label': 'own'},
            unavailable: FlowUnavailablePolicy.fallback(
              builder: (_, error) => Text(error.reason),
            ),
          ),
        ),
      ),
    );
    resolver.response.complete(contextResolvedFlow());
    await tester.pumpAndSettle();
    final label = _visibleLabel(tester);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(label, 'ancestor');
  });

  testWidgets(
      'an ancestor snapshot appearing later supersedes the widget '
      'context parameter', (tester) async {
    final resolver = ControlledFlowResolver();
    ContextSnapshot? ancestor;
    late StateSetter updateAncestor;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            updateAncestor = setState;
            return RestageContextSnapshotScope(
              snapshot: ancestor,
              child: RestageFlowGraph<FirstRunResult>(
                flow: firstRunFlowRef,
                resolver: resolver,
                context: const <String, Object?>{'label': 'own'},
                unavailable: FlowUnavailablePolicy.fallback(
                  builder: (_, error) => Text(error.reason),
                ),
              ),
            );
          },
        ),
      ),
    );
    resolver.response.complete(contextResolvedFlow());
    await tester.pumpAndSettle();
    final beforeAncestor = _visibleLabel(tester);

    updateAncestor(() {
      ancestor = ContextSnapshot.of(const <String, Object?>{
        'label': 'ancestor',
      });
    });
    await tester.pumpAndSettle();
    final afterAncestor = _visibleLabel(tester);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(beforeAncestor, 'own');
    expect(afterAncestor, 'ancestor');
  });
}
