import 'package:package_config/package_config.dart';
import 'package:restage_codegen/src/restage_sdk_compatibility.dart';
import 'package:test/test.dart';

Package _restage(String root) => Package('restage', Uri.parse(root));

void main() {
  test('a hosted restage older than the minimum is refused', () {
    final problem = restageVersionIncompatibility(
      _restage('file:///home/dev/.pub-cache/hosted/pub.dev/restage-2.0.0/'),
    );

    expect(problem, contains('restage 2.1.0 or newer'));
    expect(problem, contains('resolves restage 2.0.0'));
  });

  test('a hosted restage at or above the minimum passes', () {
    for (final version in ['2.1.0', '2.3.1', '3.0.0']) {
      expect(
        restageVersionIncompatibility(
          _restage('file:///cache/hosted/pub.dev/restage-$version/'),
        ),
        isNull,
      );
    }
  });

  test('a path or workspace restage is not checked', () {
    expect(
      restageVersionIncompatibility(_restage('file:///repo/packages/restage/')),
      isNull,
    );
  });

  test('a package without restage is not checked', () {
    expect(restageVersionIncompatibility(null), isNull);
  });

  test('a hosted restage_core older than its minimum is refused', () {
    final problem = restageVersionIncompatibility(
      Package(
        'restage_core',
        Uri.parse('file:///cache/hosted/pub.dev/restage_core-2.0.0/'),
      ),
      minimum: kMinimumRestageCoreVersion,
    );

    expect(problem, contains('restage_core 2.1.0 or newer'));
    expect(problem, contains('dart pub upgrade restage_core'));
  });
}
