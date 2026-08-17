import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:build/build.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:restage_codegen/src/surface_publication/output_placement.dart';
import 'package:restage_codegen/src/surface_publication/placement_registry.dart';
import 'package:restage_codegen/src/widgetbook/widgetbook_catalog_source_index.dart';
import 'package:restage_codegen/src/widgetbook/widgetbook_story_plan.dart';
import 'package:restage_codegen/src/widgetbook/widgetbook_story_source_renderer.dart';

final Resource<WidgetbookCatalogIndexCache> _widgetbookCatalogResource =
    Resource<WidgetbookCatalogIndexCache>(WidgetbookCatalogIndexCache.new);

const _widgetbookStoryBuilderSentinelOutput =
    'generated/.restage_widgetbook_story_builder';

/// Creates the opt-in Widgetbook v4 story builder.
Builder createWidgetbookStoryBuilder(BuilderOptions options) =>
    createWidgetbookStoryBuilderForLib(options, Directory('lib'));

/// The package-relative story path a class-derived story library occupies
/// under [plan], for a component declared in [declarationSourcePath].
///
/// Story source is generated Dart, so it is placed exactly like the neutral
/// part of the library that declares the component.
String widgetbookStoryPath(
  RestageOutputPlacementPlan plan, {
  required String declarationSourcePath,
  required String className,
}) =>
    plan.forLibrary(declarationSourcePath).generatedDartPath(
          '${_snakeCase(className)}.stories.dart',
        );

/// Creates the Widgetbook story builder against an explicit package lib root.
///
/// Production builds use [createWidgetbookStoryBuilder]. This seam lets tests
/// isolate startup discovery without mutating the process-wide current
/// directory shared by concurrent tests.
@visibleForTesting
Builder createWidgetbookStoryBuilderForLib(
  BuilderOptions options,
  Directory lib,
) {
  requireOnlyRestagePlacementOptions(
    options,
    featureLabel: 'Widgetbook story generation',
  );
  final plan = RestageOutputPlacementPlan.fromBuilderOptions(options);
  return WidgetbookStoryBuilder(_discoverOutputs(lib, plan), plan: plan);
}

/// Emits every package story from one analyzer-authoritative package step.
final class WidgetbookStoryBuilder implements Builder {
  /// Creates a builder with startup-discovered outputs.
  ///
  /// [plan] is omitted only by callers that exercise the default placement;
  /// production always passes the factory-resolved plan.
  const WidgetbookStoryBuilder(this.buildExtensions, {this.plan});

  @override
  final Map<String, List<String>> buildExtensions;

  /// The resolved placement authority for story source, or `null` for the
  /// default layout.
  final RestageOutputPlacementPlan? plan;

  RestageOutputPlacementPlan get _placement =>
      plan ?? RestageOutputPlacementPlan.defaults;

