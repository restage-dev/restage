import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

// A surface whose source another builder generates must compile: the
// compiler's catalog read builds other packages' catalogs lazily, and that must
// not hide the generated source from the resolver.
void main() {
  test('compiles a surface whose source an earlier builder generates',
      () async {
    final packages = p.normalize(p.join(Directory.current.path, '..'));
    final root = await Directory.systemTemp.createTemp('generated_surface_');
    addTearDown(() => root.delete(recursive: true));

    _write(root, 'generator/pubspec.yaml', '''
name: generator
environment:
  sdk: ^3.9.0
dependencies:
  build: any
''');
    _write(root, 'generator/build.yaml', '''
builders:
  copy:
    import: 'package:generator/builder.dart'
    builder_factories: ['copyBuilder']
    build_extensions: {'.surface': ['.dart']}
    auto_apply: root_package
    build_to: source
    runs_before: ['restage_codegen:restage_source_roster']
''');
    _write(root, 'generator/lib/builder.dart', '''
import 'package:build/build.dart';

Builder copyBuilder(BuilderOptions options) => _Copy();

class _Copy implements Builder {
  @override
  final buildExtensions = const {
    '.surface': ['.dart'],
  };

  @override
  Future<void> build(BuildStep buildStep) async => buildStep.writeAsString(
        buildStep.inputId.changeExtension('.dart'),
        await buildStep.readAsString(buildStep.inputId),
      );
}
''');

    final overrides = _workspaceClosure(
      p.normalize(p.join(packages, '..')),
      const ['restage', 'restage_codegen'],
    );
    _write(root, 'app/pubspec.yaml', '''
name: app
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
  generator:
    path: ../generator
  restage_codegen:
    path: ${p.join(packages, 'restage_codegen')}
dependency_overrides:
${[
      for (final MapEntry(key: name, value: path) in overrides.entries)
        '  $name:\n    path: $path'
    ].join('\n')}
''');
    _write(root, 'app/lib/offer.surface', '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/offer.restage.g.dart';

@Paywall()
class OfferPaywall extends StatelessWidget {
  const OfferPaywall({super.key});

  @override
  Widget build(BuildContext context) => const Text('Welcome');
}
''');

    final app = p.join(root.path, 'app');
    final get = await Process.run(
      'flutter',
      ['pub', 'get', '--offline'],
      workingDirectory: app,
    );
    expect(get.exitCode, 0, reason: '${get.stdout}\n${get.stderr}');
    final build = await Process.run(
      'dart',
      ['run', 'build_runner', 'build'],
      workingDirectory: app,
    );
    expect(build.exitCode, 0, reason: '${build.stdout}\n${build.stderr}');
    expect(
      File(p.join(app, 'lib/restage.generated/offer.restage.g.dart'))
          .existsSync(),
      isTrue,
    );
  });
}

void _write(Directory root, String path, String contents) =>
    File(p.join(root.path, path))
      ..createSync(recursive: true)
      ..writeAsStringSync(contents);

/// The workspace members [roots] reach through `dependencies`, by name, each
/// with its directory, read from the root pubspec's `workspace:` list.
Map<String, String> _workspaceClosure(String repoRoot, List<String> roots) {
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
