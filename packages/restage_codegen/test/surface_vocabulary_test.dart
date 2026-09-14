import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:build/build.dart';
import 'package:restage_codegen/src/app_widget_vocabulary.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/surface_vocabulary.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// The app library every fixture is written to. Flutter-importing sources need
/// a root package that carries Flutter, hence `apps_examples`.
const String _fixtureId = 'apps_examples|lib/surface_vocabulary_fixture.dart';

/// A Flutter-hosted `IconData` carrying one field beyond the set the build
/// rebuilds, plus an `Icons` holder naming one.
///
/// Flutter's own `IconData` is a `final class`, so the only way to resolve an
/// icon with a field the reconstruction does not know about is to declare the
/// type — and it has to sit under `package:flutter/`, which is the identity
/// both the icon recognition and the translator's icon arm gate on.
const String _extraFieldIconsAsset = 'flutter|lib/extra_field_icons.dart';
const String _extraFieldIconsSource = '''
class IconData {
  const IconData(
    this.codePoint, {
    this.fontFamily,
    this.fontPackage,
    this.matchTextDirection = false,
    this.fontFamilyFallback,
    this.opticalSize,
  });

  final int codePoint;
  final String? fontFamily;
  final String? fontPackage;
  final bool matchTextDirection;
  final List<String>? fontFamilyFallback;
  final double? opticalSize;
}

class Icons {
  const Icons._();

  static const IconData star = IconData(
    0xe900,
    fontFamily: 'MaterialIcons',
    opticalSize: 24,
  );
}
''';

/// A Flutter-hosted icon holder whose one constant names no font family.
///
/// Flutter's own `Icons` and `CupertinoIcons` name a family on every member,
/// and the translator's icon arm only recognises holders under
/// `package:flutter/`, so this is the only way to drive that path.
const String _familylessIconsAsset = 'flutter|lib/familyless_icons.dart';
const String _familylessIconsSource = '''
class IconData {
  const IconData(
    this.codePoint, {
    this.fontFamily,
    this.fontPackage,
    this.matchTextDirection = false,
    this.fontFamilyFallback,
  });

  final int codePoint;
  final String? fontFamily;
  final String? fontPackage;
  final bool matchTextDirection;
  final List<String>? fontFamilyFallback;
}

class Icons {
  const Icons._();

  static const IconData badge = IconData(0xe900);
}
''';

Future<SurfaceVocabularyReferences> _referencesOf(
  String source,
  Catalog catalog, {
  Map<String, String> extras = const {},
}) =>
    resolveWorkspaceSources(
      {...extras, _fixtureId: source},
      (resolver) async {
        final library = await resolver.libraryFor(AssetId.parse(_fixtureId));
        final resolved =
            await library.session.getResolvedLibraryByElement(library);
        if (resolved is! ResolvedLibraryResult) {
          throw StateError('The surface vocabulary fixture did not resolve.');
        }
        return deriveAppVocabulary([resolved], catalog).references;
      },
      resolverFor: _fixtureId,
      rootPackage: 'apps_examples',
    );

/// The resolved const value of each top-level variable in [source].
Future<Map<String, DartObject>> _constantsOf(
  String source, {
  Map<String, String> extras = const {},
}) =>
    resolveWorkspaceSources(
      {...extras, _fixtureId: source},
      (resolver) async {
        final library = await resolver.libraryFor(AssetId.parse(_fixtureId));
        return <String, DartObject>{
          for (final variable in library.topLevelVariables)
            if (variable.name case final name?)
              if (variable.computeConstantValue() case final value?)
                name: value,
        };
      },
      resolverFor: _fixtureId,
      rootPackage: 'apps_examples',
    );

