import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/widget_classification.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('CustomWidgetParam', () {
    test('carries the parameter name, numeric flag, and default', () {
      const param = CustomWidgetParam(
        name: 'size',
        isNumeric: true,
        defaultValue: 8,
      );

      expect(param.name, 'size');
      expect(param.isNumeric, isTrue);
      expect(param.defaultValue, 8);
    });
  });

  group('CustomWidgetBlueprint', () {
    test('exposes its fields and an unmodifiable params list', () async {
      final expr = await parseExpressionForTest('42');
      final blueprint = CustomWidgetBlueprint(
        classKey: 'pkg#AcmeCard',
        rfwName: 'AcmeCard',
        buildExpression: expr,
        params: const [
          CustomWidgetParam(
            name: 'label',
            isNumeric: false,
            defaultValue: null,
          ),
        ],
      );

      expect(blueprint.classKey, 'pkg#AcmeCard');
      expect(blueprint.rfwName, 'AcmeCard');
      expect(blueprint.buildExpression, same(expr));
      expect(blueprint.params.map((p) => p.name), ['label']);
      expect(
        () => blueprint.params.add(
          const CustomWidgetParam(
            name: 'x',
            isNumeric: false,
            defaultValue: null,
          ),
        ),
        throwsUnsupportedError,
      );
    });
  });

  group('ClassificationResult', () {
    test('exposes unmodifiable classifications and blueprints maps', () async {
      final expr = await parseExpressionForTest('42');
      final classification = ComposableWidget(
        'pkg#AcmeCard',
        requiredMechanisms: const {},
        composedCustomWidgets: const [],
      );
      final blueprint = CustomWidgetBlueprint(
        classKey: 'pkg#AcmeCard',
        rfwName: 'AcmeCard',
        buildExpression: expr,
        params: const [],
      );
      final result = ClassificationResult(
        classifications: {'pkg#AcmeCard': classification},
        blueprints: {'pkg#AcmeCard': blueprint},
      );

      expect(result.classifications['pkg#AcmeCard'], same(classification));
      expect(result.blueprints['pkg#AcmeCard'], same(blueprint));
      expect(
        () => result.classifications['x'] = classification,
        throwsUnsupportedError,
      );
      expect(
        () => result.blueprints['x'] = blueprint,
        throwsUnsupportedError,
      );
    });
  });
}
