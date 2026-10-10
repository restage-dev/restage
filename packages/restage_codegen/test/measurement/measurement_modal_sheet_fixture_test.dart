// A callback that opens a declarative sheet is a routed tap, and the sheet
// body is measured under that tap's sheet scope.

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

import '../helpers.dart';
import 'measurement_fixture_helpers.dart';

const _fixtureRoot = 'test/fixtures/measurement_modal_sheet';
const _package = 'apps_examples';
const _sourcePath = 'lib/surfaces/sheet_notice.dart';
const _bundlePath = 'assets/restage/bundles/lib/surfaces/sheet_notice.rsbundle';
const _slug = 'sheet_notice';

const _source = 'package:apps_examples/surfaces/sheet_notice.dart#SheetNotice';
const _column = 'package:flutter/src/widgets/basic.dart#Column';
const _padding = 'package:flutter/src/widgets/basic.dart#Padding';
const _filled = 'package:flutter/src/material/filled_button.dart#FilledButton';
const _text = 'package:flutter/src/material/text_button.dart#TextButton';

void main() {
  test('a sheet-opening callback and the sheet body are measured', () async {
    final compiled = await _compileFixture();

    expect(
      compiled.output.valid,
      isTrue,
      reason: compiled.output.errors.join('\n'),
    );
    expect(compiled.log, isNot(contains('compiles unmeasured')));
    expect(
      compiled.output.publications
          .map((publication) => publication.selector.slug),
      <String>[_slug],
    );

    const trigger = '$_source|child:$_column:$_column.children[0]|'
        'widget:$_filled';
    const sheet = '$trigger|sheet:onPressed:builder';
    const close = '$sheet|child:$_padding:$_padding.child[0]|'
        'child:$_column:$_column.children[1]|widget:$_text';
    final routed = {
      for (final node in compiled.output.ledgerNodes)
        for (final event in node.events)
          if (event.active)
            '${node.structuralOccurrenceKey}\u0000'
                '${event.sourceEventIdentity.value}',
    };
    expect(
      routed,
      containsAll(<String>['$trigger\u0000onPressed', '$close\u0000onPressed']),
    );
    expect(
      compiled.output.ledgerNodes.map((node) => node.structuralOccurrenceKey),
      contains('$sheet|widget:$_padding'),
    );

    // Opening and closing change sheet state; each pairs the state update
    // with the measure-only tap that carries its route.
    final bundle = RestageBundleCodec.decode(
      compiled.readerWriter.testing.readBytes(AssetId(_package, _bundlePath)),
    );
    final blob = bundle.entries.singleWhere(
      (entry) => entry.logicalPath.endsWith('.rfw'),
    );
    final handlers = rfwEventHandlers(fmt.decodeLibraryBlob(blob.bytes));
    final taps = handlers.whereType<fmt.EventHandler>().where(
          (handler) =>
              handler.eventName == kMeasurementPublicationTapEventNameV1,
        );
    expect(taps, hasLength(2));
    for (final tap in taps) {
      expect(
        tap.eventArguments.keys,
        <String>[kMeasurementPublicationRouteArgumentKeyV1],
      );
    }
  });
}

class _Compiled {
  const _Compiled(this.output, this.log, this.readerWriter);
  final RestageMeasurementCompilerOutputV1 output;
  final String log;
  final TestReaderWriter readerWriter;
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
      '$_package|$_sourcePath':
          File(p.join(_fixtureRoot, _sourcePath)).readAsStringSync(),
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
