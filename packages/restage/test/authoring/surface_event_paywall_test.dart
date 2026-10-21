import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/authoring/onboarding_event_dispatcher.dart'
    show DeclaredEventDispatcher;
import 'package:restage/src/authoring/paywall_event_dispatch.dart'
    show RestagePaywallEventTargetScope;

const _subscribe = SurfaceEvent<String>('subscribe');
const _plan = SurfaceEvent<Map<String, Object?>>('plan');
const _close = SurfaceEvent<void>('close');

void main() {
  testWidgets('surfaceEvent in a paywall fires a paywall event',
      (tester) async {
    final received = <(String, Map<String, Object?>)>[];
    final callbacks = <void Function([Object?])>[];
    await tester.pumpWidget(
      RestagePaywallEventDispatcher(
        onEvent: (name, args) => received.add((name, args)),
        child: Builder(
          builder: (_) {
            callbacks
              ..add(surfaceEvent(_subscribe, 'yearly'))
              ..add(surfaceEvent(_plan, const <String, Object?>{'id': 'a'}))
              ..add(surfaceEvent(_close));
            return const SizedBox();
          },
        ),
      ),
    );

    for (final callback in callbacks) {
      callback();
    }
    callbacks.first('monthly');

    expect(received.map((event) => event.$1),
        ['subscribe', 'plan', 'close', 'subscribe']);
    expect(received.map((event) => event.$2), [
      {'value': 'yearly'},
      {'id': 'a'},
      isEmpty,
      {'value': 'monthly'},
    ]);
  });

  testWidgets('a paywall over a mounted flow receives its own events',
      (tester) async {
    final paywall = <String>[];
    final flow = <String>[];
    void Function([Object?])? subscribe;
    void Function([Object?])? flowNext;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            DeclaredEventDispatcher(
              surfaceName: 'onboarding',
              // The flow beneath declares the paywall's event id too.
              declares: (id) => id == 'next' || id == 'subscribe',
              onEvent: (name, _) => flow.add(name),
              child: Builder(
                builder: (_) {
                  flowNext = surfaceEvent(const SurfaceEvent<void>('next'));
                  return const SizedBox();
                },
              ),
            ),
            RestagePaywallEventDispatcher(
              onEvent: (name, _) => paywall.add(name),
              child: Builder(
                builder: (_) {
                  subscribe = surfaceEvent(_subscribe, 'yearly');
                  return const SizedBox();
                },
              ),
            ),
          ],
        ),
      ),
    );

    subscribe!();
    flowNext!();

    expect(paywall, ['subscribe']);
    expect(flow, ['next']);
  });

  testWidgets('a paywall that is a flow step leaves its events to the flow',
      (tester) async {
    final paywall = <String>[];
    final flow = <String>[];
    void Function([Object?])? subscribe;
    await tester.pumpWidget(
      DeclaredEventDispatcher(
        surfaceName: 'onboarding',
        declares: (id) => id == 'subscribe',
        onEvent: (name, _) => flow.add(name),
        child: RestagePaywallEventTargetScope(
          owner: Object(),
          content: Object(),
          isCurrent: () => true,
          flowStep: true,
          child: RestagePaywallEventDispatcher(
            onEvent: (name, _) => paywall.add(name),
            child: Builder(
              builder: (_) {
                subscribe = surfaceEvent(_subscribe, 'yearly');
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );

    subscribe!();

    expect(flow, ['subscribe']);
    expect(paywall, isEmpty);
  });
}
