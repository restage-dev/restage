import 'package:restage_codegen/src/customer_structured_admissibility.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Every condition in the decision has a shape here that fails when that
/// condition alone is neutralised — checked one at a time, and by reading the
/// FAILURE CAUSE rather than the exit code, since a suite can go red for the
/// wrong reason.
///
/// Neutralising does not have to mean deleting. The is-a-class check cannot be
/// deleted — the checks after it are undefined on the broader element type, so
/// the file stops compiling — but inverting its verdict compiles, and the
/// function-typed row goes red when it is inverted. **A perturbation that does
/// not compile does not mean a condition is unprovable**; it means that
/// particular perturbation was the wrong one.
///
/// One thing this table does NOT cover: the alias unwrap in the classifier's
/// copy. Removing it leaves every row here green, which shows only that these
/// shapes do not exercise it — the single alias below points at a concrete
/// class, which resolves to the same underlying type either way. An alias to
/// an alias, an alias carrying type arguments, or an alias to a non-class type
/// are all unexamined. **Do not read the green as licence to delete the
/// unwrap**; read it as a gap in this table.
const _shapes = <({
  String closureTypeName,
  String declarations,
  bool isCustomerDataClass,
  String valueType,
})>[
  (
    declarations: '''
      class Plan {
        const Plan({required this.name});
        final String name;
      }
    ''',
    valueType: 'Plan',
    closureTypeName: 'Plan',
    isCustomerDataClass: true,
  ),
  // Abstract AND takes constructor parameters, deliberately. Without the
  // parameters this shape is already excluded for having no usable
  // constructor, so it would pass whether or not being-abstract is still
  // checked — a witness that cannot fail is not a witness.
  (
    declarations: '''
      abstract class AbsPlan {
        AbsPlan(this.name);
        final String name;
      }
    ''',
    valueType: 'AbsPlan',
    closureTypeName: 'AbsPlan',
    isCustomerDataClass: false,
  ),
  (
    declarations: '''
      class Empty {
        const Empty();
      }
    ''',
    valueType: 'Empty',
    closureTypeName: 'Empty',
    isCustomerDataClass: false,
  ),
  // A `dart:` class that clears every OTHER condition — concrete, and its
  // generative constructor takes a parameter. It is excluded only by being
  // outside the customer's own code, so it is the one shape that fails if that
  // check is dropped. Sibling SDK types were tried and do not work: their
  // constructors are factories or take nothing, so a stricter condition
  // already excludes them and they could not detect this one going missing.
  (
    declarations: '',
    valueType: 'StringBuffer',
    closureTypeName: 'StringBuffer',
    isCustomerDataClass: false,
  ),
  (
    declarations: '',
    valueType: 'void Function()',
    closureTypeName: 'void Function()',
    isCustomerDataClass: false,
  ),
  // A type alias for an admitted data class. Both copies answer the same, and
  // the row is kept precisely because their PRE-CHECKS differ: one resolves the
  // element without unwrapping aliases, the other unwraps first. That is where
  // two hand-copied predicates would plausibly drift, so an agreeing row here
  // is evidence rather than filler — do not delete it as redundant.
  //
  // The closure entry is named for the underlying class, not the alias, which
  // is why this row carries a different closureTypeName.
  (
    declarations: '''
      class Plan {
        const Plan({required this.name});
        final String name;
      }
      typedef PlanAlias = Plan;
    ''',
    valueType: 'PlanAlias',
    closureTypeName: 'Plan',
    isCustomerDataClass: true,
  ),
];

/// Discovery's verdict: does [valueType] join the closure when reached only
/// through a map on a widget property?
Future<bool> _joinsClosure(
  String declarations,
  String valueType,
  String closureTypeName,
) async {
  final result = await runWidgetVisitorOn({
    'lib/agreement_widget.dart': '''
      import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

      $declarations

      @RestageWidget(
        name: 'AgreementWidget',
        library: WidgetLibrary.custom('acme.design_system'),
        category: WidgetCategory.decoration,
        description: 'A widget with map-backed tiers.',
      )
      class AgreementWidget {
        const AgreementWidget({required this.tiers});
        @RestageProperty(description: 'The tiers.')
        final Map<String, $valueType> tiers;
      }
    ''',
  });

  return result.structuredTypes.any(
    (entry) => entry.sourceType.endsWith('#$closureTypeName'),
  );
}

/// The classifier's verdict: does [valueType] get the deferred cause when it is
/// the value of a map on a field of a data class?
Future<bool> _getsDeferredCause(String declarations, String valueType) async {
  final result = await runWidgetVisitorOn({
    'lib/agreement_holder_widget.dart': '''
      import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

      $declarations

      class Holder {
        const Holder({required this.tiers});
        final Map<String, $valueType> tiers;
      }

      @RestageWidget(
        name: 'AgreementHolderWidget',
        library: WidgetLibrary.custom('acme.design_system'),
        category: WidgetCategory.decoration,
        description: 'A widget with a holder.',
      )
      class AgreementHolderWidget {
        const AgreementHolderWidget({required this.holder});
        @RestageProperty(description: 'The holder.')
        final Holder holder;
      }
    ''',
  });
  final admission = computeAdmission(
    widgets: result.widgets,
    structuredTypes: result.structuredTypes,
    slotTargets: result.slotTargets,
    localUnrenderable: result.localUnrenderable,
    widgetUnrenderable: result.widgetUnrenderable,
    mapPlans: result.mapPlans,
  );

  return admission.excluded.single.reason.contains(
    'move the map to a widget property',
  );
}

void main() {
  test('both customer-data-class decisions agree on every boundary shape',
      () async {
    // The two packages each carry their own copy of this decision because the
    // dependency runs one way, so they cannot share it. If the copies drift,
    // nothing crashes: the classifier and discovery simply disagree about
    // what a customer data class is, and the visible result is a diagnostic
    // that is quietly wrong. This test turns that into a failure.
    for (final shape in _shapes) {
      final joined = await _joinsClosure(
        shape.declarations,
        shape.valueType,
        shape.closureTypeName,
      );
      final deferred =
          await _getsDeferredCause(shape.declarations, shape.valueType);
      expect(
        joined,
        deferred,
        reason: 'the two decisions disagree for ${shape.valueType}: '
            'discovery ${joined ? 'collected' : 'did not collect'} it, '
            'while the classifier '
            '${deferred ? 'called it' : 'did not call it'} customer-authored',
      );
      expect(
        joined,
        shape.isCustomerDataClass,
        reason: 'expected ${shape.valueType} to be '
            '${shape.isCustomerDataClass ? '' : 'not '}a customer data class',
      );
    }
  });
}
