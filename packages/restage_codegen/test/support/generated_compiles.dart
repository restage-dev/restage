// Builds sources through the whole surface pipeline and resolves what it
// generates: a build either refuses with a diagnostic or emits Dart that
// compiles.

import 'dart:io';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:path/path.dart' as p;
import 'package:restage_codegen/builder.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// What happened to one case: compiled into [parts] generated parts, or
/// refused with [refusal].
typedef GeneratedOutcome = ({bool compiled, int parts, String? refusal});

// A refusal is a diagnostic the compiler writes for the author; anything else
// that fails the build, a malformed output included, is the generator breaking.
final RegExp _diagnostic = RegExp(
  r'^(\w+ on [^\n]*:\n)?'
  r'(\[(?!malformedTranslatorOutput\])[A-Za-z]+\] |'
  r'Bad state: \d+ Restage source roster issue)',
);

/// Builds each case's sources in [package], a batch at a time, and fails the
/// test on a build crash or generated Dart that doesn't analyze.
Future<Map<String, GeneratedOutcome>> expectGeneratedCompiles(
  Map<String, Map<String, String>> cases, {
  String package = 'apps_examples',
  int batch = 8,
  Map<String, String> Function(List<String> names)? merge,
  Set<String> Function(List<String> errors, List<String> names)? blame,
}) async {
  final outcomes = <String, GeneratedOutcome>{};
  final failures = <String>[];
  Future<void> run(List<String> names) async {
    final sources = names.length == 1 || merge == null
        ? {for (final name in names) ...cases[name]!}
        : merge(names);
    final watch = Stopwatch()..start();
    final built = await _build(sources, package);
    print(
      'built ${names.length} case(s) in ${watch.elapsed.inSeconds}s: '
      '${built.errors.isEmpty ? '${built.libraries.length} parts' : 'refused'}',
    );
    if (built.errors.isEmpty) {
      final errors = await _analysisErrors(
        {...sources, ...built.generated},
        built.libraries,
        package,
      );
      if (errors.isEmpty || names.length == 1) {
        // A batch's parts are counted once, on its first case.
        for (final (index, name) in names.indexed) {
          outcomes[name] = (
            compiled: true,
            parts: index == 0 ? built.libraries.length : 0,
            refusal: null,
          );
        }
        if (errors.isNotEmpty) {
          failures.add('${names.single}:\n  ${errors.join('\n  ')}');
        }
        return;
      }
    } else if (names.length > 1 && blame != null) {
      // A batch refused only for its authors' reasons drops the cases the
      // diagnostics name and builds the rest again.
      final crash = built.errors.where((e) => !_diagnostic.hasMatch(e));
      final blamed = crash.isEmpty ? blame(built.errors, names) : <String>{};
      if (blamed.isNotEmpty) {
        for (final name in blamed) {
          outcomes[name] = (
            compiled: false,
            parts: 0,
            refusal: built.errors
                .firstWhere(
                  (e) => blame([e], [name]).isNotEmpty,
                  orElse: () => built.errors.first,
                )
                .split('\n')
                .firstWhere(
                  (line) => line.startsWith('['),
                  orElse: () => '',
                ),
          );
        }
        final rest = [
          for (final name in names)
            if (!blamed.contains(name)) name,
        ];
        if (rest.isNotEmpty) await run(rest);
        return;
      }
    }
    if (built.errors.isNotEmpty && names.length == 1) {
      final crash = built.errors.where((e) => !_diagnostic.hasMatch(e));
      if (crash.isNotEmpty) {
        failures.add(
          '${names.single} broke the build:\n  ${crash.join('\n  ')}',
        );
      }
      outcomes[names.single] = (
        compiled: false,
        parts: 0,
        refusal: built.errors.first
            .split('\n')
            .firstWhere(
              (line) => line.startsWith('['),
              orElse: () => built.errors.first,
            ),
      );
      return;
    }
    // A batch that refused or broke is split until each case stands alone.
    final half = names.length ~/ 2;
    await run(names.sublist(0, half));
    await run(names.sublist(half));
  }

  final names = cases.keys.toList();
  for (var start = 0; start < names.length; start += batch) {
    await run(names.sublist(start, (start + batch).clamp(0, names.length)));
  }
  expect(failures, isEmpty, reason: failures.join('\n\n'));
  return outcomes;
}

/// Prints how many cases compiled and why each other one was refused.
void printOutcomes(Map<String, GeneratedOutcome> outcomes) {
  final compiled = outcomes.values.where((o) => o.compiled);
  print(
    'compiled ${compiled.length} of ${outcomes.length}, '
    '${compiled.fold(0, (sum, o) => sum + o.parts)} generated parts',
  );
  for (final MapEntry(:key, :value) in outcomes.entries) {
    if (!value.compiled) print('refused: $key: ${value.refusal}');
  }
}

