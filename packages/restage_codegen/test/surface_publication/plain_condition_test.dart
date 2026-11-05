import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:restage_codegen/src/surface_publication/plain_condition.dart';
import 'package:test/test.dart';

Expression _expression(String source) =>
    ((parseString(content: 'final x = $source;').unit.declarations.single
            as TopLevelVariableDeclaration)
        .variables
        .variables
        .single
        .initializer)!;

void main() {
  group('plain condition', () {
    for (final (source, held, plain, written) in [
      ('offer != null', true, "when there's an offer", 'offer != null'),
      (
        'widget.plan != null',
        true,
        "when there's a plan",
        'widget.plan != null',
      ),
      ('offer == null', false, "when there's an offer", 'offer != null'),
      ('showBanner', true, 'when show banner is on', 'showBanner'),
      ('showBanner', false, 'when show banner is off', '!showBanner'),
      ('!widget.premium', true, 'when premium is off', '!widget.premium'),
      ('plans.isEmpty', true, 'when there are no plans', 'plans.isEmpty'),
      ('plans.isNotEmpty', true, 'when there are plans', 'plans.isNotEmpty'),
      (
        'plans.isNotEmpty',
        false,
        'when there are no plans',
        '!plans.isNotEmpty',
      ),
      (
        '!widget.plans.isEmpty',
        true,
        'when there are plans',
        '!widget.plans.isEmpty',
      ),
      ('isTrial', true, 'when `isTrial`', 'isTrial'),
      ('isTrial', false, 'when `!isTrial`', '!isTrial'),
      ('(plan.isTrial)', true, 'when `(plan.isTrial)`', '(plan.isTrial)'),
      ('plans.length > 2', true, 'when `plans.length > 2`', 'plans.length > 2'),
      ('offer == null', true, 'when `offer == null`', 'offer == null'),
    ]) {
      test('`$source` holding $held', () {
        final test = _expression(source);
        expect(plainCondition(test, held: held), plain);
        expect(conditionSource(test, held: held), written);
      });
    }
  });
}
