import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:restage_cli/src/config/restage_config.dart';
import 'package:restage_cli/src/init/pubspec_editor.dart'
    show
        AddDependenciesPlan,
        addDependencies,
        complexConstraintMarker,
        planAddDependencies;
import 'package:restage_cli/src/init/starter_paywall.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:path/path.dart' as p;

/// Default version constraints for the wired-in dependencies.
///
/// These pin against the currently-published shape of the SDK packages.
/// Once those packages are on pub.dev, bumping the constraints here is a
/// single-file change.
const Map<String, String> _defaultRuntimeDeps = {'restage': '^0.1.0'};
const Map<String, String> _defaultDevDeps = {
  'build_runner': '>=2.4.0 <3.0.0',
  'restage_codegen': '^0.1.0',
};

/// Bootstrap a Flutter project for Restage.
///
/// The wizard prompts for project, app, and (default) environment
/// slugs, then writes three artifacts:
///
///   1. `restage_config.yaml` at the project root.
///   2. A starter paywall under `lib/paywalls/`.
///   3. Edits to `pubspec.yaml` adding the SDK + codegen dependencies.
///
/// Each artifact has an opt-out flag (`--no-starter`, `--no-wire-deps`)
/// and the wizard can be skipped end-to-end with `--non-interactive` +
/// the per-value flags. `--dry-run` prints the planned changes without
/// writing.
///
/// Re-running is idempotent: existing artifacts are preserved (the
/// wizard prompts before overwriting; non-interactive mode keeps the
/// existing artifact).
class InitCommand extends Command<int> {
  /// Construct an init command.
  InitCommand({
    required StringSink stdout,
    required StringSink stderr,
    required Interactive interactive,
  }) : _stdout = stdout,
       _stderr = stderr,
       _interactive = interactive {
    argParser
      ..addOption(
        'directory',
        abbr: 'C',
        defaultsTo: '.',
        help: 'Project root (defaults to the current directory).',
      )
      ..addOption('project', help: 'Project slug (skips the prompt).')
      ..addOption('app', help: 'App slug (skips the prompt).')
      ..addOption('env', help: 'Default environment slug (skips the prompt).')
      ..addFlag(
        'starter',
        help: 'Write a starter paywall to `lib/paywalls/`.',
        defaultsTo: true,
      )
      ..addFlag(
        'wire-deps',
        help:
            'Add `restage` (dependencies) plus `restage_codegen` '
            'and `build_runner` (dev_dependencies) to pubspec.yaml.',
        defaultsTo: true,
      )
      ..addFlag(
        'dry-run',
        negatable: false,
        help: 'Print the planned changes without writing.',
      );
  }

  final StringSink _stdout;
  final StringSink _stderr;
  final Interactive _interactive;

  @override
  String get name => 'init';

  @override
  String get description =>
      'Bootstrap a Flutter project for Restage — writes config, a '
      'starter paywall, and pubspec wiring.';

