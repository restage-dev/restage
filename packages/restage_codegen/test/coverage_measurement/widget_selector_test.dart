import 'dart:io';
import 'dart:isolate';

import 'package:restage_codegen/src/coverage_measurement/real_package_scanner.dart';
import 'package:test/test.dart';

/// Resolves the on-disk directory of the real example package via the running
/// isolate's package config (CWD-independent), exactly like the B3 self-test.
Future<String> _examplesPackageDir() async {
  final libUri = await Isolate.resolvePackageUri(
    Uri.parse('package:restage_example/main.dart'),
  );
  if (libUri == null) {
    throw StateError('Unable to resolve package:restage_example.');
  }
  // <pkg>/lib/main.dart -> <pkg>
  return File.fromUri(libUri).parent.parent.path;
}

void main() {
  test(
    'allFlutterWidgets selects a strict superset of @RestageWidget widgets, '
    'including private widgets',
    () async {
      final dir = await _examplesPackageDir();
      final catalog = await loadMergedCatalogFromDisk();

      // Default selection (unchanged): @RestageWidget-annotated widgets only.
      final annotated = await scanPackage(packagePath: dir, catalog: catalog);
      // All-widgets selection: every StatelessWidget/StatefulWidget subclass.
      final all = await scanPackage(
        packagePath: dir,
        catalog: catalog,
        widgetSelector: allFlutterWidgets,
      );

      final annotatedKeys = annotated.classifications.keys.toSet();
      final allKeys = all.classifications.keys.toSet();

      // Default selector measures the annotated custom-widget surface (the
      // exact census + names are value-asserted by real_package_scanner_test;
      // here we only need a non-empty annotated set to anchor the superset).
      expect(annotated.widgetCount, greaterThan(0));
      // All-widgets is a strict superset — apps/examples has many plain widget
      // classes (incl. private _-prefixed ones) beyond the annotated ones.
      expect(
        allKeys.containsAll(annotatedKeys),
        isTrue,
        reason: 'all-widgets selection must include every annotated widget',
      );
      expect(
        allKeys.length,
        greaterThan(annotatedKeys.length),
        reason: 'all-widgets selection must measure more than the 7 annotated',
      );
      // Idiom honesty: private widgets carry real build() idioms and are
      // measured (the chosen reading for idiom discovery).
      expect(
        allKeys.any((k) => k.split('#').last.startsWith('_')),
        isTrue,
        reason: 'private (_-prefixed) widgets must be included',
      );
    },
  );
}
