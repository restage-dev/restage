import 'dart:convert';

import 'package:build/build.dart';
import 'package:build_config/build_config.dart' as build_config;
import 'package:build_runner/src/internal.dart' as build_runner_internal;
import 'package:build_test/src/internal_test_reader_writer.dart';
import 'package:built_collection/built_collection.dart';
import 'package:glob/glob.dart';
import 'package:test/test.dart';

const _package = 'dynamic_output_fixture';
const _bundlePath = 'assets/restage/dynamic-proof.bundle.json';
const _failureMarkerPath = 'assets/restage/dynamic-proof.invalid';
const _dynamicPrefix = 'assets/restage/dynamic/';

final _buildTrace = <String>[];
final _materializedPaths = <String>[];
final _postProcessInputs = <AssetId>[];

void main() {
  test(
    'owns dynamic artifact families across one persistent incremental build',
    () async {
      _buildTrace.clear();
      _materializedPaths.clear();
      _postProcessInputs.clear();
      expect(_failureMarkerPath.startsWith(_dynamicPrefix), isFalse);
      final initialSources = <String, String>{
        'lib/restage_dynamic/z_alpha.source': _source(
          id: 'alpha',
          surface: 'onboarding',
          artifacts: _family('onboarding', 'alpha'),
        ),
        'lib/restage_dynamic/a_beta.source': _source(
          id: 'beta',
          surface: 'message',
          artifacts: _family('message', 'beta'),
        ),
      };
      final fixture = await _PersistentDynamicOutputBuild.create(
        initialSources,
      );
      addTearDown(fixture.close);

      var result = await fixture.apply(initialSources);
      _expectSuccess(result);
      _expectFixedBundle(fixture, const ['alpha', 'beta']);
      _expectFamily(fixture, 'onboarding/alpha', owner: 'alpha');
      _expectFamily(fixture, 'message/beta', owner: 'beta');
      _expectNormalOutputBeforePostMaterialization();
      expect(
        _postProcessInputs,
        orderedEquals([AssetId(_package, _bundlePath)]),
      );

      result = await fixture.apply({
        'lib/restage_dynamic/z_alpha.source': _source(
          id: 'alpha',
          surface: 'onboarding',
          artifacts: _family('onboarding', 'alpha'),
        ),
        'lib/restage_dynamic/a_beta.source': _source(
          id: 'beta',
          surface: 'message',
          artifacts: _family('message', 'beta'),
        ),
        'lib/restage_dynamic/m_gamma.source': _source(
          id: 'gamma',
          surface: 'survey',
          artifacts: _family('survey', 'gamma'),
        ),
      });
      _expectSuccess(result);
      _expectFixedBundle(fixture, const ['alpha', 'beta', 'gamma']);
      _expectFamily(fixture, 'survey/gamma', owner: 'gamma');

      result = await fixture.apply({
        // The source moved, but its explicit delivery identity and family
        // identity remain alpha. Its physical artifact family is relocated.
        'lib/restage_dynamic/moved/alpha_renamed.source': _source(
          id: 'alpha',
          surface: 'onboarding',
          artifacts: _family('moved', 'alpha'),
        ),
        'lib/restage_dynamic/a_beta.source': _source(
          id: 'beta',
          surface: 'message',
          artifacts: _family('message', 'beta'),
        ),
        'lib/restage_dynamic/m_gamma.source': _source(
          id: 'gamma',
          surface: 'survey',
          artifacts: _family('survey', 'gamma'),
        ),
      });
      _expectSuccess(result);
      _expectFixedBundle(fixture, const ['alpha', 'beta', 'gamma']);
      expect(
        _bundleEntries(fixture).singleWhere(
          (entry) => entry['deliveryId'] == 'alpha',
        )['sourcePath'],
        'lib/restage_dynamic/moved/alpha_renamed.source',
      );
      _expectFamily(fixture, 'moved/alpha', owner: 'alpha');
      _expectNoDynamicFamily(fixture, 'onboarding/alpha');

      result = await fixture.apply({
        'lib/restage_dynamic/moved/alpha_renamed.source': _source(
          id: 'alpha',
          surface: 'onboarding',
          artifacts: _family('moved', 'alpha'),
        ),
        'lib/restage_dynamic/m_gamma.source': _source(
          id: 'gamma',
          surface: 'survey',
          artifacts: _family('survey', 'gamma'),
        ),
      });
      _expectSuccess(result);
      _expectFixedBundle(fixture, const ['alpha', 'gamma']);
      _expectNoDynamicFamily(fixture, 'message/beta');
      _expectFamily(fixture, 'moved/alpha', owner: 'alpha');

      result = await fixture.apply({
        // Reclassify both declarations and deliberately exchange the output
        // families previously owned by alpha and gamma. The single
        // post-process action must write each current path once, regardless
        // of who owned that path in the previous build.
        'lib/restage_dynamic/moved/alpha_renamed.source': _source(
          id: 'alpha',
          surface: 'survey',
          artifacts: _family('survey', 'gamma', owner: 'alpha'),
        ),
        'lib/restage_dynamic/m_gamma.source': _source(
          id: 'gamma',
          surface: 'onboarding',
          artifacts: _family('moved', 'alpha', owner: 'gamma'),
        ),
      });
      _expectSuccess(result);
      expect(
        result.errors
            .where((error) => error.contains('InvalidOutputException')),
        isEmpty,
      );
      _expectFixedBundle(fixture, const ['alpha', 'gamma']);
      _expectFamily(fixture, 'survey/gamma', owner: 'alpha');
      _expectFamily(fixture, 'moved/alpha', owner: 'gamma');
      expect(
        _materializedPaths,
        orderedEquals(<String>[
          'assets/restage/dynamic/moved/alpha.capability.json',
          'assets/restage/dynamic/moved/alpha.rfw',
          'assets/restage/dynamic/survey/gamma.capability.json',
          'assets/restage/dynamic/survey/gamma.rfw',
        ]),
      );

      result = await fixture.apply({
        'lib/restage_dynamic/moved/alpha_renamed.source': _source(
          id: 'alpha',
          surface: 'survey',
          artifacts: _family('survey', 'gamma', owner: 'alpha'),
        ),
        'lib/restage_dynamic/m_gamma.source': _source(
          id: 'gamma',
          surface: 'onboarding',
          artifacts: _family('moved', 'alpha', owner: 'gamma'),
        ),
        // Duplicate roster identity. The fixed normal bundle is still
        // emitted, but invalid, so post-processing reads it, removes the
        // previous families, and fails before writing any delivery family.
        'lib/restage_dynamic/duplicate.source': _source(
          id: 'alpha',
          surface: 'general',
          artifacts: const [
            _Artifact(
              path: 'assets/restage/dynamic/invalid/partial.rfw',
              content: 'must-not-be-materialized',
            ),
            _Artifact(
              path: 'assets/restage/dynamic/invalid/partial.capability.json',
              content: '{"id":"alpha-duplicate"}',
            ),
          ],
        ),
      });
      expect(result.status, build_runner_internal.BuildStatus.failure);
      expect(
        result.errors.join('\n'),
        allOf(
          contains('duplicate delivery identity "alpha"'),
          isNot(contains('AssetNotFoundException')),
          isNot(contains('InvalidOutputException')),
        ),
      );
      expect(result.errors, hasLength(1));
      final invalidBundle = jsonDecode(
        fixture.readerWriter.testing.readString(
          AssetId(_package, _bundlePath),
        ),
      ) as Map<String, Object?>;
      expect(invalidBundle['valid'], isFalse);
      expect(invalidBundle['entries'], isEmpty);
      expect(_allDynamicOutputs(fixture), isEmpty);
      expect(
        fixture.readerWriter.testing.exists(
          AssetId(
            _package,
            'assets/restage/dynamic/invalid/partial.rfw',
          ),
        ),
        isFalse,
      );
      expect(
        _buildTrace,
        orderedEquals(<String>[
          'normal:aggregate',
          'normal:fixed-bundle-written',
          'post:aggregate-read-attempt',
          'post:invalid-roster',
        ]),
      );
      expect(
        _postProcessInputs,
        orderedEquals(
          List<AssetId>.filled(6, AssetId(_package, _bundlePath)),
        ),
      );

      result = await fixture.apply({
        // Recovery uses the same persistent graph after removing the
        // duplicate. The failed post-process marker is an owned output and
        // must be cleaned before the current families are restored.
        'lib/restage_dynamic/moved/alpha_renamed.source': _source(
          id: 'alpha',
          surface: 'survey',
          artifacts: _family('survey', 'gamma', owner: 'alpha'),
        ),
        'lib/restage_dynamic/m_gamma.source': _source(
          id: 'gamma',
          surface: 'onboarding',
          artifacts: _family('moved', 'alpha', owner: 'gamma'),
        ),
      });
      _expectSuccess(result);
      expect(
        fixture.readerWriter.testing.exists(
          AssetId(_package, _failureMarkerPath),
        ),
        isFalse,
      );
      _expectFixedBundle(fixture, const ['alpha', 'gamma']);
      _expectFamily(fixture, 'survey/gamma', owner: 'alpha');
      _expectFamily(fixture, 'moved/alpha', owner: 'gamma');
      expect(
        _allDynamicOutputs(fixture),
        orderedEquals(<String>[
          'assets/restage/dynamic/moved/alpha.capability.json',
          'assets/restage/dynamic/moved/alpha.rfw',
          'assets/restage/dynamic/survey/gamma.capability.json',
          'assets/restage/dynamic/survey/gamma.rfw',
        ]),
      );
      expect(
        _materializedPaths,
        orderedEquals(<String>[
          'assets/restage/dynamic/moved/alpha.capability.json',
          'assets/restage/dynamic/moved/alpha.rfw',
          'assets/restage/dynamic/survey/gamma.capability.json',
          'assets/restage/dynamic/survey/gamma.rfw',
        ]),
      );
      expect(
        _buildTrace,
        orderedEquals(<String>[
          'normal:aggregate',
          'normal:fixed-bundle-written',
          'post:aggregate-read-attempt',
          'post:materialize',
          'post:write:assets/restage/dynamic/moved/alpha.capability.json',
          'post:write:assets/restage/dynamic/moved/alpha.rfw',
          'post:write:assets/restage/dynamic/survey/gamma.capability.json',
          'post:write:assets/restage/dynamic/survey/gamma.rfw',
        ]),
      );
      expect(
        _postProcessInputs,
        orderedEquals(
          List<AssetId>.filled(7, AssetId(_package, _bundlePath)),
        ),
      );
    },
  );
}

