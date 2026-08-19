// Single resolved placement authority for generated Restage build output.
//
// Every generated-output producer and consumer resolves physical placement
// through this one plan so that a package's `build.yaml` options are parsed
// and validated exactly once, in one place, before any output is declared.

import 'package:build/build.dart';
import 'package:path/path.dart' as p;

/// The reserved directory name collecting generated files for one source
/// directory under the default [RestageSourceOutputLayout.generatedDirectory]
/// layout. Never admitted as a builder input.
const String kRestageGeneratedDirectoryName = 'restage.generated';

/// Every builder-options key [RestageOutputPlacementPlan.fromBuilderOptions]
/// recognizes. Shared across every builder that resolves a placement plan
/// from its own [BuilderOptions], so each stays option-key-complete without
/// hand-copying the list.
const Set<String> kRestagePlacementOptionNames = <String>{
  'source_output_layout',
  'inspection_report',
  'bundled_runtime',
  'dart_output_root',
  'output_root',
};

/// Fixed package-wide filenames and roots that do not depend on any single
/// authored source.
const String _kOutputsIndexFileName = 'restage.outputs.json';
const String _kPublicationManifestFileName = 'restage.publication.json';
const String _kA2uiCatalogFileName = 'restage_a2ui_catalog.a2ui.json';
const String _kPackageGeneratedDartDefaultDir = 'lib/generated';

/// How source-owned generated files (the neutral Dart part, the bundle, and
/// the optional inspection report) are placed relative to their authored
/// Dart source when no more specific option overrides them.
enum RestageSourceOutputLayout {
  /// One fixed-name `restage.generated/` directory per source directory,
  /// holding the canonical stem-named files for every source in it. The
  /// default.
  generatedDirectory,

  /// Flat placement beside the authored source.
  adjacent;

  static RestageSourceOutputLayout _parse(Object? value) {
    if (value == null) return generatedDirectory;
    if (value is! String) {
      throw FormatException(
        'source_output_layout must be a string, got ${value.runtimeType}.',
      );
    }
    return switch (value) {
      'generated_directory' => generatedDirectory,
      'adjacent' => adjacent,
      _ => throw FormatException(
          'Unsupported source_output_layout "$value". Supported values are '
          '"generated_directory" and "adjacent".',
        ),
    };
  }
}

/// Rejects any builder option outside [kRestagePlacementOptionNames].
///
/// For a builder whose only options are placement options — the whole
/// package's annotated source is its input — an unrecognized key would
/// otherwise be silently ignored and the output would land somewhere the
/// developer did not ask for. [featureLabel] names the generation feature in
/// the message, for example `A2UI catalog generation`.
void requireOnlyRestagePlacementOptions(
  BuilderOptions options, {
  required String featureLabel,
}) {
  final unsupported = options.config.keys
      .where((key) => !kRestagePlacementOptionNames.contains(key))
      .toList()
    ..sort();
  if (unsupported.isNotEmpty) {
    throw ArgumentError(
      '$featureLabel has no per-widget authoring options; remove unsupported '
      'option(s): ${unsupported.join(', ')}.',
    );
  }
}

/// Whether a package-relative authored source path is reserved because it
/// lives inside a `restage.generated/` collection directory.
///
/// Such paths are never admitted as builder input regardless of placement
/// mode.
bool isReservedRestageGeneratedPath(String packageRelativePath) =>
    p.posix.split(packageRelativePath).contains(kRestageGeneratedDirectoryName);

/// The one resolved placement authority for a package's generated Restage
/// output.
///
/// Constructed once from a builder's fully merged [BuilderOptions]. Every
/// value it exposes is statically knowable at construction time: it never
/// reads the filesystem and never depends on which sources currently exist.
final class RestageOutputPlacementPlan {
  RestageOutputPlacementPlan._({
    required this.sourceOutputLayout,
    required this.inspectionReport,
    required this.bundledRuntime,
    required this.dartOutputRoot,
    required this.outputRoot,
  });

