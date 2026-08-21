// What a package pays the analyzer for the builders it gets by default.
//
// Five builders apply to every package that depends on this one and each walks
// the whole package. An artifact cannot show whether a walk resolved one file
// or ten thousand — both emit the same nothing when nothing is annotated — so
// these tests count `libraryFor` at the resolver.

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/builder.dart';
import 'package:restage_codegen/src/widgetbook/widgetbook_story_builder.dart';
import 'package:test/test.dart';

import 'counting_resolvers.dart';
import 'helpers.dart';

/// Every builder `build.yaml` applies to a consumer automatically and that
/// walks the package rather than a single input.
Map<String, Builder> _defaultOnPackageWalkers() => {
      'restage_source_roster': restageSourceRosterBuilder(BuilderOptions.empty),
      'restage_package_surface_compiler':
          restagePackageSurfaceCompilerBuilder(BuilderOptions.empty),
      'user_catalog': userCatalogBuilder(BuilderOptions.empty),
      'user_catalog_json': userCatalogJsonBuilder(BuilderOptions.empty),
      'user_factories': userFactoryBuilder(BuilderOptions.empty),
    };

/// The two builders a consumer must opt into. They are not applied
/// automatically, but a consumer that enables one pays the same walk.
Map<String, Builder> _optInPackageWalkers() => {
      'user_a2ui_catalog': userA2uiCatalogBuilder(BuilderOptions.empty),
      'widgetbook_stories': widgetbookStoryBuilder(BuilderOptions.empty),
    };

/// The opt-in walkers again, for the annotated fixture.
///
/// A walker added to [_optInPackageWalkers] is covered by both the zero-test
/// and the positive test without being named twice.
Map<String, Builder> _optInPackageWalkersForAnnotatedFixture() => {
      ..._optInPackageWalkers(),
      // The Widgetbook builder alone needs replacing: it discovers its outputs
      // at startup from the real filesystem, so a synthetic fixture has to
      // declare the story output its widget requires.
      'widgetbook_stories': const WidgetbookStoryBuilder({
        r'$lib$': ['widgets/restage.generated/badge.stories.dart'],
      }),
    };

/// A package of ordinary Flutter code with no Restage declaration anywhere.
const Map<String, String> _unannotatedPackage = {
  'lib/main.dart': '''
import 'package:flutter/widgets.dart';

class HomeScreenController {
  const HomeScreenController();
}
''',
  'lib/widgets/card.dart': '''
import 'package:flutter/widgets.dart';

class ProductCard extends StatelessWidget {
  const ProductCard({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''',
  'lib/models/order.dart': '''
class Order {
  const Order(this.id);

  final String id;
}
''',
};

const String _annotatedWidget = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageWidget(
  name: 'Badge',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'A badge.',
)
class Badge extends StatelessWidget {
  const Badge({super.key, this.label = ''});

  /// Text to show.
  final String label;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

/// The opt-in targets additionally require the custom library to declare a
/// capability version, so their fixture carries the barrel the default-on
/// targets do not need.
const String _annotatedWidgetLibrary = '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
export 'widgets/badge.dart';

@RestageLibrary(
  library: WidgetLibrary.custom('fixture.widgets'),
  capabilityVersion: 1,
)
const restageLibrary = 0;
''';

const String _annotatedScreen = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/welcome.restage.g.dart';

@Screen(id: 'welcome')
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(width: 1, height: 1);
}
''';

void main() {
  group('default-on package walkers', () {
    test('every package walker has an annotated fixture', () {
      // The positive tests are driven off this map, so a walker missing from
      // it would lose its counterpart quietly.
      expect(
        {..._defaultOnPackageWalkers().keys, ..._optInPackageWalkers().keys}
            .difference(_annotatedFixtures.keys.toSet()),
        isEmpty,
        reason: 'these walkers have a zero-test and no positive counterpart',
      );
    });

    _walkerTests(
      zero: _defaultOnPackageWalkers(),
      positive: _defaultOnPackageWalkers(),
    );
    _walkerTests(
      zero: _optInPackageWalkers(),
      positive: _optInPackageWalkersForAnnotatedFixture(),
    );

    // G-5: the property the whole design rests on. Scanning a file must make
    // it an input of the step, or a token-free file that later gains an
    // annotation would not re-trigger the walk.
    test('registers every scanned file as an input of the step', () async {
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );

      final result = await testBuilder(
        restageSourceRosterBuilder(BuilderOptions.empty),
        {
          ..._unannotatedPackage.map(
            (path, source) => MapEntry('apps_examples|$path', source),
          ),
          'apps_examples|lib/models/order.g.dart': 'class OrderDto {}',
          'apps_examples|lib/onboarding/screens/welcome.dart': _annotatedScreen,
        },
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
      );
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));

      final tracked = readerWriter.testing.inputsTrackedFor(
        primaryInput: AssetId('apps_examples', r'$package$'),
      );
      // A token-free file, a generated file the walk will not resolve, and the
      // glob node itself — a new file has to invalidate the walk too.
      expect(tracked, contains(AssetId('apps_examples', 'lib/main.dart')));
      expect(
        tracked,
        contains(AssetId('apps_examples', 'lib/models/order.g.dart')),
      );
      expect(
        tracked.map((asset) => asset.path),
        contains(startsWith('glob.')),
      );
    });
  });
}

