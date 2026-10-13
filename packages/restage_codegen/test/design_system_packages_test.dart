import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:build_config/build_config.dart' as config;
import 'package:build_runner/src/internal.dart' as runner;
import 'package:build_test/src/internal_test_reader_writer.dart';
import 'package:built_collection/built_collection.dart';
import 'package:restage_codegen/builder.dart';
import 'package:restage_codegen/src/library_contract.dart';
import 'package:restage_codegen/src/measurement/measurement_compiler_output.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_codegen/src/surface_publication/package_surface_compiler_builder.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as fmt;
import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const _app = 'apps_examples';
const _design = 'acme_design_system';
const _catalogKey = 'restage_codegen:user_catalog_json';
const _compilerKey = 'restage_codegen:restage_package_surface_compiler';
const _factoriesKey = 'restage_codegen:user_factories';
const _screenPath = 'lib/welcome.dart';
const _widgetsPath = 'lib/widgets.dart';
const _libraryPath = 'lib/acme_design_system.dart';

String _fixture(String name) =>
    File('test/fixtures/design_system_packages/$name.dart.txt')
        .readAsStringSync();

void main() {
  test('dependency widgets and helpers compile and rebuild through the graph',
      () async {
    final build = await _DesignSystemBuild.create();
    addTearDown(build.close);
    await build.run();
    final first = build.bundle;
    final text = utf8
        .decode(first.ownedOutputs['assets/general/screens/welcome.rfwtxt']!);
    expect(text, contains('Shared badge'));
    expect(text, contains('Welcome'));
    expect(text, contains('FilledButton('));
    expect(text, contains('AcmeMark('));
    final registration = build.readerWriter.testing.readString(
      AssetId(_app, 'lib/user_factories.g.dart'),
    );
    expect(registration, contains('acme.widgets'));
    expect(registration, contains('AcmeMark('));
    expect(registration, isNot(contains('RestageWidgetLibraries.builtIn(')));
    expect(
      first.ownedOutputs.entries
          .where((entry) => entry.key.endsWith('.restage.g.dart'))
          .map((entry) => utf8.decode(entry.value))
          .join(),
      contains('AcmeMark('),
    );
    await resolveWorkspaceSources(
      {
        '$_app|$_screenPath': _fixture('screen'),
        '$_design|$_widgetsPath': _fixture('widgets'),
        '$_design|$_libraryPath': _fixture('library'),
        '$_app|lib/user_factories.g.dart': registration,
        for (final entry in first.ownedOutputs.entries)
          if (entry.key.endsWith('.dart'))
            '$_app|${entry.key}': utf8.decode(entry.value),
      },
      (resolver) async {
        for (final path in [_screenPath, 'lib/user_factories.g.dart']) {
          final library = await resolver.libraryFor(AssetId(_app, path));
          final resolved =
              await library.session.getResolvedLibraryByElement(library);
          if (resolved is! ResolvedLibraryResult) {
            throw StateError(
              'Generated dependency consumer $path did not resolve.',
            );
          }
          final errors = [
            for (final unit in resolved.units)
              for (final diagnostic in unit.diagnostics)
                if (diagnostic.severity == Severity.error)
                  diagnostic.problemMessage.messageText(includeUrl: false),
          ];
          expect(errors, isEmpty, reason: path);
        }
      },
      resolverFor: '$_app|$_screenPath',
      rootPackage: _app,
    );
    final measurement = build.measurement;
    expect(measurement.publications, hasLength(1));
    expect(measurement.publications.single.routePlan.routes, isNotEmpty);

    final edited =
        _fixture('widgets').replaceAll('Shared badge', 'Updated badge');
    final result = await build.run(
      changes: {
        AssetId(_design, _widgetsPath): edited,
      },
    );
    expect(
      result.outputs,
      contains(AssetId(_app, kRestageSurfacePublicationCompilerBundlePath)),
    );
    final updated = utf8.decode(
      build.bundle.ownedOutputs['assets/general/screens/welcome.rfwtxt']!,
    );
    expect(updated, contains('Updated badge'));
    expect(updated, isNot(contains('Shared badge')));
    expect(
      build.measurement.ledgerNodes.map((node) => node.toJson()),
      measurement.ledgerNodes.map((node) => node.toJson()),
    );
    final upgraded = edited.replaceAll("Text('Continue')", "Text('Proceed')");
    await build.run(
      changes: {
        AssetId(_design, _widgetsPath): upgraded,
        AssetId(_design, _libraryPath): _fixture('library')
            .replaceAll('capabilityVersion: 1', 'capabilityVersion: 2'),
        AssetId(_design, 'pubspec.yaml'):
            'name: $_design\nversion: 2.0.0\ndependencies:\n'
                '  flutter:\n    sdk: flutter\n  restage: any\n',
      },
    );
    final catalog = jsonDecode(
      utf8.decode(
        build.cachedBytes(
          'lib/src/widget_catalog/catalog.json',
          package: _design,
        ),
      ),
    ) as Map<String, Object?>;
    expect(
      ((catalog['libraries']! as Map<String, Object?>)['acme.widgets']!
          as Map<String, Object?>)['capabilityVersion'],
      2,
    );
    final registrationAfterUpgrade = build.readerWriter.testing.readString(
      AssetId(_app, 'lib/user_factories.g.dart'),
    );
    expect(registrationAfterUpgrade, contains('capabilityVersion: 2'));
    expect(
      utf8.decode(
        build.bundle.ownedOutputs['assets/general/screens/welcome.rfwtxt']!,
      ),
      contains('Proceed'),
    );
    expect(
      build.measurement.ledgerNodes.map((node) => node.toJson()),
      measurement.ledgerNodes.map((node) => node.toJson()),
    );
  });

  for (final workspace in [false, true]) {
    final mode = workspace ? 'workspace' : 'single-package';
    test('widget-ID state alone rebuilds a $mode dependency consumer',
        () async {
      const path = '.restage/wire-ids.events.jsonl';
      final build = await _DesignSystemBuild.create(
        measured: false,
        workspace: workspace,
        state: {path: ''},
      );
      addTearDown(build.close);
      await build.run();
      final before = build.bundle;
      final catalog = decodeCatalog(
        utf8.decode(
          build.cachedBytes(
            'lib/src/widget_catalog/catalog.json',
            package: _design,
          ),
        ),
      );
      final allocator = WireIdAllocator(
        library: _design,
        at: '2026-10-09T00:00:00Z',
        by: 'design-system-test',
      );
      final ids = <String, WireId>{};
      for (final widget in catalog.widgets.reversed) {
        final event = allocator.allocate(
          WireIdAllocationCandidate.widget(
            name: widget.name,
            source: widget.flutterType,
          ),
        );
        ids[widget.name] = event.id;
        for (final property in widget.properties) {
          allocator.allocate(
            WireIdAllocationCandidate.property(
              owner: event.id,
              name: property.name,
              source: '${widget.flutterType}.${property.name}',
            ),
          );
        }
      }
      final result = await build.run(
        changes: {
          AssetId(_design, path): encodeWireIdEventsJsonl(allocator.events),
        },
      );
      expect(
        result.outputs,
        contains(AssetId(_app, kRestageSurfacePublicationCompilerBundlePath)),
      );
      final after = decodeCatalog(
        utf8.decode(
          build.cachedBytes(
            'lib/src/widget_catalog/catalog.json',
            package: _design,
          ),
        ),
      );
      expect(
        after.widgets.map((widget) => widget.wireId),
        after.widgets.map((widget) => ids[widget.name]),
      );
      expect(
        after.widgets.map((widget) => widget.wireId),
        isNot(equals(catalog.widgets.map((widget) => widget.wireId))),
      );
      WireId installedMark(RestageSurfacePublicationBundle bundle) {
        final publication = bundle.manifest!.publications.single.publication;
        final contract = publication.compiledScreenContracts.values.single;
        return contract.catalog.widgets
            .singleWhere((widget) => widget.name == 'AcmeMark')
            .wireId;
      }

      expect(installedMark(build.bundle), ids['AcmeMark']);
      expect(installedMark(build.bundle), isNot(installedMark(before)));
      expect(build.bundle.artifacts, equals(before.artifacts));
    });

    test(
        'library contract state alone invalidates the $mode dependency catalog',
        () async {
      const path = '.restage/library-contracts/acme.widgets/v1.json';
      final build = await _DesignSystemBuild.create(workspace: workspace);
      addTearDown(build.close);
      await build.run();
      final catalog = decodeCatalog(
        utf8.decode(
          build.cachedBytes(
            'lib/src/widget_catalog/catalog.json',
            package: _design,
          ),
        ),
      );
      final snapshot = LibraryContractSnapshot.of(
        catalog,
        const WidgetLibrary.custom('acme.widgets'),
      )!;
      await build.run(changes: {AssetId(_design, path): snapshot.encode()});
      final recorded = jsonDecode(snapshot.encode()) as Map<String, Object?>;
      (recorded['widgets']! as List<Object?>).removeLast();
      final changed =
          LibraryContractSnapshot.decode(jsonEncode(recorded), path);
      final result = await build.run(
        changes: {AssetId(_design, path): changed.encode()},
        expectSuccess: false,
      );
      expect(result.status, runner.BuildStatus.failure);
      expect(result.errors.join('\n'), contains('acme.widgets'));
      expect(
          result.errors.join('\n'), contains('Raise capabilityVersion to 2'));
      await build.run(changes: {AssetId(_design, path): snapshot.encode()});
    });
  }

  test('measured dependency routes survive persisted ledger rebuilds',
      () async {
    final build = await _DesignSystemBuild.create();
    addTearDown(build.close);
    await build.run();
    final first = build.measurement.publications.single.draft;
    final artifacts = build.bundle.artifacts;
    expect(
      build.measurement.ledgerNodes
          .where(
            (node) => node.structuralOccurrenceKey.contains(
              'package:$_design/widgets.dart',
            ),
          )
          .expand((node) => node.events)
          .where((event) => event.active),
      isNotEmpty,
    );
    expect(first.routes, isNotEmpty);
    expect(first.presentationRoutes, isNotEmpty);
    expect(
      first.lineageIntents.map((intent) => intent.operation),
      everyElement(LineageOperation.continueLineage),
    );

    for (var rebuild = 0; rebuild < 2; rebuild += 1) {
      final result = await build.run(
        changes: {
          // Whitespace forces compilation when ledger content is stable.
          AssetId(_app, kRestageMeasurementCompilerLedgerSourcePath):
              '${build.measurement.encodeCanonicalJson()}'
                  '${' ' * (rebuild + 1)}',
        },
      );
      expect(
        result.outputs,
        containsAll([
          AssetId(_app, kRestageMeasurementCompilerOutputPath),
          AssetId(_app, kRestageSurfacePublicationCompilerBundlePath),
        ]),
        reason: 'Each ledger update must execute the publication compiler',
      );
      final repeated = build.measurement.publications.single.draft;
      expect(
        repeated.lineageIntents.map((intent) => intent.operation),
        everyElement(LineageOperation.continueLineage),
      );
      expect(repeated.routeDraftClosureDigest, first.routeDraftClosureDigest);
      expect(repeated.routes, orderedEquals(first.routes));
      expect(
        repeated.presentationRoutes,
        orderedEquals(first.presentationRoutes),
      );
      expect(repeated.artifacts, orderedEquals(first.artifacts));
      expect(build.bundle.artifacts, equals(artifacts));
    }
  });

  test('dependency helper errors retain their declaring file', () async {
    final build = await _DesignSystemBuild.create(
      widgetsSource: _fixture('widgets')
          .replaceAll('Text(title);', 'Text(title.toUpperCase());'),
    );
    addTearDown(build.close);
    final result = await build.run(expectSuccess: false);
    expect(result.status, runner.BuildStatus.failure);
    final errors = result.errors.join('\n');
    expect(errors, contains('acme_design_system'));
    expect(errors, contains('widgets.dart'));
    final helperLine = _fixture('widgets').split('\n').indexWhere(
              (line) => line.startsWith('Widget acmeTitle'),
            ) +
        1;
    expect(
      errors,
      contains('package:acme_design_system/widgets.dart:$helperLine:'),
    );
    expect(errors, isNot(contains('lib/welcome.dart:')));
  });

  test('copied local definitions preserve artifacts and catalog provenance',
      () async {
    final dependency = await _DesignSystemBuild.create(measured: false);
    final local =
        await _DesignSystemBuild.create(copiedLocal: true, measured: false);
    addTearDown(dependency.close);
    addTearDown(local.close);
    await dependency.run();
    await local.run();
    expect(dependency.bundle.artifacts, equals(local.bundle.artifacts));
    final dependencyManifest = jsonEncode(dependency.bundle.manifest!.toJson());
    final localManifest = jsonEncode(local.bundle.manifest!.toJson());
    expect(
      dependencyManifest,
      contains('package:acme_design_system/widgets.dart'),
    );
    expect(localManifest, contains('package:apps_examples/widgets.dart'));
    expect(
      dependencyManifest.replaceAll(
        'package:acme_design_system/widgets.dart',
        'package:apps_examples/widgets.dart',
      ),
      localManifest,
    );
    expect(
      dependency.bundle.ownedOutputs['assets/general/screens/welcome.rfwtxt'],
      equals(
        local.bundle.ownedOutputs['assets/general/screens/welcome.rfwtxt'],
      ),
    );
  });

  test('moving declarations preserves event semantics and changes origin',
      () async {
    final dependency = await _DesignSystemBuild.create();
    final local = await _DesignSystemBuild.create(copiedLocal: true);
    addTearDown(dependency.close);
    addTearDown(local.close);
    await dependency.run();
    await local.run();
    final dependencyNodes = dependency.measurement.ledgerNodes;
    final localNodes = local.measurement.ledgerNodes;
    expect(dependencyNodes, hasLength(localNodes.length));
    expect(
      dependencyNodes.map((node) => node.structuralOccurrenceKey),
      isNot(equals(localNodes.map((node) => node.structuralOccurrenceKey))),
    );
    Map<String, Object?> eventSemantics(_DesignSystemBuild build) {
      final plan = build.measurement.publications.single.routePlan;
      expect(plan.events, isNotEmpty);
      expect(plan.routes, hasLength(plan.events.length));
      final events = <Map<String, Object?>>[];
      final rendered = fmt
          .decodeLibraryBlob(
            Uint8List.fromList(
              build.bundle.artifacts['assets/general/screens/welcome.rfw']!,
            ),
          )
          .toString();
      for (final event in plan.events) {
        final route = plan.routes.singleWhere(
          (route) => route.generatedReferenceId == event.generatedReferenceId,
        );
        final node = plan.nodes.singleWhere(
          (node) => node.codeIdentityId == event.nodeCodeIdentityId,
        );
        expect(
          route.artifactOccurrenceEdgeToken,
          node.artifactOccurrenceEdgeToken,
        );
        if (route.orderedCaptureV1?.lifecycleChannel == null) {
          expect(rendered, contains(route.carrier));
        }
        final ledger = build.measurement.ledgerNodes.singleWhere(
          (node) => node.codeIdentityId == event.nodeCodeIdentityId,
        );
        final ledgerEvent = ledger.events.singleWhere(
          (candidate) =>
              candidate.generatedReferenceId == route.generatedReferenceId,
        );
        events.add({
          'kind': event.normalizedInteractionKind.wireName,
          'privacy': event.privacyClass.wireName,
          'value': event.semanticValueClass.wireName,
          'collection': event.collectionClass.wireName,
          'sourceEvent': event.sourceEventIdentity.value,
          'eventLocator': ledgerEvent.resolvedEventLocator,
          'owner': ledger.structuralOccurrenceKey.replaceAll(
            'package:acme_design_system/widgets.dart',
            'package:apps_examples/widgets.dart',
          ),
          'orderedCapture': route.orderedCaptureV1?.toJson(),
        });
      }
      events.sort((a, b) => jsonEncode(a).compareTo(jsonEncode(b)));
      return {
        'events': events,
        'eventContract': SurfaceScreenEventSchemaV1Codec.encode(
          build.bundle.manifest!.publications.single.publication.eventContract!,
        ),
      };
    }

    expect(eventSemantics(dependency), equals(eventSemantics(local)));
  });
}

