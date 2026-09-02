import 'dart:convert';
import 'dart:io';

import 'package:build/build.dart';
import 'package:build_config/build_config.dart' as build_config;
import 'package:build_runner/src/internal.dart' as build_runner_internal;
import 'package:build_test/build_test.dart';
import 'package:build_test/src/internal_test_reader_writer.dart';
import 'package:built_collection/built_collection.dart';
import 'package:path/path.dart' as p;
import 'package:restage_codegen/builder.dart';
import 'package:restage_codegen/src/analytics_id_control.dart';
import 'package:restage_codegen/src/measurement/measurement_compiler_output.dart';
import 'package:restage_codegen/src/measurement/measurement_route_emission.dart';
import 'package:restage_codegen/src/surface_publication/output_placement.dart';
import 'package:restage_codegen/src/surface_publication/package_surface_compiler_builder.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../helpers.dart';
import 'measurement_fixture_helpers.dart';

const _fixtureRoot = 'test/fixtures/measurement_configuration';
const _package = 'apps_examples';
const _screenPath = 'lib/surfaces/measurement_configuration.dart';
const _screenSlug = 'measurement_configuration';

void main() {
  test('omitted setting keeps Measurement enabled', () async {
    final build = await _compile('lib/config/default_on.dart');

    _expectSucceeded(build);
    expect(build.output.policy, isNotNull);
    expect(build.output.publications, hasLength(1));
    expect(build.output.publications.single.routePlan.routes, isNotEmpty);
  });

  test('explicit false keeps ordinary artifacts and removes Measurement',
      () async {
    final build = await _compile('lib/config/explicit_off.dart');

    _expectSucceeded(build);
    expect(build.output.policy, isNull);
    expect(build.output.ledgerNodes, isEmpty);
    expect(build.output.publications, isEmpty);
    expectUnmeasuredScreenPublication(
      readerWriter: build.readerWriter,
      packageName: _package,
      sourcePath: _screenPath,
      bundlePath:
          'assets/restage/bundles/lib/surfaces/measurement_configuration.rsbundle',
      surface: Surface.general,
      slug: _screenSlug,
    );
    final generated = build.readerWriter.testing.readString(
      AssetId(
        _package,
        'lib/surfaces/restage.generated/measurement_configuration.restage.g.dart',
      ),
    );
    expect(generated, isNot(contains(kMeasurementRouteArgumentKeyV1)));
    expect(generated, isNot(contains('measurementPublicationDraftDigest')));
  });

  test('function invocation can disable Measurement', () async {
    final build = await _compile('lib/config/function_invocation.dart');

    _expectSucceeded(build);
    expect(build.output.policy, isNull);
    expect(build.output.publications, isEmpty);
  });

  test('explicit call invocation can disable Measurement', () async {
    final build = await _compile('lib/config/call_invocation.dart');

    _expectSucceeded(build);
    expect(build.output.policy, isNull);
    expect(build.output.publications, isEmpty);
  });

  test('disabled build replaces prior ledger state', () async {
    final captured = <RestageMeasurementCompilerOutputV1>[];
    Future<void> captureLedger({
      required String package,
      required RestageMeasurementCompilerOutputV1 output,
    }) async {
      expect(package, _package);
      captured.add(output);
    }

    final enabled = await _compile(
      'lib/config/default_on.dart',
      ledgerWriter: captureLedger,
    );
    final disabled = await _compile(
      'lib/config/explicit_off.dart',
      ledgerWriter: captureLedger,
    );

    expect(enabled.result.succeeded, isTrue);
    expect(disabled.result.succeeded, isTrue);
    expect(captured, hasLength(2));
    expect(captured.first.policy, isNotNull);
    expect(
      captured.last.canonicalBytes,
      orderedEquals(RestageMeasurementCompilerOutputV1.empty().canonicalBytes),
    );
  });

  test('unrelated configure methods do not change the setting', () async {
    final build = await _compile('lib/config/unrelated.dart');

    _expectSucceeded(build);
    expect(build.output.policy, isNotNull);
    expect(build.output.publications, hasLength(1));
  });

  test('generated parts do not change the setting', () async {
    final build = await _compile(
      'lib/config/generated_part.dart',
      includeGeneratedPart: true,
    );

    _expectSucceeded(build);
    expect(build.output.policy, isNotNull);
    expect(build.output.publications, hasLength(1));
  });

  test('const false disables Measurement', () async {
    final build = await _compile('lib/config/const_false.dart');

    _expectSucceeded(build);
    expect(build.output.policy, isNull);
    expect(build.output.publications, isEmpty);
  });

  test('nonconstant setting is rejected', () async {
    final build = await _compile('lib/config/nonconstant.dart');

    expect(build.result.succeeded, isFalse);
    expect(
      build.result.errors.join('\n'),
      contains('compile-time bool literal or const bool reference'),
    );
  });

  test('conflicting settings are rejected', () async {
    final build = await _compile('lib/config/conflicting.dart');

    expect(build.result.succeeded, isFalse);
    expect(
      build.result.errors.join('\n'),
      contains('must agree'),
    );
  });

  test('incremental setting changes refresh package outputs', () async {
    final fixture = await _PersistentMeasurementBuild.create();
    addTearDown(fixture.close);

    var result = await fixture.apply(enabled: true);
    _expectBuildSucceeded(result);
    expect(fixture.ledgerOutputs, hasLength(1));
    expect(fixture.measurementOutput.policy, isNotNull);
    expect(fixture.measurementOutput.publications, hasLength(1));
    expect(fixture.analyticsOutput.publications, hasLength(1));

    result = await fixture.apply(enabled: false);
    _expectBuildSucceeded(result);
    expect(
      result.outputs,
      containsAll(<AssetId>[
        AssetId(_package, kRestageMeasurementCompilerOutputPath),
        AssetId(_package, kRestageAnalyticsIdControlOutputPath),
      ]),
    );
    expect(fixture.ledgerOutputs, hasLength(2));
    expect(
      fixture.ledgerOutputs.last.canonicalBytes,
      orderedEquals(RestageMeasurementCompilerOutputV1.empty().canonicalBytes),
    );
    expect(
      fixture.measurementOutput.canonicalBytes,
      orderedEquals(RestageMeasurementCompilerOutputV1.empty().canonicalBytes),
    );
    expect(fixture.analyticsOutput.publications, isEmpty);

    result = await fixture.apply(enabled: true);
    _expectBuildSucceeded(result);
    expect(fixture.ledgerOutputs, hasLength(3));
    expect(fixture.ledgerOutputs.last.policy, isNotNull);
    expect(fixture.measurementOutput.policy, isNotNull);
    expect(fixture.measurementOutput.publications, hasLength(1));
    expect(fixture.analyticsOutput.publications, hasLength(1));
  });
}

