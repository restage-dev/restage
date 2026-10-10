// Free text typed into a survey reaches the host only through the flow's
// captured result, never measurement.

import 'dart:convert';
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

const _fixtureRoot = 'test/fixtures/free_text_survey';
const _package = 'apps_examples';
const _fixtureDartPaths = <String>[
  'lib/surfaces/exit_note.dart',
  'lib/surfaces/exit_note_flow.dart',
];

void main() {
  late _Compiled compiled;

  setUpAll(() async {
    compiled = await _compileFixture();
  });

  test('generated screen and flow parts opt out of lints', () {
    for (final stem in ['exit_note', 'exit_note_flow']) {
      final part = compiled.readerWriter.testing.readString(
        AssetId(
            _package, 'lib/surfaces/restage.generated/$stem.restage.g.dart'),
      );
      expect(part, contains('// ignore_for_file: type=lint'), reason: stem);
    }
  });

  test('the survey compiles measured', () {
    expect(compiled.output.valid, isTrue,
        reason: compiled.output.errors.join('\n'));
    expect(
      compiled.output.publications
          .map((publication) => publication.selector.slug),
      containsAll(<String>['exit_note', 'exit_note_survey']),
    );
  });

  test('typed text becomes a local value and rides the Send event', () {
    final libraries = compiled.libraries('lib/surfaces/exit_note.dart');
    expect(libraries, isNotEmpty);
    for (final library in libraries) {
      final handlers = rfwEventHandlers(library).whereType<fmt.EventHandler>();
      final writes = handlers
          .where((handler) => handler.eventName == 'restage.local.set')
          .toList();
      expect(writes, hasLength(1));
      expect(writes.single.eventArguments, <String, Object?>{'key': 'note'});
      expect(
        handlers.where((handler) => handler.eventName == 'submit'),
        hasLength(1),
      );
      expect(_references(library), contains('data.local.note'));
    }
  });

  test('the note is never a measured answer', () {
    for (final publication in compiled.output.publications) {
      for (final route in publication.routePlan.routes) {
        expect(route.orderedCaptureV1?.declaredAnswerV1, isNull);
      }
    }
    final interactions = compiled.output.publications
        .singleWhere(
          (publication) => publication.selector.slug == 'exit_note_survey',
        )
        .routePlan
        .routes
        .where((route) => route.orderedCaptureV1?.lifecycleChannel == null);
    expect(interactions, hasLength(1), reason: 'only the Send tap');
  });

  test('the flow captures the note into its terminal result only', () {
    final bundle = RestageBundleCodec.decode(
      compiled.readerWriter.testing.readBytes(
        AssetId(
          _package,
          'assets/restage/bundles/lib/surfaces/exit_note_flow.rsbundle',
        ),
      ),
    );
    final document = jsonDecode(
      utf8.decode(
        bundle.entries
            .singleWhere((entry) => entry.logicalPath.endsWith('.flow.json'))
            .bytes,
      ),
    ) as Map<String, Object?>;
    final outbound = document['outbound']! as Map<String, Object?>;
    final terminal = outbound['terminalResult']! as Map<String, Object?>;
    expect(
        (terminal['fields']! as Map<String, Object?>).keys, <String>['note']);
    expect(outbound['surveyAnswers'] ?? const <String, Object?>{}, isEmpty);
    expect(jsonEncode(document['states']), contains('"note"'));
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

  List<fmt.RemoteWidgetLibrary> libraries(String sourcePath) {
    final bundle = RestageBundleCodec.decode(
      readerWriter.testing.readBytes(
        AssetId(
          _package,
          'assets/restage/bundles/${p.withoutExtension(sourcePath)}.rsbundle',
        ),
      ),
    );
    return [
      for (final entry in bundle.entries)
        if (entry.logicalPath.endsWith('.rfw'))
          fmt.decodeLibraryBlob(entry.bytes),
    ];
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
