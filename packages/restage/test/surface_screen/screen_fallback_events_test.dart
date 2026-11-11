import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_shared/restage_shared.dart';

import '../fixtures/compiled_surfaces/native_flow.dart';
import 'surface_screen_test_support.dart';

const _pick = SurfaceEvent<String>('pick');
const _close = SurfaceEvent<void>('close');
const _undeclared = SurfaceEvent<void>('undeclared');

final _schema = SurfaceScreenEventSchemaV1Codec.decode(jsonDecode(
  '{"schemaVersion":1,"events":['
  '{"id":"close","arguments":{"encoding":"none"}},'
  '{"id":"pick","arguments":{"encoding":"value","shape":{"kind":"string"}}}]}',
));

ScreenFixture<String> _fixture({String slug = 'picker'}) => stringScreenFixture(
      slug: slug,
      schema: _schema,
      packagesBundle: false,
      decoder: (name, arguments) => switch (name) {
        'pick' => 'pick:${arguments['value']}',
        _ => name,
      },
    );

final class _Original extends StatefulWidget {
  const _Original();

  @override
  State<_Original> createState() => _OriginalState();
}

final class _OriginalState extends State<_Original> {
  var choice = 'a';

  @override
  Widget build(BuildContext context) => Column(
        children: [
          TextButton(
            onPressed: () => setState(() => choice = 'b'),
            child: const Text('Choose b'),
          ),
          TextButton(
            onPressed: context.surfaceEvent(_pick, choice),
            child: const Text('Pick'),
          ),
          TextButton(
              onPressed: context.surfaceEvent(_close),
              child: const Text('Close')),
          TextButton(
            onPressed: context.surfaceEvent(_undeclared),
            child: const Text('Undeclared'),
          ),
        ],
      );
}

Widget _mount(
  ScreenFixture<String> fixture, {
  SurfaceScreenResolver? resolver,
  ValueChanged<String>? onEvent,
}) =>
    MaterialApp(
      home: Scaffold(
        body: _screen(fixture, resolver: resolver, onEvent: onEvent),
      ),
    );

Widget _screen(
  ScreenFixture<String> fixture, {
  SurfaceScreenResolver? resolver,
  ValueChanged<String>? onEvent,
  Widget original = const _Original(),
}) =>
    RestageScreen<String>(
      screen: fixture.ref,
      resolver: resolver,
      onEvent: onEvent,
      fallbackBuilder: (_) => original,
    );

const _dismiss = SurfaceEvent<void>('dismiss');

ScreenFixture<String> _dismissFixture() => stringScreenFixture(
      slug: 'notice',
      schema: SurfaceScreenEventSchemaV1Codec.decode(jsonDecode(
        '{"schemaVersion":1,"events":['
        '{"id":"dismiss","arguments":{"encoding":"none"}}]}',
      )),
      packagesBundle: false,
    );

final class _Notice extends StatelessWidget {
  const _Notice();

  @override
  Widget build(BuildContext context) => TextButton(
      onPressed: context.surfaceEvent(_dismiss), child: const Text('Dismiss'));
}

final class _FlowScreenWithMessage extends StatelessWidget {
  const _FlowScreenWithMessage({required this.onEvent});

  final ValueChanged<String> onEvent;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          TextButton(
            onPressed: context.surfaceEvent(NativePreferences.done),
            child: const Text('Done'),
          ),
          _screen(_fixture(), onEvent: onEvent),
        ],
      );
}

