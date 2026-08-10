import 'dart:convert';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/native_screen_source_index.dart';
import 'package:restage_codegen/src/widget_visitor.dart';
import 'package:restage_codegen/src/widgetbook/widgetbook_catalog_source_index.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  test(
    'aggregates customer widgets, structured facts, and usage',
    () async {
      final sources = <String, String>{
        'apps_examples|lib/data/badge_data.dart': _badgeData,
        'apps_examples|lib/widgets/badge.dart': _badgeWidget,
        'apps_examples|lib/widgets/label.dart': _labelWidget,
      };
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      for (final entry in sources.entries) {
        final parts = entry.key.split('|');
        readerWriter.testing.writeString(
          AssetId(parts.first, parts.last),
          entry.value,
        );
      }

      await testBuilder(
        const _IndexProbeBuilder(),
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|lib/widgetbook_index.txt': decodedMatches(
            allOf(
              contains('widgets=Badge,Label'),
              contains('usage=Badge:Use Badge for a compact customer status.'),
              contains('|Label:A customer label.'),
              contains('structured=BadgeData'),
              contains('#Badge.data=>'),
            ),
          ),
        },
      );
    },
  );

  test('retains automatic-story exclusions without RFW filtering', () async {
    const source = '''
      import 'package:flutter/widgets.dart';
      import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

      const library = WidgetLibrary.custom('fixture.widgets');

      @RestageWidget(
        name: 'GenericCard',
        library: library,
        category: WidgetCategory.decoration,
        description: 'Generic card.',
      )
      class GenericCard<T> extends StatelessWidget {
        const GenericCard({required this.label});
        @RestageProperty(description: 'Label.')
        final String label;
        @override
        Widget build(BuildContext context) => Text(label);
      }
    ''';
    final sources = {'apps_examples|lib/widgets.dart': source};
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    readerWriter.testing.writeString(
      AssetId('apps_examples', 'lib/widgets.dart'),
      source,
    );

    await testBuilder(
      const _IndexProbeBuilder(),
      sources,
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      outputs: {
        'apps_examples|lib/widgetbook_index.txt': decodedMatches(
          contains('GenericCard=generic @RestageWidget classes'),
        ),
      },
    );
  });

  test('rejects unsupported structured leaves with an owning property path',
      () async {
    const source = '''
      import 'package:flutter/widgets.dart';
      import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

      class CustomerData {
        const CustomerData({required this.locale});
        @RestageProperty(description: 'Customer locale.')
        final Locale locale;
      }

      @RestageWidget(
        name: 'CustomerCard',
        library: WidgetLibrary.custom('fixture.widgets'),
        category: WidgetCategory.decoration,
        description: 'Customer card.',
      )
      class CustomerCard extends StatelessWidget {
        const CustomerCard({required this.data});
        @RestageProperty(description: 'Customer data.')
        final CustomerData data;
        @override
        Widget build(BuildContext context) => const SizedBox();
      }
    ''';
    final sources = {'apps_examples|lib/customer_card.dart': source};
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    readerWriter.testing.writeString(
      AssetId('apps_examples', 'lib/customer_card.dart'),
      source,
    );

    await testBuilder(
      const _IndexProbeBuilder(),
      sources,
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      outputs: {
        'apps_examples|lib/widgetbook_index.txt': decodedMatches(
          allOf(
            contains("property 'data' targets 'CustomerData'"),
            contains('type denylisted: Locale on CustomerData.locale'),
          ),
        ),
      },
    );
  });

  test('rejects direct scalar lists at their constructor-property path',
      () async {
    const source = '''
      import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

      /// Customer tags.
      @RestageWidget(
        name: 'CustomerTags',
        library: WidgetLibrary.custom('fixture.widgets'),
        category: WidgetCategory.decoration,
      )
      class CustomerTags {
        const CustomerTags({required this.tags});

        /// Tags shown by the customer widget.
        final List<String> tags;
      }
    ''';
    final result = await runWidgetVisitorOn(
      {'lib/customer_tags.dart': source},
      target: WidgetVisitorTarget.widgetbook,
    );

    final issue = result.issues.singleWhere(
      (candidate) => candidate.code == IssueCode.unsupportedPropertyType,
    );
    expect(issue.location, 'lib/customer_tags.dart#CustomerTags.tags');
    expect(issue.message, contains('automatic Widgetbook stories'));
  });

  test('source properties may share the metadata sidebar labels', () async {
    const source = r'''
      import 'package:flutter/widgets.dart';
      import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

      @RestageWidget(
        name: 'CustomerCard',
        library: WidgetLibrary.custom('fixture.widgets'),
        category: WidgetCategory.decoration,
        description: 'Customer card.',
      )
      class CustomerCard extends StatelessWidget {
        const CustomerCard({required this.description, required this.usage});
        @RestageProperty(description: 'Visible description text.')
        final String description;
        @RestageProperty(description: 'Visible usage text.')
        final String usage;
        @override
        Widget build(BuildContext context) => Text('$description|$usage');
      }
    ''';
    final sources = {'apps_examples|lib/customer_card.dart': source};
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    readerWriter.testing.writeString(
      AssetId('apps_examples', 'lib/customer_card.dart'),
      source,
    );

    await testBuilder(
      const _IndexProbeBuilder(),
      sources,
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      outputs: {
        'apps_examples|lib/widgetbook_index.txt': decodedMatches(
          allOf(
            contains('widgets=CustomerCard'),
            isNot(contains('metadata sidebar fields')),
          ),
        ),
      },
    );
  });

  test('A2UI-only evaluation failures do not gate Widgetbook indexing',
      () async {
    const source = '''
      import 'package:flutter/widgets.dart';
      import 'package:rfw_catalog_schema/a2ui.dart' as a2ui;
      import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

      final runtimeEnabled = DateTime.now().isUtc;

      @a2ui.Config.enabled(runtimeEnabled)
      @RestageWidget(
        name: 'IsolatedCard',
        library: WidgetLibrary.custom('fixture.widgets'),
        description: 'A target-isolation probe.',
      )
      class IsolatedCard extends StatelessWidget {
        const IsolatedCard({super.key, this.label = ''});

        /// Visible label.
        final String label;

        @override
        Widget build(BuildContext context) => Text(label);
      }
    ''';
    final sources = {'apps_examples|lib/isolated_card.dart': source};
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    readerWriter.testing.writeString(
      AssetId('apps_examples', 'lib/isolated_card.dart'),
      source,
    );

    await testBuilder(
      const _IndexProbeBuilder(),
      sources,
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      outputs: {
        'apps_examples|lib/widgetbook_index.txt': decodedMatches(
          allOf(
            contains('widgets=IsolatedCard'),
            contains('usage=IsolatedCard:A target-isolation probe.'),
          ),
        ),
      },
    );
  });

  test('does not guess Widgetbook collisions without namespace evidence',
      () async {
    const source = '''
      import 'package:flutter/widgets.dart';
      import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

      @RestageWidget(
        name: 'Meta',
        library: WidgetLibrary.custom('fixture.widgets'),
        category: WidgetCategory.decoration,
        description: 'A customer widget with a reserved source name.',
      )
      class Meta extends StatelessWidget {
        const Meta({required this.label});
        @RestageProperty(description: 'Visible label.')
        final String label;
        @override
        Widget build(BuildContext context) => Text(label);
      }
    ''';
    final sources = {'apps_examples|lib/meta.dart': source};
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    readerWriter.testing.writeString(
      AssetId('apps_examples', 'lib/meta.dart'),
      source,
    );

    await testBuilder(
      const _IndexProbeBuilder(),
      sources,
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      outputs: {
        'apps_examples|lib/widgetbook_index.txt': decodedMatches(
          allOf(
            contains('widgets=Meta'),
            isNot(contains('Meta=source class name')),
          ),
        ),
      },
    );
  });

  test('Widgetbook keeps same-name widgets and screens on distinct paths',
      () async {
    const source = '''
      import 'package:flutter/widgets.dart';
      import 'package:restage/restage.dart';
      import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

      part 'shared.rsscreen.g.dart';

      @RestageWidget(
        name: 'shared',
        library: WidgetLibrary.custom('fixture.widgets'),
        category: WidgetCategory.decoration,
        description: 'A customer widget under its ordinary path.',
      )
      class SharedCard extends StatelessWidget {
        const SharedCard({super.key});
        @override
        Widget build(BuildContext context) => const SizedBox.shrink();
      }

      /// A native screen under the reserved Screens path.
      @ScreenSource(id: 'shared')
      class SharedScreen extends StatelessWidget {
        const SharedScreen({super.key});
        @override
        Widget build(BuildContext context) => const SizedBox.shrink();
      }
    ''';
    const pubspec = '''
name: apps_examples
dependencies:
  flutter: any
  restage: any
  rfw_catalog_schema: any
''';
    final sources = <String, String>{
      'apps_examples|lib/onboarding/screens/shared.dart': source,
      'apps_examples|pubspec.yaml': pubspec,
    };
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );

    await runWithNativeScreenPackageGraphForTesting(
      packageGraphSource: _screenSourcePackageGraph,
      body: () => testBuilder(
        const _IndexProbeBuilder(),
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|lib/widgetbook_index.txt': decodedMatches(
            allOf(
              contains('widgets=shared'),
              contains('screens=shared'),
            ),
          ),
        },
      ),
    );
  });

  test('ScreenSource passes through the Widgetbook capability wall', () async {
    const source = '''
      import 'package:flutter/widgets.dart';
      import 'package:restage/restage.dart';

      part 'unsupported_screen.rsscreen.g.dart';

      class ScreenData {
        const ScreenData({required this.decoration});

        /// Text decoration is catalogued but not reconstructed by Widgetbook.
        final TextDecoration decoration;
      }

      /// A screen with structured state outside Widgetbook's vocabulary.
      @ScreenSource(id: 'unsupported_screen')
      class UnsupportedScreen extends StatelessWidget {
        const UnsupportedScreen({super.key, required this.data});

        /// Structured screen state.
        final ScreenData data;

        @override
        Widget build(BuildContext context) => const SizedBox.shrink();
      }
    ''';
    const pubspec = '''
name: apps_examples
dependencies:
  flutter: any
  restage: any
''';
    final sources = <String, String>{
      'apps_examples|lib/onboarding/screens/unsupported_screen.dart': source,
      'apps_examples|pubspec.yaml': pubspec,
    };
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );

    await runWithNativeScreenPackageGraphForTesting(
      packageGraphSource: _screenSourcePackageGraph,
      body: () => testBuilder(
        const _IndexProbeBuilder(),
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|lib/widgetbook_index.txt': decodedMatches(
            allOf(
              contains('screens=unsupported_screen'),
              contains('UnsupportedScreen='),
              contains('unsupported_screen.data.decoration'),
              contains(
                'unsupported Widgetbook structured field type textDecoration',
              ),
            ),
          ),
        },
      ),
    );
  });

  test('ignores unrelated annotations named RestageWidget', () async {
    const source = '''
      class RestageWidget {
        const RestageWidget();
      }

      @RestageWidget()
      class NotACatalogWidget {}
    ''';
    final sources = {'apps_examples|lib/fake.dart': source};
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    readerWriter.testing.writeString(
      AssetId('apps_examples', 'lib/fake.dart'),
      source,
    );

    await testBuilder(
      const _IndexProbeBuilder(),
      sources,
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      outputs: {
        'apps_examples|lib/widgetbook_index.txt': decodedMatches(
          startsWith('widgets=\n'),
        ),
      },
    );
  });
}

