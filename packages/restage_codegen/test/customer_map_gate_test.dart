import 'package:restage_codegen/src/customer_structured_admissibility.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/widget_visitor.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

Future<
    ({
      CustomerStructuredAdmission admission,
      WidgetVisitorResult result,
    })> _admit(Map<String, String> sources) async {
  final result = await runWidgetVisitorOn(sources);
  return (
    admission: computeAdmission(
      widgets: result.widgets,
      structuredTypes: result.structuredTypes,
      slotTargets: result.slotTargets,
      localUnrenderable: result.localUnrenderable,
      widgetUnrenderable: result.widgetUnrenderable,
      mapPlans: result.mapPlans,
    ),
    result: result,
  );
}

/// Whether the walk raised a BUILD-FATAL property issue — the failure mode an
/// exclusion must replace, not inherit.
bool _hasBuildFatalPropertyIssue(WidgetVisitorResult result) =>
    result.issues.any((i) => i.code == IssueCode.unsupportedPropertyType);

String _widget(String propertyDeclaration) => '''
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
  @RestageWidget(name: 'MapWidget',
    library: WidgetLibrary.custom('acme.design_system'),
    category: WidgetCategory.decoration, description: 'm')
  class MapWidget {
    const MapWidget({required this.values});
    @RestageProperty(description: 'v') $propertyDeclaration
  }
''';

void main() {
  test('an admitted map property survives with the map contract', () async {
    final r = await _admit({
      'lib/map_widget.dart': _widget('final Map<String, String> values;'),
    });

    final widget =
        r.admission.admitted.firstWhere((w) => w.name == 'MapWidget');
    final properties =
        widget.properties.where((prop) => prop.name == 'values').toList();
    expect(
      properties,
      hasLength(1),
      reason: 'the map property must survive the walk, not be dropped',
    );
    final prop = properties.single;
    expect(prop.type, PropertyType.unknown);
    expect(
      (prop.valueShape! as ScalarShape).isOpaqueStringKeyedMap,
      isTrue,
    );
  });

  test(
    'an unsupported map key excludes the widget and names the key',
    () async {
      final r = await _admit({
        'lib/map_widget.dart': _widget('final Map<int, String> values;'),
      });

      expect(r.admission.admitted, isEmpty);
      expect(r.admission.excluded, hasLength(1));
      expect(
        r.admission.excluded.single.reason,
        contains('map key type int'),
      );
      expect(
        _hasBuildFatalPropertyIssue(r.result),
        isFalse,
        reason: 'an unsupported map must exclude the widget, not fail the '
            'build',
      );
    },
  );

  test(
    'a map whose VALUE is a record excludes the widget and says so',
    () async {
      // A record resolves to an opaque value shape that is carried on a scalar
      // shape. A value check asking only "is this a scalar shape?" therefore
      // admits a record value while appearing to enforce the vocabulary, and
      // the admitted entry would carry a value shape nothing downstream can
      // reconstruct. The exclusion must name the record specifically, so it is
      // distinguishable from an ordinary unsupported value type.
      final r = await _admit({
        'lib/map_widget.dart': _widget(
          'final Map<String, ({String title, int step})> values;',
        ),
      });

      expect(r.admission.admitted, isEmpty);
      expect(r.admission.excluded, hasLength(1));
      expect(
        r.admission.excluded.single.reason,
        contains('is a record'),
      );
      expect(
        _hasBuildFatalPropertyIssue(r.result),
        isFalse,
        reason: 'a record-valued map must exclude the widget, not fail the '
            'build',
      );
    },
  );

  test('a nullable map slot excludes the widget with its cause', () async {
    final r = await _admit({
      'lib/map_widget.dart': _widget('final Map<String, String>? values;'),
    });

    expect(r.admission.admitted, isEmpty);
    expect(r.admission.excluded, hasLength(1));
    expect(
      r.admission.excluded.single.reason,
      contains('nullable map slot'),
    );
    expect(
      _hasBuildFatalPropertyIssue(r.result),
      isFalse,
      reason: 'a nullable map must exclude the widget, not fail the build',
    );
  });

  test('the map contract does not leak into the other target', () async {
    final result = await runWidgetVisitorOn(
      {
        'lib/map_widget.dart': _widget('final Map<String, String> values;'),
      },
      target: WidgetVisitorTarget.a2ui,
    );

    final mapMarkedProperties =
        result.widgets.expand((widget) => widget.properties).where((prop) {
      final shape = prop.valueShape;
      return shape is ScalarShape && shape.isOpaqueStringKeyedMap;
    });
    expect(mapMarkedProperties, isEmpty);
  });
}
