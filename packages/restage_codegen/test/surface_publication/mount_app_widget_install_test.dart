import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:restage_codegen/builder.dart';
import 'package:test/test.dart';

import '../helpers.dart';

const _package = 'apps_examples';

const _widgetSource = r'''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

/// A streak count.
@RestageWidget()
class StreakBadge extends StatelessWidget {
  /// Creates a streak badge.
  const StreakBadge({super.key, required this.days});

  /// Consecutive active days.
  final int days;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
        ),
        child: Text('$days day streak'),
      );
}
''';

final String _chipSource = _widgetSource
    .replaceAll('StreakBadge', 'StreakChip')
    .replaceAll('A streak count.', 'A streak chip.')
    .replaceAll('streak badge', 'streak chip');

const _twoWidgetBarrelSource = '''
import 'package:restage/restage.dart';

export 'widgets/streak_badge.dart';
export 'widgets/streak_chip.dart';

final class AppWidgets extends WidgetLibrary {
  const AppWidgets();

  @override
  final String namespace = 'app.widgets';
}

const WidgetLibrary appWidgets = AppWidgets();

@RestageLibrary(library: appWidgets, capabilityVersion: 1)
const appWidgetCatalog = 0;
''';

const _welcomeStepSource = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import '../widgets/streak_badge.dart';

part 'restage.generated/welcome_step.restage.g.dart';

@Screen()
final class WelcomeStep extends StatelessWidget {
  const WelcomeStep({super.key});

  static const next = SurfaceEvent<void>('next');

  @override
  Widget build(BuildContext context) => Column(
        children: [
          const StreakBadge(days: 3),
          FilledButton(
            onPressed: surfaceEvent(next),
            child: const Text('Start'),
          ),
        ],
      );
}
''';

String _flowSource(String imports) => '''
import 'package:restage/restage.dart';

$imports

part 'restage.generated/first_run.restage.g.dart';

@FlowGraph(id: 'first_run', surface: Surface.onboarding)
const firstRun = FlowDefinition(
  start: WelcomeStep,
  transitions: [Transition.complete(WelcomeStep.next)],
);
''';

const _flowPart = 'lib/onboarding/restage.generated/first_run.restage.g.dart';

const _barrelSource = '''
import 'package:restage/restage.dart';

export 'widgets/streak_badge.dart';

final class AppWidgets extends WidgetLibrary {
  const AppWidgets();

  @override
  final String namespace = 'app.widgets';
}

const WidgetLibrary appWidgets = AppWidgets();

@RestageLibrary(library: appWidgets, capabilityVersion: 1)
const appWidgetCatalog = 0;
''';

String _messageSource(String import, String badge) => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

$import

part 'restage.generated/recap.restage.g.dart';

@Screen(id: 'recap', surface: Surface.message)
final class Recap extends StatelessWidget {
  const Recap({super.key});

  @override
  Widget build(BuildContext context) => Column(
        children: [const Text('Nice week'), $badge(days: 3)],
      );
}
''';

const _recapPart = 'lib/messages/restage.generated/recap.restage.g.dart';

