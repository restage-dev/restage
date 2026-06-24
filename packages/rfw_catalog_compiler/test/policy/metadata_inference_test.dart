// packages/rfw_catalog_compiler/test/policy/metadata_inference_test.dart
import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart'
    show PropertyCategory, PropertyPriority;
import 'package:test/test.dart';

void main() {
  group('inferPropertyCategory — built-in heuristics', () {
    const heuristics = CategoryHeuristics(rules: kBuiltInCategoryHeuristics);

    test('callback property (onPressed) → behavior', () {
      expect(
        inferPropertyCategory('onPressed', heuristics),
        equals(PropertyCategory.behavior),
      );
    });

    test(r'^(color|backgroundColor|foregroundColor)$ → style', () {
      expect(
        inferPropertyCategory('color', heuristics),
        equals(PropertyCategory.style),
      );
    });

    test(r'^(alignment|crossAxisAlignment|mainAxisAlignment)$ → layout', () {
      expect(
        inferPropertyCategory('mainAxisAlignment', heuristics),
        equals(PropertyCategory.layout),
      );
    });

    test('^semantic.* → accessibility', () {
      expect(
        inferPropertyCategory('semanticLabel', heuristics),
        equals(PropertyCategory.accessibility),
      );
    });

    test('no match → null (conservative)', () {
      expect(
        inferPropertyCategory('elevation', heuristics),
        isNull,
      );
    });
  });

  group('inferPropertyPriority', () {
    test('required=true + requiredAsPrimary=true → primary', () {
      const heuristics = PriorityHeuristics(
        requiredAsPrimary: true,
        firstNCommon: 0,
      );
      expect(
        inferPropertyPriority(required: true, heuristics: heuristics),
        equals(PropertyPriority.primary),
      );
    });

    test('required=false + requiredAsPrimary=true → null', () {
      const heuristics = PriorityHeuristics(
        requiredAsPrimary: true,
        firstNCommon: 0,
      );
      expect(
        inferPropertyPriority(required: false, heuristics: heuristics),
        isNull,
      );
    });

    test(
        'required=true + requiredAsPrimary=false → null '
        '(heuristic toggle respected)', () {
      const heuristics = PriorityHeuristics(
        requiredAsPrimary: false,
        firstNCommon: 0,
      );
      expect(
        inferPropertyPriority(required: true, heuristics: heuristics),
        isNull,
      );
    });

    // Structural guard: inferPropertyPriority takes no declaration-index
    // parameter, so firstNCommon cannot influence its result. This test
    // confirms that two PriorityHeuristics values differing ONLY in
    // firstNCommon produce identical (null) output for a non-required
    // property — proving firstNCommon is not consulted.
    test('firstNCommon has no effect on non-required result', () {
      const heuristicsA = PriorityHeuristics(
        requiredAsPrimary: true,
        firstNCommon: 0,
      );
      const heuristicsB = PriorityHeuristics(
        requiredAsPrimary: true,
        firstNCommon: 5,
      );
      final resultA =
          inferPropertyPriority(required: false, heuristics: heuristicsA);
      final resultB =
          inferPropertyPriority(required: false, heuristics: heuristicsB);
      expect(resultA, isNull, reason: 'heuristicsA (firstNCommon=0)');
      expect(resultB, isNull, reason: 'heuristicsB (firstNCommon=5)');
    });
  });

  group('inferPropertyCategory — typeNameFilter', () {
    // A rule that only fires when typeName is exactly 'Color'.
    const colorTypedRule = CategoryRule(
      namePattern: r'^value$',
      category: PropertyCategory.style,
      typeNameFilter: 'Color',
    );
    const filteredHeuristics = CategoryHeuristics(rules: [colorTypedRule]);

    test('matches when typeName equals typeNameFilter', () {
      expect(
        inferPropertyCategory('value', filteredHeuristics, typeName: 'Color'),
        equals(PropertyCategory.style),
      );
    });

    test('does NOT match when typeName is null', () {
      expect(
        inferPropertyCategory('value', filteredHeuristics),
        isNull,
      );
    });

    test('does NOT match when typeName differs from typeNameFilter', () {
      expect(
        inferPropertyCategory(
          'value',
          filteredHeuristics,
          typeName: 'double',
        ),
        isNull,
      );
    });
  });
}
