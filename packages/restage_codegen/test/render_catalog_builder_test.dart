import 'package:build/build.dart';
import 'package:restage_codegen/src/render_catalog_builder.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

Catalog _custom(String namespace, String name) => Catalog(
      schemaVersion: kSupportedSchemaVersion,
      generatedAt: '2026-06-19T00:00:00Z',
      libraries: {
        WidgetLibrary.custom(namespace): const LibraryInfo(version: '0.0.0'),
      },
      widgets: [
        WidgetEntry(
          wireId: WireId('w0001'),
          name: name,
          library: WidgetLibrary.custom(namespace),
          category: WidgetCategory.layout,
          description: 'A custom widget.',
          flutterType: 'package:$namespace/widget.dart#$name',
          childrenSlot: ChildrenSlot.none,
          properties: const [],
        ),
      ],
    );

void main() {
  test('writes the built-ins, the app and its dependencies with a fixed stamp',
      () async {
    const root = 'restage_codegen';
    final readerWriter =
        await readerWriterWithFilesystemSources(rootPackage: root);
    readerWriter.testing
      ..writeString(
        AssetId(root, 'pubspec.yaml'),
        'name: $root\ndependencies:\n  restage: any\n  kit: any\n',
      )
      ..writeString(AssetId('kit', 'pubspec.yaml'), 'name: kit\n')
      ..writeString(
        AssetId(root, 'lib/src/widget_catalog/catalog.json'),
        encodeCatalog(_custom('app.widgets', 'AppBadge')),
      )
      ..writeString(
        AssetId('kit', 'lib/src/widget_catalog/catalog.json'),
        encodeCatalog(_custom('kit.widgets', 'KitBadge')),
      );

    final result = await testBuilders(
      [const RenderCatalogBuilder()],
      const {},
      rootPackage: root,
      readerWriter: readerWriter,
      flattenOutput: true,
    );
    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));

    final catalog = decodeCatalog(
      result.readerWriter.testing.readString(AssetId(root, kRenderCatalogPath)),
    );
    final names = {
      for (final widget in catalog.widgets)
        '${widget.library.namespace}:${widget.name}',
    };
    expect(
      names,
      containsAll(['app.widgets:AppBadge', 'kit.widgets:KitBadge']),
    );
    expect(
      names.any((name) => name.startsWith('${WidgetLibrary.core.namespace}:')),
      isTrue,
    );
    expect(catalog.generatedAt, '1970-01-01T00:00:00Z');
  });

  test('writes nothing for a package that does not depend on the SDK',
      () async {
    const root = 'restage_codegen';
    final readerWriter =
        await readerWriterWithFilesystemSources(rootPackage: root);
    readerWriter.testing.writeString(
      AssetId(root, 'pubspec.yaml'),
      'name: $root\ndependencies:\n  kit: any\n',
    );

    final result = await testBuilders(
      [const RenderCatalogBuilder()],
      const {},
      rootPackage: root,
      readerWriter: readerWriter,
      flattenOutput: true,
    );
    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    expect(
      result.readerWriter.testing.exists(AssetId(root, kRenderCatalogPath)),
      isFalse,
    );
  });
}
