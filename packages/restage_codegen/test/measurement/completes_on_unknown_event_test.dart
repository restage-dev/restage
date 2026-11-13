// A paywall's completing event must be fired by a tap or by its own code.

import 'dart:io';

import 'package:build/build.dart';
import 'package:path/path.dart' as p;
import 'package:restage_codegen/src/measurement/measurement_compiler_output.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../helpers.dart';
import '../support/surface_build_chain.dart';

const _fixtureRoot = 'test/fixtures/completes_on_unknown';
const _package = 'apps_examples';

void main() {
  test(
    'completesOn naming an event the paywall never fires is a build error',
    () async {
      final compiled = await _compileFixture('lib/paywalls/stray_offer.dart');
      expect(compiled.succeeded, isFalse);
      expect(
        compiled.log,
        allOf(
          contains(
            "completesOn names the event 'subscribe', which this paywall's "
            'own file never fires. Fire it from app code in '
            'package:apps_examples/paywalls/stray_offer.dart',
          ),
          contains('A call in another file is not seen'),
          contains('context.surfaceEvent(<the declared event constant>)'),
        ),
      );
    },
  );

  for (final fixture in ['conditional_offer']) {
    test(
      'a tap firing a completing event builds with a warning: $fixture',
      () async {
        final compiled = await _compileFixture('lib/paywalls/$fixture.dart');
        expect(compiled.succeeded, isTrue, reason: compiled.log);
        expect(
          compiled.log,
          contains(
            'which only a tap fires, and a tap never '
            'completes the paywall',
          ),
        );
      },
    );
  }

  for (final (fixture, label) in [
    ('app_fired_offer', 'in the build'),
    ('child_fired_offer', 'in a private child widget'),
  ]) {
    test(
      'app code that fires the completing event $label declares the '
      'completion route and warns nothing',
      () async {
        final compiled = await _compileFixture('lib/paywalls/$fixture.dart');
        expect(compiled.succeeded, isTrue, reason: compiled.log);
        expect(compiled.log, isNot(contains('only a tap fires')));
        final routes = _routes(compiled);
        expect(
          routes.map((route) => route.orderedCaptureV1?.lifecycleChannel),
          contains(MeasurementOccurrenceChannelV1.completion),
        );
        final generated = compiled.readerWriter.testing.readString(
          AssetId(
            _package,
            'lib/paywalls/restage.generated/$fixture.restage.g.dart',
          ),
        );
        expect(generated, contains("completesOn: const <String>{'purchased'}"));
      },
    );
  }
}

List<MeasurementPublicationDraftRouteV1> _routes(
  ({bool succeeded, String log, TestReaderWriter readerWriter}) compiled,
) => RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
  compiled.readerWriter.testing.readBytes(
    AssetId(_package, kRestageMeasurementCompilerOutputPath),
  ),
).publications.single.routePlan.routes;

Future<({bool succeeded, String log, TestReaderWriter readerWriter})>
_compileFixture(String path) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: _package,
  );
  final logs = <String>[];
  final result = await testBuilders(
    [
      ...surfaceBuildChain(options: _builderOptions),
    ],
    {'$_package|$path': File(p.join(_fixtureRoot, path)).readAsStringSync()},
    rootPackage: _package,
    readerWriter: readerWriter,
    flattenOutput: true,
    verbose: true,
    onLog: (record) => logs.add(record.message),
  );
  return (
    succeeded: result.succeeded,
    log: [...logs, ...result.errors].join('\n'),
    readerWriter: readerWriter,
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
        _stringKey(entry.key, 'builder $builderKey option'): _yamlValue(
          entry.value,
        ),
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