void main() {
  setUp(resetSurfaceScreenTestState);

  final resolvers = <String, SurfaceScreenResolver? Function()>{
    'no configuration': () => null,
    'a failing resolver': () => FailingScreenResolver(
          const SurfaceScreenUnavailableError(
            reason: SurfaceScreenUnavailableReason.missing,
            message: 'Delivery failed.',
          ),
        ),
  };

  for (final MapEntry(key: label, value: resolver) in resolvers.entries) {
    testWidgets('fallback original delivers typed events with $label',
        (tester) async {
      final events = <String>[];
      await tester.pumpWidget(
        _mount(_fixture(), resolver: resolver(), onEvent: events.add),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choose b'));
      await tester.pump();
      await tester.tap(find.text('Pick'));
      await tester.tap(find.text('Close'));
      await tester.pump();

      expect(events, ['pick:b', 'close']);
    });
  }

  testWidgets('fallback original reports an event outside the contract',
      (tester) async {
    final events = <String>[];
    await tester.pumpWidget(_mount(_fixture(), onEvent: events.add));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Undeclared'));
    await tester.pump();

    expect(tester.takeException(), isFormatException);
    expect(events, isEmpty);
    expect(find.text('Pick'), findsOneWidget);
  });

  testWidgets('side-by-side fallbacks of different screens both deliver',
      (tester) async {
    final events = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          _screen(_fixture(), onEvent: (e) => events.add('picker:$e')),
          _screen(
            _dismissFixture(),
            onEvent: (e) => events.add('notice:$e'),
            original: const _Notice(),
          ),
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Dismiss'));
    await tester.tap(find.text('Close'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(events, ['notice:dismiss', 'picker:close']);
  });

  testWidgets('a screen fallback inside a flow original routes by event',
      (tester) async {
    final events = <String>[];
    NativeClassResult? result;
    final compiled = nativeClassFlowRef.compiled!;
    final flow = OnboardingFlowRef<NativeClassResult>(
      id: nativeClassFlowRef.id,
      version: nativeClassFlowRef.version,
      minClient: nativeClassFlowRef.minClient,
      surface: Surface.onboarding,
      decodeResult: (_) => const NativeClassResult(),
      compiled: CompiledFlow(
        documentJson: compiled.documentJson,
        screens: {
          'native_preferences': () => _FlowScreenWithMessage(
                onEvent: (e) => events.add('picker:$e'),
              ),
        },
      ),
    );
    await tester.pumpWidget(MaterialApp(
      home: RestageFlowGraph<NativeClassResult>(
        flow: flow,
        onComplete: (r) => result = r,
      ),
    ));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Close'));
    await tester.pump();
    expect(events, ['picker:close']);
    expect(result, isNull);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(result, isA<NativeClassResult>());
  });

  testWidgets('copies of a screen each deliver to their own mount',
      (tester) async {
    final events = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          _screen(_fixture(), onEvent: (e) => events.add('first:$e')),
          _screen(_fixture(), onEvent: (e) => events.add('second:$e')),
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Choose b').last);
    await tester.pump();
    await tester.tap(find.text('Pick').last);
    await tester.tap(find.text('Close').first);
    await tester.tap(find.text('Pick').first);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(events, ['second:pick:b', 'first:close', 'first:pick:a']);
  });

  testWidgets('copies built lazily in a list own their taps', (tester) async {
    final events = <String>[];
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final fixture = _fixture();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView.builder(
          controller: scroll,
          itemCount: 40,
          itemExtent: 100,
          itemBuilder: (_, index) => _screen(
            fixture,
            onEvent: (e) => events.add('row$index:$e'),
            original: _Row(index),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    scroll.jumpTo(2500);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close 27'));
    await tester.tap(find.text('Close 26'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(events, ['row27:close', 'row26:close']);
  });

  testWidgets('nested screens each own the events their widgets fire',
      (tester) async {
    final events = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: _screen(
          _fixture(),
          onEvent: (e) => events.add('outer:$e'),
          original: Column(children: [
            const _Row(1),
            _screen(
              _fixture(slug: 'inner'),
              onEvent: (e) => events.add('inner:$e'),
              original: const _Row(2),
            ),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close 2'));
    await tester.tap(find.text('Close 1'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(events, ['inner:close', 'outer:close']);
  });

  testWidgets('a dialog opened from a copy fires on the copy', (tester) async {
    final events = <String>[];
    final fixture = _fixture();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          for (final name in ['first', 'second'])
            _screen(
              fixture,
              onEvent: (e) => events.add('$name:$e'),
              original: _DialogOpener(name),
            ),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('second open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('second dialog close'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(events, ['second:close']);
  });

  for (final outer in [true, false]) {
    testWidgets(
        'a dialog fires on the screen that opened it '
        '(${outer ? 'with' : 'without'} a surface above the navigator)',
        (tester) async {
      final outerEvents = <String>[];
      final events = <String>[];
      final app = MaterialApp(
        home: Scaffold(
          body: _screen(
            _fixture(),
            onEvent: events.add,
            original: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (dialogContext) => TextButton(
                    onPressed: dialogContext.surfaceEvent(_close),
                    child: const Text('dialog close'),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(outer
          ? RestageEventDispatcher(
              onEvent: (name, _) => outerEvents.add(name),
              child: app,
            )
          : app);
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('dialog close'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(events, ['close']);
      expect(outerEvents, isEmpty);
    });
  }

  testWidgets('a bottom sheet fires on the paywall that opened it',
      (tester) async {
    final events = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywallEventDispatcher(
          onEvent: (name, _) => events.add(name),
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                builder: (sheetContext) => TextButton(
                  onPressed: sheetContext.surfaceEvent(_close),
                  child: const Text('sheet close'),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('sheet close'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(events, ['close']);
  });
}

final class _Row extends StatelessWidget {
  const _Row(this.index);

  final int index;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: context.surfaceEvent(_close),
        child: Text('Close $index'),
      );
}

// The dialog's button fires with the opener's context, which is inside the
// copy; the dialog's own context is under the root navigator.
final class _DialogOpener extends StatelessWidget {
  const _DialogOpener(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    final close = context.surfaceEvent(_close);
    return TextButton(
      onPressed: () => showDialog<void>(
        context: context,
        builder: (dialogContext) => Center(
          child: TextButton(
            onPressed: () {
              close();
              Navigator.of(dialogContext).pop();
            },
            child: Text('$name dialog close'),
          ),
        ),
      ),
      child: Text('$name open'),
    );
  }
}
