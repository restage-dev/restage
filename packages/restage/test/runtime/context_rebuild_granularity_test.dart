import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/runtime/context_data.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart' hide WidgetLibrary;

const _localLibrary = LibraryName(<String>['acme', 'widgets']);
const _remoteLibrary = LibraryName(<String>['acme', 'surface']);
const _rootWidget = FullyQualifiedWidgetName(_remoteLibrary, 'Root');

const _source = '''
import acme.widgets;
widget Root = Probe(id: 'root', label: 'static', children: [
  Probe(id: 'a', label: data.context.a),
  Probe(id: 'b', label: data.context.b),
  Probe(id: 'parent', label: data.context.parentLabel, children: [
    Probe(id: 'child', label: 'static'),
  ]),
  Probe(id: 'host', label: 'static', children: [
    ...for item in data.context.items:
      Probe(id: item.id, label: item.name, trackIdentity: true),
  ]),
]);
''';

final class _IdentityProbe extends StatefulWidget {
  const _IdentityProbe({
    required this.authoredId,
    required this.allocateToken,
    required this.recordToken,
    required this.child,
  });

  final String authoredId;
  final int Function() allocateToken;
  final void Function(String authoredId, int token) recordToken;
  final Widget child;

  @override
  State<_IdentityProbe> createState() => _IdentityProbeState();
}

final class _IdentityProbeState extends State<_IdentityProbe> {
  late final int _token;

  @override
  void initState() {
    super.initState();
    _token = widget.allocateToken();
  }

  @override
  Widget build(BuildContext context) {
    widget.recordToken(widget.authoredId, _token);
    return widget.child;
  }
}

final class _GranularityHarness {
  _GranularityHarness()
      : runtime = Runtime(),
        data = DynamicContent() {
    publisher = ContextPublisher(data);
    runtime
      ..update(
        _localLibrary,
        LocalWidgetLibrary(<String, LocalWidgetBuilder>{'Probe': _buildProbe}),
      )
      ..update(_remoteLibrary, parseLibraryFile(_source));
  }

  final Map<String, int> counts = <String, int>{};
  final Map<String, int> identityTokens = <String, int>{};
  final Runtime runtime;
  final DynamicContent data;
  late final ContextPublisher publisher;
  int _nextIdentityToken = 0;

  Widget _buildProbe(BuildContext context, DataSource source) {
    final id = source.v<String>(const <Object>['id'])!;
    counts[id] = (counts[id] ?? 0) + 1;
    final child = Column(
      children: <Widget>[
        Text(
          source.v<String>(const <Object>['label']) ?? '',
          textDirection: TextDirection.ltr,
        ),
        ...source.childList(const <Object>['children']),
      ],
    );
    if (source.v<bool>(const <Object>['trackIdentity']) != true) return child;
    return _IdentityProbe(
      authoredId: id,
      allocateToken: () => ++_nextIdentityToken,
      recordToken: (authoredId, token) {
        identityTokens[authoredId] = token;
      },
      child: child,
    );
  }
}

Future<_GranularityHarness> _mount(
  WidgetTester tester,
  Map<String, Object?> initialContext, {
  List<String> rowIds = const <String>[],
}) async {
  final harness = _GranularityHarness();
  harness.publisher.publish(initialContext);
  await tester.pumpWidget(
    RemoteWidget(
      runtime: harness.runtime,
      data: harness.data,
      widget: _rootWidget,
      onEvent: (_, __) {},
    ),
  );
  await tester.pump();
  addTearDown(harness.runtime.dispose);
  expect(harness.counts, <String, int>{
    'root': 1,
    'a': 1,
    'b': 1,
    'parent': 1,
    'child': 1,
    'host': 1,
    for (final id in rowIds) id: 1,
  });
  return harness;
}

Map<String, int> _snapshot(Map<String, int> counts) =>
    Map<String, int>.of(counts);

Map<String, int> _deltas(
  Map<String, int> before,
  Map<String, int> after,
  List<String> ids,
) =>
    <String, int>{
      for (final id in ids) id: (after[id] ?? 0) - (before[id] ?? 0),
    };

void _expectMeasured(
  String caseName,
  Map<String, int> actual,
  Map<String, int> expected,
) {
  expect(actual, expected, reason: caseName);
}

Map<String, Object?> _context({
  String a = 'A',
  String b = 'B',
  String parentLabel = 'Parent',
  List<Object?>? items,
}) =>
    <String, Object?>{
      'a': a,
      'b': b,
      'parentLabel': parentLabel,
      if (items != null) 'items': items,
    };

Map<String, Object?> _item(String id, String name) => <String, Object?>{
      'id': id,
      'name': name,
    };

