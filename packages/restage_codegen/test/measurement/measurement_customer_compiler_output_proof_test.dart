import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/publication/publication_assembler.dart';
import 'package:restage_cli/src/publication/publication_manifest.dart';
import 'package:restage_cli/src/publication/publication_outputs.dart';
import 'package:restage_codegen/builder.dart';
import 'package:restage_codegen/src/measurement/measurement_compiler_output.dart';
import 'package:restage_codegen/src/measurement/measurement_route_emission.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as fmt;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../helpers.dart';

const _fixtureRoot = 'test/fixtures/measurement_customer';
const _package = 'apps_examples';
const _screenSourcePath = 'lib/surfaces/measurement_showcase.dart';
const _paywallSourcePath = 'lib/paywalls/customer_measurement_upgrade.dart';
const _screenSlug = 'customer_measurement_showcase';
const _paywallSlug = 'customer_measurement_upgrade';
const _screenBundlePath =
    'assets/restage/bundles/lib/surfaces/measurement_showcase.rsbundle';
const _paywallBundlePath =
    'assets/restage/bundles/lib/paywalls/customer_measurement_upgrade.rsbundle';

const _fixtureDartPaths = <String>[
  _screenSourcePath,
  _paywallSourcePath,
  'lib/widgets/measurement_actions.dart',
];