/// The annotated fixture a package walker has to reach, keyed by builder name:
/// what to add on top of [_unannotatedPackage], and the path the walk must
/// resolve.
///
/// One map for every walker, so a builder added to [_defaultOnPackageWalkers]
/// or [_optInPackageWalkers] is covered by the zero-test AND its positive
/// counterpart without being named a third time. Without the positive test, a
/// change that stopped a builder resolving for an unrelated reason would keep
/// its zero green with nothing to notice.
const Map<String, ({Map<String, String> sources, String resolves})>
    _annotatedFixtures = {
  'restage_source_roster': _screenFixture,
  'restage_package_surface_compiler': _screenFixture,
  'user_catalog': _widgetFixture,
  'user_catalog_json': _widgetFixture,
  'user_factories': _widgetFixture,
  'user_a2ui_catalog': _widgetLibraryFixture,
  'widgetbook_stories': _widgetLibraryFixture,
};

const ({Map<String, String> sources, String resolves}) _screenFixture = (
  sources: {'lib/onboarding/screens/welcome.dart': _annotatedScreen},
  resolves: 'lib/onboarding/screens/welcome.dart',
);

const ({Map<String, String> sources, String resolves}) _widgetFixture = (
  sources: {'lib/widgets/badge.dart': _annotatedWidget},
  resolves: 'lib/widgets/badge.dart',
);

const ({Map<String, String> sources, String resolves}) _widgetLibraryFixture = (
  sources: {
    'lib/widgets/badge.dart': _annotatedWidget,
    'lib/fixture_widgets.dart': _annotatedWidgetLibrary,
  },
  resolves: 'lib/widgets/badge.dart',
);

/// Runs [builder] over [sources] with a counting resolver and returns what it
/// resolved in the fixture package.
Future<List<ResolverUse>> _resolverUses(
  Builder builder,
  Map<String, String> sources,
) async {
  final resolvers = CountingResolvers();
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );

  final result = await testBuilder(
    builder,
    {
      for (final source in sources.entries)
        'apps_examples|${source.key}': source.value,
    },
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    resolvers: resolvers,
  );

  expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
  return resolvers.usesIn('apps_examples');
}

/// The zero-test and its positive counterpart for every walker in [zero].
///
/// [positive] is the same set unless a builder needs a different instance for
/// the annotated fixture.
void _walkerTests({
  required Map<String, Builder> zero,
  required Map<String, Builder> positive,
}) {
  for (final entry in zero.entries) {
    test('${entry.key} resolves nothing in an unannotated package', () async {
      final uses = await _resolverUses(entry.value, _unannotatedPackage);

      expect(
        uses,
        isEmpty,
        reason: 'analysed: ${uses.map((use) => use.asset?.path).toList()}',
      );
    });
  }

  for (final entry in positive.entries) {
    final fixture = _annotatedFixtures[entry.key]!;
    test('${entry.key} resolves an annotated package', () async {
      final uses = await _resolverUses(entry.value, {
        ..._unannotatedPackage,
        ...fixture.sources,
      });

      expect(uses.map((use) => use.asset?.path), contains(fixture.resolves));
    });
  }
}
