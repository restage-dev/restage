import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:build/build.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
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
  if (options.config.isNotEmpty) {
    throw ArgumentError(
      'Widgetbook story generation has no per-widget authoring options; remove '
      'unsupported option(s): ${options.config.keys.join(', ')}.',
    );
  }
  return WidgetbookStoryBuilder(_discoverOutputs(lib));
}

/// Emits every package story from one analyzer-authoritative package step.
final class WidgetbookStoryBuilder implements Builder {
  /// Creates a builder with startup-discovered outputs.
  const WidgetbookStoryBuilder(this.buildExtensions);

  @override
  final Map<String, List<String>> buildExtensions;

  @override
  Future<void> build(BuildStep buildStep) async {
    final cache = await buildStep.fetchResource(_widgetbookCatalogResource);
    final index = await cache.getOrLoad(buildStep);
    final packageName = buildStep.inputId.package;
    final declaredOutputs =
        buildExtensions[r'$lib$']?.toSet() ?? const <String>{};
    final ownersByOutput = <String, List<WidgetbookWidgetSource>>{};
    for (final widget in index.storySources) {
      final className = widget.className;
      final sourceLabel =
          widget.isNativeScreen ? '@ScreenSource' : '@RestageWidget';
      final output = 'generated/${_snakeCase(className)}.stories.dart';
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
      for (final className in index.restageWidgetClassNames)
        'generated/${_snakeCase(className)}.stories.dart',
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
    return '@ScreenSource declarations';
  }
  return 'Restage source declarations';
}

Map<String, List<String>> _discoverOutputs(Directory lib) {
  final outputs = <String>{_widgetbookStoryBuilderSentinelOutput};
  if (!lib.existsSync()) return _buildExtensions(outputs);
  outputs.addAll(_existingRestageStoryOutputs(lib));
  for (final unit in _readAuthoredUnits(lib)) {
    for (final name in _annotatedClassNames(unit)) {
      final output = 'generated/${_snakeCase(name)}.stories.dart';
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

Iterable<String> _existingRestageStoryOutputs(Directory lib) sync* {
  final generated = Directory(p.join(lib.path, 'generated'));
  if (!generated.existsSync()) return;
  final stories = generated
      .listSync(followLinks: false)
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

List<CompilationUnit> _readAuthoredUnits(Directory lib) {
  final files = lib
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((file) => _isAuthoredDartFile(file.path))
      .toList()
    ..sort((left, right) => left.path.compareTo(right.path));
  return [
    for (final file in files)
      parseString(
        content: file.readAsStringSync(),
        path: file.path,
        throwIfDiagnostics: false,
      ).unit,
  ];
}

bool _isAuthoredDartFile(String path) =>
    path.endsWith('.dart') &&
    !path.endsWith('.stories.dart') &&
    !path.endsWith('.g.dart');

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
