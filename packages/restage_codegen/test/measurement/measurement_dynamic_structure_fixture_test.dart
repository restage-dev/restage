// Surfaces whose widget structure varies at run time still publish
// Measurement: each branch or template is its own static occurrence.

import 'dart:io';

import 'package:build/build.dart';
import 'package:path/path.dart' as p;
import 'package:restage_codegen/builder.dart';
import 'package:restage_codegen/src/measurement/measurement_compiler_output.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as fmt;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../helpers.dart';
import 'measurement_fixture_helpers.dart';

const _fixtureRoot = 'test/fixtures/measurement_dynamic_structure';
const _package = 'apps_examples';
const _fixtureDartPaths = <String>[
  'lib/widgets/dynamic_widgets.dart',
  'lib/paywalls/conditional_plan.dart',
  'lib/paywalls/tear_off_plan.dart',
  'lib/paywalls/combined_condition.dart',
  'lib/paywalls/spread_plan.dart',
  'lib/surfaces/host_rows.dart',
  'lib/surfaces/badge_card.dart',
  'lib/surfaces/label_table.dart',
  'lib/surfaces/pinned_header.dart',
];

const _column = 'package:flutter/src/widgets/basic.dart#Column';
const _gesture =
    'package:flutter/src/widgets/gesture_detector.dart#GestureDetector';
const _filled = 'package:flutter/src/material/filled_button.dart#FilledButton';
const _text = 'package:flutter/src/material/text_button.dart#TextButton';
const _inkWell = 'package:flutter/src/material/ink_well.dart#InkWell';
const _outlined =
    'package:flutter/src/material/outlined_button.dart#OutlinedButton';

void main() {
  late _Compiled compiled;

  setUpAll(() async {
    compiled = await _compileFixture();
  });

  test('no dynamic surface compiles unmeasured', () {
    expect(compiled.output.valid, isTrue,
        reason: compiled.output.errors.join('\n'));
    expect(
      compiled.log
          .split('\n')
          .where((line) => line.contains('compiles unmeasured')),
      everyElement(contains('combined_condition')),
    );
    expect(
      compiled.output.publications
          .map((publication) => publication.selector.slug),
      unorderedEquals(<String>[
        'conditional_plan',
        'tear_off_plan',
        'badge_card',
        'label_table',
        'pinned_header',
        'spread_plan',
        'host_rows',
      ]),
    );
  });

  test('a callback under a combined condition leaves the surface unmeasured',
      () {
    expect(
      compiled.log,
      contains('Measurement is unavailable for paywall/combined_condition: '),
    );
    expect(compiled.log, contains('combined with && or ||'));
  });

  test('each branch of a conditional child is its own occurrence', () {
    const source =
        'package:apps_examples/paywalls/conditional_plan.dart#ConditionalPlan';
    const element = '$source|child:$_column:$_column.children[0]';
    expect(
      compiled.routedKeys(source),
      containsAll(<String>[
        '$element|cond:then|widget:$_filled\u0000onPressed',
        '$element|cond:else|widget:$_outlined\u0000onPressed',
      ]),
    );
    expect(compiled.routeCount('conditional_plan'), greaterThanOrEqualTo(3));
  });

  test('a run-time collection-if spreading a list guards each element', () {
    const source = 'package:apps_examples/paywalls/spread_plan.dart#SpreadPlan';
    const element = '$source|child:$_column:$_column.children[0]';
    expect(
      compiled.routedKeys(source),
      <String>{
        '$element|collection:listElement[0]|collection:selectedThen[0]|'
            'collection:listElement[1]|widget:$_filled\u0000onPressed',
        '$element|collection:listElement[0]|collection:selectedElse[1]|'
            'widget:$_outlined\u0000onPressed',
        '$source|child:$_column:$_column.children[1]|widget:$_text'
            '\u0000onPressed',
      },
    );
    expect(compiled.routeCount('spread_plan'), greaterThanOrEqualTo(3));
  });

  test('a custom widget spreading under a run-time collection-if inlines', () {
    const source =
        'package:apps_examples/surfaces/pinned_header.dart#PinnedHeaderScreen';
    const header = 'package:apps_examples/widgets/dynamic_widgets.dart'
        '#PinnedHeader';
    expect(
      compiled.routedKeys(source),
      <String>{
        '$source|child:$_column:$_column.children[0]|inline:$header|'
            'inlinedBody:$header|widget:$_gesture\u0000onTap',
      },
    );
  });

  test('a run-time collection-for measures its template once', () {
    const source = 'package:apps_examples/surfaces/host_rows.dart#HostRows';
    expect(
      compiled.routedKeys(source),
      <String>{
        '$source|child:$_column:$_column.children[0]|'
            'collection:listElement[0]|collection:loopTemplate[0]|'
            'widget:$_inkWell\u0000onTap',
      },
    );
  });

  test('a State method tear-off routes through the measure-only tap', () {
    const source =
        'package:apps_examples/paywalls/tear_off_plan.dart#TearOffPlan';
    expect(
      compiled.routedKeys(source),
      contains(
        '$source|child:$_column:$_column.children[0]|widget:$_gesture'
        '\u0000onTap',
      ),
    );
    final handlers = compiled.eventHandlers('lib/paywalls/tear_off_plan.dart');
    final taps = handlers
        .whereType<fmt.EventHandler>()
        .where((handler) =>
            handler.eventName == kMeasurementPublicationTapEventNameV1)
        .toList();
    expect(taps, hasLength(1));
    expect(
      taps.single.eventArguments.keys,
      <String>[kMeasurementPublicationRouteArgumentKeyV1],
    );
    expect(handlers.whereType<fmt.SetStateHandler>(), hasLength(1));
  });

  for (final (slug, className, widget) in <(String, String, String)>[
    ('badge_card', 'BadgeCardScreen', 'BadgeCard'),
    ('label_table', 'LabelTableScreen', 'LabelTable'),
  ]) {
    test(
        'a custom widget with run-time collection flow in $widget is one '
        'opaque occurrence', () {
      final source = 'package:apps_examples/surfaces/$slug.dart#$className';
      final custom =
          'package:apps_examples/widgets/dynamic_widgets.dart#$widget';
      expect(
        compiled.routedKeys(source),
        <String>{
          '$source|child:$_column:$_column.children[0]|widget:$custom'
              '\u0000onTap',
        },
      );
      expect(
        compiled.nodeKeys(source).where((key) => key.contains('inlinedBody')),
        isEmpty,
      );
    });
  }
}

