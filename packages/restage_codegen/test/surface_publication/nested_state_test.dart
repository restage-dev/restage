// Stateful custom widgets placed in a mounted surface: delivered with their
// own rfw state, or kept in the app as an island, never a build error.
import 'dart:convert';
import 'dart:typed_data';

import 'package:build/build.dart';
import 'package:logging/logging.dart';
import 'package:restage_codegen/src/measurement/measurement_compiler_output.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    show
        NormalizedInteractionKind,
        SemanticValueClass,
        kLocalValueSetEventName,
        kMeasurementPublicationRouteArgumentKeyV1;
import 'package:restage_shared/rfw_formats.dart' as fmt;
import 'package:test/test.dart';

import '../helpers.dart';
import '../support/surface_build_chain.dart';

String _surface(
  String body, {
  required String classes,
  String members = '',
  String? build,
  String imports = '',
  String annotation = '@Paywall()',
  String fields = '',
}) =>
    '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';$imports
part 'restage.generated/mounted.restage.g.dart';

$classes
$annotation
final class Mounted extends StatelessWidget {
  const Mounted({super.key, this.plans = const ['a', 'b'], this.onQuery${fields.isEmpty ? '' : ', this.offers = const []'}});
  static const go = SurfaceEvent<void>('go');
  static const pick = SurfaceEvent<String>('pick');
  final List<String> plans;
  final ValueChanged<String>? onQuery;
  $fields
  @override
  Widget build(BuildContext context) ${build ?? '=> Column(children: [$body]);'}
$members
}
''';

String _tile({
  String fields = 'bool on = false;',
  String handlers = 'void flip() => setState(() => on = !on);',
  String build =
      "GestureDetector(onTap: flip, child: Text(on ? 'on' : widget.label))",
}) =>
    '''
class Tile extends StatefulWidget {
  const Tile({super.key, this.label = 'x', this.initial = false});
  final String label;
  final bool initial;
  @override
  State<Tile> createState() => _TileState();
}
class _TileState extends State<Tile> {
  $fields
  $handlers
  @override
  Widget build(BuildContext context) => $build;
}
''';

const _outer = '''
class Outer extends StatelessWidget {
  const Outer({super.key, required this.label});
  final String label;
  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.all(4), child: Tile(label: label));
}
''';

const _frame = '''
class Frame extends StatefulWidget {
  const Frame({super.key, required this.child});
  final Widget child;
  @override
  State<Frame> createState() => _FrameState();
}
class _FrameState extends State<Frame> {
  bool on = false;
  void flip() => setState(() => on = !on);
  @override
  Widget build(BuildContext context) =>
      GestureDetector(onTap: flip, child: on ? const Text('on') : widget.child);
}
''';

const _gate = '''
class Gate extends StatelessWidget {
  const Gate({super.key, required this.a, required this.b, required this.child});
  final bool a;
  final bool b;
  final Widget child;
  @override
  Widget build(BuildContext context) => Column(children: [if (a || b) child]);
}
''';

const _boxed = '''
class Boxed extends StatelessWidget {
  const Boxed({super.key, required this.badge, required this.child});
  final bool badge;
  final Widget child;
  @override
  Widget build(BuildContext context) => Column(children: [
    if (badge) const Text('B'),
    Padding(padding: const EdgeInsets.all(8), child: child),
  ]);
}
''';

const _stars = '''
class Stars extends StatelessWidget {
  const Stars({
    super.key,
    required this.showLabel,
    required this.label,
    required this.icon,
  });
  final bool showLabel;
  final String label;
  final Widget icon;
  @override
  Widget build(BuildContext context) => Row(children: [
    if (showLabel) Text(label),
    for (final _ in const [1, 2, 3]) icon,
  ]);
}
''';

const _twice = '''
class Twice extends StatelessWidget {
  const Twice({super.key, required this.badge, required this.child});
  final bool badge;
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      Column(children: [if (badge) const Text('B'), child, child]);
}
''';

const _pick = '''
class Pick extends StatelessWidget {
  const Pick({super.key, required this.on, required this.a, required this.b});
  final bool on;
  final Widget a;
  final Widget b;
  @override
  Widget build(BuildContext context) => on ? a : b;
}
''';

const _section = '''
class Section extends StatelessWidget {
  const Section({super.key, required this.badge, required this.child});
  final bool badge;
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      Column(children: [if (badge) const Text('B'), child]);
}
''';

const _badgedRow = '''
class BadgedRow extends StatelessWidget {
  const BadgedRow({super.key, required this.badge});
  final bool badge;
  @override
  Widget build(BuildContext context) =>
      Column(children: [if (badge) const Text('B'), const Pip(label: 'a')]);
}
''';

const _buttons = '''
class Go extends StatelessWidget {
  const Go({super.key, required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: context.surfaceEvent(Mounted.go),
    child: Text(label),
  );
}

class Pick extends StatelessWidget {
  const Pick({super.key, required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: context.surfaceEvent(Mounted.pick, label),
    child: Text(label),
  );
}

class PlanCard extends StatelessWidget {
  const PlanCard({super.key, required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Column(children: [
    TextButton(
      onPressed: context.surfaceEvent(Mounted.pick, label),
      child: Text(label),
    ),
    TextButton(
      onPressed: context.surfaceEvent(Mounted.go),
      child: const Text('Details'),
    ),
  ]);
}

class CtaButton extends StatelessWidget {
  const CtaButton({super.key, required this.label, this.onPressed});
  final String label;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) =>
      TextButton(onPressed: onPressed, child: Text(label));
}

class Twice extends StatefulWidget {
  const Twice({super.key});
  @override
  State<Twice> createState() => _TwiceState();
}

class _TwiceState extends State<Twice> {
  bool on = false;
  void flip() => setState(() => on = !on);
  Widget _row(String label) =>
      GestureDetector(onTap: flip, child: Text(label));
  @override
  Widget build(BuildContext context) =>
      Column(children: [_row('a'), _row('b')]);
}

class Mixed extends StatefulWidget {
  const Mixed({super.key, required this.onTap});
  final VoidCallback onTap;
  @override
  State<Mixed> createState() => _MixedState();
}

class _MixedState extends State<Mixed> {
  bool on = false;
  void flip() => setState(() => on = !on);
  @override
  Widget build(BuildContext context) => Column(children: [
    GestureDetector(onTap: flip, child: Text(on ? 'on' : 'off')),
    GestureDetector(onTap: widget.onTap, child: const Text('go')),
  ]);
}

class Offer {
  const Offer(this.name);
  final String name;
}

class Relay extends StatefulWidget {
  const Relay({super.key, required this.label});
  final String label;
  @override
  State<Relay> createState() => _RelayState();
}

class _RelayState extends State<Relay> {
  bool on = false;
  void flip() => setState(() => on = !on);
  @override
  Widget build(BuildContext context) => Inner(onTap: flip, label: widget.label);
}

class Inner extends StatelessWidget {
  const Inner({super.key, required this.onTap, required this.label});
  final VoidCallback onTap;
  final String label;
  @override
  Widget build(BuildContext context) =>
      GestureDetector(onTap: onTap, child: Text(label));
}

class Holder extends StatelessWidget {
  const Holder({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      Column(children: [child, const Pick(label: 'b')]);
}

class Pair extends StatelessWidget {
  const Pair({super.key, required this.top, required this.bottom});
  final Widget top;
  final Widget bottom;
  @override
  Widget build(BuildContext context) => Column(children: [top, bottom]);
}

class Row2 extends StatelessWidget {
  const Row2({super.key, required this.label});
  final String label;
  @override
  Widget build(BuildContext context) =>
      Padding(padding: EdgeInsets.zero, child: Go(label: label));
}
''';

const _goLibrary = {
  'apps_examples|lib/ui.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
export 'go_chip.dart';

@RestageLibrary(
  library: WidgetLibrary.custom('apps_examples.ui'),
  capabilityVersion: 1,
)
const restageUiLibrary = 0;
''',
  'apps_examples|lib/go_chip.dart': '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Fired when a chip is tapped.
const chipTapped = SurfaceEvent<void>('chipTapped');

/// A chip that fires one event.
@RestageWidget()
class GoChip extends StatelessWidget {
  /// Creates a chip.
  const GoChip({super.key, required this.label});

  /// The label.
  final String label;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: context.surfaceEvent(chipTapped),
    child: Text(label),
  );
}
''',
};

const _pipLibrary = {
  'apps_examples|lib/ui.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
export 'pip.dart';

@RestageLibrary(
  library: WidgetLibrary.custom('apps_examples.ui'),
  capabilityVersion: 1,
)
const restageUiLibrary = 0;
''',
  'apps_examples|lib/pip.dart': '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// A pip.
@RestageWidget()
class Pip extends StatefulWidget {
  /// Creates a pip.
  const Pip({super.key, required this.label});

