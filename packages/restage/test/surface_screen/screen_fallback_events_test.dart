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
            onPressed: surfaceEvent(_pick, choice),
            child: const Text('Pick'),
          ),
          TextButton(
              onPressed: surfaceEvent(_close), child: const Text('Close')),
          TextButton(
            onPressed: surfaceEvent(_undeclared),
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
      unavailable: SurfaceScreenUnavailablePolicy.fallback(
        builder: (_, __) => original,
      ),
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
      onPressed: surfaceEvent(_dismiss), child: const Text('Dismiss'));
}

final class _FlowScreenWithMessage extends StatelessWidget {
  const _FlowScreenWithMessage({required this.onEvent});

  final ValueChanged<String> onEvent;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          TextButton(
            onPressed: surfaceEvent(NativePreferences.done),
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
        unavailable: const FlowUnavailablePolicy.hide(),
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

  testWidgets('two copies of the same screen refuse and name the screen',
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

    Object? failure;
    try {
      await tester.tap(find.text('Close').last);
    } on Object catch (error) {
      failure = error;
    }
    failure ??= tester.takeException();

    expect(events, isEmpty);
    expect(failure, isA<AssertionError>());
    expect(
      (failure! as AssertionError).message,
      '[restage] surfaceEvent refused authored event dispatch: dispatcher '
      'ownership is ambiguous (more than one mounted surface declares the '
      'event: picker, picker).',
    );
  });
}
