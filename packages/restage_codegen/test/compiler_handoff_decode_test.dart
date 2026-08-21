// How often the compiler handoff is decoded during one build.
//
// The two materializing builders run once per `.dart` file in the package, and
// each of them reads the handoff. Decoding it means a `jsonDecode` plus a
// base64 decode of every artifact's bytes, so doing that per input costs
// (number of Dart files) x (size of every compiled artifact) — a cost that
// grows with the package on both axes.
//
// A decode is invisible in the output, so the count is observed through the
// one thing a bad handoff produces exactly once per decode: its report.

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/builder.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const String _malformedHandoff = '{ this is not the handoff }';

const Map<String, String> _threeLibraries = {
  'lib/a.dart': 'class A {}',
  'lib/b.dart': 'class B {}',
  'lib/c.dart': 'class C {}',
};

void main() {
  group('compiler handoff', () {
    test('is decoded once per build, not once per Dart input', () async {
      final reports = await _handoffReports(restageGeneratedDartBuilder);

      expect(reports, hasLength(1));
    });

    test('is decoded once per build for the outputs builder too', () async {
      final reports = await _handoffReports(restageOutputsBuilder);

      expect(reports, hasLength(1));
    });

    test('stays an input of every step that consumes it', () async {
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      final handoff = AssetId(
        'apps_examples',
        kRestageSurfacePublicationCompilerBundlePath,
      );

      await testBuilder(
        restageGeneratedDartBuilder(BuilderOptions.empty),
        {
          for (final entry in _threeLibraries.entries)
            'apps_examples|${entry.key}': entry.value,
          'apps_examples|$kRestageSurfacePublicationCompilerBundlePath':
              _malformedHandoff,
        },
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
      );

      // Sharing the decode must not share the dependency. Every library's step
      // has to record the handoff, or editing it would leave those libraries
      // un-rebuilt.
      for (final library in _threeLibraries.keys) {
        expect(
          readerWriter.testing.inputsTrackedFor(
            primaryInput: AssetId('apps_examples', library),
          ),
          contains(handoff),
          reason: library,
        );
      }
    });
  });
}

/// Runs [builderFactory] over three Dart libraries alongside a handoff that
/// cannot be decoded, and returns every report the decode produced.
Future<List<String>> _handoffReports(
  Builder Function(BuilderOptions) builderFactory,
) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  final logs = <String>[];

  final result = await testBuilder(
    builderFactory(BuilderOptions.empty),
    {
      for (final entry in _threeLibraries.entries)
        'apps_examples|${entry.key}': entry.value,
      'apps_examples|$kRestageSurfacePublicationCompilerBundlePath':
          _malformedHandoff,
    },
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    onLog: (record) => logs.add(record.message),
  );

  // The premise is that the report count drops from N to 1 — and "1" is one
  // refactor away from "0". Decoding outside a build step's log zone would
  // turn a hard failure into a silent success with the counts still green, so
  // the failure is asserted here rather than assumed.
  expect(result.succeeded, isFalse);

  return [
    for (final message in logs)
      if (message.contains('compiler handoff is invalid')) message,
  ];
}
