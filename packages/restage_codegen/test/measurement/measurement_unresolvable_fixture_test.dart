// A surface Measurement cannot fully resolve compiles unmeasured, with a
// diagnostic naming it — never a build break, and never a partial plan.

import 'dart:io';

import 'package:build/build.dart';
import 'package:path/path.dart' as p;
import 'package:restage_codegen/builder.dart';
import 'package:restage_codegen/src/measurement/measurement_compiler_output.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as fmt;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../helpers.dart';
import 'measurement_fixture_helpers.dart';

const _fixtureRoot = 'test/fixtures/measurement_unresolvable';
const _package = 'apps_examples';
const _branchingSourcePath = 'lib/surfaces/branching_notice.dart';
const _branchingBundlePath =
    'assets/restage/bundles/lib/surfaces/branching_notice.rsbundle';
const _branchingSlug = 'branching_notice';
const _statefulPaywallSourcePath = 'lib/paywalls/stateful_choice.dart';
const _statefulPaywallBundlePath =
    'assets/restage/bundles/lib/paywalls/stateful_choice.rsbundle';
const _statefulPaywallSlug = 'stateful_choice';

void main() {
  test('an unresolvable surface compiles unmeasured, and says so', () async {
    final compiled = await _compileFixture(_branchingSourcePath);

    expect(
      compiled.output.valid,
      isTrue,
      reason: compiled.output.errors.join('\n'),
    );
    expect(
      compiled.output.publications,
      isEmpty,
      reason: 'a surface Measurement cannot resolve must get no partial plan',
    );
    expect(
      compiled.log,
      contains('Measurement is unavailable for'),
      reason: 'the boundary must name the surface, not skip silently',
    );
    expect(compiled.log, contains('compiles unmeasured'));
    expectUnmeasuredScreenPublication(
      readerWriter: compiled.readerWriter,
      packageName: _package,
      sourcePath: _branchingSourcePath,
      bundlePath: _branchingBundlePath,
      surface: Surface.general,
      slug: _branchingSlug,
    );
  });

  test('a state-update paywall compiles unmeasured with its handlers intact',
      () async {
    final compiled = await _compileFixture(_statefulPaywallSourcePath);

    expect(
      compiled.output.valid,
      isTrue,
      reason: compiled.output.errors.join('\n'),
    );
    expect(compiled.output.publications, isEmpty);
    expect(compiled.log, contains('Flutter State method tear-off'));
    expect(compiled.log, contains('compiles unmeasured'));
    _expectUnmeasuredStatefulPaywall(compiled.readerWriter);
  });
}

class _Compiled {
  const _Compiled(this.output, this.log, this.readerWriter);
  final RestageMeasurementCompilerOutputV1 output;
  final String log;
  final TestReaderWriter readerWriter;
}

Future<_Compiled> _compileFixture(String sourcePath) async {
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
      '$_package|$sourcePath':
          File(p.join(_fixtureRoot, sourcePath)).readAsStringSync(),
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

void _expectUnmeasuredStatefulPaywall(TestReaderWriter readerWriter) {
  final manifest = SurfacePublicationManifestV1Codec.decodeJson(
    readerWriter.testing.readString(
      AssetId(_package, 'lib/generated/restage.publication.json'),
    ),
  );
  expect(manifest.publications, hasLength(1));
  final publication = manifest.publications.single;
  expect(publication.publication.surface, Surface.paywall);
  expect(publication.publication.slug, _statefulPaywallSlug);
  expect(publication.publication.sourceKind, SurfaceSourceKind.paywall);
  expect(publication.publication.payloadKind, SurfacePayloadKind.blob);
  expect(publication.sources, <String>[_statefulPaywallSourcePath]);

  final bundle = RestageBundleCodec.decode(
    readerWriter.testing.readBytes(
      AssetId(_package, _statefulPaywallBundlePath),
    ),
  );
  expect(bundle.packageName, _package);
  expect(bundle.authoredLibraryPath, _statefulPaywallSourcePath);
  final deliveryFiles = <String, List<int>>{
    for (final artifact in bundle.entries)
      if (artifact.role != RestageBundleEntryRole.rfwText)
        artifact.logicalPath: artifact.bytes,
  };
  expect(manifest.validateArtifactClosure(deliveryFiles), hasLength(1));

  final blobPath = publication.artifacts
      .singleWhere(
        (artifact) =>
            artifact.role == SurfacePublicationArtifactRole.screenBlob,
      )
      .path;
  final blob = bundle.entries.singleWhere(
    (artifact) => artifact.logicalPath == blobPath,
  );
  final library = fmt.decodeLibraryBlob(blob.bytes);
  expectNoMeasurementRfwIdentities(library);

  final handlers = rfwEventHandlers(library);
  final stateHandler = handlers.whereType<fmt.SetStateHandler>().single;
  expect(
    (stateHandler.stateReference as fmt.StateReference).parts,
    ['annualSelected'],
  );
  expect(stateHandler.value, isFalse);
  final hostEvent = handlers.whereType<fmt.EventHandler>().single;
  expect(hostEvent.eventName, 'close');
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
