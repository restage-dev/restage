// A throwaway Flutter app that depends on this repository's packages, for
// tests that run a real `dart run build_runner build`.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// The `pubspec.yaml` of an app named [name] depending on `restage` and
/// building with this `restage_codegen`, from the `packages/` directory
/// [packages].
String scratchAppPubspec(String packages, {String name = 'app'}) {
  final overrides = workspaceClosure(
    p.normalize(p.join(packages, '..')),
    const [
      'restage',
      'restage_codegen',
    ],
  );
  return '''
name: $name
publish_to: none
environment:
  sdk: ^3.9.0
dependencies:
  flutter:
    sdk: flutter
  restage:
    path: ${p.join(packages, 'restage')}
dev_dependencies:
  build_runner: any
  flutter_test:
    sdk: flutter
  restage_codegen:
    path: ${p.join(packages, 'restage_codegen')}
  restage_shared:
    path: ${p.join(packages, 'restage_shared')}
dependency_overrides:
${[for (final MapEntry(key: name, value: path) in overrides.entries) '  $name:\n    path: $path'].join('\n')}
''';
}

/// Runs `dart run build_runner build` in [app].
Future<ProcessResult> buildScratchApp(String app) => Process.run('dart', [
  'run',
  'build_runner',
  'build',
], workingDirectory: app);

/// What [result] printed.
String processOutput(ProcessResult result) =>
    '${result.stdout}\n${result.stderr}';

/// Writes [contents] at [path] under [root].
void writeScratchFile(String root, String path, String contents) =>
    File(p.join(root, path))
      ..createSync(recursive: true)
      ..writeAsStringSync(contents);

/// The workspace members [roots] reach through `dependencies`, by name, each
/// with its directory, read from the root pubspec's `workspace:` list.
Map<String, String> workspaceClosure(String repoRoot, List<String> roots) {
  YamlMap pubspec(String directory) =>
      loadYaml(File(p.join(directory, 'pubspec.yaml')).readAsStringSync())
          as YamlMap;
  final members = <String, String>{
    for (final path
        in (pubspec(repoRoot)['workspace'] as YamlList).cast<String>())
      if (p.join(repoRoot, path) case final directory)
        pubspec(directory)['name'] as String: directory,
  };
  final closure = <String, String>{};
  final pending = [...roots];
  while (pending.isNotEmpty) {
    final name = pending.removeLast();
    final directory = members[name];
    if (directory == null || closure.containsKey(name)) continue;
    closure[name] = directory;
    final dependencies = pubspec(directory)['dependencies'] as YamlMap?;
    pending.addAll(dependencies?.keys.cast<String>() ?? const []);
  }
  return closure;
}