  /// Resolves and validates every placement option from a builder's merged
  /// [BuilderOptions]. Throws [FormatException] before any output is
  /// declared if an option is malformed.
  factory RestageOutputPlacementPlan.fromBuilderOptions(
    BuilderOptions options,
  ) {
    final config = options.config;
    final layout = RestageSourceOutputLayout._parse(
      config['source_output_layout'],
    );
    final inspectionReport = _parseBool(
      config['inspection_report'],
      optionName: 'inspection_report',
      defaultValue: false,
    );
    final bundledRuntime = _parseBool(
      config['bundled_runtime'],
      optionName: 'bundled_runtime',
      defaultValue: false,
    );
    final dartOutputRoot = _parseRoot(
      config['dart_output_root'],
      optionName: 'dart_output_root',
      requireUnderLib: true,
      rejectHiddenSegments: true,
    );
    final outputRoot = _parseRoot(
      config['output_root'],
      optionName: 'output_root',
      requireUnderLib: false,
      rejectHiddenSegments: false,
    );
    return RestageOutputPlacementPlan._(
      sourceOutputLayout: layout,
      inspectionReport: inspectionReport,
      bundledRuntime: bundledRuntime,
      dartOutputRoot: dartOutputRoot,
      outputRoot: outputRoot,
    );
  }

  /// The plan an unconfigured package resolves: the default source layout
  /// with no configured roots and no inspection report.
  ///
  /// Shared by every caller that has no [BuilderOptions] of its own to
  /// resolve. A plan is immutable and depends on nothing outside its options,
  /// so one instance serves them all.
  static final RestageOutputPlacementPlan defaults =
      RestageOutputPlacementPlan.fromBuilderOptions(BuilderOptions.empty);

  /// The source-owned placement layout in effect when neither
  /// [dartOutputRoot] nor [outputRoot] overrides it.
  final RestageSourceOutputLayout sourceOutputLayout;

  /// Whether the optional `.restage.md` sibling report is enabled.
  final bool inspectionReport;

  /// Whether `.rsbundle` files are routed into `assets/restage/bundles/`.
  final bool bundledRuntime;

  /// The package-relative, `lib/`-rooted centralization root for
  /// Restage-owned generated Dart, or `null` if not configured.
  final String? dartOutputRoot;

  /// The package-relative root for portable tooling output, or `null` if not
  /// configured.
  final String? outputRoot;

  /// The resolved physical root recorded by the generated output index.
  ///
  /// This is [outputRoot] when configured, or `.` (the package root) for the
  /// default in-tree placement.
  String get physicalRoot => outputRoot ?? '.';

  /// The package-wide physical output index path.
  String get outputIndexPath => _packageWidePath(_kOutputsIndexFileName);

  /// The package-wide publication manifest path.
  String get publicationManifestPath =>
      _packageWidePath(_kPublicationManifestFileName);

  /// The package-wide producer-facing A2UI catalog document path.
  String get a2uiCatalogPath => _packageWidePath(_kA2uiCatalogFileName);

  String _packageWidePath(String fileName) {
    final root = outputRoot;
    return root == null
        ? p.posix.join(_kPackageGeneratedDartDefaultDir, fileName)
        : p.posix.join(root, _metadataSegmentFor(fileName), fileName);
  }

  String _metadataSegmentFor(String fileName) =>
      fileName == _kA2uiCatalogFileName ? 'a2ui' : 'metadata';

  /// The package-wide Restage-owned generated Dart path for [fileName]
  /// (for example `restage_a2ui_catalog.g.dart`), honoring [dartOutputRoot].
  String packageGeneratedDartPath(String fileName) {
    final root = dartOutputRoot;
    return p.posix.join(root ?? _kPackageGeneratedDartDefaultDir, fileName);
  }

  /// The static build-extension map for portable per-library and
  /// package-wide outputs under these resolved options.
  ///
  /// Every input template uses `package:build`'s documented multi-capture-
  /// group form; no capture group is ever referenced twice in one output.
  Map<String, List<String>> get portableBuildExtensions {
    final extensions = <String, List<String>>{};
    extensions
        .putIfAbsent(_bundleInputPattern, () => <String>[])
        .add(_bundleOutputTemplate);
    if (inspectionReport) {
      extensions
          .putIfAbsent(_reportInputPattern, () => <String>[])
          .add(_reportOutputTemplate);
    }
    extensions[r'$package$'] = <String>[
      outputIndexPath,
      publicationManifestPath,
    ];
    return extensions;
  }

