import 'dart:convert';

import 'package:build/build.dart';
import 'package:crypto/crypto.dart';
import 'package:restage_codegen/src/a2ui/user_a2ui_catalog_builder.dart';
import 'package:restage_codegen/src/native_screen_source_index.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import '../index_probe_helpers.dart';

void main() {
  test(
    'no-screen builder path freezes the custom props Dart and JSON bytes',
    () async {
      const source = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageLibrary(
  library: WidgetLibrary.custom('acme.widgets'),
  capabilityVersion: 1,
)
const restageLibrary = 0;

@RestageWidget(
  name: 'LegacyGauge',
  library: WidgetLibrary.custom('acme.widgets'),
  description: 'A legacy no-screen byte probe.',
)
class LegacyGauge extends StatelessWidget {
  const LegacyGauge({super.key, required this.value});

  /// Visible gauge value.
  final double value;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/legacy_gauge.dart'),
        source,
      );

      final result = await testBuilder(
        UserA2uiCatalogBuilder(BuilderOptions.empty),
        const <String, String>{
          'apps_examples|lib/legacy_gauge.dart': source,
        },
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );

      expect(result.succeeded, isTrue);
      final dartBytes = result.readerWriter.testing.readBytes(
        AssetId(
          'apps_examples',
          'lib/generated/restage_a2ui_catalog.g.dart',
        ),
      );
      final jsonBytes = result.readerWriter.testing.readBytes(
        AssetId(
          'apps_examples',
          '.restage/build/a2ui/restage_a2ui_catalog.a2ui.json',
        ),
      );
      expect(
        sha256.convert(dartBytes).toString(),
        '32160f32a33483e923048084dee15d0c36ff406cbfc65b792bcf4d46821baef1',
        reason: 'the custom props Dart artifact must match the emitter',
      );
      expect(
        sha256.convert(jsonBytes).toString(),
        'ea8cb08315a88bf7e3fcac89636ab4dd496b63900303306b997c1c3872c61cb8',
        reason: 'the custom props JSON artifact must remain byte-identical',
      );
    },
  );

  for (final annotation in ['Screen', 'ScreenSource']) {
    test(
      '$annotation rejects a surface-valid ID forbidden as an A2UI component',
      () async {
        final source = _legacyNotice
            .replaceAll('@ScreenSource', '@$annotation')
            .replaceAll('legacy_notice', 'legacy-notice');
        final readerWriter = await readerWriterWithFilesystemSources(
          rootPackage: 'apps_examples',
        );
        readerWriter.testing
          ..writeString(
            AssetId(
              'apps_examples',
              'lib/onboarding/screens/legacy-notice.dart',
            ),
            source,
          )
          ..writeString(
            AssetId('apps_examples', 'pubspec.yaml'),
            _screenSourcePubspec,
          )
          ..writeString(
            AssetId('apps_examples', '.dart_tool/package_graph.json'),
            _screenSourcePackageGraph,
          );
        final logs = <String>[];
        final result = await runWithNativeScreenPackageGraphForTesting(
          packageGraphSource: _screenSourcePackageGraph,
          body: () => testBuilder(
            UserA2uiCatalogBuilder(BuilderOptions.empty),
            {
              'apps_examples|lib/onboarding/screens/legacy-notice.dart': source,
              'apps_examples|pubspec.yaml': _screenSourcePubspec,
            },
            rootPackage: 'apps_examples',
            readerWriter: readerWriter,
            onLog: (record) => logs.add(record.message),
          ),
        );
        expect(result.succeeded, isFalse);
        expect(
          logs.join('\n'),
          allOf(
            contains('legacy-notice'),
            contains('@$annotation(id: ...)'),
            contains('non-reserved A2UI component identifier'),
          ),
        );
        expect(
          result.readerWriter.testing.exists(
            AssetId(
              'apps_examples',
              'lib/generated/restage_a2ui_catalog.g.dart',
            ),
          ),
          isFalse,
        );
      },
    );
  }

  test(
    'ordinary A2UI build emits one exact-ID opaque native screen component',
    () async {
      const source = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/widgetbook.dart' as wb;

part 'restage.generated/opaque_screen.restage.g.dart';

@ScreenSource(id: 'opaque_screen', version: 2)
@wb.Config.values([true])
class OpaqueScreen extends StatelessWidget {
  const OpaqueScreen({
    super.key,
    required this.title,
    this.enabled = true,
  });

  static const continued = SurfaceEvent<String>('continue');

  /// Visible screen title.
  final String title;

  /// Whether continuing is enabled.
  final bool enabled;

  @override
  Widget build(BuildContext context) => Column(
        children: <Widget>[
          Text(title),
          ElevatedButton(
            onPressed: context.surfaceEvent(continued, 'preview'),
            child: const Text('Continue'),
          ),
        ],
      );
}
''';
      const pubspec = '''
name: apps_examples
dependencies:
  flutter: any
  restage: any
  rfw_catalog_schema: any
''';
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      readerWriter.testing
        ..writeString(
          AssetId(
            'apps_examples',
            'lib/onboarding/screens/opaque_screen.dart',
          ),
          source,
        )
        ..writeString(AssetId('apps_examples', 'pubspec.yaml'), pubspec);
      final logs = <String>[];

      final result = await runWithNativeScreenPackageGraphForTesting(
        packageGraphSource: _screenSourcePackageGraph,
        body: () => testBuilder(
          UserA2uiCatalogBuilder(BuilderOptions.empty),
          const <String, String>{
            'apps_examples|lib/onboarding/screens/opaque_screen.dart': source,
            'apps_examples|pubspec.yaml': pubspec,
          },
          rootPackage: 'apps_examples',
          readerWriter: readerWriter,
          flattenOutput: true,
          onLog: (record) => logs.add(record.message),
        ),
      );

      expect(result.succeeded, isTrue, reason: logs.join('\n'));
      final dartId = AssetId(
        'apps_examples',
        'lib/generated/restage_a2ui_catalog.g.dart',
      );
      final stampId = AssetId(
        'apps_examples',
        '.restage/build/a2ui/restage_a2ui_catalog.a2ui.json',
      );
      expect(result.readerWriter.testing.exists(dartId), isTrue);
      expect(result.readerWriter.testing.exists(stampId), isTrue);
      final dart = result.readerWriter.testing.exists(dartId)
          ? utf8.decode(result.readerWriter.testing.readBytes(dartId))
          : '';
      final stampJson = result.readerWriter.testing.exists(stampId)
          ? utf8.decode(result.readerWriter.testing.readBytes(stampId))
          : '';
      final stamp = stampJson.isNotEmpty
          ? jsonDecode(stampJson) as Map<String, Object?>
          : const <String, Object?>{};

      expect(dart, contains("name: 'opaque_screen'"));
      expect(dart, matches(RegExp(r"'props_title':\s*S.combined\(")));
      expect(dart, matches(RegExp(r"'props_enabled':\s*S.combined\(")));
      expect(dart, contains("required: <String>['props_title']"));
      expect(dart, contains('restageProps.value(key)'));
      expect(dart, contains("data['props_title']"));
      expect(dart, contains("data['props_enabled']"));
      expect(dart, contains('OpaqueScreen('));
      expect(dart, contains('RestageEventDispatcher('));
      expect(dart, contains('itemContext.dispatchAction('));
      expect(dart, contains("'name': eventId"));
      expect(dart, contains("'value': value"));
      expect(dart, isNot(contains('Column(')));
      expect(dart, isNot(contains('Text(')));
      expect(dart, isNot(contains('restage.native_screen_source')));
      expect(dart, isNot(contains('WidgetCategory.layout')));
      expect(stampJson, isNot(contains('restage.native_screen_source')));
      expect(stampJson, isNot(contains('"category"')));

      final a2uiCatalog = stamp['a2uiCatalog'] as Map<String, Object?>?;
      expect(
        (a2uiCatalog?['components'] as Map<String, Object?>?)?.keys,
        <String>['opaque_screen'],
      );
      final components = a2uiCatalog?['components'] as Map<String, Object?>?;
      final screenSchema =
          components?['opaque_screen'] as Map<String, Object?>?;
      final screenProperties =
          screenSchema?['properties'] as Map<String, Object?>?;
      expect(screenSchema?['required'], <Object?>['props_title']);
      expect(screenProperties?.keys, <String>['props_title', 'props_enabled']);
      final capability = stamp['restageCapability'] as Map<String, Object?>?;
      expect(capability?['availableLibraries'], isEmpty);
      expect(
        capability?['perItemSinceVersion'],
        <String, Object?>{'opaque_screen': 2},
      );

      expect(
        result.readerWriter.testing.exists(
          AssetId(
            'apps_examples',
            'lib/generated/opaque_screen.a2ui.dart',
          ),
        ),
        isFalse,
      );
    },
  );

  test(
    'A2UI catalogs package-wide canonical screens with implicit and '
    'colocated explicit IDs alongside a legacy screen',
    () async {
      const sources = <String, String>{
        'apps_examples|lib/features/implicit_notice.dart':
            _canonicalImplicitNotice,
        'apps_examples|lib/features/message_bundle.dart':
            _canonicalMessageBundle,
        'apps_examples|lib/onboarding/screens/legacy_notice.dart':
            _legacyNotice,
        'apps_examples|pubspec.yaml': _screenSourcePubspec,
      };
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      for (final source in sources.entries) {
        readerWriter.testing.writeString(
          AssetId.parse(source.key),
          source.value,
        );
      }
      final logs = <String>[];

      final result = await runWithNativeScreenPackageGraphForTesting(
        packageGraphSource: _screenSourcePackageGraph,
        body: () => testBuilder(
          UserA2uiCatalogBuilder(BuilderOptions.empty),
          sources,
          rootPackage: 'apps_examples',
          readerWriter: readerWriter,
          flattenOutput: true,
          onLog: (record) => logs.add(record.message),
        ),
      );

      expect(result.succeeded, isTrue, reason: logs.join('\n'));
      final stamp =
          jsonDecode(
                utf8.decode(
                  result.readerWriter.testing.readBytes(
                    AssetId(
                      'apps_examples',
                      '.restage/build/a2ui/restage_a2ui_catalog.a2ui.json',
                    ),
                  ),
                ),
              )
              as Map<String, Object?>;
      final catalog = stamp['a2uiCatalog']! as Map<String, Object?>;
      final components = catalog['components']! as Map<String, Object?>;
      expect(
        components.keys,
        containsAll(<String>[
          'implicit_notice',
          'stable_first',
          'stable_second',
          'legacy_notice',
        ]),
      );
      final capability = stamp['restageCapability']! as Map<String, Object?>;
      expect(
        capability['perItemSinceVersion'],
        containsPair('implicit_notice', 2),
      );
    },
  );

  for (final decoy in _partDirectiveDecoys.entries) {
    test(
      'A2UI rejects a ${decoy.key} part-directive decoy before empty-index '
      'writes',
      () async {
        final source = _screenWithPartDirectiveDecoy(decoy.value);
        final input = AssetId(
          'apps_examples',
          'lib/onboarding/screens/part_decoy.dart',
        );
        final readerWriter = await readerWriterWithFilesystemSources(
          rootPackage: 'apps_examples',
        );
        readerWriter.testing
          ..writeString(input, source)
          ..writeString(
            AssetId('apps_examples', 'pubspec.yaml'),
            _screenSourcePubspec,
          )
          ..writeString(
            AssetId('apps_examples', '.dart_tool/package_graph.json'),
            _screenSourcePackageGraph,
          );
        final logs = <String>[];

        final result = await runWithNativeScreenPackageGraphForTesting(
          packageGraphSource: _screenSourcePackageGraph,
          body: () => testBuilder(
            UserA2uiCatalogBuilder(BuilderOptions.empty),
            {
              'apps_examples|${input.path}': source,
              'apps_examples|pubspec.yaml': _screenSourcePubspec,
            },
            rootPackage: 'apps_examples',
            readerWriter: readerWriter,
            flattenOutput: true,
            onLog: (record) => logs.add(record.message),
            outputs: const {},
          ),
        );

        expect(result.succeeded, isFalse);
        expect(logs.join('\n'), contains('missingPartDirective'));
        for (final path in const <String>[
          'lib/generated/restage_a2ui_catalog.g.dart',
          '.restage/build/a2ui/restage_a2ui_catalog.a2ui.json',
        ]) {
          expect(
            result.readerWriter.testing.exists(
              AssetId('apps_examples', path),
            ),
            isFalse,
            reason: '$path must not be emitted from an invalid empty index',
          );
        }
      },
    );
  }

  test(
    'A2UI rejects an abstract ScreenSource before generated construction',
    () async {
      const source = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart' as restage;

part 'restage.generated/abstract_screen.restage.g.dart';

@restage.ScreenSource(id: 'abstract_screen')
abstract class AbstractScreen extends StatelessWidget {
  const AbstractScreen({super.key});
}
''';
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      readerWriter.testing
        ..writeString(
          AssetId(
            'apps_examples',
            'lib/onboarding/screens/abstract_screen.dart',
          ),
          source,
        )
        ..writeString(
          AssetId('apps_examples', 'pubspec.yaml'),
          _screenSourcePubspec,
        )
        ..writeString(
          AssetId('apps_examples', '.dart_tool/package_graph.json'),
          _screenSourcePackageGraph,
        );
      final logs = <String>[];

      final result = await runWithNativeScreenPackageGraphForTesting(
        packageGraphSource: _screenSourcePackageGraph,
        body: () => testBuilder(
          UserA2uiCatalogBuilder(BuilderOptions.empty),
          const <String, String>{
            'apps_examples|lib/onboarding/screens/abstract_screen.dart': source,
            'apps_examples|pubspec.yaml': _screenSourcePubspec,
          },
          rootPackage: 'apps_examples',
          readerWriter: readerWriter,
          flattenOutput: true,
          onLog: (record) => logs.add(record.message),
        ),
      );

      expect(result.succeeded, isFalse);
      expect(
        logs.join('\n'),
        allOf(
          contains('has no build() method'),
          contains(
            'lib/onboarding/screens/abstract_screen.dart#AbstractScreen',
          ),
        ),
      );
      expect(
        result.readerWriter.testing.exists(
          AssetId(
            'apps_examples',
            'lib/generated/restage_a2ui_catalog.g.dart',
          ),
        ),
        isFalse,
      );
    },
  );
}

