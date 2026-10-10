import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/runtime/local_values.dart';
import 'package:rfw/formats.dart' show parseLibraryFile;
import 'package:rfw/rfw.dart';

const LibraryName _core = LibraryName(<String>['core']);
const LibraryName _probe = LibraryName(<String>['probe']);
const LibraryName _main = LibraryName(<String>['main']);

class _Input extends StatelessWidget {
  const _Input(this.onChanged);

  final ValueChanged<Object?>? onChanged;

  @override
  Widget build(BuildContext context) => const SizedBox();
}

Runtime _runtime() => Runtime()
  ..update(_core, createCoreWidgets())
  ..update(
    _probe,
    LocalWidgetLibrary(<String, LocalWidgetBuilder>{
      'Input': (context, source) => _Input(
            source.handler<ValueChanged<Object?>>(
              const <Object>['onChanged'],
              (trigger) =>
                  (value) => trigger(<String, Object?>{'value': value}),
            ),
          ),
    }),
  )
  ..update(
    _main,
    parseLibraryFile('''
      import core;
      import probe;
      widget root = Column(children: [
        Input(onChanged: event "restage.local.set" { key: "answer" }),
        Text(text: data.local.answer, textDirection: "ltr"),
      ]);
    '''),
  );

void main() {
  late List<String> forwarded;

  Future<LocalValues> mount(
    WidgetTester tester, {
    Map<String, Object>? seed,
  }) async {
    forwarded = <String>[];
    final data = DynamicContent();
    final local = LocalValues(data, seed: seed);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RemoteWidget(
          runtime: _runtime(),
          data: data,
          widget: const FullyQualifiedWidgetName(_main, 'root'),
          onEvent: (name, args) {
            if (!local.intercept(name, args)) forwarded.add(name);
          },
        ),
      ),
    );
    return local;
  }

  void type(WidgetTester tester, Object? value) =>
      tester.widget<_Input>(find.byType(_Input)).onChanged!(value);

  testWidgets('a seed shows before the first input', (tester) async {
    await mount(tester, seed: const <String, Object>{'answer': 'maybe'});
    expect(find.text('maybe'), findsOneWidget);
  });

  testWidgets('a value callback updates text reading data.local',
      (tester) async {
    final local =
        await mount(tester, seed: const <String, Object>{'answer': ''});

    type(tester, 'blue');
    await tester.pump();
    expect(find.text('blue'), findsOneWidget);

    type(tester, 'blue sky');
    await tester.pump();
    expect(find.text('blue sky'), findsOneWidget);
    expect(local.values, <String, Object>{'answer': 'blue sky'});
    expect(forwarded, isEmpty, reason: 'the reserved event is consumed');
  });

  test('other events are not consumed', () {
    final local = LocalValues(DynamicContent());
    expect(local.intercept('next', const <String, Object?>{}), isFalse);
  });

  test('numbers and bools are kept', () {
    final local = LocalValues(DynamicContent());
    local
      ..intercept(kLocalSetEventName, {'key': 'count', 'value': 3})
      ..intercept(kLocalSetEventName, {'key': 'ratio', 'value': 0.5})
      ..intercept(kLocalSetEventName, {'key': 'on', 'value': true});
    expect(
        local.values, <String, Object>{'count': 3, 'ratio': 0.5, 'on': true});
  });

  test('an invalid key or value is dropped and still consumed', () {
    final local = LocalValues(DynamicContent());
    final writes = <Map<String, Object?>>[
      {'key': '1st', 'value': 'x'},
      {'key': 'has space', 'value': 'x'},
      {'key': 'a' * 65, 'value': 'x'},
      {'key': 'long', 'value': 'x' * (kMaxLocalStringLength + 1)},
      {
        'key': 'list',
        'value': <Object>[1]
      },
      {
        'key': 'map',
        'value': <String, Object>{'a': 1}
      },
      {'key': 'nothing', 'value': null},
      {'key': 'nan', 'value': double.nan},
      {'value': 'x'},
    ];
    for (final write in writes) {
      expect(local.intercept(kLocalSetEventName, write), isTrue);
    }
    expect(local.intercept(kLocalSetEventName, 'not a map'), isTrue);
    expect(local.values, isEmpty);

    local.intercept(kLocalSetEventName, {
      'key': '_ok${'a' * 60}',
      'value': 'x' * kMaxLocalStringLength,
    });
    expect(local.values, hasLength(1));
  });

  test('an invalid seed entry is dropped', () {
    final local = LocalValues(
      DynamicContent(),
      seed: const <String, Object>{'ok': 'yes', 'no key': 'x'},
    );
    expect(local.values, <String, Object>{'ok': 'yes'});
  });

  test('a cleared map ignores later writes', () {
    final local = LocalValues(
      DynamicContent(),
      seed: const <String, Object>{'answer': 'a'},
    )..clear();
    local.intercept(kLocalSetEventName, {'key': 'answer', 'value': 'b'});
    expect(local.values, isEmpty);
  });
}
