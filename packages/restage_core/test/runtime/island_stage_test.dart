import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';

final builds = <String>[];
final inits = <String>[];

// Reads the stage and, once shown, creates a State.
class _Reader extends StatelessWidget {
  const _Reader(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    final candidate = RestageIslandStage.isCandidate(context);
    builds.add('$name:${candidate ? 'staged' : 'shown'}');
    return candidate ? const SizedBox.shrink() : _Counted(name);
  }
}

class _Counted extends StatefulWidget {
  const _Counted(this.name);

  final String name;

  @override
  State<_Counted> createState() => _CountedState();
}

class _CountedState extends State<_Counted> {
  @override
  void initState() {
    super.initState();
    inits.add(widget.name);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

// `a` sits deeper than `b`, so depth order would build `b` first.
const _kept = Column(
  children: [
    Padding(padding: EdgeInsets.zero, child: _Reader('a')),
    _Reader('b'),
  ],
);

// Shows its stage with a root it keeps, a fresh one each build, or a fresh
// root around a kept subtree.
class _Host extends StatefulWidget {
  const _Host(this.root);

  final Widget Function() root;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  var candidate = true;
  var generation = 0;

  /// Shows the staged version.
  void promote() => setState(() => candidate = false);

  /// Changes what reads the stage must rebuild for.
  void bump() => setState(() => generation++);

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: RestageIslandStage(
          candidate: candidate,
          generation: generation,
          child: widget.root(),
        ),
      );
}

void main() {
  for (final (name, root, inTreeOrder) in [
    ('a host that keeps its root', () => _kept, true),
    (
      'a host that builds a fresh root',
      () => Column(
            children: [
              Padding(padding: EdgeInsets.zero, child: _Reader('a')),
              _Reader('b'),
            ],
          ),
      true,
    ),
    // What the update reaches builds there, the rest after it, as Flutter
    // orders an inherited change under a parent that rebuilds.
    (
      'a fresh root around a kept subtree',
      () => Column(
            children: [
              const Padding(padding: EdgeInsets.zero, child: _Reader('a')),
              _Reader('b'),
            ],
          ),
      false,
    ),
  ]) {
    testWidgets('$name: each reader builds once per change', (tester) async {
      Matcher inOrder(List<String> expected) =>
          inTreeOrder ? equals(expected) : unorderedEquals(expected);
      builds.clear();
      inits.clear();
      await tester.pumpWidget(_Host(root));
      expect(builds, ['a:staged', 'b:staged']);
      final host = tester.state<_HostState>(find.byType(_Host));

      builds.clear();
      host.promote();
      await tester.pump();
      expect(builds, inOrder(['a:shown', 'b:shown']));
      expect(inits, inOrder(['a', 'b']));

      builds.clear();
      host.bump();
      await tester.pump();
      expect(builds, inOrder(['a:shown', 'b:shown']));
      expect(inits, inOrder(['a', 'b']));
    });
  }
}
