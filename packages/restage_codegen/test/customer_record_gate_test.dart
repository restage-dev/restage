import 'package:restage_codegen/src/customer_structured_admissibility.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/widget_visitor.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Named-record admissibility — driven through the REAL walker/discovery.
///
/// The admitted boundary is a NAMED record whose labels are all NON-NULLABLE
/// scalars or enums. Everything outside it is EXCLUDED-LOUD: the owning widget
/// leaves the catalog with a named reason and the build CONTINUES — never
/// admitted-but-wrong, never silently dropped, never a hard build failure.
///
/// The `build continues` half is asserted explicitly on every excluded case,
/// because the pre-existing widget-property path fails the build outright for a
/// type it cannot infer; routing records to an exclusion instead of that
/// failure is part of the contract, not an accident.
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

const _tone = '''
  enum Tone { neutral, emphasis }
''';

const _dataClass = '''
  class Plan {
    const Plan({required this.name});
    final String name;
  }
''';

String _widget(String propertyDeclaration) => '''
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
  $_tone
  $_dataClass
  @RestageWidget(name: 'SectionHeader',
    library: WidgetLibrary.custom('acme.design_system'),
    category: WidgetCategory.decoration, description: 'h')
  class SectionHeader {
    const SectionHeader({required this.heading});
    @RestageProperty(description: 'h') $propertyDeclaration
  }
''';

String _nestedWidget(String fieldDeclaration) => '''
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
  $_tone
  $_dataClass
  class Entry {
    const Entry({required this.label, required this.meta});
    final String label;
    $fieldDeclaration
  }
  @RestageWidget(name: 'SectionHeader',
    library: WidgetLibrary.custom('acme.design_system'),
    category: WidgetCategory.decoration, description: 'h')
  class SectionHeader {
    const SectionHeader({required this.entry});
    @RestageProperty(description: 'e') final Entry entry;
  }
''';

