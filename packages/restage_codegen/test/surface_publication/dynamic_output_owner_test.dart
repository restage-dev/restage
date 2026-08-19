import 'dart:convert';
import 'dart:typed_data';

import 'package:build/build.dart';
import 'package:build_config/build_config.dart' as build_config;
import 'package:build_runner/src/internal.dart' as build_runner_internal;
import 'package:build_test/build_test.dart';
import 'package:build_test/src/internal_test_reader_writer.dart';
import 'package:built_collection/built_collection.dart';
import 'package:glob/glob.dart';
import 'package:restage_codegen/src/surface_publication/dynamic_output_owner.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

const _package = 'fu0375_surface_publication_owner_fixture';

void main() {
  test('round-trips a strict bundle with its complete artifact closure', () {
    final source = _publicationSource(
      id: 'notice',
      surface: Surface.general,
      byte: 7,
    );
    final bundle = _bundleForSources([source]);
    final decoded = RestageSurfacePublicationBundle.fromJson(
      jsonDecode(bundle.encodeCanonicalJson()),
    );

    expect(decoded.valid, isTrue);
    expect(decoded.errors, isEmpty);
    expect(decoded.manifest!.publications.single.publication.slug, 'notice');
    expect(
      decoded.artifacts.keys,
      containsAll(<String>[
        'assets/general/screens/notice.rfw',
        'assets/general/screens/notice.capability.json',
      ]),
    );
    expect(
      decoded.ownedOutputs.keys,
      containsAll(<String>[
        'assets/general/screens/notice.rfwtxt',
        'lib/generated/notice.rsscreen.g.dart',
      ]),
    );
  });

  for (final compilerInput in <String, String?>{
    'a missing': null,
    'an empty': RestageSurfacePublicationBundle.valid(
      manifest: SurfacePublicationManifestV1(publications: const []),
      artifacts: const {},
    ).encodeCanonicalJson(),
  }.entries) {
    test(
        'fails closed for canonical admission with ${compilerInput.key} '
        'compiler bundle', () async {
      final aggregate = await _runAggregateBuilder(
        compilerBundle: compilerInput.value,
      );

      expect(aggregate.valid, isFalse);
      expect(aggregate.manifest, isNull);
      expect(aggregate.artifacts, isEmpty);
      expect(
        aggregate.errors.single,
        allOf(
          contains('Canonical Restage sources'),
          anyOf(contains('bundle'), contains('manifest')),
        ),
      );
    });
  }

  test('owns add/remove/move/reclassify and invalid recovery incrementally',
      () async {
    final initial = <String, String>{
      'lib/sources/a.source': _publicationSource(
        id: 'alpha',
        surface: Surface.general,
        byte: 1,
      ),
      'lib/sources/b.source': _publicationSource(
        id: 'beta',
        surface: Surface.message,
        byte: 2,
      ),
    };
    final fixture = await _PersistentOwnerBuild.create(initial);
    addTearDown(fixture.close);

    var result = await fixture.apply(initial);
    _expectSuccess(result);
    expect(
      fixture.readerWriter.testing.exists(
        AssetId(_package, kRestageSurfacePublicationCompilerBundlePath),
      ),
      isTrue,
    );
    expect(
      fixture.readerWriter.testing.exists(
        AssetId(_package, kRestageSurfacePublicationBundlePath),
      ),
      isTrue,
    );
    _expectArtifact(fixture, 'general/screens/alpha', 1);
    _expectArtifact(fixture, 'message/screens/beta', 2);
    _expectManifest(fixture, const ['alpha', 'beta']);

    result = await fixture.apply({
      ...initial,
      'lib/sources/c.source': _publicationSource(
        id: 'gamma',
        surface: Surface.survey,
        byte: 3,
      ),
    });
    _expectSuccess(result);
    _expectArtifact(fixture, 'survey/screens/gamma', 3);

    result = await fixture.apply({
      'lib/sources/moved_alpha.source': _publicationSource(
        id: 'alpha',
        surface: Surface.general,
        byte: 4,
      ),
      'lib/sources/b.source': initial['lib/sources/b.source']!,
      'lib/sources/c.source': _publicationSource(
        id: 'gamma',
        surface: Surface.survey,
        byte: 3,
      ),
    });
    _expectSuccess(result);
    _expectArtifact(fixture, 'general/screens/alpha', 4);

    result = await fixture.apply({
      'lib/sources/moved_alpha.source': _publicationSource(
        id: 'gamma',
        surface: Surface.general,
        byte: 5,
      ),
      'lib/sources/c.source': _publicationSource(
        id: 'alpha',
        surface: Surface.survey,
        byte: 6,
      ),
    });
    _expectSuccess(result);
    _expectArtifact(fixture, 'general/screens/gamma', 5);
    _expectArtifact(fixture, 'survey/screens/alpha', 6);
    _expectNoArtifact(fixture, 'message/screens/beta');
    _expectNoArtifact(fixture, 'general/screens/alpha');
    _expectNoArtifact(fixture, 'survey/screens/gamma');

    result = await fixture.apply({
      'lib/sources/moved_alpha.source': _publicationSource(
        id: 'gamma',
        surface: Surface.general,
        byte: 7,
      ),
      'lib/sources/c.source': _publicationSource(
        id: 'gamma',
        surface: Surface.general,
        byte: 8,
      ),
    });
    expect(result.status, build_runner_internal.BuildStatus.failure);
    expect(
      result.errors.join('\n'),
      contains('duplicate publication identity'),
    );
    expect(_allGeneratedOutputs(fixture), isEmpty);
    expect(
      fixture.readerWriter.testing.exists(
        AssetId(_package, kRestageSurfacePublicationManifestPath),
      ),
      isFalse,
    );
    expect(
      fixture.readerWriter.testing.exists(
        AssetId(_package, kRestageSurfacePublicationInvalidPath),
      ),
      isTrue,
    );

    result = await fixture.apply({
      'lib/sources/moved_alpha.source': _publicationSource(
        id: 'alpha',
        surface: Surface.general,
        byte: 7,
      ),
    });
    _expectSuccess(result);
    _expectArtifact(fixture, 'general/screens/alpha', 7);
    _expectNoArtifact(fixture, 'general/screens/gamma');
    expect(
      fixture.readerWriter.testing.exists(
        AssetId(_package, 'lib/generated/gamma.rsscreen.g.dart'),
      ),
      isFalse,
    );
    expect(
      fixture.readerWriter.testing.exists(
        AssetId(_package, kRestageSurfacePublicationInvalidPath),
      ),
      isFalse,
    );
  });
}