void main() {
  group('a generated mount installs the app widgets its surface draws', () {
    test('a screen names the factory through its own imports', () async {
      final sources = {
        'lib/widgets/streak_badge.dart': _widgetSource,
        'lib/app_widgets.dart': _barrelSource,
        'lib/messages/recap.dart':
            _messageSource("import '../app_widgets.dart';", 'StreakBadge'),
      };
      final build = await _build(sources);
      final part = build.parts[_recapPart]!;

      expect(
        _packed(part),
        contains(
          _packed(
            'libraries:[RestageWidgetLibraryRegistration.constant('
            "library:WidgetLibrary.custom('app.widgets'),"
            'capabilityVersion:1,',
          ),
        ),
      );
      expect(
        _packed(part),
        contains(
          _packed(
            "RestageWidgetFactory(name:'StreakBadge',"
            r'builder:_restage$app$widgets$$StreakBadge)',
          ),
        ),
      );
      expect(part, contains(r'Widget _restage$app$widgets$$StreakBadge('));
      expect(part, contains('return StreakBadge('));
      expect(build.warnings, isEmpty);
      expect(await _errors(sources, build.parts), isEmpty);
    });

    test('a declared break carries compatibleSince into the registration',
        () async {
      final sources = {
        'lib/widgets/streak_badge.dart': _widgetSource,
        'lib/app_widgets.dart': _barrelSource.replaceFirst(
          'capabilityVersion: 1)',
          'capabilityVersion: 4, compatibleSince: 4)',
        ),
        'lib/messages/recap.dart':
            _messageSource("import '../app_widgets.dart';", 'StreakBadge'),
      };
      final part = (await _build(sources)).parts[_recapPart]!;

      expect(
        _packed(part),
        contains(
          _packed(
            'capabilityVersion:4,compatibleSince:4,generatedVersion:2,widgets:',
          ),
        ),
      );
    });

    test('compatibleSince 1 stays out of the registration', () async {
      final sources = {
        'lib/widgets/streak_badge.dart': _widgetSource,
        'lib/app_widgets.dart': _barrelSource,
        'lib/messages/recap.dart':
            _messageSource("import '../app_widgets.dart';", 'StreakBadge'),
      };
      final part = (await _build(sources)).parts[_recapPart]!;

      expect(part, isNot(contains('compatibleSince')));
    });

    test('a prefixed import spells the widget through its prefix', () async {
      final sources = {
        'lib/widgets/streak_badge.dart': _widgetSource,
        'lib/app_widgets.dart': _barrelSource,
        'lib/messages/recap.dart': _messageSource(
          "import '../app_widgets.dart' as app;",
          'app.StreakBadge',
        ),
      };
      final build = await _build(sources);

      expect(build.parts[_recapPart], contains('return app.StreakBadge('));
      expect(await _errors(sources, build.parts), isEmpty);
    });

    test('a paywall mount installs them before it mounts', () async {
      final sources = {
        'lib/widgets/streak_badge.dart': _widgetSource,
        'lib/app_widgets.dart': _barrelSource,
        'lib/paywalls/offer.dart': '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import '../app_widgets.dart';

part 'restage.generated/offer.restage.g.dart';

@Paywall(id: 'offer')
final class Offer extends StatelessWidget {
  const Offer({super.key});

  @override
  Widget build(BuildContext context) =>
      Column(children: [const Text('Go pro'), StreakBadge(days: 3)]);
}
''',
      };
      final build = await _build(sources);
      final part = _packed(
        build.parts['lib/paywalls/restage.generated/offer.restage.g.dart']!,
      );

      expect(
        part,
        contains(
          _packed(
            r'builder:_restage$app$widgets$$StreakBadge),],),],)'
            '.addToInstalled();',
          ),
        ),
      );
      expect(build.warnings, isEmpty);
      expect(await _errors(sources, build.parts), isEmpty);
    });

    test('a flow installs its steps through constants their parts declare',
        () async {
      final sources = {
        'lib/widgets/streak_badge.dart': _widgetSource,
        'lib/app_widgets.dart': _barrelSource,
        'lib/onboarding/welcome_step.dart': '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import '../widgets/streak_badge.dart';

part 'restage.generated/welcome_step.restage.g.dart';

@Screen()
final class WelcomeStep extends StatelessWidget {
  const WelcomeStep({super.key});

  static const next = SurfaceEvent<void>('next');

  @override
  Widget build(BuildContext context) => Column(
        children: [
          const StreakBadge(days: 3),
          FilledButton(
            onPressed: surfaceEvent(next),
            child: const Text('Start'),
          ),
        ],
      );
}
''',
        'lib/onboarding/first_run.dart': '''
import 'package:restage/restage.dart';

import 'welcome_step.dart';

part 'restage.generated/first_run.restage.g.dart';

@FlowGraph(id: 'first_run', surface: Surface.onboarding)
const firstRun = FlowDefinition(
  start: WelcomeStep,
  transitions: [Transition.complete(WelcomeStep.next)],
);
''',
      };
      final build = await _build(sources);

      const generated = 'lib/onboarding/restage.generated';
      expect(
        build.parts['$generated/welcome_step.restage.g.dart'],
        contains(
          'const welcomeStepAppWidgets = <RestageWidgetLibraryRegistration>[',
        ),
      );
      expect(
        build.parts['$generated/first_run.restage.g.dart'],
        contains('libraries: [...welcomeStepAppWidgets]'),
      );
      expect(build.warnings, isEmpty);
      expect(await _errors(sources, build.parts), isEmpty);
    });

    test('a surface installs every widget of the libraries it draws from',
        () async {
      final sources = {
        'lib/widgets/streak_badge.dart': _widgetSource,
        'lib/widgets/streak_chip.dart': _chipSource,
        'lib/app_widgets.dart': _twoWidgetBarrelSource,
        'lib/messages/recap.dart':
            _messageSource("import '../app_widgets.dart';", 'StreakBadge'),
      };
      final build = await _build(sources);
      final part = _packed(build.parts[_recapPart]!);

      // A later published version may draw StreakChip: delivery admits it by
      // library and capability version alone.
      expect(
        part,
        contains(
          _packed(
            "RestageWidgetFactory(name:'StreakBadge',"
            r'builder:_restage$app$widgets$$StreakBadge),'
            "RestageWidgetFactory(name:'StreakChip',"
            r'builder:_restage$app$widgets$$StreakChip)',
          ),
        ),
      );
      expect(build.warnings, isEmpty);
      expect(await _errors(sources, build.parts), isEmpty);
    });

    test('a library widget the surface cannot name installs nothing', () async {
      final sources = {
        'lib/widgets/streak_badge.dart': _widgetSource,
        'lib/widgets/streak_chip.dart': _chipSource,
        'lib/app_widgets.dart': _twoWidgetBarrelSource,
        'lib/messages/recap.dart': _messageSource(
          "import '../widgets/streak_badge.dart';",
          'StreakBadge',
        ),
      };
      final build = await _build(sources);
      final part = build.parts[_recapPart]!;

      expect(part, isNot(contains('libraries:')));
      expect(
        build.warnings,
        contains(allOf(contains('StreakChip'), contains('streak_chip.dart'))),
      );
      expect(await _errors(sources, build.parts), isEmpty);
    });

    test('a flow whose library names the widgets installs them itself',
        () async {
      final sources = {
        'lib/widgets/streak_badge.dart': _widgetSource,
        'lib/app_widgets.dart': _barrelSource,
        'lib/onboarding/welcome_step.dart': _welcomeStepSource,
        'lib/onboarding/first_run.dart': _flowSource(
          "import 'package:flutter/material.dart';\n"
          "import '../app_widgets.dart';\n"
          "import 'welcome_step.dart' show WelcomeStep;",
        ),
      };
      final build = await _build(sources);
      final flow = _packed(build.parts[_flowPart]!);

      expect(
        flow,
        contains(
          _packed('libraries:[RestageWidgetLibraryRegistration.constant('),
        ),
        reason: build.warnings.join('\n'),
      );
      expect(flow, contains(r'Widget_restage$app$widgets$$StreakBadge('));
      expect(flow, isNot(contains('welcomeStepAppWidgets')));
      expect(build.warnings, isEmpty);
      expect(await _errors(sources, build.parts), isEmpty);
    });

    for (final (label, extra, import) in [
      (
        'a show import',
        const <String, String>{},
        "import 'welcome_step.dart' show WelcomeStep;",
      ),
      (
        'a barrel exporting with show',
        const {
          'lib/onboarding/steps.dart':
              "export 'welcome_step.dart' show WelcomeStep;\n",
        },
        "import 'steps.dart';",
      ),
    ]) {
      test('a flow that cannot see a step constant through $label compiles',
          () async {
        final sources = {
          'lib/widgets/streak_badge.dart': _widgetSource,
          'lib/app_widgets.dart': _barrelSource,
          'lib/onboarding/welcome_step.dart': _welcomeStepSource,
          ...extra,
          'lib/onboarding/first_run.dart': _flowSource(import),
        };
        final build = await _build(sources);

        expect(build.parts[_flowPart], isNot(contains('AppWidgets')));
        expect(
          build.warnings,
          contains(contains('cannot see welcomeStepAppWidgets')),
        );
        expect(await _errors(sources, build.parts), isEmpty);
      });
    }

    test('factory names keep namespace and widget apart', () async {
      final recap = _messageSource(
        "import '../app_widgets.dart';\nimport '../card_widgets.dart';",
        'StreakBadge',
      ).replaceAll(
        'StreakBadge(days: 3)',
        'StreakBadge(days: 3), CardsStreakBadge(days: 2)',
      );
      final sources = {
        'lib/widgets/streak_badge.dart': _widgetSource,
        'lib/widgets/cards_streak_badge.dart': _widgetSource
            .replaceAll('StreakBadge', 'CardsStreakBadge')
            .replaceAll('A streak count.', 'A card streak count.'),
        'lib/app_widgets.dart': _barrelSource.replaceAll(
          "export 'widgets/streak_badge.dart';",
          "export 'widgets/cards_streak_badge.dart';",
        ),
        'lib/card_widgets.dart': _barrelSource
            .replaceAll('AppWidgets', 'CardWidgets')
            .replaceAll('appWidgets', 'cardWidgets')
            .replaceAll('appWidgetCatalog', 'cardWidgetCatalog')
            .replaceAll("'app.widgets'", "'app.widgets.cards'"),
        'lib/messages/recap.dart': recap,
      };
      final build = await _build(sources);
      final part = _packed(build.parts[_recapPart]!);

      expect(part, contains(r'_restage$app$widgets$cards$$StreakBadge'));
      expect(part, contains(r'_restage$app$widgets$$CardsStreakBadge'));
      expect(await _errors(sources, build.parts), isEmpty);
    });

    test('a name its library shadows installs nothing, with a warning',
        () async {
      final sources = {
        'lib/widgets/streak_badge.dart': _widgetSource,
        'lib/app_widgets.dart': _barrelSource,
        'lib/messages/recap.dart': '''
${_messageSource("import '../app_widgets.dart';", 'StreakBadge')}

final class DataSource {}
''',
      };
      final build = await _build(sources);
      final part = build.parts[_recapPart]!;

      expect(part, isNot(contains('libraries:')));
      expect(part, isNot(contains(r'_restage$app')));
      expect(
        build.warnings,
        contains(contains('cannot name DataSource')),
      );
      expect(await _errors(sources, build.parts), isEmpty);
    });
  });
}

