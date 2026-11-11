import 'dart:convert';

import 'package:build/build.dart';
import 'package:restage_codegen/builder.dart';
import 'package:restage_codegen/src/measurement/measurement_compiler_output.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:test/test.dart';

import '../helpers.dart';

const _package = 'apps_examples';

const _events = '''
import 'package:restage/restage.dart';

abstract final class CommonEvents {
  static const close = SurfaceEvent<void>('close');
  static const pick = SurfaceEvent<String>('pick');
}
''';

const _widget = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'common_events.dart';

@RestageLibrary(
  library: WidgetLibrary.custom('acme.ui'),
  capabilityVersion: 1,
)
const restageLibrary = 0;

@RestageWidget(
  name: 'CloseAction',
  library: WidgetLibrary.custom('acme.ui'),
  category: WidgetCategory.decoration,
  description: 'A close button.',
)
class CloseAction extends StatelessWidget {
  const CloseAction({super.key});

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: context.surfaceEvent(CommonEvents.close),
        child: const Text('Close'),
      );
}
''';

const _ui = '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
export 'pip.dart';

@RestageLibrary(
  library: WidgetLibrary.custom('apps_examples.ui'),
  capabilityVersion: 1,
)
const restageUiLibrary = 0;
''';

const _pip = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Fired when a pip is tapped.
const pipTapped = SurfaceEvent<void>('pipTapped');

/// A pip.
@RestageWidget()
class Pip extends StatelessWidget {
  /// Creates a pip.
  const Pip({super.key, required this.label});

  /// The label.
  final String label;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: context.surfaceEvent(pipTapped),
        child: Text(label),
      );
}
''';

String _surface(String annotation, String placement) =>
    '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import '../widgets/close_action.dart';

part 'restage.generated/notice.restage.g.dart';

$annotation
final class Notice extends StatelessWidget {
  const Notice({super.key});

  @override
  Widget build(BuildContext context) =>
      const Column(children: [Text('Hi'), $placement]);
}
''';

const _screen = "@Screen(id: 'notice', surface: Surface.general)";
const _lifecycle = {
  'restageLifecycle_dismiss',
  'restageLifecycle_presentation',
};

