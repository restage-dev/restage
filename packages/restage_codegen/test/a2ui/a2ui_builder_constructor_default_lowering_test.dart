import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/a2ui/user_a2ui_catalog_builder.dart';
import 'package:test/test.dart';

import '../helpers.dart';

Future<(bool succeeded, String dart)> _runBuilder(
  Map<String, String> sources,
) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'restage_codegen',
    includeFlutter: true,
  );
  for (final entry in sources.entries) {
    readerWriter.testing.writeString(
      AssetId('apps_examples', entry.key),
      entry.value,
    );
  }
  final result = await testBuilder(
    UserA2uiCatalogBuilder(BuilderOptions.empty),
    {
      for (final entry in sources.entries)
        'apps_examples|${entry.key}': entry.value,
    },
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  final dart = result.succeeded
      ? String.fromCharCodes(
          result.readerWriter.testing.readBytes(
            AssetId(
              'apps_examples',
              'lib/generated/restage_a2ui_catalog.g.dart',
            ),
          ),
        )
      : '';
  return (result.succeeded, dart);
}

const _libraryDeclaration = '''
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
  @RestageLibrary(
    library: WidgetLibrary.custom('acme.widgets'),
    capabilityVersion: 1,
  )
  const restageLibrary = 0;
''';

void main() {
  test('production builder preserves nullable children null and authored lists',
      () async {
    const source = '''
      import 'package:flutter/widgets.dart';
      import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

      @RestageWidget(
        name: 'NullableChildrenProbe',
        library: WidgetLibrary.custom('acme.widgets'),
        category: WidgetCategory.layout,
        description: 'A nullable children probe.',
      )
      class NullableChildrenProbe extends StatelessWidget {
        const NullableChildrenProbe({this.children});

        /// Optional child widgets.
        final List<Widget>? children;

        @override
        Widget build(BuildContext context) => Column(
          children: children ?? const <Widget>[],
        );
      }

      @RestageWidget(
        name: 'NullableDefaultChildrenProbe',
        library: WidgetLibrary.custom('acme.widgets'),
        category: WidgetCategory.layout,
        description: 'A nullable default children probe.',
      )
      class NullableDefaultChildrenProbe extends StatelessWidget {
        const NullableDefaultChildrenProbe({
          this.children = const <Widget>[SizedBox.shrink()],
        });

        /// Optional child widgets with a non-null default.
        final List<Widget>? children;

        @override
        Widget build(BuildContext context) => Column(
          children: children ?? const <Widget>[],
        );
      }

      @RestageWidget(
        name: 'NonNullableDefaultChildrenProbe',
        library: WidgetLibrary.custom('acme.widgets'),
        category: WidgetCategory.layout,
        description: 'A non-nullable default children probe.',
      )
      class NonNullableDefaultChildrenProbe extends StatelessWidget {
        const NonNullableDefaultChildrenProbe({
          this.children = const <Widget>[SizedBox.shrink()],
        });

        /// Child widgets with a non-null default.
        final List<Widget> children;

        @override
        Widget build(BuildContext context) => Column(children: children);
      }
    ''';
    final sources = {
      'lib/lib.dart': _libraryDeclaration,
      'lib/nullable_children_probe.dart': source,
    };
    final (succeeded, dart) = await _runBuilder(sources);

    expect(succeeded, isTrue);
    final nullable = _catalogItemSource(dart, 'NullableChildrenProbe');
    final nullableCompact = nullable.replaceAll(RegExp(r'\s+'), ' ');
    expect(
      nullableCompact,
      contains(
        "children: props.containsKey('children') ? "
        "(props['children'] == null ? null : "
        "_restageA2uiBuildChildren(itemContext, props['children'])) : null,",
      ),
      reason: 'missing and explicit-null inputs must remain null, while empty '
          'and non-empty authored lists must still call the children builder',
    );
    expect(
      RegExp(r'_restageA2uiBuildChildren\(').allMatches(nullable),
      hasLength(1),
      reason: 'only the present non-null branch may build a list; the absent '
          'branch must not manufacture an empty list',
    );
    expect(
      nullable,
      isNot(contains('children: const <Widget>[]')),
      reason: 'an empty-list literal must not stand in for constructor null',
    );

    final nullableDefault =
        _catalogItemSource(dart, 'NullableDefaultChildrenProbe');
    expect(
      nullableDefault.replaceAll(RegExp(r'\s+'), ' '),
      allOf(
        contains("props.containsKey('children') ?"),
        contains("props['children'] == null ? null :"),
        contains(': const <Widget>[const SizedBox.shrink()],'),
      ),
      reason: 'absence must select the exact non-null default while explicit '
          'null remains null and authored lists remain lists',
    );

    final nonNullableDefault =
        _catalogItemSource(dart, 'NonNullableDefaultChildrenProbe');
    expect(
      nonNullableDefault.replaceAll(RegExp(r'\s+'), ' '),
      allOf(
        contains("props.containsKey('children') ?"),
        contains(': const <Widget>[const SizedBox.shrink()],'),
      ),
      reason: 'the non-nullable constructor-default control must retain its '
          'existing omission behavior',
    );
    await _expectGeneratedCompiles(sources, dart);
  });

  test('production builder lowers reference, invocation, and list defaults',
      () async {
    const source = '''
      import 'package:flutter/widgets.dart';
      import 'package:apps_examples/defaults.dart';
      import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

      class Tokens {
        static const retries = 3;
        static const primaryLabel = 'first';
        static const sharedLabels = <String>[primaryLabel, 'second'];
      }

      const defaultTimeout = 5;

      class Tone {
        const Tone({required this.level});

        final int level;
      }

      @RestageWidget(
        name: 'DefaultProbe',
        library: WidgetLibrary.custom('acme.widgets'),
        category: WidgetCategory.decoration,
        description: 'a constructor-default probe',
      )
      class DefaultProbe {
        const DefaultProbe({
          this.retries = Tokens.retries,
          this.timeout = defaultTimeout,
          this.color = const Color(0xFF123456),
          this.labels = const <String>[Tokens.primaryLabel, 'second'],
          this.sharedLabels = Tokens.sharedLabels,
          this.maybeLabels = Tokens.sharedLabels,
          this.tone = const Tone(level: Defaults.level),
          this.scores = const <String, int>{'first': 1},
          this.summary = (count: 1, label: 'first'),
          this.child = const SizedBox.shrink(),
          this.children = const <Widget>[SizedBox.shrink()],
          this.hostState,
        });

        /// Retry count.
        final int retries;
        /// Timeout count.
        final int timeout;
        /// Brand color.
        final Color color;
        /// Visible labels.
        final List<String> labels;
        /// Shared visible labels.
        final List<String> sharedLabels;
        /// Nullable shared visible labels.
        final List<String>? maybeLabels;
        /// Display tone.
        final Tone tone;
        /// Scores by label.
        final Map<String, int> scores;
        /// Summary values.
        final ({int count, String label}) summary;
        /// Default child.
        final Widget child;
        /// Default children.
        final List<Widget> children;
        /// State supplied only by the host application.
        final Object? hostState;
      }
    ''';

    final (succeeded, dart) = await _runBuilder({
      'lib/lib.dart': _libraryDeclaration,
      'lib/defaults.dart': '''
        class Defaults {
          static const level = 2;
        }
      ''',
      'lib/default_probe.dart': source,
    });

    expect(succeeded, isTrue);
    expect(dart, contains('Tokens.retries'));
    expect(dart, contains('defaultTimeout'));
    expect(dart, contains('Color.new(4279383126)'));
    expect(dart, contains("const <String>[p1.Tokens.primaryLabel, 'second']"));
    expect(dart, contains('p1.Tokens.sharedLabels'));
    expect(
      dart.replaceAll(RegExp(r'\s+'), ''),
      contains(
        "props.containsKey('maybeLabels')?"
        "(props['maybeLabels']==null?null:"
        '((maybeLabelsisList?maybeLabels.cast<Object?>():null)??'
        'p1.Tokens.sharedLabels)):p1.Tokens.sharedLabels',
      ),
    );
    expect(dart, contains('Tone.new(level:'));
    expect(dart, contains('Defaults.level'));
    expect(dart, contains('const SizedBox.shrink()'));
    expect(dart, contains('const <Widget>[const SizedBox.shrink()]'));
    expect(dart, contains(r'$RestageExclusions'));
    expect(dart, contains('"property": "hostState"'));
    expect(dart, contains('"property": "scores"'));
    expect(dart, contains('"property": "summary"'));
    expect(dart, contains('"target": "a2ui"'));
    expect(dart, isNot(contains('RestageRfwConstructorPresence')));
  });
}

