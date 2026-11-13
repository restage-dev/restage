// Every place an app-rendered widget can be written, in every enclosing form:
// the build either refuses with a diagnostic or emits code that compiles.

import 'package:test/test.dart';

import '../support/generated_compiles.dart';

// App widgets: building one runs app code, so each is an island.
const _kit = '''
class Probe extends StatelessWidget {
  Probe({super.key, required this.label, this.onTap});
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: null, child: Text(label));
}

class Wide extends StatelessWidget {
  const Wide({super.key, required this.child, this.children = const []});
  final Widget child;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: null, child: Column(children: [child, ...children]));
}

class Narrow extends StatelessWidget {
  const Narrow({super.key, required this.probe, this.probes = const []});
  final Probe probe;
  final List<Probe> probes;
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: null, child: Column(children: [probe, ...probes]));
}

class Panel extends StatefulWidget {
  const Panel({super.key, required this.repaintOn, required this.child});
  final Listenable repaintOn;
  final Widget child;
  @override
  State<Panel> createState() => _PanelState();
}

class _PanelState extends State<Panel> {
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: null, child: widget.child);
}

class Header extends SliverPersistentHeaderDelegate {
  Header(this.title);
  final String title;
  @override
  double get minExtent => 40;
  @override
  double get maxExtent => 40;
  @override
  Widget build(BuildContext context, double shrink, bool overlaps) =>
      SizedBox(height: 40, child: Text(title));
  @override
  bool shouldRebuild(Header old) => old.title != title;
}

const List<String> fixedNames = ['a', 'b', 'c'];

class Opt {
  const Opt(this.title, {this.isNew = false});
  final String title;
  final bool isNew;
}

const List<Opt> fixedOptions = [Opt('a', isNew: true), Opt('b')];

// Composes an app widget it takes as one: a pure composition.
class ProbeFrame extends StatelessWidget {
  const ProbeFrame({super.key, required this.probe});
  final Probe probe;
  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.all(4), child: probe);
}

class ProbeColumn extends StatelessWidget {
  const ProbeColumn({super.key, required this.probes});
  final List<Probe> probes;
  @override
  Widget build(BuildContext context) => Column(children: probes);
}

class Tile extends StatelessWidget {
  Tile({super.key, required this.label, this.child});
  final String label;
  final Widget? child;
  @override
  Widget build(BuildContext context) => CustomPaint(
      painter: null,
      child: Column(children: [Text(label), if (child != null) child!]));
}

class ProbeBar extends StatelessWidget implements PreferredSizeWidget {
  ProbeBar({super.key, required this.title});
  final String title;
  @override
  Size get preferredSize => const Size.fromHeight(40);
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: null, child: Text(title));
}

Probe makeProbe(String label) => Probe(label: label);
''';