void main() {
  group('admitted — a named record of non-nullable scalar/enum labels', () {
    // Admission alone is not evidence: a dropped property leaves a widget with
    // no structured slot, which `computeAdmission` admits vacuously. Every
    // admitted case therefore asserts the SLOT SURVIVED and carries the
    // opaque-record contract, not merely that the widget was admitted.
    void expectRecordSlot(
      CustomerStructuredAdmission admission,
      String propertyName,
    ) {
      final widget =
          admission.admitted.firstWhere((w) => w.name == 'SectionHeader');
      final prop =
          widget.properties.where((p) => p.name == propertyName).toList();
      expect(
        prop,
        hasLength(1),
        reason: 'the record property must survive the walk, not be dropped',
      );
      expect(prop.single.type, PropertyType.unknown);
      expect(isCustomerRecordPropertySlot(prop.single), isTrue);
    }

    test('all-scalar labels ADMIT the owning widget', () async {
      final r = await _admit({
        'lib/header.dart': _widget('final ({String title, int step}) heading;'),
      });
      expect(
        r.admission.admitted.map((w) => w.name),
        contains('SectionHeader'),
      );
      expect(r.admission.excluded, isEmpty);
      expectRecordSlot(r.admission, 'heading');
    });

    test('an ENUM label ADMITS the owning widget', () async {
      final r = await _admit({
        'lib/header.dart':
            _widget('final ({String title, Tone tone}) heading;'),
      });
      expect(
        r.admission.admitted.map((w) => w.name),
        contains('SectionHeader'),
      );
      expect(r.admission.excluded, isEmpty);
      expectRecordSlot(r.admission, 'heading');
    });

    test('a record behind a TYPE ALIAS ADMITS the owning widget', () async {
      final r = await _admit({
        'lib/header.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
          typedef Heading = ({String title, int step});
          @RestageWidget(name: 'SectionHeader',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.decoration, description: 'h')
          class SectionHeader {
            const SectionHeader({required this.heading});
            @RestageProperty(description: 'h') final Heading heading;
          }
        ''',
      });
      expect(
        r.admission.admitted.map((w) => w.name),
        contains('SectionHeader'),
      );
      expect(r.admission.excluded, isEmpty);
      expectRecordSlot(r.admission, 'heading');
    });

    test('a record FIELD nested in a data class ADMITS the owning widget',
        () async {
      final r = await _admit({
        'lib/header.dart':
            _nestedWidget('final ({int order, bool pinned}) meta;'),
      });
      expect(
        r.admission.admitted.map((w) => w.name),
        contains('SectionHeader'),
      );
      expect(r.admission.excluded, isEmpty);
      // The nested record rides the data class's field list, so the evidence
      // is on the STRUCTURED entry, not the widget property.
      final entry =
          r.result.structuredTypes.firstWhere((s) => s.name == 'Entry');
      final field = entry.fields.where((f) => f.name == 'meta').toList();
      expect(
        field,
        hasLength(1),
        reason: 'the nested record field must survive the walk, not be dropped',
      );
      expect(field.single.type, PropertyType.unknown);
      expect(isCustomerRecordFieldSlot(field.single), isTrue);
    });
  });

  group('excluded-loud — outside the boundary, and the build CONTINUES', () {
    Future<void> expectExcluded(
      Map<String, String> sources, {
      required Pattern reasonContains,
    }) async {
      final r = await _admit(sources);
      expect(r.admission.admitted, isEmpty);
      expect(r.admission.excluded, hasLength(1));
      expect(r.admission.excluded.single.widget.name, 'SectionHeader');
      expect(r.admission.excluded.single.reason, contains(reasonContains));
      expect(
        _hasBuildFatalPropertyIssue(r.result),
        isFalse,
        reason: 'an out-of-boundary record must EXCLUDE the widget, not fail '
            'the build',
      );
    }

    test('a POSITIONAL record field is excluded', () async {
      await expectExcluded(
        {'lib/header.dart': _widget('final (String, int) heading;')},
        reasonContains: 'positional',
      );
    });

    test('a NULLABLE label is excluded, naming the label', () async {
      await expectExcluded(
        {
          'lib/header.dart':
              _widget('final ({String title, int? step}) heading;'),
        },
        reasonContains: 'step',
      );
    });

    test('a PRIVATE label is excluded, naming the label', () async {
      await expectExcluded(
        {
          'lib/header.dart':
              _widget('final ({String title, int _step}) heading;'),
        },
        reasonContains: '_step',
      );
    });

    test('a MAP-typed label is excluded, naming the label', () async {
      // A record slot admits only non-nullable scalar or enum labels. A map is
      // neither. This is pinned explicitly because the map value shape is
      // itself carried on a scalar shape, so a boundary check that asks only
      // "is this a scalar shape?" would let a map label through while looking
      // like it was enforcing the rule.
      await expectExcluded(
        {
          'lib/header.dart':
              _widget('final ({String title, Map<String, int> data}) heading;'),
        },
        reasonContains: 'data',
      );
    });

    test('a NON-SCALAR label is excluded, naming the label', () async {
      await expectExcluded(
        {
          'lib/header.dart':
              _widget('final ({String title, Plan plan}) heading;'),
        },
        reasonContains: 'plan',
      );
    });

    test('a NESTED-RECORD label is excluded', () async {
      await expectExcluded(
        {
          'lib/header.dart': _widget(
            'final ({String title, ({int a}) inner}) heading;',
          ),
        },
        reasonContains: 'inner',
      );
    });

    test('a NULLABLE record SLOT is excluded', () async {
      await expectExcluded(
        {
          'lib/header.dart':
              _widget('final ({String title, int step})? heading;'),
        },
        reasonContains: 'heading',
      );
    });

    test(
        'a nullable record slot behind a TYPE ALIAS is excluded — alias '
        'unwrapping must not strip the slot nullability', () async {
      // Alias unwrapping instantiates with a non-nullable suffix, so the outer
      // `?` on `Heading?` is lost if the nullability is only read AFTER the
      // unwrap. Reading it before is what keeps this closed.
      await expectExcluded(
        {
          'lib/header.dart': '''
            import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
            typedef Heading = ({String title, int step});
            @RestageWidget(name: 'SectionHeader',
              library: WidgetLibrary.custom('acme.design_system'),
              category: WidgetCategory.decoration, description: 'h')
            class SectionHeader {
              const SectionHeader({required this.heading});
              @RestageProperty(description: 'h') final Heading? heading;
            }
          ''',
        },
        reasonContains: 'heading',
      );
    });

    test('the record contract does NOT leak into the OTHER emit target',
        () async {
      // The two targets resolve customer data shapes through different
      // substrates and their admitted boundaries differ deliberately. The
      // opaque-record marker is a shape of THIS target's wire; it must not
      // appear on the other target's catalog entries, and a record must not
      // change that target's exclusion behaviour either.
      final r = await runWidgetVisitorOn(
        {
          'lib/header.dart':
              _widget('final ({String title, int step}) heading;'),
        },
        target: WidgetVisitorTarget.a2ui,
      );
      final leaked = r.widgets
          .expand((w) => w.properties)
          .where(isCustomerRecordPropertySlot)
          .toList();
      expect(
        leaked,
        isEmpty,
        reason: 'the opaque-record shape must be scoped to this wire target',
      );
      expect(r.widgetUnrenderable, isEmpty);
    });

    test(
        'an out-of-boundary record NESTED in a data class excludes the owner, '
        'build continues', () async {
      await expectExcluded(
        {
          'lib/header.dart':
              _nestedWidget('final ({int order, bool? pinned}) meta;'),
        },
        reasonContains: 'meta',
      );
    });
  });
}
