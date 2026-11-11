import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

const _subscribe = SurfaceEvent<String>('subscribe');
const _plan = SurfaceEvent<Map<String, Object?>>('plan');
const _close = SurfaceEvent<void>('close');

void main() {
  testWidgets('context.surfaceEvent in a paywall fires a paywall event',
      (tester) async {
    final received = <(String, Map<String, Object?>)>[];
    final callbacks = <void Function([Object?])>[];
    await tester.pumpWidget(
      RestagePaywallEventDispatcher(
        onEvent: (name, args) => received.add((name, args)),
        child: Builder(
          builder: (context) {
            callbacks
              ..add(context.surfaceEvent(_subscribe, 'yearly'))
              ..add(context
                  .surfaceEvent(_plan, const <String, Object?>{'id': 'a'}))
              ..add(context.surfaceEvent(_close));
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
            RestageEventDispatcher(
              onEvent: (name, _) => flow.add(name),
              child: Builder(
                builder: (context) {
                  flowNext =
                      context.surfaceEvent(const SurfaceEvent<void>('next'));
                  return const SizedBox();
                },
              ),
            ),
            RestagePaywallEventDispatcher(
              onEvent: (name, _) => paywall.add(name),
              child: Builder(
                builder: (context) {
                  subscribe = context.surfaceEvent(_subscribe, 'yearly');
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
}
