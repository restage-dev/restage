import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_core/restage_core.dart' show RestageIslandStage;

final class _NoArguments implements DataSource {
  @override
  T? v<T extends Object>(List<Object> argsKey) => null;

  @override
  int length(List<Object> argsKey) => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

// The arguments of an island placed at [item] in one loop.
final class _At implements DataSource {
  const _At(this.item);
  final int item;

  @override
  T? v<T extends Object>(List<Object> argsKey) =>
      argsKey.length == 2 && argsKey.first == 'restageItems' ? item as T : null;

  @override
  int length(List<Object> argsKey) => argsKey.single == 'restageItems' ? 1 : 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

var _starts = 0;

class _Counter extends StatefulWidget {
  const _Counter();
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int count = 0;
  @override
  void initState() {
    super.initState();
    _starts++;
  }

  @override
  Widget build(BuildContext context) =>
      Text('$count', textDirection: TextDirection.ltr);
}

Widget _island(BuildContext context) =>
    RestageIslandScope.build('counter', 'missing', context, _NoArguments());

/// Versions of one mount, each with its own subtree, as a host shows them:
/// the shown one first, a staged one above it.
Widget _host(Object owner,
        List<({Object version, bool staged, int copies})> versions) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: RestageIslandScope(
        owner: owner,
        builders: {'counter': (context, source) => const _Counter()},
        child: Stack(children: [
          for (final v in versions)
            KeyedSubtree(
              key: ObjectKey(v.version),
              child: RestageIslandStage(
                candidate: v.staged,
                child: Column(children: [
                  for (var i = 0; i < v.copies; i++) Builder(builder: _island),
                ]),
              ),
            ),
        ]),
      ),
    );

void main() {
  testWidgets('an island keeps its element across versions of its mount',
      (tester) async {
    _starts = 0;
    final owner = Object();
    final first = Object(), second = Object();
    await tester
        .pumpWidget(_host(owner, [(version: first, staged: false, copies: 1)]));
    tester.state<_CounterState>(find.byType(_Counter)).count = 7;

    // Staged beside the shown version, the new one builds no island.
    await tester.pumpWidget(_host(owner, [
      (version: first, staged: false, copies: 1),
      (version: second, staged: true, copies: 1),
    ]));
    expect(tester.takeException(), isNull);
    expect(find.byType(_Counter), findsOneWidget);

    // Promoted, it takes the shown island with its state.
    await tester.pumpWidget(
        _host(owner, [(version: second, staged: false, copies: 1)]));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tester.state<_CounterState>(find.byType(_Counter)).count, 7);
    expect(_starts, 1);
  });

  // Publishing refuses a version that places an item-free island twice; if
  // one still does, the duplicate key fails it in debug builds.
  testWidgets('a double placement fails closed', (tester) async {
    await tester.pumpWidget(
        _host(Object(), [(version: Object(), staged: false, copies: 2)]));
    expect(tester.takeException(), isNotNull);
  });

  testWidgets('an island in a loop keys each iteration apart', (tester) async {
    _starts = 0;
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageIslandScope(
        owner: Object(),
        builders: {'counter': (context, source) => const _Counter()},
        child: Column(children: [
          for (var i = 0; i < 3; i++)
            Builder(
                builder: (context) => RestageIslandScope.build(
                    'counter', 'missing', context, _At(i))),
        ]),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.byType(_Counter), findsNWidgets(3));
    expect(_starts, 3);
  });

  testWidgets(
      'an island that moves within its version starts at most once more',
      (tester) async {
    _starts = 0;
    final owner = Object();
    final version = Object();
    Widget host({required bool padded, int build = 0}) => Directionality(
          textDirection: TextDirection.ltr,
          child: RestageIslandScope(
            owner: owner,
            // A new map each build rebuilds every island.
            builders: {
              'counter': (context, source) => const _Counter(),
              if (build > 0)
                'unused$build': (context, source) => const Text(''),
            },
            child: KeyedSubtree(
              key: ObjectKey(version),
              child: RestageIslandStage(
                candidate: false,
                child: Column(children: [
                  if (padded)
                    const Padding(
                        padding: EdgeInsets.zero,
                        child: Builder(builder: _island))
                  else
                    const Builder(builder: _island),
                ]),
              ),
            ),
          ),
        );
    await tester.pumpWidget(host(padded: false));
    await tester.pumpWidget(host(padded: true));
    final moved = _starts;
    await tester.pumpWidget(host(padded: true, build: 1));
    expect(tester.takeException(), isNull);
    // The move keeps the island's element, and the next rebuild too.
    expect(moved, 1);
    expect(_starts, 1);
    expect(find.byType(KeyedSubtree, skipOffstage: false), findsNWidgets(2));
  });

  testWidgets(
      'an island moved to an earlier cell keeps its element through '
      'a swap', (tester) async {
    _starts = 0;
    final owner = Object();
    Widget host(Object version, {required bool left}) => Directionality(
          textDirection: TextDirection.ltr,
          child: RestageIslandScope(
            owner: owner,
            builders: {'counter': (context, source) => const _Counter()},
            child: KeyedSubtree(
              key: ObjectKey(version),
              child: RestageIslandStage(
                candidate: false,
                child: Row(children: [
                  Expanded(
                    child: left
                        ? const Builder(builder: _island)
                        : const SizedBox(),
                  ),
                  Expanded(
                    child: left
                        ? const SizedBox()
                        : const Builder(builder: _island),
                  ),
                ]),
              ),
            ),
          ),
        );
    final first = Object();
    await tester.pumpWidget(host(first, left: false));
    await tester.pumpWidget(host(first, left: true));
    await tester.pump();
    expect(_starts, 1);
    await tester.pumpWidget(host(Object(), left: true));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(_starts, 1);
    expect(find.byType(_Counter), findsOneWidget);
  });
}
