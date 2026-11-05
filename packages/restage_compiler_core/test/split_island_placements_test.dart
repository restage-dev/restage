import 'package:restage_compiler_core/src/surface_fit_projection.dart';
import 'package:restage_shared/rfw_formats.dart';
import 'package:test/test.dart';

const _label = 'CustomPaint in PlanCard';

// The placements of `Paint` when [design] is the paywall's root, beside a
// split `PlanCard` whose body places it [inBody].
RfwSplitIslandPlacements _placed(String design, {String inBody = 'Paint()'}) =>
    rfwSplitIslandPlacements(
      parseLibraryFile('''
        import core;
        widget PlanCard = PlanCard__split(label: args.label,
            restageWidget: Continuation(bodies: [Column(children: [
              Text(text: args.label), $inBody])]));
        widget Paywall = $design;
      '''),
      'Paywall',
      isSplitWrapper: (name) => name == 'PlanCard__split',
    )['Paint']!;

String? _refusal(String design, {String inBody = 'Paint()'}) =>
    splitIslandPlacementRefusal(_placed(design, inBody: inBody), label: _label);

void main() {
  group('a split widget island', () {
    test('may be placed inside its body any number of times', () {
      expect(
        _refusal(
            "Column(children: [PlanCard(label: 'a'), PlanCard(label: 'b')])",
            inBody: 'Paint(), Paint()'),
        isNull,
      );
      expect(_placed("PlanCard(label: 'a')").owners, {'PlanCard'});
    });

    test('placed outside its body is refused', () {
      expect(
        _refusal("Column(children: [PlanCard(label: 'a'), Paint()])"),
        'This design shows `$_label` outside `PlanCard`. Only `PlanCard`\'s '
        'app code can draw it. Try placing it only inside `PlanCard`.',
      );
    });

    test('passed into its body from outside is still outside', () {
      final placed = rfwSplitIslandPlacements(
        parseLibraryFile('''
          import core;
          widget PlanCard = PlanCard__split(
              restageWidget: Continuation(bodies: [Column(children: [
                args.child, Paint()])]));
          widget Paywall = PlanCard(child: Paint());
        '''),
        'Paywall',
        isSplitWrapper: (name) => name == 'PlanCard__split',
      )['Paint']!;
      expect(placed.owners, {'PlanCard'});
      expect(placed.outside, 1);
    });
  });
}