/// The resolved expression `x()` returns in [source].
Future<Expression> _expressionOf(
  String source, {
  Map<String, String> extras = const {},
}) =>
    resolveWorkspaceSources(
      {...extras, _fixtureId: source},
      (resolver) async {
        final library = await resolver.libraryFor(AssetId.parse(_fixtureId));
        final resolved =
            await library.session.getResolvedLibraryByElement(library);
        if (resolved is! ResolvedLibraryResult) {
          throw StateError('The expression fixture did not resolve.');
        }
        final function =
            library.topLevelFunctions.firstWhere((each) => each.name == 'x');
        final node =
            resolved.getFragmentDeclaration(function.firstFragment)?.node;
        if (node is! FunctionDeclaration) {
          throw StateError('The expression fixture declares no `x()`.');
        }
        final body = node.functionExpression.body;
        if (body is! ExpressionFunctionBody) {
          throw StateError('`x()` must be expression-bodied.');
        }
        return body.expression;
      },
      resolverFor: _fixtureId,
      rootPackage: 'apps_examples',
    );

/// The translation of the expression `x()` returns in [source].
Future<TranslationResult> _translationOf(
  String source, {
  Map<String, String> extras = const {},
}) async =>
    ExpressionTranslator(catalog: kEmptyCatalog, helpers: HelperRegistry())
        .translate(await _expressionOf(source, extras: extras));

