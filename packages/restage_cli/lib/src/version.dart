import 'dart:isolate';

/// The version of this command-line interface, as its pubspec states it.
const restageCliVersion = '0.1.0';

/// `restage <version>`, with the commit a git install resolved when its path
/// names one.
Future<String> restageVersionLine() async {
  Uri? lib;
  try {
    lib = await Isolate.resolvePackageUri(Uri.parse('package:restage_cli/'));
  } on Object {
    lib = null;
  }
  final commit = lib == null ? null : commitInPackagePath(lib.path);
  return commit == null
      ? 'restage $restageCliVersion'
      : 'restage $restageCliVersion (commit ${commit.substring(0, 12)})';
}

/// The commit a pub git checkout at [path] names, as in
/// `.pub-cache/git/restage-<commit>/packages/restage_cli/lib/`, or null.
String? commitInPackagePath(String path) =>
    RegExp(r'/git/[^/]+-([0-9a-f]{40})/').firstMatch(path)?.group(1);
