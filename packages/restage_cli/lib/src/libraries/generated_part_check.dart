import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// Runs a process: the executable, its arguments and the directory to run in.
typedef GeneratedPartAnalyzer =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments,
      String workingDirectory,
    );

/// A generated part that doesn't compile: its package-relative path, and its
/// first error and where it is, as `line:column`.
@experimental
typedef GeneratedPartError = ({String path, String location, String error});

/// The JSON form of a [GeneratedPartError].
extension GeneratedPartErrorJson on GeneratedPartError {
  /// The JSON form.
  Map<String, Object?> toJson() => {
    'path': path,
    'location': location,
    'error': error,
  };
}

/// The generated parts under [root]'s `lib/` that have analyzer errors, one
/// entry per part with its first error. Empty when the package has no
/// generated parts or hasn't resolved its dependencies.
@experimental
Future<List<GeneratedPartError>> generatedPartErrors(
  Directory root, {
  GeneratedPartAnalyzer? analyze,
}) async {
  final lib = Directory(p.join(root.path, 'lib'));
  final resolved = File(
    p.join(root.path, '.dart_tool', 'package_config.json'),
  ).existsSync();
  if (!lib.existsSync() || !resolved) return const [];
  final parts = [
    for (final entity in lib.listSync(recursive: true))
      if (entity is File && entity.path.endsWith('.restage.g.dart'))
        p.relative(entity.path, from: root.path),
  ]..sort();
  if (parts.isEmpty) return const [];
  final executable =
      p.basenameWithoutExtension(Platform.resolvedExecutable).startsWith('dart')
      ? Platform.resolvedExecutable
      : 'dart';
  final result = await (analyze ?? _run)(executable, [
    'analyze',
    '--format=machine',
    ...parts,
  ], root.path);
  final first = <String, (String, String)>{};
  for (final line in '${result.stdout}\n${result.stderr}'.split('\n')) {
    final fields = line.split('|');
    if (fields.length < 8 || fields[0] != 'ERROR') continue;
    final path = p.relative(fields[3], from: root.path);
    first.putIfAbsent(
      path,
      () => ('${fields[4]}:${fields[5]}', fields.sublist(7).join('|')),
    );
  }
  return [
    for (final path in parts)
      if (first[path] case (final location, final error))
        (path: path, location: location, error: error),
  ];
}

/// The sentence for a generated part that doesn't compile.
@experimental
String generatedPartErrorSentence(GeneratedPartError part) =>
    "Restage generated code that doesn't compile "
    '(${part.path}:${part.location}): '
    '${part.error.endsWith('.') ? part.error : '${part.error}.'} Please report '
    'this as a Restage bug. Try updating Restage, then running `dart run '
    'build_runner build` again.';

Future<ProcessResult> _run(
  String executable,
  List<String> arguments,
  String workingDirectory,
) => Process.run(executable, arguments, workingDirectory: workingDirectory);
