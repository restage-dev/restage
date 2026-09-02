import 'dart:async';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:rfw/rfw.dart' show DynamicContent, RemoteWidget;

import 'flow_test_support.dart';

Map<Object?, Object?> _readContext(DynamicContent data) {
  void noop(Object _) {}
  final value = data.subscribe(const <Object>['context'], noop);
  data.unsubscribe(const <Object>['context'], noop);
  return value as Map<Object?, Object?>;
}

void main() {
  RestageFlowController<FirstRunResult> controllerFor(
    ResolvedFlow flow, {
    void Function(FlowUnavailableError error)? onUnavailable,
  }) {
    return RestageFlowController<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: StaticFlowResolver(flow),
      actions: null,
      onEvent: (_) {},
      onComplete: (_) {},
      onUnavailable: onUnavailable ?? (_) {},
    );
  }

  testWidgets('renders the controller current screen', (tester) async {
    final controller = controllerFor(resolvedFlow());
    addTearDown(controller.dispose);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageScreenView(controller: controller),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();

    expect(find.text('Welcome'), findsOneWidget);
    expect(controller.hasRenderedContent, isTrue);
  });

  testWidgets('publishes current context after each controlled screen advance',
      (tester) async {
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
    var hostContext = <String, Object?>{'label': 'first'};
    late StateSetter updateHost;

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          updateHost = setState;
          return Directionality(
            textDirection: TextDirection.ltr,
            child: RestageScreenView<FirstRunResult>(
              controller: controller,
              context: hostContext,
            ),
          );
        },
      ),
    );
    unawaited(controller.load());
    await tester.pump();
    expect(find.byType(RemoteWidget), findsNothing);

    hostContext['label'] = 'later';
    resolver.response.complete(contextResolvedFlow());
    await tester.pumpAndSettle();
    expect(find.text('first'), findsOneWidget);
    expect(find.text('later'), findsNothing);

    updateHost(() => hostContext = <String, Object?>{'label': 'second'});
    await tester.pump();
    await tester.tap(find.text('second'));
    await tester.pumpAndSettle();

    final data = tester.widget<RemoteWidget>(find.byType(RemoteWidget)).data;
    expect(_readContext(data)['label'], 'second');
    var notifications = 0;
    void onContext(Object _) => notifications += 1;
    data.subscribe(const <Object>['context'], onContext);

    updateHost(() => hostContext = <String, Object?>{'label': 'third'});
    await tester.pump();
    expect(find.text('third'), findsOneWidget);
    expect(notifications, 1);

    updateHost(() => hostContext = <String, Object?>{'label': 'third'});
    await tester.pump();
    expect(notifications, 1);
    data.unsubscribe(const <Object>['context'], onContext);
  });

  testWidgets(
      'routes the screen event through the controller and re-renders the new '
      'current screen', (tester) async {
    final controller = controllerFor(resolvedFlow());
    addTearDown(controller.dispose);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageScreenView(controller: controller),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();
    expect(find.text('Welcome'), findsOneWidget);

    await tester.tap(find.text('Welcome'));
    await tester.pumpAndSettle();

    // The single-screen surface renders only the *current* screen: profile is
    // now shown and welcome is gone (no keep-mounted stack).
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Welcome', skipOffstage: false), findsNothing);
  });

  testWidgets(
      'renders no chrome, back affordance, or transition — the host composes '
      'those', (tester) async {
    final controller = controllerFor(resolvedFlow());
    addTearDown(controller.dispose);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageScreenView(controller: controller),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Welcome'));
    await tester.pumpAndSettle();

    // Back is available on the controller, but RestageScreenView shows no
    // built-in chrome (the lower-level primitive — the host owns nav/chrome).
    expect(controller.canBack, isTrue);
    expect(find.byIcon(Icons.arrow_back), findsNothing);
    expect(find.byIcon(Icons.arrow_back_ios_new), findsNothing);
  });

  testWidgets('fails the controller closed when the screen throws on build',
      (tester) async {
    Restage.debugReset();
    registerThrowingWidget();
    addTearDown(Restage.debugReset);
    FlowUnavailableError? captured;
    final controller = controllerFor(
      throwingResolvedFlow(),
      onUnavailable: (error) => captured = error,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageScreenView(controller: controller),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();

    // The fail-closed RuntimeErrorBoundary absorbed the throw (nothing leaked to
    // the binding) and routed it to the controller, which failed closed.
    expect(tester.takeException(), isNull);
    expect(controller.isUnavailable, isTrue);
    expect(captured?.reason, 'render_failed');
    expect(controller.hasRenderedContent, isFalse);
  });
}
