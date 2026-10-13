/// Derives a pinned render-bundle engine set from an installed Flutter SDK.
///
/// Run it after the pinned Flutter version moves, then append the printed
/// entry beside the others in `render_bundle_engine_set.dart` and add it to
/// `renderBundleEngineSets`:
///
/// ```sh
/// dart run tool/derive_render_bundle_engine_set.dart [--sdk <path>]
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:restage_shared/restage_shared.dart';

/// Files under the SDK's engine directory that no bundle ever fetches.
const engineSourceMapSuffix = '.symbols';

/// Where the SDK keeps the engine files a web build copies into a bundle.
const engineSdkDirectory = 'bin/cache/flutter_web_sdk/canvaskit';

const _versionFile = 'bin/cache/flutter.version.json';

/// Reads the engine set the SDK at [sdkRoot] produces.
///
/// The set is exactly the SDK's engine directory with its source maps left
/// out, which is what a web build copies into a bundle.
RenderBundleEngineSet deriveRenderBundleEngineSet(
  Directory sdkRoot, {
  String? flutterVersion,
}) {
  final root = _normalize(sdkRoot.path);
  final engineDirectory = Directory('$root/$engineSdkDirectory');
  if (!engineDirectory.existsSync()) {
    throw FileSystemException('No engine directory.', engineDirectory.path);
  }
  final prefix = _normalize(engineDirectory.path);
  final files = <RenderBundleEngineFile>[];
  for (final entity in engineDirectory.listSync(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is! File) continue;
    if (entity.path.endsWith(engineSourceMapSuffix)) continue;
    final bytes = entity.readAsBytesSync();
    files.add(
      RenderBundleEngineFile(
        path: _normalize(entity.path).substring(prefix.length + 1),
        contentHash: 'sha256:${crypto.sha256.convert(bytes)}',
        byteLength: bytes.length,
      ),
    );
  }
  files.sort((left, right) => left.path.compareTo(right.path));
  return RenderBundleEngineSet(
    flutterVersion: flutterVersion ?? readFlutterVersion(sdkRoot),
    files: files,
  );
}

/// Reads the framework version the SDK at [sdkRoot] reports.
String readFlutterVersion(Directory sdkRoot) {
  final file = File('${_normalize(sdkRoot.path)}/$_versionFile');
  if (!file.existsSync()) {
    throw FileSystemException('No version file.', file.path);
  }
  final document = jsonDecode(file.readAsStringSync());
  if (document is! Map<String, Object?> ||
      document['frameworkVersion'] is! String) {
    throw FormatException('No framework version.', file.path);
  }
  return document['frameworkVersion']! as String;
}

/// Locates an installed SDK, or returns `null` when none is reachable.
///
/// Checks `FLUTTER_ROOT` first and then the `flutter` executable on `PATH`,
/// so a machine holding several SDKs resolves the one in use.
Directory? findFlutterSdkRoot() {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null && root.isNotEmpty && Directory(root).existsSync()) {
    return Directory(root);
  }
  final path = Platform.environment['PATH'];
  if (path == null) return null;
  for (final directory in path.split(Platform.isWindows ? ';' : ':')) {
    if (directory.isEmpty) continue;
    final candidate = File('${_normalize(directory)}/flutter');
    if (!candidate.existsSync()) continue;
    return File(candidate.resolveSymbolicLinksSync()).parent.parent;
  }
  return null;
}

String _normalize(String path) {
  final forward = path.replaceAll(r'\', '/');
  return forward.endsWith('/')
      ? forward.substring(0, forward.length - 1)
      : forward;
}

/// Prints the entry to append and the identifier it will serve under.
void main(List<String> arguments) {
  String? sdkPath;
  String? version;
  for (var index = 0; index < arguments.length; index++) {
    switch (arguments[index]) {
      case '--sdk':
        sdkPath = index + 1 < arguments.length ? arguments[++index] : null;
      case '--flutter-version':
        version = index + 1 < arguments.length ? arguments[++index] : null;
      default:
        stderr.writeln('Unknown argument: ${arguments[index]}');
        exitCode = 64;
        return;
    }
  }
  final sdkRoot = sdkPath == null ? findFlutterSdkRoot() : Directory(sdkPath);
  if (sdkRoot == null || !sdkRoot.existsSync()) {
    stderr.writeln('No Flutter SDK found. Pass --sdk <path>.');
    exitCode = 66;
    return;
  }

  final set = deriveRenderBundleEngineSet(sdkRoot, flutterVersion: version);
  final name = '_flutter${set.flutterVersion.replaceAll('.', '')}';
  final buffer = StringBuffer()
    ..writeln('final $name = RenderBundleEngineSet(')
    ..writeln("  flutterVersion: '${set.flutterVersion}',")
    ..writeln('  files: <RenderBundleEngineFile>[');
  for (final file in set.files) {
    buffer
      ..writeln('    _file(')
      ..writeln("      '${file.path}',")
      ..writeln("      '${file.contentHash.substring('sha256:'.length)}',")
      ..writeln('      ${file.byteLength},')
      ..writeln('    ),');
  }
  buffer
    ..writeln('  ],')
    ..writeln(');');
  stdout
    ..write(buffer)
    ..writeln()
    ..writeln(
      '// Flutter ${set.flutterVersion}: ${set.files.length} files, '
      '${set.byteLength} bytes',
    )
    ..writeln('// engine set id: ${set.id}');
}
