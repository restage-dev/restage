// Taps inside repeated elements carry the element's identity: a static
// element's literal key or position, or a run-time element's position.

import 'dart:io';
import 'dart:typed_data';

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

const _fixtureRoot = 'test/fixtures/measurement_item_identity';
const _package = 'apps_examples';
const _fixtureDartPaths = <String>[
  'lib/surfaces/host_rows.dart',
  'lib/surfaces/filtered_rows.dart',
  'lib/surfaces/conditional_tags.dart',
  'lib/surfaces/host_tags.dart',
  'lib/surfaces/static_plans.dart',
  'lib/surfaces/free_text.dart',
  'lib/surfaces/nested_static_in_runtime.dart',
  'lib/surfaces/nested_runtime_in_static.dart',
  'lib/paywalls/toggle_plans.dart',
  'lib/paywalls/completing_offer.dart',
];

void main() {
  late _Compiled compiled;

  setUpAll(() async {
    compiled = await _compileFixture();
  });

  test('every fixture surface compiles measured', () {
    expect(compiled.output.valid, isTrue,
        reason: compiled.output.errors.join('\n'));
    expect(
      compiled.output.publications
          .map((publication) => publication.selector.slug),
      unorderedEquals(<String>[
        'host_rows',
        'filtered_rows',
        'conditional_tags',
        'host_tags',
        'static_plans',
        'toggle_plans',
        'free_text',
        'completing_offer',
        'nested_static_in_runtime',
        'nested_runtime_in_static',
      ]),
    );
  });

  test('a run-time loop over objects carries the element position', () {
    expect(compiled.itemRouteCount('host_rows'), 1);
    final taps = compiled.measuredHandlers('lib/surfaces/host_rows.dart');
    expect(taps, hasLength(1));
    final item =
        taps.single.eventArguments[kMeasurementPublicationItemArgumentKeyV1];
    expect(item, isA<fmt.LoopReference>());
    expect((item! as fmt.LoopReference).parts, <Object>['__restage_index']);
  });

  test('a filtered loop preserves its source item and compiled runtime fixture',
      () {
    expect(compiled.itemRouteCount('filtered_rows'), 1);
    final taps = compiled.measuredHandlers('lib/surfaces/filtered_rows.dart');
    expect(taps, hasLength(1));
    final item =
        taps.single.eventArguments[kMeasurementPublicationItemArgumentKeyV1]!
            as fmt.LoopReference;
    expect(item.loop, 1);
    expect(item.parts, <Object>['__restage_index']);

    final blob = compiled.blob('lib/surfaces/filtered_rows.dart');
    final fixture = File(
      '../restage/test/fixtures/collection_if/filtered_rows.rfw',
    );
    if (Platform.environment['REGEN_COLLECTION_IF_FIXTURE'] == '1') {
      fixture.parent.createSync(recursive: true);
      fixture.writeAsBytesSync(blob);
    }
    expect(blob, orderedEquals(fixture.readAsBytesSync()));
  });

  test('a run-time loop over scalars keeps one shared count', () {
    expect(compiled.itemRouteCount('host_tags'), 0);
    final taps = compiled.measuredHandlers('lib/surfaces/host_tags.dart');
    expect(taps, hasLength(1));
    expect(
      taps.single.eventArguments.keys,
      isNot(contains(kMeasurementPublicationItemArgumentKeyV1)),
    );
    expect(compiled.log, contains('interactionItemUnavailable'));
  });

  test('composed loop conditions emit each measured callback once', () {
    expect(compiled.itemRouteCount('conditional_tags'), 0);
    final taps =
        compiled.measuredHandlers('lib/surfaces/conditional_tags.dart');
    expect(taps, hasLength(2));
    final routes = taps.map(
      (tap) => tap.eventArguments[kMeasurementPublicationRouteArgumentKeyV1],
    );
    expect(routes.toSet(), hasLength(2));
  });

  test('static elements share one route and carry their key or position', () {
    expect(compiled.itemRouteCount('static_plans'), 2);
    final items = compiled
        .measuredHandlers('lib/surfaces/static_plans.dart')
        .map((handler) =>
            handler.eventArguments[kMeasurementPublicationItemArgumentKeyV1])
        .toList();
    expect(
      items,
      unorderedEquals(<Object?>['yearly', 'monthly', '1', '2', null]),
    );
  });

  test('a state update in a static element pairs an item-bearing tap', () {
    expect(compiled.itemRouteCount('toggle_plans'), 1);
    final taps = compiled
        .measuredHandlers('lib/paywalls/toggle_plans.dart')
        .where((handler) =>
            handler.eventName == kMeasurementPublicationTapEventNameV1)
        .toList();
    expect(
      taps.map((handler) =>
          handler.eventArguments[kMeasurementPublicationItemArgumentKeyV1]),
      unorderedEquals(<Object?>['1', '2']),
    );
  });

  test('typed text never reaches a measured route', () {
    final routes = compiled.output.publications
        .singleWhere((publication) => publication.selector.slug == 'free_text')
        .routePlan
        .routes
        .where((route) => route.orderedCaptureV1?.lifecycleChannel == null);
    expect(routes, hasLength(1));
    final handlers = compiled
        .eventHandlers('lib/surfaces/free_text.dart')
        .whereType<fmt.EventHandler>()
        .toList();
    expect(
      handlers
          .where((handler) =>
              handler.eventName == 'typed' || handler.eventName == 'sent')
          .map((handler) => handler.eventArguments.keys),
      everyElement(
        everyElement(
          isNot(startsWith(kMeasurementPublicationReservedArgumentPrefixV1)),
        ),
      ),
    );
    expect(
      handlers.where((handler) =>
          handler.eventName == 'typed' || handler.eventName == 'sent'),
      hasLength(4),
    );
  });

  test('a completing event flags only its own route', () {
    final routes = compiled.output.publications
        .singleWhere(
          (publication) => publication.selector.slug == 'completing_offer',
        )
        .routePlan
        .routes
        .where((route) => route.orderedCaptureV1?.lifecycleChannel == null)
        .toList();
    expect(routes, hasLength(2));
    expect(
      routes.where((route) => route.orderedCaptureV1!.completesSurfaceV1),
      hasLength(1),
    );
  });

  for (final (slug, path) in [
    ('nested_static_in_runtime', 'lib/surfaces/nested_static_in_runtime.dart'),
    ('nested_runtime_in_static', 'lib/surfaces/nested_runtime_in_static.dart'),
  ]) {
    test('a tap in nested loops of different kinds is unmeasured ($slug)', () {
      final routes = compiled.output.publications
          .singleWhere((publication) => publication.selector.slug == slug)
          .routePlan
          .routes
          .where((route) => route.orderedCaptureV1?.lifecycleChannel == null);
      expect(routes, isEmpty);
      expect(
        compiled
            .eventHandlers(path)
            .whereType<fmt.EventHandler>()
            .expand((handler) => handler.eventArguments.keys),
        everyElement(
          isNot(startsWith(kMeasurementPublicationReservedArgumentPrefixV1)),
        ),
      );
      expect(
        compiled.log,
        contains('nested loops of different kinds cannot tell their items '
            'apart'),
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

  int itemRouteCount(String slug) => output.publications
      .singleWhere((publication) => publication.selector.slug == slug)
      .routePlan
      .routes
      .where((route) => route.orderedCaptureV1?.interactionItemsV1 ?? false)
      .length;

  List<fmt.EventHandler> measuredHandlers(String sourcePath) => eventHandlers(
        sourcePath,
      )
          .whereType<fmt.EventHandler>()
          .where((handler) => handler.eventArguments
              .containsKey(kMeasurementPublicationRouteArgumentKeyV1))
          .toList();

  List<fmt.AnyEventHandler> eventHandlers(String sourcePath) {
    return rfwEventHandlers(fmt.decodeLibraryBlob(blob(sourcePath)));
  }

  Uint8List blob(String sourcePath) {
    final bundle = RestageBundleCodec.decode(
      readerWriter.testing.readBytes(
        AssetId(
          _package,
          'assets/restage/bundles/${p.withoutExtension(sourcePath)}.rsbundle',
        ),
      ),
    );
    return bundle.entries
        .singleWhere(
          (entry) => entry.logicalPath.endsWith('.rfw'),
        )
        .bytes;
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
    verbose: true,
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
