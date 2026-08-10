import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('tracked example README leads with minimal constructor authoring', () {
    final readme = File('example/README.md').readAsStringSync();
    final normalized = readme.replaceAll(RegExp(r'\s+'), ' ');

    expect(readme, contains("export 'widgets/acme_border.dart';"));
    expect(readme, contains('extends WidgetLibrary'));
    expect(readme, contains('@RestageLibrary('));
    expect(readme, contains('const restageCatalog = 0;'));
    expect(readme, isNot(contains('const _restageCatalog = 0;')));
    expect(readme, contains('/// Wraps a child in a colored border.'));
    expect(readme, contains('@RestageWidget()'));
    expect(readme, contains('required this.child'));
    expect(readme, contains('final Widget child;'));
    expect(
      readme,
      contains("@RestageProperty(defaultBrandToken: 'primary')"),
    );

    final widgetAnnotations = RegExp(
      r'@RestageWidget\((.*?)\)',
      dotAll: true,
    ).allMatches(readme).toList();
    expect(widgetAnnotations, hasLength(1));
    expect(widgetAnnotations.single.group(1)!.trim(), isEmpty);
    expect(RegExp(r'@RestageProperty\(').allMatches(readme), hasLength(1));
    expect(
      RegExp(r'@RestageProperty\([^)]*\)\s*final Widget child;', dotAll: true)
          .hasMatch(readme),
      isFalse,
    );
    expect(
      normalized,
      isNot(
        contains(
          'and its configurable properties with `@RestageProperty`',
        ),
      ),
    );
    expect(
      RegExp(
        r'Constructor-bound\s+inputs and Dart documentation are inferred',
      ).hasMatch(readme),
      isTrue,
    );
    expect(
      RegExp(r'`@RestageProperty` is optional\s+metadata').hasMatch(readme),
      isTrue,
    );
  });
}
