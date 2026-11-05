import 'package:restage_compiler_core/src/surface_fit_projection.dart';
import 'package:restage_shared/rfw_formats.dart';
import 'package:test/test.dart';

const _tooOften =
    'This design places `Fade in Plans` more times than its app code '
    'supports. Try removing the extra copies.';
const _outsideItsList =
    '`Fade in Plans` shows one item of a list. Try placing it inside that list.';

RfwPlacements? _placed(String design) => rfwPlacements(
      parseLibraryFile('''
        import core;
        widget Local = Fade();
        widget Ignores = Column(children: []);
        widget Twice = Column(children: [args.child, args.child]);
        widget Each = Column(children: [...for i in data.items: args.child]);
        widget Paywall = $design;
      '''),
      'Paywall',
    )['Fade'];

String? _refusal(String design, int itemInputs) => islandPlacementRefusal(
      _placed(design)!,
      label: 'Fade in Plans',
      itemInputs: itemInputs,
    );

void main() {
  // Each row: a design, where it places `Fade`, and the refusal for a `Fade`
  // the compiler placed outside any loop and for one it placed in one loop.
  for (final (name, design, outside, looped, unlooped, inOneLoop) in [
    ('once', 'Column(children: [Fade()])', 1, 0, null, _outsideItsList),
    (
      'twice',
      'Column(children: [Fade(), Fade()])',
      2,
      0,
      _tooOften,
      _tooOften,
    ),
    (
      'in a loop',
      'Column(children: [...for i in data.items: Fade()])',
      0,
      1,
      _tooOften,
      null,
    ),
    (
      'under a condition',
      'Column(children: [...for i in switch data.on {true: [0], false: []}: '
          'Fade()])',
      1,
      0,
      null,
      _outsideItsList,
    ),
    (
      'in a one-element list that spreads a loop',
      'Column(children: [...for a in [...for b in data.items: b]: Fade()])',
      0,
      1,
      _tooOften,
      null,
    ),
    (
      'under a switch branch that spreads a loop',
      'Column(children: [...for a in switch data.on '
          '{true: [...for b in data.items: b], false: []}: Fade()])',
      0,
      1,
      _tooOften,
      null,
    ),
    (
      'in either branch of a switch',
      'switch data.on { true: Fade(), false: Column(children: [Fade()]) }',
      1,
      0,
      null,
      _outsideItsList,
    ),
    (
      'through a local widget used twice',
      'Column(children: [Local(), Local()])',
      2,
      0,
      _tooOften,
      _tooOften,
    ),
    (
      'as a child a local widget places twice',
      'Twice(child: Fade())',
      2,
      0,
      _tooOften,
      _tooOften
    ),
    (
      'as a child a local widget places in a loop',
      'Each(child: Fade())',
      0,
      1,
      _tooOften,
      null
    ),
    (
      'as a child a local widget never places',
      'Ignores(child: Fade())',
      0,
      0,
      null,
      null
    ),
    (
      'in a builder, twice',
      'Builder(builder: (scope) => Column(children: [Fade(), Fade()]))',
      0,
      2,
      _tooOften,
      _tooOften,
    ),
    (
      'as a loop variable read twice',
      'Column(children: [...for w in [Fade()]: Column(children: [w, w])])',
      2,
      0,
      _tooOften,
      _tooOften,
    ),
    (
      'as one element of a literal list a loop wraps',
      'Column(children: [...for w in [Fade(), Text(text: "a")]: '
          'Padding(child: w)])',
      1,
      0,
      null,
      _outsideItsList,
    ),
  ]) {
    test('a design placing it $name', () {
      final placed = _placed(design)!;
      expect((placed.outside, placed.looped), (outside, looped));
      expect(_refusal(design, 0), unlooped);
      expect(_refusal(design, 1), inOneLoop);
    });
  }

  // A `Fade` the compiler placed in one or two loops, placed by a design
  // more than once per iteration, or at another depth.
  for (final (name, design, itemInputs, refusal) in [
    (
      'twice in one loop body',
      'Column(children: [...for i in data.items: '
          'Column(children: [Fade(), Fade()])])',
      1,
      _tooOften,
    ),
    (
      'once in each of two loops',
      'Column(children: [...for i in data.items: Fade(), '
          '...for j in data.items: Fade()])',
      1,
      _tooOften,
    ),
    (
      'through a local widget used twice inside one loop',
      'Column(children: [...for i in data.items: '
          'Column(children: [Local(), Local()])])',
      1,
      _tooOften,
    ),
    (
      'once per loop of two nested loops',
      'Column(children: [...for i in data.rows: Column(children: [Fade(), '
          '...for j in i.items: Fade()])])',
      1,
      _tooOften,
    ),
    (
      'inside two nested loops',
      'Column(children: [...for i in data.rows: '
          'Column(children: [...for j in i.items: Fade()])])',
      1,
      _tooOften,
    ),
    (
      'inside one loop',
      'Column(children: [...for i in data.items: Fade()])',
      2,
      _outsideItsList,
    ),
    (
      'once at its depth of two',
      'Column(children: [...for i in data.rows: '
          'Column(children: [...for j in i.items: Fade()])])',
      2,
      null,
    ),
  ]) {
    test('a $itemInputs-loop widget placed $name', () {
      expect(_refusal(design, itemInputs), refusal);
    });
  }
}
