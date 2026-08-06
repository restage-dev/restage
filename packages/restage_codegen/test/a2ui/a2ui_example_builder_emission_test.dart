import 'dart:convert';
import 'dart:io';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/a2ui/user_a2ui_catalog_builder.dart';
import 'package:test/test.dart';

import '../helpers.dart';

const _package = 'enum_customer';
const _fixtureRoot = 'test/fixtures/a2ui_example_enum_customer';
const _sourcePath = 'lib/enum_card.dart';
const _alphaPath = 'lib/a2ui_examples/enum_card/alpha.json';
const _zuluPath = 'lib/a2ui_examples/enum_card/zulu.json';
const _dartOutput = 'lib/restage_a2ui_catalog.g.dart';
const _stampOutput = 'lib/restage_a2ui_catalog.a2ui.json';

String _fixture(String path) => File('$_fixtureRoot/$path').readAsStringSync();

String _generatedAssetSuffix(String path) =>
    '.dart_tool/build/generated/$_package/$path';

Future<
    ({
      bool succeeded,
      String logs,
      TestReaderWriter readerWriter,
    })> _runBuilder({String? alpha, String? zulu}) async {
  final source = _fixture(_sourcePath);
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'restage_codegen',
  );
  readerWriter.testing
    ..writeString(AssetId(_package, _sourcePath), source)
    ..writeString(
      AssetId(_package, _alphaPath),
      alpha ?? _fixture(_alphaPath),
    )
    ..writeString(
      AssetId(_package, _zuluPath),
      zulu ?? _fixture(_zuluPath),
    );
  final logs = <String>[];
  final result = await testBuilder(
    const UserA2uiCatalogBuilder(BuilderOptions.empty),
    {'$_package|$_sourcePath': source},
    rootPackage: _package,
    readerWriter: readerWriter,
    onLog: (record) => logs.add(record.message),
  );
  return (
    succeeded: result.succeeded,
    logs: logs.join('\n'),
    readerWriter: result.readerWriter,
  );
}

String _output(TestReaderWriter readerWriter, String path) {
  final asset = readerWriter.testing.assets.singleWhere(
    (candidate) => candidate.path.endsWith(_generatedAssetSuffix(path)),
    orElse: () => throw StateError(
      'missing $path; assets: ${readerWriter.testing.assets.join(', ')}; '
      'written: ${readerWriter.testing.assetsWritten.join(', ')}',
    ),
  );
  return readerWriter.testing.readString(asset);
}

void _expectNoOutputs(TestReaderWriter readerWriter) {
  for (final output in [_dartOutput, _stampOutput]) {
    expect(
      readerWriter.testing.assets.any(
        (asset) => asset.path.endsWith(_generatedAssetSuffix(output)),
      ),
      isFalse,
    );
  }
}

void main() {
  test('real builder emits both enum members in canonical name order',
      () async {
    final result = await _runBuilder();

    expect(result.succeeded, isTrue, reason: result.logs);
    final dart = _output(result.readerWriter, _dartOutput);
    expect(
      dart,
      contains(
        'const Map<String, Map<String, String>> '
        'restageA2uiExampleRegistry',
      ),
    );
    expect(dart, contains('exampleData: <ExampleBuilderCallback>['));
    expect(dart.indexOf("'Alpha':"), lessThan(dart.indexOf("'Zulu':")));
    expect(
      dart,
      contains(
        '[{"component":"EnumCard","id":"root",'
        '"labels":["alpha","beta"],"measurements":[1,2.0],'
        '"tone":"quiet"}]',
      ),
    );
    expect(dart, isNot(contains('widgetbook')));
  });

  test('invalid enum member fails before either output is written', () async {
    final invalid = _fixture(_alphaPath).replaceFirst('"quiet"', '"unknown"');
    final result = await _runBuilder(alpha: invalid);

    expect(result.succeeded, isFalse);
    expect(result.logs, contains('resolved enum member'));
    expect(result.logs, contains('EnumCard'));
    expect(result.logs, contains('Alpha'));
    expect(result.logs, contains(_alphaPath));
    _expectNoOutputs(result.readerWriter);
  });

  test('canonical edits rerun while only semantic edits change Dart', () async {
    final originalAlpha = _fixture(_alphaPath);
    const reorderedAlpha = '[{"component":"EnumCard","labels":["alpha","beta"],'
        '"id":"root","measurements":[1,2.0],"tone":"quiet"}]';
    final baseline = await _runBuilder(alpha: originalAlpha);
    final reordered = await _runBuilder(alpha: reorderedAlpha);
    final semantic = await _runBuilder(
      alpha: originalAlpha.replaceFirst('"quiet"', '"loud"'),
    );
    final numericKind = await _runBuilder(
      alpha: originalAlpha.replaceFirst('[1, 2.0]', '[1.0, 2.0]'),
    );
    final arrayOrder = await _runBuilder(
      alpha: originalAlpha.replaceFirst(
        '["alpha", "beta"]',
        '["beta", "alpha"]',
      ),
    );

    for (final result in [
      baseline,
      reordered,
      semantic,
      numericKind,
      arrayOrder,
    ]) {
      expect(result.succeeded, isTrue, reason: result.logs);
      expect(
        result.readerWriter.testing.inputsTracked,
        contains(AssetId(_package, _alphaPath)),
      );
      expect(
        result.readerWriter.testing.assetsRead,
        contains(AssetId(_package, _alphaPath)),
      );
    }

    final baselineDart = _output(baseline.readerWriter, _dartOutput);
    expect(_output(reordered.readerWriter, _dartOutput), baselineDart);
    expect(_output(semantic.readerWriter, _dartOutput), isNot(baselineDart));
    expect(_output(numericKind.readerWriter, _dartOutput), isNot(baselineDart));
    expect(_output(arrayOrder.readerWriter, _dartOutput), isNot(baselineDart));

    final baselineStamp = _output(baseline.readerWriter, _stampOutput);
    for (final changed in [reordered, semantic, numericKind, arrayOrder]) {
      expect(_output(changed.readerWriter, _stampOutput), baselineStamp);
    }
    final stamp = jsonDecode(baselineStamp) as Map<String, Object?>;
    final catalog = stamp['a2uiCatalog']! as Map<String, Object?>;
    expect(catalog['catalogId'], catalog[r'$id']);
  });
}
