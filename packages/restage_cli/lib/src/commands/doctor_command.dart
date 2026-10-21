import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/api/discovery_api.dart';
import 'package:restage_cli/src/api/library_requirements_api.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/selector_syntax.dart';
import 'package:restage_cli/src/api/typed_error_renderer.dart';
import 'package:restage_cli/src/config/config_target_check.dart';
import 'package:restage_cli/src/config/restage_config.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/libraries/library_contract_check.dart';

/// A build flag Restage apps no longer need.
///
/// Generated registrations keep icons as compile-time constants, so icon tree
/// shaking works. Passing this flag only keeps every glyph in the app.
const _unneededBuildFlag = '--no-tree-shake-icons';

/// Relative paths (from the project root) of files that commonly carry a
/// build invocation.
const _buildConfigCandidates = <String>[
  'Makefile',
  'makefile',
  'GNUmakefile',
  'justfile',
  'Justfile',
  '.github/workflows',
  'fastlane/Fastfile',
  'ios/fastlane/Fastfile',
  'android/fastlane/Fastfile',
  'codemagic.yaml',
  'bitrise.yml',
  '.gitlab-ci.yml',
  'cloudbuild.yaml',
  'melos.yaml',
  'scripts',
  'tool',
];

/// File extensions worth scanning when we descend into a candidate
/// directory (e.g. `scripts/`, `.github/workflows`).
const _scannableExtensions = <String>{
  '.sh',
  '.bash',
  '.zsh',
  '.yaml',
  '.yml',
  '.dart',
  '.rb',
  '.ps1',
  '.bat',
  '.cmd',
  '.mk',
  '.gradle',
  '.kts',
};

/// Check the host project for common setup issues and print PASS or WARN.
///
/// Advisory only: it exits `0` either way.
class DoctorCommand extends Command<int> {
  /// Construct a doctor command bound to the given output sinks.
  DoctorCommand({
    required StringSink stdout,
    required StringSink stderr,
    FileCredentialStore? credentialStore,
    http.Client? httpClient,
  }) : _stdout = stdout,
       _stderr = stderr,
       _credentialStore = credentialStore,
       _httpClient = httpClient {
    argParser.addOption(
      'directory',
      abbr: 'C',
      defaultsTo: '.',
      help: 'Project root (defaults to the current directory).',
    );
  }

  final StringSink _stdout;
  final StringSink _stderr;
  final FileCredentialStore? _credentialStore;
  final http.Client? _httpClient;

  @override
  String get name => 'doctor';

  @override
  String get description =>
      'Check the project for common setup issues: a restage_config.yaml that '
      'names a project, app or environment that does not exist, a build '
      'command that turns off icon tree shaking, or a version in use this '
      "build's library contracts would stop rendering.";

  @override
  Future<int> run() async {
    final root = Directory(argResults!['directory'] as String).absolute;
    if (!root.existsSync()) {
      _stderr.writeln(
        'No directory at ${root.path}. Run `restage doctor` from a project '
        'root, or pass `--directory <path>`.',
      );
      return 1;
    }

    final evidence = _findFlagEvidence(root);

    _stdout.writeln('restage doctor');
    _stdout.writeln('');

    await _checkConfig(root);
    await _checkLibraries(root);

    if (evidence != null) {
      _stdout.writeln('WARN  Icon tree shaking is turned off');
      _stdout.writeln(
        '      ${p.relative(evidence, from: root.path)} passes '
        '$_unneededBuildFlag. Restage apps don\'t need it, and it keeps '
        'every icon glyph in your app. Remove it unless another dependency '
        'needs it.',
      );
    } else {
      _stdout.writeln('PASS  Icon tree shaking');
      _stdout.writeln(
        '      No build command found that passes $_unneededBuildFlag.',
      );
    }

    return 0;
  }

