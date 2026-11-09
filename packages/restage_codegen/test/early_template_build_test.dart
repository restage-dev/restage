import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

// An app builds offline without a key, and with one the native template and
// the generated registration carry the same key and service URL.
void main() {
  test(
    'builds offline without a key and bakes a configured key',
    () async {
      final packages = p.normalize(p.join(Directory.current.path, '..'));
      final root = await Directory.systemTemp.createTemp('early_template_');
      addTearDown(() => root.delete(recursive: true));
      final overrides = _workspaceClosure(
        p.normalize(p.join(packages, '..')),
        const ['restage', 'restage_codegen'],
      );
      final app = p.join(root.path, 'app');
      _write(app, 'pubspec.yaml', '''
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
  restage_codegen:
    path: ${p.join(packages, 'restage_codegen')}
dependency_overrides:
${[for (final MapEntry(key: name, value: path) in overrides.entries) '  $name:\n    path: $path'].join('\n')}
''');
      _write(app, 'lib/paywalls/offer.dart', '''
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
      Directory(p.join(app, 'android/app')).createSync(recursive: true);
      Directory(p.join(app, 'ios/Runner')).createSync(recursive: true);
      final iosTemplate = File(p.join(app, 'ios/Runner/restage_early.json'));
      final template = File(
        p.join(app, 'android/app/src/main/assets/restage_early.json'),
      );
      final factories = File(p.join(app, 'lib/user_factories.g.dart'));

      final get = await Process.run('flutter', [
        'pub',
        'get',
        '--offline',
      ], workingDirectory: app);
      expect(get.exitCode, 0, reason: '${get.stdout}\n${get.stderr}');

      final offline = await _build(app);
      expect(offline.exitCode, 0, reason: _output(offline));
      expect(
        _output(offline),
        contains(
          "The first-launch request isn't built in: no publishable key. "
          'Try `restage init --sdk-key rs_pk_...`.',
        ),
      );
      expect(template.existsSync(), isFalse);
      expect(iosTemplate.existsSync(), isFalse);
      expect(factories.readAsStringSync(), isNot(contains('_restageApiKey')));

      // The old builder's options are reported, not read.
      _write(app, 'build.yaml', r'''
targets:
  $default:
    builders:
      restage_codegen:restage_early_template:
        options:
          api_key: rs_pk_sandbox_dev_old
          base_url: https://old.example.com
''');
      final moved = await _build(app);
      expect(moved.exitCode, 0, reason: _output(moved));
      expect(
        _output(moved),
        contains(
          'build.yaml sets api_key, base_url under '
          'restage_codegen:restage_early_template, which the build no longer '
          'reads. Try moving them to the restage_codegen:user_factories '
          'options, or run `restage init`.',
        ),
      );
      expect(template.existsSync(), isFalse);

      // Keyed, with the URL as a sign-in stores it and pubspec not yet listing
      // the iOS asset.
      _write(app, 'build.yaml', r'''
targets:
  $default:
    builders:
      restage_codegen:user_factories:
        options:
          api_key: rs_pk_sandbox_dev_build
          base_url: https://api.example.com/
          channel: beta
''');
      final keyed = await _build(app);
      expect(keyed.exitCode, 0, reason: _output(keyed));
      expect(_output(keyed), isNot(contains("isn't built in")));
      expect(
        _output(keyed),
        contains(
          'iOS sends the first-launch request only when pubspec.yaml lists '
          '`ios/Runner/restage_early.json` under `flutter: assets:`.',
        ),
      );
      final generated = factories.readAsStringSync();
      expect(
        generated,
        contains("const String _restageApiKey = 'rs_pk_sandbox_dev_build';"),
      );
      expect(
        generated,
        contains("const String _restageBaseUrl = 'https://api.example.com';"),
      );
      expect(generated, contains("const String? _restageChannel = 'beta';"));
      for (final file in [template, iosTemplate]) {
        final json =
            jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
        expect(
          json['url'],
          'https://api.example.com/sdk/v1/placements/resolve',
        );
        expect(json['authorization'], 'Bearer rs_pk_sandbox_dev_build');
        expect((json['builtIns']! as Map)['channel'], 'beta');
      }

      // Listed as an asset with no key, the iOS file stays as an empty one.
      final pubspec = File(p.join(app, 'pubspec.yaml'));
      pubspec.writeAsStringSync(
        '${pubspec.readAsStringSync()}flutter:\n'
        '  assets:\n    - ios/Runner/restage_early.json\n',
      );
      File(p.join(app, 'build.yaml')).deleteSync();
      final listed = await _build(app);
      expect(listed.exitCode, 0, reason: _output(listed));
      expect(iosTemplate.readAsStringSync(), '{}\n');
      expect(template.existsSync(), isFalse);

      // Target sources without pubspec.yaml: the listing is read from the
      // package root, so no false warning and the placeholder stays.
      const sources = '''
targets:
  \$default:
    sources:
      - lib/**
      - \$package\$
      - .restage/**
      - android/**
      - ios/**
    builders:
''';
      _write(app, 'build.yaml', '''$sources
      restage_codegen:user_factories:
        options:
          api_key: rs_pk_sandbox_dev_build
          base_url: https://api.example.com
''');
      final narrowKeyed = await _build(app);
      expect(narrowKeyed.exitCode, 0, reason: _output(narrowKeyed));
      expect(_output(narrowKeyed), isNot(contains('iOS sends')));
      expect(iosTemplate.readAsStringSync(), contains('"url"'));
      _write(app, 'build.yaml', sources.replaceFirst('    builders:\n', ''));
      final narrowOffline = await _build(app);
      expect(narrowOffline.exitCode, 0, reason: _output(narrowOffline));
      expect(iosTemplate.readAsStringSync(), '{}\n');
    },
  );
}

Future<ProcessResult> _build(String app) => Process.run('dart', [
  'run',
  'build_runner',
  'build',
], workingDirectory: app);

String _output(ProcessResult result) => '${result.stdout}\n${result.stderr}';

void _write(String root, String path, String contents) =>
    File(p.join(root, path))
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