void _expectSuccess(build_runner_internal.BuildResult result) {
  expect(
    result.status,
    build_runner_internal.BuildStatus.success,
    reason: result.errors.join('\n'),
  );
  expect(result.errors, isEmpty);
}

void _expectNormalOutputBeforePostMaterialization() {
  expect(
    _buildTrace,
    orderedEquals(<String>[
      'normal:aggregate',
      'normal:fixed-bundle-written',
      'post:aggregate-read-attempt',
      'post:materialize',
      'post:write:assets/restage/dynamic/message/beta.capability.json',
      'post:write:assets/restage/dynamic/message/beta.rfw',
      'post:write:assets/restage/dynamic/onboarding/alpha.capability.json',
      'post:write:assets/restage/dynamic/onboarding/alpha.rfw',
    ]),
  );
}

void _expectFixedBundle(
  _PersistentDynamicOutputBuild fixture,
  List<String> expectedIds,
) {
  final entries = _bundleEntries(fixture);
  expect(
    entries.map((entry) => entry['deliveryId']),
    orderedEquals(expectedIds),
    reason: 'build trace: $_buildTrace',
  );
  for (final entry in entries) {
    final artifacts =
        (entry['artifacts']! as List<Object?>).cast<Map<String, Object?>>();
    expect(
      artifacts.map((artifact) => artifact['path']),
      orderedEquals(
        artifacts.map((artifact) => artifact['path']).toList()..sort(),
      ),
    );
  }
}

