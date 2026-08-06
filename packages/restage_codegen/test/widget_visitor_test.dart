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
      expect(w.fires, isEmpty);
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
      final result = await runWidgetVisitorOn({
        'lib/btn.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          class Widget {}

          @RestageWidget(
            name: 'Btn',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.input,
            description: 'CTA.',
            fires: [WidgetEventName.onPressed],
            childrenSlot: ChildrenSlot.single,
          )
          class Btn {
            const Btn({required this.child, this.onPressed});
            @RestageProperty(description: 'Label', required: true)
            final Widget child;
            @RestageProperty(description: 'Tap')
            final void Function()? onPressed;
          }
        ''',
      });

      expect(result.issues, isEmpty);
      final w = result.widgets.single;
      expect(w.fires, [WidgetEventName.onPressed]);
      expect(w.childrenSlot, ChildrenSlot.single);
      expect(w.properties, hasLength(2));
      final child = w.properties.firstWhere((p) => p.name == 'child');
      expect(child.required, isTrue);
      expect(child.type, PropertyType.widget);
      final tap = w.properties.firstWhere((p) => p.name == 'onPressed');
      expect(tap.required, isFalse);
      expect(tap.type, PropertyType.event);
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
            import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

            class Widget {}
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
      expect(properties['onTap']!.required, isFalse);
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
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          class Widget {}
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

      final legacy = await runWidgetVisitorOn(sources);
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
      expect(namedTone.enumType, isNull);
      expect(namedTone.valueShape, isNull);
      expect(
        snapshot(named),
        [
          ('title', PropertyType.string, false, false),
          ('tone', PropertyType.enumValue, false, false),
          ('child', PropertyType.widget, false, false),
          ('children', PropertyType.widgetList, false, false),
          ('onTap', PropertyType.event, false, false),
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

    test('extracts deprecatedSince marker', () async {
      final result = await runWidgetVisitorOn({
        'lib/foo.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          @RestageWidget(
            name: 'Foo',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.layout,
            description: 'A foo widget.',
            deprecatedSince: '2.0.0',
          )
          class Foo { const Foo(); }
        ''',
      });
      expect(result.issues, isEmpty);
      expect(result.widgets.single.deprecatedSince, '2.0.0');
    });

    test('decodes literal defaultValue and defaultBrandToken on properties',
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
            @RestageProperty(description: 'Label.', defaultValue: 'Buy')
            final String label;
            @RestageProperty(description: 'Color.', defaultBrandToken: 'primary')
            final String? color;
            @RestageProperty(description: 'Padding.', defaultValue: 12)
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
  });
}
