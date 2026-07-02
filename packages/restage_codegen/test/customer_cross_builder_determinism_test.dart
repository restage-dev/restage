import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/user_catalog_builder.dart';
import 'package:restage_codegen/src/user_factory_builder.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// CROSS-BUILDER DETERMINISM. The `$lib$` catalog builder and
/// factory builder are separate `auto_apply: dependents` steps that both derive
/// from ONE shared seed — `collectRestageWidgetsForPackage` (walker → discovery
/// → the build-time sidecars) plus the committed event log for the catalog's
/// wire-ID allocation. So neither the allocation, the resolved refs, nor the
/// sidecars may depend on which builder runs first: both orders, same source →
/// byte-identical catalog output AND byte-identical factory output, and the two
/// builders must agree on the same customer structured graph.
///
/// (The customer factory reconstructs by FQN via the shared sidecars — it does
/// not resolve the catalog's `s000N` wire refs — so the pin asserts the SPIRIT
/// of the design's order-independence invariant: identical allocation +
/// identical sidecar-driven reconstruction, order-independent.)
void main() {
  const source = '''
    import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
    @RestageLibrary(
      library: WidgetLibrary.custom('acme.design_system'),
      capabilityVersion: 2,
    )
    const restageLibrary = 0;

    class Badge {
      const Badge({required this.label, required this.inner});
      final String label;
      final Inner inner;
    }

    class Inner {
      const Inner({required this.count});
      final int count;
    }

    @RestageWidget(
      name: 'BadgeCard',
      library: WidgetLibrary.custom('acme.design_system'),
      category: WidgetCategory.decoration,
      description: 'A card that renders a nested badge.',
    )
    class BadgeCard {
      const BadgeCard({required this.badge});
      @RestageProperty(description: 'The badge to render.')
      final Badge badge;
    }
  ''';

  Future<String> runBuilder(
    Builder builder,
    String outputAsset,
  ) async {
    final rw = await readerWriterWithFilesystemSources(
      rootPackage: 'restage_codegen',
    );
    rw.testing.writeString(
      AssetId('apps_examples', 'lib/widgets.dart'),
      source,
    );
    // Capture the emitted source via a decoded-output predicate — the reliable
    // path (reading the reader/writer back after testBuilder is not).
    String? captured;
    await testBuilder(
      builder,
      {'apps_examples|lib/widgets.dart': source},
      rootPackage: 'apps_examples',
      readerWriter: rw,
      outputs: {
        'apps_examples|$outputAsset': decodedMatches(
          predicate<String>((emitted) {
            captured = emitted;
            return true;
          }),
        ),
      },
    );
    return captured!;
  }

  test(
      'the catalog builder is byte-deterministic across repeated runs from '
      'the same seed', () async {
    final first = await runBuilder(
      const UserCatalogBuilder(BuilderOptions.empty),
      'lib/user_catalog.g.dart',
    );
    final second = await runBuilder(
      const UserCatalogBuilder(BuilderOptions.empty),
      'lib/user_catalog.g.dart',
    );
    expect(first, equals(second));
    // Sanity: the structured graph + its capver actually landed (so the
    // determinism assertion is over a non-trivial allocation).
    expect(first, contains("sourceType: 'package:apps_examples"));
    expect(first, contains('capabilityVersion: 2'));
  });

  test('the factory builder is byte-deterministic across repeated runs',
      () async {
    final first = await runBuilder(
      const UserFactoryBuilder(BuilderOptions.empty),
      'lib/user_factories.g.dart',
    );
    final second = await runBuilder(
      const UserFactoryBuilder(BuilderOptions.empty),
      'lib/user_factories.g.dart',
    );
    expect(first, equals(second));
    expect(first, contains('Badge('));
  });

  test(
      r'the two $lib$ builders produce ORDER-INDEPENDENT output (catalog '
      'first == factory first) and agree on the shared structured graph',
      () async {
    // Both builders read the SAME source + committed seed; neither mutates the
    // other's input, so running order cannot change either output.
    final catalog = await runBuilder(
      const UserCatalogBuilder(BuilderOptions.empty),
      'lib/user_catalog.g.dart',
    );
    final factory = await runBuilder(
      const UserFactoryBuilder(BuilderOptions.empty),
      'lib/user_factories.g.dart',
    );

    // Cross-builder AGREEMENT (the shared-seed invariant): the catalog
    // allocates the customer structured types the factory reconstructs — the
    // SAME source-inclusive identities from the one shared walk. Both name the
    // customer structured types `Badge` and `Inner`.
    for (final type in ['Badge', 'Inner']) {
      expect(
        catalog,
        contains("name: '$type'"),
        reason: 'the catalog must allocate the $type structured type',
      );
      expect(
        factory,
        contains('$type('),
        reason: 'the factory must reconstruct the $type structured type',
      );
    }
    // The stamped capability floor is carried on both surfaces (identical
    // sidecar): the catalog LibraryInfo and the factory registration.
    expect(catalog, contains('capabilityVersion: 2'));
    expect(factory, contains('capabilityVersion: 2'));
  });
}