List<Map<String, Object?>> _bundleEntries(
  _PersistentDynamicOutputBuild fixture,
) {
  final bundle = jsonDecode(
    fixture.readerWriter.testing.readString(
      AssetId(_package, _bundlePath),
    ),
  ) as Map<String, Object?>;
  expect(bundle['valid'], isTrue);
  return (bundle['entries']! as List<Object?>).cast<Map<String, Object?>>();
}

void _expectFamily(
  _PersistentDynamicOutputBuild fixture,
  String family, {
  required String owner,
}) {
  final base = '$_dynamicPrefix$family';
  final rfw = fixture.readerWriter.testing.readString(
    AssetId(_package, '$base.rfw'),
  );
  final capability = fixture.readerWriter.testing.readString(
    AssetId(_package, '$base.capability.json'),
  );
  expect(rfw, contains('owner:$owner'));
  expect(capability, contains('"owner":"$owner"'));
}

void _expectNoDynamicFamily(
  _PersistentDynamicOutputBuild fixture,
  String family,
) {
  final base = '$_dynamicPrefix$family';
  expect(
    fixture.readerWriter.testing.exists(AssetId(_package, '$base.rfw')),
    isFalse,
  );
  expect(
    fixture.readerWriter.testing
        .exists(AssetId(_package, '$base.capability.json')),
    isFalse,
  );
}