  /// The static build-extension map for the neutral per-library generated
  /// Dart part under these resolved options.
  ///
  /// `dart_output_root` never shares its capture-group family with
  /// [portableBuildExtensions]'s bundle/report templates — each resolves
  /// independently, matching [RestageSourceOutputPlacement.neutralPartPath].
  Map<String, List<String>> get generatedDartBuildExtensions {
    final root = dartOutputRoot;
    if (root != null) {
      return <String, List<String>>{
        'lib/{{source}}.dart': <String>['$root/{{source}}.restage.g.dart'],
      };
    }
    final adjacent = sourceOutputLayout == RestageSourceOutputLayout.adjacent;
    return <String, List<String>>{
      '{{dir}}/{{file}}.dart': <String>[
        if (adjacent)
          '{{dir}}/{{file}}.restage.g.dart'
        else
          '{{dir}}/$kRestageGeneratedDirectoryName/{{file}}.restage.g.dart',
      ],
    };
  }

  bool get _bundleUsesFullSourcePath => bundledRuntime || outputRoot != null;
  bool get _reportUsesFullSourcePath => outputRoot != null;

  String get _bundleInputPattern => _bundleUsesFullSourcePath
      ? 'lib/{{source}}.dart'
      : '{{dir}}/{{file}}.dart';

  String get _reportInputPattern => _reportUsesFullSourcePath
      ? 'lib/{{source}}.dart'
      : '{{dir}}/{{file}}.dart';

  String get _bundleOutputTemplate {
    if (bundledRuntime) {
      return 'assets/restage/bundles/lib/{{source}}.rsbundle';
    }
    final root = outputRoot;
    if (root != null) {
      return p.posix.join(root, 'bundles', 'lib/{{source}}.rsbundle');
    }
    return sourceOutputLayout == RestageSourceOutputLayout.adjacent
        ? '{{dir}}/{{file}}.rsbundle'
        : '{{dir}}/$kRestageGeneratedDirectoryName/{{file}}.rsbundle';
  }

  String get _reportOutputTemplate {
    final root = outputRoot;
    if (root != null) {
      return p.posix.join(root, 'reports', 'lib/{{source}}.restage.md');
    }
    return sourceOutputLayout == RestageSourceOutputLayout.adjacent
        ? '{{dir}}/{{file}}.restage.md'
        : '{{dir}}/$kRestageGeneratedDirectoryName/{{file}}.restage.md';
  }

  /// Resolves per-source-library placement for one authored Dart library
  /// path, for example `lib/features/onboarding/welcome.dart`.
  RestageSourceOutputPlacement forLibrary(String dartLibraryPath) {
    if (!dartLibraryPath.endsWith('.dart')) {
      throw FormatException(
        'Expected an authored Dart library path, got "$dartLibraryPath".',
      );
    }
    if (isReservedRestageGeneratedPath(dartLibraryPath)) {
      throw FormatException(
        'Authored source "$dartLibraryPath" lies inside the reserved '
        '$kRestageGeneratedDirectoryName/ directory.',
      );
    }
    return RestageSourceOutputPlacement._(
      plan: this,
      dartPath: dartLibraryPath,
    );
  }
}

/// Resolved physical placement for one authored Dart library.
final class RestageSourceOutputPlacement {
  RestageSourceOutputPlacement._({
    required RestageOutputPlacementPlan plan,
    required String dartPath,
  })  : _plan = plan,
        _dartPath = dartPath,
        _dir = p.posix.dirname(dartPath),
        _stem = p.posix.basenameWithoutExtension(dartPath);

  final RestageOutputPlacementPlan _plan;
  final String _dartPath;
  final String _dir;
  final String _stem;

  String get _dartPathWithoutExtension => p.posix.withoutExtension(_dartPath);

  /// The source-layout directory ignoring any configured
  /// [RestageOutputPlacementPlan.dartOutputRoot]. Used for bundle and report
  /// fallback placement, which `dart_output_root` never affects.
  String get _sourceLayoutDir =>
      _plan.sourceOutputLayout == RestageSourceOutputLayout.adjacent
          ? _dir
          : p.posix.join(_dir, kRestageGeneratedDirectoryName);