void main() {
  const textType = 'package:flutter/src/widgets/text.dart#Text';
  const columnType = 'package:flutter/src/widgets/basic.dart#Column';
  const rowType = 'package:flutter/src/widgets/basic.dart#Row';
  const chipType = 'package:flutter/src/material/chip.dart#Chip';

  final catalog = Catalog(
    schemaVersion: kSupportedSchemaVersion,
    generatedAt: '1970-01-01T00:00:00Z',
    libraries: {
      WidgetLibrary.core: const LibraryInfo(version: '0.1.0'),
      WidgetLibrary.material: const LibraryInfo(version: '0.1.0'),
    },
    widgets: [
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
      entry(
        name: 'Row',
        childrenSlot: ChildrenSlot.list,
        properties: [prop('children', PropertyType.widgetList)],
        flutterType: rowType,
      ),
      entry(
        name: 'Chip',
        properties: const [],
        library: WidgetLibrary.material,
        flutterType: chipType,
      ),
    ],
  );

  group('IconData reconstruction', () {
    // Between them these exercise every field the const constructor takes: a
    // plain Material icon, a directional one that sets matchTextDirection, a
    // Cupertino icon shipped in a package, and a fallback list.
    const source = '''
      import 'package:flutter/material.dart';
      import 'package:flutter/cupertino.dart' show CupertinoIcons;

      const IconData plain = Icons.check;
      const IconData directional = Icons.arrow_back;
      const IconData packaged = CupertinoIcons.heart;
      const IconData fallback = IconData(
        0xe900,
        fontFamily: 'AcmeIcons',
        fontFamilyFallback: <String>['AcmeFallback', 'MaterialIcons'],
      );
    ''';

    late Map<String, DartObject> constants;

    setUpAll(() async {
      constants = await _constantsOf(source);
    });

    for (final name in const [
      'plain',
      'directional',
      'packaged',
      'fallback',
    ]) {
      test('$name is rebuilt field for field', () {
        final value = constants[name]!;
        final reference = iconDataReference(value);

        expect(reference.codePoint, value.getField('codePoint')!.toIntValue());
        expect(
          reference.fontFamily,
          value.getField('fontFamily')!.toStringValue(),
        );
        expect(
          reference.fontPackage,
          value.getField('fontPackage')!.toStringValue(),
        );
        expect(
          reference.matchTextDirection,
          value.getField('matchTextDirection')!.toBoolValue(),
        );
        expect(
          reference.fontFamilyFallback,
          value
              .getField('fontFamilyFallback')!
              .toListValue()
              ?.map((element) => element.toStringValue())
              .toList(),
        );
      });
    }

    test('a directional icon keeps matchTextDirection', () {
      final reference = iconDataReference(constants['directional']!);

      expect(reference.matchTextDirection, isTrue);
      expect(reference.spelling(), contains('matchTextDirection: true'));
    });

    test('a packaged icon keeps its font package', () {
      final reference = iconDataReference(constants['packaged']!);

      expect(reference.fontPackage, isNotNull);
      expect(
        reference.spelling(),
        contains("fontPackage: '${reference.fontPackage}'"),
      );
    });

    test('a plain icon spells only the arguments it needs', () {
      final reference = iconDataReference(constants['plain']!);

      expect(
        reference.spelling(),
        'IconData(0x${reference.codePoint.toRadixString(16)}, '
        "fontFamily: 'MaterialIcons')",
      );
      expect(reference.spelling('r.'), startsWith('r.IconData('));
    });

    test('a fallback list is spelled as a typed list', () {
      final reference = iconDataReference(constants['fallback']!);

      expect(
        reference.spelling(),
        "IconData(0xe900, fontFamily: 'AcmeIcons', "
        "fontFamilyFallback: <String>['AcmeFallback', 'MaterialIcons'])",
      );
    });

    test('an icon naming no font family cannot be carried', () async {
      // The icon table is keyed by family. Carrying the bare code point would
      // have the runtime look it up under the Material family and throw at
      // first render, turning a build-time fact into a field failure.
      final familyless = await _constantsOf(
        "import 'package:flutter/material.dart';\n\n"
        'const IconData unfamilied = IconData(0xe900);\n',
      );

      expect(
        () => iconDataReference(familyless['unfamilied']!),
        throwsA(isA<IconFontFamilyMissing>()),
      );
    });
  });

  group('an icon naming no font family', () {
    const familylessSource = '''
      import 'package:flutter/material.dart';

      const IconData unfamilied = IconData(0xe900);
      const IconData named = unfamilied;
    ''';

    test('a surface that renders one fails the build', () async {
      // Before this, the translator emitted the bare code point and the
      // runtime looked it up under the Material family, so a build-time fact
      // surfaced as a first-render failure in the field instead.
      final translation = await _translationOf(
        "import 'package:flutter/familyless_icons.dart';\n\n"
        'Object x() => Icons.badge;\n',
        extras: const {_familylessIconsAsset: _familylessIconsSource},
      );

      final refusals = translation.issues
          .where((issue) => issue.code == IssueCode.unreconstructableIconData)
          .toList();
      expect(refusals, isNotEmpty);
      expect(refusals.first.message, contains('Icons.badge'));
      expect(refusals.first.message, contains('names no font family'));
      expect(refusals.first.location, isNotEmpty);
      expect(translation.dsl, isEmpty);
    });

    test('the walk censuses what it can carry and passes the rest over',
        () async {
      // The walk derives an app's over-the-air headroom. A family-less icon
      // is not part of that vocabulary, and app code that never reaches a
      // delivered surface must not fail the whole build.
      final references = await _referencesOf(familylessSource, kEmptyCatalog);

      expect(references.icons, isEmpty);
    });
  });

  group('icon capture', () {
    test('a Flutter icon is captured with every field it sets', () async {
      const source = '''
        import 'package:flutter/material.dart';

        const IconData confirm = Icons.arrow_back;
      ''';

      final references = await _referencesOf(source, catalog);
      final family = references.mirroredIcons['MaterialIcons']!;
      final icon = family.values.single;

      // A mirroring icon is carried apart, so it and its non-mirroring twin
      // can be installed at once.
      expect(references.icons, isEmpty);
      expect(icon.codePoint, family.keys.single);
      expect(icon.fontFamily, 'MaterialIcons');
      expect(icon.fontPackage, isNull);
      expect(icon.matchTextDirection, isTrue);
      expect(icon.fontFamilyFallback, isNull);
    });

    test('a Cupertino icon keeps its own family and package', () async {
      const source = '''
        import 'package:flutter/cupertino.dart' show CupertinoIcons, IconData;

        const IconData zulu = CupertinoIcons.heart;
      ''';

      final references = await _referencesOf(source, catalog);
      final icon = references.icons['CupertinoIcons']![0xf442]!;

      expect(icon.fontFamily, 'CupertinoIcons');
      expect(icon.fontPackage, 'cupertino_icons');
      expect(
        icon.spelling(),
        "IconData(0xf442, fontFamily: 'CupertinoIcons', "
        "fontPackage: 'cupertino_icons')",
      );
    });

    test('one code point keeps one icon however often it is named', () async {
      const source = '''
        import 'package:flutter/material.dart';

        const IconData alpha = Icons.check;
        const IconData zulu = Icons.check;
      ''';

      final references = await _referencesOf(source, catalog);
      final family = references.icons['MaterialIcons']!;

      expect(family.keys, [0xe156]);
      expect(family[0xe156]!.spelling(), contains('0xe156'));
    });
  });

  group('emitSurfaceVocabulary', () {
    test('names one builder per widget and rebuilds each icon', () async {
      const source = '''
        import 'package:flutter/material.dart';

        const IconData confirm = Icons.check;

        Widget layout() => Column(children: const [Text('a')]);
      ''';

      final references = await _referencesOf(source, catalog);

      expect(
        emitSurfaceVocabulary(references),
        <String>[
          'SurfaceVocabulary(',
          'widgets: RestageWidgetLibraries.fromVocabulary(',
          "core: {'Column': buildColumn,'Text': buildText,},",
          '),',
          'icons: RestageIconTable.fromFamilies(families: ',
          "{'MaterialIcons': {0xe156: IconData(0xe156, ",
          "fontFamily: 'MaterialIcons'),},}),",
          ')',
        ].join(),
      );
    });

    test('leaves the rest of the catalog out', () async {
      const source = '''
        import 'package:flutter/material.dart';

        Widget layout() => Column(children: const []);
      ''';

      final references = await _referencesOf(source, catalog);
      final emitted = emitSurfaceVocabulary(references);

      expect(emitted, contains("'Column': buildColumn"));
      expect(emitted, isNot(contains('buildRow')));
      expect(emitted, isNot(contains('buildText')));
      expect(emitted, isNot(contains('buildChip')));
    });

    test('qualifies the SDK and IconData through one prefix', () {
      const icon = IconDataReference(
        codePoint: 0xe156,
        fontFamily: 'MaterialIcons',
      );

      expect(
        emitSurfaceVocabulary(
          SurfaceVocabularyReferences(
            widgetNames: const ['restage.material:Chip'],
            icons: const [icon],
          ),
          sdkPrefix: 'r.',
        ),
        <String>[
          'r.SurfaceVocabulary(',
          'widgets: r.RestageWidgetLibraries.fromVocabulary(',
          "material: {'Chip': r.buildChip,},",
          '),',
          'icons: r.RestageIconTable.fromFamilies(families: ',
          "{'MaterialIcons': {0xe156: r.IconData(0xe156, ",
          "fontFamily: 'MaterialIcons'),},}),",
          ')',
        ].join(),
      );
    });

    test('a mirroring icon fills the mirrored map', () async {
      const source = '''
        import 'package:flutter/material.dart';

        const IconData confirm = Icons.check;
        const IconData back = Icons.arrow_back;
      ''';

      final references = await _referencesOf(source, catalog);

      expect(
        emitSurfaceVocabulary(references),
        <String>[
          'SurfaceVocabulary(',
          'icons: RestageIconTable.fromFamilies(families: ',
          "{'MaterialIcons': {0xe156: IconData(0xe156, ",
          "fontFamily: 'MaterialIcons'),},}, mirrored: ",
          "{'MaterialIcons': {0xe092: IconData(0xe092, ",
          "fontFamily: 'MaterialIcons', matchTextDirection: true),},}),",
          ')',
        ].join(),
      );
    });

    test('names nothing installable when only custom widgets appear', () {
      final references = SurfaceVocabularyReferences(
        widgetNames: const ['acme.widgets:Badge'],
      );

      expect(references.isEmpty, isFalse);
      expect(references.namesInstallable, isFalse);
      expect(emitSurfaceVocabulary(references), 'SurfaceVocabulary.none');
    });
  });

  group('determinism', () {
    const declarations = '''
      import 'package:flutter/material.dart';

      const IconData confirm = Icons.check;

      Widget first() => const Text('a');
      Widget second() => Column(children: const [Text('b')]);
    ''';
    const reordered = '''
      import 'package:flutter/material.dart';

      Widget second() => Column(children: const [Text('b')]);
      Widget first() => const Text('a');

      const IconData confirm = Icons.check;
    ''';

    test('two emissions from one input are byte-identical', () async {
      final references = await _referencesOf(declarations, catalog);

      expect(
        emitSurfaceVocabulary(references),
        emitSurfaceVocabulary(references),
      );
    });

    test('declaration order does not change the emission', () async {
      final oneOrder = await _referencesOf(declarations, catalog);
      final anotherOrder = await _referencesOf(reordered, catalog);

      expect(
        emitSurfaceVocabulary(anotherOrder),
        emitSurfaceVocabulary(oneOrder),
      );
    });

    test('a union folds to one canonical set whichever side it starts',
        () async {
      final left = SurfaceVocabularyReferences(
        widgetNames: const ['restage.core:Text'],
        icons: const [
          IconDataReference(
            codePoint: 0xe156,
            fontFamily: 'MaterialIcons',
          ),
        ],
      );
      final right = SurfaceVocabularyReferences(
        widgetNames: const ['restage.material:Chip'],
      );

      expect(
        emitSurfaceVocabulary(left.union(right)),
        emitSurfaceVocabulary(right.union(left)),
      );
      expect(
        emitSurfaceVocabulary(left.union(right)),
        contains("core: {'Text': buildText,}"),
      );
      expect(
        emitSurfaceVocabulary(left.union(right)),
        contains("material: {'Chip': buildChip,}"),
      );
    });

    test('one code point named twice folds to one entry', () {
      const check = IconDataReference(
        codePoint: 0xe156,
        fontFamily: 'MaterialIcons',
      );

      final references = SurfaceVocabularyReferences(
        icons: const [check, check],
      );

      expect(references.icons['MaterialIcons']!.keys, [0xe156]);
      expect(
        emitSurfaceVocabulary(references),
        <String>[
          'SurfaceVocabulary(icons: RestageIconTable.fromFamilies(families: ',
          "{'MaterialIcons': {0xe156: IconData(0xe156, ",
          "fontFamily: 'MaterialIcons'),},}),)",
        ].join(),
      );
    });
  });

  group('one code point, two glyphs', () {
    const bare = IconDataReference(
      codePoint: 0xe156,
      fontFamily: 'MaterialIcons',
    );
    const mirrored = IconDataReference(
      codePoint: 0xe156,
      fontFamily: 'MaterialIcons',
      matchTextDirection: true,
    );

    test('both are carried, one in each half', () {
      // The wire carries the mirroring beside the family and the code point,
      // so the two members of a pair are separately addressable rather than
      // one having to be dropped.
      final references = SurfaceVocabularyReferences(
        icons: const [bare, mirrored],
      );

      expect(references.icons['MaterialIcons']!.keys, [0xe156]);
      expect(references.mirroredIcons['MaterialIcons']!.keys, [0xe156]);
      expect(
        references.mirroredIcons['MaterialIcons']![0xe156]!.spelling(),
        "IconData(0xe156, fontFamily: 'MaterialIcons', "
        'matchTextDirection: true)',
      );
    });

    test('both reach the emission, one map each', () {
      expect(
        emitSurfaceVocabulary(
          SurfaceVocabularyReferences(icons: const [mirrored, bare]),
        ),
        <String>[
          'SurfaceVocabulary(icons: RestageIconTable.fromFamilies(families: ',
          "{'MaterialIcons': {0xe156: IconData(0xe156, ",
          "fontFamily: 'MaterialIcons'),},}, mirrored: ",
          "{'MaterialIcons': {0xe156: IconData(0xe156, ",
          "fontFamily: 'MaterialIcons', matchTextDirection: true),},}),)",
        ].join(),
      );
    });

    test('a surface naming no mirroring icon leaves the second map off', () {
      expect(
        emitSurfaceVocabulary(SurfaceVocabularyReferences(icons: const [bare])),
        <String>[
          'SurfaceVocabulary(icons: RestageIconTable.fromFamilies(families: ',
          "{'MaterialIcons': {0xe156: IconData(0xe156, ",
          "fontFamily: 'MaterialIcons'),},}),)",
        ].join(),
      );
    });

    test('a union carries both halves', () {
      final union = SurfaceVocabularyReferences(icons: const [bare])
          .union(SurfaceVocabularyReferences(icons: const [mirrored]));

      expect(union.icons['MaterialIcons']!.keys, [0xe156]);
      expect(union.mirroredIcons['MaterialIcons']!.keys, [0xe156]);
    });
  });

  group('two icons the wire cannot tell apart', () {
    const packaged = IconDataReference(
      codePoint: 0xf3cf,
      fontFamily: 'CupertinoIcons',
      fontPackage: 'cupertino_icons',
    );
    const bundled = IconDataReference(
      codePoint: 0xf3cf,
      fontFamily: 'CupertinoIcons',
    );

    test('one naming a font package the other does not fails the build', () {
      // Family, code point and mirroring all agree, and the wire carries
      // nothing else, so keeping whichever spelling sorted first would change
      // which font the other one renders from.
      expect(
        () => SurfaceVocabularyReferences(icons: const [packaged, bundled]),
        throwsA(
          isA<IconCodePointCollision>()
              .having((error) => error.fontFamily, 'family', 'CupertinoIcons')
              .having((error) => error.codePoint, 'code point', 0xf3cf)
              .having((error) => error.matchTextDirection, 'mirroring', isFalse)
              .having(
                (error) => error.firstSpelling,
                'first spelling',
                "IconData(0xf3cf, fontFamily: 'CupertinoIcons')",
              )
              .having(
                (error) => error.secondSpelling,
                'second spelling',
                "IconData(0xf3cf, fontFamily: 'CupertinoIcons', "
                    "fontPackage: 'cupertino_icons')",
              ),
        ),
      );
    });

    test('the refusal names both spellings whichever came first', () {
      String messageOf(List<IconDataReference> icons) {
        try {
          SurfaceVocabularyReferences(icons: icons);
        } on IconCodePointCollision catch (collision) {
          return collision.toString();
        }
        return '';
      }

      expect(
        messageOf(const [packaged, bundled]),
        messageOf(const [bundled, packaged]),
      );
      expect(
        messageOf(const [packaged, bundled]),
        allOf(
          contains('0xf3cf'),
          contains("font family 'CupertinoIcons'"),
          contains("IconData(0xf3cf, fontFamily: 'CupertinoIcons')"),
          contains("fontPackage: 'cupertino_icons'"),
        ),
      );
    });

    test('the refusal no longer suggests a mirroring difference', () {
      String messageOf(List<IconDataReference> icons) {
        try {
          SurfaceVocabularyReferences(icons: icons);
        } on IconCodePointCollision catch (collision) {
          return '${collision.reason}\n$collision';
        }
        return '';
      }

      expect(
        messageOf(const [packaged, bundled]),
        isNot(contains('matchTextDirection')),
      );
    });

    test('a union that disagrees on one code point fails too', () {
      expect(
        () => SurfaceVocabularyReferences(icons: const [packaged])
            .union(SurfaceVocabularyReferences(icons: const [bundled])),
        throwsA(isA<IconCodePointCollision>()),
      );
    });
  });

  group('Flutter pairs that share a code point', () {
    // CupertinoIcons.back and CupertinoIcons.chevron_back are both 0xf3cf and
    // differ only in matchTextDirection, which the wire carries, so a surface
    // can name both and still render each one.
    const sharedCodePointPair = '''
      import 'package:flutter/cupertino.dart' show CupertinoIcons, IconData;

      const IconData mirrored = CupertinoIcons.back;
      const IconData plain = CupertinoIcons.chevron_back;
    ''';

    test('the walk carries both, one in each half', () async {
      final references =
          await _referencesOf(sharedCodePointPair, kEmptyCatalog);

      expect(
        references.icons['CupertinoIcons']![0xf3cf]!.matchTextDirection,
        isFalse,
      );
      expect(
        references.mirroredIcons['CupertinoIcons']![0xf3cf]!.matchTextDirection,
        isTrue,
      );
    });

    test('the translator carries both and raises nothing', () async {
      final translation = await _translationOf(
        "import 'package:flutter/cupertino.dart';\n\n"
        'Object x() => [CupertinoIcons.back, CupertinoIcons.chevron_back];\n',
      );

      expect(
        translation.issues.map((issue) => issue.code),
        isNot(contains(IssueCode.collidingIconCodePoints)),
      );
      expect(translation.iconReferences, hasLength(2));
      expect(
        translation.iconReferences.map((icon) => icon.codePoint),
        everyElement(0xf3cf),
      );
      expect(
        translation.iconReferences.map((icon) => icon.matchTextDirection),
        containsAll(<bool>[false, true]),
      );
    });

    test('one icon named twice is carried once and raises nothing', () async {
      final translation = await _translationOf(
        "import 'package:flutter/material.dart';\n\n"
        'Object x() => [Icons.check, Icons.check];\n',
      );

      expect(
        translation.issues.map((issue) => issue.code),
        isNot(contains(IssueCode.collidingIconCodePoints)),
      );
      expect(translation.iconReferences, hasLength(1));
      expect(translation.iconReferences.single.codePoint, 0xe156);
    });
  });

  group('an IconData field this build does not know about', () {
    const namingSource = '''
      import 'package:flutter/extra_field_icons.dart';

      const IconData badge = Icons.star;
    ''';

    test('the field census refuses the constant', () async {
      final constants = await _constantsOf(
        namingSource,
        extras: const {_extraFieldIconsAsset: _extraFieldIconsSource},
      );

      expect(
        () => iconDataReference(constants['badge']!),
        throwsA(
          isA<IconDataReconstructionFailure>().having(
            (failure) => failure.reason,
            'reason',
            allOf(
              contains('unexpected: opticalSize'),
              contains('rather than shipping an icon with a dropped field'),
            ),
          ),
        ),
      );
    });

    test('the walk turns the refusal into its error', () async {
      await expectLater(
        _referencesOf(
          namingSource,
          kEmptyCatalog,
          extras: const {_extraFieldIconsAsset: _extraFieldIconsSource},
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('Icons.star'),
              contains('unexpected: opticalSize'),
            ),
          ),
        ),
      );
    });

    test('the translator turns the refusal into a fatal build issue', () async {
      final translation = await _translationOf(
        "import 'package:flutter/extra_field_icons.dart';\n\n"
        'Object x() => Icons.star;\n',
        extras: const {_extraFieldIconsAsset: _extraFieldIconsSource},
      );

      final refusals = translation.issues
          .where((issue) => issue.code == IssueCode.unreconstructableIconData)
          .toList();
      expect(refusals, isNotEmpty);
      final refusal = refusals.first;
      expect(refusal.message, contains('Icons.star'));
      expect(refusal.message, contains('unexpected: opticalSize'));
      expect(refusal.location, isNotEmpty);
      expect(refusal.code.isInformational, isFalse);
      expect(translation.dsl, isEmpty);
    });
  });
}
