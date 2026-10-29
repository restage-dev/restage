import 'package:restage_cli/src/init/android_manifest_editor.dart';
import 'package:test/test.dart';

const _permission =
    '<uses-permission android:name="android.permission.INTERNET"/>';

const _template = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <application android:label="app">
    </application>
</manifest>
''';

void main() {
  test('adds the permission once, as the first child, keeping the rest', () {
    final updated = addAndroidInternetPermission(_template)!;
    expect(
      updated,
      _template.replaceFirst(
        'res/android">\n',
        'res/android">\n    $_permission\n',
      ),
    );
    expect(androidManifestAllowsInternet(updated), isTrue);
    expect(addAndroidInternetPermission(updated), isNull);
  });

  for (final (name, source, expected) in <(String, String, String?)>[
    (
      'any attribute order and quotes count as declared',
      "<manifest>\n  <uses-permission android:maxSdkVersion='99'\n"
          "    android:name='android.permission.INTERNET' />\n</manifest>",
      null,
    ),
    (
      'a commented-out permission does not count',
      '<manifest>\n  <!-- $_permission -->\n</manifest>',
      '<manifest>\n  $_permission\n  <!-- $_permission -->\n</manifest>',
    ),
    (
      'a multi-line open tag keeps its line endings and indent',
      '<manifest xmlns:android="x"\r\n  package="a.b">\r\n  <application/>\r\n'
          '</manifest>\r\n',
      '<manifest xmlns:android="x"\r\n  package="a.b">\r\n  $_permission\r\n'
          '  <application/>\r\n</manifest>\r\n',
    ),
    (
      'a permission marked for removal does not count',
      '<manifest xmlns:tools="t">\n  <uses-permission '
          'android:name="android.permission.INTERNET" tools:node="remove"/>\n'
          '</manifest>',
      '<manifest xmlns:tools="t">\n  $_permission\n  <uses-permission '
          'android:name="android.permission.INTERNET" tools:node="remove"/>\n'
          '</manifest>',
    ),
    (
      'a > inside an attribute value stays inside it',
      '<manifest android:versionName="1>2">\n  <application/>\n</manifest>',
      '<manifest android:versionName="1>2">\n  $_permission\n'
          '  <application/>\n</manifest>',
    ),
    ('a manifest that does not parse is left alone', '<manifest', null),
    ('a self-closing manifest is left alone', '<manifest/>', null),
    ('a file without a manifest is left alone', '<resources/>', null),
  ]) {
    test(name, () => expect(addAndroidInternetPermission(source), expected));
  }
}
