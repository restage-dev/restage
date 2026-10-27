import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:rfw/formats.dart' as rfw;
import 'package:rfw/rfw.dart';

const _root = LibraryName(['test']);
const _core = LibraryName(['restage', 'core']);

final class _Identity extends StatefulWidget {
  const _Identity(this.id, {super.key});
  final String id;
  @override
  State<_Identity> createState() => _IdentityState();
}

final class _IdentityState extends State<_Identity> {
  late final initial = widget.id;
  @override
  Widget build(BuildContext context) => Text('$initial:${widget.id}');
}

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(home: SizedBox(width: 300, height: 150, child: child)));

Widget _remote(Runtime runtime, DynamicContent data) => RemoteWidget(
    runtime: runtime,
    data: data,
    widget: const FullyQualifiedWidgetName(_root, 'Root'));

void main() {
  testWidgets('source alias casts keep each native generic and branch timing',
      (tester) async {
    final dsl = File('test/fixtures/grid_scalar/casts.rfw').readAsStringSync();
    final runtime = Runtime()
      ..update(_core, buildCoreWidgetLibrary())
      ..update(_root, rfw.parseLibraryFile(dsl));
    await _pump(tester, _remote(runtime, DynamicContent()));
    final callback = (tester
            .widget<GridView>(find.byType(GridView))
            .childrenDelegate as SliverChildBuilderDelegate)
        .findChildIndexCallback!;
    int native(Key key) {
      final alias = key;
      final number = alias as ValueKey<num>;
      if (number.value < 0) {
        // ignore: unused_local_variable
        final narrowed = number as ValueKey<int>;
        // The local cast is eager even though its value is unused.
        return 0;
      }
      return 1;
    }

    for (final key in [const ValueKey<int>(-2), const ValueKey<double>(2)]) {
      expect(callback(key), native(key));
    }
    for (final key in [
      const ValueKey<double>(-2),
      const ValueKey<num>(-2),
    ]) {
      expect(() => native(key), throwsA(isA<TypeError>()));
      expect(() => callback(key), throwsA(isA<TypeError>()));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('called helpers preserve native key casts and lazy branches',
      (tester) async {
    final runtime = Runtime()
      ..update(_core, buildCoreWidgetLibrary())
      ..update(
          _root,
          rfw.parseLibraryFile(File('test/fixtures/grid_scalar/helpers.rfw')
              .readAsStringSync()));
    await _pump(tester, _remote(runtime, DynamicContent()));
    final callback = (tester
            .widget<GridView>(find.byType(GridView))
            .childrenDelegate as SliverChildBuilderDelegate)
        .findChildIndexCallback!;
    int readKey(Key key) {
      final number = key as ValueKey<num>;
      return number.value < 0 ? (number as ValueKey<int>).value : 1;
    }

    int forward(Key key) {
      final alias = key;
      return readKey(alias);
    }

    for (final key in [const ValueKey<int>(-2), const ValueKey<double>(2)]) {
      expect(callback(key), forward(key));
    }
    for (final key in [const ValueKey<num>(-2), const ValueKey<double>(-2)]) {
      expect(() => forward(key), throwsA(isA<TypeError>()));
      expect(() => callback(key), throwsA(isA<TypeError>()));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('predicate context stays in the native lexical callback frame',
      (tester) async {
    final runtime = Runtime()
      ..update(_core, buildCoreWidgetLibrary())
      ..update(
          _root,
          rfw.parseLibraryFile(File('test/fixtures/grid_scalar/context.rfw')
              .readAsStringSync()));
    await _pump(
        tester,
        _remote(
            runtime,
            DynamicContent({
              'context': {
                'items': [
                  <String, Object>{},
                  {'id': 'b'}
                ]
              }
            })));
    final callback = (tester
            .widget<GridView>(find.byType(GridView))
            .childrenDelegate as SliverChildBuilderDelegate)
        .findChildIndexCallback!;
    expect(callback(const ValueKey<String?>(null)), 0);
    expect(callback(const ValueKey<String?>('b')), 1);
    for (final (theme, width) in [
      (ThemeData.dark(), 800.0),
      (ThemeData.light(), 50.0)
    ]) {
      await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: MediaQuery(
              data: MediaQueryData(size: Size(width, 150)),
              child: SizedBox(
                  width: 300,
                  height: 150,
                  child: _remote(
                      runtime,
                      DynamicContent({
                        'context': {
                          'items': [
                            <String, Object>{},
                            {'id': 'b'}
                          ]
                        }
                      }))))));
      await tester.pumpAndSettle();
      expect(Theme.of(tester.element(find.byType(GridView))).brightness,
          theme.brightness);
      final updated = (tester
              .widget<GridView>(find.byType(GridView))
              .childrenDelegate as SliverChildBuilderDelegate)
          .findChildIndexCallback!;
      expect(updated(const ValueKey<String?>(null)), -1);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('source nullable keys preserve typed lookup and reordered state',
      (tester) async {
    final dsl =
        File('test/fixtures/grid_scalar/nullable.rfw').readAsStringSync();
    var items = <String?>[null, 'b'];
    Widget native() => GridView.builder(
        primary: false,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, mainAxisExtent: 40),
        itemCount: items.length,
        itemBuilder: (_, index) => _Identity(items[index] ?? 'nil',
            key: ValueKey<String?>(items[index])),
        findChildIndexCallback: (key) => items
            .indexWhere((item) => item == (key as ValueKey<String?>).value));
    await _pump(tester, native());
    items = ['b', null];
    await _pump(tester, native());
    expect(find.text('b:b'), findsOneWidget);
    expect(find.text('nil:nil'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    final runtime = Runtime()
      ..update(
          _core,
          LocalWidgetLibrary({
            ...buildCoreWidgetLibrary().widgets,
            // A stateful body makes the compiled outer key identity observable.
            'Text': (context, source) => _Identity(source.v<String>(['text'])!),
          }))
      ..update(_root, rfw.parseLibraryFile(dsl));
    final data = DynamicContent({
      'context': {
        'items': [
          <String, Object>{},
          {'id': 'b'}
        ]
      }
    });
    await _pump(tester, _remote(runtime, data));
    data.update('context', {
      'items': [
        {'id': 'b'},
        <String, Object>{}
      ]
    });
    await tester.pump();
    expect(find.text('b:b'), findsOneWidget);
    expect(find.text('nil:nil'), findsOneWidget);
    final callback = (tester
            .widget<GridView>(find.byType(GridView))
            .childrenDelegate as SliverChildBuilderDelegate)
        .findChildIndexCallback!;
    expect(callback(const ValueKey<String?>(null)), 1);
    expect(
        () => callback(const ValueKey<int?>(null)), throwsA(isA<TypeError>()));
    expect(tester.takeException(), isNull);
  });
}