List<String> _allDynamicOutputs(_PersistentDynamicOutputBuild fixture) =>
    fixture.readerWriter.testing.assets
        .where(
          (asset) =>
              asset.package == _package &&
              asset.path.startsWith(_dynamicPrefix),
        )
        .map((asset) => asset.path)
        .toList()
      ..sort();

String _source({
  required String id,
  required String surface,
  required List<_Artifact> artifacts,
}) =>
    jsonEncode(<String, Object?>{
      'deliveryId': id,
      'surface': surface,
      'artifacts': [
        for (final artifact in artifacts)
          <String, String>{
            'path': artifact.path,
            'content': artifact.content,
          },
      ],
    });

List<_Artifact> _family(
  String category,
  String name, {
  String? owner,
}) {
  final artifactOwner = owner ?? name;
  return [
    _Artifact(
      path: '$_dynamicPrefix$category/$name.rfw',
      content: 'owner:$artifactOwner:$category',
    ),
    _Artifact(
      path: '$_dynamicPrefix$category/$name.capability.json',
      content: jsonEncode(<String, String>{
        'owner': artifactOwner,
        'surface': category,
      }),
    ),
  ];
}

final class _Artifact {
  const _Artifact({required this.path, required this.content});

  final String path;
  final String content;
}

final class _PersistentDynamicOutputBuild {
  _PersistentDynamicOutputBuild({
    required this.readerWriter,
    required build_runner_internal.BuildSeries buildSeries,
    required Map<String, String> sources,
  })  : _buildSeries = buildSeries,
        _sources = sources;

  final InternalTestReaderWriter readerWriter;
  final build_runner_internal.BuildSeries _buildSeries;
  Map<String, String> _sources;
  bool _firstBuild = true;

