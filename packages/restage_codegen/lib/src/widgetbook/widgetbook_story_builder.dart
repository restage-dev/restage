import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:build/build.dart';
import 'package:path/path.dart' as p;
import 'package:restage_codegen/src/widgetbook/widgetbook_catalog_source_index.dart';
import 'package:restage_codegen/src/widgetbook/widgetbook_story_plan.dart';
import 'package:restage_codegen/src/widgetbook/widgetbook_story_source_renderer.dart';

final Resource<WidgetbookCatalogIndexCache> _widgetbookCatalogResource =
    Resource<WidgetbookCatalogIndexCache>(WidgetbookCatalogIndexCache.new);

/// Creates the opt-in Widgetbook v4 story builder.
Builder createWidgetbookStoryBuilder(BuilderOptions options) {
  if (options.config.isNotEmpty) {
    throw ArgumentError(
      'Widgetbook story generation has no per-widget authoring options; remove '
      'unsupported option(s): ${options.config.keys.join(', ')}.',
    );
  }
  return WidgetbookStoryBuilder(_discoverOutputs());
}

/// Emits one story output for every annotated class in each discovered input.
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
    final outputs = buildExtensions[buildStep.inputId.path] ?? const [];
    final ownedWidgets = index.widgets.where(
      (widget) => widget.sourceAsset == buildStep.inputId,
    );

    for (final widget in ownedWidgets) {
      final className = widget.className;
      final expectedName = '${_snakeCase(className)}.stories.dart';
      final matchingOutputs =
          outputs.where((path) => p.basename(path) == expectedName).toList();
      if (matchingOutputs.isEmpty) {
        throw StateError(
          'Widgetbook story discovery found $className after this builder '
          'started. Restart dart run build_runner watch to refresh generated '
          'story outputs.',
        );
      }
      if (matchingOutputs.length > 1) {
        throw StateError(
          'Widgetbook story output for $className is ambiguous in '
          '${buildStep.inputId.path}.',
        );
      }

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
        AssetId(packageName, matchingOutputs.single),
        source,
      );
    }
  }
}

Map<String, List<String>> _discoverOutputs() {
  final lib = Directory('lib');
  if (!lib.existsSync()) return const {};
  final sources = _readAuthoredSources(lib);
  final outputs = <String, List<String>>{};
  final owners = <String, String>{};
  for (final source in sources.values) {
    if (source.unit.directives.whereType<PartOfDirective>().isNotEmpty) {
      continue;
    }
    final names = <String>[
      ..._annotatedClassNames(source.unit),
      for (final part in _partSources(source, sources))
        ..._annotatedClassNames(part.unit),
    ];
    if (names.isEmpty) continue;
    final generated = <String>[];
    for (final name in names) {
      final output = 'lib/generated/${_snakeCase(name)}.stories.dart';
      final prior = owners[output];
      if (prior != null) {
        throw ArgumentError(
          "Widgetbook story output '$output' is ambiguous: both '$prior' "
          "and '${source.path}' declare @RestageWidget class '$name'. Rename "
          'one class so each generated story path is unique.',
        );
      }
      owners[output] = source.path;
      generated.add(output);
    }
    if (generated.isNotEmpty) {
      outputs[source.path] = List.unmodifiable(generated);
    }
  }
  return Map.unmodifiable(outputs);
}

Map<String, _ParsedSource> _readAuthoredSources(Directory lib) {
  final files = lib
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((file) => _isAuthoredDartFile(file.path))
      .toList()
    ..sort((left, right) => left.path.compareTo(right.path));
  return {
    for (final file in files)
      _assetPath(file.path): _ParsedSource(
        path: _assetPath(file.path),
        unit: parseString(
          content: file.readAsStringSync(),
          path: file.path,
          throwIfDiagnostics: false,
        ).unit,
      ),
  };
}

bool _isAuthoredDartFile(String path) =>
    path.endsWith('.dart') &&
    !path.endsWith('.stories.dart') &&
    !path.endsWith('.g.dart');

String _assetPath(String path) => p.posix.normalize(
      p.relative(path, from: Directory.current.path).replaceAll(r'\', '/'),
    );

Iterable<_ParsedSource> _partSources(
  _ParsedSource source,
  Map<String, _ParsedSource> sources,
) sync* {
  for (final directive in source.unit.directives.whereType<PartDirective>()) {
    final uri = directive.uri.stringValue;
    if (uri == null) continue;
    final path = p.posix.normalize(
      p.posix.join(p.posix.dirname(source.path), uri.replaceAll(r'\', '/')),
    );
    if (!path.startsWith('lib/')) continue;
    final part = sources[path];
    if (part != null) yield part;
  }
}

Iterable<String> _annotatedClassNames(
  CompilationUnit unit,
) =>
    unit.declarations
        .whereType<ClassDeclaration>()
        // Startup output discovery is deliberately syntax-broad so genuine
        // annotations imported through customer barrels still schedule a build
        // step. The analyzer-backed package index is the strict origin check;
        // unrelated lookalike annotations never produce a story.
        .where(_hasRestageWidgetAnnotation)
        .map(_className);

final class _ParsedSource {
  const _ParsedSource({required this.path, required this.unit});

  final String path;
  final CompilationUnit unit;
}

String _className(ClassDeclaration declaration) {
  final name = declaration.namePart;
  if (name is NameWithTypeParameters) return name.typeName.lexeme;
  throw StateError('Primary constructors are not supported.');
}

bool _hasRestageWidgetAnnotation(ClassDeclaration declaration) =>
    declaration.metadata.any((annotation) {
      final name = annotation.name;
      if (name is SimpleIdentifier) {
        return name.name == 'RestageWidget';
      }
      return name is PrefixedIdentifier &&
          name.identifier.name == 'RestageWidget';
    });

String _snakeCase(String value) => value
    .replaceAllMapped(
      RegExp('([a-z0-9])([A-Z])'),
      (match) => '${match[1]}_${match[2]}',
    )
    .toLowerCase();
