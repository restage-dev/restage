import 'dart:convert';

import 'package:build/build.dart';
import 'package:restage_codegen/builder.dart';
import 'package:restage_codegen/src/surface_publication/package_surface_compiler_builder.dart';
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
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

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
  Widget build(BuildContext context) => const Column(
        children: [
          StreakBadge(label: "Day", count: 9),
          StreakBadge(label: "Week", count: 12),
        ],
      );
}
''';

  const canonicalSource = '''
import 'package:apps_examples/paywalls/streak.dart';
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@Paywall(id: 'streak_offer')
class StreakOffer extends StatelessWidget {
  const StreakOffer({super.key});
  @override
  Widget build(BuildContext context) =>
      const StreakBadge(label: 'Offer', count: 21);
}
''';

  const paywallAsset = 'apps_examples|lib/paywalls/streak.dart';
  const canonicalAsset = 'apps_examples|lib/paywalls/offer.dart';
  const configurationAsset = 'apps_examples|lib/configuration.dart';
  const catalogAsset = 'apps_examples|lib/src/widget_catalog/catalog.json';
  const configurationSource = '''
import 'package:restage/restage.dart';

void configureApp() {
  Restage.configure(
    apiKey: 'rs_pk_test',
    measurementEnabled: false,
  );
}
''';
  const priceAsset = 'apps_examples|lib/paywalls/price_tag.dart';
  const priceSource = '''
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:restage/restage.dart';

