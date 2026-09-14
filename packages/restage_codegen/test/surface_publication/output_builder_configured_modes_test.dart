// Runs RestageOutputsBuilder end to end (not just placement-path math) under
// every configured placement option: adjacent layout, dart_output_root,
// output_root, bundled_runtime, and inspection_report — individually and
// combined, matching the precedence combination output_placement_test.dart
// already proves at the path-resolution level.
import 'dart:convert';

import 'package:build/build.dart';
import 'package:logging/logging.dart';
import 'package:restage_codegen/src/surface_publication/output_builder.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import 'output_builder_fixtures.dart';

Future<TestBuilderResult> _run(
  BuilderOptions options,
  List<OutputsFixture> fixtures,
  TestReaderWriter readerWriter, {
  List<String>? messages,
  List<LogRecord>? records,
  bool verbose = false,
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
    verbose: verbose,
    onLog: (record) {
      messages?.add(record.message);
      records?.add(record);
    },
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

  for (final bundled in [false, true]) {
    test('does not duplicate compiler success for bundled_runtime: $bundled',
        () async {
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      final messages = <String>[];
      final records = <LogRecord>[];
      final result = await _run(
        BuilderOptions(<String, Object?>{'bundled_runtime': bundled}),
        [alpha],
        readerWriter,
        messages: messages,
        records: records,
        verbose: true,
      );
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      final notices = messages.where(
        (message) =>
            message.contains('[restage] bundled_runtime:') ||
            message.contains('[restage] Compiled'),
      );
      expect(notices, isEmpty);
      expect(
        records.where((record) => record.level >= Level.WARNING),
        isEmpty,
        reason:
            'Routine bundle status must not train users to ignore warnings.',
      );
      if (bundled) {
        expect(
          _exists(
            readerWriter,
            'assets/restage/bundles/lib/features/alpha.rsbundle',
          ),
          isTrue,
        );
      }
    });
  }

  for (final bundled in [false, true]) {
    test('direct surface mount warnings require disabled bundling: $bundled',
        () async {
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      final records = <LogRecord>[];
      final result = await _run(
        BuilderOptions({'bundled_runtime': bundled}),
        [alpha],
        readerWriter,
        records: records,
        dartSources: {
          'lib/features/alpha.dart': '// authored\n',
          'lib/main.dart': _mountSource(
            jsonEncode(
              utf8.decode(alpha.files['assets/general/flows/alpha.flow.json']!),
            ),
          ),
          'lib/legacy_mounts.dart': '''
import 'package:restage/restage.dart' as rs;
List<Object> mounts(rs.SurfaceFlowRef<void> flow, rs.SurfaceScreenRef<void> screen) => [
  rs.RestageSurfaceFlow(flow: flow, unavailable: const rs.FlowUnavailablePolicy.hide()),
  rs.RestageSurfaceScreen(screen: screen, unavailable: const rs.SurfaceScreenUnavailablePolicy.hide()),
];
''',
        },
      );
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      final warnings = records
          .where((record) => record.level >= Level.WARNING)
          .map((record) => record.message)
          .toList();
      if (bundled) {
        expect(warnings, isEmpty);
      } else {
        expect(warnings, hasLength(8));
        expect(
          warnings.where((warning) => warning.contains('main.dart:')),
          hasLength(6),
        );
        expect(
          warnings.where((warning) => warning.contains('legacy_mounts.dart:')),
          hasLength(2),
        );
        expect(warnings, everyElement(contains('bundled_runtime is false')));
        expect(warnings, contains(contains("RestagePaywall(id: 'offer')")));
        expect(warnings, contains(contains("RestagePaywall(id: 'null_ui')")));
        expect(warnings, contains(contains('RestageScreen(screen: screen)')));
        expect(warnings, contains(contains('RestageFlowGraph(flow: oldFlow)')));
        expect(
          warnings,
          contains(contains('RestageFlowGraph(flow: incompleteFlow)')),
        );
        expect(
          warnings,
          contains(contains('RestageOnboarding(flow: oldFlow)')),
        );
      }
    });
  }

  test('warns in an authored part without a compiler handoff', () async {
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final records = <LogRecord>[];
    final result = await testBuilder(
      RestageOutputsBuilder(BuilderOptions.empty),
      const {
        'apps_examples|lib/main.dart': '''
import 'package:restage/restage.dart' as rs;
part 'mounts.dart';
''',
        'apps_examples|lib/mounts.dart': '''
part of 'main.dart';
const mounted = rs.RestagePaywall(id: 'part_offer');
''',
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
      onLog: records.add,
    );
    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    final warnings = records.where((record) => record.level >= Level.WARNING);
    expect(warnings, hasLength(1));
    expect(warnings.single.message, contains('mounts.dart:2:17:'));
    expect(warnings.single.message, contains("id: 'part_offer'"));
  });

  test(
      'source_output_layout: adjacent keeps portable bundles under the default root',
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
      isFalse,
    );
    expect(
      _exists(
        readerWriter,
        '.restage/build/bundles/lib/features/alpha.rsbundle',
      ),
      isTrue,
    );
    final bundle = RestageBundleCodec.decode(
      _bytes(
          readerWriter, '.restage/build/bundles/lib/features/alpha.rsbundle'),
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
        '.restage/build/bundles/lib/features/alpha.rsbundle',
      ),
      isTrue,
    );
    expect(
      _exists(readerWriter, '.restage/build/metadata/restage.outputs.json'),
      isTrue,
    );
    expect(
      _exists(readerWriter, '.restage/build/metadata/restage.publication.json'),
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
    expect(rfwTextEntry.role, RestageBundleEntryRole.rfwText);
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
        '.restage/build/reports/lib/features/alpha.restage.md',
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

String _mountSource(String documentJson) => '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart' as rs;

void decode(Map<String, Object?> result) {}
const oldFlow = rs.SurfaceFlowRef<void>(
  id: 'old_flow', version: 1, minClient: 1,
  surface: rs.Surface.onboarding, decodeResult: decode,
);
const compiledFlow = rs.SurfaceFlowRef<void>(
  id: 'compiled_flow', version: 1, minClient: 1,
  surface: rs.Surface.onboarding, decodeResult: decode,
  compiled: rs.CompiledFlow(documentJson: $documentJson, screens: {'start': original}),
);
Widget original() => const SizedBox.shrink();
const incompleteFlow = rs.SurfaceFlowRef<void>(
  id: 'compiled_flow', version: 1, minClient: 1,
  surface: rs.Surface.onboarding, decodeResult: decode,
  compiled: rs.CompiledFlow(documentJson: $documentJson, screens: {}),
);
Widget fallback(BuildContext context) => const SizedBox.shrink();
Widget flowFallback(BuildContext context, rs.FlowUnavailableError error) =>
    const SizedBox.shrink();
const explicitFlowFallback = rs.FlowUnavailablePolicy.fallback(builder: flowFallback);

// The generated mount pattern supplies the original constructor via super.
class OfferSurface extends rs.RestagePaywall {
  const OfferSurface() : super(id: 'typed', fallbackBuilder: fallback);
}
class RestagePaywall {
  const RestagePaywall({required String id});
}
const lookalike = RestagePaywall(id: 'unrelated');

List<Widget> mounts(rs.SurfaceScreenRef<void> screen) => [
  const rs.RestagePaywall(id: 'offer'),
  const rs.RestagePaywall(id: 'null_ui', errorBuilder: null),
  rs.RestageScreen(screen: screen, unavailable: const rs.SurfaceScreenUnavailablePolicy.hide()),
  const rs.RestageFlowGraph(flow: oldFlow, unavailable: rs.FlowUnavailablePolicy.hide()),
  const rs.RestageOnboarding(flow: oldFlow, unavailable: rs.FlowUnavailablePolicy.hide()),
  const rs.RestageFlowGraph(flow: incompleteFlow, unavailable: rs.FlowUnavailablePolicy.hide()),

  // Each of these already retains native content or explicit fallback UI.
  const OfferSurface(),
  const rs.RestagePaywall(id: 'native', fallbackBuilder: fallback),
  rs.RestagePaywall(id: 'error_ui', errorBuilder: (context, error) => const SizedBox.shrink()),
  rs.RestageScreen(screen: screen, unavailable: rs.SurfaceScreenUnavailablePolicy.fallback(builder: (context, error) => const SizedBox.shrink())),
  const rs.RestageFlowGraph(flow: oldFlow, unavailable: explicitFlowFallback),
  rs.RestageOnboarding(flow: oldFlow, unavailable: rs.FlowUnavailablePolicy.fallback(builder: (context, error) => const SizedBox.shrink())),
  const rs.RestageFlowGraph(flow: compiledFlow, unavailable: rs.FlowUnavailablePolicy.hide()),
];
''';
