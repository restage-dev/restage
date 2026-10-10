// A value callback that assigns a State field writes a screen-local value;
// reads of the field read it back.

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

import 'helpers.dart';
import 'measurement/measurement_fixture_helpers.dart';

const _fixtureRoot = 'test/fixtures/local_values';
const _package = 'apps_examples';
const _fixtureDartPaths = <String>[
  'lib/surfaces/feedback_note.dart',
  'lib/paywalls/volume_offer.dart',
];

void main() {
  late _Compiled compiled;

  setUpAll(() async {
    compiled = await _compileFixture();
  });

  test('both fixtures compile', () {
    expect(compiled.output.valid, isTrue,
        reason: compiled.output.errors.join('\n'));
  });

  test('generated screen and paywall parts opt out of lints', () {
    for (final path in [
      'lib/surfaces/restage.generated/feedback_note.restage.g.dart',
      'lib/paywalls/restage.generated/volume_offer.restage.g.dart',
    ]) {
      final part = compiled.readerWriter.testing.readString(
        AssetId(_package, path),
      );
      expect(
        part.split('\n').take(4),
        contains('// ignore_for_file: type=lint'),
        reason: path,
      );
    }
  });

  test('a text value callback writes a local value', () {
    final library = compiled.library('lib/surfaces/feedback_note.dart');
    final writes = rfwEventHandlers(library)
        .whereType<fmt.EventHandler>()
        .where((handler) => handler.eventName == 'restage.local.set')
        .toList();
    expect(writes, hasLength(2));
    expect(
      writes.map((write) => write.eventArguments),
      unorderedEquals(<Object?>[
        <String, Object?>{'key': 'note'},
        <String, Object?>{'key': 'note', 'value': ''},
      ]),
    );
    final taps = rfwEventHandlers(library)
        .whereType<fmt.EventHandler>()
        .where((handler) =>
            handler.eventName == kMeasurementPublicationTapEventNameV1)
        .toList();
    expect(taps, hasLength(1), reason: 'the Clear tap stays measured');
    final references = _references(library);
    expect(references, contains('data.local.note'));
    expect(references, isNot(contains('state.note')));
  });

  test('a switch value callback writes a local value', () {
    final library = compiled.library('lib/paywalls/volume_offer.dart');
    final writes = rfwEventHandlers(library)
        .whereType<fmt.EventHandler>()
        .where((handler) => handler.eventName == 'restage.local.set')
        .toList();
    expect(writes, hasLength(1));
    expect(
      writes.single.eventArguments,
      <String, Object?>{'key': 'reminders'},
    );
  });
}

Set<String> _references(fmt.RemoteWidgetLibrary library) {
  final found = <String>{};
  void visit(Object? value) {
    switch (value) {
      case fmt.DataReference(:final parts):
        found.add('data.${parts.join('.')}');
      case fmt.StateReference(:final parts):
        found.add('state.${parts.join('.')}');
      case fmt.ConstructorCall(:final arguments):
        visit(arguments);
      case fmt.EventHandler(:final eventArguments):
        visit(eventArguments);
      case fmt.Switch(:final input, :final outputs):
        visit(input);
        visit(outputs.values);
      case fmt.Loop(:final input, :final output):
        visit(input);
        visit(output);
      case Map<Object?, Object?>():
        visit(value.values);
      case Iterable<Object?>():
        for (final item in value) {
          visit(item);
        }
    }
  }

  for (final widget in library.widgets) {
    visit(widget.initialState);
    visit(widget.root);
  }
  return found;
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

  fmt.RemoteWidgetLibrary library(String sourcePath) {
    final bundle = RestageBundleCodec.decode(
      readerWriter.testing.readBytes(
        AssetId(
          _package,
          'assets/restage/bundles/${p.withoutExtension(sourcePath)}.rsbundle',
        ),
      ),
    );
    return fmt.decodeLibraryBlob(
      bundle.entries
          .singleWhere((entry) => entry.logicalPath.endsWith('.rfw'))
          .bytes,
    );
  }

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