void main() {
  testWidgets('a scalar change rebuilds only its bound probe', (tester) async {
    final harness = await _mount(tester, _context());
    final before = _snapshot(harness.counts);

    harness.publisher.publish(_context(a: 'A2'));
    await tester.pump();

    _expectMeasured(
      'scalar-only',
      _deltas(
        before,
        harness.counts,
        const <String>['root', 'a', 'b', 'parent', 'child', 'host'],
      ),
      <String, int>{
        'root': 0,
        'a': 1,
        'b': 0,
        'parent': 0,
        'child': 0,
        'host': 0,
      },
    );
  });

  testWidgets('equal snapshots rebuild no probes', (tester) async {
    final raw = _context(items: <Object?>[_item('one', 'One')]);
    final snapshot = ContextSnapshot.of(raw);
    final harness = _GranularityHarness();
    harness.publisher.publishSnapshot(snapshot);
    await tester.pumpWidget(
      RemoteWidget(
        runtime: harness.runtime,
        data: harness.data,
        widget: _rootWidget,
        onEvent: (_, __) {},
      ),
    );
    await tester.pump();
    addTearDown(harness.runtime.dispose);
    expect(harness.counts, <String, int>{
      'root': 1,
      'a': 1,
      'b': 1,
      'parent': 1,
      'child': 1,
      'host': 1,
      'one': 1,
    });
    final before = _snapshot(harness.counts);

    harness.publisher.publishSnapshot(snapshot);
    await tester.pump();
    final equal = ContextSnapshot.of(
      _context(items: <Object?>[_item('one', 'One')]),
      previous: snapshot,
    );
    expect(identical(equal, snapshot), isTrue);
    harness.publisher.publishSnapshot(equal);
    await tester.pump();

    _expectMeasured(
      'identical-republish',
      _deltas(
        before,
        harness.counts,
        const <String>['root', 'a', 'b', 'parent', 'child', 'host', 'one'],
      ),
      <String, int>{
        'root': 0,
        'a': 0,
        'b': 0,
        'parent': 0,
        'child': 0,
        'host': 0,
        'one': 0,
      },
    );
  });

  testWidgets('an unchanged list rebuilds its host on another context change', (
    tester,
  ) async {
    final harness = await _mount(
      tester,
      _context(items: <Object?>[_item('one', 'One')]),
      rowIds: const <String>['one'],
    );
    final before = _snapshot(harness.counts);

    harness.publisher.publish(
      _context(a: 'A2', items: <Object?>[_item('one', 'One')]),
    );
    await tester.pump();

    _expectMeasured(
      'unchanged-list',
      _deltas(
        before,
        harness.counts,
        const <String>['root', 'a', 'b', 'parent', 'child', 'host', 'one'],
      ),
      <String, int>{
        'root': 0,
        'a': 1,
        'b': 0,
        'parent': 0,
        'child': 0,
        'host': 1,
        'one': 1,
      },
    );
  });

  testWidgets('appending a list item rebuilds rows positionally',
      (tester) async {
    final harness = await _mount(
      tester,
      _context(
        items: <Object?>[_item('one', 'One'), _item('two', 'Two')],
      ),
      rowIds: const <String>['one', 'two'],
    );
    final before = _snapshot(harness.counts);

    harness.publisher.publish(
      _context(
        items: <Object?>[
          _item('one', 'One'),
          _item('two', 'Two'),
          _item('three', 'Three'),
        ],
      ),
    );
    await tester.pump();

    _expectMeasured(
      'append',
      _deltas(
        before,
        harness.counts,
        const <String>['root', 'host', 'one', 'two', 'three'],
      ),
      <String, int>{
        'root': 0,
        'host': 1,
        'one': 1,
        'two': 1,
        'three': 1,
      },
    );
  });

  testWidgets('inserting at zero rebuilds rows positionally', (tester) async {
    final harness = await _mount(
      tester,
      _context(
        items: <Object?>[_item('one', 'One'), _item('two', 'Two')],
      ),
      rowIds: const <String>['one', 'two'],
    );
    final before = _snapshot(harness.counts);
    final identitiesBefore = _snapshot(harness.identityTokens);

    harness.publisher.publish(
      _context(
        items: <Object?>[
          _item('zero', 'Zero'),
          _item('one', 'One'),
          _item('two', 'Two'),
        ],
      ),
    );
    await tester.pump();

    _expectMeasured(
      'insert-at-zero',
      _deltas(
        before,
        harness.counts,
        const <String>['root', 'host', 'zero', 'one', 'two'],
      ),
      <String, int>{
        'root': 0,
        'host': 1,
        'zero': 1,
        'one': 1,
        'two': 1,
      },
    );
    expect(harness.identityTokens['zero'], identitiesBefore['one']);
    expect(harness.identityTokens['one'], identitiesBefore['two']);
    expect(
      harness.identityTokens['two'],
      isNot(anyOf(identitiesBefore['one'], identitiesBefore['two'])),
    );
  });

  testWidgets('reordering rows keeps state with positions', (tester) async {
    final harness = await _mount(
      tester,
      _context(
        items: <Object?>[_item('one', 'One'), _item('two', 'Two')],
      ),
      rowIds: const <String>['one', 'two'],
    );
    final before = _snapshot(harness.counts);
    final identitiesBefore = _snapshot(harness.identityTokens);

    harness.publisher.publish(
      _context(
        items: <Object?>[_item('two', 'Two'), _item('one', 'One')],
      ),
    );
    await tester.pump();

    _expectMeasured(
      'reorder',
      _deltas(
        before,
        harness.counts,
        const <String>['root', 'host', 'one', 'two'],
      ),
      <String, int>{'root': 0, 'host': 1, 'one': 1, 'two': 1},
    );
    expect(harness.identityTokens['two'], identitiesBefore['one']);
    expect(harness.identityTokens['one'], identitiesBefore['two']);
  });

  testWidgets('a parent-bound ref rebuilds its child subtree', (tester) async {
    final harness = await _mount(tester, _context());
    final before = _snapshot(harness.counts);

    harness.publisher.publish(_context(parentLabel: 'Changed'));
    await tester.pump();

    _expectMeasured(
      'parent-subtree',
      _deltas(
        before,
        harness.counts,
        const <String>['root', 'a', 'b', 'parent', 'child', 'host'],
      ),
      <String, int>{
        'root': 0,
        'a': 0,
        'b': 0,
        'parent': 1,
        'child': 1,
        'host': 0,
      },
    );
  });
}
