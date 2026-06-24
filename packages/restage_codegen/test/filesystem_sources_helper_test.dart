import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('readerWriterWithFilesystemSources', () {
    test('preloads only the package sources fixture analysis needs', () async {
      final writer = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );

      final assets = writer.testing.assets.toList();
      final packages = assets.map((id) => id.package).toSet();

      expect(packages, contains('rfw_catalog_schema'));
      expect(packages, contains('restage'));
      expect(packages, contains('restage_shared'));
      expect(packages, contains('flutter'));
      expect(packages, isNot(contains('analyzer')));
      expect(packages, isNot(contains('build_runner')));
      expect(packages.length, lessThan(40));
      expect(
        assets.where((id) => id.path.startsWith('.dart_tool/')),
        isEmpty,
      );
    });

    test('can omit Flutter sources for Dart-only fixtures', () async {
      final writer = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
        includeFlutter: false,
      );

      final packages = writer.testing.assets.map((id) => id.package).toSet();

      expect(packages, contains('rfw_catalog_schema'));
      expect(packages, isNot(contains('flutter')));
    });
  });
}
