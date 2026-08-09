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
    const UserA2uiCatalogBuilder(BuilderOptions.empty),
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
            if (diagnostic.severity == Severity.error ||
                diagnostic.severity == Severity.warning)
              _diagnosticText(diagnostic),
      ];
      expect(
        diagnostics,
        isEmpty,
        reason: 'generated A2UI catalog must have no errors or warnings:\n'
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