void main() {
  test(
    'customer source graph emits the CLI-consumable Measurement closure',
    () async {
      final compiled = await _compileFixture();
      final compilerOutput = compiled.compilerOutput;
      expect(compilerOutput.valid, isTrue);
      expect(compilerOutput.policy, isNotNull);
      expect(
        compilerOutput.policy!.toJson(),
        <String, Object?>{
          'collectionBudgetRevisionId': 'budget.customer-v1',
          'minimumMeasurementClient': 1,
          'privacyPolicyRevisionId': 'privacy.customer-v1',
        },
      );
      expect(compilerOutput.publications, hasLength(2));

      final screenPublication = compilerOutput.publications.singleWhere(
        (publication) => publication.selector.slug == _screenSlug,
      );
      final paywallPublication = compilerOutput.publications.singleWhere(
        (publication) => publication.selector.slug == _paywallSlug,
      );
      expect(screenPublication.routePlan.routes, hasLength(7));
      expect(paywallPublication.routePlan.routes, hasLength(1));
      expect(
        screenPublication.routePlan.routes
            .map((route) => route.generatedReferenceId.value)
            .toSet(),
        hasLength(7),
      );
      expect(
        utf8.decode(screenPublication.routePlan.canonicalBytes),
        isNot(contains('contentHash')),
        reason: 'Route planning must happen before final artifact hashes.',
      );
      expect(
        utf8.decode(screenPublication.draft.canonicalBytes),
        contains('contentHash'),
      );
      expect(
        screenPublication.draft.routeDraftClosureDigest,
        screenPublication.routePlan.routeDraftClosureDigest,
      );

      final handoff = compiled.handoff;
      expect(handoff.valid, isTrue, reason: handoff.errors.join('\n'));
      expect(
        () => handoff.manifest!.validateArtifactClosure({
          ...handoff.artifacts,
          ...handoff.borrowedArtifacts,
        }),
        returnsNormally,
      );
      final screenManifest = handoff.manifest!.publications.singleWhere(
        (entry) => entry.publication.slug == _screenSlug,
      );
      final paywallManifest = handoff.manifest!.publications.singleWhere(
        (entry) => entry.publication.slug == _paywallSlug,
      );
      final blobArtifact = screenManifest.artifacts.singleWhere(
        (artifact) =>
            artifact.role == SurfacePublicationArtifactRole.screenBlob,
      );
      final blob = handoff.artifacts[blobArtifact.path]!;
      final library = fmt.decodeLibraryBlob(Uint8List.fromList(blob));
      final carriers = _eventHandlers(library)
          .map(
            (handler) => handler.eventArguments[kMeasurementRouteArgumentKeyV1],
          )
          .whereType<String>()
          .toList();
      final compactPointTokens = _presentationPointTokens(library);
      expect(carriers, hasLength(7));
      expect(carriers.toSet(), hasLength(7));
      expect(
        carriers,
        unorderedEquals(
          screenPublication.routePlan.routes.map((route) => route.carrier),
        ),
      );
      expect(compactPointTokens, hasLength(7));
      expect(
        compactPointTokens,
        unorderedEquals([
          for (final carrier in carriers) _compactToken(carrier),
        ]),
        reason:
            'Ordinary Flutter callbacks receive compact tokens without author '
            'metadata or wrapper syntax.',
      );
      for (final bytes in [
        ...handoff.artifacts.values,
        ...handoff.borrowedArtifacts.values,
        ...handoff.ownedOutputs.values,
      ]) {
        final text = utf8.decode(bytes, allowMalformed: true);
        expect(text, isNot(contains(kMeasurementRouteReferenceMarkerKeyV1)));
        expect(text, isNot(contains(kMeasurementRouteReferenceMarkerPrefixV1)));
      }
      expect(
        screenPublication.draft.artifacts
            .singleWhere(
              (artifact) => artifact.artifactKind.value == 'rfw.blob',
            )
            .contentHash
            .hex,
        blobArtifact.contentHash.substring('sha256:'.length),
      );

      expect(
        compiled.measurementIndexBytes,
        orderedEquals(compilerOutput.outputIndexBytes(_package)),
      );
      final measurementIndex = _jsonObject(
        jsonDecode(utf8.decode(compiled.measurementIndexBytes)),
      );
      expect(measurementIndex['kind'], 'restageMeasurementPublicationIndex');
      expect(measurementIndex['package'], _package);
      final measurementEntries =
          (measurementIndex['entries']! as List<Object?>).cast<Object?>();
      expect(measurementEntries, hasLength(2));
      expect(
        _allJsonKeys(measurementIndex).intersection(const {
          'finalRevisionId',
          'publicationRowId',
          'surfaceRevisionId',
          'target',
        }),
        isEmpty,
      );
      final indexedScreen = _jsonObject(
        measurementEntries.singleWhere(
          (entry) =>
              _jsonObject(entry)['selector'] is Map &&
              _jsonObject(_jsonObject(entry)['selector'])['slug'] ==
                  _screenSlug,
        ),
      );
      final indexedDraft = MeasurementPublicationDraftV1.fromCanonicalBytes(
        base64Url.decode(
          base64Url.normalize(indexedScreen['draftBase64']! as String),
        ),
      );
      expect(
        indexedDraft.canonicalBytes,
        orderedEquals(screenPublication.draft.canonicalBytes),
      );

      final outputIndex = RestageOutputIndex.decodeJson(
        utf8.decode(compiled.outputIndexBytes),
      )..validateAgainstManifest(handoff.manifest!);
      expect(
        {
          for (final artifact in screenManifest.artifacts)
            outputIndex.locatorFor(artifact.path).bundle,
        },
        {_screenBundlePath},
      );
      expect(
        {
          for (final artifact in paywallManifest.artifacts)
            outputIndex.locatorFor(artifact.path).bundle,
        },
        {_paywallBundlePath},
      );
      final sourceOwnedBundle = RestageBundleCodec.decode(
        compiled.readBytes(_screenBundlePath),
      );
      expect(sourceOwnedBundle.packageName, _package);
      expect(sourceOwnedBundle.authoredLibraryPath, _screenSourcePath);
      expect(
        sourceOwnedBundle.entries.map((entry) => entry.logicalPath),
        containsAll(screenManifest.artifacts.map((artifact) => artifact.path)),
      );
      expect(
        sourceOwnedBundle.entries,
        contains(
          isA<RestageBundleEntry>().having(
            (entry) => entry.role,
            'role',
            RestageBundleEntryRole.rfwText,
          ),
        ),
      );
      final paywallBundle = RestageBundleCodec.decode(
        compiled.readBytes(_paywallBundlePath),
      );
      expect(paywallBundle.packageName, _package);
      expect(paywallBundle.authoredLibraryPath, _paywallSourcePath);

      final root = await _materializeCliFixture(compiled, outputIndex);
      addTearDown(() async {
        if (root.existsSync()) await root.delete(recursive: true);
      });
      final loaded = await SurfacePublicationManifestLoader().load(
        projectRoot: root,
      );
      final selected = loaded.manifest.publications.singleWhere(
        (entry) => entry.publication.slug == _screenSlug,
      );
      final assembled = await SurfacePublicationAssembler().assemble(
        loaded: loaded,
        entry: selected,
      );
      expect(assembled.selectedBundleAssetPaths, [_screenBundlePath]);
      expect(assembled.hasBundledMeasurementSourceClosure, isTrue);
      expect(assembled.measurementUpload, isNotNull);
      expect(
        assembled.measurementUpload!.proof.measurementPublicationDraft
            .canonicalBytes,
        orderedEquals(screenPublication.draft.canonicalBytes),
      );

      final source = _fixtureSources()['$_package|$_screenSourcePath']!;
      const sourceKey = 'key: UniqueKey(),';
      final changedKeySource = source.replaceFirst(
        sourceKey,
        "key: const ValueKey<String>('host-only-key'),",
      );
      expect(changedKeySource, isNot(equals(source)));
      final changedKey = await _compileFixture(
        screenSourceOverride: changedKeySource,
      );
      expect(
        changedKey.compilerOutput.canonicalBytes,
        orderedEquals(compilerOutput.canonicalBytes),
        reason: 'Flutter keys must not contribute to Measurement identity.',
      );
      expect(
        changedKey.compilerOutputBytes,
        orderedEquals(compiled.compilerOutputBytes),
      );
      expect(
        changedKey.measurementIndexBytes,
        orderedEquals(compiled.measurementIndexBytes),
      );
      expect(
        changedKey.outputIndexBytes,
        orderedEquals(compiled.outputIndexBytes),
      );
      for (final path in [
        kRestageSurfacePublicationCompilerBundlePath,
        'lib/generated/restage.publication.json',
        _screenBundlePath,
        _paywallBundlePath,
      ]) {
        expect(
          changedKey.readBytes(path),
          orderedEquals(compiled.readBytes(path)),
        );
      }
    },
  );
}

