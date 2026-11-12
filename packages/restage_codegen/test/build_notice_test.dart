import 'dart:io';

import 'package:restage_codegen/src/build_notice.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('build_notice'));
  tearDown(() => root.deleteSync(recursive: true));

  test('a notice shows once, and again only when it changes', () {
    final uri = root.uri;
    expect(isNewBuildNotice(uri, 'summary', 'all 136 widgets'), isTrue);
    expect(isNewBuildNotice(uri, 'summary', 'all 136 widgets'), isFalse);
    expect(isNewBuildNotice(uri, 'summary', 'all 137 widgets'), isTrue);
    expect(isNewBuildNotice(uri, 'other', 'all 137 widgets'), isTrue);
  });

  test(
    'a later build process does not show the notice the last one showed',
    () {
      File.fromUri(root.uri.resolve('.dart_tool/restage/notices/summary'))
        ..createSync(recursive: true)
        ..writeAsStringSync('derived');
      expect(isNewBuildNotice(root.uri, 'summary', 'derived'), isFalse);
      expect(isNewBuildNotice(root.uri, 'summary', 'whole'), isTrue);
    },
  );

  test('without a package root every notice shows', () {
    expect(isNewBuildNotice(null, 'summary', 'same'), isTrue);
    expect(isNewBuildNotice(null, 'summary', 'same'), isTrue);
  });
}