void _expectBuildSucceeded(build_runner_internal.BuildResult result) {
  expect(
    result.status,
    build_runner_internal.BuildStatus.success,
    reason: result.errors.join('\n'),
  );
}

void _expectSucceeded(_FixtureCompilation build) {
  expect(
    build.result.succeeded,
    isTrue,
    reason: build.result.errors.join('\n'),
  );
}

Future<_FixtureCompilation> _compile(
  String configurationPath, {
  bool includeGeneratedPart = false,
  MeasurementCompilerLedgerWriter? ledgerWriter,
}) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: _package,
  );
  final sources = <String, String>{
    '$_package|$_screenPath': _fixtureSource(_screenPath),
    '$_package|$configurationPath': _fixtureSource(configurationPath),
  };
  if (includeGeneratedPart) {
    sources['$_package|lib/config/generated_part.freezed.dart'] =
        _fixtureSource('lib/config/generated_part.freezed.dart');
  }
  final compilerOptions =
      _builderOptions('restage_codegen:restage_package_surface_compiler');
  final packageSurfaceCompiler = ledgerWriter == null
      ? restagePackageSurfaceCompilerBuilder(compilerOptions)
      : PackageSurfaceCompilerBuilder(
          compilerOptions,
          ledgerWriter: ledgerWriter,
        );
  final result = await testBuilders(
    [
      restageSourceRosterBuilder(
        _builderOptions('restage_codegen:restage_source_roster'),
      ),
      userCatalogJsonBuilder(BuilderOptions.empty),
      packageSurfaceCompiler,
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
  final output = RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
    readerWriter.testing.readBytes(
      AssetId(_package, kRestageMeasurementCompilerOutputPath),
    ),
  );
  return (result: result, readerWriter: readerWriter, output: output);
}