/// The Dart sources under `lib` of the workspace package at [root], without
/// generated files, and its durable Restage state, keyed by package-relative
/// path.
Map<String, String> packageSources(String root) {
  Iterable<File> under(String directory) {
    final base = Directory(p.join(root, directory));
    return base.existsSync()
        ? base.listSync(recursive: true).whereType<File>()
        : const [];
  }

  String relative(File file) =>
      p.posix.joinAll(p.split(p.relative(file.path, from: root)));
  return {
    for (final file in under('lib'))
      if (file.path.endsWith('.dart') &&
          !file.path.endsWith('.g.dart') &&
          !file.path.contains('${p.separator}restage.generated${p.separator}'))
        relative(file): file.readAsStringSync(),
    for (final file in under('.restage'))
      if (!file.path.contains('${p.separator}build${p.separator}'))
        relative(file): file.readAsStringSync(),
  };
}

Future<
  ({
    List<String> errors,
    Map<String, String> generated,
    List<String> libraries,
  })
>
_build(Map<String, String> sources, String package) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    entrypoints: _entrypoints(sources, package),
    rootPackage: package,
    includeFlutter: true,
    includeIntl: true,
  );
  const options = BuilderOptions({'bundled_runtime': true}, isRoot: true);
  final result = await testBuilders(
    [
      restageSourceRosterBuilder(options),
      userCatalogJsonBuilder(BuilderOptions.empty),
      restagePackageSurfaceCompilerBuilder(options),
      restageGeneratedDartBuilder(
        const BuilderOptions({'bundled_runtime': true}),
      ),
      userCatalogBuilder(BuilderOptions.forRoot),
      userFactoryBuilder(BuilderOptions.forRoot),
    ],
    {
      for (final MapEntry(:key, :value) in sources.entries)
        '$package|$key': value,
    },
    rootPackage: package,
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  if (!result.succeeded) {
    return (
      errors: [for (final e in result.errors) '$e'],
      generated: const <String, String>{},
      libraries: const <String>[],
    );
  }
  final generated = <String, String>{};
  for (final id in readerWriter.testing.assetsWritten) {
    if (id.package == package && id.path.endsWith('.dart')) {
      generated[id.path] = readerWriter.testing.readString(id);
    }
  }
  // Each authored library a generated part belongs to.
  final libraries = [
    for (final path in sources.keys)
      if (generated.containsKey(
        p.posix.join(
          p.posix.dirname(path),
          'restage.generated',
          '${p.posix.basenameWithoutExtension(path)}.restage.g.dart',
        ),
      ))
        path,
  ];
  return (errors: const <String>[], generated: generated, libraries: libraries);
}

// Every error the analyzer reports in [libraries] and their parts.
Future<List<String>> _analysisErrors(
  Map<String, String> sources,
  List<String> libraries,
  String package,
) async {
  if (libraries.isEmpty) return const [];
  final errors = <String>[];
  await resolveWorkspaceSources(
    {
      for (final MapEntry(:key, :value) in sources.entries)
        '$package|$key': value,
    },
    (resolver) async {
      for (final path in libraries) {
        final library = await resolver.libraryFor(AssetId(package, path));
        final resolved = await library.session.getResolvedLibraryByElement(
          library,
        );
        if (resolved is! ResolvedLibraryResult) {
          errors.add('$path did not resolve');
          continue;
        }
        for (final unit in resolved.units) {
          for (final diagnostic in unit.diagnostics) {
            if (diagnostic.severity != Severity.error) continue;
            final at = unit.lineInfo.getLocation(diagnostic.offset);
            final line = unit.content.split('\n')[at.lineNumber - 1].trim();
            errors.add(
              '${p.basename(unit.path)}:${at.lineNumber}:${at.columnNumber}: '
              '${diagnostic.message} [$line]',
            );
          }
        }
      }
    },
    resolverFor: '$package|${libraries.first}',
    rootPackage: package,
    includeFlutter: true,
    includeIntl: true,
    entrypoints: _entrypoints(sources, package),
  );
  return errors;
}

// The other packages' libraries [sources] import, by package.
Map<String, List<String>> _entrypoints(
  Map<String, String> sources,
  String package,
) {
  final found = <String, Set<String>>{};
  for (final source in sources.values) {
    for (final match in RegExp(
      r"^(?:import|export) 'package:([a-z0-9_]+)/([^']+)'",
      multiLine: true,
    ).allMatches(source)) {
      if (match[1] == package) continue;
      (found[match[1]!] ??= {}).add('lib/${match[2]}');
    }
  }
  return {
    for (final MapEntry(:key, :value) in found.entries) key: value.toList(),
  };
}
