import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

/// Signature for locating the desktop preview binary. Returns the
/// absolute path or null when no binary is installed.
typedef PreviewBinaryLocator =
    String? Function({Map<String, String>? environment, bool? isWindows});

/// Signature for launching the preview binary against [blobPath].
///
/// Implementations spawn the binary detached so the wrapper can exit
/// while the preview window stays open. The default implementation
/// uses [Process.start] with a detached mode and an extended
/// environment containing `RESTAGE_PREVIEW_BLOB=<blobPath>`.
typedef PreviewLauncher =
    Future<int> Function({required String binary, required String blobPath});

/// Launch the desktop preview application against a compiled `.rfw`.
///
/// Discovery is delegated to [PreviewBinaryLocator] (defaults to the
/// PATH-aware locator in `binary_discovery.dart`); the launch itself is
/// delegated to [PreviewLauncher] (defaults to a detached
/// [Process.start] with the blob path forwarded as an environment
/// variable).
class PreviewCommand extends Command<int> {
  /// Construct a preview command.
  PreviewCommand({
    required StringSink stdout,
    required StringSink stderr,
    required PreviewBinaryLocator locator,
    required PreviewLauncher launcher,
  }) : _stdout = stdout,
       _stderr = stderr,
       _locator = locator,
       _launcher = launcher;

  final StringSink _stdout;
  final StringSink _stderr;
  final PreviewBinaryLocator _locator;
  final PreviewLauncher _launcher;

  @override
  String get name => 'preview';

  @override
  String get description =>
      'Launch the desktop preview application against a compiled '
      '`.rfw` paywall.';

  // Hidden from `--help` until the desktop preview binary is distributed: this
  // command locates the binary but does not fetch it, so listing it before the
  // binary is obtainable would surface a dead-end. It still runs for anyone who
  // has `restage-preview` installed. Flip to `false` once the binary ships.
  @override
  bool get hidden => true;

  @override
  Future<int> run() async {
    final rest = argResults?.rest ?? const <String>[];
    if (rest.isEmpty) {
      _stderr.writeln(
        'Missing positional argument: <path>. Run `restage preview '
        '<path-to-.rfw>`.',
      );
      return 1;
    }
    if (rest.length > 1) {
      _stderr.writeln(
        'Too many positional arguments. Expected exactly one '
        '<path>.',
      );
      return 1;
    }

    final blobPath = p.absolute(rest.first);
    if (!File(blobPath).existsSync()) {
      _stderr.writeln('No compiled paywall at $blobPath.');
      return 1;
    }

    final binary = _locator();
    if (binary == null) {
      _stderr
        ..writeln('The desktop preview app is not available yet.')
        ..writeln(
          'To preview a compiled .rfw on your machine now, render it in a '
          'Flutter app with the SDK: add a surface widget (e.g. RestagePaywall) '
          'with an AssetVariantResolver and `flutter run`. The examples show a '
          'ready-to-copy setup.',
        )
        ..writeln(
          '(If you already have the restage-preview binary: put it on PATH or '
          'at ~/.restage/bin/restage-preview, or set RESTAGE_PREVIEW_BIN.)',
        );
      return 1;
    }

    _stdout.writeln('Launching preview against ${p.relative(blobPath)}...');
    return _launcher(binary: binary, blobPath: blobPath);
  }
}