BuilderOptions _builderOptions(String builderKey) {
  final document = loadYaml(_fixtureSource('build.yaml'));
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

String _fixtureSource(String path) =>
    File(p.join(_fixtureRoot, path)).readAsStringSync();

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

typedef _FixtureCompilation = ({
  TestBuilderResult result,
  TestReaderWriter readerWriter,
  RestageMeasurementCompilerOutputV1 output,
});

const _configurationPath = 'lib/config/setting.dart';
const _cacheConsumerOutputPath =
    'lib/src/measurement/restage.measurement.consumer.txt';
const _cacheConsumerKey = 'restage_codegen:measurement_configuration_consumer';
const _packageCompilerKey = 'restage_codegen:restage_package_surface_compiler';

final class _PersistentMeasurementBuild {
  _PersistentMeasurementBuild({
    required this.readerWriter,
    required build_runner_internal.BuildSeries buildSeries,
    required this.ledgerOutputs,
  }) : _buildSeries = buildSeries;

  final InternalTestReaderWriter readerWriter;
  final build_runner_internal.BuildSeries _buildSeries;
  final List<RestageMeasurementCompilerOutputV1> ledgerOutputs;
  bool _firstBuild = true;
  bool? _enabled;

  RestageMeasurementCompilerOutputV1 get measurementOutput =>
      RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
        readerWriter.testing.readBytes(
          AssetId(_package, kRestageMeasurementCompilerOutputPath),
        ),
      );

  AnalyticsIdControlOutputV1 get analyticsOutput =>
      AnalyticsIdControlOutputV1.fromJson(
        jsonDecode(
          readerWriter.testing.readString(
            AssetId(_package, kRestageAnalyticsIdControlOutputPath),
          ),
        ),
      );

  static Future<_PersistentMeasurementBuild> create() async {
    final readerWriter = (await readerWriterWithFilesystemSources(
      rootPackage: _package,
    )) as InternalTestReaderWriter;
    readerWriter.testing.writeString(
      AssetId(_package, _screenPath),
      _fixtureSource(_screenPath),
    );
    readerWriter.testing.writeString(
      AssetId(_package, _configurationPath),
      _configurationSource(true),
    );

    final dependencyPackages = readerWriter.testing.assets
        .map((asset) => asset.package)
        .where((package) => package != _package)
        .toSet()
        .toList()
      ..sort();
    final buildPackages =
        build_runner_internal.BuildPackages.singlePackageBuild(
      _package,
      <build_runner_internal.BuildPackage>[
        build_runner_internal.BuildPackage(
          name: _package,
          path: '/$_package',
          watch: true,
          isOutput: true,
          dependencies: dependencyPackages.toSet(),
        ),
        for (final package in dependencyPackages)
          build_runner_internal.BuildPackage(
            name: package,
            path: '/$package',
            watch: true,
          ),
      ],
    );
    final builderDefinitions =
        <build_runner_internal.AbstractBuilderDefinition>[
      build_runner_internal.BuilderDefinition(
        _cacheConsumerKey,
        package: 'restage_codegen',
        autoApply: build_config.AutoApply.none,
        hideOutput: false,
      ),
      build_runner_internal.BuilderDefinition(
        _packageCompilerKey,
        package: 'restage_codegen',
        autoApply: build_config.AutoApply.none,
        hideOutput: false,
      ),
    ].build();
    final buildConfig = build_config.BuildConfig.fromMap(
      _package,
      dependencyPackages,
      <String, Object?>{
        'targets': <String, Object?>{
          _package: <String, Object?>{
            'sources': <String>[r'\$package$', 'lib/**'],
            'builders': <String, Object?>{
              _cacheConsumerKey: <String, Object?>{
                'enabled': true,
                'options': <String, Object?>{'bundled_runtime': true},
              },
              _packageCompilerKey: <String, Object?>{
                'enabled': true,
                'options': <String, Object?>{'bundled_runtime': true},
              },
            },
          },
        },
      },
    );
    final ledgerOutputs = <RestageMeasurementCompilerOutputV1>[];
    final builderFactories = build_runner_internal.BuilderFactories(
      <String, List<BuilderFactory>>{
        _cacheConsumerKey: <BuilderFactory>[
          _MeasurementConfigurationConsumer.new,
        ],
        _packageCompilerKey: <BuilderFactory>[
          (options) => PackageSurfaceCompilerBuilder(
                options,
                ledgerWriter: ({required package, required output}) async {
                  expect(package, _package);
                  ledgerOutputs.add(output);
                },
              ),
        ],
      },
    );
    final buildPlan = await build_runner_internal.BuildPlan.load(
      builderFactories: builderFactories,
      buildOptions: build_runner_internal.BuildOptions.forTests(),
      testingOverrides: build_runner_internal.TestingOverrides(
        builderDefinitions: builderDefinitions,
        buildConfig: <String, build_config.BuildConfig>{
          _package: buildConfig,
        }.build(),
        buildPackages: buildPackages,
        checkBuilderFreshness: false,
        flattenOutput: true,
        readerWriter: readerWriter,
        resolvers: build_runner_internal.ResolversImpl.custom(),
      ),
    );
    return _PersistentMeasurementBuild(
      readerWriter: readerWriter,
      buildSeries: build_runner_internal.BuildSeries(buildPlan),
      ledgerOutputs: ledgerOutputs,
    );
  }

  Future<build_runner_internal.BuildResult> apply({
    required bool enabled,
  }) async {
    final configuration = AssetId(_package, _configurationPath);
    final updates = <AssetId>{};
    if (_enabled != enabled) {
      readerWriter.testing.writeString(
        configuration,
        _configurationSource(enabled),
      );
      if (!_firstBuild) updates.add(configuration);
    }
    _enabled = enabled;
    final result = await _buildSeries.run(
      _firstBuild ? const <AssetId>{} : updates,
      recentlyBootstrapped: _firstBuild,
    );
    _firstBuild = false;
    return result;
  }

  Future<void> close() => _buildSeries.close();
}

final class _MeasurementConfigurationConsumer implements Builder {
  const _MeasurementConfigurationConsumer(this.options);

  final BuilderOptions options;

  @override
  Map<String, List<String>> get buildExtensions => const <String, List<String>>{
        r'$package$': <String>[_cacheConsumerOutputPath],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    final compilation = await compileTrackedPackageSurfaces(
      buildStep,
      plan: RestageOutputPlacementPlan.fromBuilderOptions(options),
      measurementPolicy:
          MeasurementCompilerPolicyInput.fromBuilderOptions(options),
      builderKey: _cacheConsumerKey,
    );
    if (!compilation.isValid) {
      throw StateError(compilation.issues.map((issue) => issue.message).join());
    }
    await buildStep.writeAsBytes(
      AssetId(buildStep.inputId.package, _cacheConsumerOutputPath),
      compilation.measurementCompilerOutput.canonicalBytes,
    );
  }
}

String _configurationSource(bool enabled) => '''
import 'package:restage/restage.dart';

void configureApp() {
  Restage.configure(
    apiKey: 'rs_pk_test',
    measurementEnabled: $enabled,
  );
}
''';
