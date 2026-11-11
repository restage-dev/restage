import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

// Fires its event from its own build, as an island's app code does.
final class _Island extends StatelessWidget {
  const _Island(this.name);

  final String name;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: context.surfaceEvent(SurfaceEvent<void>(name)),
        child: Text(name, textDirection: TextDirection.ltr),
      );
}

void main() {
  final owner = Object();
  final other = Object();

  Widget dispatcher(Object mount, List<String> into, Widget child) =>
      RestagePaywallEventDispatcher(
        onEvent: (name, _) => into.add(name),
        mount: mount,
        child: child,
      );

  testWidgets('a recorded event built before its dispatcher reaches it',
      (tester) async {
    final received = <String>[];
    final recording = RestageRecording(owner: owner);
    final onTap = recording.surfaceEvent(
      const SurfaceEvent<Map<String, Object?>>('top'),
      {'plan': 'pro'},
    );
    await tester.pumpWidget(dispatcher(
      owner,
      received,
      GestureDetector(
        onTap: onTap,
        child: const Text('top', textDirection: TextDirection.ltr),
      ),
    ));
    await tester.tap(find.text('top'));
    expect(received, ['top']);
  });

  testWidgets('a recorded event goes to its own mount among several',
      (tester) async {
    final mine = <String>[];
    final theirs = <String>[];
    final recording = RestageRecording(owner: owner);
    await tester.pumpWidget(Column(children: [
      dispatcher(other, theirs, const SizedBox()),
      dispatcher(
        owner,
        mine,
        GestureDetector(
          onTap: recording.surfaceEvent(const SurfaceEvent<void>('top')),
          child: const Text('top', textDirection: TextDirection.ltr),
        ),
      ),
    ]));
    await tester.tap(find.text('top'));
    expect(mine, ['top']);
    expect(theirs, isEmpty);
  });

  testWidgets('an island that fires events builds inside its dispatcher',
      (tester) async {
    final mine = <String>[];
    final theirs = <String>[];
    final recording = RestageRecording(owner: owner);
    await tester.pumpWidget(Column(children: [
      dispatcher(other, theirs, const SizedBox()),
      dispatcher(
        owner,
        mine,
        recording.island('island', const _Island('inner')),
      ),
    ]));
    await tester.tap(find.text('inner'));
    expect(tester.takeException(), isNull);
    expect(mine, ['inner']);
    expect(theirs, isEmpty);
  });

  testWidgets('a step recording fires through the surface its mount is in',
      (tester) async {
    final received = <String>[];
    await tester.pumpWidget(RestageEventDispatcher(
      onEvent: (name, _) => received.add(name),
      child: Builder(builder: (context) {
        final recording = RestageRecording(owner: Object(), mount: context);
        return GestureDetector(
          onTap: recording.surfaceEvent(const SurfaceEvent<void>('next')),
          child: const Text('next', textDirection: TextDirection.ltr),
        );
      }),
    ));
    await tester.tap(find.text('next'));
    expect(tester.takeException(), isNull);
    expect(received, ['next']);
  });

  testWidgets('a recording with no mount context refuses its events',
      (tester) async {
    final received = <String>[];
    late VoidCallback onTap;
    await tester.pumpWidget(RestageEventDispatcher(
      onEvent: (name, _) => received.add(name),
      child: Builder(builder: (context) {
        onTap = RestageRecording(owner: Object())
            .surfaceEvent(const SurfaceEvent<void>('next'));
        return const SizedBox();
      }),
    ));
    expect(onTap, throwsAssertionError);
    expect(received, isEmpty);
  });
}