final class _DesignSystemBuild {
  _DesignSystemBuild(this.readerWriter, this.series);

  final InternalTestReaderWriter readerWriter;
  final runner.BuildSeries series;
  bool first = true;

  List<int> cachedBytes(String path, {String package = _app}) =>
      readerWriter.filesystem.readAsBytesSync(
        readerWriter.assetPathProvider
            .pathFor(AssetId(package, path), inArtifactTree: true),
      );

  RestageSurfacePublicationBundle get bundle =>
      RestageSurfacePublicationBundle.fromJson(
        jsonDecode(
          utf8.decode(
            cachedBytes(kRestageSurfacePublicationCompilerBundlePath),
          ),
        ),
      );

  RestageMeasurementCompilerOutputV1 get measurement =>
      RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
        cachedBytes(kRestageMeasurementCompilerOutputPath),
      );

  static Future<_DesignSystemBuild> create({
    bool copiedLocal = false,
    bool workspace = false,
    bool measured = true,
    String? widgetsSource,
    Map<String, String> state = const {},
  }) async {
    final readerWriter = (await readerWriterWithFilesystemSources(
      rootPackage: _app,
    )) as InternalTestReaderWriter;
    readerWriter.testing.writeString(
      AssetId(_app, _screenPath),
      copiedLocal
          ? _fixture('screen').replaceAll(
              'package:acme_design_system/widgets.dart',
              'widgets.dart',
            )
          : _fixture('screen'),
    );
    if (!measured) {
      readerWriter.testing.writeString(
        AssetId(_app, 'lib/config.dart'),
        "import 'package:restage/restage.dart';\nvoid configureApp() => Restage.configure(apiKey: 'rs_pk_test', measurementEnabled: false);",
      );
    }
    readerWriter.testing.writeString(
      AssetId(copiedLocal ? _app : _design, _widgetsPath),
      widgetsSource ?? _fixture('widgets'),
    );
    readerWriter.testing.writeString(
      AssetId(copiedLocal ? _app : _design, _libraryPath),
      _fixture('library'),
    );
    readerWriter.testing.writeString(AssetId(_app, 'pubspec.yaml'), '''
name: $_app
environment:
  sdk: ^3.6.0
dependencies:
  flutter:
    sdk: flutter
  restage: any
${copiedLocal ? '' : '  $_design: any'}
''');
    readerWriter.testing.writeString(AssetId(_design, 'pubspec.yaml'), '''
name: $_design
environment:
  sdk: ^3.6.0
dependencies:
  flutter:
    sdk: flutter
  restage: any
''');
    for (final entry in state.entries) {
      readerWriter.testing
          .writeString(AssetId(_design, entry.key), entry.value);
    }
    final dependencies = readerWriter.testing.assets
        .map((asset) => asset.package)
        .where((package) => package != _app)
        .toSet();
    final members = [
      runner.BuildPackage(
        name: _app,
        path: '/$_app',
        watch: true,
        isOutput: true,
        dependencies: dependencies,
      ),
      for (final package in dependencies)
        runner.BuildPackage(
          name: package,
          path: '/$package',
          watch: true,
          isOutput: workspace && package == _design,
        ),
    ];
    final packages = workspace
        ? runner.BuildPackages.workspaceBuild(
            currentPackage: _app,
            workspace: _app,
            packages: members,
          )
        : runner.BuildPackages.singlePackageBuild(_app, members);
    expect(packages.singleOutputPackage, workspace ? isNull : _app);
    expect(packages.outputPackages,
        workspace ? containsAll([_app, _design]) : [_app]);
    final production = config.BuildConfig.parse(
      'restage_codegen',
      const [],
      File('build.yaml').readAsStringSync(),
    );
    final definitions = <runner.AbstractBuilderDefinition>[
      for (final key in [_catalogKey, _compilerKey, _factoriesKey])
        runner.BuilderDefinition.fromConfig(
          production.builderDefinitions[key]!,
        ),
    ].build();
    config.BuildConfig buildConfig(String package) =>
        config.BuildConfig.fromMap(
          package,
          dependencies,
          {
            'additional_public_assets': ['.restage/**'],
            'targets': {
              package: {
                'sources': [
                  r'$package$',
                  'lib/**',
                  'pubspec.yaml',
                  '.restage/**',
                ],
                'builders': {
                  if (package == _app) ...{
                    _compilerKey: {
                      'enabled': true,
                      'options': {'bundled_runtime': true},
                    },
                    _factoriesKey: {
                      'enabled': true,
                      'options': {'catalog': 'derived'},
                    },
                  },
                },
              },
            },
          },
        );
    final plan = await runner.BuildPlan.load(
      await runner.BuildSpec.load(
        builderFactories: runner.BuilderFactories({
          _catalogKey: [userCatalogJsonBuilder],
          _compilerKey: [
            (options) => PackageSurfaceCompilerBuilder(
                  options,
                  ledgerWriter: ({required package, required output}) async {},
                ),
          ],
          _factoriesKey: [userFactoryBuilder],
        }),
        buildOptions: runner.BuildOptions.forTests(),
        testingOverrides: runner.TestingOverrides(
          builderDefinitions: definitions,
          buildConfig: {
            _app: buildConfig(_app),
            _design: buildConfig(_design),
            for (final package in [
              'restage_core',
              'restage_material',
              'restage_cupertino',
            ])
              package: config.BuildConfig.parse(
                package,
                const [],
                File('../$package/build.yaml').readAsStringSync(),
              ),
          }.build(),
          buildPackages: packages,
          checkBuilderFreshness: false,
          forceToPackagePathsForTesting: true,
          readerWriter: readerWriter,
          resolvers: runner.ResolversImpl.custom(),
        ),
      ),
    );
    for (final package in [_app, _design]) {
      for (final path in [
        '.restage/wire-ids.events.jsonl',
        '.restage/library-contracts/acme.widgets/v1.json',
      ]) {
        final asset = AssetId(package, path);
        expect(plan.buildSpec.buildConfigs.isPublicAsset(asset), isTrue,
            reason: '$asset must be exposed to consumers.');
        expect(plan.buildSpec.buildConfigs.anyMatchesAsset(asset), isTrue,
            reason: '$asset must be included in target sources.');
      }
    }
    return _DesignSystemBuild(readerWriter, runner.BuildSeries(plan));
  }

  Future<runner.BuildResult> run({
    Map<AssetId, String> changes = const {},
    bool expectSuccess = true,
  }) async {
    for (final entry in changes.entries) {
      readerWriter.testing.writeString(entry.key, entry.value);
    }
    final result =
        await series.run(changes.keys.toSet(), recentlyBootstrapped: first);
    first = false;
    if (expectSuccess) {
      expect(
        result.status,
        runner.BuildStatus.success,
        reason: result.errors.join('\n'),
      );
    }
    return result;
  }

  Future<void> close() => series.close();
}