  /// Reports whether restage_config.yaml names things that exist.
  Future<void> _checkConfig(Directory root) async {
    void line(String status, String detail) {
      _stdout
        ..writeln('$status  Project config')
        ..writeln('      $detail');
    }

    final ({RestageConfig config, File source})? loaded;
    try {
      loaded = await loadRestageConfig(from: root);
    } on RestageConfigFormatException catch (error) {
      line('WARN', error.message);
      return;
    }
    if (loaded == null) {
      final syntax = currentSelectorSyntax;
      line(
        'WARN',
        'No restage_config.yaml. ${syntax.run} '
            '${syntax.command(initFollowUp)} to set one up.',
      );
      return;
    }
    final store = _credentialStore ?? FileCredentialStore.atDefaultLocation();
    final credential = await store.read();
    if (credential == null) {
      line('SKIP', 'Not checked against the server. ${notSignedInSentence()}');
      return;
    }
    RestageApi? api;
    try {
      api = RestageApi(
        endpoint: resolveApiEndpoint(
          config: loaded.config,
          credential: credential,
        ),
        httpClient: _httpClient,
        credential: credential,
      );
      final check = await checkConfigTarget(DiscoveryApi(api), loaded.config);
      if (check.problems.isEmpty) {
        line('PASS', 'The ${configTargetConfirmed(loaded.config)}.');
      } else {
        for (final problem in check.problems) {
          line('WARN', problem);
        }
      }
    } on EndpointConfigurationException catch (error) {
      line('SKIP', error.toString());
    } on InsecureEndpointException catch (error) {
      line('SKIP', error.toString());
    } on RestageApiException catch (error) {
      line('SKIP', renderApiError(error).message);
    } on SocketException catch (error) {
      line('SKIP', backendUnreachableMessage(api?.endpoint, error));
    } finally {
      if (_httpClient == null) api?.close();
    }
  }

  /// Warns about live versions this build's library contracts stop rendering.
  Future<void> _checkLibraries(Directory root) async {
    void line(String status, String detail) {
      _stdout
        ..writeln('$status  Library contracts')
        ..writeln('      $detail');
    }

    final Map<String, int> since;
    try {
      since = localCompatibleSince(await libraryContractRoot(root));
    } on FormatException catch (error) {
      line('WARN', error.message);
      return;
    }
    if (since.isEmpty) return;
    final ({RestageConfig config, File source})? loaded;
    try {
      loaded = await loadRestageConfig(from: root);
    } on RestageConfigFormatException {
      return;
    }
    if (loaded == null) return;
    final project = loaded.config.project;
    final app = loaded.config.app;
    if (project == null || app == null) {
      line(
        'SKIP',
        'Not checked against the server: restage_config.yaml names no '
            'project and app.',
      );
      return;
    }
    final store = _credentialStore ?? FileCredentialStore.atDefaultLocation();
    final credential = await store.read();
    if (credential == null) {
      line('SKIP', 'Not checked against the server. ${notSignedInSentence()}');
      return;
    }
    RestageApi? api;
    try {
      api = RestageApi(
        endpoint: resolveApiEndpoint(
          config: loaded.config,
          credential: credential,
        ),
        httpClient: _httpClient,
        credential: credential,
      );
      final live = await LibraryRequirementsApi(
        api,
      ).liveLibraryRequirements(project: project, app: app);
      final breaks = findLibraryBreaks(live: live, compatibleSince: since);
      if (breaks.isEmpty) {
        line('PASS', 'All versions in use render on this build.');
      }
      for (final item in breaks) {
        line('WARN', '${item.version.environment}: ${item.sentence}');
      }
    } on EndpointConfigurationException catch (error) {
      line('SKIP', error.toString());
    } on InsecureEndpointException catch (error) {
      line('SKIP', error.toString());
    } on RestageApiException catch (error) {
      line('SKIP', renderApiError(error).message);
    } on SocketException catch (error) {
      line('SKIP', backendUnreachableMessage(api?.endpoint, error));
    } finally {
      if (_httpClient == null) api?.close();
    }
  }

  /// Returns the first build-config file under [root] that mentions the flag.
  String? _findFlagEvidence(Directory root) {
    for (final candidate in _buildConfigCandidates) {
      final path = p.join(root.path, candidate);
      final asFile = File(path);
      if (asFile.existsSync()) {
        if (_fileMentionsFlag(asFile)) return asFile.path;
        continue;
      }
      final asDir = Directory(path);
      if (asDir.existsSync()) {
        final hit = _scanDirectory(asDir);
        if (hit != null) return hit;
      }
    }
    return null;
  }

  /// Scans text files under [dir], limited to [_scannableExtensions].
  String? _scanDirectory(Directory dir) {
    final List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(recursive: true, followLinks: false);
    } on FileSystemException {
      return null;
    }
    for (final entry in entries) {
      if (entry is! File) continue;
      final ext = p.extension(entry.path).toLowerCase();
      // Files with no extension (e.g. a CI shell step file) are scanned
      // too; extension-bearing files must be in the allow-list.
      if (ext.isNotEmpty && !_scannableExtensions.contains(ext)) continue;
      if (_fileMentionsFlag(entry)) return entry.path;
    }
    return null;
  }

  /// True when [file] reads as text and contains the flag.
  bool _fileMentionsFlag(File file) {
    try {
      return file.readAsStringSync().contains(_unneededBuildFlag);
    } on FileSystemException {
      return false;
    } on FormatException {
      // Binary content — not a build script we can read as text.
      return false;
    }
  }
}
