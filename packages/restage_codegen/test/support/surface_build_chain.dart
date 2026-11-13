// The builders a build runs from a package's surfaces to its outputs, in the
// order build.yaml runs them, so a test builds what build_runner builds.

import 'package:build/build.dart';
import 'package:restage_codegen/builder.dart';
import 'package:restage_codegen/src/generated_dart_builder.dart';
import 'package:restage_codegen/src/surface_publication/output_builder.dart';
import 'package:restage_codegen/src/surface_publication/output_location.dart';

/// The keys of the chain's builders, in the order they run.
const List<String> kSurfaceBuildChainKeys = [
  'restage_source_roster',
  'user_catalog_json',
  'restage_package_surface_compiler',
  'generated_dart',
  'generated_check',
  'outputs',
];

// The chain's builders that run only on the root package.
const _rootOnly = {
  'restage_source_roster',
  'restage_package_surface_compiler',
  'generated_check',
};

/// The surface build chain.
///
/// Each builder but the check takes [options] for its
/// `restage_codegen:<key>`, or else [config]. [after] runs once the roster and
/// the catalog have; [compiler] replaces the package surface compiler.
/// [priorOutputs] are the files a failed build writes back.
List<Builder> surfaceBuildChain({
  Map<String, Object?> config = const {},
  BuilderOptions Function(String builderKey)? options,
  Builder? compiler,
  List<Builder> after = const [],
  bool catalog = true,
  Map<String, List<int>> priorOutputs = const {},
}) {
  // The root-only builders run on the root package, as build.yaml applies
  // them.
  BuilderOptions of(String key) {
    // The check takes no options of its own.
    final given = key == 'generated_check'
        ? null
        : options?.call('restage_codegen:$key');
    return BuilderOptions(
      given?.config ?? config,
      isRoot: _rootOnly.contains(key) || (given?.isRoot ?? false),
    );
  }

  Future<Map<String, List<int>>> reader(
    String package,
    RestageOutputLocationPlan plan,
  ) async => priorOutputs;

  return [
    restageSourceRosterBuilder(of('restage_source_roster')),
    if (catalog) userCatalogJsonBuilder(BuilderOptions.empty),
    ...after,
    compiler ??
        restagePackageSurfaceCompilerBuilder(
          of('restage_package_surface_compiler'),
        ),
    RestageGeneratedDartBuilder(
      of('generated_dart'),
      priorOutputReader: reader,
    ),
    restageGeneratedCheckBuilder(of('generated_check')),
    RestageOutputsBuilder(of('outputs'), priorOutputReader: reader),
  ];
}
