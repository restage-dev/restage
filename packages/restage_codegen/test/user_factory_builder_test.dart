// Source expectations join Dart tokens without inserting whitespace.
// ignore_for_file: missing_whitespace_between_adjacent_strings

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:restage_codegen/src/app_size_disclosure.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_codegen/src/surface_vocabulary.dart';
import 'package:restage_codegen/src/user_factory_builder.dart';
import 'package:restage_codegen/src/user_factory_emitter.dart';
import 'package:restage_shared/restage_shared.dart'
    show SurfacePublicationManifest;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('UserFactoryBuilder', () {
    test('emits user_factories.g.dart when @RestageWidget classes are found',
        () async {
      const widgetSource = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        @RestageWidget(
          name: 'AcmeBadge',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.action,
          description: 'Promo badge.',
        )
        class AcmeBadge {
          const AcmeBadge({required this.label});
          @RestageProperty(description: 'Visible label.', required: true)
          final String label;
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/widgets/acme_badge.dart'),
        widgetSource,
      );

      await testBuilder(
        const UserFactoryBuilder(BuilderOptions.empty),
        {'apps_examples|lib/widgets/acme_badge.dart': widgetSource},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|lib/user_factories.g.dart': decodedMatches(
            allOf([
              contains('GENERATED CODE - DO NOT MODIFY BY HAND'),
              contains("import 'package:flutter/widgets.dart'"),
              contains(
                "import 'package:restage/restage.dart'",
              ),
              // Generated file does not import rfw directly — the SDK
              // re-exports DataSource / ArgumentDecoders /
              // LocalWidgetBuilder, so the custom package isn't
              // required to depend on rfw.
              isNot(contains("import 'package:rfw/rfw.dart'")),
              contains(
                "import 'package:apps_examples/widgets/acme_badge.dart'",
              ),
              contains('void registerRestageWidgets({'),
              contains(
                "@Deprecated('Use registerRestageWidgets; removed in 3.0')",
              ),
              contains(
                'void registerRestageCustomerWidgets() => '
                'registerRestageWidgets();',
              ),
              predicate<String>(
                (source) =>
                    RegExp(r'void registerRestageWidgets\(\{')
                        .allMatches(source)
                        .length ==
                    1,
                'contains one registration implementation body',
              ),
              contains("WidgetLibrary.custom('acme.design_system')"),
              contains(
                "RestageWidgetFactory(name: 'AcmeBadge', "
                'builder: _buildAcmeBadge)',
              ),
              contains(
                'Widget _buildAcmeBadge(BuildContext context, '
                'DataSource source)',
              ),
              // An all-simple-property package (no structured
              // types) still emits the custom library aliased (`as s0`),
              // so the constructor must be qualified with that alias. A
              // bare `AcmeBadge(...)` reference is undefined under the
              // prefixed import and fails analysis.
              contains('return s0.AcmeBadge('),
              isNot(contains('return AcmeBadge(')),
            ]),
          ),
        },
      );
    });

    test(
        'generated user_factories.g.dart ANALYZES CLEAN for an all-simple '
        'package with no structured-type properties', () async {
      // The durable net: a string pin on the aliased call shape is
      // analyze-blind as a class, so this resolves the generated library
      // through the analyzer and asserts zero error-severity diagnostics.
      // Before the fix the constructor emitted bare (`AcmeBadge(...)`) under
      // the prefixed import (`as s0`), an `undefined_function` error this
      // resolution catches. The widget is a real `StatelessWidget` so the
      // generated factory's `Widget` return type checks against it.
      const widgetSource = '''
        import 'package:flutter/widgets.dart';
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        @RestageWidget(
          name: 'AcmeBadge',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.action,
          description: 'Promo badge.',
        )
        class AcmeBadge extends StatelessWidget {
          const AcmeBadge({required this.label, super.key});
          @RestageProperty(description: 'Visible label.', required: true)
          final String label;
          @override
          Widget build(BuildContext context) => Text(label);
        }
      ''';

      // The fixture is a real `StatelessWidget`, so the builder needs the
      // Flutter sources loaded to resolve it — hence `apps_examples` (which
      // carries Flutter in its pubspec) rather than the dart-only root.
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/widgets/acme_badge.dart'),
        widgetSource,
      );

      // `testBuilders` (plural) + `flattenOutput` leaves the generated asset
      // readable back off `result.readerWriter` — the same shape the
      // onboarding compile fixtures use.
      final result = await testBuilders(
        [const UserFactoryBuilder(BuilderOptions.empty)],
        {'apps_examples|lib/widgets/acme_badge.dart': widgetSource},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );

      final generated = result.readerWriter.testing.readString(
        AssetId('apps_examples', 'lib/user_factories.g.dart'),
      );

      await resolveWorkspaceSources(
        {
          'apps_examples|lib/widgets/acme_badge.dart': widgetSource,
          'apps_examples|lib/user_factories.g.dart': generated,
        },
        (resolver) async {
          final library = await resolver.libraryFor(
            AssetId('apps_examples', 'lib/user_factories.g.dart'),
          );
          final resolved =
              await library.session.getResolvedLibraryByElement(library);
          if (resolved is! ResolvedLibraryResult) {
            throw StateError(
              'Generated user_factories.g.dart did not resolve.',
            );
          }
          final errors = [
            for (final unit in resolved.units)
              for (final diagnostic in unit.diagnostics)
                if (diagnostic.severity == Severity.error)
                  diagnostic.problemMessage.messageText(includeUrl: false),
          ];
          expect(
            errors,
            isEmpty,
            reason: 'generated factories must analyze clean; a bare '
                'constructor under a prefixed import is undefined_function',
          );
        },
        resolverFor: 'apps_examples|lib/user_factories.g.dart',
        rootPackage: 'apps_examples',
      );
    });

    test('same-named cross-library widget constructors analyze clean',
        () async {
      String widgetSource(String catalogName) => '''
        import 'package:flutter/widgets.dart';
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        @RestageWidget(
          name: '$catalogName',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.action,
          description: 'Promo badge.',
        )
        class Badge extends StatelessWidget {
          const Badge({required this.label, super.key});
          @RestageProperty(description: 'Visible label.', required: true)
          final String label;
          @override
          Widget build(BuildContext context) => Text(label);
        }
      ''';
      final firstSource = widgetSource('FirstBadge');
      final secondSource = widgetSource('SecondBadge');
      final sources = {
        'apps_examples|lib/widgets/first_badge.dart': firstSource,
        'apps_examples|lib/widgets/second_badge.dart': secondSource,
      };
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      for (final entry in sources.entries) {
        final path = entry.key.substring(entry.key.indexOf('|') + 1);
        readerWriter.testing.writeString(
          AssetId('apps_examples', path),
          entry.value,
        );
      }

      final result = await testBuilders(
        [const UserFactoryBuilder(BuilderOptions.empty)],
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      final generated = result.readerWriter.testing.readString(
        AssetId('apps_examples', 'lib/user_factories.g.dart'),
      );
      expect(generated, contains('return s0.Badge('));
      expect(generated, contains('return s1.Badge('));

      await resolveWorkspaceSources(
        {
          ...sources,
          'apps_examples|lib/user_factories.g.dart': generated,
        },
        (resolver) async {
          final library = await resolver.libraryFor(
            AssetId('apps_examples', 'lib/user_factories.g.dart'),
          );
          final resolved =
              await library.session.getResolvedLibraryByElement(library);
          if (resolved is! ResolvedLibraryResult) {
            throw StateError(
              'Same-name generated user_factories.g.dart did not resolve.',
            );
          }
          final errors = [
            for (final unit in resolved.units)
              for (final diagnostic in unit.diagnostics)
                if (diagnostic.severity == Severity.error)
                  diagnostic.problemMessage.messageText(includeUrl: false),
          ];
          expect(errors, isEmpty, reason: generated);
        },
        resolverFor: 'apps_examples|lib/user_factories.g.dart',
        rootPackage: 'apps_examples',
      );
    });

    test('case-distinct constructor presence locals analyze clean', () async {
      const widgetSource = r'''
        import 'package:flutter/widgets.dart';
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        @RestageWidget(
          name: 'CaseDistinctProbe',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.input,
          description: 'Case-distinct constructor probe.',
        )
        class CaseDistinctProbe extends StatelessWidget {
          const CaseDistinctProbe({
            this.foo = 'lower',
            this.Foo = 'upper',
            super.key,
          });

          @RestageProperty(description: 'Lower-case value.')
          final String? foo;

          @RestageProperty(description: 'Upper-case value.')
          final String? Foo;

          @override
          Widget build(BuildContext context) => Text('${foo ?? ''}${Foo ?? ''}');
        }
      ''';
      final sources = {
        'apps_examples|lib/widgets/case_distinct_probe.dart': widgetSource,
      };
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/widgets/case_distinct_probe.dart'),
        widgetSource,
      );

      final result = await testBuilders(
        [const UserFactoryBuilder(BuilderOptions.empty)],
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      final generated = result.readerWriter.testing.readString(
        AssetId('apps_examples', 'lib/user_factories.g.dart'),
      );

      await resolveWorkspaceSources(
        {
          ...sources,
          'apps_examples|lib/user_factories.g.dart': generated,
        },
        (resolver) async {
          final library = await resolver.libraryFor(
            AssetId('apps_examples', 'lib/user_factories.g.dart'),
          );
          final resolved =
              await library.session.getResolvedLibraryByElement(library);
          if (resolved is! ResolvedLibraryResult) {
            throw StateError(
              'Case-distinct generated user_factories.g.dart did not resolve.',
            );
          }
          final errors = [
            for (final unit in resolved.units)
              for (final diagnostic in unit.diagnostics)
                if (diagnostic.severity == Severity.error)
                  diagnostic.problemMessage.messageText(includeUrl: false),
          ];
          expect(errors, isEmpty, reason: generated);
        },
        resolverFor: 'apps_examples|lib/user_factories.g.dart',
        rootPackage: 'apps_examples',
      );
    });

    test(
        'the derived scope emits user_factories.g.dart with the whole-app '
        'vocabulary when the package declares no @RestageWidget class',
        () async {
      // Nothing mounts this screen, and it carries no Restage annotation, so
      // only the wider `lib/**.dart` scan sees the widgets and icons it names.
      const reserveSource = '''
        import 'package:flutter/material.dart';

        class ReserveScreen extends StatelessWidget {
          const ReserveScreen({super.key});

          @override
          Widget build(BuildContext context) => const Column(
                children: [Text('reserve'), Icon(Icons.check)],
              );
        }
      ''';

      // The scan resolves the fixture, so the Flutter sources have to be
      // loaded — hence `apps_examples` rather than the dart-only root.
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/screens/reserve.dart'),
        reserveSource,
      );

      await testBuilder(
        _derivedCatalogBuilder,
        {'apps_examples|lib/screens/reserve.dart': reserveSource},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|lib/user_factories.g.dart': decodedMatches(
            allOf([
              contains('GENERATED CODE - DO NOT MODIFY BY HAND'),
              contains("import 'package:restage/restage.dart';"),
              // The rebuilt icon names only IconData, which the SDK
              // re-exports, so the generated file imports no icon library.
              isNot(contains("import 'package:flutter/material.dart'")),
              contains('const SurfaceVocabulary kRestageAppVocabulary ='),
              contains("'Column': buildColumn"),
              contains("'Text': buildText"),
              _packs(
                contains("0xe156:IconData(0xe156,fontFamily:'MaterialIcons'"),
              ),
              contains(
                '  void call({\n'
                '    bool includeMaterial = true,\n'
                '    bool includeCupertino = true,\n'
                '  }) {\n'
                '    kRestageAppVocabulary.addToInstalled('
                'explicitSelection: true);\n'
                '  }',
              ),
              // The derived scope leaves the rest of the built-in catalog out
              // of the build.
              isNot(contains('buildRow')),
              isNot(contains('RestageWidgetLibraries.builtIn(')),
              isNot(contains('builtInIconTable(')),
            ]),
          ),
        },
      );
    });

    test(
        'the default scope installs the whole built-in catalog and both icon '
        'tables before the derived set', () async {
      const reserveSource = '''
        import 'package:flutter/material.dart';

        class ReserveScreen extends StatelessWidget {
          const ReserveScreen({super.key});

          @override
          Widget build(BuildContext context) => const Column(
                children: [Text('reserve'), Icon(Icons.check)],
              );
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/screens/reserve.dart'),
        reserveSource,
      );

      await testBuilder(
        const UserFactoryBuilder(BuilderOptions.empty),
        {'apps_examples|lib/screens/reserve.dart': reserveSource},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|lib/user_factories.g.dart': decodedMatches(
            allOf([
              contains("import 'package:restage/restage.dart';"),
              // The whole catalog goes in first, so the derived add unions to
              // the same thing.
              contains(
                '  void call({\n'
                '    bool includeMaterial = true,\n'
                '    bool includeCupertino = true,\n'
                '  }) {\n'
                '    InstalledWidgetLibraries.add('
                'RestageWidgetLibraries.builtIn(\n'
                '      includeMaterial: includeMaterial,\n'
                '      includeCupertino: includeCupertino,\n'
                '    ));\n'
                '    InstalledIconTable.add(builtInIconTable(\n'
                '      includeMaterial: includeMaterial,\n'
                '      includeCupertino: includeCupertino,\n'
                '    ));\n'
                '    kRestageAppVocabulary.addToInstalled('
                'explicitSelection: true);\n'
                '  }',
              ),
              // The derived set is still emitted alongside it.
              contains('const SurfaceVocabulary kRestageAppVocabulary ='),
              contains("'Column': buildColumn"),
            ]),
          ),
        },
      );
    });

    test('an unrecognised catalog scope fails the build', () async {
      const reserveSource = '''
        import 'package:flutter/material.dart';

        class ReserveScreen extends StatelessWidget {
          const ReserveScreen({super.key});

          @override
          Widget build(BuildContext context) => const Text('reserve');
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/screens/reserve.dart'),
        reserveSource,
      );

      final logs = <String>[];
      final result = await testBuilder(
        const UserFactoryBuilder(BuilderOptions({'catalog': 'everything'})),
        {'apps_examples|lib/screens/reserve.dart': reserveSource},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        onLog: (record) => logs.add('${record.message}${record.error ?? ''}'),
      );

      expect(result.succeeded, isFalse);
      expect(
        logs.join('\n'),
        allOf([
          contains('catalog'),
          contains('everything'),
          contains("'full'"),
          contains("'derived'"),
        ]),
      );
    });

    test('emitting twice from one input is byte-identical', () {
      final appVocabulary = SurfaceVocabularyReferences(
        widgetNames: const ['restage.core:Text'],
        icons: const [
          IconDataReference(
            codePoint: 0xe156,
            fontFamily: 'MaterialIcons',
          ),
        ],
      );

      expect(
        emitEmptyUserFactoriesDart(appVocabulary: appVocabulary),
        emitEmptyUserFactoriesDart(appVocabulary: appVocabulary),
      );
      expect(
        emitAdmittedUserFactoriesDart(
          const <WidgetEntry>[],
          appVocabulary: appVocabulary,
        ),
        emitAdmittedUserFactoriesDart(
          const <WidgetEntry>[],
          appVocabulary: appVocabulary,
        ),
      );
      expect(
        _packed(emitEmptyUserFactoriesDart(appVocabulary: appVocabulary)),
        contains("0xe156:IconData(0xe156,fontFamily:'MaterialIcons'"),
      );
    });

    test(
        'the app vocabulary carries a catalog entry only the compiled surface '
        'names', () async {
      // The source writes an interpolated `Text`, which the compiler lowers to
      // the rich-text catalog entry. That entry is nowhere in the Dart, so it
      // reaches the aggregate only through the compiled surfaces.
      const screenSource = r'''
        import 'package:flutter/material.dart';

        class Greeting extends StatelessWidget {
          const Greeting({super.key, required this.name});

          final String name;

          @override
          Widget build(BuildContext context) => Text('Hello $name');
        }
      ''';
      expect(screenSource, isNot(contains('TextRich')));

      // The scan resolves the fixture, so the Flutter sources have to be
      // loaded — hence `apps_examples` rather than the dart-only root.
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      readerWriter.testing
        ..writeString(
          AssetId('apps_examples', 'lib/screens/greeting.dart'),
          screenSource,
        )
        ..writeString(
          AssetId(
            'apps_examples',
            kRestageSurfacePublicationCompilerBundlePath,
          ),
          RestageSurfacePublicationBundle.valid(
            manifest: SurfacePublicationManifest(publications: const []),
            artifacts: const {},
            surfaceWidgetNames: const ['restage.core:TextRich'],
          ).encodeCanonicalJson(),
        );

      await testBuilder(
        const UserFactoryBuilder(BuilderOptions.empty),
        {'apps_examples|lib/screens/greeting.dart': screenSource},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|lib/user_factories.g.dart': decodedMatches(
            allOf([
              contains("'TextRich': buildTextRich"),
              contains("'Text': buildText"),
            ]),
          ),
        },
      );
    });

    test(
        'the app vocabulary carries the rich-text entry for an interpolated '
        'Text that no surface renders', () async {
      // The walk supplies over-the-air headroom for what an app writes in
      // ordinary Flutter code. An interpolated `Text` is delivered as the
      // rich-text entry, so an update using one renders only if that entry is
      // in the build — and nothing here compiles a surface that would name it.
      const interpolatedSource = r'''
        import 'package:flutter/material.dart';

        class Greeter extends StatelessWidget {
          const Greeter({super.key, required this.name});

          final String name;

          @override
          Widget build(BuildContext context) => Text('Hello $name');
        }
      ''';
      const plainSource = '''
        import 'package:flutter/material.dart';

        class Notice extends StatelessWidget {
          const Notice({super.key});

          @override
          Widget build(BuildContext context) => const Text('reserve');
        }
      ''';
      expect(interpolatedSource, isNot(contains('TextRich')));
      expect(plainSource, isNot(contains('TextRich')));

      // The scan resolves the fixture, so the Flutter sources have to be
      // loaded — hence `apps_examples` rather than the dart-only root.
      final interpolatedReaderWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      interpolatedReaderWriter.testing.writeString(
        AssetId('apps_examples', 'lib/screens/greeter.dart'),
        interpolatedSource,
      );

      await testBuilder(
        const UserFactoryBuilder(BuilderOptions.empty),
        {'apps_examples|lib/screens/greeter.dart': interpolatedSource},
        rootPackage: 'apps_examples',
        readerWriter: interpolatedReaderWriter,
        outputs: {
          'apps_examples|lib/user_factories.g.dart': decodedMatches(
            allOf([
              contains("'TextRich': buildTextRich"),
              contains("'Text': buildText"),
            ]),
          ),
        },
      );

      // The discriminator: a plain `Text` is delivered as itself, so the
      // rich-text entry stays out of a build that never lowers to it.
      final plainReaderWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      plainReaderWriter.testing.writeString(
        AssetId('apps_examples', 'lib/screens/notice.dart'),
        plainSource,
      );

      await testBuilder(
        const UserFactoryBuilder(BuilderOptions.empty),
        {'apps_examples|lib/screens/notice.dart': plainSource},
        rootPackage: 'apps_examples',
        readerWriter: plainReaderWriter,
        outputs: {
          'apps_examples|lib/user_factories.g.dart': decodedMatches(
            allOf([
              contains("'Text': buildText"),
              isNot(contains('TextRich')),
            ]),
          ),
        },
      );
    });

    test('a screen nothing mounts still contributes its widgets', () async {
      // The reserve position: a screen the app never builds is the way to keep
      // a widget renderable over the air before the app itself draws it, so
      // its widgets have to survive into the app-wide vocabulary.
      const homeSource = '''
        import 'package:flutter/material.dart';

        class Home extends StatelessWidget {
          const Home({super.key});

          @override
          Widget build(BuildContext context) => const Text('home');
        }
      ''';
      const reserveSource = '''
        import 'package:flutter/material.dart';
        import 'package:restage/restage.dart';

        @Screen(id: 'reserve')
        class ReserveScreen extends StatelessWidget {
          const ReserveScreen({super.key});

          @override
          Widget build(BuildContext context) =>
              const ExpansionTile(title: Text('more'));
        }
      ''';
      // Nothing else in the package draws it, and nothing builds the screen.
      expect(homeSource, isNot(contains('ExpansionTile')));
      expect(homeSource, isNot(contains('ReserveScreen')));

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      readerWriter.testing
        ..writeString(
          AssetId('apps_examples', 'lib/screens/home.dart'),
          homeSource,
        )
        ..writeString(
          AssetId('apps_examples', 'lib/screens/reserve.dart'),
          reserveSource,
        );

      await testBuilder(
        const UserFactoryBuilder(BuilderOptions.empty),
        {
          'apps_examples|lib/screens/home.dart': homeSource,
          'apps_examples|lib/screens/reserve.dart': reserveSource,
        },
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|lib/user_factories.g.dart': decodedMatches(
            allOf([
              contains("'ExpansionTile': buildExpansionTile"),
              contains("'Text': buildText"),
            ]),
          ),
        },
      );
    });

    test('the derived build reports the vocabulary it derived, once', () async {
      const homeSource = '''
        import 'package:flutter/material.dart';

        class Home extends StatelessWidget {
          const Home({super.key});

          @override
          Widget build(BuildContext context) => const Text('home');
        }
      ''';
      const asideSource = '''
        import 'package:flutter/material.dart';

        class Aside extends StatelessWidget {
          const Aside({super.key});

          @override
          Widget build(BuildContext context) =>
              const Column(children: [Text('aside')]);
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      readerWriter.testing
        ..writeString(
          AssetId('apps_examples', 'lib/screens/home.dart'),
          homeSource,
        )
        ..writeString(
          AssetId('apps_examples', 'lib/screens/aside.dart'),
          asideSource,
        );

      final messages = <String>[];
      await testBuilder(
        _derivedCatalogBuilder,
        {
          'apps_examples|lib/screens/home.dart': homeSource,
          'apps_examples|lib/screens/aside.dart': asideSource,
        },
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        // Not verbose: this is the build a developer runs.
        onLog: (record) => messages.add(record.message),
      );

      // A build record carries the builder and asset on its first line, so the
      // summary is found inside the message rather than at its start.
      final summaries = messages
          .where((message) => message.contains('Restage: a surface'))
          .toList();

      // Two libraries, one summary, and it survives a build with no flags.
      expect(summaries, hasLength(1));
      expect(
        summaries.single,
        allOf([
          contains('render 2 built-in widgets and 0 icons'),
          contains('opted down with catalog: derived'),
          contains('Restage.configureWithInstalledCatalog()'),
          contains('@Screen the app never mounts'),
          contains('drop the option'),
          contains(kAppSizeDocsUrl),
        ]),
      );

      // The per-group costs are longer and stay behind --verbose.
      expect(
        messages.where((message) => message.contains('text entry (TextField')),
        isEmpty,
      );
    });

    test(
        'the default build reports the whole-catalog position and the '
        'opt-down, once', () async {
      const homeSource = '''
        import 'package:flutter/material.dart';

        class Home extends StatelessWidget {
          const Home({super.key});

          @override
          Widget build(BuildContext context) => const Text('home');
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/screens/home.dart'),
        homeSource,
      );

      final messages = <String>[];
      await testBuilder(
        const UserFactoryBuilder(BuilderOptions.empty),
        {'apps_examples|lib/screens/home.dart': homeSource},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        // Verbose, so a per-group cost would be seen if one were logged.
        verbose: true,
        onLog: (record) => messages.add(record.message),
      );

      final summaries = messages
          .where(
            (message) =>
                message.contains('Restage: generated registration includes '
                    'the whole built-in catalog'),
          )
          .toList();
      expect(summaries, hasLength(1));
      expect(
        summaries.single,
        allOf([
          // The count is the whole catalog's, well above the one widget this
          // source draws.
          matches(RegExp(r'all [1-9]\d+ built-in widgets')),
          contains('every built-in icon of both families'),
          contains('catalog: derived'),
          contains('restage_codegen:user_factories'),
          contains('build.yaml'),
          contains(kAppSizeDocsUrl),
        ]),
      );

      // The derived-set summary is the other position's text, so it is absent.
      expect(
        messages.where((message) => message.contains('Restage: a surface')),
        isEmpty,
      );

      // Nothing is missing from the build, so no group costs are logged.
      expect(
        messages.where((message) => message.contains('text entry (TextField')),
        isEmpty,
      );
    });

    test('the derived build per-group costs ride the log --verbose shows',
        () async {
      const homeSource = '''
        import 'package:flutter/material.dart';

        class Home extends StatelessWidget {
          const Home({super.key});

          @override
          Widget build(BuildContext context) => const Text('home');
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/screens/home.dart'),
        homeSource,
      );

      final messages = <String>[];
      await testBuilder(
        _derivedCatalogBuilder,
        {'apps_examples|lib/screens/home.dart': homeSource},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        // Builder messages below a warning reach a log listener only when the
        // build is verbose.
        verbose: true,
        onLog: (record) => messages.add(record.message),
      );

      final groups = messages
          .where((message) => message.contains('text entry (TextField'))
          .toList();
      expect(groups, hasLength(1));
      expect(
        groups.single,
        allOf([
          contains(
            'text entry (TextField, CupertinoTextField, '
            'CupertinoSearchTextField)',
          ),
          contains('backdrop filter (BackdropFilter)'),
        ]),
      );

      // The summary is still there, and is not duplicated.
      expect(
        messages.where((message) => message.contains('Restage: a surface')),
        hasLength(1),
      );
    });

    test('a package whose pubspec does not depend on the SDK emits nothing',
        () async {
      const widgetSource = '''
        import 'package:flutter/widgets.dart';

        class Badge extends StatelessWidget {
          const Badge({super.key});

          @override
          Widget build(BuildContext context) => const SizedBox.shrink();
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
      );
      readerWriter.testing
        ..writeString(
          AssetId('apps_examples', 'lib/widgets/badge.dart'),
          widgetSource,
        )
        ..writeString(
          AssetId('apps_examples', 'pubspec.yaml'),
          'name: acme_catalog\n'
          '\n'
          'dependencies:\n'
          '  flutter:\n'
          '    sdk: flutter\n'
          '  restage_shared: ^2.0.0\n',
        );

      await testBuilder(
        const UserFactoryBuilder(BuilderOptions.empty),
        {'apps_examples|lib/widgets/badge.dart': widgetSource},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: const {},
      );
    });

    test('admitted-then-skipped factory emission is a hard coherence failure',
        () {
      const emittableBeforeFailure = WidgetEntry(
        wireId: WireId.unallocatedWidget,
        name: 'EmittableBeforeFailure',
        library: WidgetLibrary.custom('acme.design_system'),
        category: WidgetCategory.layout,
        description: 'Valid fixture before the malformed entry.',
        flutterType: 'package:acme/widgets.dart#EmittableBeforeFailure',
        childrenSlot: ChildrenSlot.none,
        properties: <PropertyEntry>[],
      );
      const malformedHistorical = WidgetEntry(
        wireId: WireId.unallocatedWidget,
        name: 'MalformedHistorical',
        library: WidgetLibrary.custom('acme.design_system'),
        category: WidgetCategory.layout,
        description: 'Historical malformed fixture.',
        flutterType: 'package:acme/widgets.dart#MalformedHistorical',
        childrenSlot: ChildrenSlot.single,
        properties: <PropertyEntry>[],
      );

      expect(
        () => emitAdmittedUserFactoriesDart(
          const <WidgetEntry>[
            emittableBeforeFailure,
            malformedHistorical,
          ],
        ),
        throwsA(
          isA<StateError>()
              .having(
                (error) => error.message,
                'message',
                allOf(
                  contains('catalog/factory coherence failure'),
                  contains('MalformedHistorical'),
                  contains('package:acme/widgets.dart#MalformedHistorical'),
                  contains('Catalog names default to the Dart class'),
                  contains('shared admission predicate'),
                  contains('No generated output was written'),
                ),
              )
              .having(
                (error) => error.message,
                'manual glue recommendation',
                isNot(contains('hand-written')),
              ),
        ),
      );
    });
  });

  group('pubspecDependsOnRestageSdk', () {
    test('a dependency on the SDK counts', () {
      expect(
        pubspecDependsOnRestageSdk(
          'name: acme_app\n'
          '\n'
          'dependencies:\n'
          '  flutter:\n'
          '    sdk: flutter\n'
          '  restage: ^2.0.0\n',
        ),
        isTrue,
      );
    });

    test('a dev dependency on the SDK counts', () {
      expect(
        pubspecDependsOnRestageSdk(
          'name: acme_catalog\n'
          '\n'
          'dev_dependencies:\n'
          '  restage:\n'
          '    path: ../restage\n',
        ),
        isTrue,
      );
    });

    test('a package naming only neighbouring packages does not', () {
      expect(
        pubspecDependsOnRestageSdk(
          'name: restage_material\n'
          '\n'
          'dependencies:\n'
          '  restage_shared: ^2.0.0\n'
          '  rfw_catalog_schema: ^2.0.0\n'
          '\n'
          'dev_dependencies:\n'
          '  restage_codegen: ^2.0.0\n',
        ),
        isFalse,
      );
    });

    test('the SDK named outside a dependency section does not count', () {
      expect(
        pubspecDependsOnRestageSdk(
          'name: acme_app\n'
          '\n'
          'dependency_overrides:\n'
          '  restage:\n'
          '    path: ../restage\n',
        ),
        isFalse,
      );
    });

    test('a commented-out dependency does not count', () {
      expect(
        pubspecDependsOnRestageSdk(
          'name: acme_app\n'
          '\n'
          'dependencies:\n'
          '  # restage: ^2.0.0\n',
        ),
        isFalse,
      );
    });
  });
}

/// The builder opted down to the set this package's own source draws on.
const _derivedCatalogBuilder = UserFactoryBuilder(
  BuilderOptions({'catalog': 'derived'}),
);

/// [source] with its whitespace removed, so an assertion about an emitted
/// expression survives the formatter's line breaks.
String _packed(String source) => source.replaceAll(RegExp(r'\s+'), '');

/// [matcher] applied to the emitted source with its whitespace removed.
Matcher _packs(Matcher matcher) => isA<String>().having(
      _packed,
      'without whitespace',
      matcher,
    );
