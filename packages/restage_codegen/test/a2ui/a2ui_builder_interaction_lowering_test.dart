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

Future<void> _expectGeneratedAnalyzesClean(
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
      final diagnostics = [
        for (final unit in resolved.units)
          for (final diagnostic in unit.diagnostics)
            if (diagnostic.severity == Severity.error)
              _diagnosticText(diagnostic),
      ];
      expect(
        diagnostics,
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

void _expectCustomerNameStaysExact(String generated, String name) {
  expect(generated, contains("'$name':"), reason: '$name schema key');
  expect(
    generated,
    matches(RegExp('^\\s+$name:', multiLine: true)),
    reason: '$name constructor label',
  );
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
  test(
    'multi-leaf source names remain exact while generated locals avoid every '
    'rendered bare-identifier family',
    () async {
      const source = '''
        import 'dart:core' as core;
        import 'dart:ui' as ui;

        import 'package:flutter/widgets.dart';
        import 'package:flutter/widgets.dart' as flutter;
        import 'package:rfw_catalog_schema/a2ui.dart' as a2ui;
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        enum GeneratedNameState { ready, complete }

        /// A widget whose legal source names overlap emitted Dart symbols.
        @a2ui.Config.writeBackValues({
          'onBoundStringChanged': 'BoundString',
        })
        @RestageWidget(
          name: 'GeneratedSymbolCard',
          library: WidgetLibrary.custom('acme.widgets'),
          category: WidgetCategory.input,
        )
        final class GeneratedSymbolCard extends StatelessWidget {
          const GeneratedSymbolCard({
            super.key,
            required this.data,
            required this.context,
            required this.itemContext,
            required this.restageA2uiStatus,
            required this.restageA2uiWriteBoundString,
            required this.p0,
            required this.restageA2uiCatalogId,
            required this.BoundString,
            required this.followingString,
            required this.BoundBool,
            required this.followingBool,
            required this.BoundNumber,
            required this.followingNumber,
            required this.BoundObject,
            required this.followingList,
            required this.Duration,
            required this.followingDuration,
            required this.FontWeight,
            required this.followingWeight,
            required this.Color,
            required this.followingColor,
            required this.UserActionEvent,
            required this.Map,
            required this.String,
            required this.SizedBox,
            required this.state,
            required this.ordinaryLabel,
            required this.builder,
            required this.dataContext,
            required this.containsKey,
            required this.milliseconds,
            required this.normal,
            required this.values,
            required this.onBoundStringChanged,
            required this.trigger,
            this.child = const flutter.SizedBox.shrink(),
          });

          /// Generated data-local collision.
          final core.String data;
          /// Generated bound-context collision.
          final core.String context;
          /// Generated item-context collision.
          final core.String itemContext;
          /// Generated-prefix-shaped non-collision.
          final GeneratedNameState restageA2uiStatus;
          /// Generated controlled-writer collision.
          final core.String restageA2uiWriteBoundString;
          /// Dynamic-prefix collision.
          final core.String p0;
          /// Catalog identifier collision.
          final core.String restageA2uiCatalogId;
          /// String binder collision.
          final core.String BoundString;
          /// Nested string binder witness.
          final core.String followingString;
          /// Boolean binder collision.
          final core.bool BoundBool;
          /// Nested boolean binder witness.
          final core.bool followingBool;
          /// Number binder collision.
          final core.double BoundNumber;
          /// Nested number binder witness.
          final core.double followingNumber;
          /// Object binder collision.
          final core.List<core.String> BoundObject;
          /// Nested object binder witness.
          final core.List<core.String> followingList;
          /// Core duration collision.
          final core.Duration Duration;
          /// Nested duration-constructor witness.
          final core.Duration followingDuration;
          /// Flutter font-weight collision.
          final ui.FontWeight FontWeight;
          /// Nested font-weight witness.
          final ui.FontWeight followingWeight;
          /// Flutter color collision.
          final ui.Color Color;
          /// Nested color-constructor witness.
          final ui.Color followingColor;
          /// Runtime event-class collision.
          final core.String UserActionEvent;
          /// Core map-type collision.
          final core.String Map;
          /// Core string-type collision.
          final core.String String;
          /// Flutter constructor collision from a child fallback.
          final core.String SizedBox;
          /// Customer enum value.
          final GeneratedNameState state;
          /// Non-colliding control value.
          final core.String ordinaryLabel;
          /// Named-argument-label witness.
          final core.String builder;
          /// Member-selector and named-label witness.
          final core.String dataContext;
          /// Member-selector witness.
          final core.String containsKey;
          /// Named-argument-label witness.
          final core.String milliseconds;
          /// Member-selector witness.
          final core.String normal;
          /// Member-selector witness.
          final core.String values;
          /// Controlled string callback.
          final void Function(core.String) onBoundStringChanged;
          /// Dispatch callback.
          final VoidCallback trigger;
          /// Child with a Flutter-owned constructor default.
          final Widget child;

          @override
          Widget build(BuildContext context) =>
              const flutter.SizedBox.shrink();
        }
      ''';
      const sources = <String, String>{
        'lib/lib.dart': _libraryDeclaration,
        'lib/generated_symbol_card.dart': source,
      };

      final (succeeded, generated) = await _runBuilder(sources);

      expect(succeeded, isTrue);
      for (final name in <String>[
        'data',
        'context',
        'itemContext',
        'restageA2uiWriteBoundString',
        'p0',
        'restageA2uiCatalogId',
        'BoundString',
        'BoundBool',
        'BoundNumber',
        'BoundObject',
        'Duration',
        'FontWeight',
        'Color',
        'UserActionEvent',
        'Map',
        'String',
        'SizedBox',
      ]) {
        _expectCustomerNameStaysExact(generated, name);
        expect(
          generated,
          matches(RegExp('\\b${name}_2\\b')),
          reason: '$name allocated local',
        );
      }
      for (final name in <String>[
        'restageA2uiStatus',
        'ordinaryLabel',
        'builder',
        'dataContext',
        'containsKey',
        'milliseconds',
        'normal',
        'values',
      ]) {
        _expectCustomerNameStaysExact(generated, name);
        expect(
          generated,
          isNot(matches(RegExp('\\b${name}_2\\b'))),
          reason: '$name remains an ordinary non-colliding local',
        );
      }
      expect(
        generated,
        matches(RegExp(r'state:\s*p0\.GeneratedNameState\s*\.values')),
      );
      expect(
        generated,
        matches(
          RegExp(
            r'restageA2uiStatus:\s*p0\.GeneratedNameState\s*\.values',
          ),
        ),
      );
      expect(
        generated,
        matches(RegExp(r'\.asNameMap\(\)\[\s*state\]')),
      );
      expect(
        generated,
        matches(
          RegExp(r'onBoundStringChanged:\s*restageA2uiWriteBoundString'),
        ),
      );
      expect(generated, matches(RegExp(r"name:\s*'trigger'")));
      expect(
        generated,
        matches(
          RegExp(r'child:\s*_restageA2uiBuildChild\(\s*itemContext,'),
        ),
      );
      await _expectGeneratedAnalyzesClean(sources, generated);
    },
  );

  test(
      'production builder lowers scalar, list, and enum write-back plus an '
      'arbitrary open-name dispatch', () async {
    const source = '''
      import 'package:flutter/widgets.dart';
      import 'package:rfw_catalog_schema/a2ui.dart' as a2ui;
      import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

      enum DeliveryState { queued, sent }

      @a2ui.Config.writeBackValues({
        'replaceTitle': 'title',
        'replaceTags': 'tags',
        'advanceDeliveryState': 'deliveryState',
        'clearDeliveryState': 'nullableDeliveryState',
      })
      @RestageWidget(
        name: 'DeliveryEditor',
        library: WidgetLibrary.custom('acme.widgets'),
        category: WidgetCategory.input,
        description: 'an interactive delivery editor',
      )
      class DeliveryEditor extends StatelessWidget {
        const DeliveryEditor({
          super.key,
          required this.title,
          required this.tags,
          required this.deliveryState,
          required this.nullableDeliveryState,
          required this.replaceTitle,
          required this.replaceTags,
          required this.advanceDeliveryState,
          required this.clearDeliveryState,
          required this.transmitImmediately,
        });

        /// The current title.
        final String title;
        /// The current tags.
        final List<String> tags;
        /// The current delivery state.
        final DeliveryState deliveryState;
        /// The current optional delivery state.
        final DeliveryState? nullableDeliveryState;
        /// Replaces the title.
        final void Function(String) replaceTitle;
        /// Replaces the tags.
        final void Function(List<String>) replaceTags;
        /// Advances the delivery state.
        final void Function(DeliveryState) advanceDeliveryState;
        /// Replaces or clears the optional delivery state.
        final void Function(DeliveryState?) clearDeliveryState;
        /// Transmits the delivery immediately.
        final void Function() transmitImmediately;

        @override
        Widget build(BuildContext context) => const SizedBox.shrink();
      }
    ''';

    final sources = {
      'lib/lib.dart': _libraryDeclaration,
      'lib/delivery_editor.dart': source,
    };
    final (succeeded, dart) = await _runBuilder(sources);

    expect(succeeded, isTrue);
    expect(dart, contains('replaceTitle: restageA2uiWriteTitle'));
    expect(dart, contains('replaceTags: restageA2uiWriteTags'));
    expect(dart, contains('advanceDeliveryState: (restageA2uiNext) =>'));
    expect(
      dart,
      contains(
        RegExp(
          r'restageA2uiWriteDeliveryState\(\s*restageA2uiNext\.name\)',
        ),
      ),
    );
    expect(
      dart,
      contains(
        RegExp(
          r'restageA2uiWriteNullableDeliveryState\('
          r'\s*restageA2uiNext\?\.name\)',
        ),
      ),
    );
    expect(dart, contains("name: 'transmitImmediately'"));
    await _expectGeneratedAnalyzesClean(sources, dart);
  });
}