  /// The directory holding this library's generated Dart, honoring
  /// [RestageOutputPlacementPlan.dartOutputRoot] when configured.
  String get _dartOutputDir {
    final root = _plan.dartOutputRoot;
    if (root == null) return _sourceLayoutDir;
    final relativeFromLib = p.posix.relative(_dir, from: 'lib');
    return relativeFromLib == '.' ? root : p.posix.join(root, relativeFromLib);
  }

  /// The neutral per-library generated Dart part, for example
  /// `lib/features/onboarding/restage.generated/welcome.restage.g.dart`.
  String get neutralPartPath =>
      p.posix.join(_dartOutputDir, '$_stem.restage.g.dart');

  /// The physical path for another Restage-generated Dart file that belongs
  /// beside [neutralPartPath] (for example a Widgetbook story library).
  String generatedDartPath(String fileName) =>
      p.posix.join(p.posix.dirname(neutralPartPath), fileName);

  /// The exact `part` URI the authored source must declare to reach a
  /// generated-Dart path produced by this plan (typically [neutralPartPath]
  /// or a [generatedDartPath] result).
  String partUriFor(String generatedDartPath) =>
      p.posix.relative(generatedDartPath, from: _dir);

  /// This library's deterministic `.rsbundle` path.
  String get bundlePath {
    if (_plan.bundledRuntime) {
      return 'assets/restage/bundles/$_dartPathWithoutExtension.rsbundle';
    }
    final root = _plan.outputRoot;
    if (root != null) {
      return p.posix
          .join(root, 'bundles', '$_dartPathWithoutExtension.rsbundle');
    }
    return p.posix.join(_sourceLayoutDir, '$_stem.rsbundle');
  }

  /// This library's optional `.restage.md` inspection report path, or `null`
  /// when [RestageOutputPlacementPlan.inspectionReport] is disabled.
  String? get inspectionReportPath {
    if (!_plan.inspectionReport) return null;
    final root = _plan.outputRoot;
    if (root != null) {
      return p.posix
          .join(root, 'reports', '$_dartPathWithoutExtension.restage.md');
    }
    return p.posix.join(_sourceLayoutDir, '$_stem.restage.md');
  }
}

bool _parseBool(
  Object? value, {
  required String optionName,
  required bool defaultValue,
}) {
  if (value == null) return defaultValue;
  if (value is! bool) {
    throw FormatException(
      '$optionName must be a boolean, got ${value.runtimeType}.',
    );
  }
  return value;
}

String? _parseRoot(
  Object? value, {
  required String optionName,
  required bool requireUnderLib,
  required bool rejectHiddenSegments,
}) {
  if (value == null) return null;
  if (value is! String) {
    throw FormatException(
      '$optionName must be a string, got ${value.runtimeType}.',
    );
  }
  if (value.isEmpty) {
    throw FormatException('$optionName must not be empty.');
  }
  if (value.startsWith('/') || value.contains(r'\')) {
    throw FormatException('$optionName must be package-relative: "$value".');
  }
  if (RegExp('^[A-Za-z][A-Za-z0-9+.-]*:').hasMatch(value)) {
    throw FormatException('$optionName must not be a URI: "$value".');
  }
  final segments = value.split('/');
  for (final segment in segments) {
    if (segment.isEmpty) {
      throw FormatException(
        '$optionName must not contain empty path segments: "$value".',
      );
    }
    if (segment == '.' || segment == '..') {
      throw FormatException(
        '$optionName must not traverse directories: "$value".',
      );
    }
    if (segment == '.dart_tool') {
      throw FormatException(
        '$optionName must not point inside .dart_tool: "$value".',
      );
    }
    if (rejectHiddenSegments && segment.startsWith('.')) {
      throw FormatException(
        '$optionName must not use a hidden directory segment: "$value".',
      );
    }
  }
  if (requireUnderLib && segments.first != 'lib') {
    throw FormatException('$optionName must be under lib/: "$value".');
  }
  return value;
}
