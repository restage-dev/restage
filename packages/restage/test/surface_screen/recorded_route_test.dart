import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/authoring/onboarding_event.dart'
    show RecordedEventHost;

const _close = SurfaceEvent<void>('close');

// A screen the route shows, firing from its own context as app code does.
Widget _closeButton() => Builder(
      builder: (context) => TextButton(
        onPressed: context.surfaceEvent(_close),
        child: const Text('Close'),
      ),
    );

void main() {
  // The surface sits below the app's navigator, as a generated mount's does,
  // and [push] runs from [mount], the mount's own context above it.
  Future<void> pumpSurface(
    WidgetTester tester, {
    required Widget Function(Object owner, Widget child) surface,
    required void Function(BuildContext mount, RestageRecording recording) push,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (mount) {
        final recording = RestageRecording(owner: mount);
        return surface(
          mount,
          DefaultTextStyle(
            style: const TextStyle(fontSize: 31),
            child: TextButton(
              onPressed: () => push(mount, recording),
              child: const Text('Open'),
            ),
          ),
        );
      }),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets("a route a mount pushes fires on the mount's surface",
      (tester) async {
    final received = <String>[];
    await pumpSurface(
      tester,
      surface: (owner, child) => RestageEventDispatcher(
        onEvent: (name, _) => received.add(name),
        child: RecordedEventHost(owner: owner, child: child),
      ),
      push: (mount, recording) => Navigator.of(mount).push(
        MaterialPageRoute<void>(
          builder: (_) => recording.route(_closeButton()),
        ),
      ),
    );

    await tester.tap(find.text('Close'));
    expect(received, ['close']);
    // The route keeps Flutter's own inheritance: only the event scopes come.
    expect(
      DefaultTextStyle.of(tester.element(find.text('Close'))).style.fontSize,
      isNot(31),
    );
  });

  testWidgets('without the recording, the route refuses with the fix',
      (tester) async {
    final received = <String>[];
    await pumpSurface(
      tester,
      surface: (owner, child) => RestageEventDispatcher(
        onEvent: (name, _) => received.add(name),
        child: RecordedEventHost(owner: owner, child: child),
      ),
      push: (mount, _) => Navigator.of(mount).push(
        MaterialPageRoute<void>(builder: (_) => _closeButton()),
      ),
    );

    await tester.tap(find.text('Close'));
    expect(
      tester.takeException(),
      isA<AssertionError>().having(
        (error) => '${error.message}',
        'message',
        contains(
          'wrap the route\'s content in `InheritedTheme.capture(from: '
          'context, to: Navigator.of(context).context).wrap(...)`',
        ),
      ),
    );
    expect(received, isEmpty);
  });

  testWidgets("a route a paywall's mount pushes fires on the paywall",
      (tester) async {
    final received = <String>[];
    await pumpSurface(
      tester,
      surface: (owner, child) => RestagePaywallEventDispatcher(
        onEvent: (name, _) => received.add(name),
        child: RecordedEventHost(owner: owner, child: child),
      ),
      push: (mount, recording) => Navigator.of(mount).push(
        MaterialPageRoute<void>(
          builder: (_) => recording.route(_closeButton()),
        ),
      ),
    );

    await tester.tap(find.text('Close'));
    expect(received, ['close']);
  });

  testWidgets("a dialog a mount opens fires on the mount's surface",
      (tester) async {
    final received = <String>[];
    await pumpSurface(
      tester,
      surface: (owner, child) => RestageEventDispatcher(
        onEvent: (name, _) => received.add(name),
        child: RecordedEventHost(owner: owner, child: child),
      ),
      push: (mount, recording) => showDialog<void>(
        context: mount,
        builder: (_) => recording.route(_closeButton()),
      ),
    );

    await tester.tap(find.text('Close'));
    expect(received, ['close']);
  });

  testWidgets("a route a step mount pushes fires on the step's surface",
      (tester) async {
    final received = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: RestageEventDispatcher(
        onEvent: (name, _) => received.add(name),
        child: Builder(builder: (step) {
          final recording = RestageRecording(mount: step);
          return TextButton(
            onPressed: () => Navigator.of(step).push(
              MaterialPageRoute<void>(
                builder: (_) => recording.route(_closeButton()),
              ),
            ),
            child: const Text('Open'),
          );
        }),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Close'));
    expect(received, ['close']);
  });

  testWidgets('a navigator inside the surface needs no wrapping',
      (tester) async {
    final received = <String>[];
    final navigator = GlobalKey<NavigatorState>();
    late RestageRecording recording;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (mount) {
        recording = RestageRecording(owner: mount);
        return RestageEventDispatcher(
          onEvent: (name, _) => received.add(name),
          child: RecordedEventHost(
            owner: mount,
            child: Navigator(
              key: navigator,
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (_) => const Text('Root'),
              ),
            ),
          ),
        );
      }),
    ));
    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => recording.route(_closeButton())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Close'));
    expect(received, ['close']);
  });
}
