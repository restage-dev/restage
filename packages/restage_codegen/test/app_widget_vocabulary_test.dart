import 'dart:convert';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:build/build.dart';
import 'package:restage_codegen/src/app_widget_vocabulary.dart';
import 'package:restage_shared/restage_shared.dart' show WidgetVocabulary;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// The app library every fixture is written to. Flutter-importing sources need
/// a root package that carries Flutter, hence `apps_examples`.
const String _fixtureId = 'apps_examples|lib/app_vocabulary_fixture.dart';

/// Resolves [source] as an app library and hands the result to [derive].
Future<T> _withResolvedFixture<T>(
  String source,
  T Function(ResolvedLibraryResult library) derive,
) =>
    resolveWorkspaceSources(
      {_fixtureId: source},
      (resolver) async {
        final library = await resolver.libraryFor(AssetId.parse(_fixtureId));
        final resolved =
            await library.session.getResolvedLibraryByElement(library);
        if (resolved is! ResolvedLibraryResult) {
          throw StateError('The app vocabulary fixture did not resolve.');
        }
        return derive(resolved);
      },
      resolverFor: _fixtureId,
      rootPackage: 'apps_examples',
    );

Future<WidgetVocabulary> _vocabularyOf(String source, Catalog catalog) =>
    _withResolvedFixture(
      source,
      (library) => deriveAppWidgetVocabulary([library], catalog),
    );

