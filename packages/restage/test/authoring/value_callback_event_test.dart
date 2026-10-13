import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

abstract final class _Survey {
  static const pick = SurfaceEvent<Object>('pick');
  static const next = SurfaceEvent<void>('next');
}

void main() {
  Future<List<(String, Object?)>> pumpSurface(
    WidgetTester tester,
    Widget Function() build,
  ) async {
    final events = <(String, Object?)>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: RestageOnboardingEventDispatcher(
            onEvent: (eventId, value) => events.add((eventId, value)),
            child: Builder(builder: (_) => build()),
          ),
        ),
      ),
    );
    return events;
  }

  testWidgets('a Switch fires the event it is given directly', (tester) async {
    final events = await pumpSurface(
      tester,
      () => Switch(value: false, onChanged: surfaceEvent(_Survey.pick, false)),
    );

    await tester.tap(find.byType(Switch));

    expect(events, [('pick', true)]);
  });

  testWidgets('a Checkbox fires the event it is given directly',
      (tester) async {
    final events = await pumpSurface(
      tester,
      () => Checkbox(value: false, onChanged: surfaceEvent(_Survey.pick)),
    );

    await tester.tap(find.byType(Checkbox));

    expect(events, [('pick', true)]);
  });

  testWidgets('a TextField fires the event it is given directly',
      (tester) async {
    final events = await pumpSurface(
      tester,
      () => TextField(onChanged: surfaceEvent(_Survey.pick)),
    );

    await tester.enterText(find.byType(TextField), 'annual');

    expect(events, [('pick', 'annual')]);
  });

  testWidgets('a tap callback keeps the authored value', (tester) async {
    final events = await pumpSurface(
      tester,
      () => TextButton(
        onPressed: surfaceEvent(_Survey.pick, 'annual'),
        child: const Text('Annual'),
      ),
    );

    await tester.tap(find.byType(TextButton));

    expect(events, [('pick', 'annual')]);
  });

  testWidgets('a void event fits a value callback', (tester) async {
    final events = await pumpSurface(
      tester,
      () => Switch(value: false, onChanged: surfaceEvent(_Survey.next)),
    );

    await tester.tap(find.byType(Switch));

    expect(events, [('next', true)]);
  });

  testWidgets('paywallEvent carries the widget value in its arguments',
      (tester) async {
    final received = <(String, Map<String, Object?>)>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: RestagePaywallEventDispatcher(
            onEvent: (name, args) => received.add((name, args)),
            child: Builder(
              builder: (_) => Column(
                children: [
                  Switch(
                    value: false,
                    onChanged: paywallEvent(
                      'toggle_trial',
                      args: const <String, Object?>{'plan': 'annual'},
                    ),
                  ),
                  TextButton(
                    onPressed: paywallEvent('close'),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(Switch));
    await tester.tap(find.byType(TextButton));

    expect(received.map((event) => event.$1), ['toggle_trial', 'close']);
    expect(received[0].$2, {'plan': 'annual', 'value': true});
    expect(received[1].$2, isEmpty);
  });
}
