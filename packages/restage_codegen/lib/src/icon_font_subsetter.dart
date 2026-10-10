// ignore_for_file: public_member_api_docs

import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// The family Flutter's Material icons use.
const String kMaterialIconsFamily = 'MaterialIcons';

/// Thrown when an icon font cannot be subset.
final class IconFontSubsetException implements Exception {
  const IconFontSubsetException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Produces a subset of an icon font that covers exactly some code points.
abstract interface class IconFontSubsetter {
  /// The subset of [family]'s font, declared by [fontPackage] (the app when
  /// null), covering [codePoints]. Equal inputs give equal bytes.
  Uint8List subset({
    required String family,
    required String? fontPackage,
    required Set<int> codePoints,
  });

  /// The file extension of [family]'s source font, with its dot.
  String extension({required String family, required String? fontPackage});
}

/// Subsets with the `font-subset` tool from the Flutter SDK that runs the
/// build: Material icons from the SDK, other families from the `fonts:` of
/// the pubspec that declares them.
final class FlutterIconFontSubsetter implements IconFontSubsetter {
  FlutterIconFontSubsetter({
    String? flutterRoot,
    String? appRoot,
    String? Function(String package)? packageRoot,
  })  : _flutterRoot = flutterRoot,
        _appRoot = appRoot,
        _packageRoot = packageRoot ?? _resolvePackageRoot;

  /// One subsetter per build process, so each subset is computed once.
  static final FlutterIconFontSubsetter shared = FlutterIconFontSubsetter();

  final String? _flutterRoot;
  final String? _appRoot;
  final String? Function(String package) _packageRoot;
  final Map<String, Uint8List> _subsets = {};

  @override
  Uint8List subset({
    required String family,
    required String? fontPackage,
    required Set<int> codePoints,
  }) {
    final source = sourceFont(family: family, fontPackage: fontPackage);
    final sorted = codePoints.toList()..sort();
    final stat = source.statSync();
    final key = '${source.path}\u0000${stat.size}\u0000'
        '${stat.modified.microsecondsSinceEpoch}\u0000${sorted.join(' ')}';
    final cached = _subsets[key];
    if (cached != null) return Uint8List.fromList(cached);

    final tool = fontSubsetTool();
    final directory = Directory.systemTemp.createTempSync('restage_icons_');
    try {
      final output =
          p.join(directory.path, 'subset${p.extension(source.path)}');
      final result = _runWithInput(
        tool.path,
        [output, source.path],
        sorted.join(' '),
      );
      if (result.exitCode != 0) {
        throw IconFontSubsetException(
          'font-subset failed for the $family icon font '
                  '(exit ${result.exitCode}): ${result.stderr}'
              .trim(),
        );
      }
      final bytes = File(output).readAsBytesSync();
      _subsets[key] = bytes;
      return Uint8List.fromList(bytes);
    } finally {
      directory.deleteSync(recursive: true);
    }
  }

  @override
  String extension({required String family, required String? fontPackage}) =>
      p.extension(sourceFont(family: family, fontPackage: fontPackage).path);

  /// The Flutter SDK root: `FLUTTER_ROOT`, else the SDK whose Dart runs this.
  String flutterRoot() {
    final configured = _flutterRoot ?? Platform.environment['FLUTTER_ROOT'];
    if (configured != null && configured.isNotEmpty) return configured;
    // <root>/bin/cache/dart-sdk/bin/dart
    final executable = File(Platform.resolvedExecutable).absolute.path;
    final root = p.dirname(
      p.dirname(p.dirname(p.dirname(p.dirname(executable)))),
    );
    if (File(p.join(root, 'bin', 'flutter')).existsSync() ||
        File(p.join(root, 'bin', 'flutter.bat')).existsSync()) {
      return root;
    }
    throw const IconFontSubsetException(
      'Icon fonts are subset with the Flutter SDK, which was not found. '
      'Run the build with Flutter or set FLUTTER_ROOT.',
    );
  }