const _screenSourcePackageGraph = '''
{"roots":["apps_examples"],"packages":[{"name":"apps_examples","version":"0.0.0","dependencies":["flutter","restage","rfw_catalog_schema"],"devDependencies":[]}]}
''';

final class _IndexProbeBuilder implements Builder {
  const _IndexProbeBuilder();

  @override
  Map<String, List<String>> get buildExtensions => const {
        r'$lib$': ['widgetbook_index.txt'],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    final index = await loadWidgetbookCatalogSourceIndex(buildStep);
    final out = StringBuffer()
      ..writeln(
        'widgets=${index.widgets.map((widget) => widget.entry.name).join(',')}',
      )
      ..writeln(
        'usage=${index.widgets.map(
              (widget) => '${widget.entry.name}:${widget.usage}',
            ).join('|')}',
      )
      ..writeln(
        'screens=${index.nativeScreens.map(
              (screen) => screen.entry.name,
            ).join(',')}',
      )
      ..writeln(
        'structured=${index.structuredTypes.map(
              (entry) => entry.name,
            ).join(',')}',
      );
    for (final entry in index.slotTargets.entries) {
      out.writeln('${entry.key}=>${entry.value}');
    }
    for (final entry in index.unrenderableByWidget.entries) {
      out.writeln('${entry.key.split('#').last}=${entry.value}');
    }
    await buildStep.writeAsString(
      AssetId(buildStep.inputId.package, 'lib/widgetbook_index.txt'),
      const LineSplitter().convert(out.toString()).join('\n'),
    );
  }
}

