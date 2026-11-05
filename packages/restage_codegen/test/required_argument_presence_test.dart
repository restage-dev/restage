// A design must carry every required argument Flutter can't take as null.
import 'dart:io';

import 'package:build/build.dart';
import 'package:restage_codegen/builder.dart';
import 'package:restage_codegen/src/catalog_validator.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_shared/rfw_formats.dart' show parseLibraryFile;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

Catalog _catalog(String package) => decodeCatalog(
  File('../$package/lib/src/widget_catalog/catalog.json').readAsStringSync(),
);

void main() {
  // (library, design, refused)
  const cases = <(String, String, bool)>[
    ('cupertino', 'CupertinoDatePicker()', true),
    (
      'cupertino',
      'CupertinoDatePicker(onDateTimeChanged: event "d" {})',
      false,
    ),
    ('material', 'Switch(onChanged: event "s" {})', true),
    // `onPressed` is required but nullable: absence means null.
    ('material', 'IconButton(icon: Icon(iconCodepoint: 1))', false),
  ];
  for (final (library, design, refused) in cases) {
    test('${refused ? 'refuses' : 'accepts'} $design', () {
      final model = parseLibraryFile(
        'import restage.$library;\nwidget Screen = $design;',
        sourceIdentifier: 'test',
      );
      final issues = validateModelAgainstCatalog(
        model,
        _catalog('restage_$library'),
      );
      expect(
        issues.any((i) => i.code == IssueCode.missingRequiredSlot),
        refused,
        reason: issues.map((i) => i.message).join('\n'),
      );
    });
  }

  group('app code', () {
    const package = 'apps_examples';
    late TestBuilderResult result;

    String paywall(String name, String import, String body) =>
        '''
import 'package:flutter/$import.dart';
import 'package:restage/restage.dart';

part 'restage.generated/${name.toLowerCase()}.restage.g.dart';

@Paywall()
class $name extends StatelessWidget {
  const $name({super.key});

  @override
  Widget build(BuildContext context) => $body;
}
''';

    setUpAll(() async {
      final sources = {
        '$package|lib/paywalls/picker.dart': paywall(
          'Picker',
          'cupertino',
          'CupertinoDatePicker(onDateTimeChanged: (_) {})',
        ),
        '$package|lib/paywalls/overflow.dart': paywall(
          'Overflow',
          'widgets',
          'const DefaultTextStyle(style: TextStyle(overflow: '
              'TextOverflow.fade), overflow: TextOverflow.ellipsis, '
              "child: Text('x'))",
        ),
      };
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: package,
        includeFlutter: true,
      );
      for (final MapEntry(:key, :value) in sources.entries) {
        readerWriter.testing.writeString(AssetId.parse(key), value);
      }
      result = await testBuilders(
        [restageCodegenBuilder(BuilderOptions.empty)],
        sources,
        rootPackage: package,
        readerWriter: readerWriter,
        flattenOutput: true,
      );
    });

    String widget(String id) => result.readerWriter.testing
        .readString(AssetId(package, 'assets/paywalls/$id.rfwtxt'))
        .split('\n')
        .singleWhere((line) => line.startsWith('widget '));

    test('a no-op required callback and both overflows compile', () {
      expect(result.errors, isEmpty, reason: result.errors.join('\n'));
    });

    test('DefaultTextStyle keeps its own overflow apart from the style', () {
      expect(
        widget('overflow'),
        allOf(
          contains('overflow: "ellipsis"'),
          contains('styleOverflow: "fade"'),
        ),
      );
    });
  });
}