  /// The SDK's `font-subset` tool.
  File fontSubsetTool() {
    final host = switch (Abi.current()) {
      Abi.macosArm64 || Abi.macosX64 => 'darwin-x64',
      Abi.windowsX64 || Abi.windowsArm64 => 'windows-x64',
      Abi.linuxArm64 => 'linux-arm64',
      _ => 'linux-x64',
    };
    final name = Platform.isWindows ? 'font-subset.exe' : 'font-subset';
    final tool = File(
      p.join(flutterRoot(), 'bin', 'cache', 'artifacts', 'engine', host, name),
    );
    if (!tool.existsSync()) {
      throw IconFontSubsetException(
        'The Flutter font-subset tool is missing at ${tool.path}. '
        'Run `flutter precache` or `flutter doctor`.',
      );
    }
    return tool;
  }

  /// The full font [family] is subset from.
  File sourceFont({required String family, required String? fontPackage}) {
    if (fontPackage == null && family == kMaterialIconsFamily) {
      final font = File(
        p.join(
          flutterRoot(),
          'bin',
          'cache',
          'artifacts',
          'material_fonts',
          'MaterialIcons-Regular.otf',
        ),
      );
      if (!font.existsSync()) {
        throw IconFontSubsetException(
          'The Material icon font is missing at ${font.path}. '
          'Run `flutter precache`.',
        );
      }
      return font;
    }
    final owner = fontPackage ?? 'the app';
    final root = fontPackage == null
        ? (_appRoot ?? Directory.current.path)
        : _packageRoot(fontPackage);
    if (root == null) {
      throw IconFontSubsetException(
        'The $family icon font comes from package $fontPackage, which this '
        'build cannot resolve.',
      );
    }
    final asset = _declaredFontAsset(root, family);
    if (asset == null) {
      throw IconFontSubsetException(
        'The $family icon font is not declared under flutter: fonts: in the '
        'pubspec of $owner.',
      );
    }
    final font = File(p.join(root, asset));
    if (!font.existsSync()) {
      throw IconFontSubsetException(
        'The $family icon font of $owner is missing at ${font.path}.',
      );
    }
    return font;
  }
}

String? _declaredFontAsset(String packageRoot, String family) {
  final pubspec = File(p.join(packageRoot, 'pubspec.yaml'));
  if (!pubspec.existsSync()) return null;
  final yaml = loadYaml(pubspec.readAsStringSync());
  if (yaml is! YamlMap) return null;
  final flutter = yaml['flutter'];
  if (flutter is! YamlMap) return null;
  final fonts = flutter['fonts'];
  if (fonts is! YamlList) return null;
  for (final entry in fonts) {
    if (entry is! YamlMap || entry['family'] != family) continue;
    final files = entry['fonts'];
    if (files is! YamlList) continue;
    for (final file in files) {
      if (file is YamlMap && file['asset'] is String) {
        return file['asset'] as String;
      }
    }
  }
  return null;
}

String? _resolvePackageRoot(String package) {
  final lib = Isolate.resolvePackageUriSync(Uri.parse('package:$package/'));
  if (lib == null || lib.scheme != 'file') return null;
  return p.dirname(p.fromUri(lib));
}

ProcessResult _runWithInput(
  String executable,
  List<String> arguments,
  String input,
) {
  // Process.runSync has no stdin, so the code points go through a shell pipe.
  final inputFile = File(
    p.join(Directory.systemTemp.createTempSync('restage_cp_').path, 'in.txt'),
  )..writeAsStringSync('$input\n');
  try {
    if (Platform.isWindows) {
      final command = '"$executable" ${arguments.map((a) => '"$a"').join(' ')}'
          ' < "${inputFile.path}"';
      return Process.runSync('cmd', ['/c', command]);
    }
    return Process.runSync('/bin/sh', [
      '-c',
      r'"$0" "$1" "$2" < "$3"',
      executable,
      ...arguments,
      inputFile.path,
    ]);
  } finally {
    inputFile.parent.deleteSync(recursive: true);
  }
}