  static Future<_PersistentDynamicOutputBuild> create(
    Map<String, String> initialSources,
  ) async {
    final readerWriter = InternalTestReaderWriter(
      outputRootPackage: _package,
    );
    for (final entry in initialSources.entries) {
      readerWriter.testing.writeString(
        AssetId(_package, entry.key),
        entry.value,
      );
    }
    expect(
      readerWriter.testing.assets.map((asset) => asset.path),
      containsAll(initialSources.keys),
    );
    final buildPackages =
        build_runner_internal.BuildPackages.singlePackageBuild(_package, [
      build_runner_internal.BuildPackage(
        name: _package,
        path: '/$_package',
        watch: true,
        isOutput: true,
      ),
    ]);
    final builderDefinitions =
        <build_runner_internal.AbstractBuilderDefinition>[
      build_runner_internal.BuilderDefinition(
        '$_package:aggregate',
        package: _package,
        autoApply: build_config.AutoApply.none,
        hideOutput: false,
      ),
      build_runner_internal.PostProcessBuilderDefinition(
        '$_package:dynamic',
        package: _package,
        hideOutput: false,
      ),
    ].build();
    final buildConfig = build_config.BuildConfig.fromMap(
      _package,
      const <String>[],
      <String, Object?>{
        'targets': <String, Object?>{
          _package: <String, Object?>{
            // This explicit package-wide input set is the tracked source
            // roster. `lib/$lib$` is only the required placeholder for a
            // package's Dart sources; it does not include arbitrary source
            // families such as the `.source` files used by this proof.
            'sources': <String>[r'\$package$', 'lib/**'],
            'builders': <String, Object?>{
              '$_package:aggregate': <String, Object?>{'enabled': true},
              '$_package:dynamic': <String, Object?>{'enabled': true},
            },
          },
        },
      },
    );
    final testingOverrides = build_runner_internal.TestingOverrides(
      builderDefinitions: builderDefinitions,
      buildConfig: <String, build_config.BuildConfig>{
        _package: buildConfig,
      }.build(),
      buildPackages: buildPackages,
      checkBuilderFreshness: false,
      flattenOutput: true,
      readerWriter: readerWriter,
    );
    final builderFactories = build_runner_internal.BuilderFactories(
      <String, List<BuilderFactory>>{
        '$_package:aggregate': [
          (_) => const _DynamicAggregateBuilder(),
        ],
      },
      postProcessBuilderFactories: <String, PostProcessBuilderFactory>{
        '$_package:dynamic': (_) => const _DynamicArtifactBuilder(),
      },
    );
    final buildPlan = await build_runner_internal.BuildPlan.load(
      builderFactories: builderFactories,
      buildOptions: build_runner_internal.BuildOptions.forTests(),
      testingOverrides: testingOverrides,
    );
    return _PersistentDynamicOutputBuild(
      readerWriter: readerWriter,
      buildSeries: build_runner_internal.BuildSeries(buildPlan),
      sources: Map.of(initialSources),
    );
  }

  Future<build_runner_internal.BuildResult> apply(
    Map<String, String> nextSources,
  ) async {
    _buildTrace.clear();
    _materializedPaths.clear();
    final updates = <AssetId>{};
    for (final path in _sources.keys) {
      if (!nextSources.containsKey(path)) {
        final id = AssetId(_package, path);
        readerWriter.testing.delete(id);
        updates.add(id);
      }
    }
    for (final entry in nextSources.entries) {
      if (_sources[entry.key] != entry.value) {
        final id = AssetId(_package, entry.key);
        readerWriter.testing.writeString(id, entry.value);
        updates.add(id);
      }
    }
    _sources = Map.of(nextSources);
    final result = await _buildSeries.run(
      _firstBuild ? const <AssetId>{} : updates,
      recentlyBootstrapped: _firstBuild,
    );
    _firstBuild = false;
    return result;
  }

  Future<void> close() => _buildSeries.close();
}

final class _DynamicAggregateBuilder implements Builder {
  const _DynamicAggregateBuilder();

