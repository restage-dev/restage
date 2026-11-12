import 'dart:io';

final Map<String, String> _shown = {};

/// Whether [text] is new for [key] in the package at [root]: not shown yet in
/// this build process, and not what the last build of the package showed.
/// Records it as shown. Without a package root every notice is new.
bool isNewBuildNotice(Uri? root, String key, String text) {
  if (root == null) return true;
  final file = File.fromUri(root.resolve('.dart_tool/restage/notices/$key'));
  if (_shown[file.path] == text) return false;
  _shown[file.path] = text;
  try {
    if (file.existsSync() && file.readAsStringSync() == text) return false;
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(text);
  } on FileSystemException {
    // A notice shown twice is better than one never shown.
  }
  return true;
}
