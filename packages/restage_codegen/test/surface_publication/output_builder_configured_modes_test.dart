// Runs RestageOutputsBuilder end to end (not just placement-path math) under
// every configured placement option: adjacent layout, dart_output_root,
// output_root, bundled_runtime, and inspection_report — individually and
// combined, matching the precedence combination output_placement_test.dart
// already proves at the path-resolution level.
import 'dart:convert';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/surface_publication/output_builder.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import 'output_builder_fixtures.dart';

Future<TestBuilderResult> _run(
  BuilderOptions options,
  List<OutputsFixture> fixtures,
  TestReaderWriter readerWriter, {
  Map<String, String> dartSources = const {
    'lib/features/alpha.dart': '// authored\n',
  },
}) {
  final sources = <String, String>{
    for (final entry in dartSources.entries)
      'apps_examples|${entry.key}': entry.value,
    'apps_examples|$compilerJsonPath': compilerJsonFor(fixtures),
  };
  return testBuilder(
    RestageOutputsBuilder(options),
    sources,
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
}

List<int> _bytes(TestReaderWriter readerWriter, String path) =>
    readerWriter.testing.readBytes(AssetId('apps_examples', path));

bool _exists(TestReaderWriter readerWriter, String path) =>
    readerWriter.testing.exists(AssetId('apps_examples', path));

void main() {
  late OutputsFixture alpha;

  setUp(() {
    alpha = flowFixture(
      slug: 'alpha',
      libraryPath: 'lib/features/alpha.dart',
      screenBytes: const [1, 2, 3],
    );
  });

  test('source_output_layout: adjacent places the bundle beside the source',
      () async {
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final result = await _run(
      const BuilderOptions(
        <String, Object?>{'source_output_layout': 'adjacent'},
      ),
      [alpha],
      readerWriter,
    );
    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));

    expect(
      _exists(readerWriter, 'lib/features/alpha.rsbundle'),
      isTrue,
    );
    expect(
      _exists(
        readerWriter,
        'lib/features/restage.generated/alpha.rsbundle',
      ),
      isFalse,
    );
    final bundle = RestageBundleCodec.decode(
      _bytes(readerWriter, 'lib/features/alpha.rsbundle'),
    );
    expect(bundle.authoredLibraryPath, 'lib/features/alpha.dart');
  });

  test('dart_output_root does not relocate portable output', () async {
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final result = await _run(
      const BuilderOptions(
        <String, Object?>{'dart_output_root': 'lib/generated/restage'},
      ),
      [alpha],
      readerWriter,
    );
    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));

    // Bundle, index, and manifest stay at their default portable locations —
    // dart_output_root only ever relocates generated Dart, which this builder
    // does not write.
    expect(
      _exists(
        readerWriter,
        'lib/features/restage.generated/alpha.rsbundle',
      ),
      isTrue,
    );
    expect(
      _exists(readerWriter, 'lib/generated/restage.outputs.json'),
      isTrue,
    );
    expect(
      _exists(readerWriter, 'lib/generated/restage.publication.json'),
      isTrue,
    );
  });

  test('output_root relocates the bundle, report, index, and manifest',
      () async {
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final result = await _run(
      const BuilderOptions(<String, Object?>{
        'output_root': 'tool/restage',
        'inspection_report': true,
      }),
      [alpha],
      readerWriter,
    );
    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));

    const bundlePath = 'tool/restage/bundles/lib/features/alpha.rsbundle';
    const reportPath = 'tool/restage/reports/lib/features/alpha.restage.md';
    expect(_exists(readerWriter, bundlePath), isTrue);
    expect(_exists(readerWriter, reportPath), isTrue);
    expect(
      _exists(readerWriter, 'tool/restage/metadata/restage.outputs.json'),
      isTrue,
    );
    expect(
      _exists(
        readerWriter,
        'tool/restage/metadata/restage.publication.json',
      ),
      isTrue,
    );

    final indexJson = jsonDecode(
      readerWriter.testing.readString(
        AssetId(
          'apps_examples',
          'tool/restage/metadata/restage.outputs.json',
        ),
      ),
    ) as Map<String, Object?>;
    expect(indexJson['physicalRoot'], 'tool/restage');
    final indexEntries =
        (indexJson['entries']! as List<Object?>).cast<Map<String, Object?>>();
    expect(
      indexEntries.every((entry) => entry['bundle'] == bundlePath),
      isTrue,
    );

    final bundle = RestageBundleCodec.decode(_bytes(readerWriter, bundlePath));
    final report = readerWriter.testing.readString(
      AssetId('apps_examples', reportPath),
    );
    for (final entry in bundle.entries) {
      expect(report, contains(entry.logicalPath));
    }

    // The library's canonical .rfwtxt sibling is bundled and rendered as
    // fenced text in the report — configured placement doesn't change what
    // belongs in the bundle. It is never indexed, under any placement: the
    // index is an exact bijection with the manifest's own artifact set, and
    // text is never a manifest artifact.
    const rfwTextPath = 'assets/general/screens/alpha.rfwtxt';
    final rfwTextEntry = bundle.entries.singleWhere(
      (entry) => entry.logicalPath == rfwTextPath,
    );
    expect(rfwTextEntry.role, RestageBundleEntryRoleV1.rfwText);
    expect(
      indexEntries.any((entry) => entry['path'] == rfwTextPath),
      isFalse,
    );
    expect(
      report,
      contains('```text\n${utf8.decode(rfwTextEntry.bytes)}\n```'),
    );
  });

  test('bundled_runtime routes only the bundle into Flutter assets', () async {
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final result = await _run(
      const BuilderOptions(<String, Object?>{
        'bundled_runtime': true,
        'inspection_report': true,
      }),
      [alpha],
      readerWriter,
    );
    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));

    const bundledPath = 'assets/restage/bundles/lib/features/alpha.rsbundle';
    expect(_exists(readerWriter, bundledPath), isTrue);
    // The report is not routed into assets — bundled_runtime affects only
    // the bundle.
    expect(
      _exists(
        readerWriter,
        'lib/features/restage.generated/alpha.restage.md',
      ),
      isTrue,
    );
    expect(
      _exists(readerWriter, 'assets/restage/bundles/alpha.restage.md'),
      isFalse,
    );
    final bundle = RestageBundleCodec.decode(_bytes(readerWriter, bundledPath));
    expect(bundle.authoredLibraryPath, 'lib/features/alpha.dart');
  });

  test(
      'output_root, bundled_runtime, dart_output_root, and inspection_report '
      'combine per the frozen precedence', () async {
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final result = await _run(
      const BuilderOptions(<String, Object?>{
        'bundled_runtime': true,
        'dart_output_root': 'lib/generated/restage',
        'inspection_report': true,
        'output_root': 'tool/restage',
        'source_output_layout': 'adjacent',
      }),
      [alpha],
      readerWriter,
    );
    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));

    // bundled_runtime wins for the bundle; output_root governs the report
    // and package-wide metadata; dart_output_root is irrelevant since this
    // builder never writes generated Dart.
    const bundlePath = 'assets/restage/bundles/lib/features/alpha.rsbundle';
    const reportPath = 'tool/restage/reports/lib/features/alpha.restage.md';
    expect(_exists(readerWriter, bundlePath), isTrue);
    expect(_exists(readerWriter, reportPath), isTrue);
    expect(
      _exists(readerWriter, 'tool/restage/metadata/restage.outputs.json'),
      isTrue,
    );

    final indexJson = jsonDecode(
      readerWriter.testing.readString(
        AssetId(
          'apps_examples',
          'tool/restage/metadata/restage.outputs.json',
        ),
      ),
    ) as Map<String, Object?>;
    final indexEntries =
        (indexJson['entries']! as List<Object?>).cast<Map<String, Object?>>();
    expect(
      indexEntries.every((entry) => entry['bundle'] == bundlePath),
      isTrue,
      reason: 'The recorded bundle locator must be the exact physical '
          "result of the plan's own precedence, matching "
          'output_placement_test.dart at the path-math level.',
    );
  });
}