  /// The label.
  final String label;

  @override
  State<Pip> createState() => _PipState();
}

class _PipState extends State<Pip> {
  bool on = false;
  void flip() => setState(() => on = !on);
  @override
  Widget build(BuildContext context) =>
      GestureDetector(onTap: flip, child: Text(on ? 'on' : widget.label));
}
''',
};

void main() {
  group('a nested stateful widget', () {
    test('placed once is one declaration with its own state', () async {
      final out = await _compile(
        _surface("Tile(label: 'a')", classes: _tile()),
      );
      expect(out.errors, isEmpty);
      expect(out.islands, isEmpty);
      expect(
        out.text,
        contains(
          'widget Tile { on: false } = GestureDetector(onTap: '
          '[set state.on = switch state.on { true: false, false: true }, ',
        ),
      );
      expect(
        out.text,
        contains(
          'Text(text: switch state.on { true: "on", false: args.label })',
        ),
      );
      expect(out.text, contains('Tile(label: "a", initial: false)'));
    });

    test(
      'with a field starting from a widget value stays in the app',
      () async {
        final out = await _compile(
          _surface(
            "Tile(label: 'a', initial: true)",
            classes: _tile(fields: 'late bool on = widget.initial;'),
          ),
        );
        expect(out.errors, isEmpty);
        final island = out.island('Tile');
        expect(island.reasonCode, 'nestedStateIsland');
        expect(
          island.reason,
          allOf(
            contains("'Tile' keeps its state in the app"),
            contains("the field 'on' (lib/mounted.dart:13:13)"),
            contains('starts from `widget.initial`'),
            contains('Try starting the field from a constant value'),
          ),
        );
        expect(out.text, isNot(contains('widget Tile')));
      },
    );

    test('with a widget-valued field inside a stateless widget keeps the '
        'outer widget in the app', () async {
      final out = await _compile(
        _surface(
          "Outer(label: 'a')",
          classes: _tile(fields: 'late bool on = widget.initial;') + _outer,
        ),
      );
      expect(out.errors, isEmpty);
      final island = out.island('Outer');
      expect(island.reasonCode, 'nestedStateIsland');
      expect(
        island.reason,
        contains("the field 'on' (lib/mounted.dart:13:13)"),
      );
    });

    test('with a handler setting two fields stays in the app', () async {
      final out = await _compile(
        _surface(
          "Tile(label: 'a')",
          classes: _tile(
            fields: 'bool on = false; bool b = false;',
            handlers: 'void flip() => setState(() { on = true; b = true; });',
            build:
                "GestureDetector(onTap: flip, child: Text(on && b ? 'on' : "
                'widget.label))',
          ),
        ),
      );
      expect(out.errors, isEmpty);
      final island = out.island('Tile');
      expect(island.reasonCode, 'nestedStateIsland');
      expect(
        island.reason,
        allOf(
          contains(
            "'Tile' keeps its state in the app: 'flip' "
            "(lib/mounted.dart:14:3) can't be delivered because the setState "
            'closure does not contain a single assignment expression.',
          ),
          contains(
            'Try giving each field its own handler with one setState(...) '
            'call',
          ),
        ),
      );
    });

    test('with a generator handler stays in the app and says why', () async {
      final out = await _compile(
        _surface(
          "Tile(label: 'a')",
          classes: _tile(
            handlers:
                'Iterable<void> flip() sync* { setState(() => on = !on); }',
          ),
        ),
      );
      expect(out.errors, isEmpty);
      final island = out.island('Tile');
      expect(island.reasonCode, 'nestedStateIsland');
      expect(
        island.reason,
        allOf(
          contains(
            "'Tile' keeps its state in the app: `flip` is a `sync*` generator "
            "method, which a design can't run",
          ),
          contains(
            'Try writing a plain method that does the work or returns '
            'the values.',
          ),
        ),
      );
    });

    test(
      'with a generator setState writer stays in the app and says why',
      () async {
        final out = await _compile(
          _surface(
            "Tile(label: 'a')",
            classes: _tile(
              handlers: 'void flip() => setState(() sync* { on = !on; });',
            ),
          ),
        );
        expect(out.errors, isEmpty);
        final island = out.island('Tile');
        expect(island.reasonCode, 'nestedStateIsland');
        expect(
          island.reason,
          allOf(
            contains(
              "'Tile' keeps its state in the app: the closure `flip` passes to "
              'setState is a `sync*` generator, so setState never runs it',
            ),
            contains(
              'Try removing `sync*` from the closure `flip` passes to '
              'setState.',
            ),
          ),
        );
      },
    );

    test('in a loop over host data stays in the app', () async {
      final out = await _compile(
        _surface('for (final p in plans) Tile(label: p)', classes: _tile()),
      );
      expect(out.errors, isEmpty);
      final island = out.island('Tile');
      expect(island.reasonCode, 'nestedStateIsland');
      expect(
        island.reason,
        allOf(
          contains(
            "'Tile' keeps its state in the app because it is placed "
            'in a loop',
          ),
          contains("Try placing 'Tile' outside the loop"),
        ),
      );
      expect(out.text, isNot(contains('widget Tile')));
    });

    test(
      'inside a stateless widget in a loop keeps that widget in the app',
      () async {
        final out = await _compile(
          _surface(
            "Outer(label: 'z'), for (final p in plans) Outer(label: p)",
            classes: _tile() + _outer,
          ),
        );
        expect(out.errors, isEmpty);
        final island = out.island('Outer');
        expect(island.reasonCode, 'nestedStateIsland');
        expect(
          island.reason,
          contains(
            "'Tile' keeps its state in the app because 'Outer', which places "
            'it, is placed in a loop',
          ),
        );
        // The placement outside the loop is still delivered.
        expect(out.text, contains('Column(children: [Outer(label: "z"), '));
        expect(out.text, contains('widget Tile { on: false }'));
      },
    );

    test(
      'inside a builder, which failed the build on main, stays in the app',
      () async {
        final out = await _compile(
          _surface(
            "LayoutBuilder(builder: (context, c) => const Tile())",
            classes: _tile(
              build:
                  "GestureDetector(onTap: flip, child: Text(on ? 'on' : 'off'))",
            ),
          ),
        );
        expect(out.errors, isEmpty);
        final island = out.island('LayoutBuilder');
        expect(island.reasonCode, 'nestedStateIsland');
        expect(island.reason, contains('whenever the builder runs'));
      },
    );

    test('inside a widget builder stays in the app', () async {
      final out = await _compile(
        _surface(
          "LayoutBuilder(builder: (context, c) => Tile(label: 'a'))",
          classes: _tile(),
        ),
      );
      expect(out.errors, isEmpty);
      final island = out.island('LayoutBuilder');
      expect(island.reasonCode, 'nestedStateIsland');
      expect(
        island.reason,
        contains(
          "'Tile' keeps its state in the app because it is placed in "
          'a builder',
        ),
      );
    });

    test('after a sibling whose count changes stays in the app', () async {
      final out = await _compile(
        _surface(
          "if (plans.isEmpty) const Text('B'), Tile(label: 'a')",
          classes: _tile(),
        ),
      );
      expect(out.errors, isEmpty);
      final island = out.island('Tile');
      expect(island.reasonCode, 'nestedStateIsland');
      expect(
        island.reason,
        allOf(
          contains(
            "'Tile' keeps its state in the app because it follows "
            "`if (plans.isEmpty) const Text('B')`",
          ),
          contains('a condition whose number of widgets can change'),
          contains(
            "Try placing 'Tile' before it, or giving the condition an "
            '`else`',
          ),
        ),
      );
    });

    test(
      'wrapped after a sibling whose count changes is the island itself',
      () async {
        final out = await _compile(
          _surface(
            "if (plans.isEmpty) const Text('B'), "
            "Padding(padding: EdgeInsets.zero, child: Tile(label: 'a'))",
            classes: _tile(),
          ),
        );
        expect(out.errors, isEmpty);
        expect(out.islands, ['Tile']);
        expect(out.text, contains('Padding('));
      },
    );

    test('before a sibling whose count changes stays delivered', () async {
      final out = await _compile(
        _surface(
          "Tile(label: 'a'), if (plans.isEmpty) const Text('B')",
          classes: _tile(),
        ),
      );
      expect(out.errors, isEmpty);
      expect(out.islands, isEmpty);
      expect(out.text, contains('widget Tile { on: false }'));
    });

    test('in a loop over a constant list stays delivered', () async {
      final out = await _compile(
        _surface(
          "for (final p in const ['a', 'b']) Tile(label: p)",
          classes: _tile(),
        ),
      );
      expect(out.errors, isEmpty);
      expect(out.islands, isEmpty);
      expect(
        out.text,
        contains(
          '[Tile(label: "a", initial: false), '
          'Tile(label: "b", initial: false)]',
        ),
      );
    });

    test('after a sibling of fixed count stays delivered', () async {
      final out = await _compile(
        _surface(
          "if (plans.isEmpty) const Text('B') else const Text('C'), "
          "Tile(label: 'a')",
          classes: _tile(),
        ),
      );
      expect(out.errors, isEmpty);
      expect(out.islands, isEmpty);
      expect(out.text, contains('widget Tile { on: false }'));
    });

    test('in both branches of a conditional renders from the app, one '
        'island per branch', () async {
      final out = await _compile(
        _surface(
          "plans.isEmpty ? Tile(label: 'a') : Tile(label: 'b')",
          classes: _tile(),
        ),
      );
      expect(out.errors, isEmpty);
      _expectBranchTwins(out, 'Tile', 'label: "a"', 'label: "b"');
      expect(
        out.island('Tile', first: true).reason,
        allOf(
          contains(
            "'Tile' renders from the app because it is placed at the same "
            'spot in more than one branch of a condition',
          ),
          contains(
            'its state starts again whenever the condition changes '
            'branch',
          ),
          contains("Try placing one 'Tile' outside the condition"),
        ),
      );
    });

    test('after a sibling, through a helper, stays in the app', () async {
      final out = await _compile(
        _surface(
          "if (plans.isEmpty) const Text('B'), _row()",
          classes: _tile(),
          members:
              '  Widget _row() => Padding(padding: EdgeInsets.zero, '
              "child: Tile(label: 'a'));",
        ),
      );
      expect(out.errors, isEmpty);
      expect(out.islands, ['Tile']);
      expect(out.island('Tile').reason, contains('a condition whose number'));
    });

    test('after a sibling, through a build local, stays in the app', () async {
      final out = await _compile(
        _surface(
          '',
          classes: _tile(),
          build: '''{
    final tile = Tile(label: 'a');
    return Column(children: [if (plans.isEmpty) const Text('B'), tile]);
  }''',
        ),
      );
      expect(out.errors, isEmpty);
      expect(out.islands, ['Tile']);
    });

    test('after a loop sibling stays in the app', () async {
      final out = await _compile(
        _surface(
          "for (final p in plans) Text(p), Tile(label: 'a')",
          classes: _tile(),
        ),
      );
      expect(out.errors, isEmpty);
      expect(
        out.island('Tile').reason,
        allOf(
          contains('a loop whose number of widgets can change'),
          contains("Try placing 'Tile' before it,"),
        ),
      );
      expect(out.island('Tile').reason, isNot(contains('`else`')));
    });

    test('after a spread whose count changes stays in the app', () async {
      final out = await _compile(
        _surface(
          "...[if (plans.isEmpty) const Text('B')], Tile(label: 'a')",
          classes: _tile(),
        ),
      );
      expect(out.errors, isEmpty);
      expect(out.islands, ['Tile']);
    });

    for (final (name, siblings) in [
      ('a loop over a constant list', 'for (final p in kPlans) Text(p)'),
      ('a constant spread', '...kHeader'),
      (
        'an else-if chain',
        "if (plans.isEmpty) const Text('A') "
            "else if (plans.length == 1) const Text('B') else const Text('C')",
      ),
      (
        'spread branches of one length',
        "if (plans.isEmpty) ...[const Text('A'), const Text('B')] "
            "else ...[const Text('C'), const Text('D')]",
      ),
    ]) {
      test('after $name stays delivered', () async {
        final out = await _compile(
          _surface(
            "$siblings, Tile(label: 'a')",
            classes:
                "${_tile()}const kPlans = ['a', 'b'];\n"
                "const kHeader = [Text('h1'), Text('h2')];\n",
          ),
        );
        expect(out.errors, isEmpty);
        expect(out.islands, isEmpty);
        expect(out.text, contains('widget Tile { on: false }'));
      });
    }

    test('with a widget argument in both branches renders one island per '
        'branch', () async {
      final out = await _compile(
        _surface(
          "plans.isEmpty ? Frame(child: const Text('a')) "
          ": Frame(child: const Text('b'))",
          classes: _frame,
        ),
      );
      expect(out.errors, isEmpty);
      _expectBranchTwins(
        out,
        'Frame',
        'child: Text(text: "a")',
        'child: Text(text: "b")',
      );
    });

    test(
      'in both branches of an if element renders one island per branch',
      () async {
        final out = await _compile(
          _surface(
            "if (plans.isEmpty) Tile(label: 'a') else Tile(label: 'b')",
            classes: _tile(),
          ),
        );
        expect(out.errors, isEmpty);
        _expectBranchTwins(out, 'Tile', 'label: "a"', 'label: "b"');
      },
    );

    test('in both branches of a helper call stays in the app', () async {
      final out = await _compile(
        _surface(
          'plans.isEmpty ? _a() : _b()',
          classes: _tile(),
          members:
              "  Widget _a() => Tile(label: 'a');\n"
              "  Widget _b() => Tile(label: 'b');",
        ),
      );
      expect(out.errors, isEmpty);
      _expectBranchTwins(out, 'Tile', 'label: "a"', 'label: "b"');
    });

    test('returned on two paths of the build stays in the app', () async {
      final out = await _compile(
        _surface(
          '',
          classes: _tile(),
          build: '''{
    if (plans.isEmpty) return Tile(label: 'a');
    return Tile(label: 'b');
  }''',
        ),
      );
      expect(out.errors, isEmpty);
      _expectBranchTwins(out, 'Tile', 'label: "a"', 'label: "b"');
    });

    test('in both branches of a switch expression stays in the app', () async {
      final out = await _compile(
        _surface(
          '',
          classes: _tile(),
          build: '''=> switch (plans.length) {
    0 => Tile(label: 'a'),
    _ => Tile(label: 'b'),
  };''',
        ),
      );
      expect(out.errors, isEmpty);
      _expectBranchTwins(out, 'Tile', 'label: "a"', 'label: "b"');
    });

    test(
      'passed to both branches a widget switches stays in the app',
      () async {
        final out = await _compile(
          _surface(
            "Pick(on: plans.isEmpty, a: Tile(label: 'a'), b: Tile(label: 'b'))",
            classes: _tile() + _pick,
          ),
        );
        expect(out.errors, isEmpty);
        _expectBranchTwins(out, 'Tile', 'label: "a"', 'label: "b"');
        expect(out.text, contains('widget Pick ='));
      },
    );

    test('passed after a sibling a widget places stays in the app', () async {
      final out = await _compile(
        _surface(
          "Section(badge: plans.isEmpty, child: Tile(label: 'a'))",
          classes: _tile() + _section,
        ),
      );
      expect(out.errors, isEmpty);
      expect(out.islands, ['Tile']);
      expect(out.text, contains('widget Section ='));
    });

    for (final (name, later) in [
      ('in a loop', 'for (final p in plans) Tile(label: p)'),
      (
        'after a sibling',
        "if (plans.isEmpty) const Text('B'), Tile(label: 'y')",
      ),
      (
        'in two branches',
        "plans.isEmpty ? Tile(label: 'c') : Tile(label: 'd')",
      ),
    ]) {
      test(
        'placed plainly first and then $name gets a verdict per placement',
        () async {
          final out = await _compile(
            _surface("Tile(label: 'z'), $later", classes: _tile()),
          );
          expect(out.errors, isEmpty);
          expect(out.islands, isNotEmpty);
          expect(out.islands, everyElement('Tile'));
          expect(out.text, contains('widget Tile { on: false }'));
          expect(out.text, contains('Column(children: [Tile(label: "z"'));
        },
      );
    }

    // A library widget renders from its registered widget, keyed by its
    // placement, so it keeps its state where it moves.
    test('from a widget library after a sibling renders from its keyed '
        'widget', () async {
      final out = await _compile(
        _surface(
          "if (plans.isEmpty) const Text('B'), Pip(label: 'a')",
          classes: '',
          imports: "\nimport 'package:apps_examples/ui.dart';",
        ),
        otherFiles: _pipLibrary,
      );
      expect(out.errors, isEmpty);
      expect(out.islands, isEmpty);
      expect(
        out.text,
        matches(RegExp(r'Pip\(label: "a", restageIsland: "[A-Za-z0-9_]+"\)')),
      );
    });

    test('from a widget library after a sibling inside a custom widget '
        'never fails the build', () async {
      final out = await _compile(
        _surface(
          'BadgedRow(badge: plans.isEmpty)',
          classes: _badgedRow,
          imports: "\nimport 'package:apps_examples/ui.dart';",
        ),
        otherFiles: _pipLibrary,
      );
      expect(out.errors, isEmpty);
      expect(out.islands, ['BadgedRow']);
      final island = out.island('BadgedRow');
      expect(island.reasonCode, 'nestedStateIsland');
      expect(island.reason, contains('`Pip`'));
      expect(
        island.reason,
        contains(
          "Try passing `Pip` to `BadgedRow` as a widget argument from the "
          "screen's build.",
        ),
      );
    });

    test('under an or-condition stays in the app', () async {
      final out = await _compile(
        _surface(
          "if (plans.isEmpty || plans.length > 5) Tile(label: 'a')",
          classes: _tile(),
        ),
      );
      expect(out.errors, isEmpty);
      expect(out.islands, ['Tile']);
      expect(
        out.island('Tile').reason,
        allOf(
          contains('is in a branch of `plans.isEmpty || plans.length > 5`'),
          contains('Try giving the condition a single part'),
        ),
      );
    });

    test('in the copied branch of an or-condition with an else stays in the '
        'app', () async {
      final out = await _compile(
        _surface(
          "if (plans.isEmpty || plans.length > 5) Tile(label: 'a') "
          "else const Text('b')",
          classes: _tile(),
        ),
      );
      expect(out.errors, isEmpty);
      expect(out.islands, ['Tile']);
    });

    test('under an and-condition stays delivered', () async {
      final out = await _compile(
        _surface(
          "if (plans.isEmpty && plans.length < 5) Tile(label: 'a')",
          classes: _tile(),
        ),
      );
      expect(out.errors, isEmpty);
      expect(out.islands, isEmpty);
      expect(out.text, contains('widget Tile { on: false }'));
    });

    test(
      'in the copied else branch of an and-condition stays in the app',
      () async {
        final out = await _compile(
          _surface(
            "plans.isEmpty && plans.length < 5 ? const Text('a') "
            ": Tile(label: 'b')",
            classes: _tile(),
          ),
        );
        expect(out.errors, isEmpty);
        expect(out.islands, ['Tile']);
        expect(
          out.island('Tile').reason,
          contains('is in a branch of `plans.isEmpty && plans.length < 5`'),
        );
      },
    );

    test('passed to a widget that shows it under an or-condition stays in '
        'the app', () async {
      final out = await _compile(
        _surface(
          'Gate(a: plans.isEmpty, b: plans.length > 5, '
          "child: Tile(label: 'a'))",
          classes: _tile() + _gate,
        ),
      );
      expect(out.errors, isEmpty);
      expect(out.islands, ['Tile']);
      expect(out.text, contains('widget Gate ='));
    });

    test('passed to a widget that places it twice after a sibling stays '
        'delivered', () async {
      final out = await _compile(
        _surface(
          "Twice(badge: plans.isEmpty, child: Tile(label: 'a'))",
          classes: _tile() + _twice,
        ),
      );
      expect(out.errors, isEmpty);
      // One island would sit under one key in both spots.
      expect(out.islands, isEmpty);
      expect(out.text, contains('widget Tile { on: false }'));
      expect(
        out.warnings,
        contains(contains("'Twice' places its `child` more than once")),
      );
      expect(out.warnings.join('\n'), contains('starts its state again'));
    });

    test('passed to a widget that places it once in a widget slot after a '
        'sibling stays in the app, with no warning', () async {
      final out = await _compile(
        _surface(
          "Boxed(badge: plans.isEmpty, child: Tile(label: 'a'))",
          classes: _tile() + _boxed,
        ),
      );
      expect(out.errors, isEmpty);
      expect(out.islands, ['Tile']);
      expect(out.warnings.join('\n'), isNot(contains('starts its state')));
    });

    test('in two arms through a widget that places it once is two islands, '
        'with no warning', () async {
      final out = await _compile(
        _surface(
          'plans.isEmpty '
          "? Gate(a: plans.isEmpty, b: plans.length > 5, child: Tile(label: 'a')) "
          ": Gate(a: plans.isEmpty, b: plans.length > 5, child: Tile(label: 'b'))",
          classes: _tile() + _gate,
        ),
      );
      expect(out.errors, isEmpty);
      expect(out.islands, ['Tile', 'Tile']);
      expect(out.warnings.join('\n'), isNot(contains('starts its state')));
    });

    test('passed to a widget that places it once in a constant loop after a '
        'sibling stays delivered', () async {
      final out = await _compile(
        _surface(
          "Stars(showLabel: plans.isEmpty, label: 'a', icon: Tile(label: 'a'))",
          classes: _tile() + _stars,
        ),
      );
      expect(out.errors, isEmpty);
      // One island would sit under one key in every copy.
      expect(out.islands, isEmpty);
      expect(out.text, contains('widget Tile { on: false }'));
      expect(
        out.warnings,
        contains(contains("'Stars' places its `icon` more than once")),
      );
    });

    test('in the branch an or-condition builds once stays delivered', () async {
      final out = await _compile(
        _surface(
          "plans.isEmpty || plans.length > 5 ? const Text('a') "
          ": Tile(label: 'b')",
          classes: _tile(),
        ),
      );
      expect(out.errors, isEmpty);
      expect(out.islands, isEmpty);
      expect(out.text, contains('widget Tile { on: false }'));
    });

    test('under a single condition stays delivered', () async {
      final out = await _compile(
        _surface("if (plans.isEmpty) Tile(label: 'a')", classes: _tile()),
      );
      expect(out.errors, isEmpty);
      expect(out.islands, isEmpty);
    });

    test('at a plain call site with a host value stays delivered', () async {
      final out = await _compile(
        _surface('Tile(label: plans.first)', classes: _tile()),
      );
      expect(out.errors, isEmpty);
      expect(out.islands, isEmpty);
      expect(out.text, contains('widget Tile { on: false }'));
      expect(
        out.text,
        matches(RegExp(r'Tile\(label: data\.context\._h[0-9a-f]+, initial: ')),
      );
    });

    test('placed with a GlobalKey stays in the app', () async {
      final out = await _compile(
        _surface(
          "Tile(key: _key, label: 'a')",
          classes: '${_tile()}final _key = GlobalKey<_TileState>();',
        ),
      );
      expect(out.errors, isEmpty);
      expect(out.islands, ['Tile']);
      expect(out.text, isNot(contains('widget Tile')));
    });

    // A guard: the classifier refuses the closure before translation today,
    // so this holds until nested value callbacks lower.
    test(
      'with a value callback stays in the app and writes no screen value '
      '(guard)',
      () async {
        final out = await _compile(
          _surface(
            "Tile(label: 'a')",
            classes: _tile(
              fields: "String text = '';",
              handlers: '',
              build: 'TextField(onChanged: (v) => setState(() => text = v))',
            ),
          ),
        );
        expect(out.errors, isEmpty);
        expect(out.islands, ['Tile']);
        expect(out.text, isNot(contains(kLocalValueSetEventName)));
        expect(out.part, isNot(contains(kLocalValueSetEventName)));
      },
    );
  });
  group('one widget placed twice', () {
    test('shares one point and stays measured', () async {
      final out = await _compile(
        _surface("Go(label: 'a'), Go(label: 'b')", classes: _buttons),
      );
      expect(out.errors, isEmpty);
      expect(
        out.text,
        contains('Column(children: [Go(label: "a"), Go(label: "b")])'),
      );
      expect(out.text, isNot(contains('Go_2')));
      expect(out.routes('Go'), hasLength(1));
      expect(out.planEvents().map((e) => e.$1), ['onPressed']);
      expect(out.sharedEvent('onPressed').node, contains('|definition:'));
    });

    test('placed once keeps its placement-keyed point', () async {
      final out = await _compile(
        _surface("Go(label: 'a')", classes: _buttons),
      );
      expect(out.errors, isEmpty);
      expect(out.text, contains('Column(children: [Go(label: "a")])'));
      expect(out.routes('Go'), hasLength(1));
      final node = out.sharedEvent('onPressed').node;
      expect(node, isNot(contains('definition:')));
      expect(node, contains('inline:'));
    });

    test('reordering the placements keeps the point key', () async {
      final first = await _compile(
        _surface(
          "Go(label: 'a'), Row(children: [Go(label: 'b')])",
          classes: _buttons,
        ),
      );
      final second = await _compile(
        _surface(
          "Row(children: [Go(label: 'b')]), Go(label: 'a')",
          classes: _buttons,
        ),
      );
      expect(first.errors, isEmpty);
      expect(second.errors, isEmpty);
      expect(
        second.sharedEvent('onPressed').node,
        first.sharedEvent('onPressed').node,
      );
    });

    test('reordering the placements over one ledger keeps the point and its '
        'lineage', () async {
      final first = await _compile(
        _surface(
          "Go(label: 'a'), Row(children: [Go(label: 'b')])",
          classes: _buttons,
        ),
      );
      expect(first.errors, isEmpty);
      final second = await _compile(
        _surface(
          "Row(children: [Go(label: 'b')]), Go(label: 'a')",
          classes: _buttons,
        ),
        otherFiles: first.ledger(),
      );
      expect(second.errors, isEmpty);
      expect(second.sharedEvent('onPressed'), first.sharedEvent('onPressed'));
    });

    test('a second placement moves the point to its definition and keeps its '
        'lineage', () async {
      final once = await _compile(
        _surface("Go(label: 'a')", classes: _buttons),
      );
      expect(once.errors, isEmpty);
      final twice = await _compile(
        _surface("Go(label: 'a'), Go(label: 'b')", classes: _buttons),
        otherFiles: once.ledger(),
      );
      expect(twice.errors, isEmpty);
      final before = once.sharedEvent('onPressed');
      final after = twice.sharedEvent('onPressed');
      expect(after.node, isNot(before.node));
      expect(after.node, contains('|definition:'));
      expect(after.reference, before.reference);
      expect(after.lineage, before.lineage);
    });

    test('a stateful widget placed twice shares one point', () async {
      final out = await _compile(
        _surface("Tile(label: 'a'), Tile(label: 'b')", classes: _tile()),
      );
      expect(out.errors, isEmpty);
      expect(out.islands, isEmpty);
      expect(
        out.text,
        contains(
          'Column(children: [Tile(label: "a", initial: false), '
          'Tile(label: "b", initial: false)])',
        ),
      );
      expect(out.routes('Tile'), hasLength(1));
      expect(out.planEvents().map((e) => e.$1), ['onTap']);
    });

    test('a placement in a host-data loop met before one outside it shares '
        'one point with no item', () async {
      final out = await _compile(
        _surface(
          "for (final p in plans) Go(label: p), Go(label: 'x')",
          classes: _buttons,
        ),
      );
      expect(out.errors, isEmpty);
      expect(out.routes('Go'), hasLength(1));
      for (final handler in out.events()['Go']!) {
        expect(handler.eventArguments.keys, [
          kMeasurementPublicationRouteArgumentKeyV1,
        ]);
      }
    });

    test('a placement in a host-data loop over objects met before one '
        'outside it shares one point with no item', () async {
      final out = await _compile(
        _surface(
          "for (final o in offers) Go(label: o.name), Go(label: 'x')",
          classes: _buttons,
          fields: 'final List<Offer> offers;',
        ),
      );
      expect(out.errors, isEmpty);
      expect(out.routes('Go'), hasLength(1));
      for (final handler in out.events()['Go']!) {
        expect(handler.eventArguments.keys, [
          kMeasurementPublicationRouteArgumentKeyV1,
        ]);
      }
    });

    test('a reusable button given one event at two placements keeps a point '
        'per placement', () async {
      final out = await _compile(
        _surface(
          "CtaButton(label: 'a', onPressed: context.surfaceEvent(Mounted.go)), "
          "CtaButton(label: 'b', onPressed: context.surfaceEvent(Mounted.go))",
          classes: _buttons,
        ),
      );
      expect(out.errors, isEmpty);
      expect(out.routes('CtaButton'), isEmpty);
      expect(out.routes('Paywall'), hasLength(2));
      expect(out.routes('Paywall').toSet(), hasLength(2));
    });

    test('a null callback at one placement leaves the other measured', () async {
      final out = await _compile(
        _surface(
          "CtaButton(label: 'a', onPressed: null), "
          "CtaButton(label: 'b', onPressed: context.surfaceEvent(Mounted.go))",
          classes: _buttons,
        ),
      );
      expect(out.errors, isEmpty);
      expect(out.routes('Paywall'), hasLength(1));
    });

    test('a callback reached twice in a widget placed once stays in the app, '
        'with or without a widget placed twice beside it', () async {
      final alone = await _compile(
        _surface('const Twice()', classes: _buttons),
      );
      expect(alone.errors, isEmpty);
      expect(alone.islands, ['Twice']);
      expect(alone.planEvents(), isEmpty);

      final beside = await _compile(
        _surface(
          "const Twice(), Go(label: 'a'), Go(label: 'b')",
          classes: _buttons,
        ),
      );
      expect(beside.errors, isEmpty);
      expect(beside.islands, ['Twice']);
      expect(beside.planEvents().map((e) => e.$1), ['onPressed']);
      expect(beside.routes('Go'), hasLength(1));
    });

    test(
      'a widget placed twice that handles a tap itself and takes a '
      'callback from each placement stays unmeasured with a reason',
      () async {
        final out = await _compile(
          _surface(
            'Mixed(onTap: context.surfaceEvent(Mounted.go)), '
            "Mixed(onTap: context.surfaceEvent(Mounted.pick, 'b'))",
            classes: _buttons,
          ),
        );
        expect(out.errors, isEmpty);
        expect(out.planEvents(), isEmpty);
        expect(out.unmeasuredReason(), contains('`Mixed`'));
        expect(out.unmeasuredReason(), contains('takes a callback'));
      },
    );

    test('a choice and a button in one widget share one point each', () async {
      final out = await _compile(
        _surface(
          "PlanCard(label: 'a'), PlanCard(label: 'b')",
          classes: _buttons,
        ),
      );
      expect(out.errors, isEmpty);
      expect(out.text, isNot(contains('PlanCard_2')));
      expect(out.routes('PlanCard'), hasLength(2));
      expect(out.routes('PlanCard').toSet(), hasLength(2));
    });

    test('nested in a widget placed twice, shares one point', () async {
      final out = await _compile(
        _surface("Row2(label: 'a'), Row2(label: 'b')", classes: _buttons),
      );
      expect(out.errors, isEmpty);
      expect(out.text, isNot(contains('_2(')));
      expect(out.routes('Go'), hasLength(1));
      expect(out.planEvents(), hasLength(1));
    });

    test(
      'a tap passed down inside a widget placed twice shares one point',
      () async {
        final out = await _compile(
          _surface(
            "Relay(label: 'a'), Relay(label: 'b')",
            classes: _tile() + _buttons,
          ),
        );
        expect(out.errors, isEmpty);
        expect(out.events().values.expand((h) => h), hasLength(1));
        expect(out.planEvents(), hasLength(1));
      },
    );

    test('in a constant-list loop, shares one point', () async {
      final out = await _compile(
        _surface(
          "for (final p in const ['a', 'b']) Go(label: p)",
          classes: _buttons,
        ),
      );
      expect(out.errors, isEmpty);
      expect(out.text, contains('[Go(label: "a"), Go(label: "b")]'));
      expect(out.routes('Go'), hasLength(1));
      expect(out.planEvents(), hasLength(1));
    });

    test('in a sheet and under it, shares one point', () async {
      final out = await _compile(
        _surface(
          '',
          classes: _buttons,
          build: """=> Column(children: [
    TextButton(
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        builder: (_) => const Pick(label: 'a'),
      ),
      child: const Text('open'),
    ),
    const Pick(label: 'b'),
  ]);""",
        ),
      );
      expect(out.errors, isEmpty);
      expect(
        out.planEvents().where((e) => e.$1 == 'onPressed'),
        hasLength(2),
      );
    });

    test('from a widget library, stays one component with one point', () async {
      final out = await _compile(
        _surface(
          "GoChip(label: 'a'), GoChip(label: 'b')",
          classes: '',
          imports: "\nimport 'package:apps_examples/ui.dart';",
        ),
        otherFiles: _goLibrary,
      );
      expect(out.errors, isEmpty);
      expect(out.text, contains('[GoChip(label: "a"), GoChip(label: "b")]'));
      expect(out.routes('GoChip'), hasLength(1));
      final components = out.bundle!.surfaceComponents['paywall/mounted']!;
      expect([for (final c in components) c.name], ['apps_examples.ui.GoChip']);
    });

    test(
      'passed as a const argument and also placed, shares one point',
      () async {
        final out = await _compile(
          _surface("Holder(child: const Pick(label: 'a'))", classes: _buttons),
        );
        expect(out.errors, isEmpty);
        expect(out.routes('Pick'), hasLength(1));
        expect(out.planEvents(), hasLength(1));
      },
    );

    test('as const arguments in another order than declared, shares one '
        'point', () async {
      final out = await _compile(
        _surface(
          "Pair(bottom: const Pick(label: 'b'), top: const Pick(label: 'a'))",
          classes: _buttons,
        ),
      );
      expect(out.errors, isEmpty);
      expect(out.routes('Pick'), hasLength(1));
      expect(out.planEvents(), hasLength(1));
    });
  });
}

// Asserts the two branches of a condition each place [widget] as their own
// island, with distinct names, so each gets its own key.
void _expectBranchTwins(_Compiled out, String widget, String a, String b) {
  expect(out.islands, [widget, widget]);
  final first = RegExp(
    '(mounted[A-Za-z0-9_]*_${widget}_\\d+)\\(${RegExp.escape(a)}\\)',
  ).firstMatch(out.text)?[1];
  final second = RegExp(
    '(mounted[A-Za-z0-9_]*_${widget}_\\d+)\\(${RegExp.escape(b)}\\)',
  ).firstMatch(out.text)?[1];
  expect(first, isNotNull);
  expect(second, isNotNull);
  expect(first, isNot(second));
}

typedef _Island = ({String reason, String reasonCode});

typedef _Compiled = ({
  String text,
  String part,
  List<String> errors,
  List<String> islands,
  RestageSurfacePublicationBundle? bundle,
  List<String> warnings,
  List<int>? measurement,
  String? contractFingerprint,
});

extension on _Compiled {
  fmt.RemoteWidgetLibrary library() => fmt.decodeLibraryBlob(
    Uint8List.fromList(bundle!.artifacts['assets/paywalls/mounted.rfw']!),
  );

  // The event handlers each declaration fires, by declaration.
  Map<String, List<fmt.EventHandler>> events() {
    final result = <String, List<fmt.EventHandler>>{};
    for (final widget in library().widgets) {
      void walk(Object? node) {
        switch (node) {
          case final fmt.EventHandler handler:
            (result[widget.name] ??= []).add(handler);
          case final fmt.ConstructorCall call:
            walk(call.arguments);
          case final fmt.Loop loop:
            walk(loop.output);
          case final fmt.Switch node:
            node.outputs.values.forEach(walk);
          case final Map<Object?, Object?> map:
            map.values.forEach(walk);
          case final List<Object?> list:
            list.forEach(walk);
        }
      }

      walk(widget.root);
    }
    return result;
  }

  // The measurement routes [declaration]'s handlers carry.
  List<Object?> routes(String declaration) => [
    for (final handler in events()[declaration] ?? const <fmt.EventHandler>[])
      if (handler.eventArguments[kMeasurementPublicationRouteArgumentKeyV1]
          case final route?)
        route,
  ];

  // Each measured tap of the surface, leaving out the lifecycle events every
  // publication carries: its slot, kind and value class.
  List<(String, NormalizedInteractionKind, SemanticValueClass)> planEvents() =>
      [
        for (final publication
            in RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
              measurement!,
            ).publications)
          for (final event in publication.routePlan.events)
            if (!event.sourceEventIdentity.value.startsWith(
              'restageLifecycle_',
            ))
              (
                event.sourceEventIdentity.value,
                event.normalizedInteractionKind,
                event.semanticValueClass,
              ),
      ];

  // The one active ledger event on [slot]: its node's locator, its point and
  // its lineage.
  ({String node, String reference, String lineage}) sharedEvent(String slot) {
    final output = RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
      measurement!,
    );
    final (node, event) = [
      for (final node in output.ledgerNodes)
        for (final event in node.events)
          if (node.active &&
              event.active &&
              event.sourceEventIdentity.value == slot)
            (node, event),
    ].single;
    return (
      node: node.structuralOccurrenceKey,
      reference: event.generatedReferenceId.value,
      lineage: event.lineageId.value,
    );
  }

  // This build's Measurement ledger, as the next build's prior state.
  Map<String, String> ledger() => {
    'apps_examples|$kRestageMeasurementCompilerLedgerSourcePath': utf8.decode(
      measurement!,
    ),
  };

  // Why the surface compiled unmeasured.
  String unmeasuredReason() =>
      RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
        measurement!,
      ).unmeasured.single.reason;

  _Island island(String widget, {bool first = false}) {
    bool matches(SplitSite site) =>
        site.kind.name == 'island' && site.widget == widget;
    final sites = bundle!.splitSites;
    final site = first ? sites.firstWhere(matches) : sites.singleWhere(matches);
    final json = site.toJson();
    return (
      reason: json['reason']! as String,
      reasonCode: json['reasonCode']! as String,
    );
  }
}

Future<_Compiled> _compile(
  String source, {
  Map<String, String> otherFiles = const {},
}) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  final warnings = <String>[];
  final result = await testBuilders(
    [
      ...surfaceBuildChain(config: const {'bundled_runtime': true}),
    ],
    {'apps_examples|lib/mounted.dart': source, ...otherFiles},
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    flattenOutput: true,
    onLog: (record) {
      if (record.level >= Level.SEVERE) printOnFailure(record.message);
      if (record.level == Level.WARNING) warnings.add(record.message);
    },
  );
  if (!result.succeeded) {
    return (
      text: '',
      part: '',
      errors: [for (final e in result.errors) '$e'],
      islands: const <String>[],
      bundle: null,
      warnings: warnings,
      measurement: null,
      contractFingerprint: null,
    );
  }
  final json =
      jsonDecode(
            readerWriter.testing.readString(
              AssetId(
                'apps_examples',
                kRestageSurfacePublicationCompilerBundlePath,
              ),
            ),
          )
          as Map<String, Object?>;
  final bundle = RestageSurfacePublicationBundle.fromJson(json);
  final publication =
      ((((json['manifest']! as Map)['publications']! as List).single
                  as Map)['publication']!
              as Map)['contractFingerprint']
          as String?;
  return (
    text: utf8.decode(
      bundle.ownedOutputs.entries
          .firstWhere((entry) => entry.key.endsWith('/mounted.rfwtxt'))
          .value,
    ),
    part: readerWriter.testing.readString(
      AssetId('apps_examples', 'lib/restage.generated/mounted.restage.g.dart'),
    ),
    errors: <String>[],
    islands: [
      for (final site in bundle.splitSites)
        if (site.kind.name == 'island') site.widget,
    ],
    bundle: bundle,
    warnings: warnings,
    measurement: readerWriter.testing.readBytes(
      AssetId('apps_examples', kRestageMeasurementCompilerOutputPath),
    ),
    contractFingerprint: publication,
  );
}