String _catalogItemSource(String dart, String widgetName) {
  final marker = "name: '$widgetName',";
  final markerStart = dart.indexOf(marker);
  expect(markerStart, isNonNegative, reason: '$widgetName was not emitted');
  final start = dart.lastIndexOf('    CatalogItem(', markerStart);
  expect(start, isNonNegative, reason: '$widgetName item start was not found');
  final next = dart.indexOf('    CatalogItem(', markerStart + marker.length);
  final end = next < 0 ? dart.indexOf('  ];', markerStart) : next;
  expect(end, isNonNegative, reason: '$widgetName item end was not found');
  return dart.substring(start, end);
}

Future<void> _expectGeneratedCompiles(
  Map<String, String> sources,
  String generated,
) async {
  const generatedId = 'apps_examples|lib/generated/restage_a2ui_catalog.g.dart';
  await resolveSources(
    {
      for (final entry in sources.entries)
        'apps_examples|${entry.key}': entry.value,
      generatedId: generated,
    },
    (resolver) async {
      final library = await resolver.libraryFor(AssetId.parse(generatedId));
      final resolved =
          await library.session.getResolvedLibraryByElement(library);
      if (resolved is! ResolvedLibraryResult) {
        throw StateError('Generated A2UI catalog did not resolve.');
      }
      final errors = [
        for (final unit in resolved.units)
          for (final diagnostic in unit.diagnostics)
            if (diagnostic.severity == Severity.error)
              _diagnosticText(diagnostic),
      ];
      expect(
        errors,
        isEmpty,
        reason: 'generated A2UI catalog must compile without errors:\n'
            '$generated',
      );
    },
    resolverFor: generatedId,
    rootPackage: 'apps_examples',
    readAllSourcesFromFilesystem: true,
  );
}

String _diagnosticText(Diagnostic diagnostic) {
  final code = diagnostic.diagnosticCode.lowerCaseName;
  final message = diagnostic.problemMessage.messageText(includeUrl: false);
  return '$code: $message';
}