// Where the widget is written. `$w` is the app widget expression.
const _sites = <String, String>{
  'a child': r'Column(children: [$w])',
  'a Widget parameter of an app widget': r'Wide(child: $w)',
  'a narrow parameter of an app widget': r'Narrow(probe: $w)',
  'a narrow list of an app widget': r'Narrow(probe: $w, probes: [$w])',
  'a Widget list of an app widget':
      r'Wide(child: const Text("x"), children: [$w, $w])',
  'a sliver adapter in an app panel':
      r'Panel(repaintOn: _scroll, child: '
      r'CustomScrollView(controller: _scroll, slivers: [SliverPadding('
      r'padding: const EdgeInsets.all(8), sliver: SliverToBoxAdapter('
      r'child: Column(children: [$w])))]))',
  'a pinned header beside it':
      r'CustomScrollView(slivers: [SliverPersistentHeader('
      r'pinned: true, delegate: Header(_label)), SliverToBoxAdapter(child: $w)])',
  'a sliver list builder':
      r'CustomScrollView(slivers: [SliverList.builder('
      r'itemCount: _count, itemBuilder: (context, i) => $w)])',
  'a loop over a const list':
      r'Column(children: [for (final n in fixedNames) $w])',
  'a loop over a field': r'Column(children: [for (final n in _names) $w])',
  'a condition': r'Column(children: [if (_count > 1) $w])',
  'a condition in a loop over a const list':
      r'Column(children: [for (final n in fixedNames) if (n != _label) $w])',
  'a condition on a const field in a spread loop over a const list':
      r'Column(children: [for (final o in fixedOptions) ...[if (o.isNew) $w, '
      r'Text(o.title)]])',
  'a condition on the item in a loop over a const list':
      r'Column(children: [for (final n in fixedNames) if (n == "a") $w])',
  'a conditional expression':
      r'Column(children: [_count > 1 ? $w : const Text("no")])',
  'a builder': r'LayoutBuilder(builder: (context, constraints) => $w)',
  'an unrolled loop in an app widget':
      r'Wide(child: Column(children: [for (final n in fixedNames) $w]))',
  'a narrow parameter of a composed widget': r'ProbeFrame(probe: $w)',
  'a narrow list of a composed widget': r'ProbeColumn(probes: [$w])',
  'a condition in a narrow list': r'ProbeColumn(probes: [if (_count > 1) $w])',
  'a loop over a const list in a narrow list':
      r'ProbeColumn(probes: [for (final n in fixedNames) $w])',
  'a loop over a field in a narrow list':
      r'ProbeColumn(probes: [for (final n in _names) $w])',
  'a narrow list literal': r'Column(children: <Probe>[$w])',
  'an app bar from a helper': r'Scaffold(appBar: _bar(), body: $w)',
  // These place their own app widgets.
  'a helper returning an app widget': r'Column(children: [_probe()])',
  'a helper with a parameter called twice':
      r"Column(children: [_probeOf('a'), _probeOf('b')])",
  'a top-level helper': r"Column(children: [makeProbe('t')])",
  'a helper with an unrolled loop called twice':
      r'Column(children: [_row(), _row()])',
  'a ternary on the item inside an app widget in an unrolled loop':
      r'Column(children: [for (final o in fixedOptions) '
      r'Tile(label: o.title, child: o.isNew ? Text(_label) : null)])',
  'a ternary on the item around an app widget in an unrolled loop':
      r'Column(children: [for (final o in fixedOptions) '
      r"Wide(child: o.isNew ? Text(o.title) : Probe(label: o.title))])",
};

// The widget written there.
const _widgets = <String, String>{
  'an app widget': r"Probe(label: 'p')",
  'an app widget reading state': r"Probe(label: 'n $_count', onTap: _tap)",
  'an app widget inside an app widget': r"Wide(child: Probe(label: 'p'))",
};

// The surface around it.
String _surface(String id, String build) =>
    '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/$id.restage.g.dart';

$_kit

@Screen(id: '$id', surface: Surface.onboarding)
class Shape extends StatefulWidget {
  const Shape({super.key});
  @override
  State<Shape> createState() => _ShapeState();
}

class _ShapeState extends State<Shape> {
  final ScrollController _scroll = ScrollController();
  final GlobalKey _key = GlobalKey();
  final List<String> _names = ['x', 'y'];
  int _count = 2;
  String get _label => 'label \$_count';

  void _tap() => setState(() => _count++);

  Probe _probe() => Probe(label: 'h \$_count');

  Probe _probeOf(String label) => Probe(label: label);

  Widget _row() => Row(children: [for (final n in fixedNames) Probe(label: n)]);

  PreferredSizeWidget _bar() => ProbeBar(title: 'bar \$_count');

  @override
  Widget build(BuildContext context) => KeyedSubtree(key: _key, child: $build);
}
''';

void main() {
  final cases = <({String name, String id, String source})>[
    for (final (s, site) in _sites.entries.indexed)
      for (final (w, widget) in _widgets.entries.indexed)
        // Only a Probe fits a parameter that takes a Probe; a site with
        // no place for one is built once.
        if ((!site.key.contains('narrow') ||
                widget.value.startsWith('Probe')) &&
            (site.value.contains(r'$w') || w == 0))
          (
            name: '${widget.key} in ${site.key}',
            id: 'shape_${s}_$w',
            source: _surface(
              'shape_${s}_$w',
              site.value.replaceAll(r'$w', widget.value),
            ),
          ),
  ];
  test(
    'every app widget site compiles',
    () async {
      final outcomes = await expectGeneratedCompiles({
        for (final c in cases) c.name: {'lib/${c.id}.dart': c.source},
      });
      printOutcomes(outcomes);
      // Any widget code that compiles builds: nothing here is refused.
      expect(
        [
          for (final MapEntry(:key, :value) in outcomes.entries)
            if (!value.compiled) '$key: ${value.refusal}',
        ],
        isEmpty,
      );
    },
    timeout: const Timeout(Duration(minutes: 30)),
  );
}
