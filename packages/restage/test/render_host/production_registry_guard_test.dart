import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production SDK registries contain no preview marker library', () {
    final root = _workspaceRoot();
    final files = <File>[
      for (final relative in const <String>[
        'packages/restage/lib/src/runtime',
        'packages/restage_core/lib',
        'packages/restage_material/lib',
        'packages/restage_cupertino/lib',
      ])
        ...Directory('${root.path}/$relative')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart')),
    ];

    for (final file in files) {
      final source = file.readAsStringSync();
      expect(
        source,
        isNot(contains('buildMarkerWidgetLibrary')),
        reason: '${file.path} must not register the preview marker library',
      );
      expect(
        source,
        isNot(contains('__restage_internal_geometry_marker_v1__')),
        reason: '${file.path} must not register the preview constructor',
      );
    }
  });
}

Directory _workspaceRoot() {
  var current = Directory.current.absolute;
  while (true) {
    if (File('${current.path}/pubspec.yaml').existsSync() &&
        Directory('${current.path}/packages/restage').existsSync()) {
      return current;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError('Could not locate the workspace root.');
    }
    current = parent;
  }
}