void main() {
  // An inlined widget's tap is the surface's own, so it carries a route.
  test(
    'a catalog widget from another file that inlines measures its tap',
    () async {
      expect(await _measuredEvents(_surface(_screen, 'CloseAction()')), {
        ..._lifecycle,
        'onPressed',
      });
    },
  );

  // A key keeps the widget in the app's factory: its tap is app code and
  // carries no route.
  for (final (name, annotation) in [
    ('screen', _screen),
    ('paywall', '@Paywall()'),
  ]) {
    test('a $name places a keyed catalog widget from another file', () async {
      expect(
        await _measuredEvents(
          _surface(annotation, "CloseAction(key: ValueKey('close'))"),
        ),
        _lifecycle,
      );
    });
  }

  // An event built where it fires has no constant to name it, so the widget
  // renders from its factory, on a legacy screen as on any other.
  for (final (name, annotation, path) in [
    ('screen', _screen, 'lib/features/notice.dart'),
    (
      'legacy screen',
      "@ScreenSource(id: 'notice')",
      'lib/onboarding/screens/notice.dart',
    ),
  ]) {
    test('a $name places a widget firing an event built in place', () async {
      final compiled = await _compile(
        _surface(
          annotation,
          'CloseAction()',
        ).replaceFirst("'../widgets/", "'package:apps_examples/widgets/"),
        widgets: {
          'common_events.dart': _events,
          'close_action.dart': _widget.replaceFirst(
            'CommonEvents.close',
            "const SurfaceEvent<void>('close')",
          ),
        },
        path: path,
      );
      expect(compiled.measured, _lifecycle);
    });
  }

  // Measurement asks one handler per callback; the author sees why.
  test('a measured inlined widget with a handler per arm refuses', () async {
    var errors = <String>[];
    await _compile(
      _surface(_screen, 'CloseAction(flag: true)'),
      widgets: {
        'common_events.dart': _events,
        'close_action.dart': _widget
            .replaceFirst(
              'const CloseAction({super.key});',
              'const CloseAction({super.key, required this.flag});\n\n'
                  "  @RestageProperty(description: 'Which.', required: true)\n"
                  '  final bool flag;',
            )
            .replaceFirst(
              'onPressed: context.surfaceEvent(CommonEvents.close),',
              'onPressed: flag\n'
                  '            ? context.surfaceEvent(CommonEvents.close)\n'
                  '            : context.surfaceEvent(CommonEvents.pick, "x"),',
            ),
      },
      refused: (refused) => errors = refused,
    );
    expect(
      errors.join('\n'),
      contains('A measured callback can run only one handler'),
    );
  });

  // A list built by a loop over host data reaches the widget as its items.
  test('a catalog widget fires a value for each item it is given', () async {
    final compiled = await _compile(
      '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import '../widgets/picker.dart';

part 'restage.generated/notice.restage.g.dart';

@Screen(id: 'notice', surface: Surface.general)
final class Notice extends StatelessWidget {
  const Notice({super.key, required this.plans});

  final List<String> plans;

  @override
  Widget build(BuildContext context) =>
      Picker(options: [for (final plan in plans) plan]);
}
''',
      widgets: {
        'common_events.dart': _events,
        'picker.dart': _picker
            .replaceFirst(
              'const Picker({super.key, required this.label});',
              'const Picker({super.key, required this.options});',
            )
            .replaceFirst(
              "  @RestageProperty(description: 'The label.', required: true)\n"
                  '  final String label;',
              '  @RestageProperty(\n'
                  "    description: 'The options.',\n"
                  '    required: true,\n'
                  '  )\n'
                  '  final List<String> options;',
            )
            .replaceFirst(
              'TextButton(\n'
                  '        onPressed: '
                  'context.surfaceEvent(CommonEvents.pick, label),\n'
                  '        child: Text(label),\n'
                  '      );',
              'Column(children: ['
                  '''
        for (final option in options)
          TextButton(
            onPressed: context.surfaceEvent(CommonEvents.pick, option),
            child: Text(option),
          ),
      ]);''',
            ),
      },
    );
    expect(
      compiled.contract,
      contains(
        '{"id":"pick","arguments":'
        '{"encoding":"value","shape":{"kind":"string"}}}',
      ),
    );
  });

  // A widget its library exports, firing a top-level event constant, inlines:
  // its tap is measured and the event joins the surface's contract.
  for (final (name, annotation) in [
    ('screen', _screen),
    ('paywall', '@Paywall()'),
  ]) {
    test(
      'a $name inlines an exported widget firing a top-level event',
      () async {
        final surface = _surface(annotation, "Pip(label: 'a')")
            .replaceFirst(
              "'../widgets/close_action.dart'",
              "'../widgets/ui.dart'",
            )
            .replaceFirst('const Column', 'Column');
        final compiled = await _compile(
          surface,
          widgets: {'ui.dart': _ui, 'pip.dart': _pip},
        );
        expect(compiled.measured, {..._lifecycle, 'onPressed'});
        if (name == 'screen') {
          expect(compiled.contract, contains('{"id":"pipTapped"'));
        }
      },
    );
  }

  // A value read from the widget's own field takes the type of what each
  // placement passes.
  test('a catalog widget fires a value read from its field', () async {
    final compiled = await _compile(
      _surface(_screen, "Picker(label: 'b')").replaceFirst(
        "'../widgets/close_action.dart'",
        "'../widgets/picker.dart'",
      ),
      widgets: {'common_events.dart': _events, 'picker.dart': _picker},
    );
    expect(compiled.measured, {..._lifecycle, 'onPressed'});
    expect(
      compiled.contract,
      contains(
        '{"id":"pick","arguments":'
        '{"encoding":"value","shape":{"kind":"string"}}}',
      ),
    );
  });
}

const _picker = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'common_events.dart';

@RestageLibrary(
  library: WidgetLibrary.custom('acme.ui'),
  capabilityVersion: 1,
)
const restageLibrary = 0;

@RestageWidget(
  name: 'Picker',
  library: WidgetLibrary.custom('acme.ui'),
  category: WidgetCategory.decoration,
  description: 'A picker.',
)
class Picker extends StatelessWidget {
  const Picker({super.key, required this.label});

  @RestageProperty(description: 'The label.', required: true)
  final String label;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: context.surfaceEvent(CommonEvents.pick, label),
        child: Text(label),
      );
}
''';

Future<Set<String>> _measuredEvents(
  String surface, {
  Map<String, String> widgets = const {
    'common_events.dart': _events,
    'close_action.dart': _widget,
  },
}) async => (await _compile(surface, widgets: widgets)).measured;

Future<({Set<String> measured, String contract})> _compile(
  String surface, {
  Map<String, String> widgets = const {
    'common_events.dart': _events,
    'close_action.dart': _widget,
  },
  String path = 'lib/features/notice.dart',
  void Function(List<String> errors)? refused,
}) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: _package,
  );
  final result = await testBuilders(
    [
      restageSourceRosterBuilder(BuilderOptions.forRoot),
      userCatalogJsonBuilder(BuilderOptions.empty),
      onboardingScreenBuilder(BuilderOptions.empty),
      restageCodegenBuilder(BuilderOptions.empty),
      restagePackageSurfaceCompilerBuilder(
        const BuilderOptions({
          kMeasurementMinimumClientOption: 1,
          kMeasurementPrivacyPolicyRevisionOption: 'privacy.automatic-v1',
          kMeasurementCollectionBudgetRevisionOption: 'budget.automatic-v1',
        }, isRoot: true),
      ),
    ],
    {
      for (final MapEntry(:key, :value) in widgets.entries)
        '$_package|lib/widgets/$key': value,
      '$_package|$path': surface,
    },
    rootPackage: _package,
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  if (refused != null) {
    expect(result.succeeded, isFalse);
    refused(result.errors.toList());
    return (measured: <String>{}, contract: '');
  }
  expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
  final output =
      jsonDecode(
            readerWriter.testing.readString(
              AssetId(_package, kRestageMeasurementCompilerOutputPath),
            ),
          )
          as Map<String, Object?>;
  final bundle =
      jsonDecode(
            readerWriter.testing.readString(
              AssetId(_package, kRestageSurfacePublicationCompilerBundlePath),
            ),
          )
          as Map<String, Object?>;
  final publications = (bundle['manifest']! as Map)['publications']! as List;
  final entry = publications.length == 1 ? publications.single as Map : null;
  return (
    measured: {
      for (final node in output['ledgerNodes']! as List)
        for (final event in (node as Map)['events']! as List)
          (event as Map)['sourceEventIdentity'] as String,
    },
    contract: jsonEncode((entry?['publication'] as Map?)?['eventContract']),
  );
}