Future<_CompiledFixture> _compileFixture({
  String? screenSourceOverride,
}) async {
  final sources = _fixtureSources();
  if (screenSourceOverride != null) {
    sources['$_package|$_screenSourcePath'] = screenSourceOverride;
  }
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: _package,
  );
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
    sources,
    rootPackage: _package,
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
  final compilerOutputBytes = readerWriter.testing.readBytes(
    AssetId(_package, kRestageMeasurementCompilerOutputPath),
  );
  return _CompiledFixture(
    readerWriter: readerWriter,
    compilerOutputBytes: compilerOutputBytes,
    compilerOutput: RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
      compilerOutputBytes,
    ),
    handoff: RestageSurfacePublicationBundle.fromJson(
      jsonDecode(
        readerWriter.testing.readString(
          AssetId(_package, kRestageSurfacePublicationCompilerBundlePath),
        ),
      ),
    ),
    measurementIndexBytes: readerWriter.testing.readBytes(
      AssetId(_package, 'lib/generated/restage.measurement.index.json'),
    ),
    outputIndexBytes: readerWriter.testing.readBytes(
      AssetId(_package, 'lib/generated/restage.outputs.json'),
    ),
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
  return BuilderOptions({
    for (final entry in options.entries)
      _stringKey(entry.key, 'builder $builderKey option'):
          _yamlValue(entry.value),
  });
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

Map<String, String> _fixtureSources() => {
      for (final path in _fixtureDartPaths)
        '$_package|$path': File(p.join(_fixtureRoot, path)).readAsStringSync(),
    };

Map<String, Object?> _jsonObject(Object? value) {
  if (value is! Map) throw StateError('Expected a JSON object.');
  return {
    for (final entry in value.entries) entry.key as String: entry.value,
  };
}

