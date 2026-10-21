// A surface Measurement cannot fully resolve compiles unmeasured, with a
// diagnostic naming it — never a build break, and never a partial plan.

import 'dart:convert';
import 'dart:io';

import 'package:build/build.dart';
import 'package:path/path.dart' as p;
import 'package:restage_codegen/builder.dart';
import 'package:restage_codegen/src/measurement/measurement_compiler_output.dart';
import 'package:restage_codegen/src/measurement/measurement_route_emission.dart'
    show kMeasurementRouteArgumentKeyV1;
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    show kMeasurementPublicationTapEventNameV1;
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
    final unmeasured = compiled.output.unmeasured.single;
    expect(unmeasured.selector.slug, _branchingSlug);
    expect(unmeasured.reason, contains('&& or ||'));
    expect(
      RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
        compiled.output.canonicalBytes,
      ).unmeasured.single.reason,
      unmeasured.reason,
    );
    expect(
      utf8.decode(compiled.output.outputIndexBytes(_package)),
      contains('"unmeasured"'),
      reason: 'push reads the reason from the Measurement index',
    );
    expect(
      utf8.decode(compiled.output.durableState.canonicalBytes),
      isNot(contains('unmeasured')),
    );
    expectUnmeasuredScreenPublication(
      readerWriter: compiled.readerWriter,
      packageName: _package,
      sourcePath: _branchingSourcePath,
      bundlePath: _branchingBundlePath,
      surface: Surface.general,
      slug: _branchingSlug,
    );
  });

  test('a state-update paywall publishes measurement with its handlers intact',
      () async {
    final compiled = await _compileFixture(_statefulPaywallSourcePath);

    expect(
      compiled.output.valid,
      isTrue,
      reason: compiled.output.errors.join('\n'),
    );
    expect(compiled.output.publications, hasLength(1));
    expect(compiled.log, isNot(contains('compiles unmeasured')));
    _expectMeasuredStatefulPaywall(compiled.readerWriter);
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

/// The plan card's local state update pairs with the routed measure-only tap;
/// the close control's host event carries its own route.
void _expectMeasuredStatefulPaywall(TestReaderWriter readerWriter) {
  final manifest = SurfacePublicationManifestV1Codec.decodeJson(
    readerWriter.testing.readString(
      AssetId(_package, '.restage/build/metadata/restage.publication.json'),
    ),
  );
  final publication = manifest.publications.single;
  expect(publication.publication.slug, _statefulPaywallSlug);
  final bundle = RestageBundleCodec.decode(
    readerWriter.testing.readBytes(
      AssetId(_package, _statefulPaywallBundlePath),
    ),
  );
  final blobPath = publication.artifacts
      .singleWhere(
        (artifact) =>
            artifact.role == SurfacePublicationArtifactRole.screenBlob,
      )
      .path;
  final library = fmt.decodeLibraryBlob(
    bundle.entries
        .singleWhere((artifact) => artifact.logicalPath == blobPath)
        .bytes,
  );

  final handlers = rfwEventHandlers(library);
  final stateHandler = handlers.whereType<fmt.SetStateHandler>().single;
  expect(
    (stateHandler.stateReference as fmt.StateReference).parts,
    ['annualSelected'],
  );
  expect(stateHandler.value, isFalse);
  final events = handlers.whereType<fmt.EventHandler>().toList();
  expect(
    events.map((event) => event.eventName),
    unorderedEquals(['close', kMeasurementPublicationTapEventNameV1]),
  );
  for (final event in events) {
    expect(
      event.eventArguments[kMeasurementRouteArgumentKeyV1],
      isA<String>(),
    );
  }
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
