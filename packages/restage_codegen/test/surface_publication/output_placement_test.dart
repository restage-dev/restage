import 'package:build/build.dart';
import 'package:restage_codegen/src/surface_publication/output_placement.dart';
import 'package:test/test.dart';

void main() {
  group('RestageOutputPlacementPlan', () {
    test('resolves the default restage.generated collection directory', () {
      final plan = RestageOutputPlacementPlan.fromBuilderOptions(
        BuilderOptions.empty,
      );
      final source = plan.forLibrary('lib/features/onboarding/welcome.dart');

      expect(
        source.neutralPartPath,
        'lib/features/onboarding/restage.generated/welcome.restage.g.dart',
      );
      expect(
        source.bundlePath,
        'lib/features/onboarding/restage.generated/welcome.rsbundle',
      );
      expect(source.inspectionReportPath, isNull);

      final extensions = plan.portableBuildExtensions;
      expect(
        expectedOutputs(
          _StaticBuilder(extensions),
          AssetId('fixture', 'lib/features/onboarding/welcome.dart'),
        ),
        unorderedEquals(<AssetId>[
          AssetId(
            'fixture',
            'lib/features/onboarding/restage.generated/welcome.rsbundle',
          ),
        ]),
      );
      expect(
        expectedOutputs(
          _StaticBuilder(plan.generatedDartBuildExtensions),
          AssetId('fixture', 'lib/features/onboarding/welcome.dart'),
        ),
        <AssetId>[
          AssetId('fixture', source.neutralPartPath),
        ],
      );
    });

    test('declares valid adjacent source output paths without capture reuse',
        () {
      final plan = RestageOutputPlacementPlan.fromBuilderOptions(
        const BuilderOptions(<String, Object?>{
          'inspection_report': true,
          'source_output_layout': 'adjacent',
        }),
      );
      final source = plan.forLibrary('lib/features/onboarding/welcome.dart');

      expect(
        source.neutralPartPath,
        'lib/features/onboarding/welcome.restage.g.dart',
      );
      expect(source.bundlePath, 'lib/features/onboarding/welcome.rsbundle');
      expect(
        source.inspectionReportPath,
        'lib/features/onboarding/welcome.restage.md',
      );
      expect(
        source.generatedDartPath('welcome_screen.stories.dart'),
        'lib/features/onboarding/welcome_screen.stories.dart',
      );
      expect(
        source.partUriFor(source.neutralPartPath),
        'welcome.restage.g.dart',
      );

      final extensions = plan.portableBuildExtensions;
      expect(
        expectedOutputs(
          _StaticBuilder(extensions),
          AssetId('fixture', 'lib/features/onboarding/welcome.dart'),
        ),
        unorderedEquals(<AssetId>[
          AssetId(
            'fixture',
            'lib/features/onboarding/welcome.rsbundle',
          ),
          AssetId(
            'fixture',
            'lib/features/onboarding/welcome.restage.md',
          ),
        ]),
      );
      expect(
        expectedOutputs(
          _StaticBuilder(plan.generatedDartBuildExtensions),
          AssetId('fixture', 'lib/features/onboarding/welcome.dart'),
        ),
        <AssetId>[
          AssetId('fixture', source.neutralPartPath),
        ],
      );
    });

    test('applies Dart, bundle, and portable-root precedence independently',
        () {
      final plan = RestageOutputPlacementPlan.fromBuilderOptions(
        const BuilderOptions(<String, Object?>{
          'bundled_runtime': true,
          'dart_output_root': 'lib/generated/restage',
          'inspection_report': true,
          'output_root': 'tool/restage',
          'source_output_layout': 'adjacent',
        }),
      );
      final source = plan.forLibrary('lib/features/onboarding/welcome.dart');

      expect(
        source.neutralPartPath,
        'lib/generated/restage/features/onboarding/welcome.restage.g.dart',
      );
      expect(
        source.generatedDartPath('welcome_screen.stories.dart'),
        'lib/generated/restage/features/onboarding/welcome_screen.stories.dart',
      );
      expect(
        source.partUriFor(source.neutralPartPath),
        '../../generated/restage/features/onboarding/welcome.restage.g.dart',
      );
      expect(
        source.bundlePath,
        'assets/restage/bundles/lib/features/onboarding/welcome.rsbundle',
      );
      expect(
        source.inspectionReportPath,
        'tool/restage/reports/lib/features/onboarding/welcome.restage.md',
      );
      expect(
        plan.outputIndexPath,
        'tool/restage/metadata/restage.outputs.json',
      );
      expect(
        plan.publicationManifestPath,
        'tool/restage/metadata/restage.publication.json',
      );
      expect(
        plan.a2uiCatalogPath,
        'tool/restage/a2ui/restage_a2ui_catalog.a2ui.json',
      );
      expect(
        plan.packageGeneratedDartPath('restage_a2ui_catalog.g.dart'),
        'lib/generated/restage/restage_a2ui_catalog.g.dart',
      );
      expect(plan.physicalRoot, 'tool/restage');

      final extensions = plan.portableBuildExtensions;
      expect(
        expectedOutputs(
          _StaticBuilder(extensions),
          AssetId('fixture', 'lib/features/onboarding/welcome.dart'),
        ),
        unorderedEquals(<AssetId>[
          AssetId(
            'fixture',
            'assets/restage/bundles/lib/features/onboarding/welcome.rsbundle',
          ),
          AssetId(
            'fixture',
            'tool/restage/reports/lib/features/onboarding/welcome.restage.md',
          ),
        ]),
      );
      expect(
        expectedOutputs(
          _StaticBuilder(plan.generatedDartBuildExtensions),
          AssetId('fixture', 'lib/features/onboarding/welcome.dart'),
        ),
        <AssetId>[
          AssetId('fixture', source.neutralPartPath),
        ],
        reason: 'dart_output_root resolves independently of output_root and '
            'bundled_runtime, matching neutralPartPath exactly.',
      );
    });

    test('recognizes every option fromBuilderOptions accepts', () {
      expect(
        kRestagePlacementOptionNames,
        unorderedEquals(<String>[
          'source_output_layout',
          'inspection_report',
          'bundled_runtime',
          'dart_output_root',
          'output_root',
        ]),
      );
    });

    test('rejects an authored source inside the reserved collection directory',
        () {
      final plan = RestageOutputPlacementPlan.fromBuilderOptions(
        BuilderOptions.empty,
      );
      expect(
        () => plan.forLibrary(
          'lib/features/onboarding/restage.generated/welcome.restage.g.dart',
        ),
        throwsFormatException,
      );
    });

    test('rejects malformed placement options before any output declaration',
        () {
      for (final options in <Map<String, Object?>>[
        <String, Object?>{'source_output_layout': 'flat'},
        <String, Object?>{'inspection_report': 'true'},
        <String, Object?>{'bundled_runtime': 1},
        <String, Object?>{'output_root': '../tool/restage'},
        <String, Object?>{'output_root': 'tool//restage'},
        <String, Object?>{'output_root': '.dart_tool/restage'},
        <String, Object?>{'dart_output_root': 'generated/restage'},
        <String, Object?>{'dart_output_root': 'lib/.generated/restage'},
      ]) {
        expect(
          () => RestageOutputPlacementPlan.fromBuilderOptions(
            BuilderOptions(options),
          ),
          throwsFormatException,
        );
      }
    });
  });
}

final class _StaticBuilder implements Builder {
  const _StaticBuilder(this.buildExtensions);

  @override
  final Map<String, List<String>> buildExtensions;

  @override
  void build(BuildStep buildStep) {}
}
