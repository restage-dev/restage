import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:logging/logging.dart';
import 'package:restage_codegen/builder.dart';
import 'package:restage_codegen/src/dart_import_planner.dart';
import 'package:test/test.dart';

import 'design_package_sources.dart';
import 'helpers.dart';

/// Compatibility with the design-system packages that carry copies of the
/// framework's material / cupertino layers.
///
/// A class copied into one of those packages is a DIFFERENT type from the
/// framework class of the same name — same name, same file basename, different
/// defining library. Every join in this toolchain keys on the defining library,
/// so each of these tests pins one join that silently produced the wrong answer
/// when a surface was authored against a design package.
void main() {
  group('framework identity canonicalisation', () {
    test('maps a design-package implementation library to the framework one',
        () {
      expect(
        canonicalFrameworkLibraryUri('package:material_ui/src/card.dart'),
        'package:flutter/src/material/card.dart',
      );
      expect(
        canonicalFrameworkLibraryUri('package:cupertino_ui/src/button.dart'),
        'package:flutter/src/cupertino/button.dart',
      );
    });

    test('leaves framework, SDK and customer libraries untouched', () {
      for (final uri in const [
        'package:flutter/src/material/card.dart',
        'package:flutter/widgets.dart',
        'dart:ui',
        'package:acme_app/widgets/card.dart',
        // The design packages' own barrels are not implementation libraries
        // and name no framework class, so they are not remapped.
        'package:material_ui/material_ui.dart',
      ]) {
        expect(canonicalFrameworkLibraryUri(uri), uri, reason: uri);
      }
    });
  });

  group('generated-code imports', () {
    test('routes a design-package implementation library through its barrel',
        () {
      expect(
        publicDartImportUri('package:material_ui/src/snack_bar_theme.dart'),
        'package:material_ui/material_ui.dart',
      );
      expect(
        publicDartImportUri('package:cupertino_ui/src/button.dart'),
        'package:cupertino_ui/cupertino_ui.dart',
      );
    });

    test('still routes framework implementation libraries to their barrel', () {
      expect(
        publicDartImportUri('package:flutter/src/material/card.dart'),
        'package:flutter/material.dart',
      );
    });

    test('a design package still needs a prefixed import', () {
      // Distinct from framework identity: generated code must IMPORT these
      // packages, so they remain application libraries for import planning even
      // though the classes they declare are framework classes.
      expect(
        isApplicationDartLibrary('package:material_ui/src/card.dart'),
        isTrue,
      );
      expect(
        isApplicationDartLibrary('package:flutter/src/material/card.dart'),
        isFalse,
      );
    });
  });

  group('surface authored against a design package', () {
    test('binds its widgets to the catalog by identity, not by name', () async {
      const source = '''
        import 'package:material_ui/material_ui.dart';
        import 'package:restage/restage.dart';

        @Paywall()
        class DesignPaywall extends StatelessWidget {
          const DesignPaywall({super.key});

          @override
          Widget build(BuildContext context) => Scaffold(
                backgroundColor: const Color(0xFF101010),
                body: Column(
                  children: <Widget>[
                    const Text('Go Premium'),
                    Card(child: const Text('Plan')),
                  ],
                ),
              );
        }
      ''';

      await _expectPaywallRfwText(
        source,
        path: 'lib/paywalls/design.dart',
        matcher: allOf(
          contains('Scaffold('),
          contains('Card('),
          contains('Text(text: "Go Premium")'),
        ),
      );
    });

    test('binds a named constructor to its dedicated catalog entry', () async {
      // The discriminator for identity canonicalisation. The bare-name lookup
      // can still reach the BASE entry for `Card` / `FilledButton`, so an
      // unnamed construction looks fine either way; a named constructor cannot
      // be reached by name at all, and without canonicalisation the build fails
      // for dropping the constructor's implied semantics.
      const source = '''
        import 'package:material_ui/material_ui.dart';
        import 'package:restage/restage.dart';

        @Paywall()
        class VariantPaywall extends StatelessWidget {
          const VariantPaywall({super.key});

          @override
          Widget build(BuildContext context) => Scaffold(
                body: Column(
                  children: <Widget>[
                    const Card.filled(child: Text('Filled')),
                    FilledButton.tonal(
                      onPressed: paywallEvent('go'),
                      child: const Text('Tonal'),
                    ),
                  ],
                ),
              );
        }
      ''';

      await _expectPaywallRfwText(
        source,
        path: 'lib/paywalls/variant.dart',
        matcher: allOf(
          contains('CardFilled('),
          contains('FilledButtonTonal('),
        ),
      );
    });

    test('reads the theme through the framework channel', () async {
      // `Theme.of` is element-gated: before the design packages were accepted
      // as framework libraries this failed closed as an unsupported expression.
      const source = '''
        import 'package:material_ui/material_ui.dart';
        import 'package:restage/restage.dart';

        @Paywall()
        class ThemedPaywall extends StatelessWidget {
          const ThemedPaywall({super.key});

          @override
          Widget build(BuildContext context) => Scaffold(
                backgroundColor: Theme.of(context).colorScheme.surface,
                body: const Text('Themed'),
              );
        }
      ''';

      await _expectPaywallRfwText(
        source,
        path: 'lib/paywalls/themed.dart',
        matcher: contains('Scaffold('),
      );
    });
  });
}

/// Builds [source] as a paywall and asserts the emitted RFW text matches
/// [matcher].
///
/// The build must also be diagnostic-free: a surface that binds correctly but
/// warns is not the behaviour under test.
Future<void> _expectPaywallRfwText(
  String source, {
  required String path,
  required Matcher matcher,
}) async {
  final diagnostics = await _buildPaywall(
    {path: source},
    stem: path.split('/').last.replaceAll('.dart', ''),
    rfwTextMatcher: matcher,
  );
  expect(diagnostics, isEmpty, reason: 'the surface must build clean');
}

/// Builds [sources] through the real paywall builder, asserting the emitted
/// RFW text for [stem] against [rfwTextMatcher]. Returns the diagnostics.
Future<List<String>> _buildPaywall(
  Map<String, String> sources, {
  required String stem,
  required Matcher rfwTextMatcher,
}) =>
    _runPaywallBuilder(
      sources,
      outputs: {
        'apps_examples|assets/paywalls/$stem.rfwtxt':
            decodedMatches(rfwTextMatcher),
        'apps_examples|assets/paywalls/$stem.rfw': anything,
        'apps_examples|assets/paywalls/$stem.capability.json': anything,
        'apps_examples|assets/paywalls/screens/paywall_$stem.rfw': anything,
        'apps_examples|assets/paywalls/screens/paywall_$stem.capability.json':
            anything,
      },
    );

Future<List<String>> _runPaywallBuilder(
  Map<String, String> sources, {
  required Map<String, Object>? outputs,
}) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
    includeDesignPackages: importsDesignPackages(sources.values),
  );
  for (final entry in sources.entries) {
    readerWriter.testing
        .writeString(AssetId('apps_examples', entry.key), entry.value);
  }

  final diagnostics = <String>[];
  await testBuilder(
    restageCodegenBuilder(BuilderOptions.empty),
    {
      for (final entry in sources.entries)
        'apps_examples|${entry.key}': entry.value,
    },
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    outputs: outputs,
    onLog: (record) {
      // build_runner's own progress records arrive on the same channel; only
      // the builder's diagnostics are of interest here.
      if (record.level < Level.WARNING) return;
      diagnostics.add(record.message);
    },
  );
  return diagnostics;
}