  @override
  Future<void> build(BuildStep buildStep) async {
    await registerRestagePlacementSignature(
      buildStep,
      _placement,
      builderKey: 'restage_codegen:widgetbook_stories',
    );

    final cache = await buildStep.fetchResource(_widgetbookCatalogResource);
    final index = await cache.getOrLoad(buildStep, _placement);
    final packageName = buildStep.inputId.package;
    final declaredOutputs =
        buildExtensions[r'$lib$']?.toSet() ?? const <String>{};
    final ownersByOutput = <String, List<WidgetbookWidgetSource>>{};
    for (final widget in index.storySources) {
      final className = widget.className;
      final sourceLabel =
          widget.nativeScreen?.sourceAnnotation ?? '@RestageWidget';
      final output = _libRelative(
        widgetbookStoryPath(
          _placement,
          declarationSourcePath: widget.sourceAsset.path,
          className: className,
        ),
      );
      if (!declaredOutputs.contains(output)) {
        final outputId = AssetId(packageName, 'lib/$output');
        if (await buildStep.canRead(outputId)) {
          final existingSource = await buildStep.readAsString(outputId);
          if (!isRestageWidgetbookStorySource(existingSource)) {
            throw StateError(
              'Genuine $sourceLabel declaration '
              '${widget.declarationSourcePath}#$className conflicts with the '
              'existing hand-authored Widgetbook story at lib/$output. Move '
              'or rename the hand-authored story, or rename the Restage '
              'widget class so each owns a distinct story path.',
            );
          }
        }
        throw StateError(
          'Widgetbook story output membership changed after this builder '
          'started: ${widget.declarationSourcePath}#$className requires '
          'lib/$output. Restart dart run '
          'build_runner watch to refresh generated story outputs.',
        );
      }
      ownersByOutput.putIfAbsent(output, () => []).add(widget);
    }

    final outputs = ownersByOutput.keys.toList()..sort();
    for (final output in outputs) {
      final owners = ownersByOutput[output]!
        ..sort(
          (left, right) {
            final byPath = left.declarationSourcePath.compareTo(
              right.declarationSourcePath,
            );
            return byPath != 0
                ? byPath
                : left.className.compareTo(right.className);
          },
        );
      if (owners.length > 1) {
        final declarations = owners
            .map(
              (widget) => '${widget.declarationSourcePath}#${widget.className}',
            )
            .join(', ');
        final ownerLabel = _sourceDeclarationsLabel(owners);
        throw StateError(
          "Widgetbook story output 'lib/$output' is ambiguous across genuine "
          '$ownerLabel: $declarations. Rename one class so '
          'each generated story path is unique.',
        );
      }

      final widget = owners.single;
      final plan = planWidgetbookStory(
        index: index,
        widget: widget,
      );
      final source = renderWidgetbookStorySource(
        plan: plan,
        packageName: packageName,
        sourcePath: widget.sourceAsset.path,
      );
      await buildStep.writeAsString(
        AssetId(packageName, 'lib/$output'),
        source,
      );
    }

    final disabledWidgetOutputs = {
      for (final identity in index.restageWidgetDeclarations)
        _libRelative(
          widgetbookStoryPath(
            _placement,
            declarationSourcePath: _declaringLibraryPath(identity),
            className: identity.substring(identity.lastIndexOf('#') + 1),
          ),
        ),
    };
    final inactiveOutputs = <String>{};
    for (final output in declaredOutputs.difference(outputs.toSet())) {
      if (output == _widgetbookStoryBuilderSentinelOutput) {
        continue;
      }
      if (disabledWidgetOutputs.contains(output)) {
        inactiveOutputs.add(output);
        continue;
      }
      final outputId = AssetId(packageName, 'lib/$output');
      if (await buildStep.canRead(outputId) &&
          isRestageWidgetbookStorySource(
            await buildStep.readAsString(outputId),
          )) {
        inactiveOutputs.add(output);
      }
    }
    for (final output in inactiveOutputs.toList()..sort()) {
      await buildStep.writeAsString(
        AssetId(packageName, 'lib/$output'),
        '$widgetbookStoryOwnershipPrefix\n'
        '// No enabled Restage source currently owns this story.\n',
      );
    }
  }
}

String _sourceDeclarationsLabel(List<WidgetbookWidgetSource> owners) {
  if (owners.every((owner) => !owner.isNativeScreen)) {
    return '@RestageWidget declarations';
  }
  if (owners.every((owner) => owner.isNativeScreen)) {
    final nativeSourceAnnotations =
        owners.map((owner) => owner.nativeScreen!.sourceAnnotation).toSet();
    if (nativeSourceAnnotations.length == 1) {
      return '${nativeSourceAnnotations.single} declarations';
    }
    return 'native screen declarations';
  }
  return 'Restage source declarations';
}

/// The `lib/`-relative form of a package-relative generated path.
String _libRelative(String packageRelativePath) =>
    p.posix.relative(packageRelativePath, from: 'lib');

/// The package-relative path of the library in a `<uri>#<class>` identity.
String _declaringLibraryPath(String declarationIdentity) => AssetId.resolve(
      Uri.parse(
        declarationIdentity.substring(
          0,
          declarationIdentity.lastIndexOf('#'),
        ),
      ),
    ).path;

Map<String, List<String>> _discoverOutputs(
  Directory lib,
  RestageOutputPlacementPlan plan,
) {
  final outputs = <String>{_widgetbookStoryBuilderSentinelOutput};
  if (!lib.existsSync()) return _buildExtensions(outputs);
  outputs.addAll(_existingRestageStoryOutputs(lib));
  for (final authored in _readAuthoredUnits(lib)) {
    for (final name in _annotatedClassNames(authored.unit)) {
      final output = _libRelative(
        widgetbookStoryPath(
          plan,
          declarationSourcePath: authored.libraryPath,
          className: name,
        ),
      );
      if (_canReserveOutput(lib, output)) outputs.add(output);
    }
  }
  return _buildExtensions(outputs);
}

Map<String, List<String>> _buildExtensions(Set<String> outputs) {
  final sorted = outputs.toList()..sort();
  return Map.unmodifiable({r'$lib$': List<String>.unmodifiable(sorted)});
}

