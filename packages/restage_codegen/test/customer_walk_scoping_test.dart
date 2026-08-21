// Declaration shapes the customer-widget walk must keep finding once it stops
// resolving every file in the package.
//
// Both shapes put the annotation somewhere other than "a plain library that
// also happens to be where the widget lives": a barrel names widgets declared
// elsewhere, and a `part` carries a declaration its owning library never
// mentions. A scoping mistake loses them silently — the catalog is simply
// smaller — so each has a test that fails when the file it depends on is not
// walked.

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/builder.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('customer widget walk', () {
    test('aggregates a barrel-owned widget declared in another file', () async {
      final catalog = await _catalogJson({
        'lib/widgets/card.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// A customer card.
@RestageWidget(description: 'A customer card.')
class ProductCard {
  const ProductCard();
}
''',
        'lib/product_widgets.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
export 'widgets/card.dart';

@RestageLibrary(library: WidgetLibrary.custom('acme.product'))
const restageLibrary = 0;
''',
        // Ordinary application code with no Restage declaration, present so
        // the walk has something it is entitled to skip.
        'lib/models/order.dart': '''
class Order {
  const Order(this.id);

  final String id;
}
''',
      });

      expect(catalog, contains('ProductCard'));
      expect(catalog, contains('acme.product'));
    });

    test('discovers a widget annotated with an alias declared elsewhere',
        () async {
      // The lookup seam resolves a `const` alias, so a filter that did not
      // follow one would drop this declaration in silence: the annotated file
      // spells nothing to scan for.
      final catalog = await _catalogJson({
        'lib/annotations.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

const card = RestageWidget(
  library: WidgetLibrary.custom('acme.product'),
  description: 'A customer card.',
);
''',
        'lib/widgets/card.dart': '''
import '../annotations.dart';

@card
class AliasCard {
  const AliasCard();
}
''',
      });

      expect(catalog, contains('AliasCard'));
    });

    test('discovers a widget declared inside a part of an unannotated library',
        () async {
      final catalog = await _catalogJson({
        // The owning library spells no Restage identifier of its own. Its
        // declaration lives entirely in the part.
        'lib/widgets/host.dart': '''
library acme_host;

import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

part 'card_part.dart';
''',
        'lib/widgets/card_part.dart': '''
part of 'host.dart';

/// A customer card declared in a part.
@RestageWidget(
  library: WidgetLibrary.custom('acme.product'),
  description: 'A customer card declared in a part.',
)
class PartCard {
  const PartCard();
}
''',
      });

      expect(catalog, contains('PartCard'));
    });
  });
}

/// Builds [sources] with the customer catalog JSON builder and returns the
/// emitted catalog.
Future<String> _catalogJson(Map<String, String> sources) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  final assets = {
    for (final entry in sources.entries)
      'apps_examples|${entry.key}': entry.value,
  };
  for (final entry in assets.entries) {
    readerWriter.testing.writeString(AssetId.parse(entry.key), entry.value);
  }

  final result = await testBuilder(
    userCatalogJsonBuilder(BuilderOptions.empty),
    assets,
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  expect(result.succeeded, isTrue, reason: result.errors.join('\n'));

  return readerWriter.testing.readString(
    AssetId('apps_examples', 'lib/src/widget_catalog/catalog.json'),
  );
}
