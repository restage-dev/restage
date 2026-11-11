import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_widgetbook_example/onboarding/screens/get_started_screen.dart';

// A generated mount records its original in its own build, above the screen
// it creates; its events must still reach that screen, and only it.
void main() {
  setUp(Restage.debugReset);
  tearDown(Restage.debugReset);

  testWidgets('copies of a recorded mount each deliver their own events', (
    tester,
  ) async {
    final events = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              for (final name in ['first', 'second'])
                Expanded(child: _mount(name, events)),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final actions = find.byKey(const ValueKey('get-started-action'));
    expect(actions, findsNWidgets(2));
    await tester.tap(actions.last);
    await tester.tap(actions.first);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(events, ['second', 'first']);
  });

  testWidgets('a recorded callback refuses after its own mount is gone', (
    tester,
  ) async {
    final events = <String>[];
    final showFirst = ValueNotifier(true);
    addTearDown(showFirst.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: showFirst,
            builder: (_, show, _) => Column(
              children: [
                if (show) Expanded(child: _mount('first', events)),
                Expanded(child: _mount('second', events)),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final retained = tester
        .widget<ElevatedButton>(
          find.byKey(const ValueKey('get-started-action')).first,
        )
        .onPressed!;

    showFirst.value = false;
    await tester.pumpAndSettle();

    expect(retained, throwsAssertionError);
    expect(events, isEmpty);
  });
}

Widget _mount(String name, List<String> events) => GetStartedScreenSurface(
  key: ValueKey(name),
  title: name,
  resolver: _UnavailableResolver(),
  onEvent: (_) => events.add(name),
);

final class _UnavailableResolver implements SurfaceScreenResolver {
  @override
  Future<ResolvedSurfaceScreen> resolve<E>(SurfaceScreenRef<E> screen) async =>
      throw const SurfaceScreenUnavailableError(
        reason: SurfaceScreenUnavailableReason.missing,
        message: 'The screen is unavailable.',
      );
}
