import 'dart:io';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/builder.dart';
import 'package:restage_codegen/src/native_screen_source_index.dart';
import 'package:restage_codegen/src/surface_publication/output_placement.dart';
import 'package:restage_codegen/src/widgetbook/widgetbook_catalog_source_index.dart';
import 'package:restage_codegen/src/widgetbook/widgetbook_story_builder.dart';
import 'package:test/test.dart';

import 'helpers.dart';
import 'index_probe_helpers.dart';

/// A package that opts into a source-index consumer must stay buildable under
/// every placement mode.
///
/// The source-index chain validates authored `part` directives, so it needs
/// the same resolved placement the compiler uses. Where it fell back to the
/// default instead, the two demanded different URIs and no directive could
/// satisfy both — the package became unbuildable rather than merely
/// misplaced, and only under a non-default mode, which is why the default-mode
/// suites never saw it.
///
/// The divergence registry cannot catch this: the loader is not a builder and
/// never registers.
void main() {
  for (final mode in _modes.entries) {
    test('a widgetbook-enabled package builds under ${mode.key}', () async {
      final plan = mode.value;
      final result = await _build(
        [
          createWidgetbookStoryBuilderForLib(
            BuilderOptions(_configFor(mode.key)),
            _storyLibDirectory(plan),
          ),
        ],
        plan,
      );
      expect(
        result.succeeded,
        isTrue,
        reason: 'the source index must admit the part URI this mode resolves',
      );
    });

    test('an a2ui-enabled package builds under ${mode.key}', () async {
      final result = await _build(
        [userA2uiCatalogBuilder(BuilderOptions(_configFor(mode.key)))],
        mode.value,
      );
      expect(result.succeeded, isTrue);
    });
  }

  test('the shared source index refuses to serve two placements', () async {
    // Only one builder key consumes this cache today and the resource is
    // per-build, so a disagreement cannot arise through the current graph.
    // The guard exists so that adding a second consumer surfaces a
    // configuration error instead of serving whichever builder populated the
    // cache first — exercised directly, since no builder pair can express it.
    final readerWriter = await _readerWriter(
      RestageOutputPlacementPlan.defaults,
    );
    final result = await runWithNativeScreenPackageGraphForTesting(
      packageGraphSource: _packageGraph,
      body: () => testBuilder(
        const _TwoPlacementProbe(),
        _sources(RestageOutputPlacementPlan.defaults),
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      ),
    );
    expect(result.succeeded, isFalse);
  });
}

/// Asks one cached index for two different placements in a single build.
final class _TwoPlacementProbe implements Builder {
  const _TwoPlacementProbe();

  @override
  Map<String, List<String>> get buildExtensions => const {
        r'$package$': ['lib/two_placement_probe.txt'],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    final cache = WidgetbookCatalogIndexCache();
    await cache.getOrLoad(buildStep, RestageOutputPlacementPlan.defaults);
    await cache.getOrLoad(
      buildStep,
      RestageOutputPlacementPlan.fromBuilderOptions(
        const BuilderOptions({'source_output_layout': 'adjacent'}),
      ),
    );
  }
}

final Map<String, RestageOutputPlacementPlan> _modes = {
  'default': RestageOutputPlacementPlan.defaults,
  'adjacent': RestageOutputPlacementPlan.fromBuilderOptions(
    BuilderOptions(_configFor('adjacent')),
  ),
  'a centralized dart output root':
      RestageOutputPlacementPlan.fromBuilderOptions(
    BuilderOptions(_configFor('a centralized dart output root')),
  ),
};

Map<String, dynamic> _configFor(String mode) => switch (mode) {
      'adjacent' => const {'source_output_layout': 'adjacent'},
      'a centralized dart output root' => const {
          'dart_output_root': 'lib/generated/restage',
        },
      _ => const <String, dynamic>{},
    };

/// A temp `lib/` holding the fixture, so the story census sees the same
/// source the build does.
Directory _storyLibDirectory(RestageOutputPlacementPlan plan) {
  final temp = Directory.systemTemp.createTempSync('restage-placement-');
  addTearDown(() => temp.deleteSync(recursive: true));
  final lib = Directory('${temp.path}/lib')..createSync(recursive: true);
  for (final entry in _sources(plan).entries) {
    final path = entry.key.split('|').last.substring('lib/'.length);
    File('${lib.path}/$path')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(entry.value);
  }
  return lib;
}

Future<TestBuilderResult> _build(
  List<Builder> builders,
  RestageOutputPlacementPlan plan,
) async {
  final readerWriter = await _readerWriter(plan);
  return runWithNativeScreenPackageGraphForTesting(
    packageGraphSource: _packageGraph,
    body: () => testBuilders(
      builders,
      _sources(plan),
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    ),
  );
}

final String _packageGraph = nativeScreenPackageGraph(
  const {'flutter', 'restage', 'rfw_catalog_schema'},
);

Future<TestReaderWriter> _readerWriter(
  RestageOutputPlacementPlan plan,
) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  for (final entry in _sources(plan).entries) {
    readerWriter.testing.writeString(AssetId.parse(entry.key), entry.value);
  }
  return readerWriter;
}

/// One authored screen declaring the `part` URI [plan] resolves for it.
Map<String, String> _sources(RestageOutputPlacementPlan plan) {
  const path = 'lib/onboarding/screens/welcome.dart';
  final placement = plan.forLibrary(path);
  final partUri = placement.partUriFor(placement.neutralPartPath);
  return {
    'apps_examples|$path': '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part '$partUri';

@ScreenSource(id: 'welcome')
final class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  static const next = OnboardingEvent<void>('next');

  @override
  Widget build(BuildContext context) => const SizedBox(width: 1, height: 1);
}
''',
  };
}