@PaywallSource(id: 'price_tag')
class PriceTag extends StatelessWidget {
  const PriceTag({super.key});
  @override
  Widget build(BuildContext context) => Text(
        NumberFormat.currency(
          locale: 'en_US',
          symbol: r'\$',
          decimalDigits: 2,
        ).format(9.99),
      );
}
''';

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
        catalogAsset: decodedMatches(
          predicate<String>((s) {
            catalogJson = s;
            return true;
          }),
        ),
      },
      onLog: (_) {},
    );
    expect(catalogJson, isNotNull);

    // 2) The paywall build resolves StreakBadge against the merged catalog
    //    (catalog.json seeded as a SOURCE in a fresh reader) and emits a
    //    reference blob naming the required custom library.
    final rw2 = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
      includeFlutter: true,
    );
    rw2.testing.writeString(AssetId.parse(paywallAsset), source);
    rw2.testing.writeString(AssetId.parse(catalogAsset), catalogJson!);
    final logs = <String>[];
    final legacyResult = await testBuilder(
      restageCodegenBuilder(BuilderOptions.empty),
      {paywallAsset: source},
      rootPackage: 'apps_examples',
      readerWriter: rw2,
      flattenOutput: true,
      outputs: {
        'apps_examples|assets/paywalls/streak.rfwtxt': decodedMatches(
          allOf(
            contains('import acme.ds;'),
            contains('StreakBadge'),
            contains('label: "Day"'),
            contains('count: 9'),
            contains('label: "Week"'),
            contains('count: 12'),
          ),
        ),
        'apps_examples|assets/paywalls/streak.rfw': isNotEmpty,
        'apps_examples|assets/paywalls/streak.capability.json':
            decodedMatches(contains('acme.ds')),
        'apps_examples|assets/paywalls/screens/paywall_streak.rfw': anything,
        'apps_examples|assets/paywalls/screens/paywall_streak.capability.json':
            anything,
      },
      onLog: (record) => logs.add(record.message),
    );
    final notices = logs
        .where((message) => message.contains('[customWidgetAppFactoryUsed]'))
        .toList();
    expect(notices, hasLength(1), reason: logs.join('\n'));
    expect(notices.single, contains("Custom widget 'StreakBadge'"));
    expect(notices.single, contains("registered 'acme.ds' app factory"));
    expect(notices.single, contains('CustomPaint'));
    expect(notices.single, contains("installed app's compiled widget body"));
    expect(notices.single, contains('defaults remain authoritative'));
    expect(notices.single, contains('requires an app release'));
    expect(notices.single, contains('Explicit call values remain supplied'));

    final priceReader = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
      includeFlutter: true,
      includeIntl: true,
    );
    priceReader.testing.writeString(AssetId.parse(priceAsset), priceSource);
    final priceResult = await testBuilder(
      restageCodegenBuilder(BuilderOptions.empty),
      {priceAsset: priceSource},
      rootPackage: 'apps_examples',
      readerWriter: priceReader,
      verbose: true,
      flattenOutput: true,
      outputs: {
        'apps_examples|assets/paywalls/price_tag.rfwtxt':
            decodedMatches(contains('RestagePrice(')),
        'apps_examples|assets/paywalls/price_tag.rfw': isNotEmpty,
        'apps_examples|assets/paywalls/price_tag.capability.json': anything,
        'apps_examples|assets/paywalls/screens/paywall_price_tag.rfw': anything,
        'apps_examples|assets/paywalls/screens/paywall_price_tag.capability.json':
            anything,
      },
      onLog: (record) => logs.add(record.message),
    );
    final idiomNotices = logs
        .where((message) => message.contains('[idiomAutoSubstituted]'))
        .toList();
    expect(idiomNotices, hasLength(1), reason: logs.join('\n'));

    final packageReader = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
      includeFlutter: true,
      includeIntl: true,
    );
    packageReader.testing
      ..writeString(AssetId.parse(paywallAsset), source)
      ..writeString(AssetId.parse(canonicalAsset), canonicalSource)
      ..writeString(AssetId.parse(configurationAsset), configurationSource)
      ..writeString(AssetId.parse(priceAsset), priceSource)
      ..writeString(AssetId.parse(catalogAsset), catalogJson!);
    for (final path in <String>[
      'assets/paywalls/streak.rfwtxt',
      'assets/paywalls/streak.rfw',
      'assets/paywalls/streak.capability.json',
      'assets/paywalls/screens/paywall_streak.rfw',
      'assets/paywalls/screens/paywall_streak.capability.json',
    ]) {
      final asset = AssetId('apps_examples', path);
      packageReader.testing.writeBytes(
        asset,
        legacyResult.readerWriter.testing.readBytes(asset),
      );
    }
    for (final path in <String>[
      'assets/paywalls/price_tag.rfwtxt',
      'assets/paywalls/price_tag.rfw',
      'assets/paywalls/price_tag.capability.json',
      'assets/paywalls/screens/paywall_price_tag.rfw',
      'assets/paywalls/screens/paywall_price_tag.capability.json',
    ]) {
      final asset = AssetId('apps_examples', path);
      packageReader.testing.writeBytes(
        asset,
        priceResult.readerWriter.testing.readBytes(asset),
      );
    }
    final packageResult = await testBuilder(
      const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
      {
        paywallAsset: source,
        canonicalAsset: canonicalSource,
        configurationAsset: configurationSource,
        priceAsset: priceSource,
      },
      rootPackage: 'apps_examples',
      readerWriter: packageReader,
      verbose: true,
      flattenOutput: true,
      onLog: (record) => logs.add(record.message),
    );
    final completeBuildNotices = logs
        .where((message) => message.contains('[customWidgetAppFactoryUsed]'))
        .toList();
    expect(completeBuildNotices, hasLength(1), reason: logs.join('\n'));
    final completeIdiomNotices = logs
        .where((message) => message.contains('[idiomAutoSubstituted]'))
        .toList();
    expect(completeIdiomNotices, hasLength(1), reason: logs.join('\n'));
    expect(packageResult.succeeded, isTrue, reason: logs.join('\n'));
  });

  test('logs one app-factory notice for repeated widget routes', () async {
    const source = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageLibrary(
  library: WidgetLibrary.custom('acme.ds'),
  capabilityVersion: 1,
)
const acmeLibrary = 0;

@RestageWidget(name: 'StreakBadge',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.decoration, description: 'streak')
class StreakBadge extends StatelessWidget {
  const StreakBadge({this.label, this.count});
  @RestageProperty(description: 'label')
  final String? label;
  @RestageProperty(description: 'count')
  final int? count;
  @override
  Widget build(BuildContext context) => CustomPaint(painter: StreakPainter());
}

class StreakPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {}
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

@Paywall(id: 'day_offer')
class ADayOffer extends StatelessWidget {
  const ADayOffer({super.key});
  @override
  Widget build(BuildContext context) =>
      const StreakBadge(label: 'Day', count: 9);
}

@Paywall(id: 'week_offer')
class BWeekOffer extends StatelessWidget {
  const BWeekOffer({super.key});
  @override
  Widget build(BuildContext context) =>
      const StreakBadge(label: 'Week', count: 12);
}
''';
    const sourceAsset = 'apps_examples|lib/features/offers.dart';
    final catalogReader = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
      includeFlutter: true,
    );
    catalogReader.testing.writeString(AssetId.parse(sourceAsset), source);
    String? catalogJson;
    await testBuilder(
      const UserCatalogJsonBuilder(BuilderOptions.empty),
      const {sourceAsset: source},
      rootPackage: 'apps_examples',
      readerWriter: catalogReader,
      outputs: {
        catalogAsset: decodedMatches(
          predicate<String>((value) {
            catalogJson = value;
            return true;
          }),
        ),
      },
      onLog: (_) {},
    );

    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
      includeFlutter: true,
    );
    readerWriter.testing
      ..writeString(AssetId.parse(sourceAsset), source)
      ..writeString(
        AssetId.parse(catalogAsset),
        catalogJson!,
      );
    final logs = <String>[];
    final result = await testBuilder(
      const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
      const {sourceAsset: source},
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
      onLog: (record) => logs.add(record.message),
    );

    expect(result.succeeded, isTrue, reason: logs.join('\n'));
    final bundle = jsonDecode(
      readerWriter.testing.readString(
        AssetId(
          'apps_examples',
          'lib/src/surface_publication/surface_publication.compiler.json',
        ),
      ),
    ) as Map<String, Object?>;
    final artifactPaths = [
      for (final artifact in bundle['artifacts']! as List<Object?>)
        (artifact! as Map<String, Object?>)['path'],
    ];
    expect(
      artifactPaths,
      containsAll(<String>[
        'assets/paywalls/day_offer.rfw',
        'assets/paywalls/week_offer.rfw',
      ]),
    );
    final notices = logs
        .where((message) => message.contains('[customWidgetAppFactoryUsed]'))
        .toList();
    expect(notices, hasLength(1), reason: logs.join('\n'));
    expect(notices.single, contains("Custom widget 'StreakBadge'"));
    expect(notices.single, contains('CustomPaint'));
  });
}