/// [source] without whitespace or trailing commas, so either format style
/// compares equal.
String _packed(String source) => source
    .replaceAll(RegExp(r'\s+'), '')
    .replaceAll(RegExp(r',(?=[)\]}])'), '');

typedef _Build = ({Map<String, String> parts, List<String> warnings});

Future<_Build> _build(Map<String, String> sources) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: _package,
  );
  final assets = {
    for (final entry in sources.entries) '$_package|${entry.key}': entry.value,
  };
  for (final entry in assets.entries) {
    readerWriter.testing.writeString(AssetId.parse(entry.key), entry.value);
  }
  final catalogBuild = await testBuilder(
    userCatalogJsonBuilder(BuilderOptions.empty),
    assets,
    rootPackage: _package,
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  expect(catalogBuild.succeeded, isTrue, reason: catalogBuild.errors.join());
  for (final path in const [
    'lib/src/widget_catalog/catalog.json',
    'lib/src/widget_catalog/app_widget_factories.json',
  ]) {
    assets['$_package|$path'] =
        readerWriter.testing.readString(AssetId(_package, path));
  }
  final warnings = <String>[];
  final result = await testBuilders(
    [
      restagePackageSurfaceCompilerBuilder(BuilderOptions.forRoot),
      restageGeneratedDartBuilder(BuilderOptions.empty),
    ],
    assets,
    rootPackage: _package,
    readerWriter: readerWriter,
    flattenOutput: true,
    onLog: (record) {
      if (record.level.name == 'WARNING') warnings.add(record.message);
    },
  );
  expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
  final parts = <String, String>{};
  for (final path in sources.keys) {
    final slash = path.lastIndexOf('/');
    final part = '${path.substring(0, slash)}/restage.generated/'
        '${path.substring(slash + 1, path.length - 5)}.restage.g.dart';
    final id = AssetId(_package, part);
    if (readerWriter.testing.exists(id)) {
      parts[part] = readerWriter.testing.readString(id);
    }
  }
  return (
    parts: parts,
    warnings: [
      for (final warning in warnings)
        if (!warning.contains('Measurement') &&
            !warning.contains('customWidgetAppFactoryUsed'))
          warning,
    ],
  );
}

/// Analyzer errors in [sources] once their generated [parts] are in place.
Future<List<String>> _errors(
  Map<String, String> sources,
  Map<String, String> parts,
) async {
  final inputs = {
    for (final entry in {...sources, ...parts}.entries)
      'restage_codegen|${entry.key}': entry.value,
  };
  return await resolveSources(
    inputs,
    (resolver) async {
      final errors = <String>[];
      for (final path in sources.keys) {
        final library = await resolver.libraryFor(
          AssetId('restage_codegen', path),
        );
        final resolved =
            await library.session.getResolvedLibraryByElement(library);
        if (resolved is! ResolvedLibraryResult) {
          errors.add('$path did not resolve');
          continue;
        }
        for (final unit in resolved.units) {
          for (final diagnostic in unit.diagnostics) {
            if (diagnostic.severity == Severity.error) {
              errors.add(
                '${unit.path}: '
                '${diagnostic.problemMessage.messageText(includeUrl: false)}',
              );
            }
          }
        }
      }
      return errors;
    },
    resolverFor: 'restage_codegen|${sources.keys.first}',
    rootPackage: 'restage_codegen',
    readAllSourcesFromFilesystem: true,
  );
}