Future<RestageSurfacePublicationBundle> _runAggregateBuilder({
  required String? compilerBundle,
}) async {
  String? encodedOutput;
  await testBuilder(
    const RestageSurfacePublicationBundleBuilder(BuilderOptions.empty),
    <String, String>{
      '$_package|assets/restage/source-index.json': jsonEncode(
        <String, Object?>{
          'sources': <Object?>[
            <String, Object?>{'authoring': 'canonical'},
          ],
        },
      ),
      if (compilerBundle != null)
        '$_package|$kRestageSurfacePublicationCompilerBundlePath':
            compilerBundle,
    },
    rootPackage: _package,
    outputs: <String, Matcher>{
      '$_package|$kRestageSurfacePublicationBundlePath': decodedMatches(
        predicate<String>((value) {
          encodedOutput = value;
          return true;
        }),
      ),
    },
  );
  return RestageSurfacePublicationBundle.fromJson(
    jsonDecode(encodedOutput!),
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

void _expectManifest(
  _PersistentOwnerBuild fixture,
  List<String> expectedSlugs,
) {
  final manifest = SurfacePublicationManifestV1Codec.decodeJson(
    fixture.readerWriter.testing.readString(
      AssetId(_package, kRestageSurfacePublicationManifestPath),
    ),
  );
  expect(
    manifest.publications.map((entry) => entry.publication.slug),
    orderedEquals(expectedSlugs),
  );
}

void _expectArtifact(_PersistentOwnerBuild fixture, String family, int byte) {
  final path = 'assets/$family.rfw';
  expect(
    fixture.readerWriter.testing.readBytes(AssetId(_package, path)),
    orderedEquals(<int>[byte]),
  );
  expect(
    fixture.readerWriter.testing.exists(
      AssetId(_package, 'assets/$family.rfwtxt'),
    ),
    isTrue,
  );
}

void _expectNoArtifact(_PersistentOwnerBuild fixture, String family) {
  expect(
    fixture.readerWriter.testing.exists(
      AssetId(_package, 'assets/$family.rfw'),
    ),
    isFalse,
  );
  expect(
    fixture.readerWriter.testing.exists(
      AssetId(
        _package,
        'assets/$family.capability.json',
      ),
    ),
    isFalse,
  );
  expect(
    fixture.readerWriter.testing.exists(
      AssetId(_package, 'assets/$family.rfwtxt'),
    ),
    isFalse,
  );
}

List<String> _allGeneratedOutputs(_PersistentOwnerBuild fixture) =>
    fixture.readerWriter.testing.assets
        .where(
          (asset) =>
              asset.package == _package &&
              (RegExp('^assets/[^/]+/screens/').hasMatch(asset.path) ||
                  (asset.path.startsWith('lib/generated/') &&
                      asset.path.endsWith('.g.dart'))),
        )
        .map((asset) => asset.path)
        .toList()
      ..sort();

String _publicationSource({
  required String id,
  required Surface surface,
  required int byte,
}) =>
    jsonEncode(<String, Object?>{
      'id': id,
      'surface': surface.wireName,
      'byte': byte,
    });

RestageSurfacePublicationBundle _bundleForSources(
  Iterable<String> encodedSources,
) {
  final manifests = <SurfacePublicationManifestEntryV1>[];
  final files = <String, List<int>>{};
  final ownedOutputs = <String, List<int>>{};
  for (final encoded in encodedSources) {
    final source = jsonDecode(encoded) as Map<String, Object?>;
    final id = source['id']! as String;
    final surface = Surface.fromWireName(source['surface']! as String);
    final blob = Uint8List.fromList(<int>[source['byte']! as int]);
    final capabilities = CapabilityManifest(
      builtInFloor: 1,
      requiredLibraries: const [],
    );
    final eventContract = SurfaceScreenEventSchemaV1(events: const []);
    final eventContractHash = SurfaceScreenEventContractHashV1.hash(
      eventContract,
    );
    final fingerprint = SurfaceScreenContractFingerprintV1.hash(
      sourceKind: SurfaceSourceKind.screen,
      payloadKind: SurfacePayloadKind.blob,
      capabilities: capabilities,
      eventContractHash: eventContractHash,
    );
    final payload = BlobSurfacePayload(minClient: 1, blob: blob);
    final publication = SurfacePublicationV1(
      surface: surface,
      slug: id,
      sourceKind: SurfaceSourceKind.screen,
      payloadKind: SurfacePayloadKind.blob,
      payloadContentHash: payload.contentHash,
      contractVersion: 1,
      capabilities: capabilities,
      eventContract: eventContract,
      eventContractHash: eventContractHash,
      contractFingerprint: fingerprint,
    );
    final outputStem = 'assets/${surface.wireName}/screens/$id';
    final blobPath = '$outputStem.rfw';
    final sidecarPath = '$outputStem.capability.json';
    final sidecar = utf8.encode(
      jsonEncode(
        CapabilitySidecar(
          blobSha256: CapabilitySidecar.hashBlob(blob),
          manifest: capabilities,
        ).toJson(),
      ),
    );
    manifests.add(
      SurfacePublicationManifestEntryV1(
        publication: publication,
        artifacts: [
          SurfacePublicationArtifactV1(
            contentHash: CapabilitySidecar.hashBlob(blob),
            path: blobPath,
            role: SurfacePublicationArtifactRoleV1.screenBlob,
            id: id,
          ),
          SurfacePublicationArtifactV1(
            contentHash: CapabilitySidecar.hashBlob(sidecar),
            path: sidecarPath,
            role: SurfacePublicationArtifactRoleV1.capabilitySidecar,
            id: id,
          ),
        ],
      ),
    );
    files[blobPath] = blob;
    files[sidecarPath] = sidecar;
    ownedOutputs['$outputStem.rfwtxt'] = utf8.encode('screen $id');
    ownedOutputs['lib/generated/$id.rsscreen.g.dart'] = utf8.encode(
      "part of '$id.dart';\n",
    );
  }
  return RestageSurfacePublicationBundle.valid(
    manifest: SurfacePublicationManifestV1(publications: manifests),
    artifacts: files,
    ownedOutputs: ownedOutputs,
  );
}

final class _PersistentOwnerBuild {
  _PersistentOwnerBuild({
    required this.readerWriter,
    required build_runner_internal.BuildSeries buildSeries,
    required Map<String, String> sources,
  })  : _buildSeries = buildSeries,
        _sources = Map.of(sources);

  final InternalTestReaderWriter readerWriter;
  final build_runner_internal.BuildSeries _buildSeries;
  Map<String, String> _sources;
  bool _firstBuild = true;

  static Future<_PersistentOwnerBuild> create(
    Map<String, String> initialSources,
  ) async {
    final readerWriter = InternalTestReaderWriter(outputRootPackage: _package);
    for (final entry in initialSources.entries) {
      readerWriter.testing
          .writeString(AssetId(_package, entry.key), entry.value);
    }
    final buildPackages =
        build_runner_internal.BuildPackages.singlePackageBuild(
      _package,
      [
        build_runner_internal.BuildPackage(
          name: _package,
          path: '/$_package',
          watch: true,
          isOutput: true,
        ),
      ],
    );
    final builderDefinitions =
        <build_runner_internal.AbstractBuilderDefinition>[
      build_runner_internal.BuilderDefinition(
        '$_package:compiler',
        package: _package,
        autoApply: build_config.AutoApply.none,
        hideOutput: false,
      ),
      build_runner_internal.BuilderDefinition(
        '$_package:aggregate',
        package: _package,
        autoApply: build_config.AutoApply.none,
        hideOutput: false,
      ),
      build_runner_internal.PostProcessBuilderDefinition(
        '$_package:owner',
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
            'sources': <String>[r'\$package$', 'lib/**'],
            'builders': <String, Object?>{
              '$_package:compiler': <String, Object?>{'enabled': true},
              '$_package:aggregate': <String, Object?>{'enabled': true},
              '$_package:owner': <String, Object?>{'enabled': true},
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
        '$_package:compiler': [
          (_) => const _OwnerCompilerBuilder(),
        ],
        '$_package:aggregate': [
          RestageSurfacePublicationBundleBuilder.new,
        ],
      },
      postProcessBuilderFactories: <String, PostProcessBuilderFactory>{
        '$_package:owner': RestageSurfacePublicationOutputOwner.new,
      },
    );
    final buildPlan = await build_runner_internal.BuildPlan.load(
      builderFactories: builderFactories,
      buildOptions: build_runner_internal.BuildOptions.forTests(),
      testingOverrides: testingOverrides,
    );
    return _PersistentOwnerBuild(
      readerWriter: readerWriter,
      buildSeries: build_runner_internal.BuildSeries(buildPlan),
      sources: initialSources,
    );
  }

  Future<build_runner_internal.BuildResult> apply(
    Map<String, String> nextSources,
  ) async {
    final updates = <AssetId>{};
    for (final path in _sources.keys) {
      if (!nextSources.containsKey(path)) {
        readerWriter.testing.delete(AssetId(_package, path));
        updates.add(AssetId(_package, path));
      }
    }
    for (final entry in nextSources.entries) {
      if (_sources[entry.key] != entry.value) {
        readerWriter.testing.writeString(
          AssetId(_package, entry.key),
          entry.value,
        );
        updates.add(AssetId(_package, entry.key));
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

final class _OwnerCompilerBuilder implements Builder {
  const _OwnerCompilerBuilder();

  @override
  Map<String, List<String>> get buildExtensions => const {
        r'$package$': [kRestageSurfacePublicationCompilerBundlePath],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    final sources = await buildStep
        .findAssets(Glob('lib/**'))
        .where((asset) => asset.path.endsWith('.source'))
        .toList()
      ..sort((left, right) => left.path.compareTo(right.path));
    final entries = <String>[];
    final owners = <String, AssetId>{};
    final errors = <String>[];
    for (final source in sources) {
      try {
        final value = jsonDecode(await buildStep.readAsString(source))
            as Map<String, Object?>;
        final id = value['id']! as String;
        final surface = value['surface']! as String;
        final identity = '$surface/$id';
        final previous = owners[identity];
        if (previous != null) {
          errors.add(
            'duplicate publication identity "$identity": ${previous.path}, '
            '${source.path}',
          );
          continue;
        }
        owners[identity] = source;
        entries.add(jsonEncode(value));
      } on Object catch (error) {
        errors.add('${source.path}: $error');
      }
    }
    final bundle = errors.isEmpty
        ? _bundleForSources(entries)
        : RestageSurfacePublicationBundle.invalid(errors);
    await buildStep.writeAsString(
      AssetId(
        buildStep.inputId.package,
        kRestageSurfacePublicationCompilerBundlePath,
      ),
      bundle.encodeCanonicalJson(),
    );
  }
}
