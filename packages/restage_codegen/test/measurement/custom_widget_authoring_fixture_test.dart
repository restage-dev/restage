// Custom widgets an app wraps its surfaces in stay measurable.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:build/build.dart';
import 'package:path/path.dart' as p;
import 'package:restage_codegen/builder.dart';
import 'package:restage_codegen/src/measurement/measurement_compiler_output.dart';
import 'package:restage_codegen/src/measurement/measurement_route_emission.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as fmt;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../helpers.dart';

const _fixtureRoot = 'test/fixtures/custom_widget_authoring';
const _package = 'apps_examples';
const _fixtureDartPaths = <String>[
  'lib/widgets/app_widgets.dart',
  'lib/paywalls/grounded_offer.dart',
  'lib/paywalls/plan_picker.dart',
];

void main() {
  test(
      'taps inside an opaque custom wrapper are measured and complete the '
      'paywall', () async {
    final compiled = await _compileFixture();
    expect(compiled.succeeded, isTrue, reason: compiled.log);
    expect(compiled.log, isNot(contains('Measurement is unavailable')));
    final publication = compiled.output!.publications
        .singleWhere((entry) => entry.selector.slug == 'grounded_offer');
    final taps = publication.routePlan.routes
        .where((route) => route.orderedCaptureV1?.lifecycleChannel == null)
        .toList();
    expect(taps, hasLength(2), reason: 'AppButton.onPressed and the close tap');
    expect(
      taps.where((route) => route.orderedCaptureV1!.completesSurfaceV1),
      hasLength(1),
    );
    final blob = compiled.handoff!.manifest!.publications
        .singleWhere((entry) => entry.publication.slug == 'grounded_offer')
        .artifacts
        .singleWhere(
          (artifact) =>
              artifact.role == SurfacePublicationArtifactRole.screenBlob,
        );
    final library = fmt.decodeLibraryBlob(
      Uint8List.fromList(compiled.handoff!.artifacts[blob.path]!),
    );
    expect(
      _routeCarriers(library),
      hasLength(2),
      reason: 'The emitted taps carry the routes discovery planned.',
    );
    final legal =
        _calls(library).singleWhere((call) => call.name == 'AppLegal');
    expect(legal.arguments['paragraphs'], isA<fmt.DataReference>());
    expect(legal.arguments['widths'], [1.0, 2.5]);
  });

  test('surfaceEvent fires a standalone paywall event from a State class',
      () async {
    final compiled = await _compileFixture();
    expect(compiled.succeeded, isTrue, reason: compiled.log);
    final blob = compiled.handoff!.manifest!.publications
        .singleWhere((entry) => entry.publication.slug == 'plan_picker')
        .artifacts
        .singleWhere(
          (artifact) =>
              artifact.role == SurfacePublicationArtifactRole.screenBlob,
        );
    final library = fmt.decodeLibraryBlob(
      Uint8List.fromList(compiled.handoff!.artifacts[blob.path]!),
    );
    final text = _calls(library).singleWhere((call) => call.name == 'AppText');
    expect(text.arguments['text'], isA<List<Object?>>());
    final events = _events(library);
    expect(
      events.map((event) => event.eventName),
      containsAll(['subscribe', 'close']),
    );
    expect(
      events
          .singleWhere((event) => event.eventName == 'subscribe')
          .eventArguments['value'],
      'yearly',
    );
    final taps = compiled.output!.publications
        .singleWhere((entry) => entry.selector.slug == 'plan_picker')
        .routePlan
        .routes
        .where((route) => route.orderedCaptureV1?.lifecycleChannel == null);
    expect(taps, hasLength(2));
  });
}

Future<
    ({
      bool succeeded,
      String log,
      RestageMeasurementCompilerOutputV1? output,
      RestageSurfacePublicationBundle? handoff,
    })> _compileFixture() async {
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
  final outputId = AssetId(_package, kRestageMeasurementCompilerOutputPath);
  final output = result.succeeded
      ? RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
          readerWriter.testing.readBytes(outputId),
        )
      : null;
  return (
    succeeded: result.succeeded,
    log: [...logs, ...result.errors].join('\n'),
    output: output,
    handoff: result.succeeded
        ? RestageSurfacePublicationBundle.fromJson(
            jsonDecode(
              readerWriter.testing.readString(
                AssetId(_package, kRestageSurfacePublicationCompilerBundlePath),
              ),
            ),
          )
        : null,
  );
}

BuilderOptions _builderOptions(String builderKey) {
  final document = loadYaml(
    File(p.join(_fixtureRoot, 'build.yaml')).readAsStringSync(),
  ) as YamlMap;
  final options =
      ((((document['targets'] as YamlMap)[r'$default'] as YamlMap)['builders']
          as YamlMap)[builderKey] as YamlMap)['options'] as YamlMap;
  return BuilderOptions(
    {for (final entry in options.entries) entry.key as String: entry.value},
    isRoot: true,
  );
}

List<String> _routeCarriers(fmt.RemoteWidgetLibrary library) => [
      for (final handler in _events(library))
        if (handler.eventArguments[kMeasurementRouteArgumentKeyV1]
            case final String carrier)
          carrier,
    ];

List<fmt.EventHandler> _events(fmt.RemoteWidgetLibrary library) {
  final handlers = <fmt.EventHandler>[];
  void visit(Object? value) {
    switch (value) {
      case final fmt.WidgetDeclaration declaration:
        visit(declaration.initialState);
        visit(declaration.root);
      case final fmt.EventHandler handler:
        handlers.add(handler);
        visit(handler.eventArguments);
      case final fmt.ConstructorCall call:
        visit(call.arguments);
      case final fmt.Switch switchNode:
        visit(switchNode.input);
        switchNode.outputs.values.forEach(visit);
      case final Map<Object?, Object?> map:
        map.values.forEach(visit);
      case final List<Object?> list:
        list.forEach(visit);
    }
  }

  library.widgets.forEach(visit);
  return handlers;
}

List<fmt.ConstructorCall> _calls(fmt.RemoteWidgetLibrary library) {
  final calls = <fmt.ConstructorCall>[];
  void visit(Object? value) {
    switch (value) {
      case final fmt.WidgetDeclaration declaration:
        visit(declaration.root);
      case final fmt.ConstructorCall call:
        calls.add(call);
        visit(call.arguments);
      case final fmt.Switch switchNode:
        switchNode.outputs.values.forEach(visit);
      case final Map<Object?, Object?> map:
        map.values.forEach(visit);
      case final List<Object?> list:
        list.forEach(visit);
    }
  }

  library.widgets.forEach(visit);
  return calls;
}
