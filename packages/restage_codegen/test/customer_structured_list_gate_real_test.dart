import 'package:restage_codegen/src/customer_structured_admissibility.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// List-of-objects admissibility — driven through the REAL walker/discovery.
///
/// Locks the list-of-objects admissibility invariants:
///  * a data class with a `List<ConcreteDataClass>` field is RENDERABLE — its
///    owning widget is ADMITTED;
///  * a `List<SealedUnion>` field and a bare sealed-union field stay
///    EXCLUDED-loud — a list of an unsupported item never admits a union or a
///    `List<union>`.
Future<CustomerStructuredAdmission> _admit(Map<String, String> sources) async {
  final result = await runWidgetVisitorOn(sources);
  return computeAdmission(
    widgets: result.widgets,
    structuredTypes: result.structuredTypes,
    slotTargets: result.slotTargets,
    localUnrenderable: result.localUnrenderable,
    widgetUnrenderable: result.widgetUnrenderable,
  );
}

const _leaf = '''
  class Feature {
    const Feature({required this.name, this.included = false});
    final String name;
    final bool included;
  }
''';

const _sealed = '''
  sealed class Shape {
    const Shape();
  }
  class Circle extends Shape {
    const Circle({required this.radius});
    final double radius;
  }
  class Square extends Shape {
    const Square({required this.side});
    final double side;
  }
''';

void main() {
  group('list-of-objects — real discovery', () {
    test(
        'a data class with a List<ConcreteDataClass> field is RENDERABLE — its '
        'widget is ADMITTED (RED until the un-drop lands)', () async {
      final admission = await _admit({
        'lib/card.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
          $_leaf
          class Panel {
            const Panel({required this.features});
            final List<Feature> features;
          }
          @RestageWidget(name: 'PanelCard',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.decoration, description: 'p')
          class PanelCard {
            const PanelCard({required this.panel});
            @RestageProperty(description: 'p') final Panel panel;
          }
        ''',
      });
      expect(admission.admitted.map((w) => w.name), contains('PanelCard'));
      expect(admission.excluded, isEmpty);
    });

    test(
        'a data class with a List<SealedUnion> field stays EXCLUDED-loud — the '
        'list un-drop must not admit a List<union>', () async {
      final admission = await _admit({
        'lib/card.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
          $_sealed
          class Panel {
            const Panel({required this.shapes});
            final List<Shape> shapes;
          }
          @RestageWidget(name: 'PanelCard',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.decoration, description: 'p')
          class PanelCard {
            const PanelCard({required this.panel});
            @RestageProperty(description: 'p') final Panel panel;
          }
        ''',
      });
      expect(admission.admitted, isEmpty);
      expect(admission.excluded, hasLength(1));
      expect(admission.excluded.single.widget.name, 'PanelCard');
    });

    test('a data class with a bare sealed-union field stays EXCLUDED-loud',
        () async {
      final admission = await _admit({
        'lib/card.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
          $_sealed
          class Panel {
            const Panel({required this.shape});
            final Shape shape;
          }
          @RestageWidget(name: 'PanelCard',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.decoration, description: 'p')
          class PanelCard {
            const PanelCard({required this.panel});
            @RestageProperty(description: 'p') final Panel panel;
          }
        ''',
      });
      expect(admission.admitted, isEmpty);
      expect(admission.excluded, hasLength(1));
      expect(admission.excluded.single.widget.name, 'PanelCard');
    });
  });
}
