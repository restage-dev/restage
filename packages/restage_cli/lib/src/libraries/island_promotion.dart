import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/libraries/build_report.dart';

/// Where a promoted widget's name goes in a promotion plan.
const _nameHole = '{{name}}';

/// What a promotion changed.
@experimental
typedef PromotionResult = ({String file, String library, String name});

/// Moves the island the last build placed at [at] (`path:line` or
/// `path:line:column`) into a widget class named [name], exported from the
/// widget library at [library] or the package's only one.
///
/// Throws [BuildReportException] with the sentence that says why not.
@experimental
PromotionResult promoteIsland(
  Directory root,
  BuildReport report,
  String at, {
  String? name,
  String? library,
}) {
  final wanted = _location(at);
  if (wanted == null) {
    throw BuildReportException(
      "`$at` isn't a file location. Try a location in the form "
      '`<file>:<line>`, as `restage build report` prints it.',
    );
  }
  String absolute(String file) =>
      p.normalize(p.isAbsolute(file) ? file : p.join(root.path, file));
  final matches = <BuildReportPart>[];
  for (final part in report.parts.where((part) => part.kind == 'island')) {
    final location = _location(part.location);
    if (location != null &&
        absolute(location.file) == absolute(wanted.file) &&
        location.line == wanted.line &&
        (wanted.column == null || location.column == wanted.column)) {
      matches.add(part);
    }
  }
  if (matches.isEmpty) {
    throw BuildReportException(
      'Nothing at $at renders from the app. Try `restage build report` to see '
      'what does.',
    );
  }
  if ({for (final part in matches) part.location}.length > 1) {
    throw BuildReportException(
      'More than one widget at $at renders from the app. Try adding the '
      'column, as in ${matches.first.location}.',
    );
  }
  final island = matches.first;
  final plan = island.promotion ?? const {};
  if (plan['refusal'] case final String refusal) {
    throw BuildReportException(refusal);
  }
  final className =
      name ??
      '${island.mount.replaceFirst(RegExp(r'Surface$'), '')}${island.widget.split('.').first}';
  if (!RegExp(r'^[A-Z][A-Za-z0-9]*$').hasMatch(className)) {
    throw BuildReportException(
      "`$className` isn't a valid name for the new class. Try a name that "
      'starts with a capital letter and has only letters and digits.',
    );
  }
  final relative = plan['file']! as String;
  final file = File(p.join(root.path, relative));
  final source = file.existsSync() ? file.readAsStringSync() : '';
  final offset = plan['offset']! as int;
  final original = plan['original']! as String;
  if (offset + original.length > source.length ||
      source.substring(offset, offset + original.length) != original) {
    throw BuildReportException(
      '$relative changed since the last build. Try running `dart run '
      'build_runner build`, then `restage $promoteCommandName` again.',
    );
  }
  if (RegExp(
    '\\b(class|typedef|enum|mixin)\\s+$className\\b',
  ).hasMatch(source)) {
    throw BuildReportException(
      '$relative already declares `$className`. Try another name with '
      '`--name`.',
    );
  }
  final barrel = _barrel(root, library);
  String named(Object? text) =>
      (text! as String).replaceAll(_nameHole, className);
  final updated =
      '${source.replaceRange(offset, offset + original.length, named(plan['call']))}'
      '${source.endsWith('\n') ? '' : '\n'}\n${named(plan['class'])}\n';
  file.writeAsStringSync(updated);
  if (!p.equals(barrel.path, file.path)) {
    barrel.writeAsStringSync(
      _exporting(
        barrel.readAsStringSync(),
        p.posix.joinAll(
          p.split(p.relative(file.path, from: barrel.parent.path)),
        ),
        className,
      ),
    );
  }
  return (
    file: relative,
    library: p.posix.joinAll(p.split(p.relative(barrel.path, from: root.path))),
    name: className,
  );
}

/// The sentence a promotion ends with.
@experimental
String promotedSentence(PromotionResult result) =>
    'Moved the widget into the new class `${result.name}` in ${result.file} '
    'and exported it from ${result.library}. Run `dart run build_runner '
    'build` to compile it.';

({String file, int line, int? column})? _location(String at) {
  final match = RegExp(r'^(.+?):(\d+)(?::(\d+))?$').firstMatch(at);
  if (match == null) return null;
  return (
    file: match[1]!,
    line: int.parse(match[2]!),
    column: match[3] == null ? null : int.parse(match[3]!),
  );
}

// The widget library to export from: [named], or the package's only one.
File _barrel(Directory root, String? named) {
  if (named != null) {
    final file = File(p.join(root.path, named));
    if (!file.existsSync() ||
        !file.readAsStringSync().contains('@RestageLibrary(')) {
      throw BuildReportException(
        '$named has no `@RestageLibrary` annotation. Try passing a library '
        'that has one to `--library`.',
      );
    }
    return file;
  }
  final lib = Directory(p.join(root.path, 'lib'));
  final barrels = [
    if (lib.existsSync())
      for (final entity in lib.listSync(recursive: true))
        if (entity is File &&
            entity.path.endsWith('.dart') &&
            !entity.path.endsWith('.g.dart') &&
            entity.readAsStringSync().contains('@RestageLibrary('))
          entity,
  ]..sort((a, b) => a.path.compareTo(b.path));
  return switch (barrels) {
    [final only] => only,
    [] => throw const BuildReportException(
      'No library in the package has a `@RestageLibrary` annotation to export '
      'the new widget from. Try adding one under lib/, or passing one with '
      '`--library`.',
    ),
    _ => throw BuildReportException(
      'More than one library in the package has a `@RestageLibrary` '
      'annotation (${[for (final b in barrels) p.relative(b.path, from: root.path)].join(', ')}). '
      'Try choosing one with `--library`.',
    ),
  };
}

// [barrel] exporting [name] from [path].
String _exporting(String barrel, String path, String name) {
  final existing = RegExp(
    "^export\\s+['\"]${RegExp.escape(path)}['\"]([^;]*);",
    multiLine: true,
  ).firstMatch(barrel);
  if (existing != null) {
    final combinators = existing[1]!;
    final show = RegExp(r'\bshow\s+([^;]*)').firstMatch(combinators);
    if (show == null) return barrel;
    return barrel.replaceRange(
      existing.start + existing[0]!.indexOf(show[0]!) + show[0]!.length,
      existing.start + existing[0]!.indexOf(show[0]!) + show[0]!.length,
      ', $name',
    );
  }
  final line = "export '$path' show $name;\n";
  final directives = RegExp(
    r'^(import|export)\s[^;]*;\n?',
    multiLine: true,
  ).allMatches(barrel);
  if (directives.isEmpty) return '$line$barrel';
  final end = directives.last.end;
  final newline = barrel.substring(end - 1, end) == '\n' ? '' : '\n';
  return '${barrel.substring(0, end)}$newline$line${barrel.substring(end)}';
}