const _badgeData = '''
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  class BadgeData {
    const BadgeData({required this.label, required this.score});
    @RestageProperty(description: 'Badge label.')
    final String label;
    @RestageProperty(description: 'Badge score.')
    final int score;
  }
''';

const _badgeWidget = '''
  import 'package:flutter/widgets.dart';
  import 'package:rfw_catalog_schema/a2ui.dart' as a2ui;
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
  import '../data/badge_data.dart';

  @a2ui.Config.usage('Use Badge for a compact customer status.')
  @RestageWidget(
    name: 'Badge',
    library: WidgetLibrary.custom('fixture.widgets'),
    category: WidgetCategory.decoration,
    description: 'A customer badge.',
  )
  class Badge extends StatelessWidget {
    const Badge({required this.data});
    @RestageProperty(description: 'Badge data.')
    final BadgeData data;
    @override
    Widget build(BuildContext context) => Text(data.label);
  }
''';

const _labelWidget = '''
  import 'package:flutter/widgets.dart';
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  @RestageWidget(
    name: 'Label',
    library: WidgetLibrary.custom('fixture.widgets'),
    category: WidgetCategory.decoration,
    description: 'A customer label.',
  )
  class Label extends StatelessWidget {
    const Label({required this.text});
    @RestageProperty(description: 'Visible text.')
    final String text;
    @override
    Widget build(BuildContext context) => Text(text);
  }
''';