void main() {
  const textType = 'package:flutter/src/widgets/text.dart#Text';
  const columnType = 'package:flutter/src/widgets/basic.dart#Column';

  // Two built-ins keyed by the framework identity an app really constructs.
  final coreCatalog = catalogWith([
    entry(
      name: 'Text',
      properties: [prop('text', PropertyType.string, required: true)],
      flutterType: textType,
    ),
    entry(
      name: 'Column',
      childrenSlot: ChildrenSlot.list,
      properties: [prop('children', PropertyType.widgetList)],
      flutterType: columnType,
    ),
  ]);

  // A dozen real entries key on a named constructor and carry no bare-class
  // entry at all, which is the shape these two mirror.
  const networkImageType =
      'package:flutter/src/widgets/image.dart#Image.network';
  const assetImageType = 'package:flutter/src/widgets/image.dart#Image.asset';
  final imageCatalog = catalogWith([
    entry(name: 'Image', properties: const [], flutterType: networkImageType),
    entry(
      name: 'ImageAsset',
      properties: const [],
      flutterType: assetImageType,
    ),
  ]);

  test('built-in disclosure count excludes custom catalog entries', () {
    final catalog = catalogWith([
      for (final library in WidgetLibrary.builtInLibraries)
        entry(
          name: 'Builtin',
          properties: const [],
          library: library,
        ),
      entry(
        name: 'Custom',
        properties: const [],
        library: const WidgetLibrary.custom('acme.widgets'),
      ),
    ]);
    final derivation = deriveAppVocabulary(const [], catalog);

    expect(derivation.builtInWidgetCount, 3);
    expect(derivation.references.widgetNames, isEmpty);
    expect(derivation.vocabulary.widgetNames, isEmpty);
  });

  group('deriveAppWidgetVocabulary — widgets', () {
    test('names the catalog widgets the app constructs', () async {
      const source = '''
        import 'package:flutter/material.dart';

        Widget layout() => Column(children: const [Text('a'), Text('b')]);
      ''';

      final vocabulary = await _vocabularyOf(source, coreCatalog);

      expect(vocabulary.widgetNames.toList(), [
        'restage.core:Column',
        'restage.core:Text',
      ]);
      expect(vocabulary.iconCodePoints, isEmpty);
    });

    test('an app class that is not a catalog widget names nothing', () async {
      const source = '''
        import 'package:flutter/material.dart';

        class PromoBadge extends StatelessWidget {
          const PromoBadge({super.key});

          @override
          Widget build(BuildContext context) => const Text('promo');
        }

        Widget layout() => const PromoBadge();
      ''';

      final vocabulary = await _vocabularyOf(source, coreCatalog);

      expect(vocabulary.widgetNames.toList(), ['restage.core:Text']);
    });

    test('two catalog entries on one Flutter type both stay', () async {
      const acme = WidgetLibrary.custom('acme.widgets');
      final sharedTypeCatalog = Catalog(
        schemaVersion: kSupportedSchemaVersion,
        generatedAt: '1970-01-01T00:00:00Z',
        libraries: {
          WidgetLibrary.core: const LibraryInfo(version: '0.1.0'),
          acme: const LibraryInfo(version: '1.0.0'),
        },
        widgets: [
          entry(name: 'Column', properties: const [], flutterType: columnType),
          entry(
            name: 'AcmeStack',
            properties: const [],
            library: acme,
            flutterType: columnType,
          ),
        ],
      );
      const source = '''
        import 'package:flutter/material.dart';

        Widget layout() => Column(children: const []);
      ''';

      final vocabulary = await _vocabularyOf(source, sharedTypeCatalog);

      expect(vocabulary.widgetNames.toList(), [
        'acme.widgets:AcmeStack',
        'restage.core:Column',
      ]);
    });

    test('a construction naming a member names the entry keyed on it',
        () async {
      const source = '''
        import 'package:flutter/material.dart';

        Widget hero() => Image.network('https://example.com/a.png');
      ''';

      final vocabulary = await _vocabularyOf(source, imageCatalog);

      expect(vocabulary.widgetNames.toList(), ['restage.core:Image']);
    });

    test('a bare construction names no entry keyed on a member', () async {
      const source = '''
        import 'package:flutter/material.dart';

        Widget hero() =>
            const Image(image: NetworkImage('https://example.com/a.png'));
      ''';

      final vocabulary = await _vocabularyOf(source, imageCatalog);

      expect(vocabulary.widgetNames, isEmpty);
    });

    test('a construction naming a member keeps its bare class entry too',
        () async {
      const cardType = 'package:flutter/src/material/card.dart#Card';
      final cardCatalog = catalogWith([
        entry(name: 'Card', properties: const [], flutterType: cardType),
        entry(
          name: 'CardFilled',
          properties: const [],
          flutterType: '$cardType.filled',
        ),
      ]);
      const source = '''
        import 'package:flutter/material.dart';

        Widget promo() => const Card.filled();
      ''';

      final vocabulary = await _vocabularyOf(source, cardCatalog);

      expect(vocabulary.widgetNames.toList(), [
        'restage.core:Card',
        'restage.core:CardFilled',
      ]);
    });
  });

  group('resolved constructor spelling', () {
    final loweringCatalog = catalogWith([
      entry(name: 'Text', properties: const [], flutterType: textType),
      entry(
        name: 'TextRich',
        properties: const [],
        flutterType: '$textType.rich',
      ),
      entry(name: 'Image', properties: const [], flutterType: networkImageType),
      entry(
        name: 'ImageAsset',
        properties: const [],
        flutterType: assetImageType,
      ),
      entry(
        name: 'CardFilled',
        properties: const [],
        flutterType: 'package:flutter/src/material/card.dart#Card.filled',
      ),
      entry(
        name: 'RestagePager',
        properties: const [],
        flutterType: 'package:restage_core/restage_core.dart#RestagePager',
      ),
    ]);
    for (final prefix in ['', 'f.']) {
      final import = prefix.isEmpty ? '' : ' as f';
      test('${prefix}Text interpolation retains TextRich', () async {
        final vocabulary = await _vocabularyOf(
          '''
import 'package:flutter/material.dart'$import;
${prefix}Widget render(String value) => ${prefix}Text('label \$value');
''',
          loweringCatalog,
        );
        expect(
          vocabulary.widgetNames,
          {'restage.core:Text', 'restage.core:TextRich'},
        );
      });
      test('${prefix}named constructors keep their resolved identities',
          () async {
        final vocabulary = await _vocabularyOf(
          '''
import 'package:flutter/material.dart'$import;
final widgets = [
  const ${prefix}Text.rich(${prefix}TextSpan(text: 'rich')),
  ${prefix}Image.network('https://example.com/a.png'),
  ${prefix}Image.asset('a.png'),
  const ${prefix}Card.filled(),
];
''',
          loweringCatalog,
        );
        expect(vocabulary.widgetNames, {
          'restage.core:Text',
          'restage.core:TextRich',
          'restage.core:Image',
          'restage.core:ImageAsset',
          'restage.core:CardFilled',
        });
      });
      for (final constructor in ['', '.builder']) {
        test('${prefix}PageView$constructor retains pager headroom', () async {
          final arguments = constructor.isEmpty
              ? 'children: const []'
              : 'itemBuilder: (_, index) => null';
          final vocabulary = await _vocabularyOf(
            '''
import 'package:flutter/material.dart'$import;
final pages = ${prefix}PageView$constructor($arguments);
''',
            loweringCatalog,
          );
          expect(vocabulary.widgetNames, {'restage.core:RestagePager'});
        });
      }
    }
    test('resolved app lookalikes never receive Flutter lowering headroom',
        () async {
      final vocabulary = await _vocabularyOf(
        r'''
class Text { Text(String value); Text.rich(Object value); }
class PageView { PageView(); PageView.builder(); }
Object render(String value) => [Text('label $value'), Text.rich('x'), PageView(), PageView.builder()];
''',
        loweringCatalog,
      );
      expect(vocabulary.widgetNames, isEmpty);
    });
  });

  group('deriveAppWidgetVocabulary — icons', () {
    test('a compile-time icon constant names its code point', () async {
      const source = '''
        import 'package:flutter/cupertino.dart' show CupertinoIcons;
        import 'package:flutter/material.dart';

        const IconData confirm = Icons.check;
        const IconData favourite = CupertinoIcons.heart;
      ''';

      final vocabulary = await _vocabularyOf(source, coreCatalog);

      // The values the pinned Flutter declares for `Icons.check` and
      // `CupertinoIcons.heart`.
      expect(vocabulary.iconCodePoints, {
        'CupertinoIcons': {0xf442},
        'MaterialIcons': {0xe156},
      });
      expect(vocabulary.widgetNames, isEmpty);
    });

    test('an icon reached through a variable is out of scope', () async {
      const source = '''
        import 'package:flutter/material.dart';

        Widget glyph(IconData chosen) {
          final resolved = chosen;
          return Icon(resolved);
        }
      ''';

      final vocabulary = await _vocabularyOf(source, coreCatalog);

      expect(vocabulary, WidgetVocabulary.empty);
    });
  });

  group('deriveAppWidgetVocabulary — determinism', () {
    const declarationsOneOrder = '''
      import 'package:flutter/cupertino.dart' show CupertinoIcons;
      import 'package:flutter/material.dart';

      const IconData confirm = Icons.check;
      const IconData favourite = CupertinoIcons.heart;

      Widget first() => const Text('a');
      Widget second() => Column(children: const [Text('b')]);
    ''';
    const declarationsAnotherOrder = '''
      import 'package:flutter/cupertino.dart' show CupertinoIcons;
      import 'package:flutter/material.dart';

      Widget second() => Column(children: const [Text('b')]);
      Widget first() => const Text('a');

      const IconData favourite = CupertinoIcons.heart;
      const IconData confirm = Icons.check;
    ''';

    test('deriving twice from one input encodes byte-identically', () async {
      final (first, second) = await _withResolvedFixture(
        declarationsOneOrder,
        (library) => (
          deriveAppWidgetVocabulary([library], coreCatalog),
          deriveAppWidgetVocabulary([library], coreCatalog),
        ),
      );

      expect(first, second);
      expect(jsonEncode(first.toJson()), jsonEncode(second.toJson()));
    });

    test('declaration order does not change the value', () async {
      final oneOrder = await _vocabularyOf(declarationsOneOrder, coreCatalog);
      final anotherOrder = await _vocabularyOf(
        declarationsAnotherOrder,
        coreCatalog,
      );

      expect(anotherOrder, oneOrder);
      expect(
        jsonEncode(anotherOrder.toJson()),
        jsonEncode(oneOrder.toJson()),
      );
    });
  });

  group('vocabularyOfCatalogEntries', () {
    test('names entries from every library it is given', () {
      final vocabulary = vocabularyOfCatalogEntries([
        entry(name: 'Column', properties: const []),
        entry(
          name: 'Chip',
          properties: const [],
          library: WidgetLibrary.material,
        ),
      ]);

      expect(vocabulary.widgetNames.toList(), [
        'restage.core:Column',
        'restage.material:Chip',
      ]);
      expect(vocabulary.iconCodePoints, isEmpty);
    });
  });
}
