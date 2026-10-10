import 'dart:convert';

import 'package:build/build.dart';
import 'package:restage_codegen/builder.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const String _package = 'apps_examples';

String _paywall(String name, String build, {String helper = ''}) => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@Paywall()
class $name extends StatelessWidget {
  const $name({super.key});

  @override
  Widget build(BuildContext context) {
$build
  }
$helper
}
''';

final Map<String, String> _fixtures = {
  'helper_locals': _paywall(
    'HelperLocals',
    "    return Column(children: [_card(context, 'A'), _card(context, 'B')]);",
    helper: '''
  Widget _card(BuildContext context, String title) {
    final scheme = Theme.of(context).colorScheme;
    final label = Text(title);
    return Container(color: scheme.primary, child: label);
  }''',
  ),
  'helper_inlined': _paywall(
    'HelperInlined',
    '''
    return Column(
      children: [
        Container(
          color: Theme.of(context).colorScheme.primary,
          child: const Text('A'),
        ),
        Container(
          color: Theme.of(context).colorScheme.primary,
          child: const Text('B'),
        ),
      ],
    );''',
  ),
  'top_level_helper_locals': '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

Widget _row(String title) {
  final label = Text(title);
  return Row(children: [label]);
}

@Paywall()
class TopLevelHelperLocals extends StatelessWidget {
  const TopLevelHelperLocals({super.key});

  @override
  Widget build(BuildContext context) => Column(children: [_row('A')]);
}
''',
  'top_level_helper_inlined': _paywall(
    'TopLevelHelperInlined',
    "    return Column(children: [Row(children: [const Text('A')])]);",
  ),
};

Future<TestReaderWriter> _seeded(Map<String, String> sources) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: _package,
    includeFlutter: true,
  );
  for (final entry in sources.entries) {
    readerWriter.testing.writeString(AssetId.parse(entry.key), entry.value);
  }
  return readerWriter;
}

String _text(TestBuilderResult result, String id) => result.readerWriter.testing
    .readString(AssetId(_package, 'assets/paywalls/$id.rfwtxt'));

Future<String> _log(
  String slug,
  String source, {
  Map<String, String> parts = const {},
}) async {
  final sources = {
    '$_package|lib/paywalls/$slug.dart': source,
    for (final entry in parts.entries)
      '$_package|lib/paywalls/${entry.key}': entry.value,
  };
  final logs = <String>[];
  await testBuilder(
    restageCodegenBuilder(BuilderOptions.empty),
    sources,
    rootPackage: _package,
    readerWriter: await _seeded(sources),
    outputs: const {},
    onLog: (record) => logs.add(record.message),
  );
  return logs.join('\n');
}

