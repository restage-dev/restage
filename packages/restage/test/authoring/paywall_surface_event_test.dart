import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

abstract final class _Events {
  static const subscribe = SurfaceEvent<Map<String, Object?>>('subscribe');
  static const pick = SurfaceEvent<String>('pick');
  static const close = SurfaceEvent<void>('close');
  static const restore = SurfaceEvent<void>('restore');
}

// Captures the callback its build creates.
Widget _capture(void Function(BuildContext context) onBuild) =>
    Builder(builder: (context) {
      onBuild(context);
      return const SizedBox();
    });

void main() {
  testWidgets('a paywall event with no dispatcher refuses', (tester) async {
    late VoidCallback callback;
    await tester.pumpWidget(
      _capture((context) => callback = context.surfaceEvent(_Events.close)),
    );

    expect(callback, throwsAssertionError);
  });

  testWidgets('a paywall receives the event name and its arguments',
      (tester) async {
    final received = <(String, Map<String, Object?>)>[];
    late VoidCallback map;
    late VoidCallback scalar;
    late VoidCallback none;
    await tester.pumpWidget(
      RestagePaywallEventDispatcher(
        onEvent: (name, args) => received.add((name, args)),
        child: _capture((context) {
          map = context.surfaceEvent(
            _Events.subscribe,
            const <String, Object?>{'plan': 'monthly'},
          );
          scalar = context.surfaceEvent(_Events.pick, 'annual');
          none = context.surfaceEvent(_Events.close);
        }),
      ),
    );

    map();
    scalar();
    none();

    expect(received.map((event) => event.$1), ['subscribe', 'pick', 'close']);
    expect(received.map((event) => event.$2), [
      {'plan': 'monthly'},
      {'value': 'annual'},
      isEmpty,
    ]);
  });

  testWidgets('the dispatcher drops the reserved bare restore event',
      (tester) async {
    var received = false;
    late VoidCallback callback;
    await tester.pumpWidget(
      RestagePaywallEventDispatcher(
        onEvent: (_, __) => received = true,
        child: _capture(
          (context) => callback = context.surfaceEvent(_Events.restore),
        ),
      ),
    );

    callback();

    expect(received, isFalse);
  });

  testWidgets('a retained callback fires the current handler', (tester) async {
    final received = <String>[];
    late StateSetter updateHost;
    PaywallEventHandler handler = (_, __) => received.add('first');
    VoidCallback? retained;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          updateHost = setState;
          return RestagePaywallEventDispatcher(
            onEvent: handler,
            child: _capture(
              (context) => retained ??= context.surfaceEvent(_Events.close),
            ),
          );
        },
      ),
    );

    updateHost(() => handler = (_, __) => received.add('second'));
    await tester.pump();
    retained!();

    expect(received, <String>['second']);
  });

  testWidgets('a retained callback refuses once its widget is gone',
      (tester) async {
    var received = 0;
    late VoidCallback callback;
    await tester.pumpWidget(
      RestagePaywallEventDispatcher(
        onEvent: (_, __) => received++,
        child: _capture(
          (context) => callback = context.surfaceEvent(_Events.close),
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox());

    expect(callback, throwsAssertionError);
    expect(received, 0);
  });

  testWidgets('sibling paywalls each receive their own events', (tester) async {
    final received = <String>[];
    final callbacks = <String, VoidCallback>{};
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: [
            for (final name in ['first', 'second'])
              RestagePaywallEventDispatcher(
                onEvent: (event, _) => received.add('$name:$event'),
                child: _capture(
                  (context) =>
                      callbacks[name] = context.surfaceEvent(_Events.close),
                ),
              ),
          ],
        ),
      ),
    );

    callbacks['second']!();
    callbacks['first']!();

    expect(received, ['second:close', 'first:close']);
  });

  testWidgets('a nested paywall receives the events built inside it',
      (tester) async {
    final received = <String>[];
    late VoidCallback outer;
    late VoidCallback inner;
    await tester.pumpWidget(
      RestagePaywallEventDispatcher(
        onEvent: (event, _) => received.add('outer:$event'),
        child: Column(
          children: [
            _capture((context) => outer = context.surfaceEvent(_Events.close)),
            RestagePaywallEventDispatcher(
              onEvent: (event, _) => received.add('inner:$event'),
              child: _capture(
                (context) => inner = context.surfaceEvent(_Events.close),
              ),
            ),
          ],
        ),
      ),
    );

    inner();
    outer();

    expect(received, ['inner:close', 'outer:close']);
  });
}
