import 'dart:async';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

import 'flow_test_support.dart';

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
  });

  testWidgets('publishes price data to flow-screen render data',
      (tester) async {
    Restage.debugReset();
    Restage.configure(
      apiKey: 'pk_test',
      products: const [
        RestageProduct(id: 'pro_annual', slot: 'annual', entitlement: 'pro'),
      ],
    );
    addTearDown(Restage.debugReset);

    final blob = priceScreenBlob();
    final controller = controllerFor(
      resolvedFlow(screenBlobs: {'welcome': blob}),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageScreenView(
        controller: controller,
        priceQueries: const {
          'pro_annual': PriceInfo(
            localizedPrice: r'$59.99',
            priceMicros: 59990000,
            currency: 'USD',
            title: 'Annual',
            description: 'One year',
          ),
        },
      ),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();

    expect(find.text(r'$59.99'), findsOneWidget);
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
  });
}