  @override
  Map<String, List<String>> get buildExtensions => const {
        r'$package$': [_bundlePath],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    _buildTrace.add('normal:aggregate');
    final sources = await buildStep
        .findAssets(Glob('lib/**'))
        .where((asset) => asset.path.endsWith('.source'))
        .toList()
      ..sort((left, right) => left.path.compareTo(right.path));
    final entries = <Map<String, Object?>>[];
    final owners = <String, AssetId>{};
    final errors = <String>[];
    for (final source in sources) {
      final entry = jsonDecode(await buildStep.readAsString(source))
          as Map<String, Object?>;
      final id = entry['deliveryId']! as String;
      final previous = owners[id];
      if (previous != null) {
        errors.add(
          'duplicate delivery identity "$id": ${previous.path}, '
          '${source.path}',
        );
        continue;
      }
      owners[id] = source;
      final artifacts =
          (entry['artifacts']! as List<Object?>).cast<Map<String, Object?>>();
      final seenPaths = <String>{};
      if (artifacts.any((artifact) {
        final path = artifact['path']! as String;
        return !seenPaths.add(path) || path.endsWith('.dart');
      })) {
        errors.add('invalid artifact family for "$id"');
        continue;
      }
      artifacts.sort(
        (left, right) =>
            (left['path']! as String).compareTo(right['path']! as String),
      );
      entries.add(<String, Object?>{
        'deliveryId': id,
        'surface': entry['surface']! as String,
        'sourcePath': source.path,
        'artifacts': artifacts,
      });
    }
    entries.sort(
      (left, right) => (left['deliveryId']! as String).compareTo(
        right['deliveryId']! as String,
      ),
    );
    final bundle = <String, Object?>{
      'schemaVersion': 1,
      'valid': errors.isEmpty,
      'errors': errors..sort(),
      'entries': errors.isEmpty ? entries : const <Object?>[],
    };
    await buildStep.writeAsString(
      AssetId(buildStep.inputId.package, _bundlePath),
      const JsonEncoder.withIndent('  ').convert(bundle),
    );
    _buildTrace.add('normal:fixed-bundle-written');
  }
}

final class _DynamicArtifactBuilder implements PostProcessBuilder {
  const _DynamicArtifactBuilder();

  @override
  Iterable<String> get inputExtensions => const ['.bundle.json'];

  @override
  Future<void> build(PostProcessBuildStep buildStep) async {
    _postProcessInputs.add(buildStep.inputId);
    _buildTrace.add('post:aggregate-read-attempt');
    final bundle =
        jsonDecode(await buildStep.readInputAsString()) as Map<String, Object?>;
    if (bundle['valid'] != true) {
      _buildTrace.add('post:invalid-roster');
      // build_runner records post-process diagnostics as a failed build only
      // when the step has an output. This marker is deliberately outside the
      // delivery namespace; it is not a dynamic artifact family and carries
      // the same duplicate diagnostic that makes the step fail.
      await buildStep.writeAsString(
        AssetId(buildStep.inputId.package, _failureMarkerPath),
        (bundle['errors']! as List<Object?>).join('; '),
      );
      throw StateError((bundle['errors']! as List<Object?>).join('; '));
    }
    final entries =
        (bundle['entries']! as List<Object?>).cast<Map<String, Object?>>();
    final artifacts = <Map<String, Object?>>[];
    for (final entry in entries) {
      artifacts.addAll(
        (entry['artifacts']! as List<Object?>).cast<Map<String, Object?>>(),
      );
    }
    artifacts.sort(
      (left, right) =>
          (left['path']! as String).compareTo(right['path']! as String),
    );
    _buildTrace.add('post:materialize');
    for (final artifact in artifacts) {
      final path = artifact['path']! as String;
      _materializedPaths.add(path);
      _buildTrace.add('post:write:$path');
      await buildStep.writeAsString(
        AssetId(buildStep.inputId.package, path),
        artifact['content']! as String,
      );
    }
  }
}