bool _canReserveOutput(Directory lib, String output) {
  final file = File(
    p.joinAll(<String>[lib.path, ...p.posix.split(output)]),
  );
  if (!file.existsSync()) return true;
  RandomAccessFile? reader;
  try {
    reader = file.openSync();
    final prefix = reader.readSync(widgetbookStoryOwnershipProbeLength);
    return isRestageWidgetbookStorySource(String.fromCharCodes(prefix));
  } on FileSystemException {
    // If startup cannot prove ownership, leave the source customer-owned. The
    // analyzer-backed build step will either ignore it or report a genuine
    // collision with its exact asset path.
    return false;
  } finally {
    reader?.closeSync();
  }
}

/// Every already-present story file beneath `lib/`, wherever a placement
/// mode put it.
///
/// The scan is placement-agnostic on purpose: a story generated under one
/// layout must still be recognized — and retired — after the package changes
/// its layout.
Iterable<String> _existingRestageStoryOutputs(Directory lib) sync* {
  if (!lib.existsSync()) return;
  final stories = lib
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((file) => file.path.endsWith('.stories.dart'))
      .toList()
    ..sort((left, right) => left.path.compareTo(right.path));
  for (final story in stories) {
    final output = p.posix.normalize(
      p.relative(story.path, from: lib.path).replaceAll(r'\', '/'),
    );
    if (_canReserveOutput(lib, output)) yield output;
  }
}

/// One authored library, with the package-relative path story placement is
/// resolved against.
@immutable
final class _AuthoredUnit {
  const _AuthoredUnit({required this.libraryPath, required this.unit});

  final String libraryPath;
  final CompilationUnit unit;
}

List<_AuthoredUnit> _readAuthoredUnits(Directory lib) {
  final files = lib
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((file) => _isAuthoredDartFile(file.path))
      .toList()
    ..sort((left, right) => left.path.compareTo(right.path));
  return [
    for (final file in files) _authoredUnit(lib, file),
  ];
}

/// One parsed authored file, attributed to the library that owns its
/// declarations.
///
/// A class declared in a `part` belongs to the owning library, and that is
/// the library whose placement decides where its story is written.
_AuthoredUnit _authoredUnit(Directory lib, File file) {
  final unit = parseString(
    content: file.readAsStringSync(),
    path: file.path,
    throwIfDiagnostics: false,
  ).unit;
  final own = p.posix.join(
    'lib',
    p.posix.joinAll(p.split(p.relative(file.path, from: lib.path))),
  );
  final partOf = unit.directives.whereType<PartOfDirective>().firstOrNull;
  final ownerUri = partOf?.uri?.stringValue;
  return _AuthoredUnit(
    libraryPath: ownerUri == null ? own : _resolveOwnerPath(own, ownerUri),
    unit: unit,
  );
}

/// The package-relative path a `part of` URI names, from a part at [own].
///
/// A package URI resolves against `lib/` because startup discovery only ever
/// walks the owning package's own sources.
String _resolveOwnerPath(String own, String ownerUri) {
  final uri = Uri.tryParse(ownerUri);
  if (uri != null && uri.scheme == 'package' && uri.pathSegments.length > 1) {
    return p.posix.join('lib', p.posix.joinAll(uri.pathSegments.skip(1)));
  }
  return p.posix.normalize(p.posix.join(p.posix.dirname(own), ownerUri));
}

bool _isAuthoredDartFile(String path) =>
    path.endsWith('.dart') &&
    !path.endsWith('.stories.dart') &&
    !path.endsWith('.g.dart') &&
    !p.split(path).contains(kRestageGeneratedDirectoryName);

Iterable<String> _annotatedClassNames(
  CompilationUnit unit,
) =>
    unit.declarations
        .whereType<ClassDeclaration>()
        // Imported const aliases cannot be identified soundly without package
        // resolution, which is unavailable while build_runner asks the factory
        // for its fixed output set. Every annotated class is therefore a
        // possible output unless that path is already customer-authored. The
        // analyzer-backed package index remains the sole authority that owns
        // and emits stories, so unrelated annotations and lookalikes remain
        // inert.
        .where((declaration) => declaration.metadata.isNotEmpty)
        .map(_className);

String _className(ClassDeclaration declaration) {
  final name = declaration.namePart;
  if (name is NameWithTypeParameters) return name.typeName.lexeme;
  throw StateError('Primary constructors are not supported.');
}

String _snakeCase(String value) => value
    .replaceAllMapped(
      RegExp('([a-z0-9])([A-Z])'),
      (match) => '${match[1]}_${match[2]}',
    )
    .toLowerCase();