void main() {
  late TestBuilderResult result;

  setUpAll(() async {
    final sources = {
      for (final entry in _fixtures.entries)
        '$_package|lib/paywalls/${entry.key}.dart': entry.value,
    };
    result = await testBuilders(
      [restageCodegenBuilder(BuilderOptions.empty)],
      sources,
      rootPackage: _package,
      readerWriter: await _seeded(sources),
      flattenOutput: true,
    );
  });

  test('every helper fixture compiles', () {
    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
  });

  test('a helper with final locals matches its inlined twin', () {
    expect(
      _text(result, 'helper_locals'),
      contains('data.theme.colorScheme.primary'),
    );
    expect(_text(result, 'helper_locals'), _text(result, 'helper_inlined'));
  });

  test('a top-level helper with a final local matches its inlined twin', () {
    expect(
      _text(result, 'top_level_helper_locals'),
      _text(result, 'top_level_helper_inlined'),
    );
  });

  test('an unread helper local is refused by name', () async {
    final log = await _log(
      'helper_unused_local',
      _paywall(
        'HelperUnusedLocal',
        '    return Column(children: [_card()]);',
        helper: '''
  Widget _card() {
    final unused = 'x';
    return const Text('A');
  }''',
      ),
    );
    expect(
      log,
      contains(
        "The helper '_card' cannot be inlined: the local 'unused' is declared "
        "in the helper '_card' but never read",
      ),
    );
    expect(log, isNot(contains('unknownWidget')));
  });

  test('an unsupported helper statement is refused by name', () async {
    final log = await _log(
      'helper_statement',
      _paywall(
        'HelperStatement',
        '    return Column(children: [_card(true)]);',
        helper: '''
  Widget _card(bool wide) {
    if (wide) return const Text('Wide');
    return const Text('Narrow');
  }''',
      ),
    );
    expect(
      log,
      contains(
        "The helper '_card' cannot be inlined: its body must be one returned "
        'expression',
      ),
    );
    expect(log, isNot(contains('unknownWidget')));
  });

  test('a refused helper in a part file is refused by name', () async {
    final log = await _log(
      'helper_part',
      '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'helper_part_cards.dart';

@Paywall()
class HelperPart extends StatelessWidget {
  const HelperPart({super.key});

  @override
  Widget build(BuildContext context) => Column(children: [_card(true)]);
}
''',
      parts: {
        'helper_part_cards.dart': '''
part of 'helper_part.dart';

Widget _card(bool wide) {
  if (wide) return const Text('Wide');
  return const Text('Narrow');
}
''',
      },
    );
    expect(
      log,
      contains(
        "The helper '_card' cannot be inlined: its body must be one returned "
        'expression',
      ),
    );
    expect(log, isNot(contains('unknownWidget')));
  });

  group('helpers from another file in the package', () {
    const widgets = '''
// @dart=3.13
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

import '../style/spacing.dart';

@RestageLibrary(
  library: WidgetLibrary.custom('acme.widgets'),
  capabilityVersion: 1,
)
const acmeWidgets = 0;

@RestageWidget(
  name: 'PlanBadge',
  library: WidgetLibrary.custom('acme.widgets'),
  category: WidgetCategory.decoration,
  description: 'A plan badge.',
)
final class PlanBadge extends StatelessWidget {
  const PlanBadge({super.key, required this.label});

  /// The badge text.
  final String label;

  static PlanBadge pro() => const PlanBadge(label: 'Pro');

  @override
  Widget build(BuildContext context) =>
      Padding(padding: Spacing.badge(), child: Text(label));
}

Widget buyButton(String label) =>
    FilledButton(onPressed: paywallEvent('buy'), child: Text(label));
''';
    const spacing = '''
import 'package:flutter/widgets.dart';

abstract final class Spacing {
  static EdgeInsets page() => const EdgeInsets.all(24);
  static EdgeInsets badge() => const EdgeInsets.symmetric(horizontal: 6);
}
''';
    String paywall(String body) => '''
// @dart=3.13
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import '../style/spacing.dart';
import '../widgets/plan_badge.dart';

@Paywall()
class PackageHelpers extends StatelessWidget {
  const PackageHelpers({super.key});

  @override
  Widget build(BuildContext context) {
$body
  }
}
''';
    final called = paywall('''
    final PlanBadge shorthand = .pro();
    return Padding(
      padding: Spacing.page(),
      child: Column(children: [PlanBadge.pro(), shorthand, buyButton('Buy')]),
    );''');
    final inlined = paywall('''
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const PlanBadge(label: 'Pro'),
          const PlanBadge(label: 'Pro'),
          FilledButton(onPressed: paywallEvent('buy'), child: Text('Buy')),
        ],
      ),
    );''');

    Future<(TestBuilderResult, List<String>)> compile(
      String surface,
      List<Builder> builders,
    ) async {
      final sources = {
        '$_package|lib/widgets/plan_badge.dart': widgets,
        '$_package|lib/style/spacing.dart': spacing,
        '$_package|lib/paywalls/package_helpers.dart': surface,
      };
      final logs = <String>[];
      final result = await testBuilders(
        builders,
        sources,
        rootPackage: _package,
        readerWriter: await _seeded(sources),
        flattenOutput: true,
        onLog: (record) => logs.add(record.message),
      );
      return (result, logs);
    }

    String rfwtxt(TestBuilderResult result) =>
        result.readerWriter.testing.readString(
          AssetId(_package, 'assets/paywalls/package_helpers.rfwtxt'),
        );

    test('inline like their hand-written twin', () async {
      List<Builder> builders() => [
            userCatalogJsonBuilder(BuilderOptions.empty),
            restageCodegenBuilder(BuilderOptions.empty),
          ];
      final (calledResult, calledLogs) = await compile(called, builders());
      final (inlinedResult, inlinedLogs) = await compile(inlined, builders());
      expect(
        calledResult.succeeded,
        isTrue,
        reason: calledLogs.join('\n'),
      );
      expect(
        inlinedResult.succeeded,
        isTrue,
        reason: inlinedLogs.join('\n'),
      );
      final text = rfwtxt(calledResult);
      expect(text, contains('widget PlanBadge = Padding('));
      expect(text, rfwtxt(inlinedResult));
    });

    test('carry measured events through to the published surface', () async {
      final (result, logs) = await compile(called, [
        userCatalogJsonBuilder(BuilderOptions.empty),
        restageCodegenBuilder(BuilderOptions.empty),
        paywallFlowBuilder(BuilderOptions.empty),
        restagePackageSurfaceCompilerBuilder(BuilderOptions.forRoot),
        restageGeneratedDartBuilder(BuilderOptions.empty),
      ]);
      expect(result.succeeded, isTrue, reason: logs.join('\n'));
      expect(
        logs.join('\n'),
        isNot(contains('Measurement is unavailable')),
      );
      final ledger = jsonDecode(
        result.readerWriter.testing.readString(
          AssetId(
            _package,
            'lib/src/measurement/restage.measurement.compiler.json',
          ),
        ),
      ) as Map<String, Object?>;
      final events = [
        for (final node in ledger['ledgerNodes']! as List<Object?>)
          for (final event
              in (node! as Map<String, Object?>)['events']! as List<Object?>)
            (event! as Map<String, Object?>)['resolvedEventLocator'],
      ];
      expect(events, contains(endsWith('FilledButton.onPressed')));
    });

    Future<String> refusalLog(Map<String, String> files) async {
      final sources = {
        for (final entry in files.entries)
          '$_package|${entry.key}': entry.value,
      };
      final logs = <String>[];
      final result = await testBuilders(
        [restageCodegenBuilder(BuilderOptions.empty)],
        sources,
        rootPackage: _package,
        readerWriter: await _seeded(sources),
        flattenOutput: true,
        onLog: (record) => logs.add(record.message),
      );
      expect(result.succeeded, isFalse);
      return logs.join('\n');
    }

    test('that cannot inline say why', () async {
      final log = await refusalLog({
        'lib/style/values.dart': '''
abstract final class Values {
  static T pick<T>(T value) => value;
}
''',
        'lib/paywalls/generic_helper.dart': '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import '../style/values.dart';

@Paywall()
class GenericHelper extends StatelessWidget {
  const GenericHelper({super.key});

  @override
  Widget build(BuildContext context) => Text(Values.pick('x'));
}
''',
      });
      expect(
        log,
        contains(
          "The helper 'Values.pick' cannot be inlined: a helper must return "
          'a widget or a value of a class type.',
        ),
      );
      expect(log, isNot(contains('another package')));
    });

    test('report errors in their own file', () async {
      final log = await refusalLog({
        'lib/widgets/fancy.dart': '''
import 'package:flutter/material.dart';

Widget fancy() => Padding(
      padding: const EdgeInsets.all(4),
      child: const CustomPaint(),
    );
''',
        'lib/paywalls/fancy_helper.dart': '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import '../widgets/fancy.dart';

@Paywall()
class FancyHelper extends StatelessWidget {
  const FancyHelper({super.key});

  @override
  Widget build(BuildContext context) => Column(children: [fancy()]);
}
''',
      });
      expect(log, contains('lib/widgets/fancy.dart:5:'));
      expect(log, contains("'CustomPaint'"));
    });

    test('inline into an onboarding screen', () async {
      String screen(String body) => '''
// @dart=3.13
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import '../../style/spacing.dart';
import '../../widgets/plan_badge.dart';

part 'restage.generated/welcome.restage.g.dart';

@ScreenSource(id: 'welcome')
final class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  static const next = OnboardingEvent<void>('next');

  @override
  Widget build(BuildContext context) => $body;
}
''';
      Future<String> compileScreen(String body) async {
        final sources = {
          '$_package|lib/widgets/plan_badge.dart': widgets,
          '$_package|lib/style/spacing.dart': spacing,
          '$_package|lib/onboarding/screens/welcome.dart': screen(body),
        };
        final logs = <String>[];
        final result = await testBuilders(
          [
            userCatalogJsonBuilder(BuilderOptions.empty),
            onboardingScreenBuilder(BuilderOptions.empty),
          ],
          sources,
          rootPackage: _package,
          readerWriter: await _seeded(sources),
          flattenOutput: true,
          onLog: (record) => logs.add(record.message),
        );
        expect(result.succeeded, isTrue, reason: logs.join('\n'));
        return result.readerWriter.testing.readString(
          AssetId(_package, 'assets/onboarding/screens/welcome.rfwtxt'),
        );
      }

      final called = await compileScreen(
        'Padding(padding: Spacing.page(), child: PlanBadge.pro())',
      );
      final inlined = await compileScreen(
        'const Padding(padding: EdgeInsets.all(24), '
        "child: PlanBadge(label: 'Pro'))",
      );
      expect(called, contains('widget PlanBadge = Padding('));
      expect(called, inlined);
    });

    test('from another package are refused by name', () async {
      const surface = '''
import 'package:acme_kit/kit.dart';
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@Paywall()
class OtherPackage extends StatelessWidget {
  const OtherPackage({super.key});

  @override
  Widget build(BuildContext context) => Column(children: [Kit.badge()]);
}
''';
      final sources = {'$_package|lib/paywalls/other_package.dart': surface};
      final readerWriter = await _seeded(sources);
      readerWriter.testing.writeString(
        AssetId('acme_kit', 'lib/kit.dart'),
        '''
import 'package:flutter/widgets.dart';

abstract final class Kit {
  static Widget badge() => const Text('Kit');
}
''',
      );
      final logs = <String>[];
      final result = await testBuilders(
        [restageCodegenBuilder(BuilderOptions.empty)],
        sources,
        rootPackage: _package,
        readerWriter: readerWriter,
        flattenOutput: true,
        onLog: (record) => logs.add(record.message),
      );
      expect(result.succeeded, isFalse);
      expect(
        logs.join('\n'),
        contains(
          "The helper 'Kit.badge' cannot be inlined: it is declared in "
          'another package, and helpers inline only from this one.',
        ),
      );
    });
  });
}