Future<Directory> _materializeCliFixture(
  _CompiledFixture compiled,
  RestageOutputIndex outputIndex,
) async {
  final root = await Directory.systemTemp.createTemp(
    'measurement_customer_compiler_output_',
  );
  for (final path in [
    'build.yaml',
    'pubspec.yaml',
  ]) {
    final file = File(p.join(root.path, path));
    await file.writeAsString(
      File(p.join(_fixtureRoot, path)).readAsStringSync(),
    );
  }
  for (final path in [
    kRestageSurfacePublicationCompilerBundlePath,
    kRestageMeasurementCompilerOutputPath,
    'lib/generated/restage.outputs.json',
    'lib/generated/restage.publication.json',
    'lib/generated/restage.measurement.index.json',
    ...outputIndex.entries.map((entry) => entry.bundle).toSet(),
  ]) {
    final target = File(p.join(root.path, path));
    await target.parent.create(recursive: true);
    await target.writeAsBytes(compiled.readBytes(path));
  }
  return root;
}

Set<String> _allJsonKeys(Object? value) => switch (value) {
      Map<Object?, Object?>() => {
          for (final entry in value.entries) _stringKey(entry.key, 'JSON'),
          for (final child in value.values) ..._allJsonKeys(child),
        },
      List<Object?>() => {
          for (final child in value) ..._allJsonKeys(child),
        },
      _ => const {},
    };

List<fmt.EventHandler> _eventHandlers(fmt.RemoteWidgetLibrary library) {
  final handlers = <fmt.EventHandler>[];

  void visit(Object? value) {
    switch (value) {
      case final fmt.RemoteWidgetLibrary library:
        library.widgets.forEach(visit);
      case final fmt.WidgetDeclaration declaration:
        visit(declaration.initialState);
        visit(declaration.root);
      case final fmt.EventHandler handler:
        handlers.add(handler);
        visit(handler.eventArguments);
      case final fmt.ConstructorCall call:
        visit(call.arguments);
      case final fmt.WidgetBuilderDeclaration builder:
        visit(builder.widget);
      case final fmt.Loop loop:
        visit(loop.input);
        visit(loop.output);
      case final fmt.Switch switchNode:
        visit(switchNode.input);
        switchNode.outputs.values.forEach(visit);
      case final Map<Object?, Object?> map:
        map.values.forEach(visit);
      case final List<Object?> list:
        list.forEach(visit);
      default:
        break;
    }
  }

  visit(library);
  return handlers;
}

List<String> _presentationPointTokens(fmt.RemoteWidgetLibrary library) {
  final tokens = <String>[];

  void visit(Object? value) {
    switch (value) {
      case final fmt.RemoteWidgetLibrary library:
        library.widgets.forEach(visit);
      case final fmt.WidgetDeclaration declaration:
        visit(declaration.initialState);
        visit(declaration.root);
      case final fmt.EventHandler handler:
        visit(handler.eventArguments);
      case final fmt.ConstructorCall call:
        if (call.name == 'MeasurementPresented') {
          final pointTokens = call.arguments['pointTokens'];
          if (pointTokens is List) {
            tokens.addAll(pointTokens.whereType<String>());
          }
        }
        visit(call.arguments);
      case final fmt.WidgetBuilderDeclaration builder:
        visit(builder.widget);
      case final fmt.Loop loop:
        visit(loop.input);
        visit(loop.output);
      case final fmt.Switch switchNode:
        visit(switchNode.input);
        switchNode.outputs.values.forEach(visit);
      case final Map<Object?, Object?> map:
        map.values.forEach(visit);
      case final List<Object?> list:
        list.forEach(visit);
      default:
        break;
    }
  }

  visit(library);
  return tokens;
}

String _compactToken(String routeCarrier) => routeCarrier.split('.').last;

final class _CompiledFixture {
  const _CompiledFixture({
    required this.readerWriter,
    required this.compilerOutputBytes,
    required this.compilerOutput,
    required this.handoff,
    required this.measurementIndexBytes,
    required this.outputIndexBytes,
  });

  final TestReaderWriter readerWriter;
  final List<int> compilerOutputBytes;
  final RestageMeasurementCompilerOutputV1 compilerOutput;
  final RestageSurfacePublicationBundle handoff;
  final List<int> measurementIndexBytes;
  final List<int> outputIndexBytes;

  List<int> readBytes(String path) =>
      readerWriter.testing.readBytes(AssetId(_package, path));
}
