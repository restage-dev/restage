import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/builder.dart';
import 'package:restage_codegen/src/user_catalog_json_builder.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// The end-to-end chain the fix restores: a Dart `@PaywallSource` referencing a
/// app-backed, non-inlineable custom widget. WITHOUT the emitted `catalog.json`
/// the paywall build tries to inline the widget and fails; once the package
/// builder emits `catalog.json`, the merged catalog resolves the widget as a
/// reference and the paywall emits a blob.
void main() {
  // An imperative custom widget — its `build` uses a CustomPainter, which
  // is not blob-expressible — plus a Dart paywall that references it. Scalar
  // props only (String / int).
  const source = '''
import 'package:flutter/material.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

class PaywallSource {
  const PaywallSource({required this.id, this.slot});
  final String id;
  final String? slot;
}

@RestageLibrary(
  library: WidgetLibrary.custom('acme.ds'),
  capabilityVersion: 1,
)
const acmeLibrary = 0;

@RestageWidget(name: 'StreakBadge',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.decoration, description: 'streak')
class StreakBadge extends StatelessWidget {
  const StreakBadge({super.key, this.label, this.count});
  @RestageProperty(description: 'l') final String? label;
  @RestageProperty(description: 'c') final int? count;
  // A CustomPainter is imperative and not blob-expressible.
  @override
  Widget build(BuildContext context) => CustomPaint(painter: StreakPainter());
}

class StreakPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {}
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

@PaywallSource(id: 'streak')
class Streak extends StatelessWidget {
  const Streak({super.key});
  @override
  Widget build(BuildContext context) =>
      const StreakBadge(label: "Day", count: 9);
}
''';

  const paywallAsset = 'apps_examples|lib/paywalls/streak.dart';
  const catalogAsset = 'apps_examples|lib/src/widget_catalog/catalog.json';

  test(
      'WITHOUT catalog.json the paywall build cannot resolve the app-backed '
      'widget '
      '(the bug: inline attempt fails, no blob)', () async {
    final rw = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
      includeFlutter: true,
    );
    rw.testing.writeString(AssetId.parse(paywallAsset), source);

    final logs = <String>[];
    await testBuilder(
      restageCodegenBuilder(BuilderOptions.empty),
      {paywallAsset: source},
      rootPackage: 'apps_examples',
      readerWriter: rw,
      outputs: const {},
      onLog: (record) => logs.add(record.message),
    );
    expect(logs.join('\n'), contains('[customWidgetImperative]'));
  });

  test(
      'WITH the package-emitted catalog.json the paywall REFERENCES the '
      'app-backed '
      'widget and emits a blob + capability manifest', () async {
    final rw = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
      includeFlutter: true,
    );
    rw.testing.writeString(AssetId.parse(paywallAsset), source);

    // 1) The package builder emits catalog.json from the @RestageWidget.
    String? catalogJson;
    await testBuilder(
      const UserCatalogJsonBuilder(BuilderOptions.empty),
      {paywallAsset: source},
      rootPackage: 'apps_examples',
      readerWriter: rw,
      outputs: {
        catalogAsset: decodedMatches(predicate<String>((s) {
          catalogJson = s;
          return true;
        })),
      },
      onLog: (_) {},
    );
    expect(catalogJson, isNotNull);

    // 2) The paywall build resolves StreakBadge against the merged catalog
    //    (catalog.json seeded as a SOURCE in a fresh reader) and emits a
    //    reference blob naming the required customer library.
    final rw2 = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
      includeFlutter: true,
    );
    rw2.testing.writeString(AssetId.parse(paywallAsset), source);
    rw2.testing.writeString(AssetId.parse(catalogAsset), catalogJson!);
    await testBuilder(
      restageCodegenBuilder(BuilderOptions.empty),
      {paywallAsset: source},
      rootPackage: 'apps_examples',
      readerWriter: rw2,
      outputs: {
        'apps_examples|assets/paywalls/streak.rfwtxt': decodedMatches(
          allOf(contains('import acme.ds;'), contains('StreakBadge')),
        ),
        'apps_examples|assets/paywalls/streak.rfw': isNotEmpty,
        'apps_examples|assets/paywalls/streak.capability.json':
            decodedMatches(contains('acme.ds')),
        'apps_examples|assets/paywalls/screens/paywall_streak.rfw': anything,
        'apps_examples|assets/paywalls/screens/paywall_streak.capability.json':
            anything,
      },
    );
  });
}
