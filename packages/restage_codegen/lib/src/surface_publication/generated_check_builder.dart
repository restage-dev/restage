// Resolves every generated part the build wrote and records each compile
// error in one. The outputs builder fails the build on them, so a build never
// succeeds with Dart that doesn't compile.

import 'dart:convert';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:glob/glob.dart';

/// The libraries the build generates whole, which the check resolves too.
const List<String> kRestageGeneratedLibraries = [
  'lib/user_factories.g.dart',
  'lib/restage_surfaces.g.dart',
  'lib/src/registration.g.dart',
];

/// Where the check records the errors it found, for the outputs builder.
const String kRestageGeneratedCheckPath =
    'lib/src/surface_publication/generated_parts.check.json';

/// Resolves each authored library that has a generated part, after every part
/// is written, and records each compile error found in a part.
final class RestageGeneratedCheckBuilder implements Builder {
  /// Creates the check.
  const RestageGeneratedCheckBuilder();

  @override
  Map<String, List<String>> get buildExtensions => const {
    r'$package$': [kRestageGeneratedCheckPath],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    final package = buildStep.inputId.package;
    List<String> errors;
    try {
      errors = await _check(buildStep);
    } on Object catch (error) {
      // A check that stops is reported as one, never as one that didn't run.
      errors = [_stopped(error)];
    }
    // Recorded, not logged: a failed step's outputs are unreadable to the
    // outputs builder, which reports them.
    await buildStep.writeAsString(
      AssetId(package, kRestageGeneratedCheckPath),
      jsonEncode(<String, Object?>{'schemaVersion': 1, 'errors': errors}),
    );
  }

  static Future<List<String>> _check(BuildStep buildStep) async {
    final package = buildStep.inputId.package;
    final errors = <String>[];
    await for (final part in buildStep.findAssets(
      Glob('lib/**.restage.g.dart'),
    )) {
      final library = _libraryOf(part, await buildStep.readAsString(part));
      if (library == null || !await buildStep.canRead(library)) {
        errors.add(
          '${part.path} belongs to no library this build can read, so '
          "Restage couldn't check that it compiles. Try deleting it, then "
          'run the build again.',
        );
        continue;
      }
      final resolved = await _resolve(buildStep, library);
      if (resolved == null) {
        errors.add(_unresolved(library.path));
        continue;
      }
      // The part can't compile while the library it belongs to doesn't.
      final own = [
        for (final unit in resolved.units)
          if (unit.uri != part.uri)
            for (final diagnostic in unit.diagnostics)
              if (diagnostic.severity == Severity.error) (unit, diagnostic),
      ];
      if (own.isNotEmpty) {
        final (unit, diagnostic) = own.first;
        final at = unit.lineInfo.getLocation(diagnostic.offset);
        errors.add(
          "${library.path} doesn't compile: "
          '${unit.uri == library.uri ? library.path : unit.uri}:'
          '${at.lineNumber}:${at.columnNumber}: ${diagnostic.message} Try '
          'fixing it, then run the build again.',
        );
        continue;
      }
      for (final unit in resolved.units) {
        if (unit.uri != part.uri) continue;
        errors.addAll(_errorsIn(unit, part.path, of: library.path));
      }
    }
    // The libraries the build generates whole.
    for (final path in kRestageGeneratedLibraries) {
      final library = AssetId(package, path);
      if (!await buildStep.canRead(library)) continue;
      final resolved = await _resolve(buildStep, library);
      if (resolved == null) {
        errors.add(_unresolved(path));
        continue;
      }
      for (final unit in resolved.units) {
        errors.addAll(_errorsIn(unit, path));
      }
    }
    return errors;
  }

  static Future<ResolvedLibraryResult?> _resolve(
    BuildStep buildStep,
    AssetId library,
  ) async {
    final element = await buildStep.resolver.libraryFor(library);
    final resolved = await element.session.getResolvedLibraryByElement(
      element,
    );
    return resolved is ResolvedLibraryResult ? resolved : null;
  }

  static String _stopped(Object error) =>
      "Restage's check that the code it generated compiles stopped with an "
      'error: $error. This is a Restage bug. Try running '
      '`dart run build_runner build` again. If it stops again, report it at '
      'https://github.com/restage-dev/restage/issues.';

  static String _unresolved(String path) =>
      "Restage couldn't resolve $path to check that the code it generated "
      'compiles. Try running the build again.';

  // The compile errors in [unit], the generated [path], made for the authored
  // library [of] when it is a part.
  static List<String> _errorsIn(
    ResolvedUnitResult unit,
    String path, {
    String? of,
  }) => [
    for (final diagnostic in unit.diagnostics)
      if (diagnostic.severity == Severity.error)
        if (unit.lineInfo.getLocation(diagnostic.offset) case final at)
          "The code generated ${of == null ? 'in $path' : 'for $of'} doesn't "
              'compile: $path:${at.lineNumber}:${at.columnNumber}: '
              '${diagnostic.message} Try marking the widget it comes from '
              '`@RenderInApp()`, and report it at '
              'https://github.com/restage-dev/restage/issues.',
  ];

  // The library [part] belongs to, from its `part of` directive.
  static AssetId? _libraryOf(AssetId part, String source) {
    final directive = parseString(
      content: source,
      throwIfDiagnostics: false,
    ).unit.directives.whereType<PartOfDirective>().firstOrNull;
    final uri = directive?.uri?.stringValue;
    return uri == null ? null : AssetId.resolve(Uri.parse(uri), from: part);
  }
}