final class _Compiled {
  const _Compiled(this.output, this.log, this.readerWriter);

  final RestageMeasurementCompilerOutputV1 output;
  final String log;
  final TestReaderWriter readerWriter;

  Iterable<String> nodeKeys(String source) => output.ledgerNodes
      .where((node) => node.structuralOccurrenceKey.startsWith('$source|'))
      .map((node) => node.structuralOccurrenceKey);

  Set<String> routedKeys(String source) => {
        for (final node in output.ledgerNodes)
          if (node.structuralOccurrenceKey.startsWith('$source|'))
            for (final event in node.events)
              if (event.active)
                '${node.structuralOccurrenceKey}\u0000'
                    '${event.sourceEventIdentity.value}',
      };

  int routeCount(String slug) => output.publications
      .singleWhere((publication) => publication.selector.slug == slug)
      .routePlan
      .routes
      .length;

  List<fmt.AnyEventHandler> eventHandlers(String sourcePath) {
    final bundle = RestageBundleCodec.decode(
      readerWriter.testing.readBytes(
        AssetId(
          _package,
          'assets/restage/bundles/${p.withoutExtension(sourcePath)}.rsbundle',
        ),
      ),
    );
    final blob = bundle.entries.singleWhere(
      (entry) => entry.logicalPath.endsWith('.rfw'),
    );
    return rfwEventHandlers(fmt.decodeLibraryBlob(blob.bytes));
  }
}

Future<_Compiled> _compileFixture() async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: _package,
  );
  final logs = <String>[];
  final result = await testBuilders(
    [
      restageSourceRosterBuilder(
        _builderOptions('restage_codegen:restage_source_roster'),
      ),
      userCatalogJsonBuilder(BuilderOptions.empty),
      restagePackageSurfaceCompilerBuilder(
        _builderOptions('restage_codegen:restage_package_surface_compiler'),
      ),
      restageGeneratedDartBuilder(
        _builderOptions('restage_codegen:generated_dart'),
      ),
      restageOutputsBuilder(_builderOptions('restage_codegen:outputs')),
    ],
    {
      for (final path in _fixtureDartPaths)
        '$_package|$path': File(p.join(_fixtureRoot, path)).readAsStringSync(),
    },
    rootPackage: _package,
    readerWriter: readerWriter,
    flattenOutput: true,
    onLog: (record) => logs.add(record.message),
  );
  expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
  return _Compiled(
    RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
      readerWriter.testing.readBytes(
        AssetId(_package, kRestageMeasurementCompilerOutputPath),
      ),
    ),
    logs.join('\n'),
    readerWriter,
  );
}

BuilderOptions _builderOptions(String builderKey) {
  final document = loadYaml(
    File(p.join(_fixtureRoot, 'build.yaml')).readAsStringSync(),
  );
  final root = _yamlMap(document, 'build.yaml');
  final targets = _yamlMap(root['targets'], 'build.yaml.targets');
  final defaultTarget = _yamlMap(
    targets[r'$default'],
    r'build.yaml.targets.$default',
  );
  final builders = _yamlMap(
    defaultTarget['builders'],
    r'build.yaml.targets.$default.builders',
  );
  final builder = _yamlMap(builders[builderKey], 'builder $builderKey');
  final options = _yamlMap(builder['options'], 'builder $builderKey options');
  return BuilderOptions(
    {
      for (final entry in options.entries)
        _stringKey(entry.key, 'builder $builderKey option'):
            _yamlValue(entry.value),
    },
    isRoot: true,
  );
}

Map<Object?, Object?> _yamlMap(Object? value, String path) {
  if (value is! YamlMap) throw StateError('$path must be a map.');
  return value;
}

Object? _yamlValue(Object? value) => switch (value) {
      YamlMap() => {
          for (final entry in value.entries)
            entry.key as String: _yamlValue(entry.value),
        },
      YamlList() => [for (final entry in value) _yamlValue(entry)],
      _ => value,
    };

String _stringKey(Object? value, String path) {
  if (value is! String) throw StateError('$path key must be a string.');
  return value;
}
