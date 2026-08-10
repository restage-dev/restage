import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/widget_visitor.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('visitRestageWidgets', () {
    test('finds a single @RestageWidget class with no properties', () async {
      final result = await runWidgetVisitorOn({
        'lib/foo.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          @RestageWidget(
            name: 'Foo',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.layout,
            description: 'A foo widget.',
          )
          class Foo {
            const Foo();
          }
        ''',
      });

      expect(result.issues, isEmpty);
      expect(result.widgets, hasLength(1));
      final w = result.widgets.single;
      expect(w.name, 'Foo');
      expect(w.library.namespace, 'acme.design_system');
      expect(w.category, WidgetCategory.layout);
      expect(w.description, 'A foo widget.');
      expect(w.childrenSlot, ChildrenSlot.none);
    });

    test('skips classes without the annotation', () async {
      final result = await runWidgetVisitorOn({
        'lib/foo.dart': '''
          class Plain { const Plain(); }
        ''',
      });
      expect(result.widgets, isEmpty);
      expect(result.issues, isEmpty);
    });

    test('emits missingAnnotationField when description is missing', () async {
      final result = await runWidgetVisitorOn({
        'lib/foo.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          @RestageWidget(
            name: 'Foo',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.layout,
            description: null,
          )
          class Foo { const Foo(); }
        ''',
      });
      expect(result.widgets, isEmpty);
      expect(result.issues, hasLength(1));
      expect(result.issues.single.code, IssueCode.missingAnnotationField);
    });

    test('captures @RestageProperty fields with description and required',
        () async {
      final result = await runWidgetVisitorOn(
        {
          'lib/btn.dart': '''
            import 'package:flutter/widgets.dart';
            import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

            @RestageWidget(
              name: 'Btn',
              library: WidgetLibrary.custom('acme.design_system'),
              category: WidgetCategory.input,
              description: 'CTA.',
            )
            class Btn {
              const Btn({
                required this.child,
                this.onArbitraryCustomerAction,
              });
              @RestageProperty(description: 'Label', required: true)
              final Widget child;
              @RestageProperty(description: 'Tap')
              final void Function()? onArbitraryCustomerAction;
            }
          ''',
        },
      );

      expect(result.issues, isEmpty);
      final w = result.widgets.single;
      expect(w.childrenSlot, ChildrenSlot.none);
      expect(w.properties, hasLength(2));
      final child = w.properties.firstWhere((p) => p.name == 'child');
      expect(child.required, isTrue);
      expect(child.type, PropertyType.widget);
      final tap = w.properties.firstWhere(
        (p) => p.name == 'onArbitraryCustomerAction',
      );
      expect(tap.required, isFalse);
      expect(tap.type, PropertyType.event);
    });

    test('RFW admits callbacks structurally and rejects unsupported shapes',
        () async {
      final result = await runWidgetVisitorOn({
        'lib/callbacks.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          class Payload {}

          @RestageWidget(
            name: 'Callbacks',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.input,
            description: 'Callback shape proof.',
          )
          class Callbacks {
            const Callbacks({
              this.onArbitraryCustomerAction,
              this.onValue,
              this.onNullableValue,
              this.onValues,
              this.onValuesWithNullableElements,
              this.onNestedValues,
              this.onOuterNullableValues,
              this.onOptional,
              this.onTwoValues,
              this.onReturningValue,
              this.onPayload,
            });

            @RestageProperty(description: 'No payload.')
            final void Function()? onArbitraryCustomerAction;
            @RestageProperty(description: 'One scalar payload.')
            final void Function(String)? onValue;
            @RestageProperty(description: 'One nullable scalar payload.')
            final void Function(String?)? onNullableValue;
            @RestageProperty(description: 'One list payload.')
            final void Function(List<String>)? onValues;
            @RestageProperty(description: 'One list with nullable elements.')
            final void Function(List<String?>)? onValuesWithNullableElements;
            @RestageProperty(description: 'Unsupported nested-list payload.')
            final void Function(List<List<String>>)? onNestedValues;
            @RestageProperty(description: 'Unsupported nullable-list payload.')
            final void Function(List<String>?)? onOuterNullableValues;
            @RestageProperty(description: 'Optional payload.')
            final void Function([String])? onOptional;
            @RestageProperty(description: 'Two payloads.')
            final void Function(String, int)? onTwoValues;
            @RestageProperty(description: 'Non-void return.')
            final String Function()? onReturningValue;
            @RestageProperty(description: 'Unsupported payload.')
            final void Function(Payload)? onPayload;
          }
        ''',
      });

      final properties = {
        for (final property in result.widgets.single.properties)
          property.name: property,
      };
      expect(
        properties['onArbitraryCustomerAction']!.callbackSignature,
        isNull,
      );
      expect(
        properties['onValue']!.callbackSignature,
        'ValueChanged<String>',
      );
      expect(
        properties['onNullableValue']!.callbackSignature,
        'ValueChanged<String?>',
      );
      expect(
        properties['onValues']!.callbackSignature,
        'ValueChanged<List<String>>',
      );
      expect(
        properties['onValuesWithNullableElements']!.callbackSignature,
        'ValueChanged<List<String?>>',
      );
      final invalid = result.issues
          .where((issue) => issue.code == IssueCode.invalidEventConfiguration)
          .toList();
      expect(invalid, hasLength(6));
      expect(
        invalid.map((issue) => issue.location),
        containsAll([
          'lib/callbacks.dart#Callbacks.onNestedValues',
          'lib/callbacks.dart#Callbacks.onOuterNullableValues',
          'lib/callbacks.dart#Callbacks.onOptional',
          'lib/callbacks.dart#Callbacks.onTwoValues',
          'lib/callbacks.dart#Callbacks.onReturningValue',
          'lib/callbacks.dart#Callbacks.onPayload',
        ]),
      );
    });

    test('emits unsupportedPropertyType for an unknown static type', () async {
      final result = await runWidgetVisitorOn({
        'lib/foo.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          class Mystery {}

          @RestageWidget(
            name: 'Foo',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.layout,
            description: 'A foo widget.',
          )
          class Foo {
            const Foo({required this.weird});
            @RestageProperty(description: 'Weird thing.')
            final Mystery weird;
          }
        ''',
      });

      expect(
        result.issues.map((i) => i.code),
        contains(IssueCode.unsupportedPropertyType),
      );
      // The widget itself still produces an entry — only the bad property
      // is dropped — so a single typo doesn't hide the whole widget from
      // the catalog.
      expect(result.widgets, hasLength(1));
      expect(result.widgets.single.properties, isEmpty);
    });

    test(
        'records an exclusion instead of failing for an OPTIONAL input '
        'whose type has no decoder', () async {
      final result = await runWidgetVisitorOn({
        'lib/foo.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          class Mystery {}

          @RestageWidget(
            name: 'Foo',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.layout,
            description: 'A foo widget.',
          )
          class Foo {
            const Foo({this.weird});
            @RestageProperty(description: 'Weird thing.')
            final Mystery? weird;
          }
        ''',
      });

      // An optional input the compiler cannot decode is ordinary Dart
      // omission: the author can do nothing about a missing decoder, so the
      // build must not fail. The omission is reported instead.
      expect(result.issues, isEmpty);
      expect(result.widgets, hasLength(1));
      expect(result.widgets.single.properties, isEmpty);

      expect(result.exclusions, hasLength(1));
      final excluded = result.exclusions.single;
      expect(excluded.widget, 'Foo');
      expect(excluded.property, 'weird');
      expect(excluded.reason, contains('Mystery'));
      expect(excluded.location, contains('Foo.weird'));
    });

    test(
        'fails loudly and records NO exclusion for a REQUIRED input '
        'whose type has no decoder', () async {
      final result = await runWidgetVisitorOn({
        'lib/foo.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          class Mystery {}

          @RestageWidget(
            name: 'Foo',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.layout,
            description: 'A foo widget.',
          )
          class Foo {
            const Foo({required this.weird});
            @RestageProperty(description: 'Weird thing.')
            final Mystery weird;
          }
        ''',
      });

      // A required input cannot be left out, so there is no legal omission to
      // record. It fails, and the message names what the author can actually
      // do about it.
      expect(
        result.issues.map((i) => i.code),
        contains(IssueCode.unsupportedPropertyType),
      );
      final message = result.issues
          .firstWhere((i) => i.code == IssueCode.unsupportedPropertyType)
          .message;
      expect(message, contains('Mystery'));
      expect(message, contains('default'));
      expect(message, contains('wrapper'));
      expect(result.exclusions, isEmpty);
    });

    test('A2UI mode admits every reflected scalar-list family', () async {
      final result = await runWidgetVisitorOn(
        {
          'lib/scalar_lists.dart': '''
            import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

            @RestageWidget(
              name: 'ScalarLists',
              library: WidgetLibrary.custom('acme.design_system'),
              category: WidgetCategory.layout,
              description: 'Scalar list proof.',
            )
            class ScalarLists {
              const ScalarLists({
                required this.labels,
                required this.counts,
                required this.weights,
                required this.measurements,
                required this.flags,
                this.maybeCounts,
              });

              @RestageProperty(description: 'Labels.')
              final List<String> labels;
              @RestageProperty(description: 'Counts.')
              final List<int> counts;
              @RestageProperty(description: 'Weights.')
              final List<double> weights;
              @RestageProperty(description: 'Measurements.')
              final List<num> measurements;
              @RestageProperty(description: 'Flags.')
              final List<bool> flags;
              @RestageProperty(description: 'Optional counts.')
              final List<int>? maybeCounts;
            }
          ''',
        },
        target: WidgetVisitorTarget.a2ui,
      );

      expect(result.issues, isEmpty);
      final properties = result.widgets.single.properties;
      expect(
        properties.map((property) => property.name),
        [
          'labels',
          'counts',
          'weights',
          'measurements',
          'flags',
          'maybeCounts',
        ],
      );
      expect(
        properties.map((property) => property.type),
        everyElement(PropertyType.structured),
      );
      expect(
        properties
            .where((property) => property.name != 'maybeCounts')
            .map((property) => property.required),
        everyElement(isTrue),
      );
      expect(
        properties
            .singleWhere((property) => property.name == 'maybeCounts')
            .required,
        isFalse,
      );
    });

    test('named A2UI target derives the complete constructor-required matrix',
        () async {
      final result = await runWidgetVisitorOn(
        {
          'lib/requiredness.dart': '''
            import 'package:flutter/widgets.dart';
            import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

            enum Tone { warm, cool }
            class Details {
              const Details({required this.count});
              final int count;
            }

            @RestageWidget(
              name: 'Requiredness',
              library: WidgetLibrary.custom('acme.design_system'),
              category: WidgetCategory.layout,
              description: 'Requiredness proof.',
            )
            class Requiredness {
              const Requiredness({
                required this.title,
                required this.tone,
                required this.counts,
                required this.details,
                required this.child,
                required this.children,
                required this.maybeTitle,
                this.optionalLabel,
                this.defaultedCount = 3,
                required this.onTap,
              });

              @RestageProperty(description: 'Title.')
              final String title;
              @RestageProperty(description: 'Tone.')
              final Tone tone;
              @RestageProperty(description: 'Counts.')
              final List<int> counts;
              @RestageProperty(description: 'Details.')
              final Details details;
              @RestageProperty(description: 'Child.')
              final Widget child;
              @RestageProperty(description: 'Children.')
              final List<Widget> children;
              @RestageProperty(description: 'Required nullable title.')
              final String? maybeTitle;
              @RestageProperty(description: 'Optional label.')
              final String? optionalLabel;
              @RestageProperty(description: 'Defaulted count.')
              final int defaultedCount;
              @RestageProperty(description: 'Tap callback.')
              final void Function() onTap;
            }
          ''',
        },
        target: WidgetVisitorTarget.a2ui,
      );

      expect(result.issues, isEmpty);
      final properties = {
        for (final property in result.widgets.single.properties)
          property.name: property,
      };
      for (final name in [
        'title',
        'tone',
        'counts',
        'details',
        'child',
        'children',
        'maybeTitle',
      ]) {
        expect(properties[name]!.required, isTrue, reason: name);
      }
      expect(properties['optionalLabel']!.required, isFalse);
      expect(properties['defaultedCount']!.required, isFalse);
      expect(properties['onTap']!.required, isTrue);
      expect(properties['onTap']!.type, PropertyType.event);
      expect(properties['tone']!.enumType, 'Tone');
      expect(properties['tone']!.valueShape, isA<EnumShape>());
      expect(properties['counts']!.type, PropertyType.structured);
      expect(properties['details']!.type, PropertyType.structured);
      expect(properties['child']!.type, PropertyType.widget);
      expect(properties['children']!.type, PropertyType.widgetList);
    });

    test('the named RFW target is byte-neutral with the legacy default',
        () async {
      const sources = <String, String>{
        'lib/rfw_requiredness.dart': '''
          import 'package:flutter/widgets.dart';
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          enum Tone { warm, cool }

          @RestageWidget(
            name: 'RfwRequiredness',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.layout,
            description: 'RFW no-change proof.',
          )
          class RfwRequiredness {
            const RfwRequiredness({
              required this.title,
              required this.tone,
              required this.child,
              required this.children,
              required this.onTap,
            });

            @RestageProperty(description: 'Title.')
            final String title;
            @RestageProperty(description: 'Tone.')
            final Tone tone;
            @RestageProperty(description: 'Child.')
            final Widget child;
            @RestageProperty(description: 'Children.')
            final List<Widget> children;
            @RestageProperty(description: 'Tap callback.')
            final void Function() onTap;
          }
        ''',
      };

      final legacy = await runWidgetVisitorOn(
        sources,
      );
      final named = await runWidgetVisitorOn(
        sources,
        // Explicit target is the contract under test, despite matching default.
        // ignore: avoid_redundant_argument_values
        target: WidgetVisitorTarget.rfw,
      );
      List<(String, PropertyType, bool, bool)> snapshot(
        WidgetVisitorResult result,
      ) =>
          [
            for (final property in result.widgets.single.properties)
              (
                property.name,
                property.type,
                property.required,
                property.positional,
              ),
          ];

      expect(
        named.issues.map((issue) => issue.code),
        legacy.issues.map((issue) => issue.code),
      );
      expect(snapshot(named), snapshot(legacy));
      final namedTone = named.widgets.single.properties
          .singleWhere((property) => property.name == 'tone');
      // The RFW target now carries the customer enum's identity — it
      // was previously dropped here, which made the RFW customer catalog reject
      // the enum slot. The RFW-vs-legacy-default byte-neutrality asserted above
      // still holds (both are the RFW target), so this pins the corrected RFW
      // behavior, not a divergence between the explicit target and the default.
      expect(namedTone.enumType, 'Tone');
      expect(namedTone.valueShape, isA<EnumShape>());
      expect(
        snapshot(named),
        [
          ('title', PropertyType.string, true, false),
          ('tone', PropertyType.enumValue, true, false),
          ('child', PropertyType.widget, true, false),
          ('children', PropertyType.widgetList, true, false),
          ('onTap', PropertyType.event, true, false),
        ],
      );
    });

    test('A2UI mode still rejects a list whose element is not a scalar',
        () async {
      final result = await runWidgetVisitorOn(
        {
          'lib/unsupported_list.dart': '''
            import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

            @RestageWidget(
              name: 'UnsupportedList',
              library: WidgetLibrary.custom('acme.design_system'),
              category: WidgetCategory.layout,
              description: 'Unsupported list proof.',
            )
            class UnsupportedList {
              const UnsupportedList({required this.timestamps});

              @RestageProperty(description: 'Timestamps.')
              final List<DateTime> timestamps;
            }
          ''',
        },
        target: WidgetVisitorTarget.a2ui,
      );

      expect(result.widgets.single.properties, isEmpty);
      expect(
        result.issues,
        contains(
          isA<Issue>()
              .having(
                (issue) => issue.code,
                'code',
                IssueCode.unsupportedPropertyType,
              )
              .having(
                (issue) => issue.message,
                'message',
                allOf(contains('List<DateTime>'), contains('List<scalar>')),
              ),
        ),
      );
    });

    test('synthesizes flutterType from the class library URI + class name',
        () async {
      final result = await runWidgetVisitorOn({
        'lib/foo.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          @RestageWidget(
            name: 'Foo',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.layout,
            description: 'A foo widget.',
          )
          class Foo { const Foo(); }
        ''',
      });
      expect(result.widgets.single.flutterType, endsWith('foo.dart#Foo'));
    });

    test(
        'emits duplicateWidgetName when two @RestageWidget classes share a '
        'name in the same library', () async {
      final result = await runWidgetVisitorOn({
        'lib/foo.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          @RestageWidget(
            name: 'Same',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.layout,
            description: 'one',
          )
          class A { const A(); }

          @RestageWidget(
            name: 'Same',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.layout,
            description: 'two',
          )
          class B { const B(); }
        ''',
      });

      final issue = result.issues
          .firstWhere((i) => i.code == IssueCode.duplicateWidgetName);
      expect(issue.message, contains('A'));
      expect(issue.message, contains('B'));
      expect(issue.message, contains('acme.design_system'));
      expect(issue.message, contains('Same'));
    });

    test('rejects abstract @RestageWidget classes', () async {
      final result = await runWidgetVisitorOn({
        'lib/foo.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          @RestageWidget(
            name: 'AbstractWidget',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.layout,
            description: 'never instantiable',
          )
          abstract class AbstractWidget {}
        ''',
      });
      expect(result.widgets, isEmpty);
      expect(
        result.issues.map((i) => i.code),
        contains(IssueCode.invalidWidgetClass),
      );
    });

    test('rejects private @RestageWidget classes', () async {
      final result = await runWidgetVisitorOn({
        'lib/foo.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          @RestageWidget(
            name: 'Private',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.layout,
            description: 'private to this file',
          )
          class _Private { const _Private(); }
        ''',
      });
      expect(result.widgets, isEmpty);
      expect(
        result.issues.map((i) => i.code),
        contains(IssueCode.invalidWidgetClass),
      );
    });

    test('const-eval failure produces an actionable diagnostic', () async {
      final result = await runWidgetVisitorOn({
        'lib/foo.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          @RestageWidget(
            name: 'Foo',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.layout,
            description: null,
          )
          class Foo { const Foo(); }
        ''',
      });
      expect(result.widgets, isEmpty);
      final issue = result.issues
          .firstWhere((i) => i.code == IssueCode.missingAnnotationField);
      expect(issue.message, contains('Foo'));
      expect(issue.message.toLowerCase(), contains('compile-time constant'));
    });

    test('decodes literal defaultSource and defaultBrandToken on properties',
        () async {
      final result = await runWidgetVisitorOn({
        'lib/btn.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          @RestageWidget(
            name: 'Btn',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.input,
            description: 'CTA.',
          )
          class Btn {
            const Btn({this.label = 'Buy', this.color, this.padding = 12});
            @RestageProperty(
              description: 'Label.',
              defaultSource: LiteralDefault('Buy'),
            )
            final String label;
            @RestageProperty(description: 'Color.', defaultBrandToken: 'primary')
            final String? color;
            @RestageProperty(
              description: 'Padding.',
              defaultSource: LiteralDefault(12),
            )
            final int padding;
          }
        ''',
      });
      expect(result.issues, isEmpty);
      final byName = {
        for (final p in result.widgets.single.properties) p.name: p,
      };
      expect(byName['label']!.defaultValue, 'Buy');
      expect(byName['color']!.defaultBrandToken, 'primary');
      expect(byName['padding']!.defaultValue, 12);
    });

    test('decodes @RestageProperty defaultSource', () async {
      final result = await runWidgetVisitorOn({
        'lib/btn.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          @RestageWidget(
            name: 'Btn',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.input,
            description: 'CTA.',
          )
          class Btn {
            const Btn({this.label, this.tokenColor});
            @RestageProperty(
              description: 'Label.',
              defaultSource: LiteralDefault('Buy'),
            )
            final String? label;
            @RestageProperty(
              description: 'Token color.',
              defaultSource: TokenRefDefault(
                WireIdRef(
                  library: 'acme.design_system',
                  wireId: WireId.unallocatedDesignToken,
                ),
              ),
            )
            final String? tokenColor;
          }
        ''',
      });

      expect(result.issues, isEmpty);
      final byName = {
        for (final p in result.widgets.single.properties) p.name: p,
      };
      expect(byName['label']!.defaultSource, const LiteralDefault('Buy'));
      expect(byName['label']!.defaultValue, 'Buy');
      expect(
        byName['tokenColor']!.defaultSource,
        const TokenRefDefault(
          WireIdRef(
            library: 'acme.design_system',
            wireId: WireId.unallocatedDesignToken,
          ),
        ),
      );
    });

    test('decodes typed constraints and legacy validation without loss',
        () async {
      final result = await runWidgetVisitorOn(
        {
          'lib/constrained.dart': '''
            import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

            @RestageWidget(
              name: 'Constrained',
              library: WidgetLibrary.custom('acme.design_system'),
              category: WidgetCategory.input,
              description: 'Constraint propagation proof.',
            )
            class Constrained {
              const Constrained({
                required this.count,
                required this.ratio,
                required this.label,
                required this.options,
                required this.legacy,
              });

              @RestageProperty(
                description: 'Count.',
                constraints: RestageConstraints(
                  minimum: 1,
                  exclusiveMaximum: 11,
                  allowedValues: [1, 2, null],
                ),
              )
              final int count;

              @RestageProperty(
                description: 'Ratio.',
                constraints: RestageConstraints(
                  exclusiveMinimum: 0.5,
                  maximum: 9.5,
                ),
              )
              final double ratio;

              @RestageProperty(
                description: 'Label.',
                constraints: RestageConstraints(
                  allowedValues: ['short', 'long', null],
                  pattern: r'^[a-z]+',
                  minLength: 2,
                  maxLength: 8,
                ),
              )
              final String label;

              @RestageProperty(
                description: 'Options.',
                constraints: RestageConstraints(minItems: 1, maxItems: 4),
              )
              final List<String> options;

              @RestageProperty(
                description: 'Legacy.',
                validationRule: ValidationExpr(
                  expression: 'legacy(value) == true',
                  message: 'Keep this message exactly.',
                ),
              )
              final String legacy;
            }
          ''',
        },
        target: WidgetVisitorTarget.a2ui,
      );

      expect(result.issues, isEmpty);
      final properties = {
        for (final property in result.widgets.single.properties)
          property.name: property,
      };
      expect(
        properties['count']!.constraints,
        const RestageConstraints(
          minimum: 1,
          exclusiveMaximum: 11,
          allowedValues: [1, 2, null],
        ),
      );
      expect(properties['count']!.constraints.minimum, isA<int>());
      expect(properties['count']!.constraints.exclusiveMaximum, isA<int>());
      expect(
        () => properties['count']!.constraints.allowedValues!.add(3),
        throwsUnsupportedError,
      );
      expect(
        properties['ratio']!.constraints,
        const RestageConstraints(exclusiveMinimum: 0.5, maximum: 9.5),
      );
      expect(
        properties['ratio']!.constraints.exclusiveMinimum,
        isA<double>(),
      );
      expect(properties['ratio']!.constraints.maximum, isA<double>());
      expect(
        properties['label']!.constraints,
        const RestageConstraints(
          allowedValues: ['short', 'long', null],
          pattern: '^[a-z]+',
          minLength: 2,
          maxLength: 8,
        ),
      );
      expect(
        properties['options']!.constraints,
        const RestageConstraints(minItems: 1, maxItems: 4),
      );
      expect(
        properties['legacy']!.validationRule,
        const ValidationExpr(
          expression: 'legacy(value) == true',
          message: 'Keep this message exactly.',
        ),
      );
    });

    test('rejects typed constraints combined with legacy validation', () async {
      final result = await runWidgetVisitorOn({
        'lib/conflict.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          @RestageWidget(
            name: 'ConflictedWidget',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.input,
            description: 'Conflict proof.',
          )
          class ConflictedWidget {
            const ConflictedWidget({required this.value});

            @RestageProperty(
              description: 'Conflicted property.',
              validationRule: ValidationExpr(
                expression: 'legacy(value)',
                message: 'Legacy rule.',
              ),
              constraints: RestageConstraints(minLength: 1),
            )
            final String value;
          }
        ''',
      });

      expect(result.widgets.single.properties, isEmpty);
      expect(
        result.issues,
        contains(
          isA<Issue>()
              .having(
                (issue) => issue.code,
                'code',
                IssueCode.conflictingValidationStrategy,
              )
              .having(
                (issue) => issue.message,
                'message',
                allOf(contains('ConflictedWidget'), contains('value')),
              )
              .having(
                (issue) => issue.location,
                'location',
                contains('ConflictedWidget.value'),
              ),
        ),
      );
    });

    test('rejects typed constraints with non-JSON allowed values', () async {
      final result = await runWidgetVisitorOn({
        'lib/invalid_allowed_values.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          @RestageWidget(
            name: 'InvalidAllowedValues',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.input,
            description: 'Representation admission proof.',
          )
          class InvalidAllowedValues {
            const InvalidAllowedValues({
              required this.duration,
              required this.infinity,
            });

            @RestageProperty(
              description: 'Duration value.',
              constraints: RestageConstraints(
                allowedValues: [Duration(seconds: 1)],
              ),
            )
            final String duration;

            @RestageProperty(
              description: 'Infinite value.',
              constraints: RestageConstraints(
                allowedValues: [double.infinity],
              ),
            )
            final double infinity;
          }
        ''',
      });

      expect(result.widgets.single.properties, isEmpty);
      final invalid = result.issues
          .where((issue) => issue.code == IssueCode.invalidConstraintValue)
          .toList();
      expect(invalid, hasLength(2));
      expect(
        invalid.map((issue) => issue.message),
        everyElement(contains('allowedValues[0]')),
      );
      expect(invalid[0].message, contains('InvalidAllowedValues.duration'));
      expect(invalid[0].message, contains('Duration'));
      expect(invalid[1].message, contains('InvalidAllowedValues.infinity'));
      expect(invalid[1].message, contains('double'));
    });

    test('rejects non-finite numeric constraint bounds with bound context',
        () async {
      final result = await runWidgetVisitorOn({
        'lib/non_finite_bounds.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          @RestageWidget(
            name: 'NonFiniteBounds',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.input,
            description: 'Finite-bound admission proof.',
          )
          class NonFiniteBounds {
            const NonFiniteBounds({
              required this.minimum,
              required this.exclusiveMinimum,
              required this.maximum,
              required this.exclusiveMaximum,
            });

            @RestageProperty(
              description: 'Infinite minimum.',
              constraints: RestageConstraints(minimum: double.infinity),
            )
            final double minimum;

            @RestageProperty(
              description: 'Negative infinite exclusive minimum.',
              constraints: RestageConstraints(
                exclusiveMinimum: -double.infinity,
              ),
            )
            final double exclusiveMinimum;

            @RestageProperty(
              description: 'NaN maximum.',
              constraints: RestageConstraints(maximum: double.nan),
            )
            final double maximum;

            @RestageProperty(
              description: 'Infinite exclusive maximum.',
              constraints: RestageConstraints(
                exclusiveMaximum: double.infinity,
              ),
            )
            final double exclusiveMaximum;
          }
        ''',
      });

      expect(result.widgets.single.properties, isEmpty);
      final invalid = result.issues
          .where((issue) => issue.code == IssueCode.invalidConstraintValue)
          .toList();
      expect(invalid, hasLength(4));
      for (final bound in const [
        'minimum',
        'exclusiveMinimum',
        'maximum',
        'exclusiveMaximum',
      ]) {
        expect(
          invalid.map((issue) => issue.message),
          contains(
            allOf(
              contains('constraints.$bound'),
              contains('NonFiniteBounds.$bound'),
              contains('finite compile-time constant int or double'),
            ),
          ),
        );
      }
    });

    test(
        'typed singleton WidgetLibrary.core resolves to its built-in '
        'namespace', () async {
      final result = await runWidgetVisitorOn({
        'lib/foo.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          @RestageWidget(
            name: 'Foo',
            library: WidgetLibrary.core,
            category: WidgetCategory.layout,
            description: 'A foo widget.',
          )
          class Foo { const Foo(); }
        ''',
      });
      expect(result.issues, isEmpty);
      expect(result.widgets.single.library.namespace, 'restage.core');
    });

    test(
        'a positional constructor parameter marks the property positional '
        '(so the emitted constructor call is positional, not named)', () async {
      final result = await runWidgetVisitorOn({
        'lib/badge_card.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          @RestageWidget(
            name: 'BadgeCard',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.decoration,
            description: 'A badge card.',
          )
          class BadgeCard {
            const BadgeCard(this.label);
            @RestageProperty(description: 'The label.')
            final String label;
          }
        ''',
      });
      expect(result.issues, isEmpty);
      expect(
        result.widgets.single.properties.single.positional,
        isTrue,
        reason: 'a positional ctor param must mark the property positional so '
            'the generated constructor call is BadgeCard(label), not '
            'BadgeCard(label: ...) — the latter does not compile',
      );
    });

    test('a named constructor parameter leaves the property non-positional',
        () async {
      final result = await runWidgetVisitorOn({
        'lib/badge_card.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          @RestageWidget(
            name: 'BadgeCard',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.decoration,
            description: 'A badge card.',
          )
          class BadgeCard {
            const BadgeCard({required this.label});
            @RestageProperty(description: 'The label.')
            final String label;
          }
        ''',
      });
      expect(result.issues, isEmpty);
      expect(result.widgets.single.properties.single.positional, isFalse);
    });

    test(
        'an unresolvable @RestageWidget is reported, not silently treated '
        'as not-a-widget', () async {
      // No import, so the annotation does not resolve. Skipping it would make
      // the class quietly absent from the catalog with nothing to look at.
      final result = await runWidgetVisitorOn({
        'lib/foo.dart': '''
          @RestageWidget(
            name: 'Foo',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.layout,
            description: 'A foo widget.',
          )
          class Foo {
            const Foo();
          }
        ''',
      });

      expect(result.widgets, isEmpty);
      expect(
        result.issues.map((i) => i.code),
        contains(IssueCode.missingAnnotationField),
      );
      expect(
        result.issues
            .firstWhere((i) => i.code == IssueCode.missingAnnotationField)
            .message,
        contains('Foo'),
      );
    });

    test('an unresolvable @ignore is reported, not treated as absent',
        () async {
      // Treating it as absent would INCLUDE an input the author excluded,
      // which is the more dangerous direction: the exclusion silently stops
      // applying and nothing says so.
      final result = await runWidgetVisitorOn({
        'lib/foo.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart'
              hide ignore;

          @RestageWidget(
            name: 'Foo',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.layout,
            description: 'A foo widget.',
          )
          class Foo {
            const Foo({this.label, @ignore this.retries = 3});
            final String? label;
            final int retries;
          }
        ''',
      });

      expect(
        result.issues.map((i) => i.code),
        contains(IssueCode.invalidWidgetConstructorInput),
      );
      final message = result.issues
          .firstWhere((i) => i.code == IssueCode.invalidWidgetConstructorInput)
          .message;
      expect(message, contains('retries'));
      expect(message.toLowerCase(), contains('resolve'));
    });

    test('a resolved @ignore excludes exactly its own input', () async {
      // Regression guard for the ordinary case: the exclusion applies, and it
      // does not disturb the sibling property.
      final result = await runWidgetVisitorOn({
        'lib/foo.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          @RestageWidget(
            name: 'Foo',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.layout,
            description: 'A foo widget.',
          )
          class Foo {
            const Foo({this.label, @ignore this.retries = 3});
            @RestageProperty(description: 'The label.')
            final String? label;
            final int retries;
          }
        ''',
      });

      expect(result.issues, isEmpty);
      expect(result.widgets, hasLength(1));
      expect(
        result.widgets.single.properties.map((p) => p.name),
        equals(['label']),
      );
    });

    test('a foreign @ignore that merely shares the name is not honoured',
        () async {
      // Identity is the defining library, not the spelling. Another package's
      // `@ignore` must not silently remove an input from our catalog.
      final result = await runWidgetVisitorOn({
        'lib/foo.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart'
              hide ignore;

          class Ignore {
            const Ignore();
          }

          const Ignore ignore = Ignore();

          @RestageWidget(
            name: 'Foo',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.layout,
            description: 'A foo widget.',
          )
          class Foo {
            const Foo({this.label, @ignore this.retries = 3});
            @RestageProperty(description: 'The label.')
            final String? label;
            @RestageProperty(description: 'The retry count.')
            final int retries;
          }
        ''',
      });

      expect(result.issues, isEmpty);
      expect(result.widgets, hasLength(1));
      expect(
        result.widgets.single.properties.map((p) => p.name),
        equals(['label', 'retries']),
      );
    });
  });
}