  @override
  Future<int> run() async {
    final results = argResults!;
    final root = Directory(results['directory'] as String).absolute;
    final pubspec = File(p.join(root.path, 'pubspec.yaml'));
    if (!pubspec.existsSync()) {
      _stderr.writeln(
        'No `pubspec.yaml` at ${root.path}. Run `restage init` from a '
        'Flutter project root, or pass `--directory <path>`.',
      );
      return 1;
    }

    final String project;
    final String app;
    final String environment;
    try {
      project = await _resolveSlug(results, 'project', 'Project slug?');
      app = await _resolveSlug(results, 'app', 'App slug?');
      environment = await _resolveSlug(
        results,
        'env',
        'Default environment slug?',
      );
    } on NonInteractiveDefaultMissing catch (e) {
      _stderr.writeln(
        'Required: --${e.flagName ?? "value"} <slug>. Pass the value on '
        'the command line or drop --non-interactive to use the wizard.',
      );
      return 1;
    }

    final config = RestageConfig(
      project: project,
      app: app,
      defaultEnvironment: environment,
    );

    final wantsStarter = results['starter'] as bool;
    final wantsWireDeps = results['wire-deps'] as bool;
    final dryRun = results['dry-run'] as bool;

    // Read the pubspec once; both the dry-run plan and the apply path
    // consume the same source.
    final pubspecSource = wantsWireDeps ? await pubspec.readAsString() : '';
    final pubspecPlan = wantsWireDeps
        ? planAddDependencies(
            pubspecSource,
            deps: _defaultRuntimeDeps,
            devDeps: _defaultDevDeps,
          )
        : null;

    final configFile = File(p.join(root.path, 'restage_config.yaml'));
    final starterFile = File(
      p.join(root.path, 'lib', 'paywalls', 'starter.dart'),
    );

    _printPlan(
      configFile: configFile,
      wantsStarter: wantsStarter,
      starterFile: starterFile,
      pubspecPlan: pubspecPlan,
    );

    if (dryRun) return 0;

    // Apply.
    if (configFile.existsSync()) {
      _stdout.writeln(
        'Kept existing restage_config.yaml (delete it to regenerate).',
      );
    } else {
      await writeRestageConfig(configFile, config);
      _stdout.writeln('Wrote restage_config.yaml.');
    }

    if (wantsStarter) {
      if (starterFile.existsSync()) {
        _stdout.writeln('Kept existing lib/paywalls/starter.dart.');
      } else {
        await starterFile.parent.create(recursive: true);
        await starterFile.writeAsString(starterPaywallSource('starter'));
        _stdout.writeln('Wrote lib/paywalls/starter.dart.');
      }
    }

    if (wantsWireDeps && pubspecPlan != null && !pubspecPlan.isNoOp) {
      final result = addDependencies(
        pubspecSource,
        deps: _defaultRuntimeDeps,
        devDeps: _defaultDevDeps,
      );
      await pubspec.writeAsString(result.source);
      if (result.added.isNotEmpty) {
        _stdout.writeln(
          'Updated pubspec.yaml — added: ${result.added.join(', ')}.',
        );
      }
      if (result.kept.isNotEmpty) {
        _stdout.writeln(
          'Kept existing pubspec entries: ${result.kept.join(', ')}.',
        );
      }
    } else if (wantsWireDeps) {
      _stdout.writeln('Pubspec dependencies already wired.');
    }

    _stdout
      ..writeln()
      ..writeln(
        'Next: run `dart pub get && dart run build_runner build`, then '
        '`restage paywall publish starter` to push the starter to the '
        '`$environment` environment.',
      );
    return 0;
  }

  Future<String> _resolveSlug(
    ArgResults results,
    String optionName,
    String prompt,
  ) async {
    final flag = results[optionName] as String?;
    if (flag != null && flag.isNotEmpty) return flag;
    try {
      return await _interactive.prompt(prompt);
    } on NonInteractiveDefaultMissing catch (e) {
      // Re-throw with the flag name attached so the caller can render a
      // precise `required: --<flag>` message.
      throw NonInteractiveDefaultMissing(e.question, flagName: optionName);
    }
  }

  void _printPlan({
    required File configFile,
    required bool wantsStarter,
    required File starterFile,
    required AddDependenciesPlan? pubspecPlan,
  }) {
    _stdout.writeln('Planned changes:');
    _stdout.writeln(
      '  ${configFile.existsSync() ? 'keep' : 'create'} ${configFile.path} '
      '(restage_config.yaml)',
    );
    if (wantsStarter) {
      _stdout.writeln(
        '  ${starterFile.existsSync() ? 'keep' : 'create'} ${starterFile.path}',
      );
    }
    if (pubspecPlan != null && !pubspecPlan.isNoOp) {
      _stdout.writeln('  update pubspec.yaml:');
      for (final entry in pubspecPlan.dependenciesToAdd.entries) {
        _stdout.writeln('    dependencies: + ${entry.key}: ${entry.value}');
      }
      for (final entry in pubspecPlan.dependenciesToKeep.entries) {
        _stdout.writeln(
          '    dependencies: = ${entry.key}: '
          '${_renderConstraint(entry.value)} (kept)',
        );
      }
      for (final entry in pubspecPlan.devDependenciesToAdd.entries) {
        _stdout.writeln('    dev_dependencies: + ${entry.key}: ${entry.value}');
      }
      for (final entry in pubspecPlan.devDependenciesToKeep.entries) {
        _stdout.writeln(
          '    dev_dependencies: = ${entry.key}: '
          '${_renderConstraint(entry.value)} (kept)',
        );
      }
    } else if (pubspecPlan != null) {
      _stdout.writeln('  pubspec.yaml: already wired (no-op)');
    }
    _stdout.writeln();
  }

  /// Render the right-hand side of a dependency entry, replacing the
  /// sentinel used for non-string constraints with a human-readable
  /// pointer.
  String _renderConstraint(String value) =>
      value == complexConstraintMarker ? '(see pubspec)' : value;
}