String _screenWithPartDirectiveDecoy(String decoy) =>
    '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

$decoy

@ScreenSource(id: 'part_decoy')
final class PartDecoyScreen extends StatelessWidget {
  const PartDecoyScreen({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

const _partDirectiveDecoys = <String, String>{
  'comment': "// part 'restage.generated/part_decoy.restage.g.dart';",
  'string':
      "const partDirectiveText = \"part 'restage.generated/part_decoy.restage.g.dart';\";",
};

const _canonicalImplicitNotice = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/implicit_notice.restage.g.dart';

@Screen(surface: Surface.general, version: 2)
final class ImplicitNotice extends StatelessWidget {
  const ImplicitNotice({super.key});

  static const continued = SurfaceEvent<String>('continue');

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

const _canonicalMessageBundle = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/message_bundle.restage.g.dart';

@Screen(id: 'stable_first', surface: Surface.message)
final class StableFirst extends StatelessWidget {
  const StableFirst({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

@Screen(id: 'stable_second', surface: Surface.message)
final class StableSecond extends StatelessWidget {
  const StableSecond({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

const _legacyNotice = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/legacy_notice.restage.g.dart';

@ScreenSource(id: 'legacy_notice')
final class LegacyNotice extends StatelessWidget {
  const LegacyNotice({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

const _screenSourcePubspec = '''
name: apps_examples
dependencies:
  flutter: any
  restage: any
  rfw_catalog_schema: any
''';

final String _screenSourcePackageGraph = nativeScreenPackageGraph(
  const {'flutter', 'restage', 'rfw_catalog_schema'},
);
