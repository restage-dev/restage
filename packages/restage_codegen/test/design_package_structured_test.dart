import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:logging/logging.dart';
import 'package:restage_codegen/builder.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Structured-type identity across the design-system packages that carry copies
/// of the framework's material / cupertino layers.
///
/// A widget join and a STRUCTURED-TYPE join are different joins. Binding the
/// widgets by canonical identity leaves the structured path untouched, and the
/// structured path is where a design-package value type is mistaken for a
/// customer data class: it is not the framework by the literal framework
/// prefix, and it does have a generative constructor with parameters, which is
/// the whole of what the customer-data-class test asks.
///
/// The consequence is not a diagnostic. A value type wrongly walked as customer
/// data yields a structured entry keyed to the design package, which no catalog
/// entry matches, and the widget is dropped at admission — silently, taking its
/// library with it when it is the only widget there.
void main() {
  group('design-package structured properties', () {
    test('a design-package value type is not walked as a customer data class',
        () async {
      final result = await runWidgetVisitorOn({
        'lib/styled_button.dart': '''
          import 'package:material_ui/material_ui.dart';
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          @RestageWidget(
            name: 'StyledButton',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.input,
            description: 'A button carrying a framework button style.',
            capabilityVersion: 1,
          )
          class StyledButton {
            const StyledButton({required this.label, this.style});

            @RestageProperty(description: 'The button label.')
            final String label;

            @RestageProperty(description: 'The framework button style.')
            final ButtonStyle? style;
          }
        ''',
      });

      final designSourced = result.structuredTypes
          .where((entry) => entry.sourceType.startsWith('package:material_ui/'))
          .map((entry) => entry.sourceType)
          .toList();
      expect(
        designSourced,
        isEmpty,
        reason: "a design package carries the framework's own value types, so "
            'one of them must never become a customer structured entry — the '
            'entry it would produce is keyed to a library no catalog entry '
            'names, and the widget carrying it is dropped at admission',
      );

      final designTargets = result.slotTargets.values
          .where((target) => target.startsWith('package:material_ui/'))
          .toList();
      expect(
        designTargets,
        isEmpty,
        reason: 'no structured slot may target a design-package identity',
      );
    });

    test('the equivalent framework-authored property behaves identically',
        () async {
      // The control. Authored against the framework directly, the same property
      // must reach the same answer, so a failure above is about the design
      // package and not about this widget shape.
      final result = await runWidgetVisitorOn({
        'lib/styled_button.dart': '''
          import 'package:flutter/material.dart';
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          @RestageWidget(
            name: 'StyledButton',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.input,
            description: 'A button carrying a framework button style.',
            capabilityVersion: 1,
          )
          class StyledButton {
            const StyledButton({required this.label, this.style});

            @RestageProperty(description: 'The button label.')
            final String label;

            @RestageProperty(description: 'The framework button style.')
            final ButtonStyle? style;
          }
        ''',
      });

      expect(
        result.structuredTypes.map((entry) => entry.sourceType).toList(),
        isEmpty,
        reason: 'the framework prefix is already excluded from customer data '
            'classes, so this produces no customer structured entry — which is '
            'exactly the answer the design-package case must reach',
      );
      expect(
        result.slotTargets.values.toList(),
        isEmpty,
        reason: 'and no structured slot target',
      );
    });
  });

  group('design-package identity drift', () {
    test('a moved symbol fails the build instead of binding by name', () async {
      // The canonicalising alias derives the framework identity from the
      // design package's FILE layout, so an upstream file move breaks the join
      // silently: the bare-name lookup still finds our entry, whose runtime
      // factory builds a different type. This pins the loud failure.
      //
      // `moved_divider.dart` stands in for that move: everything else about
      // the class is what the real package declares.
      final diagnostics = await _buildDriftedPaywall();

      expect(
        diagnostics.join('\n'),
        allOf(
          contains('moved_divider.dart'),
          contains('Binding by name would render a different type'),
        ),
        reason: 'the join must fail loud rather than reach the name fallback',
      );
    });
  });
}

/// Builds a surface that constructs a design-package class whose declaring FILE
/// no longer matches the one the catalog's identity was derived from, and
/// returns the builder's diagnostics.
///
/// `Divider` is used because the real stub package does not declare it, so the
/// only thing under test is the moved file — not a duplicate declaration.
Future<List<String>> _buildDriftedPaywall() async {
  const source = '''
    import 'package:material_ui/material_ui.dart';
    import 'package:material_ui/moved_divider.dart';
    import 'package:restage/restage.dart';

    @Paywall()
    class DriftedPaywall extends StatelessWidget {
      const DriftedPaywall({super.key});

      @override
      Widget build(BuildContext context) => Column(
            children: <Widget>[
              const Text('Go Premium'),
              const Divider(),
            ],
          );
    }
  ''';

  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
    includeDesignPackages: true,
  );
  readerWriter.testing
    ..writeString(
      AssetId('material_ui', 'lib/moved_divider.dart'),
      "export 'src/moved_divider.dart';\n",
    )
    ..writeString(
      AssetId('material_ui', 'lib/src/moved_divider.dart'),
      '''
import 'package:flutter/widgets.dart';

class Divider extends StatelessWidget {
  const Divider({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''',
    )
    ..writeString(
        AssetId('apps_examples', 'lib/paywalls/drifted.dart'), source);

  final diagnostics = <String>[];
  await testBuilder(
    restageCodegenBuilder(BuilderOptions.empty),
    {'apps_examples|lib/paywalls/drifted.dart': source},
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    onLog: (record) {
      if (record.level < Level.WARNING) return;
      diagnostics.add(record.message);
    },
  );
  return diagnostics;
}
